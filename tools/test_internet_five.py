"""Five additional downloaded inputs: separated encode/decode interoperability."""
from pathlib import Path
import hashlib
import json
import re
from PIL import Image
from jpeg_tool import ROOT
from jpeg_cpu import parse
from test_internet_images import cli, difference
from test_jpeg_tool import expected_rgb

INPUT = ROOT/'tests/data/internet_five'
OUTPUT = ROOT/'tests/results/internet_five'
SOURCES = [
    dict(file='dice1.png', role='encode', sampling='444',
         page='https://commons.wikimedia.org/wiki/File:PNG_transparency_demonstration_1.png',
         download='https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png',
         author='Daniel G., Ed g2s, CyberShadow', license='CC BY-SA 3.0',
         license_url='https://creativecommons.org/licenses/by-sa/3.0/'),
    dict(file='dice2.png', role='encode', sampling='422',
         page='https://commons.wikimedia.org/wiki/File:PNG_transparency_demonstration_2.png',
         download='https://upload.wikimedia.org/wikipedia/commons/9/9a/PNG_transparency_demonstration_2.png',
         author='Daniel G., Ed g2s, Nguyễn Trí Minh Hoàng', license='CC BY-SA 3.0',
         license_url='https://creativecommons.org/licenses/by-sa/3.0/'),
    dict(file='color_circle.png', role='encode', sampling='420',
         page='https://commons.wikimedia.org/wiki/File:Color_circle_(RGB).png',
         download='https://upload.wikimedia.org/wikipedia/commons/9/98/Color_circle_%28RGB%29.png',
         author='Crossover1370 (SVG), LaundryPizza03 (rasterization)', license='CC BY-SA 4.0',
         license_url='https://creativecommons.org/licenses/by-sa/4.0/'),
    dict(file='hopper.jpg', role='decode',
         page='https://github.com/python-pillow/Pillow/blob/main/Tests/images/hopper.jpg',
         download='https://raw.githubusercontent.com/python-pillow/Pillow/main/Tests/images/hopper.jpg',
         source_project='Pillow', upstream_license_url='https://github.com/python-pillow/Pillow/blob/main/LICENSE'),
    dict(file='testorig.jpg', role='decode',
         page='https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/testimages/testorig.jpg',
         download='https://raw.githubusercontent.com/libjpeg-turbo/libjpeg-turbo/main/testimages/testorig.jpg',
         source_project='libjpeg-turbo', upstream_license_url='https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md'),
    dict(file='cat.jpg', role='decode restart',
         page='https://commons.wikimedia.org/wiki/File:Cat03.jpg',
         download='https://upload.wikimedia.org/wikipedia/commons/3/3a/Cat03.jpg',
         author='Fir0002/Flagstaffotos', license='GFDL 1.2',
         license_url='https://www.gnu.org/licenses/old-licenses/fdl-1.2.html'),
    dict(file='goldfish.jpg', role='decode restart',
         page='https://commons.wikimedia.org/wiki/File:Goldfish3.jpg',
         download='https://upload.wikimedia.org/wikipedia/commons/e/e9/Goldfish3.jpg',
         author='Heptagon (Commons attribution)', license='Public domain'),
]


def main():
    target_filter = sys.argv[1].lower() if len(sys.argv) > 1 else None
    OUTPUT.mkdir(parents=True, exist_ok=True)
    provenance = []
    for source in SOURCES:
        p = INPUT/source['file']
        with Image.open(p) as image:
            image.load()
            record = dict(source, dimensions=list(image.size), mode=image.mode,
                          bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())
        provenance.append(record)
    manifest = INPUT/'sources.json'
    if manifest.exists():
        assert [r['sha256'] for r in json.loads(manifest.read_text(encoding='utf-8'))] == [r['sha256'] for r in provenance]
    manifest.write_text(json.dumps(provenance, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    report = dict(date='2026-10-06', source_images_tested=5, additional_restart_images=2,
                  separation='No RTL-encoded JPEG is sent to the RTL decoder',
                  sources=provenance, encoder=[], decoder=[], rejected=[])
    for source in SOURCES:
        p = INPUT/source['file']
        stem = p.stem
        if target_filter and target_filter not in stem.lower() and target_filter not in p.name.lower():
            continue
        role = source['role']
        if role == 'encode':
            sampling = source['sampling']
            jpg = OUTPUT/f'{stem}_encoded.jpg'
            result = cli('jpeg_encode.py', p, jpg, '--quant', 16, '--sampling', sampling)
            with Image.open(p) as image:
                rgba = image.convert('RGBA')
                white = Image.new('RGBA', image.size, (255, 255, 255, 255))
                original = Image.alpha_composite(white, rgba).convert('RGB')
            with Image.open(jpg) as image:
                image.load()
                external = image.convert('RGB')
            external.save(OUTPUT/f'{stem}_external.png')
            assert external.size == original.size
            info = parse(jpg.read_bytes())
            stats = difference(external, original)
            record = dict(input=p.name, dimensions=list(original.size), sampling=sampling, quant=16,
                          status='PASS external libjpeg decode', cycles=int(re.search(r'cycles=(\d+)', result.stdout)[1]),
                          jpeg_bytes=jpg.stat().st_size, scan_bytes=len(info['scan']),
                          original_vs_external_rgb=stats)
            report['encoder'].append(record)
            print('ENCODER', p.name, json.dumps(stats), flush=True)
        elif role.startswith('decode'):
            # Only downloaded original JPEGs enter the RTL decoder.
            assert p.resolve().parent == INPUT.resolve()
            output = OUTPUT/f'{stem}_rtl.png'
            result = cli('jpeg_decode.py', p, output)
            with Image.open(output) as image:
                actual = image.convert('RGB')
            with Image.open(p) as image:
                image.load()
                external = image.convert('RGB')
            external.save(OUTPUT/f'{stem}_external.png')
            info = parse(p.read_bytes())
            assert actual.tobytes() == expected_rgb(info), f'{p.name}: reference mismatch'
            stats = difference(actual, external)
            report['decoder'].append(dict(input=p.name, dimensions=list(actual.size),
                sampling=('444', '422', '420')[info['format']],
                cycles=int(re.search(r'cycles=(\d+)', result.stdout)[1]),
                status='PASS integer reference pixel match and external comparison',
                integer_reference='RGB byte exact', rtl_vs_external_rgb=stats))
            print('DECODER', p.name, json.dumps(stats), flush=True)
        else:
            output = OUTPUT/f'{stem}_rejected.png'
            if output.exists():
                output.unlink()
            result = cli('jpeg_decode.py', p, output, success=False)
            assert not output.exists() and 'restart intervals unsupported' in result.stderr
            report['rejected'].append(dict(input=p.name, status='PASS', reason=result.stderr.strip()))
        (OUTPUT/'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print('PASS 5 additional internet images: 3 RTL encodes/external decodes, 2 independent RTL decodes; 2 additional Restart JPEG decodes', flush=True)


if __name__ == '__main__':
    main()
