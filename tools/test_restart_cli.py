"""Restart decode CLI interoperability; no RTL encoder output is used as input."""
from pathlib import Path
import json
from PIL import Image
from jpeg_tool import ROOT
from jpeg_cpu import parse
from test_jpeg_tool import expected_rgb
from test_internet_images import cli, difference

OUTPUT=ROOT/'tests/results/restart'

def check(source, stem):
    info=parse(source.read_bytes())
    target=OUTPUT/f'{stem}_rtl.png'
    cli('jpeg_decode.py',source,target)
    with Image.open(target) as im: actual=im.convert('RGB')
    with Image.open(source) as im:
        im.load();external=im.convert('RGB')
    external.save(OUTPUT/f'{stem}_external.png')
    assert actual.tobytes()==expected_rgb(info), f'{stem}: reference mismatch'
    delta=difference(actual,external)
    record=dict(input=str(source.relative_to(ROOT)),dimensions=list(actual.size),
                interval=info['restart_interval'],sampling=('444','422','420')[info['format']],
                status='PASS',integer_reference='RGB byte exact',rtl_vs_external_rgb=delta)
    print(stem,json.dumps(record),flush=True)
    return record

def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    records=[]
    for name in ('fmt0_ri1','fmt1_ri2','fmt2_ri3','exact_final2','marker_fill','flat','marker_4k'):
        records.append(check(ROOT/f'tests/data/restart/{name}.jpg',name))
    for name in ('cat','goldfish'):
        records.append(check(ROOT/f'tests/data/internet_five/{name}.jpg',name))
        (OUTPUT/'report.json').write_text(json.dumps(records,indent=2)+'\n')
    manifest=(ROOT/'tests/data/restart/manifest.txt').read_text().splitlines()
    count=0
    for line in manifest:
        name,_,_,_,_,_,error=line.split()
        if error=='0':continue
        output=OUTPUT/f'{name}_rejected.png'
        if output.exists():output.unlink()
        cli('jpeg_decode.py',ROOT/f'tests/data/restart/{name}.jpg',output,success=False)
        assert not output.exists(),name
        count+=1
    print(f'PASS restart CLI: {len(records)} independent JPEGs, pixel-reference match, external comparison; {count} malformed rejections',flush=True)
if __name__=='__main__':main()
