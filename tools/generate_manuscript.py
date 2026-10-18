"""Original mock manuscript. Referenced HP/Brother thumbnails were not retrieved."""
from pathlib import Path
from PIL import Image,ImageDraw
import random,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/data'
w,h=2480,3508;rng=random.Random(20261005)
im=Image.new('RGB',(w,h),'white');d=ImageDraw.Draw(im)
d.rectangle((140,100,2340,210),fill=(30,65,110))
for column in range(2):
    left=140+column*1140
    for line in range(65):
        y=280+line*25
        for word in range(14):
            x=left+word*72;length=rng.randrange(20,65)
            d.rectangle((x,y,x+length,y+8),fill=(25,25,25))
for row in range(13):d.line((140,2100+row*45,1450,2100+row*45),fill=(60,60,60),width=3)
for col in range(6):d.line((140+col*262,2100,140+col*262,2640),fill=(60,60,60),width=3)
for col in range(6):d.rectangle((152+col*210,2810-col*70,310+col*210,3270),fill=(40+col*28,150-col*15,80+col*20))
# A seeded, textured color region provides non-text content; this is not a source photograph.
patch=Image.frombytes('RGB',(740,930),bytes(rng.randrange(256) for _ in range(740*930*3)))
im.paste(patch,(1600,2250));im.save(OUT/'a4_manuscript.png')
ycc=im.convert('YCbCr');planes=ycc.split();(OUT/'a4_planar.bin').write_bytes(b''.join(p.tobytes() for p in planes))
(OUT/'a4_conditions.json').write_text(json.dumps(dict(width=w,height=h,format='4:4:4',seed=20261005,quantization=16,composition='original procedural text, table, bar chart, seeded color texture',reference_thumbnails='not retrieved or viewed'),indent=2)+'\n')
print('generated original A4 mock, planar samples=',w*h*3)
