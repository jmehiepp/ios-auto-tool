"""Render one APT Release paragraph, with a date and hashes in that paragraph."""
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
from pathlib import Path
import sys

def render(directory):
    path = directory / 'Release'
    fields = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith(('MD5Sum:', 'SHA1:', 'SHA256:', 'SHA512:')):
            break
        if line and not line.startswith(' ') and ': ' in line:
            key, value = line.split(': ', 1)
            if key != 'Date': fields[key] = value
    fields['Date'] = format_datetime(datetime.now(timezone.utc), usegmt=True)
    lines = [f'{key}: {value}' for key, value in fields.items()]
    for title, algorithm in [('MD5Sum', 'md5'), ('SHA256', 'sha256')]:
        lines.append(title + ':')
        for name in ['Packages', 'Packages.gz', 'Packages.bz2']:
            data = (directory / name).read_bytes()
            digest = hashlib.new(algorithm, data).hexdigest()
            lines.append(f' {digest} {len(data):16d} {name}')
    path.write_text('\n'.join(lines)+'\n', encoding='utf-8', newline='\n')

if __name__ == '__main__':
    render(Path(sys.argv[1]))
