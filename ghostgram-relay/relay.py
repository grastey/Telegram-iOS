"""Private beta relay for synthetic gifts. No Telegram credentials or payment APIs."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from urllib.parse import parse_qs
import uuid


class APIError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def account_id(value):
    # Telegram user IDs are decimal strings across platforms, never floating point.
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]{0,15}", value):
        raise APIError(400, "invalid_account")
    return value


class Relay:
    def __init__(self, path):
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS devices (
                    token_hash TEXT PRIMARY KEY, account TEXT NOT NULL,
                    platform TEXT NOT NULL, expires INTEGER NOT NULL,
                    revoked INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS pairs (
                    a TEXT NOT NULL, b TEXT NOT NULL, PRIMARY KEY(a,b)
                );
                CREATE TABLE IF NOT EXISTS events (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT NOT NULL UNIQUE, client_id TEXT NOT NULL,
                    sender TEXT NOT NULL, recipient TEXT NOT NULL,
                    gift TEXT NOT NULL, comment TEXT NOT NULL,
                    created INTEGER NOT NULL, UNIQUE(sender,client_id)
                );
                CREATE INDEX IF NOT EXISTS incoming ON events(recipient,seq);
                CREATE INDEX IF NOT EXISTS outgoing ON events(sender,seq);
                CREATE INDEX IF NOT EXISTS rate_window ON events(sender,created);
            """)

    def connect(self):
        db = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        db.row_factory = sqlite3.Row
        return db

    def provision(self, account, platform, lifetime=30 * 86400):
        account_id(account)
        if platform not in ("ios", "android", "test"):
            raise ValueError("Unsupported platform")
        token = secrets.token_urlsafe(32)
        with closing(self.connect()) as db:
            db.execute("INSERT INTO devices VALUES (?,?,?,?,0)", (
                hashlib.sha256(token.encode()).hexdigest(), account, platform,
                int(time.time()) + lifetime,
            ))
        return token

    def allow_pair(self, a, b):
        a, b = sorted((account_id(a), account_id(b)))
        if a == b:
            raise ValueError("Use two distinct accounts")
        with closing(self.connect()) as db:
            db.execute("INSERT OR IGNORE INTO pairs VALUES (?,?)", (a, b))

    def revoke(self, token):
        with closing(self.connect()) as db:
            db.execute("UPDATE devices SET revoked=1 WHERE token_hash=?", (
                hashlib.sha256(token.encode()).hexdigest(),
            ))

    def authenticate(self, header):
        if not header.startswith("Bearer ") or len(header) > 200:
            raise APIError(401, "unauthorized")
        digest = hashlib.sha256(header[7:].encode()).hexdigest()
        with closing(self.connect()) as db:
            row = db.execute("SELECT account FROM devices WHERE token_hash=? AND revoked=0 AND expires>?",
                             (digest, int(time.time()))).fetchone()
        if row is None:
            raise APIError(401, "unauthorized")
        return row["account"]

    @staticmethod
    def event(row):
        return dict(seq=row["seq"], event_id=row["event_id"], client_id=row["client_id"],
                    sender=row["sender"], recipient=row["recipient"], gift=json.loads(row["gift"]),
                    comment=row["comment"], created=row["created"], synthetic=True)

    def send(self, sender, body):
        if not isinstance(body, dict) or set(body) != {"client_id", "recipient", "gift", "comment"}:
            raise APIError(400, "invalid_fields")
        recipient = account_id(body["recipient"])
        try:
            client_id = str(uuid.UUID(body["client_id"]))
        except (ValueError, TypeError, AttributeError):
            raise APIError(400, "invalid_client_id")
        comment = body["comment"]
        if not isinstance(comment, str) or len(comment.encode("utf-8")) > 4096 or len(comment) > 1024:
            raise APIError(400, "invalid_comment")
        gift = body["gift"]
        if not isinstance(gift, dict):
            raise APIError(400, "invalid_gift")
        if gift.get("kind") == "regular":
            valid = set(gift) == {"kind", "id"} and isinstance(gift["id"], str) and re.fullmatch(r"[1-9][0-9]{0,18}", gift["id"])
        elif gift.get("kind") == "collectible":
            valid = set(gift) == {"kind", "slug"} and isinstance(gift["slug"], str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,80}-[1-9][0-9]{0,18}", gift["slug"])
        else:
            valid = False
        if not valid:
            raise APIError(400, "invalid_gift")
        payload = json.dumps(gift, sort_keys=True, separators=(",", ":"))
        with closing(self.connect()) as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                pair = tuple(sorted((sender, recipient)))
                if not db.execute("SELECT 1 FROM pairs WHERE a=? AND b=?", pair).fetchone():
                    raise APIError(403, "pair_not_enabled")
                if not db.execute("SELECT 1 FROM devices WHERE account=? AND revoked=0 AND expires>?",
                                  (recipient, int(time.time()))).fetchone():
                    raise APIError(409, "recipient_not_connected")
                row = db.execute("SELECT * FROM events WHERE sender=? AND client_id=?", (sender, client_id)).fetchone()
                if row:
                    if (row["recipient"], row["gift"], row["comment"]) != (recipient, payload, comment):
                        raise APIError(409, "idempotency_conflict")
                    db.commit()
                    return self.event(row), False
                now = int(time.time())
                count = db.execute("SELECT COUNT(*) FROM events WHERE sender=? AND created>=?", (sender, now - 60)).fetchone()[0]
                if count >= 30:
                    raise APIError(429, "rate_limited")
                cursor = db.execute("INSERT INTO events(event_id,client_id,sender,recipient,gift,comment,created) VALUES (?,?,?,?,?,?,?)",
                                    (str(uuid.uuid4()), client_id, sender, recipient, payload, comment, now))
                row = db.execute("SELECT * FROM events WHERE seq=?", (cursor.lastrowid,)).fetchone()
                db.commit()
                return self.event(row), True
            except Exception:
                db.rollback()
                raise

    def poll(self, account, after):
        with closing(self.connect()) as db:
            rows = db.execute("SELECT * FROM events WHERE seq>? AND (sender=? OR recipient=?) ORDER BY seq LIMIT 101",
                              (after, account, account)).fetchall()
        page = rows[:100]
        return dict(events=[self.event(row) for row in page],
                    cursor=page[-1]["seq"] if page else after, has_more=len(rows) > 100)


