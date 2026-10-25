"""Shared helpers for the project's Blender build scripts (run inside the verified Blender
instance on localhost:9881 via the MCP connection `blender-opus55-max`).

Conventions: 1 Blender unit = 1 m, Z up, vehicles face +Y (exports to Godot -Z forward).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MASTER_BLEND = os.path.normcase(os.path.join(PROJECT_DIR, "Opus55ForzaMaxEffort.blend"))
ROOT_COLLECTION = "FORZA_GODOT"


def guard():
    """Refuse to touch anything unless the open file is exactly the project's master .blend."""
    cur = os.path.normcase(os.path.abspath(bpy.data.filepath)) if bpy.data.filepath else ""
    if cur != MASTER_BLEND:
        raise RuntimeError("ROUTING GUARD: open file '%s' is not the project master '%s'" % (cur, MASTER_BLEND))


# --------------------------------------------------------------------------------------------
# collections
def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    if parent is None:
        parent_col = bpy.context.scene.collection
    else:
        parent_col = parent
    if col.name not in [c.name for c in parent_col.children]:
        # unlink from other parents first so the hierarchy stays tidy
        for p in [bpy.context.scene.collection] + list(bpy.data.collections):
            if p != parent_col and col.name in [c.name for c in p.children]:
                p.children.unlink(col)
        parent_col.children.link(col)
    return col


def root_collection():
    return collection(ROOT_COLLECTION)


def sub_collection(*names):
    parent = root_collection()
    for n in names:
        parent = collection(n, parent)
    return parent


