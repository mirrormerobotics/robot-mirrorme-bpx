"""Inventory available wheel/ELF and Docker artifacts without loading the SDK.

This is a binary inventory, not a claim that statically linked dependencies
or all upstream license obligations have been identified.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile


def run(*args):
    return subprocess.check_output(args, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wheel', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--image', action='append', default=[])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    wheel_hash = hashlib.sha256(args.wheel.read_bytes()).hexdigest()
    expected = '23dec27cd4c90cfe5531fbccf5db15e44c5ec4d4b6d2a76941e61def957db115'
    if wheel_hash != expected:
        parser.error('wheel does not match the pinned SDK artifact')
    report = {'created_at': datetime.now(timezone.utc).isoformat(),
              'scope': 'available cp310 x86_64 wheel and selected local images',
              'complete_source_license_audit': False,
              'wheel': {'name': args.wheel.name, 'sha256': wheel_hash, 'files': []},
              'images': []}
    with zipfile.ZipFile(args.wheel) as archive, tempfile.TemporaryDirectory() as temp:
        for entry in archive.infolist():
            if entry.is_dir():
                continue
            data = archive.read(entry)
            item = {'path': entry.filename, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            if data.startswith(b'\x7fELF'):
                path = Path(temp) / 'library.elf'
                path.write_bytes(data)
                # Inspect dynamic dependencies without running native code/ldd.
                item['elf_dynamic'] = run('readelf', '-d', str(path))
            if entry.filename.endswith(('METADATA', 'LICENSE', 'NOTICE')):
                item['text'] = data.decode('utf-8', errors='replace')
            report['wheel']['files'].append(item)
    for image in args.image:
        metadata = json.loads(run('docker', 'image', 'inspect', image))[0]
        image_id = metadata['Id']
        packages = run('docker', 'run', '--rm', '--network', 'none', '--entrypoint', 'dpkg-query',
                       image_id, '-W', '-f=${Package}\t${Version}\t${Architecture}\n')
        python = run('docker', 'run', '--rm', '--network', 'none', '--entrypoint', 'python3',
                     image_id, '-m', 'pip', 'list', '--format=json', '--disable-pip-version-check')
        report['images'].append({'name': image, 'id': image_id, 'digests': metadata.get('RepoDigests', []),
                                 'os': metadata['Os'], 'architecture': metadata['Architecture'],
                                 'os_packages': packages.splitlines(), 'python_packages': json.loads(python)})
    path = args.output / 'inventory.json'
    path.write_text(json.dumps(report, indent=2) + '\n')
    (args.output / 'SHA256SUMS').write_text(hashlib.sha256(path.read_bytes()).hexdigest() + '  inventory.json\n')
    print(path)


if __name__ == '__main__':
    main()
