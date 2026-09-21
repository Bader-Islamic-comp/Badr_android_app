"""Generate editable, deterministic 2D face PNGs. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw
import json, math
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'shared/faces/default';OUT.mkdir(parents=True,exist_ok=True)
S=2;W,H=1024,512;BG=(8,24,31,255);INK=(158,255,220,255)
def make(name,eyes='open',mouth='smile'):
    im=Image.new('RGBA',(W*S,H*S),BG);d=ImageDraw.Draw(im)
    def ellipse(box):d.ellipse(tuple(int(v*S) for v in box),fill=INK)
    def line(points,width=12):d.line([(int(x*S),int(y*S)) for x,y in points],fill=INK,width=width*S,joint='curve')
    for x in [145,879]:
        if eyes=='closed':line([(x-24,165),(x+24,165)],12)
        elif eyes=='happy':line([(x-24+i*2,172-25*math.sin(i/24*math.pi)) for i in range(25)],10)
        else:ellipse((x-16,108,x+16,209))
    if mouth=='smile':line([(200+i*624/64,312+65*math.sin(i/64*math.pi)) for i in range(65)],12)
    elif mouth=='open':ellipse((310,306,714,420))
    elif mouth=='round':ellipse((458,290,566,418))
    elif mouth=='wide':ellipse((242,322,782,386))
    im.resize((W,H),Image.Resampling.LANCZOS).save(OUT/(name+'.png'))
for args in [('neutral',),('blink','closed'),('happy','happy'),('talk_open','open','open'),('talk_round','open','round'),('talk_wide','open','wide'),('talk_blink','closed','open'),('surprised','open','round')]:make(*args)
Image.new('RGBA',(W,H),BG).save(OUT/'blank_template.png')
clips={
 'idle':{'loop':True,'frames':[('neutral',2800),('blink',90),('neutral',1600)]},
 'blink':{'loop':False,'frames':[('blink',100),('neutral',120)]},
 'talk':{'loop':True,'frames':[('neutral',90),('talk_open',120),('talk_round',100),('talk_wide',110),('talk_open',100),('talk_blink',80),('neutral',100)]},
 'happy':{'loop':False,'frames':[('happy',1000)]},
 'surprised':{'loop':False,'frames':[('surprised',800)]}}
for clip in clips.values():clip['frames']=[{'png':n+'.png','duration_ms':t} for n,t in clip['frames']]
(OUT/'animations.json').write_text(json.dumps({'schema_version':1,'path_base':'this_file_directory','default_png':'neutral.png','resolution':[W,H],'one_shot_completion':'return_to_default_png','clips':clips},indent=2))
print('Created 9 PNGs and face animation timing manifest')
