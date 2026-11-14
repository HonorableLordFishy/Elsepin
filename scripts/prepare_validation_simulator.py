"""Create a fresh CI-only simulator, retaining toolchain inventory as evidence."""
import json
import os
from pathlib import Path
import subprocess

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def choose_destination(data, sdk_version):
    candidates = []
    for runtime in data['runtimes']:
        if not runtime.get('isAvailable') or '.iOS-' not in runtime['identifier']:
            continue
        supported = [t for t in runtime.get('supportedDeviceTypes', [])
                     if t.get('productFamily') == 'iPhone']
        if not supported:
            continue
        device_type = next((t for t in supported if t['name'] == 'iPhone 17'), supported[0])
        version = tuple(int(v) for v in runtime['version'].split('.'))
        matches_sdk = version[:2] == tuple(int(v) for v in sdk_version.split('.'))[:2]
        candidates.append(((matches_sdk, version), runtime, device_type))
    if not candidates:
        raise RuntimeError('No available iOS runtime with a supported iPhone device type')
    _, runtime, device_type = max(candidates, key=lambda candidate: candidate[0])
    return runtime, device_type

def main():
    evidence = Path('.build/simulator-evidence')
    evidence.mkdir(parents=True, exist_ok=True)
    inventory = run('xcrun', 'simctl', 'list', '--json')
    (evidence / 'simulator-inventory.json').write_text(inventory)
    sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    runtime, device_type = choose_destination(json.loads(inventory), sdk)
    device = run('xcrun', 'simctl', 'create', 'Elsepin disposable validation', device_type['identifier'], runtime['identifier'])
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write('VALIDATION_SIMULATOR=' + device + '\n')
    # Boot only after compilation, preserving memory/CPU for the compiler.
    print(f"Validation simulator: {device_type['name']}, {runtime['name']}, SDK {sdk}; disposable data only")

if __name__ == '__main__':
    main()