def clear_collection(col):
    for obj in list(col.all_objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
    for child in list(col.children):
        clear_collection(child)
        bpy.data.collections.remove(child)


def link(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    return obj


# --------------------------------------------------------------------------------------------
# materials (names are tags that the Godot side maps to runtime materials)
def _principled(mat):
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    return next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")


def _set_input(node, identifier, value):
    for s in node.inputs:
        if s.identifier == identifier:
            try:
                s.default_value = value
            except Exception:
                pass
            return


def material(name, color=(0.5, 0.5, 0.5), metallic=0.0, roughness=0.5, emission=None, emission_strength=0.0,
             alpha=1.0, coat=0.0):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    bsdf = _principled(mat)
    rgba = (color[0], color[1], color[2], 1.0)
    _set_input(bsdf, "Base Color", rgba)
    _set_input(bsdf, "Metallic", metallic)
    _set_input(bsdf, "Roughness", roughness)
    _set_input(bsdf, "Coat Weight", coat)
    if emission is not None:
        _set_input(bsdf, "Emission Color", (emission[0], emission[1], emission[2], 1.0))
        _set_input(bsdf, "Emission Strength", emission_strength)
    if alpha < 1.0:
        _set_input(bsdf, "Alpha", alpha)
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    mat.diffuse_color = rgba
    return mat


def std_materials(paint_color=(0.8, 0.1, 0.1)):
    """Creates/returns the standard vehicle material tags."""
    return {
        "Paint": material("Paint", paint_color, 0.6, 0.25, coat=1.0),
        "Glass": material("Glass", (0.05, 0.07, 0.09), 0.1, 0.03, alpha=0.5),
        "Chrome": material("Chrome", (0.9, 0.9, 0.92), 1.0, 0.06),
        "Rubber": material("Rubber", (0.03, 0.03, 0.03), 0.0, 0.9),
        "Rim": material("Rim", (0.65, 0.66, 0.68), 0.9, 0.25),
        "RimDark": material("RimDark", (0.08, 0.08, 0.09), 0.7, 0.35),
        "RimGold": material("RimGold", (0.75, 0.58, 0.25), 0.95, 0.25),
        "Trim": material("Trim", (0.025, 0.025, 0.03), 0.0, 0.45),
        "TrimMatte": material("TrimMatte", (0.05, 0.05, 0.055), 0.0, 0.8),
        "Carbon": material("Carbon", (0.04, 0.04, 0.045), 0.3, 0.2, coat=1.0),
        "Interior": material("Interior", (0.08, 0.08, 0.085), 0.0, 0.85),
        "Seat": material("Seat", (0.16, 0.11, 0.09), 0.0, 0.6),
        "Dash": material("Dash", (0.045, 0.045, 0.05), 0.0, 0.55),
        "Gauge": material("Gauge", (0.05, 0.06, 0.08), 0.0, 0.3, emission=(0.4, 0.7, 1.0), emission_strength=1.0),
        "LightHead": material("LightHead", (0.95, 0.95, 0.92), 0.3, 0.05, emission=(1, 0.96, 0.9), emission_strength=0.5),
        "LightTail": material("LightTail", (0.5, 0.02, 0.02), 0.0, 0.1, emission=(1, 0.05, 0.03), emission_strength=1.0),
        "LightReverse": material("LightReverse", (0.85, 0.85, 0.85), 0.0, 0.1),
        "LightIndicator": material("LightIndicator", (0.9, 0.45, 0.05), 0.0, 0.1, emission=(1, 0.5, 0.05), emission_strength=0.3),
        "Grille": material("Grille", (0.02, 0.02, 0.022), 0.4, 0.5),
        "Plate": material("Plate", (0.92, 0.92, 0.86), 0.0, 0.4),
        "Disc": material("Disc", (0.42, 0.42, 0.43), 0.85, 0.45),
        "Caliper": material("Caliper", (0.75, 0.08, 0.05), 0.0, 0.35),
        "Under": material("Under", (0.035, 0.035, 0.035), 0.0, 0.95),
        "Exhaust": material("Exhaust", (0.5, 0.48, 0.45), 0.9, 0.35),
        "Wood": material("Wood", (0.36, 0.2, 0.1), 0.0, 0.4, coat=0.5),
        "Canvas": material("Canvas", (0.12, 0.11, 0.1), 0.0, 0.95),
        "Mirror": material("Mirror", (0.9, 0.92, 0.95), 1.0, 0.02),
    }


# --------------------------------------------------------------------------------------------
# mesh helpers
def mesh_object(name, bm, col, materials=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    if materials:
        for m in materials:
            me.materials.append(m)
    return obj


def apply_modifiers(obj):
    """Bakes the modifier stack into the mesh without bpy.ops (works from any context)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    new_me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = new_me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def set_smooth(obj, angle_deg=40.0):
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    try:
        mod = obj.modifiers.new("Smooth", "SMOOTH_BY_ANGLE")
        mod["Input_1"] = math.radians(angle_deg)
    except Exception:
        try:
            me.set_sharp_from_angle(angle=math.radians(angle_deg))
        except Exception:
            pass


def shade_auto(obj, angle_deg=40.0):
    """Smooth shading with sharp edges above angle (baked, export friendly)."""
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(angle_deg))
    except Exception:
        pass


def box_uv(obj, scale=1.0):
    """Simple per-face box projection UVs (1 m = 1 UV unit)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 0:
                loop[uv].uv = (co.y * scale, co.z * scale)
            elif ax == 1:
                loop[uv].uv = (co.x * scale, co.z * scale)
            else:
                loop[uv].uv = (co.x * scale, co.y * scale)
    bm.to_mesh(me)
    bm.free()


def cylinder_bm(radius, depth, segments=24, axis="X", center=(0, 0, 0), cap=True):
    bm = bmesh.new()
    mat = Matrix.Identity(4)
    if axis == "X":
        mat = Matrix.Rotation(math.radians(90), 4, "Y")
    elif axis == "Y":
        mat = Matrix.Rotation(math.radians(90), 4, "X")
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments, radius1=radius, radius2=radius,
                          depth=depth, matrix=Matrix.Translation(Vector(center)) @ mat)
    return bm


def rounded_box_bm(size, center=(0, 0, 0), bevel=0.02, segments=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=segments,
                        affect="EDGES", profile=0.5)
    return bm


def join_bm(target, src, mat_index=0):
    """Appends src bmesh geometry into target, setting material index of new faces."""
    me = bpy.data.meshes.new("_tmp_join")
    src.to_mesh(me)
    src.free()
    n_before = len(target.faces)
    target.from_mesh(me)
    bpy.data.meshes.remove(me)
    target.faces.ensure_lookup_table()
    for f in target.faces[n_before:]:
        f.material_index = mat_index
    return target


def empty(name, col, location, size=0.1):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = size
    obj.location = location
    col.objects.link(obj)
    return obj


def select_only(objs):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def export_glb(objs, filepath):
    """Exports the given objects as a binary glTF (+Y up) with modifiers applied."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    select_only(objs)
    kwargs = dict(filepath=filepath, export_format="GLB", use_selection=True, export_apply=True,
                  export_yup=True, export_cameras=False, export_lights=False, export_animations=False,
                  export_materials="EXPORT", export_texcoords=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_lights", None)
        bpy.ops.export_scene.gltf(**kwargs)
    return filepath


def save_master():
    guard()
    bpy.ops.wm.save_mainfile()


# --------------------------------------------------------------------------------------------
# curve sampling
def pchip(points):
    """Monotone cubic Hermite interpolation through [(x, y), ...] sorted by x. Returns f(x)."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    n = len(xs)
    if n == 1:
        return lambda x: ys[0]
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0] = d[0]
    m[-1] = d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0] + m[0] * (x - xs[0]) if False else ys[0]
        if x >= xs[-1]:
            return ys[-1]
        lo, hi = 0, n - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] > x:
                hi = mid
            else:
                lo = mid
        i = lo
        t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
    return f


def smoothstep(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
