"""Create a fresh CI-only simulator, retaining toolchain inventory as evidence."""
import json
import os
from pathlib import Path
import subprocess

def run(*args):
    return subprocess.check_output(args, text=True).strip()

evidence = Path('.build/simulator-evidence')
evidence.mkdir(parents=True, exist_ok=True)
inventory = run('xcrun', 'simctl', 'list', '--json')
(evidence / 'simulator-inventory.json').write_text(inventory)
data = json.loads(inventory)
runtimes = [r for r in data['runtimes'] if r.get('isAvailable') and '.iOS-' in r['identifier']]
runtime = max(runtimes, key=lambda r: tuple(int(v) for v in r['version'].split('.')))
types = [t for t in data['devicetypes'] if t.get('productFamily') == 'iPhone']
# Hardware support varies with the runtime. A current iPhone hosts a real native
# window; the fixture also tests a 320pt content width and accessibility5 text.
device_type = next((t for t in types if t['name'] == 'iPhone 17'), types[-1])
device = run('xcrun', 'simctl', 'create', 'Elsepin disposable validation', device_type['identifier'], runtime['identifier'])
with open(os.environ['GITHUB_ENV'], 'a') as env:
    env.write('VALIDATION_SIMULATOR=' + device + '\n')
subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
print(f"Validation simulator: {device_type['name']}, {runtime['name']}; disposable data only")
