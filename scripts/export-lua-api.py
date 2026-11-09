"""Inventory registered globals from this project's source, not inferred examples."""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
entries = []
for file in sorted((root / 'lua').rglob('*.m')):
    text = file.read_text(encoding='utf-8')
    for match in re.finditer(r'lua_register\(L,\s*"([^"\n]+)"\s*,\s*(\w+)\)', text):
        entries.append({'name': match[1], 'native_function': match[2],
                        'source': file.relative_to(root).as_posix(),
                        'line': text[:match.start()].count('\n') + 1})
target = root / 'docs/lua-api.json'
target.write_text(json.dumps({'scope': 'Static registration inventory; iPhone behavior requires device testing.',
                              'globals': entries}, indent=2), encoding='utf-8')
print(f'{len(entries)} Lua globals inventoried')
