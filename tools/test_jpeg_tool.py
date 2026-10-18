"""End-to-end CLI tests; scan and pixels checked against the integer model."""
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
from PIL import Image
from jpeg_tool import ROOT, subsample, encode, decode, dimensions
from jpeg_cpu import parse, decode_scan
from reference import frame_blocks, encode_scan, reconstructed
from generate_vectors import marker


def expected_rgb(info):
    w, h, fmt = info['width'], info['height'], info['format']
    dummy = [bytes(cw*ch) for cw, ch in dimensions(w, h, fmt)]
    components = [c for c, _ in frame_blocks(dummy, w, h, fmt)]
    # decode_scan's historic interface uses table0 for Y and table1 for chroma.
    # Feed a separately selected stream to avoid any dependence on Pillow JPEG decode.
    coeff = decode_scan(info['scan'], components,
                        {d: info['hs'][d][1] for d in info['dcids']},
                        {a: info['hs'][16+a][1] for a in info['acids']},
                        dcids=info['dcids'], acids=info['acids'],
                        restart_interval=info.get('restart_interval', 0), format=fmt)
    raw = reconstructed(coeff, w, h, fmt, [info['qs'][q] for q in info['qids']])
    planes = [Image.frombytes('L', size, pixels) for size, pixels in zip(dimensions(w, h, fmt), raw)]
    if fmt:
        hs, vs = 2, (2 if fmt == 2 else 1)
        for c in (1, 2):
            cw, ch = dimensions(w, h, fmt)[c]
            planes[c] = planes[c].resize((cw*hs, ch*vs), Image.Resampling.NEAREST).crop((0, 0, w, h))
    return Image.merge('YCbCr', planes).convert('RGB').tobytes()


def remap_ids(payload):
    """Change Q/DC/AC IDs and component IDs without changing entropy bits."""
    pos = 2
    out = bytearray(payload[:2])
    while pos < len(payload):
        code = payload[pos+1]
        size = int.from_bytes(payload[pos+2:pos+4], 'big')
        body = bytearray(payload[pos+4:pos+2+size])
        pos += 2+size
        if code == 0xdb:
            for p in range(0, len(body), 65):
                body[p] = 3-body[p]
        elif code == 0xc4:
            p = 0
            while p < len(body):
                n = sum(body[p+1:p+17])
                body[p] = (body[p] & 0xf0) | (3-(body[p] & 15))
                p += 17+n
        elif code == 0xc0:
            for c in range(3):
                body[6+3*c] = 10+c
                body[8+3*c] = 3-body[8+3*c]
        elif code == 0xda:
            for c in range(3):
                body[1+2*c] = 10+c
                table = body[2+2*c]
                body[2+2*c] = ((3-(table >> 4)) << 4) | (3-(table & 15))
            out.extend(marker(code, body))
            out.extend(payload[pos:])
            break
        out.extend(marker(code, body))
    return bytes(out)


def main():
    rng = random.Random(20261006)
    cases = [('one', 1, 1, '444', 1), ('rgba', 17, 13, '444', 16),
             ('odd422', 17, 13, '422', 8), ('odd420', 17, 13, '420', 16),
             ('largeq', 9, 9, '420', 255), ('dense', 32, 24, '444', 1)]
    with tempfile.TemporaryDirectory(prefix='jpeg-cli-test-') as temporary:
        job = Path(temporary)
        for name, w, h, sampling, quant in cases:
            source, jpg, png = job/f'{name}.png', job/f'{name}.jpg', job/f'{name}_out.png'
            image = Image.frombytes('RGBA', (w, h), bytes(rng.randrange(256) for _ in range(w*h*4)))
            image.save(source)
            encode(source, jpg, quant, sampling)
            info = parse(jpg.read_bytes())
            bg = Image.new('RGBA', (w, h), (255, 255, 255, 255))
            planes = [p.tobytes() for p in Image.alpha_composite(bg, image).convert('RGB').convert('YCbCr').split()]
            fmt = info['format']
            if fmt:
                planes[1:] = [subsample(p, w, h, 2, 2 if fmt == 2 else 1) for p in planes[1:]]
            expected_scan, _ = encode_scan(list(frame_blocks(planes, w, h, fmt)),
                                          [info['qs'][q] for q in info['qids']], info['hs'][0][0], info['hs'][16][0])
            assert info['scan'] == expected_scan, f'{name}: RTL scan differs from reference'
            with Image.open(jpg) as external:
                external.load()
                assert external.size == (w, h)
            decoder_input = job/f'{name}_independent.jpg'
            Image.alpha_composite(bg, image).convert('RGB').save(decoder_input, quality=72, subsampling=fmt)
            decode(decoder_input, png)
            with Image.open(png) as output:
                assert output.tobytes() == expected_rgb(parse(decoder_input.read_bytes())), f'{name}: decoded RGB differs from reference'
        for sampling in range(3):
            source = job/f'external{sampling}.jpg'
            output = job/f'external{sampling}.png'
            image.convert('RGB').save(source, quality=72, subsampling=sampling)
            # Also verify legal non-default IDs and arbitrary component IDs.
            source.write_bytes(remap_ids(source.read_bytes()))
            decode(source, output)
            with Image.open(output) as actual:
                assert actual.tobytes() == expected_rgb(parse(source.read_bytes()))
        # Exercise both user-facing entry scripts.
        subprocess.run([sys.executable, str(ROOT/'tools/jpeg_encode.py'), str(job/'rgba.png'), str(job/'entry.jpg')], check=True)
        subprocess.run([sys.executable, str(ROOT/'tools/jpeg_decode.py'), str(job/'external0.jpg'), str(job/'entry.png')], check=True)
        failures = []
        progressive = job/'progressive.jpg'
        image.convert('RGB').save(progressive, progressive=True)
        failures.append(progressive)
        gray = job/'gray.jpg'
        image.convert('L').save(gray)
        failures.append(gray)
        truncated = job/'truncated.jpg'
        truncated.write_bytes((job/'external0.jpg').read_bytes()[:-2])
        failures.append(truncated)
        restart = job/'restart.jpg'
        data = (job/'external0.jpg').read_bytes()
        restart.write_bytes(data[:2]+marker(0xdd, struct.pack('>H', 1))+data[2:])
        failures.append(restart)
        for source in failures:
            output = job/'rejected.png'
            result = subprocess.run([sys.executable, str(ROOT/'tools/jpeg_decode.py'), str(source), str(output)], capture_output=True)
            assert result.returncode != 0 and not output.exists(), source
        result = subprocess.run([sys.executable, str(ROOT/'tools/jpeg_encode.py'), str(job/'rgba.png'), str(job/'invalid.jpg'), '--quant', '0'], capture_output=True)
        assert result.returncode != 0 and not (job/'invalid.jpg').exists()
        original = (job/'rgba.png').read_bytes()
        result = subprocess.run([sys.executable, str(ROOT/'tools/jpeg_encode.py'), str(job/'rgba.png'), str(job/'rgba.png')], capture_output=True)
        assert result.returncode != 0 and (job/'rgba.png').read_bytes() == original
    print('PASS CLI: 6 PNG encodes byte-exact, 9 JPEG decodes pixel-exact, external decode, remapped table IDs, entry scripts and rejection cases')


if __name__ == '__main__':
    main()
