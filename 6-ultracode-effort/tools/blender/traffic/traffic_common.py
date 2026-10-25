"""Shared workflow helpers for the Sunward Roads traffic vehicles (tools/blender/traffic/<id>.py).

Geometry comes from tools/blender/car_kit.py (ProfileBody, LoftBody, wheels, ...); this module only holds the
per-vehicle workflow: view-layer isolation for looks/renders, the temporary 1.8 m reference figure, measuring the
JSON fields (same fields as assets/imported/cars/*.json, Godot coordinates), export + GLB verification, hero and
lineup renders, and the final restore-and-save step.

Run a vehicle script inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\traffic\\van_delivery.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Utility entry points (this file, STEP global): 'solo:<id>' (exclude every other car / traffic collection),
'restore' (un-exclude all, remove QA reference figures), 'save' (restore + bpy.ops.wm.save_mainfile()),
'lineup' (contact sheet of all traffic vehicles -> docs/blender_props/traffic.png), 'ref:<id>' (add the 1.8 m figure).
"""
import os
import sys
import math
import json
import importlib

import bpy
import bmesh
from mathutils import Vector, Matrix

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender'))
import car_kit as ck  # noqa: E402

GLB_DIR = os.path.join(PROJECT, 'assets', 'imported', 'traffic')
DOC_DIR = os.path.join(PROJECT, 'docs', 'blender_props')
IDS = ['hatch_small', 'van_delivery', 'lorry_box', 'bus_coach', 'tractor_farm', 'pickup_work']
REF_NAME = 'QA_Ref_1.8m'


# ---------------------------------------------------------------------------------------------------- visibility
def _groups():
    root = bpy.context.view_layer.layer_collection.children.get('SUNWARD_GODOT')
    if root is None:
        return []
    return [root.children.get(g) for g in ('Cars', 'Traffic') if root.children.get(g) is not None]


def solo(car_id):
    """Exclude (view layer only) every Cars/* and Traffic/* collection except Traffic_<car_id>."""
    keep = 'Traffic_' + car_id
    out = []
    for g in _groups():
        for lc in g.children:
            lc.exclude = lc.name != keep
            if lc.exclude:
                out.append(lc.name)
    bpy.context.view_layer.update()
    return out


def restore_visibility():
    for g in _groups():
        for lc in g.children:
            lc.exclude = False
    remove_ref()
    bpy.context.view_layer.update()


def add_ref(car_id, loc=(0.0, 0.0, 0.0)):
    """Temporary 1.8 m reference figure (box torso + legs + head) inside Traffic_<car_id> so `look` frames it."""
    remove_ref()
    col = bpy.data.collections.get('Traffic_' + car_id)
    p = ck.Part()
    x, y, z = loc
    p.extend(ck.abox((x - 0.17, y - 0.11, z), (x + 0.17, y + 0.11, 0.86), 'Paint'))
    p.extend(ck.abox((x - 0.22, y - 0.13, 0.86), (x + 0.22, y + 0.13, 1.52), 'Paint'))
    p.extend(ck.ellipsoid((x, y, 1.66), (0.10, 0.11, 0.14), 'Paint', nu=12, nv=8))
    me = bpy.data.meshes.new(REF_NAME)
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in p.v]
    for f in p.f:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bm.to_mesh(me)
    bm.free()
    mat = ck.make_material('QA_RefMat', base=(0.9, 0.35, 0.05), roughness=0.6)
    me.materials.append(mat)
    ob = bpy.data.objects.new(REF_NAME, me)
    col.objects.link(ob)
    return ob


def remove_ref():
    ob = bpy.data.objects.get(REF_NAME)
    if ob is not None:
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)


# ---------------------------------------------------------------------------------------------------- measuring
def mesh_objects(car):
    return [o for o in car.objects.values() if o.type == 'MESH']


def world_verts(ob):
    M = ob.matrix_world
    return [M @ v.co for v in ob.data.vertices]


