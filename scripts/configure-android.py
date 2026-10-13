#!/usr/bin/env python3
"""Copy only private gateway configuration into the ignored Android debug config."""
from pathlib import Path
import re
from urllib.parse import urlparse

root = Path(__file__).resolve().parent.parent
source = root / "ios/config/Development.local.xcconfig"
if not source.exists():
    raise SystemExit("Configure private development access with configure-development.py first.")
values = dict(re.findall(r"^\s*(\w+)\s*=\s*(.*?)\s*$", source.read_text(), re.M))
url = values.get("DRAPE_AI_URL", "").replace("$()", "")
token = values.get("DRAPE_DEVELOPMENT_TOKEN", "")
if urlparse(url).scheme != "https" or not urlparse(url).hostname or not token:
    raise SystemExit("The existing private gateway configuration is incomplete.")
if any(char in url + token for char in "\r\n"):
    raise SystemExit("Invalid gateway configuration.")
# Escape Java Properties syntax without exposing the credential in logs.
escape = lambda value: value.replace("\\", "\\\\").replace(" ", "\\ ")
destination = root / "android/development.properties"
destination.touch(mode=0o600, exist_ok=True)
destination.chmod(0o600)
destination.write_text(f"ai.url={escape(url)}\nai.token={escape(token)}\n")
print("Configured private Android debug gateway access. Release access remains disabled.")
