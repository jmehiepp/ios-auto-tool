"""Inventory registered globals from this project's source, not inferred examples."""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
entries = []
for file in sorted((root / 'lua').rglob('*.m')):
    text = file.read_text(encoding='utf-8')
    for match in re.finditer(r'lua_register\(\w+,\s*"([^"\n]+)"\s*,\s*(\w+)\)', text):
        entries.append({'name': match[1], 'native_function': match[2],
                        'source': file.relative_to(root).as_posix(),
                        'line': text[:match.start()].count('\n') + 1})
source = root / 'lua/bindings/bind-data.m'
text = source.read_text(encoding='utf-8')
library = re.search(r'const luaL_Reg functions\[\] = \{(.*?)\{NULL,NULL\}', text, re.S)[1]
for match in re.finditer(r'\{"([^"\n]+)",\s*(\w+)\}', library):
    entries.append({'name':match[1], 'native_function':match[2], 'source':source.relative_to(root).as_posix()})

tables = []
source = root / 'lua/bindings/bind-spoof.m'
text = source.read_text(encoding='utf-8-sig')
library = re.search(r'static const luaL_Reg spoof_lib\[\] = \{(.*?)\{NULL, NULL\}', text, re.S)[1]
for match in re.finditer(r'\{"([^"\n]+)",\s*(\w+)\}', library):
    tables.append({'name':'spoof.' + match[1], 'native_function':match[2], 'source':source.relative_to(root).as_posix()})
target = root / 'docs/lua-api.json'
target.write_text(json.dumps({'scope': 'Static registration inventory; iPhone behavior requires device testing.',
                              'globals': entries, 'table_functions': tables}, indent=2), encoding='utf-8')
print(f'{len(entries)} Lua globals and {len(tables)} table functions inventoried')