def used_materials(car):
    mats = set()
    for o in mesh_objects(car):
        used = {p.material_index for p in o.data.polygons}
        mats |= {o.data.materials[i].name for i in used if i < len(o.data.materials) and o.data.materials[i]}
    return sorted(mats)


def measure(car, meta):
    """meta: dict(name, cls, drivetrain, engine, doors, seats, width_body, height_roof, paint_hex, paint_lin,
    finish, eye, sw_radius, notes...) -> JSON dict in Godot coordinates (x right, y up, z = -Blender Y)."""
    G = ck.to_godot
    body = car.objects['Body']
    bv = world_verts(body)
    mn = Vector((min(v.x for v in bv), min(v.y for v in bv), min(v.z for v in bv)))
    mx = Vector((max(v.x for v in bv), max(v.y for v in bv), max(v.z for v in bv)))
    all_mn, all_mx = ck.world_aabb(mesh_objects(car))
    wheel_keys = sorted(k[len('Wheel_'):] for k in car.objects if k.startswith('Wheel_'))
    wheels = {k: car.objects['Wheel_' + k].matrix_world.translation.copy() for k in wheel_keys}

    def wdims(k):
        vs = world_verts(car.objects['Wheel_' + k])
        return (max(v.z for v in vs) - min(v.z for v in vs)) / 2, max(v.x for v in vs) - min(v.x for v in vs)
    rf, wf = wdims('FL')
    rr, wr = wdims('RL')
    sockets = {n: G(car.objects[n].matrix_world.translation) for n in car.sockets}
    sw = car.objects['SteeringWheel']
    data = {
        'id': car.car_id, 'name': car.name, 'class': meta['cls'], 'drivetrain': meta['drivetrain'],
        'engine': meta['engine'], 'doors': meta['doors'], 'seats': meta['seats'],
        'source_blend': 'Opus55ForzaUltracodeEffort.blend', 'collection': 'Traffic/Traffic_' + car.car_id,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (vehicle faces -z); metres; origin = ground, mid-axles',
        'length': round(meta.get('length_body', mx.y - mn.y), 4),
        'length_overall': round(all_mx.y - all_mn.y, 4),
        'width': round(meta.get('width_body', mx.x - mn.x), 4),
        'width_with_mirrors': round(max(mx.x, all_mx.x) - min(mn.x, all_mn.x), 4),
        'height': round(meta.get('height_roof', mx.z), 4),
        'height_overall': round(all_mx.z, 4),
        'ground_clearance': round(meta.get('ground_clearance', mn.z), 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4),
        'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'wheels': {k: G(v) for k, v in wheels.items()},
        'sockets': sockets,
        'steering_wheel': {'position': G(sw.matrix_world.translation),
                           'column_axis': G(sw.matrix_world.to_3x3() @ Vector((0, 1, 0))),
                           'radius': meta['sw_radius'], 'spin_axis_local_godot': [0.0, 0.0, -1.0],
                           'note': 'Blender local +Y (column toward dash) becomes node-local -Z after the +Y-up glTF export'},
        'wheel_spin_axis_local_godot': [1.0, 0.0, 0.0],
        'eye_point': G(meta['eye']),
        'body_aabb': {'min': [round(mn.x, 4), round(mn.z, 4), round(-mx.y, 4)],
                      'max': [round(mx.x, 4), round(mx.z, 4), round(-mn.y, 4)]},
        'car_aabb': {'min': [round(all_mn.x, 4), round(all_mn.z, 4), round(-all_mx.y, 4)],
                     'max': [round(all_mx.x, 4), round(all_mx.z, 4), round(-all_mn.y, 4)]},
        'tris': ck.tri_counts(car),
        'materials': used_materials(car),
        'default_paint': {'hex': meta['paint_hex'], 'linear_rgb': [round(c, 4) for c in meta['paint_lin']],
                          'finish': meta.get('finish', 'gloss')},
    }
    for k in ('rim_diameter_in_front', 'rim_diameter_in_rear', 'tyre_width_nominal', 'wheel_width_note', 'cargo',
              'notes', 'livery', 'extra_wheels'):
        if k in meta:
            data[k] = meta[k]
    return data