class Application:
    def __init__(self, relay):
        self.relay = relay

    def __call__(self, env, start_response):
        try:
            path, method = env.get("PATH_INFO"), env.get("REQUEST_METHOD")
            status = 200
            if path == "/health" and method == "GET":
                result = {"ok": True}
            else:
                account = self.relay.authenticate(env.get("HTTP_AUTHORIZATION", ""))
                if path == "/v1/me" and method == "GET":
                    result = {"account": account, "protocol": 1}
                elif path == "/v1/gifts" and method == "POST":
                    if env.get("CONTENT_TYPE", "").split(";", 1)[0] != "application/json":
                        raise APIError(415, "json_required")
                    try:
                        length = int(env.get("CONTENT_LENGTH", "0"))
                    except ValueError:
                        raise APIError(400, "invalid_length")
                    if not 0 < length <= 8192:
                        raise APIError(413, "body_too_large")
                    try:
                        body = json.loads(env["wsgi.input"].read(length))
                    except (ValueError, UnicodeError):
                        raise APIError(400, "invalid_json")
                    result, created = self.relay.send(account, body)
                    status = 201 if created else 200
                elif path == "/v1/events" and method == "GET":
                    query = parse_qs(env.get("QUERY_STRING", ""), keep_blank_values=True)
                    if set(query) - {"after"} or len(query.get("after", ["0"])) != 1:
                        raise APIError(400, "invalid_cursor")
                    value = query.get("after", ["0"])[0]
                    if not re.fullmatch(r"[0-9]{1,18}", value):
                        raise APIError(400, "invalid_cursor")
                    result = self.relay.poll(account, int(value))
                else:
                    raise APIError(404, "not_found")
        except APIError as error:
            status, result = error.status, {"error": error.code}
        except sqlite3.OperationalError:
            status, result = 503, {"error": "temporarily_unavailable"}
        data = json.dumps(result, ensure_ascii=False).encode("utf-8")
        reasons = {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                   404: "Not Found", 409: "Conflict", 413: "Payload Too Large", 415: "Unsupported Media Type",
                   429: "Too Many Requests", 503: "Service Unavailable"}
        start_response(f"{status} {reasons[status]}", [("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(data))), ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff")])
        return [data]


def create_app():
    return Application(Relay(os.environ.get("GHOSTGRAM_DB", "data/relay.sqlite3")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="data/relay.sqlite3")
    commands = parser.add_subparsers(dest="command", required=True)
    provision = commands.add_parser("device")
    provision.add_argument("account")
    provision.add_argument("platform", choices=["ios", "android"])
    pair = commands.add_parser("pair")
    pair.add_argument("a")
    pair.add_argument("b")
    commands.add_parser("serve-local")
    args = parser.parse_args()
    relay = Relay(args.db)
    if args.command == "device":
        # Only the trusted server operator can provision devices in this private beta.
        print(relay.provision(args.account, args.platform))
    elif args.command == "pair":
        relay.allow_pair(args.a, args.b)
        print("Pair enabled")
    else:
        from wsgiref.simple_server import make_server
        with make_server("127.0.0.1", 8765, Application(relay)) as server:
            server.serve_forever()
