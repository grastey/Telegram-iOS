#!/bin/bash
set -euo pipefail
OUT="$RUNNER_TEMP/admission-preview"
APP="$OUT/AdmissionPreview.app"
mkdir -p "$APP" "$OUT/frames"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun swiftc -swift-version 5 -sdk "$SDK" -target "$ARCH-apple-ios15.0-simulator" \
  submodules/TelegramUI/Sources/GhostGramPrivateAccess.swift demo-tests/AdmissionPreview.swift \
  -framework UIKit -framework Foundation -o "$APP/AdmissionPreview"
python3 - "$APP/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='dev.grastey.AdmissionPreview', CFBundleExecutable='AdmissionPreview',
        CFBundleName='AdmissionPreview', CFBundleVersion='1', CFBundleShortVersionString='1.0',
        CFBundlePackageType='APPL', LSRequiresIPhoneOS=True, UILaunchScreen={},
        UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait']), f)
PY
codesign --force --sign - "$APP"
UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime,rows in d["devices"].items() if "iOS" in runtime for x in rows if x["name"].startswith("iPhone")))')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl io "$UDID" recordVideo --codec=h264 "$OUT/admission.mov" >"$OUT/record.log" 2>&1 &
REC=$!
trap 'kill -INT "$REC" 2>/dev/null || true' EXIT
for i in $(seq 1 100); do if grep -q 'Recording started' "$OUT/record.log"; then break; fi; sleep .1; done
xcrun simctl launch "$UDID" dev.grastey.AdmissionPreview
sleep 1
xcrun simctl io "$UDID" screenshot "$OUT/01-gate.png"
sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/02-invalid.png"
sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/03-approved.png"
sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/04-wrong-account.png"
sleep 4
kill -INT "$REC"
wait "$REC" || true
trap - EXIT
DATA=$(xcrun simctl get_app_container "$UDID" dev.grastey.AdmissionPreview data)
cp "$DATA/Documents/admission-qa.json" "$OUT/"
python3 - "$OUT/admission-qa.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1])); print(data)
assert len(data)==5 and all(data.values()), data
PY
if ! command -v ffmpeg >/dev/null; then brew install ffmpeg; fi
python3 -m pip install --quiet pillow numpy --break-system-packages
python3 tools/animation_sheet.py "$OUT/admission.mov" "$OUT/frames" --start 0 --tile-width 200 --columns 6 --rows 4
