#!/usr/bin/env python3
"""Opt-in paid check through the actual iOS URLSession client and synthetic fixture."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True, help='iPhone simulator UUID')
parser.add_argument('--confirm-paid-requests', action='store_true', required=True,
                    help='Allow one analysis and, unless --analysis-only, one studio request, without retries')
parser.add_argument('--analysis-only', action='store_true', help='Validate metadata without generating another studio photo')
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
    # Xcode emits either v1 target dictionaries or v2 TestConfigurations.
    if 'TestConfigurations' in config:
        targets = [target for configuration in config['TestConfigurations']
                   for target in configuration['TestTargets']
                   if target.get('BlueprintName') == 'DrapeTests']
    else:
        targets = [value for name, value in config.items()
                   if name == 'DrapeTests' or name.startswith('DrapeTests_')]
    if len(targets) != 1:
        raise RuntimeError('Expected exactly one DrapeTests target; no paid requests were sent')
    targets[0].setdefault('EnvironmentVariables', {})['DRAPE_LIVE_GATEWAY_SMOKE'] = '1'
    if args.analysis_only:
        targets[0]['EnvironmentVariables']['DRAPE_LIVE_ANALYSIS_ONLY'] = '1'
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
print('Live iPhone gateway check passed: ' + ('analysis only' if args.analysis_only else 'analysis and studio image') + ', synthetic fixture only.')
