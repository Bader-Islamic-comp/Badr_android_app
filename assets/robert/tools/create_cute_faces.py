"""Add crisp, opaque 2:1 expression textures without changing the neutral face.

Requires Pillow. Safe to rerun after create_face_assets.py; merges named clips.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, math

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'shared/faces/default'
S=3;W=1024;H=512
BG=(8,24,31,255);MINT=(158,255,220,255);PEACH=(255,169,117,255)
LIGHT=(225,255,244,255)

def face(kind):
    im=Image.new('RGBA',(W*S,H*S),BG);d=ImageDraw.Draw(im)
    def ellipse(bounds,color=MINT):d.ellipse(tuple(round(v*S) for v in bounds),fill=color)
    def stroke(points,width=14,color=MINT):
        d.line([(round(x*S),round(y*S)) for x,y in points],fill=color,width=width*S,joint='curve')
        for x,y in [points[0],points[-1]]:ellipse((x-width/2,y-width/2,x+width/2,y+width/2),color)
    def arc(cx,cy,rx,ry,width=14,smile=False):
        stroke([(cx-rx+2*rx*i/48,cy+(1 if smile else -1)*ry*math.sin(pi*i/48)) for i in range(49)],width)
    def eye(cx,cy=200,width=46,height=108):
        ellipse((cx-width/2,cy-height/2,cx+width/2,cy+height/2))
        ellipse((cx-9,cy-height/2+10,cx+4,cy-height/2+23),LIGHT)
    def cheeks(strong=False):
        for x in [191,833]:
            ellipse((x-37,276,x+37,296 if not strong else 309),PEACH)
            if strong:
                for dx in [-15,6]:stroke([(x+dx,278),(x+dx-6,299)],4,(255,207,171,255))
    def star(cx,cy,r,color=MINT,points=4):
        pts=[]
        for i in range(points*2):
            a=-math.pi/2+i*math.pi/points;rr=r if i%2==0 else r*.40
            pts.append((round((cx+rr*math.cos(a))*S),round((cy+rr*math.sin(a))*S)))
        d.polygon(pts,fill=color)
    pi=math.pi
    if kind in ['joy','giggle_a','giggle_b','bashful']:
        for x in [255,769]:arc(x,222,50,38 if kind!='bashful' else 24)
        cheeks(kind=='bashful')
        if kind=='giggle_a':
            pts=[(410,330),(614,330)]+[(512+102*math.cos(i*pi/48),330+89*math.sin(i*pi/48)) for i in range(49)]
            d.polygon([(round(x*S),round(y*S)) for x,y in pts],fill=MINT)
            ellipse((477,377,549,410),PEACH)
        else:arc(512,344,130 if kind=='joy' else 105 if kind=='giggle_b' else 83,48 if kind!='bashful' else 30,16,True)
    elif kind=='wink':
        eye(255);arc(769,220,49,23,16);cheeks()
        stroke([(410+i*204/48,342+35*math.sin(i*pi/48)-i*.35) for i in range(49)],16)
        star(870,145,20,PEACH)
    elif kind=='curious':
        eye(255,213,40,91);eye(769,201,51,117)
        stroke([(221,139),(280,124)],11);arc(769,114,38,18,10)
        ellipse((489,339,539,393));ellipse((501,352,527,382),BG)
    elif kind=='wow':
        for x in [255,769]:eye(x,205,64,131)
        ellipse((471,327,553,426));ellipse((489,344,535,409),BG)
        star(134,145,24,PEACH);star(882,287,18,MINT)
    elif kind=='sleepy':
        for x in [255,769]:arc(x,225,50,14,14,True)
        stroke([(468+i*88/48,356+10*math.sin(i*2*pi/48)) for i in range(49)],12)
        for x,y,size in [(851,148,24),(900,92,34)]:
            stroke([(x,y),(x+size,y),(x,y+size),(x+size,y+size)],7,PEACH)
    elif kind=='starry':
        star(255,207,65,points=5);star(769,207,65,points=5)
        arc(512,335,130,61,16,True);cheeks()
        star(139,122,17,PEACH);star(885,123,17,PEACH)
    else:raise ValueError(kind)
    im.resize((W,H),Image.Resampling.LANCZOS).save(OUT/f'cute_{kind}.png')

for kind in ['joy','giggle_a','giggle_b','wink','curious','wow','sleepy','bashful','starry']:face(kind)
path=OUT/'animations.json';manifest=json.loads(path.read_text())
sequences={
 'joy':[('joy',1100)],
 'giggle':[('giggle_a',180),('giggle_b',180),('giggle_a',180),('giggle_b',180),('joy',450)],
 'wink':[('wink',650),('joy',300)],
 'curious':[('curious',1100)],
 'wow':[('wow',850),('joy',350)],
 'sleepy':[('sleepy',1300)],
 'bashful':[('bashful',1100)],
 'starry':[('starry',1000)]}
for name,frames in sequences.items():manifest['clips'][name]={'loop':False,'frames':[{'png':f'cute_{kind}.png','duration_ms':duration} for kind,duration in frames]}
path.write_text(json.dumps(manifest,indent=2))

# Labelled artwork sheet, not part of any runtime texture.
names=[('joy','Joy'),('giggle_a','Giggle'),('wink','Wink'),('curious','Curious'),('wow','Wow!'),('sleepy','Sleepy'),('bashful','Bashful'),('starry','Starry-eyed')]
sheet=Image.new('RGB',(1440,1740),(22,35,40));draw=ImageDraw.Draw(sheet)
font='C:/Windows/Fonts/segoeui.ttf';title=ImageFont.truetype(font,39);label=ImageFont.truetype(font,28);small=ImageFont.truetype(font,20)
draw.text((35,20),'ROBERT / CUTE EXPRESSIONS',font=title,fill=(232,245,233))
draw.text((38,76),'PNG screen faces  |  1024 × 512  |  Shared by every skin',font=small,fill=(158,209,191))
for i,(name,caption) in enumerate(names):
    x=25+(i%2)*720;y=126+(i//2)*397
    preview=Image.open(OUT/f'cute_{name}.png').convert('RGB').resize((670,335),Image.Resampling.LANCZOS)
    sheet.paste(preview,(x,y));draw.text((x+8,y+344),caption,font=label,fill=(232,245,233))
sheet.save(ROOT/'previews/cute_expressions.png')
print('CREATED 9 face PNGs, 8 expression clips and comparison sheet')
