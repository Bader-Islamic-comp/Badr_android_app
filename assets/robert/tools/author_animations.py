"""Reusable Robert body animation authoring. Meshes and bone rest transforms are untouched."""
import math
import bpy

FPS = 30
CLIPS = {
    'Standing': {'duration_seconds': 6.0, 'loop': True, 'face_clip': 'idle'},
    'Idle': {'duration_seconds': 6.0, 'loop': True, 'face_clip': 'idle', 'alias_of': 'Standing'},
    'Wave': {'duration_seconds': 3.2, 'loop': False, 'face_clip': 'joy'},
    'Talk': {'duration_seconds': 4.8, 'loop': True, 'face_clip': 'talk'},
    'Nod': {'duration_seconds': 1.6, 'loop': False, 'face_clip': 'idle'},
    'Celebrate': {'duration_seconds': 2.4, 'loop': False, 'face_clip': 'joy'},
}
PI = math.pi
sin = math.sin


def reset_pose(rig):
    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def pulse(t, start, end):
    if not start < t < end:
        return 0.0
    return sin(PI * (t - start) / (end - start)) ** 2


def standing(b, t):
    a = 2 * PI * t
    b['spine'].rotation_euler = (.004 * sin(a), 0, .007 * sin(a))
    b['head'].rotation_euler = (.012 * sin(2*a), .025 * sin(a), -.014 * sin(a))
    for side, sign in [('L', 1), ('R', -1)]:
        b[f'upper_arm.{side}'].rotation_euler.z = sign * .018 * sin(a)
        b[f'forearm.{side}'].rotation_euler.z = sign * .009 * sin(2*a)
        b[f'hand.{side}'].rotation_euler.x = .012 * sin(a)
    b['antenna1'].rotation_euler.z = .018 * (sin(2*a - .3) - sin(-.3))
    b['antenna-1'].rotation_euler.z = .014 * (sin(2*a - .5) - sin(-.5))


def wave(b, t):
    # Zero-speed easing into a held greeting, then a soft return to rest.
    e = smooth(t / .23) * smooth((1 - t) / .22)
    w = pulse(t, .21, .80)
    b['upper_arm.L'].rotation_euler.z = 1.60 * e
    b['forearm.L'].rotation_euler.z = .10 * e + .035 * sin(10 * PI * t) * w
    b['hand.L'].rotation_euler.z = .26 * sin(10 * PI * (t - .21)) * w
    b['upper_arm.R'].rotation_euler.z = -.035 * e
    b['head'].rotation_euler = (.018 * e, -.025 * e, -.035 * e)
    b['spine'].rotation_euler.z = -.012 * e
    b['antenna1'].rotation_euler.z = .027 * sin(6 * PI * t) * e
    b['antenna-1'].rotation_euler.z = .020 * sin(6 * PI * t) * e


def talk(b, t):
    a = 2 * PI * t
    left = pulse(t, .04, .46)
    right = pulse(t, .48, .94)
    b['spine'].rotation_euler = (.006 * sin(2*a), 0, .010 * sin(a))
    b['head'].rotation_euler = (.037 * sin(4*a), .024 * sin(a), -.018 * sin(2*a))
    for side, sign, gesture in [('L', 1, left), ('R', -1, right)]:
        b[f'upper_arm.{side}'].rotation_euler = (-.08 * gesture, 0, sign * .24 * gesture)
        b[f'forearm.{side}'].rotation_euler = (-.07 * gesture, 0, sign * .10 * gesture)
        b[f'hand.{side}'].rotation_euler = (0, .08 * gesture, sign * .05 * gesture)
    b['antenna1'].rotation_euler.z = .018 * sin(4*a)
    b['antenna-1'].rotation_euler.z = -.014 * sin(4*a)


def nod(b, t):
    b['head'].rotation_euler.x = .20 * sin(4 * PI * t) * sin(PI * t)


def celebrate(b, t):
    e = sin(PI*t)
    b['upper_arm.L'].rotation_euler.z = 1.55 * e
    b['upper_arm.R'].rotation_euler.z = -1.55 * e
    b['spine'].rotation_euler.z = .07 * sin(6*PI*t) * e


def author(rig):
    functions = {'Standing': standing, 'Idle': standing, 'Wave': wave,
                 'Talk': talk, 'Nod': nod, 'Celebrate': celebrate}
    rig.animation_data_clear()
    for action in list(bpy.data.actions):
        if action.name in CLIPS and action.users == 0:
            bpy.data.actions.remove(action)
    rig.animation_data_create()
    for name, settings in CLIPS.items():
        end = round(settings['duration_seconds'] * FPS) + 1
        for frame in range(1, end + 1):
            reset_pose(rig)
            functions[name](rig.pose.bones, (frame - 1) / (end - 1))
            for bone in rig.pose.bones:
                bone.keyframe_insert('rotation_euler', frame=frame)
                bone.keyframe_insert('location', frame=frame)
        action = rig.animation_data.action
        action.name = name
        action['loop'] = settings['loop']
        # Linear per-frame samples avoid overshoot and match baked glTF interpolation.
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.action_frame_start = 1
        strip.action_frame_end = end
        # Hold endpoints so Blender evaluates the exact final pose when scrubbing
        # the exclusive strip boundary instead of retaining the previous sample.
        strip.extrapolation = 'HOLD'
        rig.animation_data.action = None
        track.mute = True
    reset_pose(rig)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = 181
    scene.frame_set(1)
    rig.update_tag(refresh={'OBJECT', 'DATA', 'TIME'})
    bpy.context.view_layer.update()


def manifest():
    return {'schema_version': 1, 'rig_contract': 'robert-rig-v1', 'fps': FPS,
            'root_motion': False, 'default_body_clip': 'Standing',
            'face_set': 'shared/faces/default/animations.json',
            'transition_seconds': .2, 'one_shot_return': 'Standing',
            'clips': CLIPS, 'note': 'Reference metadata; configure engine playback separately. Talk is decorative, not audio lip-sync.'}
