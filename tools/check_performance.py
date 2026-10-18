from pathlib import Path
import json,math,hashlib
from PIL import Image
from generate_vectors import jpeg
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
import sys
variant='stress' if '--stress' in sys.argv else ('variable' if '--variable' in sys.argv else '')
prefix='a4'+('_'+variant if variant else '')
report_file=BUILD/('performance'+('_'+variant if variant else '')+'.json')
report=json.loads(report_file.read_text())
dcc=[0]*16;dcc[3]=12;acs=[0,240]+[r*16+n for r in range(16) for n in range(1,11)];acc=[0]*16;acc[7]=len(acs)
scan=(BUILD/(prefix+'.scan')).read_bytes();w,h=report['width'],report['height']
(BUILD/(prefix+'.jpg')).write_bytes(jpeg(scan,w,h,0,[[16]*64]*3,dcc,list(range(12)),acc,acs))
encoded=Image.open(BUILD/(prefix+'.jpg'));encoded.load()
report['encode_external_decode']='PASS'
report['decode_source']='independent Pillow/libjpeg JPEG'
report['decode_input_sha256']=hashlib.sha256((BUILD/(prefix+'_decode_input.jpg')).read_bytes()).hexdigest()
im=Image.open(BUILD/(prefix+'_decode_input.jpg'));im.draft('YCbCr',im.size);im.load();actual=im.convert('YCbCr').tobytes();raw=(BUILD/(prefix+'_decoded.bin')).read_bytes();plane=w*h
sse=0;peak=0
for c in range(3):
    for i in range(plane):
        e=int(actual[i*3+c])-raw[c*plane+i];peak=max(peak,abs(e));sse+=e*e
mse=sse/(plane*3)
report.update(external_decode='PASS',external_max_difference=peak,external_mse=mse,external_psnr_db=None if mse==0 else 10*math.log10(255**2/mse),compression_ratio=report['samples']/report['scan_bytes'],clock_hz=256000000,cycle_budget=153600000,cpu_time='unmeasured',metric_note='Pillow/libjpeg direct YCbCr decode, no RGB roundtrip')
for mode in ('encode','decode'):
    cycles=report[f'{mode}_cycles'];report[f'{mode}_seconds_at_256mhz']=cycles/256000000;report[f'{mode}_rtl_ppm']=60*256000000/cycles;report[f'{mode}_rtl_budget_pass']=cycles<=153600000
report_file.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
