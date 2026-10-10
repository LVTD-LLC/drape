#!/usr/bin/env python3
"""Create private Debug configuration, without copying the OpenRouter key."""
from pathlib import Path
import secrets

root = Path(__file__).resolve().parents[1]
env = root / '.env'
values = {}
for line in env.read_text().splitlines() if env.exists() else []:
    name, sep, value = line.strip().removeprefix('export ').partition('=')
    if sep:
        values[name.strip()] = value.strip().strip('\"\'')
token = values.get('DRAPE_DEVELOPMENT_TOKEN')
if not token:
    token = secrets.token_urlsafe(32)
    with env.open('a') as output:
        output.write('\nDRAPE_DEVELOPMENT_TOKEN=' + token + '\n')
    env.chmod(0o600)
if len(token) < 32 or not all(c.isalnum() or c in '-_' for c in token):
    raise SystemExit('DRAPE_DEVELOPMENT_TOKEN must be a URL-safe token of at least 32 characters.')
config = root / 'ios/config/Development.local.xcconfig'
config.write_text('// Private development build only. Never distribute this credential.\n'
                  'DRAPE_AI_URL = https:/$()/drape-ai.cr.lvtd.dev/api/v1/\n'
                  'DRAPE_DEVELOPMENT_TOKEN = ' + token + '\n')
config.chmod(0o600)
print('Private Debug configuration prepared. No provider key is included.')
