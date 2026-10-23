"""Update only the dedicated relay, restoring its source if the health check fails."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import time
import urllib.request
import urllib.error


def main():
    if os.name != "posix" or os.geteuid() != 0:
        raise SystemExit("Run as root on the Ubuntu VPS")
    source = Path(__file__).resolve().parent.parent / "relay.py"
    target = Path("/opt/ghostgram-sync/relay.py")
    if not target.is_file():
        raise SystemExit("Existing GhostGram installation not found")
    compile(source.read_text(), str(source), "exec")
    backup = target.with_name("relay.py.before-client-update")
    shutil.copy2(target, backup)
    try:
        target.write_bytes(source.read_bytes())
        shutil.chown(target, user="root", group="ghostgram-sync")
        target.chmod(0o640)
        subprocess.run(["systemctl", "restart", "ghostgram-sync"], check=True)
        for attempt in range(15):
            try:
                with urllib.request.urlopen("http://127.0.0.1:8765/health", timeout=2) as response:
                    assert json.load(response) == {"ok": True}
                request = urllib.request.Request("http://127.0.0.1:8765/v1/me")
                try:
                    urllib.request.urlopen(request, timeout=2)
                    raise RuntimeError("Identity endpoint must require authentication")
                except urllib.error.HTTPError as error:
                    if error.code != 401:
                        raise
                print("Relay updated; health OK; client identity endpoint protected")
                return
            except Exception:
                if attempt == 14:
                    raise
                time.sleep(1)
    except BaseException:
        shutil.copy2(backup, target)
        subprocess.run(["systemctl", "restart", "ghostgram-sync"], check=False)
        raise


if __name__ == "__main__":
    main()