# ---------------------------------------------------------------------------------------------------- export
def export(car, meta):
    glb = os.path.join(GLB_DIR, car.car_id + '.glb')
    js = os.path.join(GLB_DIR, car.car_id + '.json')
    res, info = ck.export_car(car, glb, extra=dict(export_vertex_color='ACTIVE', export_all_vertex_colors=False))
    data = measure(car, meta)
    data['glb'] = {'path': 'res://assets/imported/traffic/%s.glb' % car.car_id, 'bytes': info['file_size'],
                   'nodes': sorted(n['name'] for n in info['nodes'])}
    ck.write_car_json(car, js, data)
    return res, verify_glb(glb, car.car_id), data


def verify_glb(path, root_name):
    """Parse the GLB JSON chunk (struct + json): node names, mesh count, hierarchy checks."""
    import struct
    with open(path, 'rb') as fh:
        raw = fh.read()
    magic, version, length = struct.unpack_from('<4sII', raw, 0)
    clen, ctype = struct.unpack_from('<I4s', raw, 12)
    js = json.loads(raw[20:20 + clen].decode('utf-8'))
    nodes = js.get('nodes', [])
    scene = js['scenes'][js.get('scene', 0)]
    top = [nodes[i]['name'] for i in scene['nodes']]
    root_i = next(i for i, n in enumerate(nodes) if n.get('name') == root_name)
    children = sorted(nodes[c]['name'] for c in nodes[root_i].get('children', []))
    grand = [nodes[c]['name'] for i in nodes[root_i].get('children', []) for c in nodes[i].get('children', [])]
    meshes = js.get('meshes', [])
    prims = sum(len(m.get('primitives', [])) for m in meshes)
    attrs = sorted({a for m in meshes for p in m.get('primitives', []) for a in p.get('attributes', {})})
    root = nodes[root_i]
    out = {'magic': magic.decode(), 'version': version, 'bytes': len(raw), 'top_level': top,
           'root_children': children, 'grandchildren': grand, 'n_nodes': len(nodes), 'n_meshes': len(meshes),
           'n_primitives': prims, 'attributes': attrs, 'materials': len(js.get('materials', [])),
           'root_transform_identity': all(k not in root for k in ('translation', 'rotation', 'scale', 'matrix')),
           'extensionsUsed': js.get('extensionsUsed', []), 'cameras': len(js.get('cameras', [])),
           'animations': len(js.get('animations', [])),
           'alpha_blend': sorted(m['name'] for m in js.get('materials', []) if m.get('alphaMode') == 'BLEND')}
    return out


# ---------------------------------------------------------------------------------------------------- QA
def qa(car, wheel_R, wheel_W):
    """Kit QA (wheel ground contact, arch clearance, outward normals) + floating-part / normal checks."""
    solo(car.car_id)
    try:
        q = ck.qa_checks(car, wheel_R, wheel_W)
    finally:
        restore_visibility()
    # loose islands far from everything else = floating parts? report island count of Body
    body = car.objects['Body']
    q['body_tris'] = sum(len(p.vertices) - 2 for p in body.data.polygons)
    zmin = min(v.z for o in mesh_objects(car) if o.name.startswith('Wheel_') for v in world_verts(o))
    q['wheel_min_z'] = round(zmin, 4)
    return q


def render_hero(car, png, cam_loc, target, lens=50.0, **kw):
    solo(car.car_id)
    try:
        return ck.render_hero(car, png, cam_loc=cam_loc, target=target, lens=lens, **kw)
    finally:
        restore_visibility()


