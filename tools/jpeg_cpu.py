"""CPU-side baseline header/table preparation plus independent scan reference decode."""
import struct
from reference import huffman,ZIGZAG

def parse(data):
    """Parse supported 8-bit, three-component, single-scan YCbCr baseline JPEG.

    Preserve the historic qs/hs/qids keys for reference tests; expose scan
    selectors as dcids/acids. Reject unsupported files before running RTL.
    """
    if data[:2] != b'\xff\xd8':
        raise ValueError('JPEG SOI missing')
    pos = 2
    qs, hs = {}, {}
    frame = None
    restart_interval = 0
    while pos < len(data):
        if data[pos] != 255:
            raise ValueError('invalid JPEG marker')
        while pos < len(data) and data[pos] == 255:
            pos += 1
        if pos >= len(data):
            raise ValueError('truncated marker')
        code = data[pos]
        pos += 1
        if code in (0, 0xd8, 0xd9) or 0xd0 <= code <= 0xd7:
            raise ValueError('unexpected standalone marker')
        if pos + 2 > len(data):
            raise ValueError('truncated segment length')
        size = int.from_bytes(data[pos:pos+2], 'big')
        if size < 2 or pos + size > len(data):
            raise ValueError('invalid/truncated JPEG segment')
        body = data[pos+2:pos+size]
        pos += size
        if code == 0xdb:
            p = 0
            while p < len(body):
                ident = body[p]
                p += 1
                if ident >> 4 or (ident & 15) > 3:
                    raise ValueError('only 8-bit DQT IDs 0..3 supported')
                if p + 64 > len(body):
                    raise ValueError('truncated DQT')
                q = [0]*64
                for i in range(64):
                    q[ZIGZAG[i]] = body[p+i]
                if 0 in q:
                    raise ValueError('zero quantization value')
                qs[ident] = q
                p += 64
        elif code == 0xc4:
            p = 0
            while p < len(body):
                if p + 17 > len(body):
                    raise ValueError('truncated DHT header')
                ident = body[p]
                counts = list(body[p+1:p+17])
                p += 17
                if ident >> 4 > 1 or (ident & 15) > 3:
                    raise ValueError('invalid DHT ID/class')
                n = sum(counts)
                if not n or p + n > len(body):
                    raise ValueError('empty/truncated DHT')
                symbols = list(body[p:p+n])
                p += n
                if len(set(symbols)) != n:
                    raise ValueError('duplicate Huffman symbols')
                if ident >> 4 == 0:
                    if any(x > 11 for x in symbols):
                        raise ValueError('invalid baseline DC category')
                elif any(x not in (0, 240) and not 1 <= (x & 15) <= 10 for x in symbols):
                    raise ValueError('invalid baseline AC symbol')
                hs[ident] = huffman(counts, symbols)
        elif code == 0xc0:
            if frame is not None or len(body) != 15 or body[0] != 8 or body[5] != 3:
                raise ValueError('8-bit baseline JPEG with three YCbCr components required')
            height, width = struct.unpack('>HH', body[1:5])
            ids = [body[6+3*c] for c in range(3)]
            factors = [body[7+3*c] for c in range(3)]
            if not width or not height or len(set(ids)) != 3 or ids == list(b'RGB'):
                raise ValueError('invalid dimensions or unsupported RGB JPEG')
            if factors[0] not in (0x11, 0x21, 0x22) or factors[1:] != [0x11, 0x11]:
                raise ValueError('only YCbCr 444/422/420 sampling supported')
            fmt = {0x11: 0, 0x21: 1, 0x22: 2}[factors[0]]
            qids = [body[8+3*c] for c in range(3)]
            frame = (width, height, fmt, ids, qids)
        elif code == 0xda:
            if frame is None or len(body) != 10 or body[0] != 3 or body[-3:] != bytes([0, 63, 0]):
                raise ValueError('single baseline scan with all three components required')
            width, height, fmt, ids, qids = frame
            if [body[1+2*c] for c in range(3)] != ids:
                raise ValueError('scan order must be Y, Cb, Cr in frame order')
            dcids = [body[2+2*c] >> 4 for c in range(3)]
            acids = [body[2+2*c] & 15 for c in range(3)]
            if len(set(dcids)) > 2 or len(set(acids)) > 2:
                raise ValueError('RTL supports at most two DC and two AC tables per scan')
            if any(q not in qs for q in qids) or any(d not in hs for d in dcids) or any(16+a not in hs for a in acids):
                raise ValueError('referenced JPEG table missing')
            end = pos
            while end < len(data):
                if data[end] != 255:
                    end += 1
                    continue
                if end + 1 >= len(data):
                    raise ValueError('truncated entropy marker')
                if data[end+1] == 0:
                    end += 2
                    continue
                marker_end = end + 1
                while marker_end < len(data) and data[marker_end] == 255:
                    marker_end += 1
                if marker_end < len(data) and 0xd0 <= data[marker_end] <= 0xd7:
                    if not restart_interval:
                        raise ValueError('restart marker without nonzero DRI')
                    end = marker_end + 1
                    continue
                if marker_end >= len(data) or data[marker_end] != 0xd9:
                    raise ValueError('multiple scans or malformed entropy data unsupported')
                return dict(width=width, height=height, format=fmt, qids=qids,
                            dcids=dcids, acids=acids, qs=qs, hs=hs, scan=data[pos:end],
                            restart_interval=restart_interval)
            raise ValueError('JPEG EOI missing')
        elif code == 0xdd:
            if len(body) != 2:
                raise ValueError('invalid DRI length')
            restart_interval = int.from_bytes(body, 'big')
        elif code == 0xee:
            if body.startswith(b'Adobe') and (len(body) != 12 or body[11] != 1):
                raise ValueError('Adobe RGB/CMYK/YCCK JPEG unsupported')
        elif 0xe0 <= code <= 0xef or code == 0xfe:
            pass  # APP metadata and comments do not change the scan contract.
        else:
            raise ValueError(f'unsupported JPEG marker 0x{code:02x} (baseline only)')
    raise ValueError('JPEG SOS missing')

