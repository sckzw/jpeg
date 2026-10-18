"""Software-only JPEG encoder creates restart fixtures; never RTL encode->decode."""
from pathlib import Path
import random
import struct
from reference import huffman, frame_blocks, encode_scan, reconstructed
from jpeg_cpu import parse, decode_scan
from generate_vectors import jpeg, marker

ROOT=Path(__file__).resolve().parents[1]/'tests/data/restart'

def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    rng=random.Random(20261006)
    dc_counts=[0]*16;dc_counts[3]=12;dc_symbols=list(range(12))
    ac_counts=[0]*16;ac_symbols=[0,240]+[r*16+n for r in range(16) for n in range(1,11)];ac_counts[7]=len(ac_symbols)
    dc,_=huffman(dc_counts,dc_symbols);ac,_=huffman(ac_counts,ac_symbols)
    qs=[[16]*64 for _ in range(3)]
    manifest=[]
    def save(name,w,h,fmt,interval,scan,error=0,expected=None):
        payload=jpeg(scan,w,h,fmt,qs,dc_counts,dc_symbols,ac_counts,ac_symbols)
        payload=payload[:2]+marker(0xdd,struct.pack('>H',interval))+payload[2:]
        (ROOT/f'{name}.jpg').write_bytes(payload)
        (ROOT/f'{name}.scan').write_bytes(scan)
        for c in range(3):
            (ROOT/f'{name}_q{c}.bin').write_bytes(bytes(qs[c]))
            if expected is not None:(ROOT/f'{name}_out{c}.bin').write_bytes(expected[c])
        for kind,words in [(3,huffman(dc_counts,dc_symbols)[1]),(4,huffman(ac_counts,ac_symbols)[1])]:
            for ident in range(2):(ROOT/f'{name}_table{kind}_{ident}.bin').write_bytes(struct.pack('<'+'I'*len(words),*words))
        manifest.append(f'{name} {w} {h} {fmt} {interval} 528 {error}')
    def fixture(w,h,fmt,interval,flat=False):
        hs=1 if fmt==0 else 2;vs=2 if fmt==2 else 1
        dims=[(w,h)]+[((w+hs-1)//hs,(h+vs-1)//vs)]*2
        planes=[bytes(128 if flat else rng.randrange(256) for _ in range(cw*ch)) for cw,ch in dims]
        blocks=list(frame_blocks(planes,w,h,fmt));chunk=interval*(3,4,6)[fmt];scans=[];coeff=[]
        for offset in range(0,len(blocks),chunk):
            scan,q=encode_scan(blocks[offset:offset+chunk],qs,dc,ac);scans.append(scan);coeff.extend(q)
        scan=b''.join(segment+(bytes([255,0xd0+i%8]) if i<len(scans)-1 else b'') for i,segment in enumerate(scans))
        expected=reconstructed(coeff,w,h,fmt,qs)
        # Reference independently validates padding, sequence and DC resets.
        decoded=decode_scan(scan,[c for c,_ in blocks],[huffman(dc_counts,dc_symbols)[1]]*2,
                            [huffman(ac_counts,ac_symbols)[1]]*2,dcids=[0]*3,acids=[0]*3,restart_interval=interval,format=fmt)
        assert decoded==coeff
        return scan,expected
    for fmt in range(3):
        for interval in (1,2,3,65535):
            scan,expected=fixture(79,35,fmt,interval)
            save(f'fmt{fmt}_ri{interval}',79,35,fmt,interval,scan,expected=expected)
    for fmt in range(3):
        w=16 if fmt==0 else 32;h=8 if fmt!=2 else 16
        scan,expected=fixture(w,h,fmt,2)
        save(f'exact_final{fmt}',w,h,fmt,2,scan,expected=expected)
    scan,expected=fixture(79,35,2,1)
    index=scan.index(b'\xff\xd0')
    save('marker_fill',79,35,2,1,scan[:index]+b'\xff\xff'+scan[index:],expected=expected)
    flat,expected=fixture(24,8,0,1,flat=True);index=flat.index(b'\xff\xd0')
    save('flat',24,8,0,1,flat,expected=expected)
    save('marker_4k',24,8,0,1,flat[:index]+b'\xff'*(4095-index)+flat[index:],expected=expected)
    save('wrong_number',24,8,0,1,flat[:index+1]+b'\xd1'+flat[index+2:],6)
    save('early_marker',24,8,0,1,b'\xff\xd0'+flat,6)
    save('late_marker',24,8,0,1,flat[:index]+b'\x00'+flat[index:],10)
    save('bad_padding',24,8,0,1,flat[:index-1]+bytes([flat[index-1]&254])+flat[index:],10)
    save('missing_marker',24,8,0,1,flat[:index]+flat[index+2:],10)
    save('truncated_interval',24,8,0,1,flat[:index],5)
    save('truncated_ff',24,8,0,1,flat[:index+1],6)
    save('unexpected_final',24,8,0,1,flat+b'\xff\xd2',6)
    save('interval_zero',24,8,0,0,flat,6)
    save('interval_too_long',24,8,0,2,flat,6)
    save('interval_too_short',79,35,0,1,fixture(79,35,0,2)[0],10)
    (ROOT/'manifest.txt').write_text('\n'.join(manifest)+'\n')
    print(f'generated {len(manifest)} restart vectors, seed=20261006')
if __name__=='__main__':main()
