import bpy, bmesh, math, json, os
from mathutils import Vector
from math import sin, cos, pi

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'skins','default','model')
SOURCE=os.path.join(ROOT,'skins','default','source')
PREVIEW=os.path.join(ROOT,'previews')
VALIDATION=os.path.join(ROOT,'validation')
for folder in [OUT,SOURCE,PREVIEW,VALIDATION]:os.makedirs(folder,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(name,color,metal=0,rough=.4,emission=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emission
    return m
ivory=mat('01 • Porcelain shell',(.82,.89,.82),.15)
teal=mat('02 • Petrol teal',(.025,.23,.25),.3)
dark=mat('03 • Graphite joints',(.025,.047,.059),.3)
screen=mat('04 • Midnight display',(.005,.018,.026),.1,.23)
glow=mat('05 • Mint pixels',(.38,1,.77),0,.3,2)
orange=mat('06 • Tangerine controls',(1,.28,.055),.15)
keymat=mat('07 • Keyboard keys',(.48,.66,.64),.2)
parts=[]
def finish(o,name,m,bone):
    o.name=name; o.data.materials.append(m)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bone:
        vg=o.vertex_groups.new(name=bone); vg.add(list(range(len(o.data.vertices))),1,'REPLACE'); parts.append(o)
    return o
def box(name,loc,scale,m,bone,bevel=.06):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=o.modifiers.new('Soft manufactured corners','BEVEL'); mod.width=bevel; mod.segments=3
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Corner normals','WEIGHTED_NORMAL'); bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,m,bone)
def ell(name,loc,scale,m,bone):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,radius=1,location=loc)
    o=bpy.context.object; o.scale=scale
    for p in o.data.polygons:p.use_smooth=True
    return finish(o,name,m,bone)
def rod(name,a,b,r,m,bone,r2=None):
    a,b=Vector(a),Vector(b); d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)/2)
    o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    for p in o.data.polygons:p.use_smooth=True
    return finish(o,name,m,bone)
def tube(name,pts,r,m,bone):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.bevel_depth=r; c.bevel_resolution=2; c.resolution_u=8; c.use_fill_caps=True
    s=c.splines.new('BEZIER'); s.bezier_points.add(len(pts)-1)
    for p,co in zip(s.bezier_points,pts):p.co=co; p.handle_left_type='AUTO'; p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(o); bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); o=bpy.context.object
    finish(o,name,m,bone); o.select_set(False); return o

# Z up, front is -Y; character is 2.4 m including antennae.
box('Body', (0,0,1.01),(.58,.38,.75),ivory,'spine',.085)
box('Chest inset',(0,-.203,1.18),(.47,.035,.31),teal,'spine',.035)
box('Keyboard recess',(0,-.211,.85),(.46,.035,.27),dark,'spine',.025)
for row in range(3):
    for col in range(5):box('Key',(-.167+col*.083,-.239,.77+row*.075),(.064,.025,.048),keymat,'spine',.009)
for x in [-.18,-.07]:ell('Indicator',(x,-.239,1.27),(.023,.012,.023),glow,'spine')
box('Cross button vertical',(-.145,-.246,1.14),(.042,.028,.105),orange,'spine',.009)
box('Cross button horizontal',(-.145,-.25,1.14),(.105,.028,.042),orange,'spine',.009)
rod('Dial rim',(.13,-.235,1.18),(.13,-.269,1.18),.103,ivory,'spine')
rod('Dial face',(.13,-.27,1.18),(.13,-.288,1.18),.078,dark,'spine')
rod('Dial pointer',(.11,-.307,1.16),(.176,-.307,1.229),.013,orange,'spine')
box('Battery cover seam',(0,.1905,.85),(.39,.003,.28),dark,'spine',.018)
box('Flat battery cover',(0,.1925,.85),(.37,.002,.26),ivory,'spine',.012)
box('Recessed latch marking',(0,.194,.955),(.085,.001,.015),dark,'spine',.003)
rod('Neck',(0,0,1.37),(0,0,1.52),.10,dark,'neck')
rod('Neck collar',(0,0,1.42),(0,0,1.47),.14,orange,'neck')
box('TV housing',(0,0,1.85),(1.35,.55,.80),ivory,'head',.10)
box('Screen gasket',(0,-.282,1.85),(1.20,.055,.66),teal,'head',.075)
box('Screen glass',(0,-.318,1.85),(1.10,.035,.56),screen,'head',.065)
box('Rear screen enclosure',(0,.285,1.85),(1.11,.11,.60),teal,'head',.065)
box('Rear inset',(0,.349,1.85),(.96,.026,.46),dark,'head',.04)
for z in [1.71,1.78,1.85,1.92,1.99]:box('Rear vent',(0,.367,z),(.73,.017,.018),teal,'head',.008)
for s in [-1,1]:
    rod('Speaker rim',(s*.664,.02,1.76),(s*.701,.02,1.76),.137,teal,'head')
    rod('Speaker cone',(s*.702,.02,1.76),(s*.711,.02,1.76),.10,dark,'head')
    rod('Speaker center',(s*.712,.02,1.76),(s*.722,.02,1.76),.043,keymat,'head')
    end=(s*(.20 if s<0 else .32),0,2.61 if s<0 else 2.51)
    rod('Antenna',(0,0,2.22),end,.025,dark,'antenna'+str(s),.016)
    ell('Antenna tip',end,(.045,.045,.045),orange,'antenna'+str(s))

