"""Repair the beta's packed-Postbox-ID enrollment without changing any key."""
import argparse
from pathlib import Path
import sqlite3


def repair(path, packed, raw, android):
    if min(int(packed), int(raw), int(android)) <= 0:
        raise ValueError("Invalid account ID")
    expected = (int(raw) & 0xffffffff) | ((int(raw) >> 32) << 35)
    if expected != int(packed) or packed == raw:
        raise ValueError("These IDs do not describe the same CloudUser")
    if not Path(path).is_file():
        raise ValueError("Existing relay database not found")
    db = sqlite3.connect(path, timeout=5, isolation_level=None)
    try:
        db.execute("BEGIN IMMEDIATE")
        count = db.execute("UPDATE devices SET account=? WHERE account=? AND platform='ios'", (raw, packed)).rowcount
        db.execute("INSERT OR IGNORE INTO pairs VALUES (?,?)", tuple(sorted((raw, android))))
        db.execute("DELETE FROM pairs WHERE a=? AND b=?", tuple(sorted((packed, android))))
        db.execute("COMMIT")
        return count
    except BaseException:
        if db.in_transaction:
            db.execute("ROLLBACK")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="/var/lib/ghostgram-sync/relay.sqlite3")
    args = parser.parse_args()
    count = repair(args.db, "38183889840", "8119118768", "7059873186")
    print("iOS Telegram ID corrected; existing keys preserved; devices updated:", count)
