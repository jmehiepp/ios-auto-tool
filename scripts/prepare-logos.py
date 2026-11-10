"""Generate Logos translation units without Windows UTF-8 BOM markers."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for source in (root / 'spoof/modules').glob('*.m'):
    source.with_suffix('.xm').write_text(source.read_text(encoding='utf-8-sig'), encoding='utf-8', newline='\n')
