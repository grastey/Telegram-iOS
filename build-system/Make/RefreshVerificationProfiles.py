"""Refresh only Telegram's PUBLIC, self-signed verification profiles for CI.

The resulting IPA is intermediate build output, not Apple-signed installable output.
Installation still requires the owner's own signing workflow. Never use this for
Apple-issued development/distribution profiles or private signing credentials.
"""
import argparse
import copy
import datetime
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'build-system/fake-codesigning'
PUBLIC_CERT_SHA256 = 'eccdeb43dd50f4abdadf0dc6204c314298c16005567fcbf5d0a20a5761a93ba4'
IDENTITY = 'Apple Distribution: Telegram FZ-LLC (C67CF9S4VU)'
# The bundled PUBLIC self-signed certificate expires 2030-10-29 17:33:19 UTC.
CERTIFICATE_LIMIT = datetime.datetime(2030, 10, 28)


def refreshed_profile(profile, now):
    # XML plist dates and macOS CMS round trips have whole-second precision.
    now = now.replace(microsecond=0)
    certificates = profile.get('DeveloperCertificates', [])
    if len(certificates) != 1 or hashlib.sha256(certificates[0]).hexdigest() != PUBLIC_CERT_SHA256:
        raise ValueError('Refusing to modify anything except the pinned public verification certificate.')
    identifier = profile.get('Entitlements', {}).get('application-identifier', '')
    if not identifier.startswith('C67CF9S4VU.ph.telegra.Telegraph'):
        raise ValueError('Unexpected verification profile application identifier.')
    if now >= CERTIFICATE_LIMIT:
        raise ValueError('The bundled verification certificate must be replaced before another build.')
    result = copy.deepcopy(profile)
    result['CreationDate'] = now - datetime.timedelta(minutes=5)
    result['ExpirationDate'] = min(now + datetime.timedelta(days=365), CERTIFICATE_LIMIT)
    result['TimeToLive'] = max(1, (result['ExpirationDate'] - result['CreationDate']).days)
    result.pop('DER-Encoded-Profile', None)
    return result


def run(*args):
    return subprocess.check_output(args)


def refresh(destination):
    if sys.platform != 'darwin':
        raise RuntimeError('CMS signing requires macOS security; run --self-test on other platforms.')
    cert = (SOURCE / 'certs/Public.cer').read_bytes()
    if hashlib.sha256(cert).hexdigest() != PUBLIC_CERT_SHA256:
        raise ValueError('The bundled public verification certificate changed; review it first.')
    destination = destination.resolve()
    if destination == SOURCE.resolve() or SOURCE.resolve() in destination.parents:
        raise ValueError('Use a separate CI output directory; never overwrite source profiles.')
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copytree(SOURCE / 'certs', destination / 'certs')
    (destination / 'profiles').mkdir()
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    sources = sorted((SOURCE / 'profiles').glob('*.mobileprovision'))
    if not sources:
        raise ValueError('No verification profiles found.')
    with tempfile.TemporaryDirectory(prefix='verification-profiles-') as scratch:
        for source in sources:
            original = plistlib.loads(run('/usr/bin/security', 'cms', '-D', '-i', str(source)))
            updated = refreshed_profile(original, now)
            plist = Path(scratch) / (source.stem + '.plist')
            plist.write_bytes(plistlib.dumps(updated, fmt=plistlib.FMT_XML))
            output = destination / 'profiles' / source.name
            # ImportCertificates.py already imported this public identity into temp.keychain.
            run('/usr/bin/security', 'cms', '-S', '-k', 'temp.keychain', '-N', IDENTITY,
                '-i', str(plist), '-o', str(output))
            decoded = plistlib.loads(run('/usr/bin/security', 'cms', '-D', '-i', str(output)))
            if decoded != updated:
                changed_keys = sorted(key for key in set(decoded) | set(updated) if decoded.get(key) != updated.get(key))
                raise RuntimeError('CMS round trip failed for ' + source.name + ': ' + ', '.join(changed_keys))
            if decoded['Entitlements'] != original['Entitlements']:
                raise RuntimeError('Entitlements must never change.')
            print(source.name + ': public build-only profile valid through ' + decoded['ExpirationDate'].isoformat())
    print('Prepared {} public verification profiles. IPA still requires personal re-signing.'.format(len(sources)))


def self_test():
    cert = (SOURCE / 'certs/Public.cer').read_bytes()
    now = datetime.datetime(2026, 11, 6)
    fixture = {
        'DeveloperCertificates': [cert],
        'Entitlements': {'application-identifier': 'C67CF9S4VU.ph.telegra.Telegraph', 'aps-environment': 'production'},
        'ExpirationDate': datetime.datetime(2026, 10, 30),
        'UUID': 'fixture', 'DER-Encoded-Profile': b'old-signature',
    }
    before = copy.deepcopy(fixture)
    updated = refreshed_profile(fixture, now)
    assert fixture == before
    assert updated['Entitlements'] == before['Entitlements']
    assert updated['DeveloperCertificates'] == before['DeveloperCertificates']
    assert updated['UUID'] == before['UUID']
    assert 'DER-Encoded-Profile' not in updated
    assert updated['CreationDate'] < now < updated['ExpirationDate']
    assert updated['ExpirationDate'] == now + datetime.timedelta(days=365)
    assert plistlib.loads(plistlib.dumps(updated)) == updated
    precise = refreshed_profile(fixture, now.replace(microsecond=123456))
    assert plistlib.loads(plistlib.dumps(precise)) == precise
    assert refreshed_profile(fixture, datetime.datetime(2030, 10, 1))['ExpirationDate'] == CERTIFICATE_LIMIT
    for invalid, date in [(dict(fixture, DeveloperCertificates=[b'unrelated']), now),
                          (dict(fixture, Entitlements={'application-identifier': 'OTHER.app'}), now),
                          (fixture, CERTIFICATE_LIMIT)]:
        try:
            refreshed_profile(invalid, date)
        except ValueError:
            pass
        else:
            raise AssertionError('Unexpected profile/certificate was accepted')
    print('PASS: pinned public certificate, expiry bounds, unchanged entitlements, rejected unrelated profiles, plist round trip')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.destination:
        refresh(args.destination)
    else:
        parser.error('Choose --self-test or --destination')
