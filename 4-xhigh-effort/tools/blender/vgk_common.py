"""Shared helpers for the VALORIA Blender asset builders.

Executed inside the project's dedicated Blender instance (MCP server on localhost:9880).
Every builder imports this module and calls `guard()` before touching data, so nothing is ever
written unless the open file is the project's master .blend.

Conventions
- 1 Blender unit = 1 m, Z up, vehicles face +Y (exported glTF: -Z forward, Y up).
- Object names are globally unique: "<AssetId>_<Part>" (Godot matches by suffix).
- Material names are shared across assets; Godot maps them by name to project materials.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MASTER = os.path.join(PROJECT_DIR, "Opus55ForzaXhighEffort.blend")
ROOT = "FORZA_GODOT"


def guard():
    cur = os.path.normcase(os.path.abspath(bpy.data.filepath)) if bpy.data.filepath else ""
    if cur != os.path.normcase(os.path.abspath(MASTER)):
        raise RuntimeError("ROUTING GUARD: open file %r is not the master %r" % (bpy.data.filepath, MASTER))


def save_master():
    guard()
    bpy.ops.wm.save_mainfile(filepath=MASTER)


# ---------------------------------------------------------------- collections
def collection(path):
    """Return (creating) nested collection 'FORZA_GODOT/Cars/X'."""
    parent = bpy.context.scene.collection
    col = None
    for name in path.split("/"):
        col = bpy.data.collections.get(name)
        if col is None:
            col = bpy.data.collections.new(name)
        if col.name not in [c.name for c in parent.children]:
            # unlink from any other parent inside our tree first
            parent.children.link(col)
        parent = col
    return col


def clear_collection(col):
    for ob in list(col.all_objects):
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
    for child in list(col.children):
        clear_collection(child)
        bpy.data.collections.remove(child)


# ------------------------------------------------------------------ materials
MAT_DEFS = {
    # name: (rgba, metallic, roughness, emission_rgb, emission_strength, alpha)
    "Paint": ((0.75, 0.08, 0.06, 1), 0.6, 0.25, None, 0, 1),
    "Glass": ((0.08, 0.10, 0.12, 1), 0.0, 0.05, None, 0, 0.35),
    "Trim": ((0.025, 0.025, 0.028, 1), 0.0, 0.55, None, 0, 1),
    "Underbody": ((0.02, 0.02, 0.02, 1), 0.0, 0.9, None, 0, 1),
    "Chrome": ((0.9, 0.9, 0.92, 1), 1.0, 0.08, None, 0, 1),
    "WheelWell": ((0.012, 0.012, 0.012, 1), 0.0, 0.95, None, 0, 1),
    "Rubber": ((0.03, 0.03, 0.032, 1), 0.0, 0.85, None, 0, 1),
    "Rim": ((0.72, 0.73, 0.75, 1), 1.0, 0.25, None, 0, 1),
    "BrakeDisc": ((0.35, 0.34, 0.33, 1), 1.0, 0.45, None, 0, 1),
    "Caliper": ((0.8, 0.12, 0.05, 1), 0.2, 0.4, None, 0, 1),
    "LightHead": ((0.95, 0.95, 1.0, 1), 0.0, 0.05, (1.0, 0.97, 0.9), 2.0, 1),
    "LightTail": ((0.55, 0.02, 0.02, 1), 0.0, 0.1, (1.0, 0.05, 0.03), 1.0, 1),
    "LightReverse": ((0.9, 0.9, 0.9, 1), 0.0, 0.1, (1, 1, 1), 0.2, 1),
    "LightIndicator": ((0.9, 0.45, 0.05, 1), 0.0, 0.1, (1.0, 0.5, 0.05), 0.3, 1),
    "Grille": ((0.03, 0.03, 0.035, 1), 0.3, 0.45, None, 0, 1),
    "Plate": ((0.92, 0.9, 0.82, 1), 0.0, 0.4, None, 0, 1),
    "Interior": ((0.05, 0.048, 0.046, 1), 0.0, 0.8, None, 0, 1),
    "Seat": ((0.09, 0.06, 0.05, 1), 0.0, 0.7, None, 0, 1),
    "Gauges": ((0.1, 0.25, 0.35, 1), 0.0, 0.3, (0.3, 0.8, 1.0), 1.5, 1),
    "Carbon": ((0.04, 0.042, 0.045, 1), 0.2, 0.35, None, 0, 1),
    "Wood": ((0.32, 0.16, 0.07, 1), 0.0, 0.4, None, 0, 1),
    "Canvas": ((0.12, 0.1, 0.08, 1), 0.0, 0.9, None, 0, 1),
    "Metal": ((0.45, 0.46, 0.47, 1), 1.0, 0.4, None, 0, 1),
    "Steel": ((0.6, 0.6, 0.62, 1), 0.8, 0.5, None, 0, 1),
    "BoxWhite": ((0.9, 0.9, 0.88, 1), 0.1, 0.5, None, 0, 1),
    "GlassDark": ((0.03, 0.04, 0.05, 1), 0.5, 0.1, None, 0, 1),
}


def mat(name, color=None):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    rgba, met, rough, emi, emis, alpha = MAT_DEFS.get(name, ((0.5, 0.5, 0.5, 1), 0, 0.5, None, 0, 1))
    if color is not None:
        rgba = color
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = met
    bsdf.inputs["Roughness"].default_value = rough
    if emi is not None:
        bsdf.inputs["Emission Color"].default_value = (*emi, 1)
        bsdf.inputs["Emission Strength"].default_value = emis
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except (AttributeError, TypeError):
            pass
    m.diffuse_color = rgba
    return m


# -------------------------------------------------------------------- objects
_TMP = [0]


def new_object(name, mesh, col, location=(0, 0, 0)):
    if "_tmp" in name:  # temporary parts get unique names (they are joined away later)
        _TMP[0] += 1
        name = "%s%d" % (name, _TMP[0])
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    ob = bpy.data.objects.new(name, mesh)
    ob.location = location
    col.objects.link(ob)
    return ob


def new_empty(name, col, location, size=0.1):
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = "PLAIN_AXES"
    ob.empty_display_size = size
    ob.location = location
    col.objects.link(ob)
    return ob


def bm_to_object(bm, name, col, mats, location=(0, 0, 0), smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(mat(m) if isinstance(m, str) else m)
    if smooth:
        me.shade_smooth()
    return new_object(name, me, col, location)


def apply_modifiers(ob):
    """Bake the evaluated mesh (all modifiers) into the object without bpy.ops."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def join_into(target, others):
    """Join meshes (data API: transform + merge via bmesh, keeps material indices)."""
    bm = bmesh.new()
    bm.from_mesh(target.data)
    mat_names = [m.name for m in target.data.materials]
    inv = target.matrix_world.inverted()
    for ob in others:
        tmp = bmesh.new()
        tmp.from_mesh(ob.data)
        tmp.transform(inv @ ob.matrix_world)
        remap = []
        for m in ob.data.materials:
            if m.name not in mat_names:
                mat_names.append(m.name)
                target.data.materials.append(m)
            remap.append(mat_names.index(m.name))
        for f in tmp.faces:
            f.material_index = remap[f.material_index] if remap else 0
        me_tmp = bpy.data.meshes.new("_tmpjoin")
        tmp.to_mesh(me_tmp)
        tmp.free()
        bm.from_mesh(me_tmp)
        bpy.data.meshes.remove(me_tmp)
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    bm.to_mesh(target.data)
    bm.free()
    return target


