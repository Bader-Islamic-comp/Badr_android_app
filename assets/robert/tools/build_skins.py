"""Author six rig-compatible outfits from the approved default Blender model.

Run: blender --background --python-exit-code 1 --python build_skins.py -- cowboy ...
Without IDs, generates every outfit. The default source/model are read-only inputs.
"""
import bpy, bmesh, json, math, sys, hashlib
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'skins/default/source/Robert.blend'
NAMES={'cowboy':'Cowboy','astronaut':'Astronaut','arab_thobe':'Arab Thobe','casual':'Casual','explorer':'Explorer','gardener':'Gardener'}
IDS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(NAMES)
PREVIEW=ROOT/'previews'

def material(name,color,metal=0,rough=.65):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m

def finish(obj,name,mat,bone):
    obj.name=name;obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    group=obj.vertex_groups.new(name=bone);group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    pieces.append(obj)
    return obj

def box(name,loc,size,mat,bone='spine',bevel=.025):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=o.modifiers.new('Tailored rounded edge','BEVEL');mod.width=bevel;mod.segments=3
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Surface normals','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,mat,bone)

def ell(name,loc,size,mat,bone='spine'):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=loc)
    o=bpy.context.object;o.scale=size
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,name,mat,bone)

def mesh(name,verts,faces,mat,bone='spine',smooth=True):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    for f in me.polygons:f.use_smooth=smooth
    return finish(ob,name,mat,bone)

def tube(name,points,radius,mat,bone='spine',closed=False):
    bpy.ops.object.select_all(action='DESELECT')
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=radius;curve.bevel_resolution=2;curve.resolution_u=5;curve.use_fill_caps=True
    s=curve.splines.new('BEZIER');s.bezier_points.add(len(points)-1);s.use_cyclic_u=closed
    for b,p in zip(s.bezier_points,points):b.co=p;b.handle_left_type='AUTO';b.handle_right_type='AUTO'
    ob=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(ob);ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,name,mat,bone)

def loop(name,rx,ry,z,r,mat,bone='head',cy=0):
    return tube(name,[(rx*cos(i*2*pi/16),cy+ry*sin(i*2*pi/16),z) for i in range(16)],r,mat,bone,True)

def button(x,z,mat,y=-.231,r=.014):return ell('Stitched button',(x,y,z),(r,.009,r),mat)

def panel(name,points,mat):
    # Double sided solid garment panels rather than zero-thickness decals.
    verts=points+[(x,y+.012,z) for x,y,z in points];n=len(points)
    return mesh(name,verts,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat,smooth=False)

def base_shirt(mat):box('Tailored shirt',(0,0,.702),(.565,.435,.66),mat,bevel=.062)

def collar(mat):
    for s in [-1,1]:
        panel('Folded collar',[(s*.025,-.246,1.027),(s*.17,-.246,1.006),(s*.105,-.265,.922)],mat)

def vest(mat):
    for s in [-1,1]:
        panel('Vest front',[(s*.265,-.244,.43),(s*.06,-.244,.43),(s*.06,-.25,.83),(s*.18,-.25,1.018),(s*.265,-.244,.95)],mat)
        box('Vest side',(s*.263,0,.718),(.035,.44,.56),mat,bevel=.012)
        box('Vest pocket',(s*.165,-.27,.62),(.13,.035,.13),mat,bevel=.015)
        tube('Pocket seam',[(s*.105,-.292,.66),(s*.225,-.292,.66)],.004,stitch)

def bandana(mat):
    loop('Bandana neck',.145,.115,1.013,.025,mat,'spine')
    panel('Bandana point',[(-.17,-.251,.991),(.17,-.251,.991),(0,-.282,.823)],mat)
    tube('Bandana seam',[(-.12,-.27,.978),(0,-.294,.866),(.12,-.27,.978)],.004,cream)

def belt(mat):
    box('Waist belt',(0,0,.411),(.575,.45,.052),mat,bevel=.014)
    box('Belt buckle',(0,-.237,.411),(.084,.025,.063),gold,bevel=.010)
    box('Buckle inset',(0,-.253,.411),(.049,.005,.032),mat,bevel=.004)

