"""Assemble the rendered motion frames as shareable, correctly timed GIFs."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT.parents[2] / '.tmp/robert-animation-frames'
OUT = ROOT / 'previews'
font = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 23)
small = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 17)
clips = {}
for label, title, count in [('standing','Standing / 6 s',60),('waving','Wave / 3.2 s',32),('talking','Talking / 4.8 s',48)]:
    frames = [Image.open(FRAMES / label / f'{i:03d}.png').convert('RGB') for i in range(count)]
    clips[label] = frames
    frames[0].save(OUT / f'Robert_{label}.gif', save_all=True, append_images=frames[1:], duration=100, loop=0, disposal=2)

collection = []
for i in range(60):
    sheet = Image.new('RGB', (1260, 520), (22, 35, 40))
    draw = ImageDraw.Draw(sheet)
    for column, (label, title) in enumerate([('standing','STANDING'),('waving','FRIENDLY WAVE'),('talking','TALKING')]):
        frames = clips[label]
        index = min(i, len(frames)-1) if label == 'waving' else i % len(frames)
        sheet.paste(frames[index], (column*420, 0))
        draw.text((column*420+22, 457), title, font=font, fill=(236,241,225))
        draw.text((column*420+22, 489), 'One-shot greeting' if label=='waving' else 'Gentle loop', font=small, fill=(149,192,180))
    collection.append(sheet)
collection[0].save(OUT / 'animation_collection.gif', save_all=True, append_images=collection[1:], duration=100, loop=0, disposal=2)
collection[12].save(OUT / 'animation_collection.png')
for label, frames in clips.items():
    with Image.open(OUT / f'Robert_{label}.gif') as result:
        assert result.n_frames == len(frames)
        assert result.info['duration'] == 100
print('ANIMATION_GIFS_VERIFIED', {k:len(v) for k,v in clips.items()})
