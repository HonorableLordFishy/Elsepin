"""Observe the real Files export for assertions in the disposable validation app.

Files creates its own provider item through the export UI. This helper reads
that item and writes a test receipt outside Files, without changing the source.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time


def container(device, bundle, kind):
    return Path(subprocess.check_output(
        ['xcrun', 'simctl', 'get_app_container', device, bundle, kind],
        text=True, stderr=subprocess.PIPE, timeout=15).strip())


def files_storage_group(device, app):
    # On some runtimes this group belongs to the LocalStorage provider rather
    # than DocumentsApp, so get_app_container's specific-group lookup rejects
    # it. Resolve only that exact group's metadata inside our owned simulator.
    data = next((parent for parent in app.parents
                if parent.name == 'data' and parent.parent.name == device), None)
    if data is None:
        raise ValueError(f'App container {app} is outside simulator {device}')
    groups = data / 'Containers/Shared/AppGroup'
    identifiers = []
    for metadata in groups.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
        with metadata.open('rb') as stream:
            identifier = plistlib.load(stream).get('MCMMetadataIdentifier', '')
        if 'FileProvider' in identifier or 'Documents' in identifier:
            identifiers.append(identifier)
        if identifier == 'group.com.apple.FileProvider.LocalStorage':
            return metadata.parent
    raise FileNotFoundError(f'LocalStorage group not initialized; document groups: {identifiers}')


def main():
    device = os.environ['VALIDATION_SIMULATOR']
    evidence = Path('.build/simulator-evidence')
    started_at_ns = time.time_ns()
    deadline = time.monotonic() + 1800
    last_error = None
    observed = None
    group = None
    while time.monotonic() < deadline:
        try:
            if group is None:
                app = container(device, 'com.n3mostudio.elsepin.validation', 'data')
                storage_group = files_storage_group(device, app)
                if device not in storage_group.parts or 'AppGroup' not in storage_group.parts:
                    raise ValueError('Files group is outside the disposable simulator')
                group = storage_group
            files = [(path.stat().st_mtime_ns, path.name) for path in (group / 'File Provider Storage').glob('Elsepin-Settings*.json')
                     if path.is_file() and not path.is_symlink()]
            latest = max(files, default=None)
            if latest is not None and latest[0] >= started_at_ns and latest != observed:
                source = group / 'File Provider Storage' / latest[1]
                payload = source.read_bytes()
                backup = json.loads(payload)
                if backup.get('categories') != ['settings'] or backup.get('places') or backup.get('trips'):
                    raise ValueError('Expected only the disposable settings export')
                app = container(device, 'com.n3mostudio.elsepin.validation', 'data')
                if device not in app.parts or app.is_symlink():
                    raise ValueError('Validation app is outside the disposable simulator')
                cache = app / 'Library/Caches'
                cache.mkdir(parents=True, exist_ok=True)
                receipt = cache / 'ValidationSettingsExport.json'
                temporary = receipt.with_suffix('.tmp')
                temporary.write_text(json.dumps({'filename': source.name, 'text': payload.decode('utf-8')}), encoding='utf-8')
                temporary.replace(receipt)
                (evidence / 'native-settings-export.json').write_bytes(payload)
                observed = latest
                print(f'Observed settings export at On My iPhone/{source.name} ({len(payload)} bytes).', flush=True)
            time.sleep(1)
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            # Files' group may not exist until its first native presentation.
            message = str(error)
            if isinstance(error, subprocess.CalledProcessError):
                message += ': ' + (error.stderr or '')[:500]
            if message != last_error:
                print(message, flush=True)
            last_error = message
            time.sleep(5)
    if observed is None:
        raise RuntimeError(f'Timed out observing a native UI export: {last_error}')


if __name__ == '__main__':
    main()