def shoe_details(sport=False):
    for s,l in [(1,'L'),(-1,'R')]:
        if sport:
            sole=ell('Sneaker sole',(s*.155,-.075,.027),(.153,.217,.032),cream,'foot.'+l)
            for v in sole.data.vertices:v.co.z=max(v.co.z,-.027)
            for z in [.066,.083]:tube('Sneaker lace',[(s*.155-.05,-.196,z),(s*.155+.05,-.196,z)],.007,cream,'foot.'+l)
            box('Heel stripe',(s*.155,.095,.07),(.20,.033,.024),accent,'foot.'+l,.008)
        else:
            box('Boot cuff',(s*.155,0,.148),(.264,.285,.12),leather,'shin.'+l,.027)
            tube('Boot seam',[(s*.155-.08,-.147,.15),(s*.155,-.157,.125),(s*.155+.08,-.147,.15)],.004,stitch,'shin.'+l)

def denim_details():
    for s,l in [(1,'L'),(-1,'R')]:
        for z,bone in [(.32,'thigh.'+l),(.157,'shin.'+l)]:
            tube('Denim side stitch',[(s*.247,-.145,z-.04),(s*.247,-.145,z+.04)],.0035,stitch,bone)
        tube('Jeans pocket stitch',[(s*.07,-.147,.369),(s*.105,-.15,.319),(s*.18,-.15,.306)],.0035,stitch,'thigh.'+l)

def short_sleeve_cuffs(mat):
    for s,l in [(1,'L'),(-1,'R')]:
        shoulder=Vector((s*.315,0,.962));wrist=Vector((s*.675,-.015,.422))
        axis=(wrist-shoulder).normalized();side=Vector((abs(axis.z),0,s*abs(axis.x))).normalized()
        center=shoulder.lerp(wrist,5/16);radius=.055+.067*sin(5/16*pi*.65)
        points=[center+side*(radius*cos(i*2*pi/24))+Vector((0,radius*sin(i*2*pi/24),0)) for i in range(24)]
        tube('Sewn short sleeve cuff',points,.010,mat,'upper_arm.'+l,True)

def brim(mat,rx,ry,curl):
    verts=[];n=48
    for level in [0,1]:
        for ring in [0,.35,.7,1]:
            for i in range(n):
                a=i*2*pi/n;x=rx*ring*cos(a);y=ry*ring*sin(a)
                z=1.931+curl*(abs(x/rx)**4)-level*.022
                verts.append((x,y,z))
    faces=[]
    for level in [0,1]:
        offset=level*n*4
        for r in range(3):
            for i in range(n):a=offset+r*n+i;b=offset+r*n+(i+1)%n;faces.append((a,b,b+n,a+n))
    for i in range(n):a=3*n+i;b=3*n+(i+1)%n;faces.append((a,b,b+4*n,a+4*n))
    return mesh('Sculpted hat brim',verts,faces,mat,'head')

def hat(kind):
    first_hat_piece=len(pieces)
    if kind=='cowboy':
        brim(leather,.92,.45,.105)
        crown=ell('Creased cowboy crown',(0,0,2.035),(.46,.27,.15),leather,'head')
        for v in crown.data.vertices:
            if v.co.z>0:v.co.z-=.038*math.exp(-(v.co.x/.12)**2)*(v.co.z/.15)
        loop('Leather hatband',.45,.265,1.995,.024,chocolate)
        box('Hatband buckle',(0,-.285,1.995),(.085,.027,.062),gold,'head',.01)
    elif kind=='explorer':
        brim(khaki,.80,.405,.022);ell('Safari crown',(0,0,1.992),(.49,.28,.145),khaki,'head')
        loop('Safari band',.478,.274,1.994,.025,olive)
        for s in [-1,1]:
            for y in [-.065,.035,.13]:ell('Hat eyelet',(s*.464,y,2.025),(.010,.018,.018),chocolate,'head')
    else:
        brim(straw,.89,.45,-.018);ell('Straw crown',(0,0,2.014),(.45,.26,.14),straw,'head')
        loop('Garden hat ribbon',.445,.255,1.992,.028,accent)
        for radius in [.61,.70,.79,.865]:
            loop('Straw weave',radius,radius*.505,1.933,.0028,stitch)
    # Miniature accessory perched on one side, retaining its head-bone binding.
    bpy.context.view_layer.update()
    pivot=Vector((0,0,1.931));perch=Vector((.44,-.005,1.914))
    for obj in pieces[first_hat_piece:]:
        world=obj.matrix_world.copy();inverse=world.inverted()
        for vertex in obj.data.vertices:
            vertex.co=inverse@(perch+(world@vertex.co-pivot)*.30)

