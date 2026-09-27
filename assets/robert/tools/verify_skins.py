"""Blender verification for the six authored cosmetic outfits."""
import bpy, json, math, struct, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
IDS=['cowboy','astronaut','arab_thobe','casual','explorer','gardener']
contract=json.loads((ROOT/'shared/rig_contract.json').read_text())
reports=[]
for skin_id in IDS:
    folder=ROOT/'skins'/skin_id
    assert (folder/'skin.json').exists(),f'Missing requested skin: {skin_id}'
    manifest=json.loads((folder/'skin.json').read_text())
    assert manifest['id']==skin_id and manifest['rig_contract']==contract['id']
    model=ROOT/manifest['model'];source=ROOT/manifest['source']
    with model.open('rb') as f:
        magic,version,length=struct.unpack('<4sII',f.read(12));n,kind=struct.unpack('<II',f.read(8));g=json.loads(f.read(n))
    assert magic==b'glTF' and version==2 and length==model.stat().st_size
    assert {a['name'] for a in g['animations']}==set(contract['clips'])
    assert len(g['skins'][0]['joints'])==24
    assert any(n.get('name')=='FaceScreen' for n in g['nodes'])
    assert any(m['name']=='FaceScreen_Unlit' and 'KHR_materials_unlit' in m.get('extensions',{}) for m in g['materials'])
    assert all('JOINTS_0' in p['attributes'] and 'WEIGHTS_0' in p['attributes'] for m in g['meshes'] for p in m['primitives'])
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig=bpy.data.objects['Robert_Rig'];screen=bpy.data.objects['FaceScreen']
    assert len(rig.data.bones)==24
    for expected in contract['bones']:
        b=rig.data.bones[expected['name']]
        assert (b.parent.name if b.parent else None)==expected['parent']
        assert max(abs(b.matrix_local[i][j]-expected['rest_matrix'][i][j]) for i in range(4) for j in range(4))<1e-6
    assert set(tuple(x.uv) for x in screen.data.uv_layers.active.data)=={(0,0),(1,0),(1,1),(0,1)}
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
    assert len(meshes)==3,'Body, outfit and independent face must remain separate'
    outfit=bpy.data.objects['Robert_Outfit'];head_group=outfit.vertex_groups.get('head')
    hat_vertices=[outfit.matrix_world@v.co for v in outfit.data.vertices if head_group and any(g.group==head_group.index and g.weight>0 for g in v.groups)]
    if skin_id in ['astronaut','arab_thobe','casual']:
        assert not hat_vertices,f'{skin_id}: headgear must be absent'
    else:
        assert hat_vertices
        assert min(v.x for v in hat_vertices)>.10,'Mini hat must sit on one side'
        assert max(v.x for v in hat_vertices)-min(v.x for v in hat_vertices)<.60,'Hat must be miniature'
        assert min(v.z for v in hat_vertices)>1.87 and max(v.z for v in hat_vertices)<2.03
    tris=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    assert tris<30000,f'{skin_id}: triangle budget exceeded'
    for o in meshes:
        assert all(v.groups and abs(sum(g.weight for g in v.groups)-1)<.001 for v in o.data.vertices)
        assert all(math.isfinite(c) for v in o.data.vertices for c in v.co)
    samples=0
    for clip in contract['clips']:
        for t in rig.animation_data.nla_tracks:t.mute=t.name!=clip
        end=int(rig.animation_data.nla_tracks[clip].strips[0].frame_end)
        for frame in [1,(end+1)//2,end]:
            rig.update_tag(refresh={'OBJECT','DATA','TIME'});bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
            rig.data.update_tag();rig.update_tag(refresh={'OBJECT','DATA','TIME'});bpy.context.view_layer.update()
            dg=bpy.context.evaluated_depsgraph_get()
            erig=rig.evaluated_get(dg)
            transform=erig.matrix_world@erig.pose.bones['head'].matrix@rig.data.bones['head'].matrix_local.inverted()
            normal=(transform.to_3x3()@Vector((0,-1,0))).normalized()
            for x in [-.45,0,.45]:
                for dz in [-.21,0,.21]:
                    point=transform@Vector((x,-.340,1.5036+dz))
                    hit,loc,n,index,obj,matrix=bpy.context.scene.ray_cast(dg,point+normal*3,-normal,distance=3.01)
                    assert hit and obj.name=='FaceScreen',f'{skin_id} {clip} frame {frame}: face blocked by {obj.name if hit else "nothing"}'
            samples+=1
    # Independently re-import the exported interchange file.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(model))
    imported=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
    assert len(imported)==1 and len(imported[0].data.bones)==24
    reports.append({'id':skin_id,'triangles':tris,'bones':24,'rig_rest_contract_matches':True,'skin_weights_normalized':True,'png_face_uv_preserved':True,'face_visibility_pose_samples':samples,'glb_reimport_passed':True,'glb_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'unity_device_tested':False})
    print('SKIN_VERIFIED',skin_id,flush=True)
(ROOT/'validation/skins_validation.json').write_text(json.dumps({'skins':reports,'note':f'Face visibility is ray-tested in {len(contract["clips"])*3} sampled poses per skin. Additional dense motion checks are in animations_validation.json. Arbitrary locomotion and device tests remain pending.'},indent=2))
print('ALL_SIX_SKINS_VERIFIED',flush=True)
