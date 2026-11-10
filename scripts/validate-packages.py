"""Inspect real .deb payloads and Mach-O identity before publishing to Sileo."""
import argparse
import hashlib
import io
import json
import pathlib
import plistlib
import subprocess
import tarfile
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('directory', type=pathlib.Path)
parser.add_argument('--rename', action='store_true')
args = parser.parse_args()
results = []
seen = set()
for deb in sorted(args.directory.glob('*.deb')):
    control = subprocess.check_output(['dpkg-deb', '--field', str(deb)], text=True)
    fields = dict(line.split(': ', 1) for line in control.splitlines() if ': ' in line and not line.startswith(' '))
    assert fields['Package'] == 'com.iosautotool', fields
    arch = fields['Architecture']
    assert arch in ('iphoneos-arm', 'iphoneos-arm64', 'iphoneos-arm64e'), arch
    assert arch not in seen, 'Duplicate architecture package'
    seen.add(arch)
    prefix = 'var/jb/' if arch == 'iphoneos-arm64' else ''
    data = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(deb)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        members = {m.name.removeprefix('./'): m for m in archive.getmembers()}
        assert not any('var/jb/var/jb/' in n for n in members)
        base = prefix + 'Library/IOSAutoTool/'
        binary = archive.extractfile(members[base + 'iosautotool-daemon']).read()
        assert binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected a real thin 64-bit Mach-O'
        assert int.from_bytes(binary[4:8], 'little') == 0x100000c, 'Expected arm64 code'
        assert len(binary) > 100000, 'Suspiciously small daemon payload'
        for required in ('webide/frontend/index.html', 'webide/frontend/login.html', 'webide/frontend/editor.js', 'lua/stdlib/utils.lua', 'licenses/Mongoose-GPL2.txt', 'licenses/LuaJIT-MIT.txt'):
            assert base + required in members, required
        tweaks = prefix + 'Library/MobileSubstrate/DynamicLibraries/'
        for component in ('iosautotool-spoof', 'iosautotool-widget'):
            payload = archive.extractfile(members[tweaks + component + '.dylib']).read()
            assert payload[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'), component
        widget_filter = plistlib.loads(archive.extractfile(members[tweaks + 'iosautotool-widget.plist']).read())
        assert widget_filter['Filter']['Bundles'] == ['com.apple.springboard']
        device_filter = plistlib.loads(archive.extractfile(members[tweaks + 'iosautotool-spoof.plist']).read())
        assert device_filter['Filter']['Bundles'] == [], 'Device hooks must start with an empty app selection'
        launch_path = prefix + 'Library/LaunchDaemons/com.iosautotool.daemon.plist'
        launch = plistlib.loads(archive.extractfile(members[launch_path]).read())
        assert launch['ProgramArguments'][0] == '/' + base + 'iosautotool-daemon'
        assert launch['UserName'] == 'root'
        assert members[launch_path].mode & 0o777 == 0o644
        assert not any(n.endswith('/access-token') for n in members), 'A device token must never ship in a package'
        assert b'__ANTHROPIC_API_KEY__' not in binary, 'Embedded key placeholder must not be compiled'
        with tempfile.TemporaryDirectory() as scratch:
            native = pathlib.Path(scratch) / 'daemon'
            native.write_bytes(binary)
            entitlements = plistlib.loads(subprocess.check_output(['ldid', '-e', str(native)]))
            for entitlement in ('platform-application', 'com.apple.private.security.no-sandbox', 'com.apple.private.hid.client.event-dispatch'):
                assert entitlements.get(entitlement) is True, entitlement
            assert entitlements.get('com.apple.QuartzCore.global-capture') is True
            assert 'IOSurfaceRootUserClient' in entitlements.get('com.apple.security.iokit-user-client-class', [])
    maintainer_tar = subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', str(deb)])
    with tarfile.open(fileobj=io.BytesIO(maintainer_tar)) as archive:
        scripts = {m.name.removeprefix('./'): m for m in archive.getmembers()}
        for name in ('postinst', 'prerm'):
            assert scripts[name].mode & 0o111
            body = archive.extractfile(scripts[name]).read().decode()
            expected = ('/var/jb' if prefix else '') + '/Library/LaunchDaemons/'
            assert expected in body
    if args.rename:
        renamed = deb.with_name(f'iosautotool-daemon_{fields["Version"]}_{arch}.deb')
        if renamed != deb:
            if renamed.exists(): raise SystemExit(f'Refusing to overwrite {renamed}')
            deb.rename(renamed)
            deb = renamed
    results.append({'file': deb.name, 'package': fields['Package'], 'version': fields['Version'],
                    'architecture': arch, 'size': deb.stat().st_size,
                    'sha256': hashlib.sha256(deb.read_bytes()).hexdigest(), 'checks_passed': True})
assert seen == {'iphoneos-arm', 'iphoneos-arm64', 'iphoneos-arm64e'}, 'Rootful, rootless and RootHide packages are required'
args.directory.joinpath('validation.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps(results, indent=2))
