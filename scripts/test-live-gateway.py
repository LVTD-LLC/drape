#!/usr/bin/env python3
"""Opt-in paid check through the actual iOS URLSession client and synthetic fixture."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True, help='iPhone simulator UUID')
parser.add_argument('--confirm-paid-requests', action='store_true', required=True,
                    help='Allow exactly one analysis and one studio request, without retries')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
build = root / 'build/ios-rust-migration'
log = root / 'build/rust-migration/live-ios.log'
log.parent.mkdir(parents=True, exist_ok=True)
with log.open('w') as output:
    log.chmod(0o600)
    subprocess.run(['xcodebuild', '-project', str(root / 'ios/Drape.xcodeproj'), '-scheme', 'Drape',
                    '-destination', f'platform=iOS Simulator,id={args.simulator}',
                    '-derivedDataPath', str(build), 'build-for-testing'],
                   cwd=root, stdout=output, stderr=subprocess.STDOUT, check=True)
    original = next((build / 'Build/Products').glob('Drape_*.xctestrun'))
    config = plistlib.loads(original.read_bytes())
    for configuration in config['TestConfigurations']:
        for target in configuration['TestTargets']:
            if target['BlueprintName'] == 'DrapeTests':
                target.setdefault('EnvironmentVariables', {})['DRAPE_LIVE_GATEWAY_SMOKE'] = '1'
    # Keep it beside the original: __TESTROOT__ paths are relative to this file.
    live = original.with_name('LiveGateway.xctestrun')
    try:
        live.write_bytes(plistlib.dumps(config))
        live.chmod(0o600)
        subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(live),
                        '-destination', f'platform=iOS Simulator,id={args.simulator}',
                        '-only-testing:DrapeTests/LiveGatewayTests/testSyntheticPhotoAgainstDeployedGateway'],
                       cwd=root, stdout=output, stderr=subprocess.STDOUT, check=True)
    finally:
        live.unlink(missing_ok=True)
print('Live iPhone gateway check passed: analysis and studio image, synthetic fixture only.')