def finish_body(car, weight=50):
    """Weighted normals on every mesh except the wheels (flat panels stay flat next to rounded edges)."""
    for name, ob in car.objects.items():
        if ob.type == 'MESH' and name in ('Body', 'Glass', 'Interior', 'Lights_Head', 'Lights_Tail', 'Lights_Brake',
                                          'Lights_Reverse'):
            ck.weighted_normals(ob, weight=weight)


# ---------------------------------------------------------------------------------------------------- lineup
LINEUP_X = 80.0


def lineup(out_png=None):
    """Contact sheet: every traffic root moved temporarily into a row around x = +80 m (away from the player cars at the
    origin), EEVEE still with a temporary camera / sun / ground in the hidden _QA collection, everything restored."""
    out_png = out_png or os.path.join(DOC_DIR, 'traffic.png')
    order = ['hatch_small', 'pickup_work', 'van_delivery', 'tractor_farm', 'lorry_box', 'bus_coach']
    roots = [bpy.data.objects.get(i) for i in order]
    roots = [r for r in roots if r is not None]
    saved = {r.name: r.matrix_world.copy() for r in roots}
    sc = bpy.context.scene
    qa_col = ck.ensure_qa_collection()
    made = []
    hidden_qa = {}
    try:
        # side by side, all facing +Y, staggered along X (widths ~1.7..2.5 m)
        x = LINEUP_X
        gaps = {'hatch_small': 2.4, 'pickup_work': 2.7, 'van_delivery': 2.9, 'tractor_farm': 3.1, 'lorry_box': 3.3,
                'bus_coach': 3.2}
        for r in roots:
            r.location = (x, 0.0, 0.0)
            x += gaps.get(r.name, 3.0)
        cx = (LINEUP_X + x - 3.2) / 2
        gm = bpy.data.meshes.new('QA_LineupGround')
        gbm = bmesh.new()
        bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=30.0)
        gbm.to_mesh(gm)
        gbm.free()
        ground = bpy.data.objects.new('QA_LineupGround', gm)
        ground.location = (cx, 0.0, 0.0)
        gm.materials.append(ck.make_material('QA_GroundMat', base=(0.32, 0.32, 0.33), roughness=0.9))
        qa_col.objects.link(ground)
        made.append(ground)
        cam = bpy.data.objects.new('QA_LineupCam', bpy.data.cameras.new('QA_LineupCam'))
        qa_col.objects.link(cam)
        made.append(cam)
        tgt = Vector((cx, 0.0, 1.2))
        cam.location = tgt + Vector((7.0, 27.0, 6.0))
        cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.lens = 50.0
        cam.data.clip_end = 300.0
        sun = bpy.data.objects.new('QA_LineupSun', bpy.data.lights.new('QA_LineupSun', 'SUN'))
        sun.data.energy = 3.8
        sun.rotation_euler = (0.80, 0.0, 2.30)
        qa_col.objects.link(sun)
        made.append(sun)
        for o in bpy.data.collections['_QA'].objects:
            if o.name in ('QA_Sun', 'QA_Ground', 'QA_Camera'):
                hidden_qa[o.name] = o.hide_render
                o.hide_render = True
        _render_with(sc, cam, out_png)
    finally:
        for r in roots:
            r.matrix_world = saved[r.name]
        for o in made:
            _remove_object(o)
        for name, hr in hidden_qa.items():
            bpy.data.objects[name].hide_render = hr
        bpy.context.view_layer.update()
    bad = [r.name for r in roots if r.matrix_world != Matrix.Identity(4)]
    return out_png, bad


def _remove_object(o):
    """Remove a temporary object and its (now orphan) datablock, tolerating Blender freeing the data itself."""
    try:
        dname, dtype = (o.data.name, type(o.data).__name__) if o.data is not None else (None, None)
    except ReferenceError:
        return
    bpy.data.objects.remove(o, do_unlink=True)
    coll = {'Mesh': bpy.data.meshes, 'Camera': bpy.data.cameras}.get(dtype)
    if coll is None and dtype and 'Light' in dtype:
        coll = bpy.data.lights
    if coll is not None and dname in coll and coll[dname].users == 0:
        coll.remove(coll[dname])


