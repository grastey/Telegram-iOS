from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import io
import json
from pathlib import Path
import tempfile
import unittest
import uuid

from relay import Application, Relay


class RelayTests(unittest.TestCase):
    def setUp(self):
        test_root = Path(__file__).parent / ".test-tmp"
        test_root.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=test_root)
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / "relay.sqlite3"
        self.relay = Relay(self.db)
        self.app = Application(self.relay)
        self.android = self.relay.provision("101", "android")
        self.iphone = self.relay.provision("202", "ios")
        self.third = self.relay.provision("303", "test")
        self.relay.allow_pair("101", "202")

    def request(self, method, path, token=None, body=None, query=""):
        raw = json.dumps(body, ensure_ascii=False).encode() if body is not None else b""
        env = dict(REQUEST_METHOD=method, PATH_INFO=path, QUERY_STRING=query,
                   CONTENT_TYPE="application/json", CONTENT_LENGTH=str(len(raw)),
                   **{"wsgi.input": io.BytesIO(raw)})
        if token:
            env["HTTP_AUTHORIZATION"] = "Bearer " + token
        response = []
        data = b"".join(self.app(env, lambda status, headers: response.append((status, headers))))
        return int(response[0][0].split()[0]), json.loads(data)

    def gift(self, collectible=False):
        return dict(client_id=str(uuid.uuid4()), recipient="202", comment="Подарунок для тебе 🎁\nПривет!",
                    gift={"kind": "collectible", "slug": "LibertyFigure-21114"} if collectible
                    else {"kind": "regular", "id": "5170145012310081615"})

    def test_android_to_ios_preserves_comment_and_gift_after_restart(self):
        for collectible in (False, True):
            body = self.gift(collectible)
            status, sent = self.request("POST", "/v1/gifts", self.android, body)
            self.assertEqual(status, 201)
            self.app = Application(Relay(self.db))
            status, received = self.request("GET", "/v1/events", self.iphone)
            self.assertEqual(status, 200)
            event = received["events"][-1]
            self.assertEqual(event["comment"], body["comment"])
            self.assertEqual(event["gift"], body["gift"])
            self.assertEqual(event["sender"], "101")
            self.assertEqual(event["event_id"], sent["event_id"])
            self.assertTrue(event["synthetic"])

    def test_reply_and_second_device_same_account(self):
        self.request("POST", "/v1/gifts", self.android, self.gift())
        second = self.relay.provision("202", "android")
        self.assertEqual(len(self.request("GET", "/v1/events", second)[1]["events"]), 1)
        reply = self.gift(True)
        reply["recipient"] = "101"
        self.assertEqual(self.request("POST", "/v1/gifts", self.iphone, reply)[0], 201)
        self.assertEqual(len(self.request("GET", "/v1/events", self.android)[1]["events"]), 2)

    def test_private_history_and_pair_enrollment(self):
        self.request("POST", "/v1/gifts", self.android, self.gift())
        self.assertEqual(self.request("GET", "/v1/events", self.third)[1]["events"], [])
        body = self.gift()
        body["recipient"] = "303"
        self.assertEqual(self.request("POST", "/v1/gifts", self.android, body)[0], 403)
        self.assertEqual(self.request("GET", "/v1/events")[0], 401)
        self.assertEqual(self.request("GET", "/v1/events", "wrong")[0], 401)

    def test_no_sender_impersonation_or_arbitrary_catalog_urls(self):
        body = self.gift()
        body["sender"] = "202"
        self.assertEqual(self.request("POST", "/v1/gifts", self.android, body)[0], 400)
        body = self.gift(True)
        body["gift"]["slug"] = "https://evil.invalid/payload"
        self.assertEqual(self.request("POST", "/v1/gifts", self.android, body)[0], 400)

    def test_concurrent_retries_only_create_one_event(self):
        body = self.gift()
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: self.request("POST", "/v1/gifts", self.android, body), range(8)))
        self.assertEqual(sum(status == 201 for status, _ in results), 1)
        self.assertEqual(len({event["event_id"] for _, event in results}), 1)
        self.assertEqual(len(self.request("GET", "/v1/events", self.iphone)[1]["events"]), 1)
        body["comment"] = "changed"
        self.assertEqual(self.request("POST", "/v1/gifts", self.android, body)[0], 409)

    def test_revoked_and_expired_tokens(self):
        self.relay.revoke(self.android)
        self.assertEqual(self.request("GET", "/v1/events", self.android)[0], 401)
        expired = self.relay.provision("101", "test", lifetime=-1)
        self.assertEqual(self.request("GET", "/v1/events", expired)[0], 401)

    def test_session_identity_cannot_be_chosen_by_client(self):
        self.assertEqual(self.request("GET", "/v1/me", self.android),
                         (200, {"account": "101", "protocol": 1}))
        self.assertEqual(self.request("GET", "/v1/me", self.iphone)[1]["account"], "202")
        self.assertEqual(self.request("GET", "/v1/me")[0], 401)

    def test_cursor_and_empty_comment(self):
        body = self.gift()
        body["comment"] = ""
        event = self.request("POST", "/v1/gifts", self.android, body)[1]
        received = self.request("GET", "/v1/events", self.iphone)[1]
        self.assertEqual(received["events"][0]["comment"], "")
        self.assertEqual(self.request("GET", "/v1/events", self.iphone,
                                      query="after=" + str(event["seq"]))[1]["events"], [])
        self.assertEqual(self.request("GET", "/v1/events", self.iphone, query="after=-1")[0], 400)

    def test_comment_limit_and_rate_limit(self):
        body = self.gift()
        body["comment"] = "x" * 1025
        self.assertEqual(self.request("POST", "/v1/gifts", self.android, body)[0], 400)
        for _ in range(30):
            self.assertEqual(self.request("POST", "/v1/gifts", self.android, self.gift())[0], 201)
        self.assertEqual(self.request("POST", "/v1/gifts", self.android, self.gift())[0], 429)

    def test_plaintext_device_secrets_not_in_database(self):
        with closing(self.relay.connect()) as db:
            hashes = [row[0] for row in db.execute("SELECT token_hash FROM devices")]
        self.assertNotIn(self.android, hashes)
        self.assertTrue(all(len(value) == 64 for value in hashes))


if __name__ == "__main__":
    unittest.main()