def thobe():
    # Rounded rectangular cross sections, with a soft lower hem.
    levels=[(.118,.32,.228),(.15,.321,.23),(.31,.31,.229),(.52,.291,.224),(.74,.282,.22),(.98,.278,.218),(1.032,.25,.19)]
    n=48;verts=[]
    for z,rx,ry in levels:
        for i in range(n):
            a=i*2*pi/n;cx=cos(a);sy=sin(a)
            x=rx*math.copysign(abs(cx)**.45,cx);y=ry*math.copysign(abs(sy)**.45,sy)
            fold=.004*cos(a*12)*(1-(z-.118)/.914)
            verts.append((x*(1+fold),y*(1+fold),z))
    faces=[tuple(range(n-1,-1,-1)),tuple((len(levels)-1)*n+i for i in range(n))]
    for j in range(len(levels)-1):
        for i in range(n):a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
    cloth=mesh('Thobe full length garment',verts,faces,cream)
    cloth.vertex_groups.clear();gs=cloth.vertex_groups.new(name='spine');gr=cloth.vertex_groups.new(name='root')
    for v in cloth.data.vertices:
        w=max(0,min(1,(v.co.z-.23)/.35));w=w*w*(3-2*w)
        if w:gs.add([v.index],w,'REPLACE')
        if 1-w:gr.add([v.index],1-w,'REPLACE')
    box('Thobe button placket',(0,-.225,.856),(.038,.016,.30),cloth_white,bevel=.008)
    for z in [.968,.907,.846,.785]:button(0,z,pearl,y=-.242,r=.009)
    loop('Stand collar',.117,.105,1.026,.025,cloth_white,'spine')
    box('Thobe chest pocket',(.164,-.228,.828),(.112,.013,.126),cloth_white,bevel=.008)
    tube('Hem stitch',[(-.27,-.232,.145),(0,-.238,.145),(.27,-.232,.145)],.003,pearl,'root')

def astronaut():
    base_shirt(cream)
    box('Life support backpack',(0,.29,.765),(.47,.26,.52),cream,bevel=.065)
    box('Backpack orange inset',(0,.434,.77),(.29,.033,.29),accent,bevel=.025)
    for s in [-1,1]:
        box('Pack side cartridge',(s*.245,.29,.75),(.08,.19,.36),silver,bevel=.035)
        box('Harness strap',(s*.204,-.245,.755),(.061,.052,.50),teal,bevel=.02)
    box('Suit chest controller',(0,-.263,.816),(.285,.066,.217),teal,bevel=.027)
    box('Suit status window',(0,-.302,.851),(.19,.014,.061),navy,bevel=.012)
    for x in [-.075,0,.075]:button(x,.759,accent,y=-.302,r=.016)
    box('Suit waist strap',(0,0,.432),(.585,.45,.071),accent,bevel=.02)
    for s,l in [(1,'L'),(-1,'R')]:
        box('Suit ankle band',(s*.155,0,.136),(.257,.282,.047),accent,'shin.'+l,.014)

def leaf_badge():
    ell('Badge backing',(.11,-.284,.826),(.050,.010,.055),cream)
    panel('Leaf emblem',[(.11,-.297,.785),(.077,-.297,.825),(.125,-.297,.861),(.143,-.297,.816)],forest)
    tube('Leaf vein',[(.105,-.305,.792),(.12,-.305,.846)],.003,cream)

