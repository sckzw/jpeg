from pathlib import Path
import struct,json,random
from reference import *
ROOT=Path(__file__).resolve().parents[1]/'tests/data'
def marker(code,payload):return bytes([255,code])+struct.pack('>H',len(payload)+2)+payload
def jpeg(scan,w,h,fmt,qs,dc_counts,dc_symbols,ac_counts,ac_symbols):
    factors=[0x11,0x21,0x22]
    dqt=b''.join(bytes([c])+bytes(qs[c][i] for i in ZIGZAG) for c in range(3))
    sof=bytes([8])+struct.pack('>HH',h,w)+bytes([3,1,factors[fmt],0,2,0x11,1,3,0x11,2])
    dht=bytes([0])+bytes(dc_counts)+bytes(dc_symbols)+bytes([16])+bytes(ac_counts)+bytes(ac_symbols)
    return b'\xff\xd8'+marker(0xdb,dqt)+marker(0xc0,sof)+marker(0xc4,dht)+marker(0xda,bytes([3,1,0,2,0,3,0,0,63,0]))+scan+b'\xff\xd9'
def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    dc_counts=[0]*16;dc_counts[3]=12;dc_symbols=list(range(12))
    ac_counts=[0]*16;ac_symbols=[0,240]+[r*16+n for r in range(16) for n in range(1,11)];ac_counts[7]=len(ac_symbols)
    encdc,decdc=huffman(dc_counts,dc_symbols);encac,decac=huffman(ac_counts,ac_symbols)
    tables=[encdc,encac,decdc,decac]
    for i,table in enumerate(tables):(ROOT/f'table{i+1}.bin').write_bytes(struct.pack('<'+'I'*len(table),*table))
    manifest=[];rng=random.Random(20261005)
    for name,w,h,fmt,q,pattern in [('flat',8,8,0,16,'flat'),('edge444',17,13,0,16,'random'),('edge422',17,13,1,16,'random'),('edge420',17,13,2,16,'random'),('q255',9,9,2,255,'random'),('dense',16,16,0,1,'random'),('gradient',32,24,0,8,'gradient'),('tiny444',1,1,0,1,'random'),('tiny420',1,1,2,16,'random'),('small422',7,5,1,13,'random'),('small420',7,5,2,13,'random')]:
        hs=1 if fmt==0 else 2;vs=2 if fmt==2 else 1;dims=[(w,h)]+[((w+hs-1)//hs,(h+vs-1)//vs)]*2
        planes=[bytes(128 if pattern=='flat' else (rng.randrange(256) if pattern=='random' else ((x*7+y*3+c*30)%256)) for y in range(ch) for x in range(cw)) for c,(cw,ch) in enumerate(dims)]
        qs=[[q]*64 for _ in range(3)];scan,coeff=encode_scan(list(frame_blocks(planes,w,h,fmt)),qs,encdc,encac)
        expected=reconstructed(coeff,w,h,fmt,qs)
        for c in range(3):(ROOT/f'{name}_in{c}.bin').write_bytes(planes[c]);(ROOT/f'{name}_out{c}.bin').write_bytes(expected[c])
        (ROOT/f'{name}.scan').write_bytes(scan);(ROOT/f'{name}.jpg').write_bytes(jpeg(scan,w,h,fmt,qs,dc_counts,dc_symbols,ac_counts,ac_symbols))
        manifest.append(dict(name=name,width=w,height=h,format=fmt,q=q,scan_bytes=len(scan)))
    (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'generated {len(manifest)} vectors, seed=20261005')
if __name__=='__main__':main()
