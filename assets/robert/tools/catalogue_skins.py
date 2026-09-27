"""Register validated local outfit assets and create a visual contact sheet.

This edits the art catalogue only, never inventory or bridge authorization.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
IDS=['cowboy','astronaut','arab_thobe','casual','explorer','gardener']
LABELS=['Cowboy','Astronaut','Arab thobe','Casual','Explorer','Gardener']
reports=json.loads((ROOT/'validation/skins_validation.json').read_text())['skins']
assert {x['id'] for x in reports}==set(IDS)
for item in reports:assert item['glb_reimport_passed'] and item['rig_rest_contract_matches']
catalogue=json.loads((ROOT/'character.json').read_text())
assert catalogue['default_skin']=='default'
for skin in IDS:
    manifest=ROOT/f'skins/{skin}/skin.json'
    data=json.loads(manifest.read_text())
    for field in ['model','source','preview','face_set']:assert (ROOT/data[field]).is_file()
    catalogue['skins'][skin]=f'skins/{skin}/skin.json'
(ROOT/'character.json').write_text(json.dumps(catalogue,indent=2))
fontfile='C:/Windows/Fonts/segoeui.ttf'
title=ImageFont.truetype(fontfile,44);label=ImageFont.truetype(fontfile,28);small=ImageFont.truetype(fontfile,21)
sheet=Image.new('RGB',(1800,1640),(22,35,40));draw=ImageDraw.Draw(sheet)
draw.text((45,20),'ROBERT  /  THE OUTFIT COLLECTION',font=title,fill=(236,241,225))
draw.text((47,78),'Six rigged skins • Shared PNG face • Original proportions',font=small,fill=(149,192,180))
for i,(skin,name) in enumerate(zip(IDS,LABELS)):
    x=(i%3)*600;y=125+(i//3)*750
    picture=Image.open(ROOT/f'previews/{skin}.png').convert('RGB').resize((580,653),Image.Resampling.LANCZOS)
    sheet.paste(picture,(x+10,y))
    draw.text((x+28,y+665),name,font=label,fill=(236,241,225))
    draw.text((x+28,y+701),skin,font=small,fill=(149,192,180))
sheet.save(ROOT/'previews/skin_collection.png')
print('SIX_SKINS_REGISTERED; DEFAULT_UNCHANGED; CONTACT_SHEET_CREATED')