def _decode_entropy_segment(scan,components,dc_tables,ac_tables,dcids=None,acids=None):
    raw=bytearray();p=0
    while p<len(scan):
        b=scan[p];p+=1;raw.append(b)
        if b==255:
            if p>=len(scan) or scan[p]!=0:raise ValueError('bad stuffing')
            p+=1
    bits=''.join(f'{b:08b}' for b in raw);position=0;pred=[0,0,0];out=[]
    def take(n):
        nonlocal position
        if position+n>len(bits):raise ValueError('truncated')
        v=int(bits[position:position+n] or '0',2);position+=n;return v
    def symbol(table):
        code=0
        for n in range(1,17):
            code=(code<<1)|take(1);mn,mx,first,count=table[4*(n-1):4*n]
            if count and mn<=code<=mx:return table[64+first+code-mn]
        raise ValueError('code')
    def amplitude(n):
        v=take(n)
        return v if not n or v&(1<<(n-1)) else v-((1<<n)-1)
    for comp in components:
        dc_id=dcids[comp] if dcids is not None else (0 if comp==0 else 1);ac_id=acids[comp] if acids is not None else (0 if comp==0 else 1);coeff=[0]*64;n=symbol(dc_tables[dc_id]);pred[comp]+=amplitude(n);coeff[0]=pred[comp];i=1
        while i<64:
            s=symbol(ac_tables[ac_id]);run,n=s>>4,s&15
            if s==0:break
            if s==240:i+=16;continue
            i+=run
            if i>=64 or n>10 or n==0:raise ValueError('AC')
            coeff[ZIGZAG[i]]=amplitude(n);i+=1
        out.append((comp,coeff))
    if len(bits)-position>7 or any(b!='1' for b in bits[position:]):raise ValueError('padding')
    return out


def decode_scan(scan, components, dc_tables, ac_tables, dcids=None, acids=None,
                restart_interval=0, format=0):
    """Independent CPU reference: decode each restart segment with fresh predictors."""
    if not restart_interval:
        return _decode_entropy_segment(scan, components, dc_tables, ac_tables, dcids, acids)
    segments, start, pos, expected = [], 0, 0, 0
    while pos < len(scan):
        if scan[pos] != 255:
            pos += 1
            continue
        if pos+1 >= len(scan):
            raise ValueError('truncated restart marker')
        if scan[pos+1] == 0:
            pos += 2
            continue
        marker_start = pos
        while pos < len(scan) and scan[pos] == 255:
            pos += 1
        if pos >= len(scan) or scan[pos] != 0xd0+expected:
            raise ValueError('restart sequence')
        segments.append(scan[start:marker_start])
        expected = (expected+1) % 8
        pos += 1
        start = pos
    segments.append(scan[start:])
    blocks = restart_interval * (3, 4, 6)[format]
    if len(segments) != (len(components)-1)//blocks+1:
        raise ValueError('restart segment count')
    out = []
    for i, segment in enumerate(segments):
        out.extend(_decode_entropy_segment(segment, components[i*blocks:(i+1)*blocks],
                                           dc_tables, ac_tables, dcids, acids))
    return out
