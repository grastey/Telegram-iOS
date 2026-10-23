"""Prepare the pinned official Android tree for unsigned private-beta validation."""
import argparse
import copy
import json
import os
from pathlib import Path
import re


def prepare(root, api_id, api_hash):
    if not re.fullmatch(r"[1-9][0-9]{0,10}", api_id) or not re.fullmatch(r"[0-9a-fA-F]{32}", api_hash):
        raise ValueError("Set TELEGRAM_API_ID and TELEGRAM_API_HASH repository secrets")
    props = root / "gradle.properties"
    value = props.read_text()
    value = re.sub(r"(?m)^APP_PACKAGE=.*$", "APP_PACKAGE=dev.grastey.ghostgram", value)
    value = re.sub(r"(?m)^org.gradle.jvmargs=.*$", "org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g", value)
    props.write_text(value)
    build_vars = root / "TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java"
    value = build_vars.read_text()
    for pattern, replacement in [
        (r"public static int APP_ID = .*?;", "public static int APP_ID = " + api_id + ";"),
        (r'public static String APP_HASH = ".*?";', 'public static String APP_HASH = "' + api_hash + '";'),
        (r"public static boolean CHECK_UPDATES = .*?;", "public static boolean CHECK_UPDATES = false;"),
        (r"public static boolean SUPPORTS_PASSKEYS = .*?;", "public static boolean SUPPORTS_PASSKEYS = false;"),
        (r"public static boolean IS_BILLING_UNAVAILABLE = .*?;", "public static boolean IS_BILLING_UNAVAILABLE = true;"),
        (r'public static String SAFETYNET_KEY = ".*?";', 'public static String SAFETYNET_KEY = "";'),
        (r'public static String GOOGLE_AUTH_CLIENT_ID = ".*?";', 'public static String GOOGLE_AUTH_CLIENT_ID = "";'),
    ]:
        value, count = re.subn(pattern, lambda _: replacement, value, count=1)
        if count != 1:
            raise ValueError("Pinned upstream BuildVars format changed")
    build_vars.write_text(value)
    app = root / "TMessagesProj_AppStandalone/build.gradle"
    value = app.read_text()
    value = re.sub(r"(?m)^\s*signingConfig signingConfigs\.(debug|release)\s*$", "", value)
    value = re.sub(r'abiFilters[^\n]+', 'abiFilters "arm64-v8a"', value)
    app.write_text(value)
    library = root / "TMessagesProj/build.gradle"
    value = re.sub(r'abiFilters[^\n]+', 'abiFilters "arm64-v8a"', library.read_text())
    library.write_text(value)
    # These are upstream's public dummy Firebase values, not a connection to our relay.
    # Add fork package entries so google-services resource generation can run.
    for path in root.glob("TMessagesProj*/**/google-services.json"):
        if "build/" in path.as_posix():
            continue
        config = json.loads(path.read_text())
        clients = config.get("client", [])
        if not clients:
            continue
        for package in ("dev.grastey.ghostgram", "dev.grastey.ghostgram.web"):
            entry = copy.deepcopy(clients[0])
            entry.setdefault("client_info", {}).setdefault("android_client_info", {})["package_name"] = package
            config["client"].append(entry)
        path.write_text(json.dumps(config))
    values = root / "TMessagesProj_AppStandalone/src/main/res/values/ghostgram.xml"
    values.parent.mkdir(parents=True, exist_ok=True)
    values.write_text('<resources><string name="AppName">GhostGram</string><string name="AppNameBeta">GhostGram</string></resources>')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    prepare(args.root, os.environ.get("TELEGRAM_API_ID", ""), os.environ.get("TELEGRAM_API_HASH", ""))
    print("Prepared Android private beta sources. Signing is disabled; no private key is needed for validation.")