def repaint_body(kind):
    # Preserve the base material slots; append garment palette slots only.
    def slot(m):
        if m.name not in body.data.materials:body.data.materials.append(m)
        return body.data.materials.find(m.name)
    indices={m.name:slot(m) for m in [shirt,pants,shoe,cream]}
    groups={v.index:v.name for v in body.vertex_groups}
    for p in body.data.polygons:
        counts={}
        for index in p.vertices:
            for g in body.data.vertices[index].groups:counts[groups[g.group]]=counts.get(groups[g.group],0)+g.weight/len(p.vertices)
        name=max(counts,key=counts.get)
        z=sum((body.matrix_world@body.data.vertices[i].co).z for i in p.vertices)/len(p.vertices)
        if name.startswith(('thigh.','shin.')):p.material_index=indices[pants.name]
        elif name.startswith('foot.'):p.material_index=indices[shoe.name]
        elif name.startswith(('upper_arm.','forearm.')) and 'Porcelain' in body.data.materials[p.material_index].name:
            side_sign=1 if name.endswith('.L') else -1
            shoulder=Vector((side_sign*.315,0,.962));wrist=Vector((side_sign*.675,-.015,.422));axis=wrist-shoulder
            center=sum((body.matrix_world@body.data.vertices[i].co for i in p.vertices),Vector())/len(p.vertices)
            along=(center-shoulder).dot(axis)/axis.length_squared
            if kind in ['astronaut','arab_thobe','cowboy'] or along<.32:p.material_index=indices[shirt.name]
        elif name.startswith('finger') and kind=='astronaut':p.material_index=indices[cream.name]

def remove_original_torso():
    group=body.vertex_groups['spine'].index;bm=bmesh.new();bm.from_mesh(body.data);layer=bm.verts.layers.deform.active
    remove=[v for v in bm.verts if v[layer].get(group,0)>.999]
    bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(body.data);bm.free()

def reset_pose():
    for t in rig.animation_data.nla_tracks:t.mute=True
    for b in rig.pose.bones:b.rotation_euler=(0,0,0);b.location=(0,0,0)
    rig.update_tag(refresh={'OBJECT','DATA','TIME'});bpy.context.scene.frame_set(1);bpy.context.view_layer.update()