bones=[('root',(0,0,0),(0,0,.25),None),('spine',(0,0,.64),(0,0,1.37),'root'),('neck',(0,0,1.37),(0,0,1.49),'spine'),('head',(0,0,1.49),(0,0,2.22),'neck')]
for s,label in [(1,'L'),(-1,'R')]:
    shoulder=(s*.34,0,1.30); elbow=(s*.56,0,1.02); wrist=(s*.70,-.015,.76)
    bones.extend([(f'upper_arm.{label}',shoulder,elbow,'spine'),(f'forearm.{label}',elbow,wrist,f'upper_arm.{label}'),(f'hand.{label}',wrist,(s*.73,-.015,.64),f'forearm.{label}')])
    ell('Shoulder',shoulder,(.10,.10,.10),dark,f'upper_arm.{label}')
    # One continuous shell from shoulder through rounded palm; no wrist seam.
    verts=[]; faces=[]; seg=24
    axis=(Vector(wrist)-Vector(shoulder)).normalized()
    side=Vector((abs(axis.z),0,s*abs(axis.x))).normalized()
    profile=[]
    for j in range(17):
        t=j/16;profile.append((Vector(shoulder).lerp(Vector(wrist),t),.055+.067*sin(t*pi*.65),t))
    end_radius=profile[-1][1]
    for j in range(1,7):
        angle=j*pi/14;profile.append((Vector(wrist)+axis*(.10*sin(angle)),end_radius*cos(angle),1+j/7))
    profile.append((Vector(wrist)+axis*.10,.002,2))
    rings=len(profile)
    for p,radius,t in profile:
        for k in range(seg):
            a=k*2*pi/seg; v=p+side*(radius*cos(a))+Vector((0,radius*sin(a),0));verts.append(tuple(v))
    for j in range(rings-1):
        for k in range(seg):a=j*seg+k; b=j*seg+(k+1)%seg; faces.append((a,b,b+seg,a+seg))
    faces.extend([tuple(range(seg-1,-1,-1)),tuple((rings-1)*seg+k for k in range(seg))])
    me=bpy.data.meshes.new('Arm surface');me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new('Continuous arm '+label,me);bpy.context.collection.objects.link(ob);ob.data.materials.append(ivory);parts.append(ob)
    gu=ob.vertex_groups.new(name=f'upper_arm.{label}');gf=ob.vertex_groups.new(name=f'forearm.{label}');gh=ob.vertex_groups.new(name=f'hand.{label}')
    for j in range(rings):
        t=profile[j][2];w=max(0,min(1,(t-.35)/.30));h=max(0,min(1,(t-.78)/.50));ids=list(range(j*seg,(j+1)*seg))
        if 1-w:gu.add(ids,1-w,'REPLACE')
        if w*(1-h):gf.add(ids,w*(1-h),'REPLACE')
        if h:gh.add(ids,h,'REPLACE')
    for p in me.polygons:p.use_smooth=True
    for i,dx in enumerate([-.105,0,.105]):
        x=s*.70+dx; name=f'finger{i+1}.{label}'; start=(x,-.015,.72)
        bones.append((name,start,(x+dx*.5,-.015,.57),f'hand.{label}'))
        tube('Curved claw',[start,(x+dx*.65,-.025,.63),(x+dx*.65,-.075,.56)],.035,dark,name)
    hip=(s*.155,0,.65); knee=(s*.155,0,.38); ankle=(s*.155,0,.14)
    bones.extend([(f'thigh.{label}',hip,knee,'root'),(f'shin.{label}',knee,ankle,f'thigh.{label}'),(f'foot.{label}',ankle,(s*.155,-.18,.09),f'shin.{label}')])
    box('Thigh',(s*.155,0,.53),(.255,.28,.24),ivory,f'thigh.{label}',.035)
    rod('Knee pin',(s*.155-.14,0,.38),(s*.155+.14,0,.38),.052,teal,f'shin.{label}')
    box('Shin',(s*.155,0,.255),(.245,.27,.23),ivory,f'shin.{label}',.035)
    # Rounded upper shoe with a broad, perfectly planar sole.
    shoe=ell('Foot',(s*.155,-.07,.045),(.15,.215,.14),dark,f'foot.{label}')
    for v in shoe.data.vertices:v.co.z=max(v.co.z,-.045)
    for p in shoe.data.polygons:
        if all(abs(shoe.data.vertices[i].co.z+.045)<1e-6 for i in p.vertices):p.use_smooth=False
    bones.append(('antenna'+str(s),(0,0,2.22),(s*.2,0,2.5),'head'))

