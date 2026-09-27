"""Validate the portable catalogue, then bundle the current character only."""
from pathlib import Path
import json, hashlib, zipfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text())
catalogue=read(ROOT/'character.json')
assert catalogue['default_skin'] in catalogue['skins']
for id,rel in catalogue['skins'].items():
    skin=read(ROOT/rel);assert skin['id']==id
    for key in ['model','source','face_set']:assert (ROOT/skin[key]).is_file()
if len(catalogue['skins'])>1:
    skin_report=read(ROOT/'validation/skins_validation.json')
    validated={item['id']:item for item in skin_report['skins']}
    for id,rel in catalogue['skins'].items():
        if id=='default':continue
        item=validated[id];skin=read(ROOT/rel)
        assert item['glb_reimport_passed'] and item['rig_rest_contract_matches']
        assert hashlib.sha256((ROOT/skin['model']).read_bytes()).hexdigest()==item['glb_sha256']
facefile=ROOT/catalogue['default_face_set'];faces=read(facefile)
animation_report=read(ROOT/'validation/animations_validation.json')
animation_manifest=read(ROOT/'shared/animations.json')
assert set(animation_manifest['clips'])==set(read(ROOT/catalogue['rig_contract'])['clips'])
for clip in animation_manifest['clips'].values():
    assert clip['face_clip'] in faces['clips']
assert sum(frame['duration_ms'] for frame in faces['clips']['talk']['frames'])==4800
assert animation_report['same_animation_data_across_skins']
assert {item['skin'] for item in animation_report['skins']}==set(catalogue['skins'])
for item in animation_report['skins']:
    skin=read(ROOT/catalogue['skins'][item['skin']])
    assert item['loop_seams_passed'] and item['max_fixed_bone_error']<1e-5
    assert set(item['clips'])==set(animation_manifest['clips'])==set(skin['body_clips'])
    assert hashlib.sha256((ROOT/skin['model']).read_bytes()).hexdigest()==item['glb_sha256']
    assert hashlib.sha256((ROOT/skin['source']).read_bytes()).hexdigest()==item['blend_sha256']
for clip in faces['clips'].values():
    for frame in clip['frames']:
        assert frame['duration_ms']>0
        with Image.open(facefile.parent/frame['png']) as image:
            assert image.size==(1024,512);assert image.getextrema()[3]==(255,255)
report=read(ROOT/'validation/validation.json')
assert report['png_swap_rendered'] and report['flat_torso_battery_cover'] and report['original_head_back_restored'] and report['uv_full_range']
report['catalogue_paths_valid']=True;report['face_sequences_valid']=True
(ROOT/'validation/validation.json').write_text(json.dumps(report,indent=2))
files=[p for p in ROOT.rglob('*') if p.is_file() and p.suffix not in ['.log','.blend1','.pyc'] and p.name!='hashes.json']
hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(ROOT/'validation/hashes.json').write_text(json.dumps(hashes,indent=2))
files.append(ROOT/'validation/hashes.json')
zip_path=ROOT.parents[1]/'Robert_character.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
    for p in files:z.write(p,'robert/'+p.relative_to(ROOT).as_posix())
with zipfile.ZipFile(zip_path) as z:assert z.testzip() is None
print('PACKAGE_VERIFIED',zip_path,len(files),'files')
