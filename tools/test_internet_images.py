"""Separated RTL encoder / decoder tests with downloaded, pinned image files.

Never send an RTL-generated JPEG to the RTL decoder in this test.
Downloads are deliberately separate: cached inputs and hashes make reruns offline.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import subprocess
import sys
from PIL import Image
from jpeg_tool import ROOT
from jpeg_cpu import parse
from test_jpeg_tool import expected_rgb

INPUT = ROOT/'tests/data/internet'
OUTPUT = ROOT/'tests/results/internet'
SOURCES = [
    dict(file='example.png', role='encoder input', author='Wolfgang / W.', license='Public domain',
         page='https://commons.wikimedia.org/wiki/File:Example.png',
         download='https://upload.wikimedia.org/wikipedia/commons/7/70/Example.png'),
    dict(file='flower_baseline.jpg', role='decoder input (original 2005 version)', author='David Crawshaw',
         license='CC BY-SA 3.0', license_url='https://creativecommons.org/licenses/by-sa/3.0/',
         page='https://commons.wikimedia.org/wiki/File:JPEG_example_flower.jpg',
         download='https://upload.wikimedia.org/wikipedia/commons/archive/3/3f/20170304154030%21JPEG_example_flower.jpg'),
    dict(file='flower.jpg', role='unsupported progressive rejection', author='David Crawshaw',
         license='CC BY-SA 3.0', license_url='https://creativecommons.org/licenses/by-sa/3.0/',
         page='https://commons.wikimedia.org/wiki/File:JPEG_example_flower.jpg',
         download='https://upload.wikimedia.org/wikipedia/commons/3/3f/JPEG_example_flower.jpg'),
]


def difference(actual, expected):
    if actual.size != expected.size or actual.mode != expected.mode:
        raise AssertionError('image dimensions/mode mismatch')
    delta = [abs(a-b) for a, b in zip(actual.tobytes(), expected.tobytes())]
    mse = sum(x*x for x in delta)/len(delta)
    return dict(max_difference=max(delta), mean_absolute_difference=sum(delta)/len(delta),
                mse=mse, psnr_db=None if mse == 0 else 10*math.log10(255**2/mse))


def cli(script, *args, success=True):
    command = [sys.executable, str(ROOT/'tools'/script), *map(str, args)]
    ai_debug = os.environ.get('VSIM_AI_DEBUG', '0').lower() in ('1', 'true', 'yes')
    if ai_debug:
        print('$', ' '.join(map(str, command)), flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if (result.returncode == 0) != success:
            raise AssertionError(f'unexpected exit code {result.returncode}')
        return subprocess.CompletedProcess(command, result.returncode, stdout='cycles=0', stderr='')
    result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    print('$', ' '.join(map(str, command)), flush=True)
    print(result.stdout, end='', flush=True)
    print(result.stderr, end='', flush=True)
    if (result.returncode == 0) != success:
        raise AssertionError(f'unexpected exit code {result.returncode}')
    return result


def main():
    target_filter = sys.argv[1].lower() if len(sys.argv) > 1 else None
    OUTPUT.mkdir(parents=True, exist_ok=True)
    provenance = []
    for source in SOURCES:
        p = INPUT/source['file']
        data = p.read_bytes()
        with Image.open(p) as image:
            entry = dict(source, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                         dimensions=list(image.size), mode=image.mode,
                         progressive=bool(image.info.get('progressive')))
        provenance.append(entry)
    manifest = INPUT/'sources.json'
    if manifest.exists():
        pinned = json.loads(manifest.read_text(encoding='utf-8'))
        assert [x['sha256'] for x in pinned] == [x['sha256'] for x in provenance], 'source hashes changed'
    else:
        manifest.write_text(json.dumps(provenance, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    report = dict(date='2026-10-06', separation='RTL encoder output is never passed to RTL decoder',
                  sources=provenance, encoder=[], decoder=[])
    with Image.open(INPUT/'example.png') as source:
        original = source.convert('RGBA')
        white = Image.new('RGBA', source.size, (255, 255, 255, 255))
        original = Image.alpha_composite(white, original).convert('RGB')
    if not target_filter or 'example' in target_filter or 'encode' in target_filter:
        for sampling in ('444', '422', '420'):
            jpg = OUTPUT/f'encoded_{sampling}.jpg'
            external_png = OUTPUT/f'encoded_{sampling}_external.png'
            result = cli('jpeg_encode.py', INPUT/'example.png', jpg, '--quant', 16, '--sampling', sampling)
            with Image.open(jpg) as image:
                image.load()  # Independent Pillow/libjpeg entropy and IDCT decoding.
                external = image.convert('RGB')
            external.save(external_png)
            assert external.size == original.size
            scan = parse(jpg.read_bytes())
            stats = difference(external, original)
            report['encoder'].append(dict(sampling=sampling, quant=16, status='PASS external libjpeg decode',
                cycles=int(re.search(r'cycles=(\d+)', result.stdout)[1]), jpeg_bytes=jpg.stat().st_size,
                scan_bytes=len(scan['scan']), original_vs_external_rgb=stats))
            print('ENCODER', sampling, json.dumps(stats), flush=True)

    # The sole successful RTL decoder input is the downloaded baseline photo.
    if not target_filter or 'flower' in target_filter or 'decode' in target_filter:
        jpg = INPUT/'flower_baseline.jpg'
        assert jpg.resolve().parent == INPUT.resolve()
        output = OUTPUT/'flower_rtl.png'
        result = cli('jpeg_decode.py', jpg, output)
    with Image.open(output) as image:
        actual = image.convert('RGB')
    with Image.open(jpg) as image:
        image.load()
        external = image.convert('RGB')
    external.save(OUTPUT/'flower_external.png')
    stats = difference(actual, external)
    info = parse(jpg.read_bytes())
    reference = expected_rgb(info)
    assert actual.tobytes() == reference, 'RTL decoder differs from integer reference'
    report['decoder'].append(dict(input='flower_baseline.jpg', dimensions=list(actual.size),
        sampling=('444', '422', '420')[info['format']], cycles=int(re.search(r'cycles=(\d+)', result.stdout)[1]),
        status='PASS integer reference pixel match and external comparison',
        integer_reference='RGB byte exact', rtl_vs_external_rgb=stats,
        comparison_note='Includes fixed-point IDCT/color conversion and nearest-neighbour vs libjpeg chroma interpolation differences'))
    print('DECODER', json.dumps(stats), flush=True)
    rejected = OUTPUT/'progressive_rejected.png'
    if rejected.exists():
        rejected.unlink()
    result = cli('jpeg_decode.py', INPUT/'flower.jpg', rejected, success=False)
    assert not rejected.exists()
    report['progressive_rejection'] = dict(status='PASS', reason=result.stderr.strip())
    (OUTPUT/'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print('PASS separated internet-image encoder/decoder tests', flush=True)


if __name__ == '__main__':
    main()
