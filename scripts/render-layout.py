"""Generate layout for exactly one Theos package scheme; never prefix paths twice."""
import argparse
import pathlib
import plistlib
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--scheme', choices=('rootful', 'rootless', 'roothide'), required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
prefix = '/var/jb' if args.scheme == 'rootless' else ''
layout = root / 'layout'
frontend = layout / 'Library/IOSAutoTool/webide/frontend'
shutil.copytree(root / 'webide/frontend', frontend, dirs_exist_ok=True)
launch = layout / 'Library/LaunchDaemons/com.iosautotool.daemon.plist'
launch.parent.mkdir(parents=True, exist_ok=True)
launch.write_bytes(plistlib.dumps({
    'Label': 'com.iosautotool.daemon',
    'ProgramArguments': [prefix + '/Library/IOSAutoTool/iosautotool-daemon'],
    'UserName': 'root', 'GroupName': 'wheel',
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 30,
    'WorkingDirectory': '/var/mobile/Library/IOSAutoTool',
    'StandardOutPath': '/var/log/iosautotool/stdout.log',
    'StandardErrorPath': '/var/log/iosautotool/stderr.log',
}))
debian = layout / 'DEBIAN'
debian.mkdir(exist_ok=True)
postinst = f'''#!/bin/sh
set -e
if [ "$1" != configure ]; then exit 0; fi
mkdir -p /var/mobile/Library/IOSAutoTool/scripts /var/log/iosautotool
chmod 700 /var/mobile/Library/IOSAutoTool /var/mobile/Library/IOSAutoTool/scripts
chown root:wheel /var/mobile/Library/IOSAutoTool /var/mobile/Library/IOSAutoTool/scripts
PLIST="{prefix}/Library/LaunchDaemons/com.iosautotool.daemon.plist"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
# Ask the package manager to offer a respring after dpkg has completed.
finish_fd=${{CYDIA%% *}}
case "$finish_fd" in
    [3-9]) printf 'finish:restart\\n' 2>/dev/null >&"$finish_fd" || true ;;
esac
exit 0
'''
prerm = f'''#!/bin/sh
if [ "$1" = remove ] || [ "$1" = upgrade ] || [ "$1" = deconfigure ]; then
    launchctl unload "{prefix}/Library/LaunchDaemons/com.iosautotool.daemon.plist" 2>/dev/null || true
fi
finish_fd=${{CYDIA%% *}}
case "$finish_fd" in
    [3-9]) printf 'finish:restart\\n' 2>/dev/null >&"$finish_fd" || true ;;
esac
exit 0
'''
for name, text in [('postinst', postinst), ('prerm', prerm)]:
    file = debian / name
    file.write_text(text, encoding='utf-8', newline='\n')
    file.chmod(0o755)
stdlib = layout / 'Library/IOSAutoTool/lua/stdlib'
stdlib.mkdir(parents=True, exist_ok=True)
for source in (root / 'lua/stdlib').glob('*.lua'):
    (stdlib / source.name).write_bytes(source.read_bytes())
licenses = layout / 'Library/IOSAutoTool/licenses'
shutil.copytree(root / 'licenses', licenses, dirs_exist_ok=True)
