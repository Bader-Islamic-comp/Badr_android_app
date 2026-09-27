import bpy, sys, os

out = sys.argv[sys.argv.index('--') + 1]
# Robert_Outfit exists only in outfit skins: a separate garment mesh skinned to
# the same rig. The default skin has none, and nothing else is exported.
keep = {'FaceScreen', 'Robert_Body', 'Robert_Rig', 'Robert_Outfit'}

# The canonical scene carries a camera, lights and a studio floor for renders.
# The room builder creates its own, so export the character only.
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    o.select_set(o.name in keep)
bpy.context.view_layer.objects.active = bpy.data.objects['Robert_Rig']

bpy.ops.export_scene.fbx(
    filepath=out,
    use_selection=True,
    object_types={'ARMATURE', 'MESH'},
    use_mesh_modifiers=True,
    mesh_smooth_type='FACE',
    add_leaf_bones=False,
    primary_bone_axis='Y',
    secondary_bone_axis='X',
    bake_anim=True,
    bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=True,
    bake_anim_force_startend_keying=True,
    axis_forward='-Z',
    axis_up='Y',
    path_mode='AUTO',
    embed_textures=False,
)
print("FBX_OK", out, os.path.getsize(out))