def uv_unwrap(ob, angle=66.0, margin=0.02):
    """Smart UV project through a temp context override (needs edit mode)."""
    if not ob.data.polygons:
        return
    view_layer = bpy.context.view_layer
    for o in view_layer.objects:
        o.select_set(False)
    view_layer.objects.active = ob
    ob.select_set(True)
    try:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
        bpy.ops.object.mode_set(mode="OBJECT")
    except RuntimeError as e:  # keep building even if the operator context is unavailable
        try:
            bpy.ops.object.mode_set(mode="OBJECT")
        except RuntimeError:
            pass
        print("uv_unwrap failed for", ob.name, e)
    ob.select_set(False)


def box_uv(ob, scale=1.0):
    """Deterministic box-projection UVs (no operator context needed).
    Each face is projected on the plane of its dominant normal axis, in metres * scale."""
    me = ob.data
    if not me.polygons:
        return
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 0:
                u, v = co.y * (1 if n.x > 0 else -1), co.z
            elif ax == 1:
                u, v = co.x * (-1 if n.y > 0 else 1), co.z
            else:
                u, v = co.x, co.y * (1 if n.z > 0 else -1)
            loop[uv].uv = (u * scale, v * scale)
    bm.to_mesh(me)
    bm.free()


# --------------------------------------------------------------- primitives
def revolve(profile, segments, axis="X", uv_repeat=1.0, cap=False):
    """Revolve a list of (r, a) points around an axis (a = coordinate along the axis).
    Returns a bmesh. Profile order defines face orientation."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rings = []
    for i in range(segments):
        ang = 2 * math.pi * i / segments
        c, s = math.cos(ang), math.sin(ang)
        ring = []
        for (r, a) in profile:
            if axis == "X":
                co = (a, r * c, r * s)
            elif axis == "Y":
                co = (r * c, a, r * s)
            else:
                co = (r * c, r * s, a)
            ring.append(bm.verts.new(co))
        rings.append(ring)
    n = len(profile)
    for i in range(segments):
        r0, r1 = rings[i], rings[(i + 1) % segments]
        for j in range(n - 1):
            f = bm.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))
            u0, u1 = i / segments * uv_repeat, (i + 1) / segments * uv_repeat
            v0, v1 = j / (n - 1), (j + 1) / (n - 1)
            for loop, (uu, vv) in zip(f.loops, ((u0, v0), (u0, v1), (u1, v1), (u1, v0))):
                loop[uv].uv = (uu, vv)
    if cap:
        for idx in (0, n - 1):
            if profile[idx][0] > 1e-5:
                bm.faces.new([rings[i][idx] for i in range(segments)])
    bm.normal_update()
    return bm


def box_bm(sx, sy, sz, center=(0, 0, 0), bm=None, mat_index=0):
    bm = bm or bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    for v in verts:
        v.co = Vector((v.co.x * sx + center[0], v.co.y * sy + center[1], v.co.z * sz + center[2]))
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index
    return bm


def rounded_box(name, col, size, center, bevel, mats, segments=3, rot=None):
    bm = box_bm(*size, center=(0, 0, 0))
    ob = bm_to_object(bm, name, col, mats, location=center, smooth=True)
    if rot is not None:
        ob.rotation_euler = rot
    mod = ob.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = segments
    mod.limit_method = "NONE"
    apply_modifiers(ob)
    ob.data.shade_smooth()
    return ob


def cylinder_bm(radius, depth, segments=24, axis="Z", center=(0, 0, 0), bm=None, mat_index=0, cap=True):
    bm = bm or bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments,
                                radius1=radius, radius2=radius, depth=depth)
    verts = res["verts"]
    rot = Matrix.Identity(3)
    if axis == "X":
        rot = Matrix.Rotation(math.pi / 2, 3, "Y")
    elif axis == "Y":
        rot = Matrix.Rotation(math.pi / 2, 3, "X")
    for v in verts:
        v.co = rot @ v.co + Vector(center)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index
    return bm


def smoothstep(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def pchip(points):
    """Monotone cubic interpolation over [(x, y), ...] sorted by x. Returns f(x)."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    n = len(xs)
    if n == 1:
        return lambda x: ys[0]
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0] + m[0] * (x - xs[0]) * 0.0
        if x >= xs[-1]:
            return ys[-1]
        lo, hi = 0, n - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        t = (x - xs[lo]) / h[lo]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[lo] + (t3 - 2 * t2 + t) * h[lo] * m[lo]
                + (-2 * t3 + 3 * t2) * ys[lo + 1] + (t3 - t2) * h[lo] * m[lo + 1])

    return f


def export_glb(objects, filepath):
    """Export exactly these objects as a binary glTF (modifiers applied, Y-up)."""
    guard()
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    view_layer = bpy.context.view_layer
    for o in view_layer.objects:
        o.select_set(False)
    for o in objects:
        o.hide_set(False)
        o.select_set(True)
    if objects:
        view_layer.objects.active = objects[0]
    kwargs = dict(filepath=filepath, export_format="GLB", use_selection=True, export_apply=True,
                  export_yup=True, export_texcoords=True, export_normals=True,
                  export_materials="EXPORT", export_cameras=False, export_lights=False,
                  export_animations=False, export_extras=True)
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_extras", None)
        bpy.ops.export_scene.gltf(**kwargs)
    for o in objects:
        o.select_set(False)
    return filepath
