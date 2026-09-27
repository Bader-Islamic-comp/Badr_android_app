"""Check exported clip timing, stationary feet, seamless loops and source poses."""
import bpy, hashlib, json, math, struct
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {'Standing': 6.0, 'Idle': 6.0, 'Wave': 3.2, 'Talk': 4.8,
            'Nod': 1.6, 'Celebrate': 2.4}
LOOPS = {'Standing', 'Idle', 'Talk'}
FIXED = ['root'] + [f'{part}.{side}' for side in ['L', 'R']
                    for part in ['thigh', 'shin', 'foot']]


def read_glb(path):
    data = path.read_bytes()
    size = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20 + size]), data[28 + size:]


def accessor(g, binary, index):
    a = g['accessors'][index]
    v = g['bufferViews'][a['bufferView']]
    assert a['componentType'] == 5126
    width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
    start = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', width * 4)
    return [struct.unpack_from('<' + 'f' * width, binary, start + i * stride)
            for i in range(a['count'])]


def evaluate_frame(rig, scene, frame):
    rig.update_tag(refresh={'OBJECT', 'DATA', 'TIME'})
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    # After loading a file and switching NLA tracks, Blender 5.2 can update
    # animated properties without recomputing pose matrices in the same pass.
    # Explicitly invalidate armature evaluation after properties are current.
    rig.data.update_tag()
    rig.update_tag(refresh={'OBJECT', 'DATA', 'TIME'})
    bpy.context.view_layer.update()
    graph = bpy.context.evaluated_depsgraph_get()
    return graph, rig.evaluated_get(graph)


reports = []
reference_channels = None
catalogue = json.loads((ROOT / 'character.json').read_text())
for skin, manifest_path in catalogue['skins'].items():
    manifest = json.loads((ROOT / manifest_path).read_text())
    path = ROOT / manifest['model']
    g, binary = read_glb(path)
    assert {a['name'] for a in g['animations']} == set(EXPECTED), f'{skin}: missing body clips'
    assert set(manifest['body_clips']) == set(EXPECTED)
    channels = {}
    for animation in g['animations']:
        name = animation['name']
        channels[name] = {}
        for channel in animation['channels']:
            target = channel['target']
            bone = g['nodes'][target['node']]['name']
            sampler = animation['samplers'][channel['sampler']]
            times = accessor(g, binary, sampler['input'])
            values = accessor(g, binary, sampler['output'])
            assert abs(times[0][0]) < 1e-6
            assert abs(times[-1][0] - EXPECTED[name]) < 1e-5, (skin, name, times[-1])
            assert all(math.isfinite(v) for row in values for v in row)
            if bone in FIXED or name in LOOPS:
                rows = values if bone in FIXED else [values[-1]]
                assert max(abs(x-y) for row in rows for x,y in zip(row, values[0])) < 1e-5, (skin, name, bone)
            channels[name][bone + '/' + target['path']] = (times, values)
    if reference_channels is None:
        reference_channels = channels
    else:
        assert channels == reference_channels, f'{skin}: clips differ from default'

    bpy.ops.wm.open_mainfile(filepath=str(ROOT / manifest['source']))
    rig = bpy.data.objects['Robert_Rig']
    scene = bpy.context.scene
    assert scene.render.fps == 30
    foot_error = 0.0
    visibility_samples = 0
    for name, duration in EXPECTED.items():
        for track in rig.animation_data.nla_tracks:
            track.mute = track.name != name
        end = round(duration * 30) + 1
        samples = {}
        for frame in sorted(set(list(range(1, end + 1, 6)) + [end, 2, end - 1])):
            dg, erig = evaluate_frame(rig, scene, frame)
            samples[frame] = {p.name: p.matrix.copy() for p in erig.pose.bones}
            for bone in FIXED:
                delta = max(abs(samples[frame][bone][i][j] - rig.data.bones[bone].matrix_local[i][j])
                            for i in range(4) for j in range(4))
                foot_error = max(foot_error, delta)
                assert delta < 1e-5, (skin, name, frame, 'foot/root moved', bone, delta)
            transform = erig.matrix_world @ erig.pose.bones['head'].matrix @ rig.data.bones['head'].matrix_local.inverted()
            normal = (transform.to_3x3() @ Vector((0, -1, 0))).normalized()
            for x in [-.45, 0, .45]:
                for dz in [-.21, 0, .21]:
                    point = transform @ Vector((x, -.340, 1.5036 + dz))
                    hit, _, _, _, obj, _ = scene.ray_cast(dg, point + normal * 3, -normal, distance=3.01)
                    assert hit and obj.name == 'FaceScreen', (skin, name, frame, 'screen obscured', obj.name if hit else None)
            visibility_samples += 1
        if name in LOOPS:
            for bone in samples[1]:
                loop_error = max(abs(samples[1][bone][i][j] - samples[end][bone][i][j])
                                 for i in range(4) for j in range(4))
                assert loop_error < 1e-5, (skin, name, bone, 'loop pose', loop_error, list(samples[1][bone]), list(samples[end][bone]))
                # One-frame finite differences at either side of the loop seam.
                seam_error = max(abs((samples[2][bone][i][j] - samples[1][bone][i][j]) -
                                     (samples[end][bone][i][j] - samples[end-1][bone][i][j]))
                                 for i in range(4) for j in range(4))
                assert seam_error < .002, (skin, name, bone, 'velocity seam', seam_error)
        if name == 'Wave':
            _, erig = evaluate_frame(rig, scene, 37)
            assert erig.pose.bones['hand.L'].head.z > erig.pose.bones['upper_arm.L'].head.z + .25
    reports.append({'skin': skin, 'clips': EXPECTED, 'loop_seams_passed': True,
                    'max_fixed_bone_error': foot_error, 'face_visibility_pose_samples': visibility_samples,
                    'glb_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'blend_sha256': hashlib.sha256((ROOT / manifest['source']).read_bytes()).hexdigest()})
    print('ANIMATIONS_VERIFIED', skin, flush=True)

(ROOT / 'validation/animations_validation.json').write_text(json.dumps({
    'skins': reports, 'same_animation_data_across_skins': True, 'unity_tested': False}, indent=2))
print('ALL_ANIMATIONS_VERIFIED', flush=True)
