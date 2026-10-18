"""Independent libjpeg JPEG input for RTL decoder benchmarks (never RTL scan)."""
from pathlib import Path
import random
import struct
import sys
from PIL import Image
from jpeg_cpu import parse
ROOT=Path(__file__).resolve().parents[1]
variant=sys.argv[1] if len(sys.argv)>1 else ''
prefix='a4'+('_'+variant if variant else '')
if variant=='stress':
    # Dense, independent RGB noise; Q=1 gives an expanded JPEG input.
    rgb=Image.frombytes('RGB',(2480,3508),random.Random(20261005).randbytes(2480*3508*3))
    q=1
else:
    rgb=Image.open(ROOT/'tests/data/a4_manuscript.png').convert('RGB')
    q=16
path=ROOT/'build'/f'{prefix}_decode_input.jpg'
path.parent.mkdir(exist_ok=True)
rgb.save(path,qtables=[[q]*64,[q]*64],subsampling=0,progressive=False,optimize=False)
info=parse(path.read_bytes())
assert info['format']==0 and not info['restart_interval']
path.with_suffix('.scan').write_bytes(info['scan'])
for c in range(3):(path.parent/f'{prefix}_decode_q{c}.bin').write_bytes(bytes(info['qs'][info['qids'][c]]))
for kind,cls in [(3,0),(4,16)]:
    for ident in range(2):
        words=info['hs'][cls+ident][1]
        (path.parent/f'{prefix}_decode_table{kind}_{ident}.bin').write_bytes(struct.pack('<'+'I'*len(words),*words))
print(f'independent decoder JPEG: {path}, Q={q}, scan={len(info["scan"])} bytes')
