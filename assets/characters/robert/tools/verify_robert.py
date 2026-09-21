import bpy, os, json, struct, math
from mathutils import Vector
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'validation')
PREVIEW=os.path.join(ROOT,'previews')
path=os.path.join(ROOT,'skins','default','model','Robert.glb')
with open(path,'rb') as f:
    magic,version,total=struct.unpack('<4sII',f.read(12));n,typ=struct.unpack('<II',f.read(8));g=json.loads(f.read(n))
assert magic==b'glTF' and version==2 and total==os.path.getsize(path)
names=[a['name'] for a in g['animations']]
assert set(names)=={'Idle','Wave','Nod','Celebrate'}
assert not any('targets' in p for m in g['meshes'] for p in m['primitives'])
assert any('KHR_materials_unlit' in m.get('extensions',{}) for m in g['materials'] if m['name']=='FaceScreen_Unlit')
assert g['images'] and all('bufferView' in im for im in g['images'])
assert len(g['skins'][0]['joints'])==24
assert all('JOINTS_0' in p['attributes'] and 'WEIGHTS_0' in p['attributes'] for m in g['meshes'] for p in m['primitives'])
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=path)
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
assert len(meshes)==2
assert all(math.isfinite(c) for o in meshes for v in o.data.vertices for c in v.co)
assert all(v.groups and abs(sum(g.weight for g in v.groups)-1)<.001 for o in meshes for v in o.data.vertices)
report={'glb_header_valid':True,'roundtrip_import':True,'mesh_objects':len(meshes),'all_vertices_weighted':True,'finite_coordinates':True,'animation_names':names,'joint_count':24,'size_bytes':total,'engine_device_tested':False}
with open(os.path.join(OUT,'validation.json'),'w') as f:json.dump(report,f,indent=2)
# Verify and render a waving pose from the editable source.
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'skins','default','source','Robert.blend'))
rig=bpy.data.objects['Robert_Rig']
body=bpy.data.objects['Robert_Body']
display=bpy.data.objects['FaceScreen']
assert len(display.data.vertices)==4 and not display.data.shape_keys
assert set(tuple(x.uv) for x in display.data.uv_layers.active.data)=={(0,0),(1,0),(1,1),(0,1)}
head_group=body.vertex_groups['head'].index
head=[body.matrix_world@v.co for v in body.data.vertices if any(g.group==head_group for g in v.groups)]
assert .374<max(v.y for v in head)<.377,'Head should retain the original raised enclosure and vents'
spine_group=body.vertex_groups['spine'].index
torso=[body.matrix_world@v.co for v in body.data.vertices if any(g.group==spine_group for g in v.groups)]
assert max(v.y for v in torso)<.196,'Torso battery cover should be nearly flush'
report.update({'face_mode':'png_texture','uv_full_range':True,'no_facial_morphs':True,'embedded_png':True,'flat_torso_battery_cover':True,'original_head_back_restored':True})
for side in ['L','R']:
    group=body.vertex_groups['foot.'+side].index
    shoe=[body.matrix_world@v.co for v in body.data.vertices if any(g.group==group for g in v.groups)]
    assert abs(min(v.z for v in shoe))<1e-5
    assert sum(abs(v.z)<1e-5 for v in shoe)>16,'Sole needs a broad planar base'
report['flat_soles_verified']=True
with open(os.path.join(OUT,'validation.json'),'w') as f:json.dump(report,f,indent=2)
for tr in rig.animation_data.nla_tracks:tr.mute=tr.name!='Wave'
bpy.context.scene.frame_set(37)
rig.update_tag(refresh={'OBJECT','DATA','TIME'})
bpy.context.view_layer.update()
hand=rig.matrix_world@rig.pose.bones['hand.L'].head
print('WAVE_HAND_POSITION',tuple(hand))
assert hand.z>rig.pose.bones['upper_arm.L'].head.z+.25,'Wave must raise hand above shoulder'
bpy.context.scene.render.resolution_x=700;bpy.context.scene.render.resolution_y=700
bpy.context.scene.cycles.samples=24;bpy.context.scene.render.filepath=os.path.join(PREVIEW,'Robert_wave.png')
bpy.ops.render.render(write_still=True)
for tr in rig.animation_data.nla_tracks:tr.mute=True
for bone in rig.pose.bones:bone.rotation_euler=(0,0,0);bone.location=(0,0,0)
bpy.context.scene.frame_set(1);rig.update_tag(refresh={'OBJECT','DATA','TIME'});bpy.context.view_layer.update()
cam=bpy.context.scene.camera;cam.location=(0,-6,1.65);cam.rotation_euler=(Vector((0,0,1.16))-cam.location).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.render.filepath=os.path.join(PREVIEW,'Robert_front.png');bpy.ops.render.render(write_still=True)
# Exercise the actual image binding with a second expression.
node=bpy.data.materials['FaceScreen_Unlit'].node_tree.nodes['FACE_PNG_REPLACE_ME']
node.image=bpy.data.images.load(os.path.join(ROOT,'shared','faces','default','happy.png'))
bpy.context.scene.render.filepath=os.path.join(PREVIEW,'Robert_happy.png');bpy.ops.render.render(write_still=True)
report['png_swap_rendered']=True
with open(os.path.join(OUT,'validation.json'),'w') as f:json.dump(report,f,indent=2)
print('VERIFIED',json.dumps(report))
