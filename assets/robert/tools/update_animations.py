"""Refresh animation data on every existing model, preserving the authored geometry."""
import bpy, hashlib, json, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from author_animations import author, CLIPS, manifest


def geometry_fingerprint():
    data = {}
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH' and any(m.type == 'ARMATURE' for m in obj.modifiers):
            data[obj.name] = {
                'vertices': [(list(v.co), [(g.group, g.weight) for g in v.groups]) for v in obj.data.vertices],
                'faces': [list(p.vertices) for p in obj.data.polygons],
                'uv': [list(x.uv) for x in obj.data.uv_layers.active.data] if obj.data.uv_layers.active else [],
                'materials': [m.name for m in obj.data.materials],
            }
    rig = bpy.data.objects['Robert_Rig']
    data['rest_bones'] = {b.name: [list(row) for row in b.matrix_local] for b in rig.data.bones}
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


catalogue = json.loads((ROOT / 'character.json').read_text())
# Recover only missing authored skin files from the previously delivered, hash-checked package.
missing = [f'skins/{skin}/{suffix}' for skin in catalogue['skins']
           for suffix in ['skin.json', 'model/Robert.glb', 'source/Robert.blend']
           if not (ROOT / f'skins/{skin}/{suffix}').exists()]
if missing:
    with zipfile.ZipFile(ROOT.parents[1] / 'Robert_character.zip') as archive:
        hashes = json.loads(archive.read('robert/validation/hashes.json'))
        for relative in missing:
            target = ROOT / relative
            data = archive.read('robert/' + relative)
            assert hashlib.sha256(data).hexdigest() == hashes[relative]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            print('RESTORED_AUTHORED_ASSET', relative, flush=True)

reports = []
for skin, manifest_path in catalogue['skins'].items():
    settings = json.loads((ROOT / manifest_path).read_text())
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / settings['source']))
    bpy.context.preferences.filepaths.save_version = 0
    before = geometry_fingerprint()
    rig = bpy.data.objects['Robert_Rig']
    author(rig)
    assert geometry_fingerprint() == before, 'Animation update must not alter geometry/rest pose'
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH' and any(m.type == 'ARMATURE' for m in obj.modifiers):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(ROOT / settings['model']), use_selection=True,
        export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS',
        export_force_sampling=True, export_anim_slide_to_zero=True, export_skins=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / settings['source']))
    settings['body_clips'] = list(CLIPS)
    (ROOT / manifest_path).write_text(json.dumps(settings, indent=2))
    reports.append({'skin': skin, 'geometry_and_rest_unchanged': True, 'geometry_sha256': before})
    print('ANIMATIONS_UPDATED', skin, flush=True)

contract_path = ROOT / 'shared/rig_contract.json'
contract = json.loads(contract_path.read_text())
contract['clips'] = list(CLIPS)
contract_path.write_text(json.dumps(contract, indent=2))
template_path = ROOT / 'skins/_template/skin.template.json'
template = json.loads(template_path.read_text())
template['body_clips'] = list(CLIPS)
template_path.write_text(json.dumps(template, indent=2))
stats_path = ROOT / 'validation/model_stats.json'
stats = json.loads(stats_path.read_text())
stats.update({'clips': list(CLIPS), 'animation_revision': 2})
stats_path.write_text(json.dumps(stats, indent=2))
(ROOT / 'shared/animations.json').write_text(json.dumps(manifest(), indent=2))
(ROOT / 'validation/animation_update.json').write_text(json.dumps({'skins': reports}, indent=2))
print('ALL_SEVEN_ANIMATIONS_UPDATED', flush=True)
