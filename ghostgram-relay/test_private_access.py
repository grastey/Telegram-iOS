from contextlib import closing
import json
from pathlib import Path
import tempfile
import unittest
import uuid

from relay import APIError, Application, Relay


class PrivateAccessTests(unittest.TestCase):
    def setUp(self):
        (Path(__file__).parent / '.test-tmp').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).parent / '.test-tmp')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'private.db'
        self.relay = Relay(self.path)
        self.a, self.b = '8277161585', '9271733211'
        self.key_a = self.relay.enroll_member(self.a, 'Android tester')
        self.key_b = self.relay.enroll_member(self.b, 'iPhone tester')

    def gift(self, recipient):
        return dict(client_id=str(uuid.uuid4()), recipient=recipient,
                    gift={'kind': 'regular', 'id': '5170145012310081615'}, comment='Private test')

    def identity(self, token):
        result = []
        body = b''.join(Application(self.relay)({'PATH_INFO': '/v1/me', 'REQUEST_METHOD': 'GET',
            'HTTP_AUTHORIZATION': 'Bearer ' + token}, lambda status, headers: result.append(status)))
        return result[0], json.loads(body)

    def test_private_members_exchange_without_pair_and_separate_histories(self):
        self.assertEqual(self.identity(self.key_a), ('200 OK', {'account': self.a, 'protocol': 1, 'private_access': True}))
        self.assertEqual(len(self.key_a), 64)
        self.assertNotEqual(self.key_a, self.key_b)
        self.assertEqual(self.relay.authenticate('Bearer ' + self.key_a), self.a)
        event, _ = self.relay.send(self.a, self.gift(self.b))
        self.assertEqual(self.relay.poll(self.b, 0)['events'][0]['event_id'], event['event_id'])
        third = '1870276281'
        self.relay.enroll_member(third)
        self.assertEqual(self.relay.poll(third, 0)['events'], [])
        self.assertEqual(self.relay.send(self.b, self.gift(self.a))[0]['sender'], self.b)
        with closing(self.relay.connect()) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pairs').fetchone()[0], 0)
            self.assertNotIn(self.key_a, self.path.read_bytes().decode('latin1'))

    def test_revocation_disables_all_devices_and_legacy_pair_cannot_bypass(self):
        other = self.relay.provision(self.a, 'ios')
        self.relay.allow_pair(self.a, self.b)
        self.relay.disable_member(self.a)
        for key in (self.key_a, other):
            self.assertEqual(self.identity(key)[0], '401 Unauthorized')
        for sender, recipient in ((self.a, self.b), (self.b, self.a)):
            with self.assertRaises(APIError) as error:
                self.relay.send(sender, self.gift(recipient))
            self.assertEqual(error.exception.code, 'private_member_required')
        # Legacy device issuance must not silently undo account revocation.
        legacy = self.relay.provision(self.a, 'android')
        self.assertEqual(self.identity(legacy)[0], '403 Forbidden')
        replacement = self.relay.enroll_member(self.a)
        self.assertEqual(self.identity(replacement)[0], '200 OK')
        self.assertEqual(self.identity(self.key_a)[0], '401 Unauthorized')

    def test_code_never_authorizes_a_client_selected_sender(self):
        self.assertEqual(self.identity(self.key_a)[1]['account'], self.a)
        body = self.gift(self.b)
        body['sender'] = self.b
        with self.assertRaises(APIError):
            self.relay.send(self.a, body)
        legacy = self.relay.provision('999', 'android')
        self.assertNotIn('private_access', self.identity(legacy)[1])
        self.relay.allow_pair(self.a, '999')
        with self.assertRaises(APIError):
            self.relay.send(self.a, self.gift('999'))

    def test_expiry_and_membership_validation(self):
        with self.assertRaises(ValueError):
            self.relay.enroll_member(self.a, days=0)
        with closing(self.relay.connect()) as db:
            import hashlib
            db.execute('UPDATE devices SET expires=0 WHERE token_hash=?', (hashlib.sha256(self.key_a.encode()).hexdigest(),))
        self.assertEqual(self.identity(self.key_a)[0], '401 Unauthorized')

    def test_schema_upgrade_keeps_old_keys_events_and_pairs(self):
        # Simulate a legacy database that has keys/events/pairs but no membership table.
        event, _ = self.relay.send(self.a, self.gift(self.b))
        self.relay.allow_pair(self.a, self.b)
        with closing(self.relay.connect()) as db:
            db.execute('DROP TABLE private_members')
        reopened = Relay(self.path)
        self.assertEqual(reopened.authenticate('Bearer ' + self.key_b), self.b)
        self.assertFalse(reopened.private_member(self.a))
        self.assertEqual(reopened.poll(self.b, 0)['events'][0]['event_id'], event['event_id'])
        with closing(reopened.connect()) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pairs').fetchone()[0], 1)