def cleanup_lineup():
    """Remove leftovers of an interrupted lineup render (temporary camera / sun / ground) and re-enable the QA
    hero-render helpers for rendering."""
    out = []
    for name in ('QA_LineupGround', 'QA_LineupCam', 'QA_LineupSun'):
        o = bpy.data.objects.get(name)
        if o is not None:
            _remove_object(o)
            out.append(name)
    for name in ('QA_Sun', 'QA_Ground', 'QA_Camera'):
        o = bpy.data.objects.get(name)
        if o is not None:
            o.hide_render = False
    return out


def _render_with(sc, cam, png, res=(1600, 700), world_rgb=(0.55, 0.62, 0.72)):
    r = sc.render
    vs = sc.view_settings
    col = bpy.data.collections['_QA']
    lc = bpy.context.view_layer.layer_collection.children.get('_QA')
    world = bpy.data.worlds.get('QA_World') or bpy.data.worlds.new('QA_World')
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = next((n for n in world.node_tree.nodes if n.type == 'BACKGROUND'), None)
    if bg is not None:
        bg.inputs[0].default_value = (world_rgb[0], world_rgb[1], world_rgb[2], 1.0)
        bg.inputs[1].default_value = 0.9
    saved = dict(engine=r.engine, rx=r.resolution_x, ry=r.resolution_y, pct=r.resolution_percentage, fp=r.filepath,
                 fmt=r.image_settings.file_format, cam=sc.camera, world=sc.world, transparent=r.film_transparent,
                 vt=vs.view_transform, look=vs.look, exposure=vs.exposure, col_hv=col.hide_viewport,
                 col_hr=col.hide_render, lc_hv=lc.hide_viewport if lc else None)
    try:
        col.hide_viewport = False
        col.hide_render = False
        if lc is not None:
            lc.hide_viewport = False
        r.engine = 'BLENDER_EEVEE'
        r.resolution_x, r.resolution_y = res
        r.resolution_percentage = 100
        r.image_settings.file_format = 'PNG'
        r.filepath = png
        r.film_transparent = False
        vs.view_transform = 'Standard'
        vs.exposure = -0.2
        sc.camera = cam
        sc.world = world
        os.makedirs(os.path.dirname(png), exist_ok=True)
        bpy.ops.render.render(write_still=True)
    finally:
        r.engine = saved['engine']
        r.resolution_x, r.resolution_y = saved['rx'], saved['ry']
        r.resolution_percentage = saved['pct']
        r.filepath = saved['fp']
        r.image_settings.file_format = saved['fmt']
        r.film_transparent = saved['transparent']
        vs.view_transform = saved['vt']
        vs.look = saved['look']
        vs.exposure = saved['exposure']
        sc.camera = saved['cam']
        sc.world = saved['world']
        col.hide_viewport = True
        col.hide_render = saved['col_hr']
        if lc is not None:
            lc.hide_viewport = True


def save_master():
    restore_visibility()
    path = bpy.data.filepath
    want = os.path.join(PROJECT, 'Opus55ForzaUltracodeEffort.blend')
    if os.path.normcase(os.path.abspath(path)) != os.path.normcase(want):
        raise RuntimeError('refusing to save: open file is %s' % path)
    bpy.ops.wm.save_mainfile()
    return path


if __name__ == '__main__':
    step = globals().get('STEP', 'restore')
    if step.startswith('solo:'):
        print('excluded', solo(step[5:]))
    elif step.startswith('ref:'):
        cid = step[4:]
        loc = globals().get('REF_LOC', (0.0, 0.0, 0.0))
        print('ref', add_ref(cid, loc).name, loc)
    elif step == 'restore':
        restore_visibility()
        print('restored visibility')
    elif step == 'save':
        print('saved', save_master())
    elif step == 'lineup':
        print('lineup', lineup())
    elif step == 'cleanup':
        print('cleanup', cleanup_lineup())