# Sketch proportions: compact torso and short legs; retain arm lengths and head.
HEAD_SHIFT=-.3464
ARM_SHIFT=-.338
def proportion(co,name):
    v=Vector(co)
    if name=='root' or name.startswith(('thigh.','shin.','foot.')):
        v.z*=.60
    elif name=='spine':
        v.x*=.90;v.z=.39+(v.z-.65)*.88
    elif name.startswith(('upper_arm.','forearm.','hand.','finger')):
        v.x+=-.025 if name.endswith('.L') else .025;v.z+=ARM_SHIFT
    else:v.z+=HEAD_SHIFT
    return v
for o in parts:
    # All arm-shell groups share the same translation, so one group suffices.
    name=o.vertex_groups[0].name;inv=o.matrix_world.inverted()
    for v in o.data.vertices:v.co=inv@proportion(o.matrix_world@v.co,name)
bones=[(name,proportion(a,name),proportion(b,name),parent) for name,a,b,parent in bones]
arm=bpy.data.armatures.new('Robert skeleton');rig=bpy.data.objects.new('Robert_Rig',arm);bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name,a,b,parent in bones:
    bone=arm.edit_bones.new(name);bone.head=a;bone.tail=b;bone.align_roll(Vector((0,-1,0)))
    if parent:bone.parent=arm.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
def bind(o):
    mod=o.modifiers.new('Robert deformation','ARMATURE');mod.object=rig;o.parent=rig
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();body=bpy.context.object;body.name='Robert_Body';bind(body)

# A single flat, UV-mapped display. All expression details come from a PNG.
face_mat=bpy.data.materials.new('FaceScreen_Unlit');face_mat.use_nodes=True
nodes=face_mat.node_tree.nodes;nodes.clear()
output=nodes.new('ShaderNodeOutputMaterial')
image_node=nodes.new('ShaderNodeTexImage');image_node.name='FACE_PNG_REPLACE_ME';image_node.label='Replace with any 2:1 face PNG'
image_node.image=bpy.data.images.load(os.path.join(ROOT,'shared','faces','default','neutral.png'))
image_node.image.pack();image_node.extension='EXTEND'
# Direct colour-to-surface is Blender glTF's recognised KHR_materials_unlit graph.
face_mat.node_tree.links.new(image_node.outputs['Color'],output.inputs['Surface'])
# Rectangle fits inside the rounded screen backing. Front normal points toward -Y.
z=1.85+HEAD_SHIFT
me=bpy.data.meshes.new('FaceScreen_UV');me.from_pydata([(-.515,-.340,z-.2575),(.515,-.340,z-.2575),(.515,-.340,z+.2575),(-.515,-.340,z+.2575)],[],[(0,1,2,3)]);me.update()
uv=me.uv_layers.new(name='FaceUV')
for loop,coord in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=coord
display=bpy.data.objects.new('FaceScreen',me);bpy.context.collection.objects.link(display);display.data.materials.append(face_mat)
vg=display.vertex_groups.new(name='head');vg.add(list(range(4)),1,'REPLACE');bind(display)
faces=[display]

