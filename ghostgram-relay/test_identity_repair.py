import importlib.util
from contextlib import closing
from pathlib import Path
import tempfile
import unittest
from relay import Relay

spec = importlib.util.spec_from_file_location("repair", Path(__file__).parent / "deploy/repair-ios-identity.py")
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class IdentityRepairTests(unittest.TestCase):
    def test_existing_token_is_preserved_and_pair_uses_real_user_id(self):
        root = Path(__file__).parent / ".test-tmp"
        root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as temp:
            path = Path(temp) / "relay.sqlite3"
            relay = Relay(path)
            token = relay.provision("38183889840", "ios")
            other = relay.provision("7059873186", "android")
            relay.allow_pair("38183889840", "7059873186")
            self.assertEqual(repair.repair(path, "38183889840", "8119118768", "7059873186"), 1)
            self.assertEqual(relay.authenticate("Bearer " + token), "8119118768")
            self.assertEqual(relay.authenticate("Bearer " + other), "7059873186")
            self.assertEqual(repair.repair(path, "38183889840", "8119118768", "7059873186"), 0)
            with closing(relay.connect()) as db:
                self.assertEqual(tuple(db.execute("SELECT a,b FROM pairs").fetchone()), ("7059873186", "8119118768"))
            with self.assertRaises(ValueError):
                repair.repair(path, "38183889840", "101", "7059873186")


if __name__ == "__main__":
    unittest.main()
