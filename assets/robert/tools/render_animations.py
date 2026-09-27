"""Render real mesh-and-PNG motion previews. Outputs intermediate frames outside the package."""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT.parents[2] / '.tmp/robert-animation-frames'
FACE = ROOT / 'shared/faces/default'
SAMPLE = '--sample' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'skins/default/source/Robert.blend'))
rig = bpy.data.objects['Robert_Rig']
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 8
scene.cycles.use_denoising = True
scene.render.resolution_x = 420
scene.render.resolution_y = 450
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
camera = scene.camera
camera.location = (1.45, -7, 2.55)
camera.rotation_euler = (Vector((0, 0, 1.13)) - camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale = 2.85
node = bpy.data.materials['FaceScreen_Unlit'].node_tree.nodes['FACE_PNG_REPLACE_ME']
clips = json.loads((FACE / 'animations.json').read_text())['clips']
images = {}
for clip in clips.values():
    for frame in clip['frames']:
        if frame['png'] not in images:
            images[frame['png']] = bpy.data.images.load(str(FACE / frame['png']), check_existing=True)


def face_at(clip, seconds):
    frames = clips[clip]['frames']
    total = sum(f['duration_ms'] for f in frames)
    time = seconds * 1000
    if clips[clip]['loop']:
        time %= total
    for frame in frames:
        if time < frame['duration_ms']:
            return images[frame['png']]
        time -= frame['duration_ms']
    return images['neutral.png']


for name, label, duration, face in [('Standing','standing',6.0,'idle'),
                                     ('Wave','waving',3.2,'joy'), ('Talk','talking',4.8,'talk')]:
    for track in rig.animation_data.nla_tracks:
        track.mute = track.name != name
    folder = FRAMES / label
    folder.mkdir(parents=True, exist_ok=True)
    count = round(duration * 10)
    indices = [12] if SAMPLE else range(count)
    for i in indices:
        seconds = i / 10
        rig.update_tag(refresh={'OBJECT', 'DATA', 'TIME'})
        scene.frame_set(1 + i * 3)
        bpy.context.view_layer.update()
        rig.data.update_tag()
        rig.update_tag(refresh={'OBJECT', 'DATA', 'TIME'})
        bpy.context.view_layer.update()
        # A friendly smile throughout the greeting; body one-shot ends at neutral.
        node.image = images['cute_joy.png'] if name == 'Wave' and .35 < seconds < 2.65 else face_at(face, seconds)
        scene.render.filepath = str(folder / f'{i:03d}.png')
        bpy.ops.render.render(write_still=True)
        print('PREVIEW_FRAME', label, i + 1, count, flush=True)
print('ANIMATION_PREVIEW_FRAMES_COMPLETE', flush=True)