def stash(obj,name,end):
    ad=obj.animation_data;act=ad.action;act.name=name
    track=ad.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,act);strip.action_frame_start=1;strip.action_frame_end=end
    ad.action=None;track.mute=True
def reset():
    for p in rig.pose.bones:p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0)
def poseclip(name,end,fn):
    reset()
    for f in range(1,end+1):
        reset();fn((f-1)/(end-1))
        for p in rig.pose.bones:p.keyframe_insert('rotation_euler',frame=f);p.keyframe_insert('location',frame=f)
    stash(rig,name,end);reset()
poseclip('Idle',61,lambda t:setattr(rig.pose.bones['head'],'rotation_euler',(.015*sin(2*pi*t),.025*sin(2*pi*t),.015*sin(2*pi*t))))
def wave(t):
    envelope=sin(pi*t)**.6
    rig.pose.bones['upper_arm.L'].rotation_euler.z=1.6*envelope
    rig.pose.bones['forearm.L'].rotation_euler.z=.1*envelope
    rig.pose.bones['hand.L'].rotation_euler.z=.35*sin(6*pi*t)*envelope
poseclip('Wave',73,wave)
poseclip('Nod',49,lambda t:setattr(rig.pose.bones['head'],'rotation_euler',(.20*sin(4*pi*t)*sin(pi*t),0,0)))
def celebrate(t):
    e=sin(pi*t);rig.pose.bones['upper_arm.L'].rotation_euler.z=1.55*e;rig.pose.bones['upper_arm.R'].rotation_euler.z=-1.55*e
    rig.pose.bones['spine'].rotation_euler.z=.07*sin(6*pi*t)*e
poseclip('Celebrate',73,celebrate)

scene=bpy.context.scene;scene.render.fps=30;scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
for o in [rig,body]+faces:o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'Robert.glb'),use_selection=True,export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_morph=True,export_skins=True)
stats={'triangles':sum(len(p.vertices)-2 for o in [body]+faces for p in o.data.polygons),'vertices':sum(len(o.data.vertices) for o in [body]+faces),'bones':len(bones),'materials':8,'clips':['Idle','Wave','Nod','Celebrate'],'height_m':round(2.655+HEAD_SHIFT,4),'revision':3,'face_mode':'png_texture','torso_height_scale':.88,'leg_height_scale':.60,'arm_length_scale':1.0}
with open(os.path.join(VALIDATION,'model_stats.json'),'w') as f:json.dump(stats,f,indent=2)
contract={'id':'robert-rig-v1','coordinate_system':'Blender Z-up, front -Y; GLB converts to Y-up','bones':[{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(b.head_local),'tail':list(b.tail_local),'rest_matrix':[list(row) for row in b.matrix_local]} for b in arm.bones],'body_material_slots':[m.name for m in body.data.materials],'face_mesh':'FaceScreen','face_material':'FaceScreen_Unlit','clips':['Idle','Wave','Nod','Celebrate']}
with open(os.path.join(ROOT,'shared','rig_contract.json'),'w') as f:json.dump(contract,f,indent=2)


# Presentation studio is excluded from the GLB.
floor=mat('Studio sand',(.075,.105,.12),0,.8)
box('Studio floor',(0,0,-.05),(200,200,.1),floor,None,.01)
world=scene.world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.20,.25,1);world.node_tree.nodes['Background'].inputs[1].default_value=.5
def area(name,loc,power,size):
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1.3))-o.location).to_track_quat('-Z','Y').to_euler()
area('Key',(-3,-4,6),550,4);area('Fill',(4,-2,3),400,3);area('Rim',(1,3,4),650,3)
bpy.ops.object.camera_add(location=(3.3,-6,3.0));cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=3.0
def camera(loc):cam.location=loc;cam.rotation_euler=(Vector((0,0,1.16))-cam.location).to_track_quat('-Z','Y').to_euler()
camera((3.3,-6,3.0));scene.render.engine='CYCLES';scene.cycles.samples=32
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,'Robert.blend'))
for name,loc in [('Robert_preview',(3.3,-6,3.0)),('Robert_front',(0,-6,1.65)),('Robert_back',(3,6,2.7))]:
    camera(loc);scene.render.filepath=os.path.join(PREVIEW,name+'.png');bpy.ops.render.render(write_still=True)
print('ROBERT_COMPLETE',json.dumps(stats))
