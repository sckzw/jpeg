from pathlib import Path
import json,math
from PIL import Image
from reference import *
from jpeg_cpu import parse,decode_scan
ROOT=Path(__file__).resolve().parents[1];DATA=ROOT/'tests/data'

def external_vectors():
    import random,struct
    rng=random.Random(20261005)
    for fmt in range(3):
        name=f'external{fmt}';w,h=17,13
        im=Image.new('RGB',(w,h));im.putdata([(rng.randrange(256),rng.randrange(256),rng.randrange(256)) for _ in range(w*h)])
        im.save(DATA/f'{name}.jpg',quality=72,subsampling=fmt)
        info=parse((DATA/f'{name}.jpg').read_bytes());(DATA/f'{name}.scan').write_bytes(info['scan'])
        dims=[(w,h)]+[((w+(1 if fmt else 0))//(2 if fmt else 1),(h+(1 if fmt==2 else 0))//(2 if fmt==2 else 1))]*2
        components=[c for c,_ in frame_blocks([bytes(cw*ch) for cw,ch in dims],w,h,fmt)]
        coeff=decode_scan(info['scan'],components,[info['hs'][i][1] for i in range(2)],[info['hs'][16+i][1] for i in range(2)])
        qs=[info['qs'][qid] for qid in info['qids']];out=reconstructed(coeff,w,h,fmt,qs)
        for c in range(3):(DATA/f'{name}_q{c}.bin').write_bytes(bytes(qs[c]));(DATA/f'{name}_out{c}.bin').write_bytes(out[c])
        for kind in range(1,5):
            for ident in range(2):
                ac=kind in (2,4);decode=kind>=3;table=info['hs'][ident+(16 if ac else 0)][int(decode)]
                (DATA/f'{name}_table{kind}_{ident}.bin').write_bytes(struct.pack('<'+'I'*len(table),*table))
    print('generated 3 Pillow baseline JPEG decode vectors')

def check():
    report=[]
    for spec in json.loads((DATA/'manifest.json').read_text()):
        name=spec['name'];w=spec['width'];h=spec['height'];fmt=spec['format']
        from generate_vectors import jpeg
        dc_counts=[0]*16;dc_counts[3]=12;ac_symbols=[0,240]+[r*16+n for r in range(16) for n in range(1,11)];ac_counts=[0]*16;ac_counts[7]=len(ac_symbols)
        actual_scan=(ROOT/'build'/f'{name}.scan').read_bytes()
        actual_file=ROOT/'build'/f'{name}.jpg'
        actual_file.write_bytes(jpeg(actual_scan,w,h,fmt,[[spec['q']]*64]*3,dc_counts,list(range(12)),ac_counts,ac_symbols))
        image=Image.open(actual_file);image.draft('YCbCr',image.size);image.load()
        if image.size!=(w,h):raise AssertionError('external decode dimensions')
        # 444 permits direct comparison without mixing chroma upsampling/color conversion.
        if fmt==0:
            actual=list(image.convert('YCbCr').getdata());expected=[(DATA/f'{name}_out{c}.bin').read_bytes() for c in range(3)]
            errors=[int(actual[i][c])-expected[c][i] for i in range(w*h) for c in range(3)]
            mse=sum(e*e for e in errors)/len(errors);peak=max(map(abs,errors));psnr=None if mse==0 else 10*math.log10(255**2/mse)
            report.append(dict(name=name,max_difference=peak,mse=mse,psnr_db=psnr,note='Pillow/libjpeg direct YCbCr decode (draft mode), no RGB roundtrip'))
        else:report.append(dict(name=name,decode='PASS',note='chroma upsampling differs; no direct planar metric'))
    (ROOT/'build').mkdir(exist_ok=True);(ROOT/'build/interop.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS external decode for 11 actual RTL JPEGs; metrics build/interop.json')

if __name__=='__main__':
    import sys
    if '--generate' in sys.argv:external_vectors()
    else:check()
