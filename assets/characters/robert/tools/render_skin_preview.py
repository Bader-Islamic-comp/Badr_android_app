"""Renders one skin's preview from its own Blender scene.

    blender -b skins/<id>/source/Robert.blend --python tools/render_skin_preview.py -- <preview.png> [<thumb.png> <px>]

Uses the scene's camera, lights and studio floor exactly as authored, with the
same Cycles settings as `build_robert.py`, so every skin's preview matches the
default one. The optional thumbnail is a downscaled copy for the app's Style tab,
where a 700 px image would only cost download size.
"""
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
preview = args[0]
thumb, thumb_px = (args[1], int(args[2])) if len(args) >= 3 else (None, 0)

scene = bpy.context.scene
if scene.camera is None:
    raise SystemExit("PREVIEW_FAILED no scene camera")
scene.frame_set(1)
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.render.resolution_x = scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = preview
bpy.ops.render.render(write_still=True)
print("PREVIEW_OK", preview)

if thumb:
    image = bpy.data.images.load(preview)
    image.scale(thumb_px, thumb_px)
    image.filepath_raw = thumb
    image.file_format = "PNG"
    image.save()
    print("THUMB_OK", thumb)