for skin_id in IDS:
    assert skin_id in NAMES
    print('BUILDING_SKIN',skin_id,flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(BASE));bpy.context.preferences.filepaths.save_version=0
    rig=bpy.data.objects['Robert_Rig'];body=bpy.data.objects['Robert_Body'];face=bpy.data.objects['FaceScreen'];pieces=[]
    reset_pose()
    cream=material('Outfit / warm ivory',(.88,.90,.81));cloth_white=material('Outfit / white fabric',(.96,.96,.91))
    teal=material('Outfit / petrol',(.025,.28,.30));accent=material('Outfit / tangerine',(.98,.29,.055))
    navy=material('Outfit / denim',(.035,.12,.24));leather=material('Outfit / saddle leather',(.27,.105,.041))
    chocolate=material('Outfit / dark leather',(.028,.022,.016));gold=material('Outfit / brass',(.68,.39,.09),.55,.32)
    stitch=material('Outfit / sand stitching',(.64,.44,.18));khaki=material('Outfit / safari khaki',(.55,.40,.20))
    olive=material('Outfit / sage',(.27,.34,.19));forest=material('Outfit / garden green',(.065,.29,.16))
    straw=material('Outfit / woven straw',(.72,.49,.19));silver=material('Outfit / brushed alloy',(.5,.64,.65),.65,.3)
    pearl=material('Outfit / pearl buttons',(.67,.70,.64),.15)
    shirt={'cowboy':cream,'astronaut':cream,'arab_thobe':cream,'casual':teal,'explorer':olive,'gardener':straw}[skin_id]
    pants={'cowboy':navy,'astronaut':cream,'arab_thobe':cream,'casual':navy,'explorer':khaki,'gardener':forest}[skin_id]
    shoe=cream if skin_id=='astronaut' else teal if skin_id=='casual' else chocolate if skin_id=='arab_thobe' else leather
    remove_original_torso();repaint_body(skin_id)
    if skin_id=='cowboy':
        base_shirt(shirt);vest(leather);bandana(accent);belt(chocolate);hat('cowboy');denim_details();shoe_details()
    elif skin_id=='astronaut':astronaut()
    elif skin_id=='arab_thobe':thobe()
    elif skin_id=='casual':
        base_shirt(shirt);collar(cream);belt(chocolate);denim_details();shoe_details(True)
        box('Shirt placket',(0,-.225,.796),(.029,.014,.32),teal,bevel=.007)
        for z in [.945,.871,.797]:button(0,z,cream)
        box('Shirt chest pocket',(.162,-.235,.846),(.13,.025,.125),teal,bevel=.01)
        box('Pocket orange trim',(.162,-.251,.896),(.115,.011,.020),accent,bevel=.004)
    elif skin_id=='explorer':
        base_shirt(shirt);vest(khaki);collar(khaki);belt(chocolate);hat('explorer');shoe_details()
        for s in [-1,1]:
            box('Explorer shoulder tab',(s*.203,-.01,1.022),(.098,.30,.038),khaki,bevel=.012)
        ell('Compass badge',(.165,-.295,.862),(.042,.012,.042),gold)
        tube('Compass needle',[(.145,-.311,.843),(.182,-.311,.882)],.005,cream)
    else:
        base_shirt(shirt);hat('gardener');shoe_details()
        box('Overalls waist',(0,0,.46),(.573,.45,.18),forest,bevel=.024)
        box('Overalls bib',(0,-.238,.701),(.38,.048,.41),forest,bevel=.025)
        for s in [-1,1]:
            box('Overall shoulder strap',(s*.162,-.224,.939),(.067,.044,.197),forest,bevel=.014)
            button(s*.162,.892,gold,y=-.263,r=.020)
        box('Bib pocket',(0,-.27,.665),(.24,.033,.135),forest,bevel=.015)
        tube('Bib pocket stitch',[(-.10,-.29,.705),(-.10,-.29,.62),(.10,-.29,.62),(.10,-.29,.705)],.0035,stitch)
        leaf_badge()
    if skin_id in ['casual','explorer','gardener']:short_sleeve_cuffs(shirt)
    bpy.ops.object.select_all(action='DESELECT')
    for o in pieces:o.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();outfit=bpy.context.object;outfit.name='Robert_Outfit'
    modifier=outfit.modifiers.new('Shared Robert rig','ARMATURE');modifier.object=rig;outfit.parent=rig
    folder=ROOT/'skins'/skin_id
    for sub in ['model','source']:(folder/sub).mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in [rig,body,face,outfit]:o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(folder/'model/Robert.glb'),use_selection=True,export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True, export_anim_slide_to_zero=True,export_skins=True)
    scene=bpy.context.scene;scene.render.resolution_x=800;scene.render.resolution_y=900;scene.cycles.samples=24
    camera=scene.camera;camera.data.ortho_scale=2.85;camera.location=(2.65,-6,2.65);camera.rotation_euler=(Vector((0,0,1.15))-camera.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.wm.save_as_mainfile(filepath=str(folder/'source/Robert.blend'))
    manifest=json.loads((ROOT/'skins/default/skin.json').read_text())
    manifest.update({'id':skin_id,'display_name':NAMES[skin_id],'model':f'skins/{skin_id}/model/Robert.glb','source':f'skins/{skin_id}/source/Robert.blend','preview':f'previews/{skin_id}.png','outfit_mesh':'Robert_Outfit','presentation_only':True})
    (folder/'skin.json').write_text(json.dumps(manifest,indent=2))
    scene.render.filepath=str(PREVIEW/f'{skin_id}.png');bpy.ops.render.render(write_still=True)
    rig.animation_data.nla_tracks['Wave'].mute=False;rig.update_tag(refresh={'OBJECT','DATA','TIME'});scene.frame_set(37);bpy.context.view_layer.update()
    scene.render.resolution_x=600;scene.render.resolution_y=700;scene.render.filepath=str(PREVIEW/f'{skin_id}_poses.png');bpy.ops.render.render(write_still=True)
    print('BUILT_SKIN',skin_id,flush=True)
print('REQUESTED_SKINS_COMPLETE',flush=True)
