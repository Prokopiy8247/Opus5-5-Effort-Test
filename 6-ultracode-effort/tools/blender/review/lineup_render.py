"""Reviewer lineup render of all 10 Sunward Roads cars.

Temporarily moves the car ROOT empties into a row (no copies, no geometry edits), renders an EEVEE still
with a temporary camera in the hidden _QA collection, then moves every root back to its original transform
(the origin) and restores all render/world/camera settings.

Usage inside Blender (execute_blender_code):
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__', 'STEP': 'arrange'})
STEP: 'arrange'  -> move roots to the row, create/aim QA_LineupCam, make it the scene camera (for preview)
      'render'   -> set 1280x720 EEVEE, render to docs/screenshots/blender_car_lineup.png, restore render settings
      'restore'  -> move roots back exactly, restore scene camera / world colour / viewport visibility
"""
import bpy, json, os, math
from mathutils import Vector, Matrix

PROJ = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
OUT = os.path.join(PROJ, 'docs', 'screenshots', 'blender_car_lineup.png')
STATE = os.path.join(PROJ, 'tools', 'blender', 'review', '_lineup_state.json')
IDS = ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x",
       "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]
SPACING = 2.8
CAM_TARGET = (0.6, 0.0, 0.45)
CAM_DIR = (0.15, 1.0, 0.33)   # from target towards the eye (cars face +Y)
CAM_DIST = 40.0
LENS = 50.0
WORLD_RGB = (0.42, 0.50, 0.60)


def arrange():
    sc = bpy.context.scene
    st = {'roots': {}, 'scene_camera': sc.camera.name if sc.camera else None}
    w = sc.world
    bg = [n for n in w.node_tree.nodes if n.type == 'BACKGROUND'][0] if (w and w.use_nodes) else None
    if bg:
        st['world_bg'] = list(bg.inputs[0].default_value); st['world_strength'] = bg.inputs[1].default_value
    for cid in IDS:
        r = bpy.data.objects[cid]
        st['roots'][cid] = {'loc': list(r.location), 'rot': list(r.rotation_euler), 'scale': list(r.scale),
                            'rot_mode': r.rotation_mode}
    with open(STATE, 'w', encoding='utf-8') as f:
        json.dump(st, f, indent=1)
    n = len(IDS)
    for i, cid in enumerate(IDS):
        # roster order reads left -> right when seen from the front (+Y), i.e. kestrel at +X
        bpy.data.objects[cid].location = (((n - 1) / 2.0 - i) * SPACING, 0.0, 0.0)
    qa = bpy.data.collections['_QA']
    cam = bpy.data.objects.get('QA_LineupCam')
    if cam is None:
        cam = bpy.data.objects.new('QA_LineupCam', bpy.data.cameras.new('QA_LineupCam'))
        qa.objects.link(cam)
    cam.data.lens = LENS
    cam.data.clip_end = 300.0
    loc = Vector(CAM_TARGET) + Vector(CAM_DIR).normalized() * CAM_DIST
    cam.location = loc
    d = Vector(CAM_TARGET) - loc
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    if bg:
        bg.inputs[0].default_value = (*WORLD_RGB, 1.0)
    # all car collections visible in the viewport for the preview
    cars_lc = bpy.context.view_layer.layer_collection.children['SUNWARD_GODOT'].children['Cars']
    for lc in cars_lc.children:
        lc.hide_viewport = False
    bpy.context.view_layer.update()
    print('arranged', [(cid, tuple(round(v, 3) for v in bpy.data.objects[cid].location)) for cid in IDS])


def render():
    sc = bpy.context.scene; r = sc.render
    saved = dict(x=r.resolution_x, y=r.resolution_y, pct=r.resolution_percentage, fp=r.filepath,
                 fmt=r.image_settings.file_format, cm=r.image_settings.color_mode, eng=r.engine,
                 ft=r.film_transparent)
    try:
        eng = [e.identifier for e in r.bl_rna.properties['engine'].enum_items]
        r.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in eng else [e for e in eng if 'EEVEE' in e][0]
        r.resolution_x, r.resolution_y, r.resolution_percentage = 1280, 720, 100
        r.image_settings.file_format = 'PNG'; r.image_settings.color_mode = 'RGB'
        r.film_transparent = False
        r.filepath = OUT
        bpy.ops.render.render(write_still=True)
    finally:
        r.resolution_x, r.resolution_y, r.resolution_percentage = saved['x'], saved['y'], saved['pct']
        r.filepath = saved['fp']; r.image_settings.file_format = saved['fmt']
        r.image_settings.color_mode = saved['cm']; r.engine = saved['eng']; r.film_transparent = saved['ft']
    print('rendered', OUT, os.path.getsize(OUT), 'restored render', r.resolution_x, r.resolution_y, r.filepath, r.engine)


def restore():
    sc = bpy.context.scene
    with open(STATE, encoding='utf-8') as f:
        st = json.load(f)
    for cid, t in st['roots'].items():
        o = bpy.data.objects[cid]
        o.rotation_mode = t['rot_mode']
        o.location = t['loc']; o.rotation_euler = t['rot']; o.scale = t['scale']
    sc.camera = bpy.data.objects.get(st['scene_camera']) if st['scene_camera'] else None
    w = sc.world
    if w and w.use_nodes and 'world_bg' in st:
        bg = [n for n in w.node_tree.nodes if n.type == 'BACKGROUND'][0]
        bg.inputs[0].default_value = st['world_bg']; bg.inputs[1].default_value = st['world_strength']
    for name in ('QA_LineupCam', 'QA_ReviewCockpitCam'):
        o = bpy.data.objects.get(name)
        if o:
            cd = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if cd and cd.users == 0:
                bpy.data.cameras.remove(cd)
    cars_lc = bpy.context.view_layer.layer_collection.children['SUNWARD_GODOT'].children['Cars']
    for lc in cars_lc.children:
        lc.hide_viewport = False
    bpy.context.view_layer.update()
    bad = []
    for cid in IDS:
        o = bpy.data.objects[cid]
        if o.matrix_world != Matrix.Identity(4) or tuple(o.location) != (0.0, 0.0, 0.0):
            bad.append(cid)
    os.remove(STATE)
    print('restored; scene camera =', sc.camera.name if sc.camera else None, '; roots not at identity:', bad)


if __name__ == '__main__':
    step = globals().get('STEP', 'arrange')
    {'arrange': arrange, 'render': render, 'restore': restore}[step]()
