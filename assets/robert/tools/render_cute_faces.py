"""Render two actual PNG swaps on Robert and validate the added face assets."""
import bpy, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'skins/default/source/Robert.blend'))
node=bpy.data.materials['FaceScreen_Unlit'].node_tree.nodes['FACE_PNG_REPLACE_ME']
scene=bpy.context.scene;scene.render.resolution_x=800;scene.render.resolution_y=800;scene.cycles.samples=24
assert bpy.data.objects['FaceScreen'].data.uv_layers.active is not None
faces=ROOT/'shared/faces/default';manifest=json.loads((faces/'animations.json').read_text())
names=['joy','giggle','wink','curious','wow','sleepy','bashful','starry']
for name in names:
    assert name in manifest['clips'] and not manifest['clips'][name]['loop']
    for frame in manifest['clips'][name]['frames']:
        assert frame['duration_ms']>0 and (faces/frame['png']).exists()
for name in ['joy','wink']:
    node.image=bpy.data.images.load(str(faces/f'cute_{name}.png'))
    assert list(node.image.size)==[1024,512]
    scene.render.filepath=str(ROOT/f'previews/Robert_cute_{name}.png')
    bpy.ops.render.render(write_still=True)
report={'clips':names,'image_size':[1024,512],'rendered_on_model':['joy','wink'],'default_model_modified':False,'unity_runtime_tested':False}
(ROOT/'validation/cute_faces_validation.json').write_text(json.dumps(report,indent=2))
print('CUTE_FACES_VERIFIED')
