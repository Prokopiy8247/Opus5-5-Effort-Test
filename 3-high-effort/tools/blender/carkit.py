"""Parametric car construction kit for the Velora Roads project.

Executed inside the project's dedicated Blender instance (MCP on localhost:9879).
Blender convention used here: car faces +Y, +X is the right-hand side, Z up,
origin on the ground at the middle of the wheelbase. glTF export converts this to
Godot's -Z forward / Y up.

Bodies are lofted from cross-sections whose parameters are smooth (monotone cubic)
functions of the longitudinal position, so every car gets its own silhouette from
its spec instead of scaling a shared mesh.
"""
import bpy
import bmesh
import math
from bisect import bisect_right
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT_COLL = "FORZA_GODOT"
_CUR = {"body": None}


# --------------------------------------------------------------------------- utils
class Curve1D:
    """Monotone cubic (Fritsch-Carlson) interpolation through (x, y) keys."""

    def __init__(self, pts):
        pts = sorted(pts)
        xs, ys = [], []
        for x, y in pts:
            if xs and abs(x - xs[-1]) < 1e-6:
                ys[-1] = y
                continue
            xs.append(x)
            ys.append(y)
        self.x, self.y = xs, ys
        n = len(xs)
        if n == 1:
            self.m = [0.0]
            return
        d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
        m = [0.0] * n
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            m[i] = 0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) * 0.5
        for i in range(n - 1):
            if d[i] == 0:
                m[i] = m[i + 1] = 0.0
                continue
            a, b = m[i] / d[i], m[i + 1] / d[i]
            s = a * a + b * b
            if s > 9.0:
                t = 3.0 / math.sqrt(s)
                m[i], m[i + 1] = t * a * d[i], t * b * d[i]
        self.m = m

    def __call__(self, x):
        xs, ys, m = self.x, self.y, self.m
        if len(xs) == 1 or x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = bisect_right(xs, x) - 1
        h = xs[i + 1] - xs[i]
        t = (x - xs[i]) / h
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1])


def lerp(a, b, t):
    return a + (b - a) * t


def smooth01(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def get_coll(path):
    parent = bpy.context.scene.collection
    for name in path.split("/"):
        c = bpy.data.collections.get(name)
        if c is None:
            c = bpy.data.collections.new(name)
        if c.name not in parent.children.keys():
            parent.children.link(c)
        parent = c
    return parent


def clear_coll(coll):
    for ch in list(coll.children):
        clear_coll(ch)
        bpy.data.collections.remove(ch)
    for ob in list(coll.objects):
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data is not None and isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)


def link(ob, coll):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)


def new_obj(name, bm, coll, mats=()):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    return ob


def shade_smooth(ob, angle_deg=40.0):
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(angle_deg))
    except Exception:
        pass


def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def uv_project(ob, angle=66.0, margin=0.02):
    """Smart UV project without the operator context (bmesh cube-ish projection)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            co = l.vert.co
            if ax == 0:
                l[uv].uv = (co.y * 0.5, co.z * 0.5)
            elif ax == 1:
                l[uv].uv = (co.x * 0.5, co.z * 0.5)
            else:
                l[uv].uv = (co.x * 0.5, co.y * 0.5)
    bm.to_mesh(me)
    bm.free()


# ------------------------------------------------------------------------ materials
def material(name, color, metallic=0.0, roughness=0.5, emission=None, emit_strength=0.0,
             alpha=1.0, coat=0.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
    for key in ("Coat Weight", "Clearcoat"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = coat
            break
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emission, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = (*color, alpha)
    return m


def shared_materials():
    return {
        "trim": material("M_Trim", (0.035, 0.035, 0.037), 0.0, 0.55),
        "chrome": material("M_Chrome", (0.85, 0.86, 0.88), 1.0, 0.12),
        "glass": material("M_Glass", (0.05, 0.07, 0.08), 0.0, 0.05, alpha=0.45),
        "interior": material("M_Interior", (0.09, 0.085, 0.08), 0.0, 0.8),
        "seat": material("M_Seat", (0.16, 0.13, 0.11), 0.0, 0.75),
        "head": material("M_HeadLens", (0.9, 0.92, 0.95), 0.2, 0.08, emission=(1.0, 0.95, 0.85), emit_strength=0.0),
        "tail": material("M_TailLens", (0.75, 0.03, 0.03), 0.0, 0.15, emission=(1.0, 0.05, 0.03), emit_strength=0.0),
        "rev": material("M_RevLens", (0.5, 0.5, 0.52), 0.6, 0.15, emission=(1.0, 1.0, 1.0), emit_strength=0.0),
        "ind": material("M_IndLens", (0.9, 0.45, 0.05), 0.0, 0.2),
        "tire": material("M_Tire", (0.025, 0.025, 0.025), 0.0, 0.85),
        "disc": material("M_BrakeDisc", (0.35, 0.35, 0.36), 0.9, 0.35),
        "grille": material("M_Grille", (0.02, 0.02, 0.022), 0.3, 0.45),
        "plate": material("M_Plate", (0.92, 0.9, 0.82), 0.0, 0.4),
        "lamp": material("M_LampHousing", (0.6, 0.6, 0.62), 1.0, 0.2),
    }


# --------------------------------------------------------------------------- body
SEG_UNDER, SEG_SILL = 0, 1
SEG_WIN = 6
SEG_TOP = (9, 10)


def body_functions(s):
    L, W, wb = s["L"], s["W"], s["wb"]
    yf_end = s["fo"] + wb / 2
    yr_end = yf_end - L
    yfa, yra = wb / 2, -wb / 2
    r = s["wheel_r"]
    hw0 = W / 2
    f = {"yf_end": yf_end, "yr_end": yr_end, "yfa": yfa, "yra": yra}

    # top surface (hood / roof / deck)
    zt_keys = s.get("zt_keys")
    if zt_keys is None:
        zt_keys = [
            (yr_end, s["tail_z"] - s.get("tail_drop", 0.06)),
            (yr_end + 0.12, s["tail_z"] + 0.02),
            (s["deck_y"], s["deck_z"]),
            (s["roof_rear_y"], s["roof_z"] - 0.01),
            (lerp(s["roof_rear_y"], s["roof_front_y"], 0.5), s["roof_z"]),
            (s["roof_front_y"], s["roof_z"] - 0.01),
            (s["cowl_y"], s["cowl_z"]),
            (yf_end - 0.16, s["nose_z"] + 0.02),
            (yf_end, s["nose_z"] - s.get("nose_drop", 0.11)),
        ]
        if "trunk_keys" in s:
            zt_keys += s["trunk_keys"]
        if "hood_keys" in s:
            zt_keys += s["hood_keys"]
    f["zt"] = Curve1D(zt_keys)
    f["zs"] = Curve1D(s.get("belt_keys", [(yr_end, s["belt_r"]), (yf_end, s["belt_f"])]))
    zb_mid = s["ride"]
    f["zb"] = Curve1D([
        (yr_end, zb_mid + s.get("rear_lift", 0.14)),
        (yra - r * 1.05, zb_mid),
        (yfa + r * 1.05, zb_mid),
        (yf_end - 0.25, zb_mid + s.get("front_lift", 0.1) * 0.35),
        (yf_end, zb_mid + s.get("front_lift", 0.1)),
    ])
    nt, tt = s.get("nose_taper", 0.86), s.get("tail_taper", 0.92)
    f["hw"] = Curve1D([
        (yr_end, hw0 * tt),
        (yr_end + 0.18, hw0 * lerp(tt, 1.0, 0.75)),
        (yr_end + 0.6, hw0 * 0.995),
        (0.0, hw0 * s.get("waist", 1.0)),
        (yf_end - 0.7, hw0 * 0.99),
        (yf_end - 0.2, hw0 * lerp(nt, 1.0, 0.6)),
        (yf_end, hw0 * nt),
    ])
    flare_f, flare_r = s.get("flare_f", 0.0), s.get("flare_r", 0.0)

    def flare(y):
        a = math.exp(-((y - yfa) / (r * 1.05)) ** 2) * flare_f
        b = math.exp(-((y - yra) / (r * 1.05)) ** 2) * flare_r
        return a + b
    f["flare"] = flare

    cr0, cr1 = s["roof_rear_y"], s["roof_front_y"]
    dk, cw = s["deck_y"], s["cowl_y"]

    def cabin(y):
        if y <= dk or y >= cw:
            return 0.0
        if y < cr0:
            return smooth01(dk, cr0, y)
        if y > cr1:
            return 1.0 - smooth01(cr1, cw, y)
        return 1.0
    f["cabin"] = cabin
    return f


def section_profile(s, f, y):
    """Half profile points (x >= 0) from bottom centre to top centre."""
    hw = f["hw"](y)
    hwl = hw + f["flare"](y)
    zb = f["zb"](y)
    zs = f["zs"](y)
    zt = max(f["zt"](y), zs + 0.035)
    c = f["cabin"](y)
    tumble = s.get("tumble", 0.78)
    tw = hw * lerp(s.get("deck_round", 0.88), tumble, c)
    crown = lerp(s.get("hood_crown", 0.045), s.get("roof_crown", 0.06), c)
    hws = hw * s.get("shoulder", 0.965)
    p5 = Vector((hws, zs))
    p8 = Vector((tw, zt - crown))
    p6 = p5.lerp(p8, 0.14)
    p7 = p5.lerp(p8, 0.86)
    side_h = max(zs - zb, 0.05)
    pts = [
        Vector((0.0, zb)),
        Vector((hwl * 0.78, zb)),
        Vector((hwl * 0.965, zb + min(0.07, side_h * 0.2))),
        Vector((hwl, zb + side_h * s.get("bulge_z", 0.42))),
        Vector((lerp(hwl, hw, 0.6) * 0.995, zs - side_h * 0.13)),
        p5, p6, p7, p8,
        Vector((tw - s.get("rail", 0.075), zt - crown * 0.5)),
        Vector((tw * 0.45, zt - crown * 0.1)),
        Vector((0.0, zt)),
    ]
    return pts


def station_list(s, f, step=0.075):
    ys = []
    y = f["yr_end"]
    while y < f["yf_end"] - 1e-4:
        ys.append(y)
        y += step
    ys.append(f["yf_end"])
    keys = [s["deck_y"], s["roof_rear_y"], s["roof_front_y"], s["cowl_y"],
            s["glass_rear_y"], s["glass_front_y"]]
    keys += s.get("extra_stations", [])
    if s.get("doors", 2) == 4:
        b = s["b_pillar_y"]
        keys += [b - 0.045, b + 0.045]
    for k in s.get("open_regions", []):
        keys += [k[0], k[1]]
    for k in keys:
        ys.append(k)
    ys.sort()
    out = []
    for y in ys:
        if not out or y - out[-1] > 0.03:
            out.append(y)
        elif abs(y - out[-1]) <= 0.03 and y in keys:
            out[-1] = y
    out[0], out[-1] = f["yr_end"], f["yf_end"]
    return out


def classify_face(s, f, y, seg):
    """Material slot for a cage face: 0 paint, 1 trim, 2 glass, 3 open (deleted later)."""
    for (a, b, segs) in s.get("open_regions", []):
        if a <= y <= b and seg in segs:
            return 3
    if seg == SEG_UNDER:
        return 1
    if seg == SEG_SILL and s.get("black_sill", True):
        return 1
    c = f["cabin"](y)
    if seg == SEG_WIN and s["glass_rear_y"] <= y <= s["glass_front_y"] and c > 0.2:
        if s.get("doors", 2) == 4 and abs(y - s["b_pillar_y"]) < 0.045:
            return 0
        for (a, b) in s.get("pillars", []):
            if a <= y <= b:
                return 0
        return 2
    if seg in SEG_TOP:
        if s["cowl_y"] - s.get("ws_inset", 0.04) > y > s["roof_front_y"] + 0.02:
            return 2
        if s.get("rear_glass", True) and s["deck_y"] + 0.04 < y < s["roof_rear_y"] - 0.02:
            return 2
        if s.get("glass_roof") and s["roof_rear_y"] + 0.15 < y < s["roof_front_y"] - 0.15:
            return 2
    return 0


def build_body(s, coll, mats):
    f = body_functions(s)
    ys = station_list(s, f)
    bm = bmesh.new()
    rings = []
    for y in ys:
        prof = section_profile(s, f, y)
        right = [bm.verts.new((p.x, y, p.y)) for p in prof]
        left = [bm.verts.new((-p.x, y, p.y)) for p in prof[1:-1]]
        rings.append((right, left))
    n = len(rings[0][0])
    faces_info = []
    for i in range(len(rings) - 1):
        ra, la = rings[i]
        rb, lb = rings[i + 1]
        ym = (ys[i] + ys[i + 1]) * 0.5
        for j in range(n - 1):
            mi = classify_face(s, f, ym, j)
            # right side (outward normal +x): order a_j, a_j+1, b_j+1, b_j
            fr = bm.faces.new((ra[j], rb[j], rb[j + 1], ra[j + 1]))
            fr.material_index = mi
            # left side uses mirrored ring; centre verts (0 and n-1) are shared
            lj = ra[j] if j == 0 else la[j - 1]
            lj1 = ra[j + 1] if j + 1 == n - 1 else la[j]
            ljb = rb[j] if j == 0 else lb[j - 1]
            lj1b = rb[j + 1] if j + 1 == n - 1 else lb[j]
            fl = bm.faces.new((lj, lj1, lj1b, ljb))
            fl.material_index = mi
    # end caps: inset ring then poke
    for idx, out_dir in ((0, -1.0), (len(rings) - 1, 1.0)):
        r, l = rings[idx]
        loop = r + list(reversed(l))
        cen = sum((v.co for v in loop), Vector()) / len(loop)
        inner = []
        for v in loop:
            co = cen + (v.co - cen) * 0.82
            co.y += out_dir * s.get("cap_bulge", 0.035)
            inner.append(bm.verts.new(co))
        m = len(loop)
        for k in range(m):
            a, b = loop[k], loop[(k + 1) % m]
            ia, ib = inner[k], inner[(k + 1) % m]
            fa = bm.faces.new((a, b, ib, ia) if out_dir > 0 else (b, a, ia, ib))
            fa.material_index = 0
        cap = bm.faces.new(inner if out_dir > 0 else list(reversed(inner)))
        cap.material_index = 0
        bmesh.ops.poke(bm, faces=[cap])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj("Body", bm, coll, [mats["paint"], mats["trim"], mats["glass"], mats["trim"]])
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = s.get("subd", 1)
    sub.render_levels = sub.levels
    apply_modifiers(ob)
    # wheel arches
    r = s["wheel_r"]
    yfa = s.get("axle_f_y", f["yfa"])
    yra = s.get("axle_r_y", f["yra"])
    for ya, sc in ((yfa, s.get("arch_f", 1.0)), (yra, s.get("arch_r", 1.0))):
        cb = bmesh.new()
        bmesh.ops.create_cone(cb, cap_ends=True, segments=40, radius1=(r + 0.045) * sc,
                              radius2=(r + 0.045) * sc, depth=s["W"] + 1.0)
        bmesh.ops.rotate(cb, verts=cb.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
        bmesh.ops.translate(cb, verts=cb.verts, vec=(0, ya, r + s.get("arch_lift", 0.02)))
        cutter = new_obj("_arch_cutter", cb, coll)
        mod = ob.modifiers.new("Arch", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        apply_modifiers(ob)
        bpy.data.objects.remove(cutter, do_unlink=True)
    # delete open regions (cockpit of roadsters, pickup bed)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    dead = [fc for fc in bm.faces if fc.material_index == 3]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    shade_smooth(ob, s.get("smooth_angle", 50))
    return ob, f


def split_glass(body, coll, mats):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    gfaces = [fc for fc in bm.faces if fc.material_index == 2]
    gb = bmesh.new()
    vmap = {}
    for fc in gfaces:
        vs = []
        for v in fc.verts:
            if v.index not in vmap:
                # glass sits slightly inside the body opening
                vmap[v.index] = gb.verts.new(v.co - fc.normal * 0.004)
            vs.append(vmap[v.index])
        try:
            gb.faces.new(vs)
        except ValueError:
            pass
    bmesh.ops.delete(bm, geom=gfaces, context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    if not gb.faces:
        gb.verts.new((0, 0, 0.5))
        gb.verts.new((0.001, 0, 0.5))
        gb.verts.new((0, 0.001, 0.5))
        gb.faces.new(list(gb.verts))
    g = new_obj("Glass", gb, coll, [mats["glass"]])
    shade_smooth(g, 60)
    return g


def interior_shell(body, s, f, coll, mats):
    """Inward-facing copy of the cabin part of the body so the cockpit camera sees trim."""
    y0 = max(s["deck_y"] - 0.1, f["yr_end"] + 0.12)
    y1 = min(s["cowl_y"] + 0.25, f["yf_end"] - 0.3)
    zmid = (s["ride"] + s.get("roof_z", 1.3)) * 0.5
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    keep = [fc for fc in bm.faces if y0 < fc.calc_center_median().y < y1
            and fc.calc_center_median().z > s["ride"] + 0.12]
    out = bmesh.new()
    vmap = {}
    for fc in keep:
        vs = []
        for v in fc.verts:
            if v.index not in vmap:
                inward = (Vector((0.0, v.co.y, zmid)) - v.co).normalized()
                vmap[v.index] = out.verts.new(v.co + inward * 0.02)
            vs.append(vmap[v.index])
        try:
            nf = out.faces.new(list(reversed(vs)))
            nf.material_index = 0
        except ValueError:
            pass
    bm.free()
    ob = new_obj("InteriorShell", out, coll, [mats["interior"]])
    shade_smooth(ob, 60)
    return ob


# ---------------------------------------------------------------------- primitives
def rounded_box(name, size, coll, mat, bevel=0.02, segs=2, loc=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, affect="EDGES",
                        profile=0.5)
    bmesh.ops.translate(bm, verts=bm.verts, vec=loc)
    ob = new_obj(name, bm, coll, [mat])
    shade_smooth(ob, 35)
    return ob


def cylinder(name, r, depth, coll, mat, loc=(0, 0, 0), axis="X", segs=24, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=loc)
    ob = new_obj(name, bm, coll, [mat])
    shade_smooth(ob, 35)
    return ob


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        objs[0].data.name = name
        return objs[0]
    bm = bmesh.new()
    mats = []
    for o in objs:
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        remap = []
        for m in o.data.materials:
            if m is None:
                remap.append(0)
                continue
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        tb = bmesh.new()
        tb.from_mesh(tmp)
        for fc in tb.faces:
            if remap:
                fc.material_index = remap[fc.material_index]
        tmp2 = bpy.data.meshes.new("_tmp")
        tb.to_mesh(tmp2)
        tb.free()
        bm.from_mesh(tmp2)
        bpy.data.meshes.remove(tmp2)
        bpy.data.meshes.remove(tmp)
    coll = objs[0].users_collection[0]
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)
    ob = new_obj(name, bm, coll, mats)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def surface_patch(body, name, center, out_dir, u_dir, size_u, size_v, coll, mat,
                  offset=0.004, shape="rect", res=10, bvh=None, thickness=0.0):
    """Mesh patch conforming to the body: rays are cast from outside along -out_dir."""
    if bvh is None:
        bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    out_dir = Vector(out_dir).normalized()
    u_dir = Vector(u_dir).normalized()
    v_dir = out_dir.cross(u_dir).normalized()
    center = Vector(center)
    bm = bmesh.new()
    grid = {}
    for i in range(res + 1):
        for j in range(res + 1):
            u = i / res * 2 - 1
            v = j / res * 2 - 1
            if shape == "ellipse":
                uu = u * math.sqrt(max(0.0, 1 - v * v / 2))
                vv = v * math.sqrt(max(0.0, 1 - u * u / 2))
                u, v = uu, vv
            elif shape == "slant":
                u = u + v * 0.35
            p = center + u_dir * (u * size_u * 0.5) + v_dir * (v * size_v * 0.5)
            hit = bvh.ray_cast(p + out_dir * 1.5, -out_dir, 3.0)
            if hit[0] is None:
                continue
            grid[(i, j)] = bm.verts.new(hit[0] + hit[1] * offset)
    for i in range(res):
        for j in range(res):
            q = [grid.get((i, j)), grid.get((i + 1, j)), grid.get((i + 1, j + 1)), grid.get((i, j + 1))]
            if all(q):
                try:
                    bm.faces.new(q)
                except ValueError:
                    pass
    if not bm.faces:
        bm.free()
        return None
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # make normals point outward
    fc = bm.faces[0]
    if fc.normal.dot(out_dir) < 0 and abs(out_dir.z) < 0.9:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    if thickness > 0:
        r = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
        verts = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, verts=verts, vec=out_dir * thickness)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm, coll, [mat])
    shade_smooth(ob, 30)
    return ob


# --------------------------------------------------------------------------- wheels
def make_wheel(name, s, side, coll, mats, rim_mat):
    r, w = s["wheel_r"], s["wheel_w"]
    rim_r = r * s.get("rim_ratio", 0.66)
    sw = 1.0 if side > 0 else -1.0
    # tyre: revolve a rounded rectangular cross-section about X
    bm = bmesh.new()
    prof = []
    hw = w / 2
    sidewall = r - rim_r
    rr = min(0.035, sidewall * 0.35)
    pts = [(-hw * 0.92, rim_r), (-hw, rim_r + sidewall * 0.3), (-hw, r - rr)]
    for k in range(1, 4):
        a = math.pi / 2 * k / 4
        pts.append((-hw + rr - rr * math.cos(a), r - rr + rr * math.sin(a)))
    groove = s.get("tread_groove", 0.006)
    ng = 3
    for k in range(ng * 2 + 1):
        x = -hw + rr + (2 * hw - 2 * rr) * k / (ng * 2)
        pts.append((x, r - (groove if k % 2 == 1 else 0.0)))
    for k in range(3, 0, -1):
        a = math.pi / 2 * k / 4
        pts.append((hw - rr + rr * math.cos(a), r - rr + rr * math.sin(a)))
    pts += [(hw, r - rr), (hw, rim_r + sidewall * 0.3), (hw * 0.92, rim_r)]
    prof = [bm.verts.new((x, 0.0, z)) for x, z in pts]
    edges = [bm.edges.new((prof[i], prof[i + 1])) for i in range(len(prof) - 1)]
    bmesh.ops.spin(bm, geom=prof + edges, cent=(0, 0, 0), axis=(1, 0, 0), angle=math.pi * 2,
                   steps=36, use_duplicate=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tyre = new_obj(name + "_tyre", bm, coll, [mats["tire"]])
    shade_smooth(tyre, 45)
    parts = [tyre]
    # rim barrel + face
    face_x = sw * (hw * 0.55)
    barrel = cylinder(name + "_barrel", rim_r * 0.98, w * 0.86, coll, rim_mat, segs=32)
    bmb = bmesh.new()
    bmb.from_mesh(barrel.data)
    caps = [fc for fc in bmb.faces if abs(fc.normal.x) > 0.9]
    bmesh.ops.delete(bmb, geom=caps, context="FACES")
    bmb.to_mesh(barrel.data)
    bmb.free()
    parts.append(barrel)
    style = s.get("rim_style", "five")
    hub = cylinder(name + "_hub", rim_r * 0.22, 0.05, coll, rim_mat, loc=(face_x, 0, 0), segs=16)
    parts.append(hub)
    cap = cylinder(name + "_cap", rim_r * 0.12, 0.02, coll, mats["chrome"], loc=(face_x + sw * 0.03, 0, 0), segs=12)
    parts.append(cap)

    # dark disc behind the spokes so the rim reads as a face
    back = cylinder(name + "_back", rim_r * 0.94, 0.01, coll, mats["trim"], loc=(face_x - sw * 0.06, 0, 0), segs=32)
    parts.append(back)
    nsp = {"five": 5, "multi": 10, "mesh": 14, "six": 6, "turbine": 18, "steel": 0, "y": 5}.get(style, 5)
    spoke_w = {"five": 0.055, "multi": 0.025, "mesh": 0.012, "six": 0.045, "turbine": 0.02, "y": 0.035}.get(style, 0.05)
    for k in range(nsp):
        a = 2 * math.pi * k / nsp
        length = rim_r * 0.8
        sp = rounded_box(name + "_sp%d" % k, (0.03, spoke_w, length), coll, rim_mat, bevel=0.006, segs=1,
                         loc=(0, 0, rim_r * 0.15 + length / 2))
        if style == "turbine":
            sp.rotation_euler = (a, 0.0, 0.0)
            sp.data.transform(Matrix.Rotation(0.5, 4, "Z"))
        sp.rotation_euler = (a, 0.0, 0.0)
        sp.location = (face_x - sw * 0.01, 0, 0)
        parts.append(sp)
        if style == "y":
            for off in (-0.28, 0.28):
                sp2 = rounded_box(name + "_spy%d" % k, (0.025, spoke_w * 0.7, length * 0.45), coll, rim_mat,
                                  bevel=0.004, segs=1, loc=(0, 0, rim_r * 0.62 + length * 0.2))
                sp2.rotation_euler = (a + off, 0.0, 0.0)
                sp2.location = (face_x - sw * 0.01, 0, 0)
                parts.append(sp2)
    if style == "steel":
        disc = cylinder(name + "_steel", rim_r * 0.9, 0.03, coll, rim_mat, loc=(face_x - sw * 0.01, 0, 0), segs=32)
        parts.append(disc)
        for k in range(6):
            a = 2 * math.pi * k / 6
            hole = cylinder(name + "_hole%d" % k, rim_r * 0.1, 0.035, coll, mats["trim"],
                            loc=(face_x, math.cos(a) * rim_r * 0.55, math.sin(a) * rim_r * 0.55), segs=10)
            parts.append(hole)
    # brake disc rotates with the wheel
    disc = cylinder(name + "_disc", rim_r * 0.78, 0.028, coll, mats["disc"], loc=(-sw * w * 0.1, 0, 0), segs=28)
    parts.append(disc)
    for ob in parts:
        for p in ob.data.polygons:
            p.use_smooth = True
    wheel = join(parts, name)
    uv_project(wheel)
    return wheel


def make_caliper(name, s, side, coll, mat):
    r = s["wheel_r"] * s.get("rim_ratio", 0.66)
    sw = 1.0 if side > 0 else -1.0
    cal = rounded_box(name, (0.05, 0.13, 0.07), coll, mat, bevel=0.012, segs=2,
                      loc=(sw * 0.005, -0.0, r * 0.62))
    cal.data.transform(Matrix.Rotation(math.radians(-35), 4, "X"))
    return cal


# ------------------------------------------------------------------------ interior
def build_interior(s, f, coll, mats):
    parts = []
    hw = s["W"] / 2
    seat_y = s.get("seat_y", (s["roof_rear_y"] + s["roof_front_y"]) * 0.5 - 0.15)
    floor_z = s["ride"] + 0.12
    seat_x = s.get("seat_x", hw * 0.42)
    zs = f["zs"](seat_y)
    for sx in (-seat_x, seat_x):
        cushion = rounded_box("seat_c", (0.48, 0.5, 0.12), coll, mats["seat"], bevel=0.04, segs=2,
                              loc=(sx, seat_y, floor_z + 0.18))
        back = rounded_box("seat_b", (0.48, 0.12, 0.62), coll, mats["seat"], bevel=0.04, segs=2,
                           loc=(sx, seat_y - 0.28, floor_z + 0.5))
        back.data.transform(Matrix.Translation((sx, seat_y - 0.28, floor_z + 0.24)) @
                            Matrix.Rotation(math.radians(-14), 4, "X") @
                            Matrix.Translation((-sx, -(seat_y - 0.28), -(floor_z + 0.24))))
        head = rounded_box("seat_h", (0.28, 0.1, 0.18), coll, mats["seat"], bevel=0.03, segs=2,
                           loc=(sx, seat_y - 0.37, floor_z + 0.9))
        parts += [cushion, back, head]
    if s.get("rear_seats", False):
        rs = rounded_box("rseat", (hw * 1.5, 0.5, 0.14), coll, mats["seat"], bevel=0.04, segs=2,
                         loc=(0, seat_y - 0.85, floor_z + 0.2))
        rb = rounded_box("rseatb", (hw * 1.5, 0.12, 0.55), coll, mats["seat"], bevel=0.04, segs=2,
                         loc=(0, seat_y - 1.12, floor_z + 0.5))
        parts += [rs, rb]
    floor = rounded_box("floor", (hw * 1.8, (s["cowl_y"] - s["deck_y"]) * 0.9, 0.04), coll, mats["interior"],
                        bevel=0.0, loc=(0, (s["cowl_y"] + s["deck_y"]) * 0.5, floor_z))
    dash_y = s.get("dash_y", s["cowl_y"] - 0.18)
    dash_z = f["zs"](dash_y) - 0.02
    dash = rounded_box("dash", (hw * 1.82, 0.42, 0.2), coll, mats["interior"], bevel=0.05, segs=2,
                       loc=(0, dash_y, dash_z - 0.05))
    cluster = rounded_box("cluster", (0.36, 0.12, 0.09), coll, mats["trim"], bevel=0.02, segs=1,
                          loc=(-seat_x, dash_y - 0.18, dash_z + 0.06))
    console = rounded_box("console", (0.22, (dash_y - seat_y) + 0.3, 0.2), coll, mats["interior"], bevel=0.03,
                          loc=(0, (dash_y + seat_y) * 0.5 - 0.1, floor_z + 0.12))
    lever = cylinder("lever", 0.012, 0.18, coll, mats["chrome"], loc=(0, seat_y + 0.25, floor_z + 0.3), axis="Z")
    knob = rounded_box("knob", (0.045, 0.045, 0.045), coll, mats["trim"], bevel=0.02, segs=2,
                       loc=(0, seat_y + 0.25, floor_z + 0.4))
    parts += [floor, dash, cluster, console, lever, knob]
    interior = join(parts, "Interior")
    uv_project(interior)
    # steering wheel (separate, pivot at hub, faces the driver)
    sw_y = dash_y - 0.32
    sw_z = dash_z + 0.0
    sw_x = -seat_x  # left-hand drive
    bm = bmesh.new()
    rings = []
    R, rr = 0.18, 0.017
    for i in range(32):
        a = 2 * math.pi * i / 32
        ring = []
        for j in range(8):
            b = 2 * math.pi * j / 8
            x = (R + rr * math.cos(b)) * math.cos(a)
            z = (R + rr * math.cos(b)) * math.sin(a)
            yv = rr * math.sin(b)
            ring.append(bm.verts.new((x, yv, z)))
        rings.append(ring)
    for i in range(32):
        for j in range(8):
            a = rings[i][j]; b = rings[(i + 1) % 32][j]; c = rings[(i + 1) % 32][(j + 1) % 8]; d = rings[i][(j + 1) % 8]
            bm.faces.new((a, b, c, d))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    wheel_ob = new_obj("SteeringWheel_rim", bm, coll, [mats["trim"]])
    hubp = cylinder("SteeringWheel_hub", 0.05, 0.05, coll, mats["trim"], axis="Y", segs=16)
    spokes = []
    for a in (0.0, math.pi, -math.pi / 2):
        sp = rounded_box("sws", (0.16, 0.02, 0.03), coll, mats["trim"], bevel=0.008, segs=1, loc=(0.09, 0, 0))
        sp.data.transform(Matrix.Rotation(a, 4, "Y"))
        spokes.append(sp)
    swo = join([wheel_ob, hubp] + spokes, "SteeringWheel")
    # tilt: wheel plane faces rearward/up
    swo.data.transform(Matrix.Rotation(math.radians(-22), 4, "X"))
    swo.location = (sw_x, sw_y, sw_z)
    col = cylinder("column", 0.025, 0.3, coll, mats["trim"], axis="Y",
                   loc=(sw_x, sw_y + 0.17, sw_z - 0.05))
    interior2 = join([interior, col], "Interior")
    return interior2, swo, (sw_x, sw_y, sw_z), (seat_x, seat_y, floor_z)


# ------------------------------------------------------------------------- details
def add_details(s, f, body, coll, mats):
    out = {"Lights_Head": [], "Lights_Tail": [], "Lights_Reverse": [], "Lights_Brake": [], "Trim": [],
           "Chrome": [], "Ind": []}
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    yF, yR = f["yf_end"], f["yr_end"]
    hw = s["W"] / 2
    d = s
    hl = d.get("headlight", {})
    hl_shape = hl.get("shape", "rect")
    hz = hl.get("z", f["zs"](yF) - 0.06)
    hx = hl.get("x", hw * 0.68)
    for sx in (-1, 1):
        p = surface_patch(body, "hl", (sx * hx, yF, hz), (sx * hl.get("wrap", 0.25), 1.0, hl.get("up", 0.15)),
                          (1, 0, 0), hl.get("w", 0.3), hl.get("h", 0.1), coll, mats["head"],
                          shape=hl_shape, offset=0.006, bvh=bvh, res=10)
        out["Lights_Head"].append(p)
        if hl.get("twin"):
            p2 = surface_patch(body, "hl2", (sx * (hx - hl["twin"]), yF, hz), (0, 1, 0.1), (1, 0, 0),
                               hl.get("w", 0.3) * 0.8, hl.get("h", 0.1) * 0.8, coll, mats["head"],
                               shape=hl_shape, offset=0.006, bvh=bvh, res=10)
            out["Lights_Head"].append(p2)
        # indicator
        ip = surface_patch(body, "ind", (sx * (hw * 0.86), yF - 0.05, hz - 0.11), (sx * 0.6, 1.0, 0.0), (0, 0, 1),
                           0.04, 0.08, coll, mats["ind"], offset=0.005, bvh=bvh, res=4)
        out["Ind"].append(ip)
    tl = d.get("taillight", {})
    tz = tl.get("z", f["zs"](yR) - 0.05)
    tx = tl.get("x", hw * 0.72)
    if tl.get("bar"):
        p = surface_patch(body, "tl", (0, yR, tz), (0, -1, 0.1), (1, 0, 0), hw * 1.7, tl.get("h", 0.06), coll,
                          mats["tail"], offset=0.006, bvh=bvh, res=24)
        out["Lights_Tail"].append(p)
    for sx in (-1, 1):
        if not tl.get("bar"):
            p = surface_patch(body, "tl", (sx * tx, yR, tz), (sx * tl.get("wrap", 0.3), -1.0, 0.05), (1, 0, 0),
                              tl.get("w", 0.3), tl.get("h", 0.1), coll, mats["tail"],
                              shape=tl.get("shape", "rect"), offset=0.006, bvh=bvh, res=10)
            out["Lights_Tail"].append(p)
        rp = surface_patch(body, "rev", (sx * (tx - tl.get("w", 0.3) * 0.3), yR, tz - tl.get("h", 0.1) * 0.62),
                           (0, -1.0, 0.0), (1, 0, 0), 0.08, 0.035, coll, mats["rev"], offset=0.0085, bvh=bvh, res=4)
        out["Lights_Reverse"].append(rp)
    # third brake light at the top of the rear window / tailgate
    if s.get("roof_z", 0) > 0 and s.get("cabin_closed", True):
        by = s["roof_rear_y"] - 0.02
        p = surface_patch(body, "cbl", (0, by, f["zt"](by)), (0, -0.3, 1.0), (1, 0, 0), 0.32, 0.03, coll,
                          mats["tail"], offset=0.006, bvh=bvh, res=6)
        out["Lights_Brake"].append(p)
    # grille
    g = d.get("grille", {})
    if g.get("w", 0.6) > 0:
        gp = surface_patch(body, "grille", (0, yF, g.get("z", hz - 0.06)), (0, 1, 0.05), (1, 0, 0),
                           g.get("w", hw * 0.9), g.get("h", 0.12), coll,
                           mats["chrome"] if g.get("chrome") else mats["grille"], offset=0.005, bvh=bvh, res=12,
                           shape=g.get("shape", "rect"))
        out["Trim"].append(gp)
        if g.get("slats", 0):
            for k in range(g["slats"]):
                zz = g.get("z", hz - 0.06) - g.get("h", 0.12) * 0.4 + g.get("h", 0.12) * 0.8 * k / max(1, g["slats"] - 1)
                sl = surface_patch(body, "slat", (0, yF, zz), (0, 1, 0.05), (1, 0, 0), g.get("w", hw * 0.9) * 0.96,
                                   0.012, coll, mats["chrome"], offset=0.012, bvh=bvh, res=8)
                out["Chrome"].append(sl)
    # lower intake
    li = d.get("intake", {"w": hw * 1.1, "h": 0.08})
    if li.get("w", 0) > 0:
        ip = surface_patch(body, "intake", (0, yF, f["zb"](yF) + li.get("dz", 0.1)), (0, 1, -0.1), (1, 0, 0),
                           li["w"], li["h"], coll, mats["grille"], offset=0.004, bvh=bvh, res=12)
        out["Trim"].append(ip)
    # plates
    for yy, nd, zz in ((yF, 1, d.get("plate_zf", f["zb"](yF) + 0.2)), (yR, -1, d.get("plate_zr", tz - 0.16))):
        pp = surface_patch(body, "plate", (0, yy, zz), (0, nd, 0.0), (1, 0, 0), 0.46, 0.11, coll, mats["plate"],
                           offset=0.007, bvh=bvh, res=6)
        out["Trim"].append(pp)
    # rear diffuser / bumper lower
    dp = surface_patch(body, "diff", (0, yR, f["zb"](yR) + 0.05), (0, -1, -0.2), (1, 0, 0), hw * 1.5, 0.1, coll,
                       mats["trim"], offset=0.004, bvh=bvh, res=10)
    out["Trim"].append(dp)
    # door seams (dark thin lines) and handles
    if s.get("lite"):
        return out
    door_front = s["cowl_y"] - 0.05
    door_rear = s.get("door_rear_y", s["glass_rear_y"] + 0.05)
    seam_m = mats["trim"]
    for sx in (-1, 1):
        for yy in ([door_front, door_rear] + ([s["b_pillar_y"]] if s.get("doors", 2) == 4 else [])):
            zc = (f["zb"](yy) + f["zs"](yy)) * 0.5 + 0.03
            hgt = (f["zs"](yy) - f["zb"](yy)) * 0.78
            sp = surface_patch(body, "seam", (sx * hw, yy, zc), (sx, 0, 0), (0, 1, 0), 0.008, hgt, coll, seam_m,
                               offset=0.0025, bvh=bvh, res=6)
            out["Trim"].append(sp)
        hy = door_rear + 0.18
        if s.get("doors", 2) == 4:
            hy2 = s["b_pillar_y"] + 0.2
            hp2 = surface_patch(body, "handle", (sx * hw, hy2, f["zs"](hy2) - 0.07), (sx, 0, 0), (0, 1, 0), 0.14,
                                0.03, coll, mats["chrome"], offset=0.006, bvh=bvh, res=4, thickness=0.008)
            out["Chrome"].append(hp2)
        hp = surface_patch(body, "handle", (sx * hw, hy, f["zs"](hy) - 0.07), (sx, 0, 0), (0, 1, 0), 0.14, 0.03,
                           coll, mats["chrome"], offset=0.006, bvh=bvh, res=4, thickness=0.008)
        out["Chrome"].append(hp)
    # mirrors
    if s.get("mirrors", True):
        my = s["cowl_y"] - 0.12
        mz = f["zs"](my) + 0.08
        for sx in (-1, 1):
            hx = f["hw"](my) * s.get("shoulder", 0.965)
            arm = rounded_box("marm", (0.12, 0.05, 0.03), coll, mats["trim"], bevel=0.01, segs=1,
                              loc=(sx * (hx + 0.04), my, mz - 0.02))
            head = rounded_box("mhead", (0.15, 0.08, 0.1), coll, mats["paint"], bevel=0.03, segs=2,
                               loc=(sx * (hx + 0.12), my - 0.01, mz + 0.02))
            glass = rounded_box("mglass", (0.12, 0.01, 0.075), coll, mats["chrome"], bevel=0.004, segs=1,
                                loc=(sx * (hx + 0.12), my - 0.055, mz + 0.02))
            out["Trim"] += [arm, glass]
            out.setdefault("PaintParts", []).append(head)
    # exhausts
    for ex in s.get("exhaust", [(0.35, 0.05)]):
        for sx in ((-1, 1) if s.get("exhaust_dual", True) else (1,)):
            ez = f["zb"](yR) + ex[1] + 0.06
            tip = cylinder("exh", 0.04, 0.16, coll, mats["chrome"], axis="Y", loc=(sx * ex[0], yR + 0.03, ez), segs=16)
            inner = cylinder("exhi", 0.032, 0.02, coll, mats["trim"], axis="Y", loc=(sx * ex[0], yR - 0.045, ez), segs=16)
            out["Chrome"].append(tip)
            out["Trim"].append(inner)
    # arch liners so the body shell is not see-through in the wheel wells
    r = s["wheel_r"]
    for ya in (s.get("axle_f_y", f["yfa"]), s.get("axle_r_y", f["yra"])):
        for sx in (-1, 1):
            bm = bmesh.new()
            segs = 20
            rad = r + 0.05
            x0 = sx * (hw - 0.02)
            x1 = sx * (hw - min(0.36, s["wheel_w"] + 0.12))
            vs0, vs1 = [], []
            for k in range(segs + 1):
                a = math.radians(-15 + 210 * k / segs)
                yy = ya + math.cos(a) * rad
                zz = r + math.sin(a) * rad
                vs0.append(bm.verts.new((x0, yy, zz)))
                vs1.append(bm.verts.new((x1, yy, zz)))
            for k in range(segs):
                bm.faces.new((vs0[k], vs0[k + 1], vs1[k + 1], vs1[k]))
            # inner wall
            cvs = [bm.verts.new((x1, ya + math.cos(math.radians(-15 + 210 * k / segs)) * rad,
                                 r + math.sin(math.radians(-15 + 210 * k / segs)) * rad * 0.2)) for k in range(segs + 1)]
            for k in range(segs):
                bm.faces.new((vs1[k], vs1[k + 1], cvs[k + 1], cvs[k]))
            liner = new_obj("liner", bm, coll, [mats["trim"]])
            liner.data.update()
            for p in liner.data.polygons:
                p.use_smooth = False
            out["Trim"].append(liner)
            # double-sided by adding flipped copy
            bm2 = bmesh.new()
            bm2.from_mesh(liner.data)
            bmesh.ops.reverse_faces(bm2, faces=bm2.faces)
            l2 = new_obj("liner2", bm2, coll, [mats["trim"]])
            out["Trim"].append(l2)
    return out


def spoiler(s, f, coll, mats, kind):
    yR = f["yr_end"]
    hw = s["W"] / 2
    parts = []
    if kind == "wing":
        y = yR + 0.18
        z = f["zt"](y) + 0.22
        blade = rounded_box("wing", (hw * 1.8, 0.28, 0.035), coll, mats["paint"], bevel=0.012, segs=2, loc=(0, y, z))
        blade.data.transform(Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(-6), 4, "X") @
                             Matrix.Translation((0, -y, -z)))
        parts.append(blade)
        for sx in (-1, 1):
            parts.append(rounded_box("wingpost", (0.03, 0.12, 0.24), coll, mats["trim"], bevel=0.008, segs=1,
                                     loc=(sx * hw * 0.62, y, z - 0.12)))
            parts.append(rounded_box("endplate", (0.015, 0.34, 0.12), coll, mats["trim"], bevel=0.005, segs=1,
                                     loc=(sx * hw * 0.9, y, z - 0.02)))
    elif kind == "ducktail":
        y = yR + 0.12
        z = f["zt"](y) + 0.02
        lip = rounded_box("duck", (hw * 1.5, 0.22, 0.05), coll, mats["paint"], bevel=0.02, segs=2, loc=(0, y, z))
        lip.data.transform(Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(12), 4, "X") @
                           Matrix.Translation((0, -y, -z)))
        parts.append(lip)
    elif kind == "roof":
        y = s["roof_rear_y"] - 0.02
        z = f["zt"](y) + 0.0
        parts.append(rounded_box("roofspoiler", (hw * 1.35, 0.22, 0.03), coll, mats["paint"], bevel=0.012, segs=2,
                                 loc=(0, y - 0.08, z)))
    return parts



# --------------------------------------------------------------------------- extras
def _ex_hood_scoop(s, f, coll, mats):
    y = s["cowl_y"] + s.get("scoop_y", 0.55)
    z = f["zt"](y)
    sc = rounded_box("scoop", (0.55, 0.7, 0.14), coll, mats["paint"], bevel=0.04, segs=2, loc=(0, y, z + 0.02))
    mouth = rounded_box("scoopmouth", (0.42, 0.04, 0.07), coll, mats["grille"], bevel=0.01, segs=1, loc=(0, y + 0.35, z + 0.06))
    return {"PaintParts": [sc], "Trim": [mouth]}


def _ex_chrome_bumpers(s, f, coll, mats):
    out = []
    for yy, sgn in ((f["yf_end"], 1), (f["yr_end"], -1)):
        z = f["zb"](yy) + s.get("bumper_z", 0.2)
        w = f["hw"](yy - sgn * 0.15) * 2.0 * 1.02
        out.append(rounded_box("bumper", (w, 0.12, 0.11), coll, mats["chrome"], bevel=0.04, segs=2,
                               loc=(0, yy + sgn * 0.03, z)))
    return {"Chrome": out}


def _ex_light_pod(s, f, coll, mats):
    lights = []
    trim = []
    y = f["yf_end"] - 0.12
    z = f["zt"](y) + 0.12
    bar = rounded_box("podbar", (1.1, 0.06, 0.05), coll, mats["trim"], bevel=0.01, segs=1, loc=(0, y, z - 0.09))
    trim.append(bar)
    for k in range(4):
        x = -0.42 + k * 0.28
        housing = cylinder("podhouse", 0.09, 0.08, coll, mats["trim"], axis="Y", loc=(x, y, z), segs=16)
        lens = cylinder("podlens", 0.075, 0.02, coll, mats["head"], axis="Y", loc=(x, y + 0.045, z), segs=16)
        trim.append(housing)
        lights.append(lens)
    return {"Trim": trim, "Lights_Head": lights}


def _ex_roof_rack(s, f, coll, mats):
    out = []
    y0 = s["roof_rear_y"] + 0.1
    y1 = s["roof_front_y"] - 0.1
    z = s["roof_z"] + 0.05
    hw = f["hw"]((y0 + y1) * 0.5) * s.get("tumble", 0.78) * 0.85
    for sx in (-1, 1):
        out.append(rounded_box("rail", (0.04, y1 - y0, 0.04), coll, mats["trim"], bevel=0.01, segs=1,
                               loc=(sx * hw, (y0 + y1) * 0.5, z + 0.06)))
    k = 0
    yy = y0 + 0.15
    while yy < y1 - 0.1:
        out.append(rounded_box("cross", (hw * 2.0, 0.04, 0.03), coll, mats["trim"], bevel=0.008, segs=1,
                               loc=(0, yy, z + 0.09)))
        yy += 0.35
        k += 1
    return {"Trim": out}


def _ex_bull_bar(s, f, coll, mats):
    out = []
    y = f["yf_end"] + 0.12
    zb = f["zb"](f["yf_end"])
    for sx in (-0.45, 0.45):
        out.append(cylinder("bbpost", 0.035, 0.55, coll, mats["trim"], axis="Z", loc=(sx, y, zb + 0.35), segs=12))
    out.append(cylinder("bbtop", 0.035, 1.0, coll, mats["trim"], axis="X", loc=(0, y, zb + 0.62), segs=12))
    out.append(cylinder("bbmid", 0.03, 1.4, coll, mats["trim"], axis="X", loc=(0, y - 0.02, zb + 0.2), segs=12))
    return {"Trim": out}


def _ex_spare_wheel(s, f, coll, mats):
    y = f["yr_end"] - 0.13
    z = (f["zb"](f["yr_end"]) + f["zt"](f["yr_end"])) * 0.5 + 0.05
    t = cylinder("spare", s["wheel_r"] * 0.95, 0.24, coll, mats["tire"], axis="Y", loc=(0, y, z), segs=28)
    c = cylinder("sparecover", s["wheel_r"] * 0.6, 0.25, coll, mats["paint"], axis="Y", loc=(0, y - 0.01, z), segs=24)
    return {"Trim": [t], "PaintParts": [c]}


def _ex_bed(s, f, coll, mats):
    y0 = f["yr_end"] + 0.12
    y1 = s["deck_y"] - 0.05
    z = s["ride"] + 0.62
    hw = f["hw"]((y0 + y1) * 0.5) * 0.9
    floor = rounded_box("bedfloor", (hw * 2.0, y1 - y0, 0.05), coll, mats["trim"], bevel=0.0, loc=(0, (y0 + y1) * 0.5, z))
    front = rounded_box("bedfront", (hw * 2.0, 0.05, s["deck_z"] - z), coll, mats["trim"], bevel=0.0,
                        loc=(0, y1, (s["deck_z"] + z) * 0.5))
    walls = []
    for sx in (-1, 1):
        walls.append(rounded_box("bedwall", (0.04, y1 - y0, s["deck_z"] - z - 0.02), coll, mats["trim"], bevel=0.0,
                                 loc=(sx * hw, (y0 + y1) * 0.5, (s["deck_z"] + z) * 0.5)))
    gate = rounded_box("tailgate", (hw * 2.0, 0.05, s["deck_z"] - z - 0.05), coll, mats["paint"], bevel=0.01,
                       segs=1, loc=(0, y0 - 0.02, (s["deck_z"] + z) * 0.5))
    return {"Trim": [floor, front] + walls, "PaintParts": [gate]}


def _ex_windscreen(s, f, coll, mats):
    y = s["cowl_y"] - 0.05
    z = f["zs"](y)
    hw = f["hw"](y) * 0.8
    h = 0.32
    glass = rounded_box("ws", (hw * 2.0, 0.012, h), coll, mats["glass"], bevel=0.0, loc=(0, y, z + h * 0.5 + 0.02))
    glass.data.transform(Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(-22), 4, "X") @ Matrix.Translation((0, -y, -z)))
    frame = []
    for sx in (-1, 1):
        fr = cylinder("wsframe", 0.012, h + 0.04, coll, mats["chrome"], axis="Z", loc=(sx * hw, y, z + h * 0.5 + 0.02), segs=8)
        fr.data.transform(Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(-22), 4, "X") @ Matrix.Translation((0, -y, -z)))
        frame.append(fr)
    top = cylinder("wstop", 0.012, hw * 2.0, coll, mats["chrome"], axis="X", loc=(0, y, z + h + 0.04), segs=8)
    top.data.transform(Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(-22), 4, "X") @ Matrix.Translation((0, -y, -z)))
    frame.append(top)
    return {"GlassParts": [glass], "Chrome": frame}


def _ex_side_intakes(s, f, coll, mats):
    out = []
    bvh = None
    body = _CUR["body"]
    for sx in (-1, 1):
        y = f["yra"] + s["wheel_r"] + 0.45
        z = (f["zb"](y) + f["zs"](y)) * 0.5 + 0.02
        p = surface_patch(body, "intake_s", (sx * f["hw"](y), y, z), (sx, 0.2, 0), (0, 1, 0), 0.55, 0.2, coll,
                          mats["grille"], offset=0.004, res=8, shape="slant")
        out.append(p)
    return {"Trim": out}


def _ex_mudflaps(s, f, coll, mats):
    out = []
    for ya in (f["yfa"], f["yra"]):
        for sx in (-1, 1):
            x = sx * (s["W"] / 2 - s["wheel_w"] / 2 - 0.05)
            out.append(rounded_box("flap", (s["wheel_w"] + 0.04, 0.012, 0.26), coll, mats["trim"], bevel=0.0,
                                   loc=(x, ya - s["wheel_r"] - 0.12, s["ride"] + 0.05)))
    return {"Trim": out}


def _ex_roof_scoop(s, f, coll, mats):
    y = s["roof_front_y"] - 0.35
    z = s["roof_z"]
    sc = rounded_box("rscoop", (0.36, 0.45, 0.09), coll, mats["paint"], bevel=0.035, segs=2, loc=(0, y, z + 0.02))
    m = rounded_box("rscoopm", (0.28, 0.03, 0.05), coll, mats["grille"], bevel=0.01, segs=1, loc=(0, y + 0.22, z + 0.04))
    return {"PaintParts": [sc], "Trim": [m]}


EXTRAS = {
    "hood_scoop": _ex_hood_scoop, "chrome_bumpers": _ex_chrome_bumpers, "light_pod": _ex_light_pod,
    "roof_rack": _ex_roof_rack, "bull_bar": _ex_bull_bar, "spare_wheel": _ex_spare_wheel, "bed": _ex_bed,
    "windscreen": _ex_windscreen, "side_intakes": _ex_side_intakes, "mudflaps": _ex_mudflaps,
    "roof_scoop": _ex_roof_scoop,
}


def _ex_cargo_box(s, f, coll, mats):
    b = s["box"]
    box = rounded_box("cargobox", (b[0], b[1], b[2]), coll, mats["paint2"] if "paint2" in mats else mats["paint"],
                      bevel=0.05, segs=2, loc=(0, b[3], b[4] + b[2] * 0.5))
    chassis = rounded_box("chassis", (s["W"] * 0.7, b[1] + 0.4, 0.22), coll, mats["trim"], bevel=0.02, segs=1,
                          loc=(0, b[3], b[4] - 0.12))
    return {"Trim": [chassis], "Box": [box]}


EXTRAS["cargo_box"] = _ex_cargo_box


def build_tractor(spec, coll_path=None):
    name = spec["name"]
    coll = get_coll(coll_path or (ROOT_COLL + "/Traffic/TRF_" + name))
    clear_coll(coll)
    mats = shared_materials()
    paint = material("M_Paint_" + name, spec["paint"], 0.2, 0.35, coat=0.6)
    mats["paint"] = paint
    rim_mat = material("M_Rim_" + name, spec.get("rim_color", (0.85, 0.75, 0.15)), 0.3, 0.5)
    parts = []
    # bonnet / engine block
    hood = rounded_box("hood", (0.85, 1.7, 0.75), coll, paint, bevel=0.08, segs=2, loc=(0, 0.95, 1.05))
    grille = rounded_box("grille", (0.75, 0.05, 0.6), coll, mats["grille"], bevel=0.02, segs=1, loc=(0, 1.81, 1.05))
    chassis = rounded_box("chassis", (0.7, 3.0, 0.35), coll, mats["trim"], bevel=0.03, segs=1, loc=(0, 0.3, 0.72))
    exhaust = cylinder("stack", 0.05, 1.0, coll, mats["trim"], axis="Z", loc=(0.3, 1.3, 1.8), segs=12)
    # cab: floor, roof, four pillars, glass
    cab_floor = rounded_box("cabfloor", (1.3, 1.3, 0.12), coll, mats["trim"], bevel=0.02, segs=1, loc=(0, -0.6, 1.3))
    roof = rounded_box("roof", (1.45, 1.5, 0.08), coll, paint, bevel=0.03, segs=1, loc=(0, -0.6, 2.75))
    pillars = []
    for sx in (-0.62, 0.62):
        for sy in (-1.25, 0.05):
            pillars.append(rounded_box("pillar", (0.06, 0.06, 1.42), coll, mats["trim"], bevel=0.01, segs=1, loc=(sx, sy, 2.03)))
    fenders = []
    for sx in (-1, 1):
        fenders.append(rounded_box("fender", (0.62, 1.5, 0.08), coll, paint, bevel=0.03, segs=1, loc=(sx * 0.95, -0.85, 1.85)))
    seat = rounded_box("seat", (0.5, 0.5, 0.5), coll, mats["seat"], bevel=0.05, segs=2, loc=(0, -0.8, 1.6))
    body = join([hood, grille, chassis, exhaust, cab_floor, roof, seat] + pillars + fenders, "Body")
    uv_project(body)
    gb = bmesh.new()
    for (a, b) in (((-0.6, 0.06), (0.6, 0.06)), ((-0.6, -1.27), (0.6, -1.27))):
        v0 = gb.verts.new((a[0], a[1], 1.4)); v1 = gb.verts.new((b[0], b[1], 1.4))
        v2 = gb.verts.new((b[0], b[1], 2.7)); v3 = gb.verts.new((a[0], a[1], 2.7))
        gb.faces.new((v0, v1, v2, v3))
    glass = new_obj("Glass", gb, coll, [mats["glass"]])
    interior = rounded_box("Interior", (0.4, 0.3, 0.3), coll, mats["interior"], bevel=0.0, loc=(0, -0.3, 1.6))
    heads = []
    for sx in (-0.3, 0.3):
        heads.append(cylinder("hl", 0.08, 0.04, coll, mats["head"], axis="Y", loc=(sx, 1.84, 1.25), segs=14))
    join(heads, "Lights_Head")
    tails = []
    for sx in (-0.7, 0.7):
        tails.append(rounded_box("tl", (0.12, 0.04, 0.1), coll, mats["tail"], bevel=0.01, segs=1, loc=(sx, -1.55, 1.7)))
    join(tails, "Lights_Tail")
    # wheels: big rear, small front
    fs = dict(spec, wheel_r=0.48, wheel_w=0.28, rim_style="steel", rim_ratio=0.55, tread_groove=0.03)
    rs = dict(spec, wheel_r=0.82, wheel_w=0.45, rim_style="steel", rim_ratio=0.55, tread_groove=0.04)
    for wn, x, y, ws in (("Wheel_FL", -0.72, 1.25, fs), ("Wheel_FR", 0.72, 1.25, fs), ("Wheel_RL", -0.95, -0.85, rs), ("Wheel_RR", 0.95, -0.85, rs)):
        w = make_wheel(wn, ws, 1 if x > 0 else -1, coll, mats, rim_mat)
        w.location = (x, y, ws["wheel_r"])
    root = bpy.data.objects.new(name, None)
    coll.objects.link(root)
    root["velora_car"] = name
    for ob in list(coll.objects):
        if ob is not root:
            ob.parent = root
    for ob in coll.objects:
        if ob.type == "MESH":
            ob.data.name = ob.name
    return {"name": name, "tris": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in coll.objects if o.type == "MESH")}

# --------------------------------------------------------------------------- build
def build_car(spec, coll_path=None, export_path=None):
    name = spec["name"]
    coll_path = coll_path or (ROOT_COLL + "/Cars/CAR_" + name)
    coll = get_coll(coll_path)
    clear_coll(coll)
    mats = shared_materials()
    paint = material("M_Paint_" + name, spec["paint"], spec.get("paint_metal", 0.6), spec.get("paint_rough", 0.25),
                     coat=1.0)
    mats["paint"] = paint
    rim_mat = material("M_Rim_" + name, spec.get("rim_color", (0.75, 0.76, 0.78)), spec.get("rim_metal", 1.0),
                       spec.get("rim_rough", 0.25))
    if "paint2" in spec:
        mats["paint2"] = material("M_Box_" + name, spec["paint2"], 0.1, 0.5)
    cal_mat = material("M_Caliper_" + name, spec.get("caliper", (0.7, 0.05, 0.03)), 0.2, 0.4)
    body, f = build_body(spec, coll, mats)
    _CUR["body"] = body
    if "axle_f_y" in spec:
        f["yfa"] = spec["axle_f_y"]
    if "axle_r_y" in spec:
        f["yra"] = spec["axle_r_y"]
    details = add_details(spec, f, body, coll, mats)
    glass = split_glass(body, coll, mats)
    shell = interior_shell(body, spec, f, coll, mats)
    extra_paint = details.get("PaintParts", [])
    for kind in spec.get("spoilers", []):
        extra_paint += spoiler(spec, f, coll, mats, kind)
    glass_parts = []
    for name_ in spec.get("extras", []):
        if name_ not in EXTRAS:
            continue
        res = EXTRAS[name_](spec, f, coll, mats)
        for k, v in res.items():
            if k == "PaintParts":
                extra_paint.extend(v)
            elif k == "GlassParts":
                glass_parts.extend(v)
            else:
                details.setdefault(k, []).extend(v)
    paint_parts = [p for p in extra_paint if p is not None] + [p for p in details.get("Box", []) if p is not None]
    trim = [p for p in details["Trim"] + details.get("Chrome", []) + details.get("Ind", []) if p is not None]
    body = join([body] + paint_parts + trim, "Body")
    uv_project(body)
    if spec.get("lite"):
        bpy.data.objects.remove(shell, do_unlink=True)
        interior = rounded_box("Interior", (spec["W"] * 0.8, 1.0, 0.5), coll, mats["interior"], bevel=0.0,
                               loc=(0, spec.get("seat_y", 0.0), spec["ride"] + 0.5))
        sw_pos = (-0.4, spec.get("seat_y", 0.0) + 0.5, spec["ride"] + 1.0)
        seat = (0.4, spec.get("seat_y", 0.0), spec["ride"] + 0.3)
    else:
        interior, steer, sw_pos, seat = build_interior(spec, f, coll, mats)
        interior = join([interior, shell], "Interior")
    if glass_parts:
        glass = join([glass] + glass_parts, "Glass")
    lights = {}
    for key in ("Lights_Head", "Lights_Tail", "Lights_Reverse", "Lights_Brake"):
        objs = [o for o in details[key] if o is not None]
        if objs:
            lights[key] = join(objs, key)
    wheels = {}
    r = spec["wheel_r"]
    track_f = spec.get("track_f", spec["W"] / 2 - spec["wheel_w"] / 2 - 0.03)
    track_r = spec.get("track_r", track_f)
    for wn, x, y in (("Wheel_FL", -track_f, f["yfa"]), ("Wheel_FR", track_f, f["yfa"]),
                     ("Wheel_RL", -track_r, f["yra"]), ("Wheel_RR", track_r, f["yra"])):
        side = 1 if x > 0 else -1
        ws = dict(spec)
        if wn.startswith("Wheel_R") and "wheel_r_rear" in spec:
            ws["wheel_r"] = spec["wheel_r_rear"]
            ws["wheel_w"] = spec.get("wheel_w_rear", spec["wheel_w"])
        w = make_wheel(wn, ws, side, coll, mats, rim_mat)
        w.location = (x, y, ws["wheel_r"])
        wheels[wn] = w
        cal = make_caliper("Caliper_" + wn[6:], ws, side, coll, cal_mat)
        cal.location = (x - side * ws["wheel_w"] * 0.1, y, ws["wheel_r"])
    # root empty + parenting
    root = bpy.data.objects.get(name)
    if root is None or root.type != "EMPTY":
        root = bpy.data.objects.new(name, None)
    link(root, coll)
    root.empty_display_type = "ARROWS"
    root["velora_car"] = name
    for ob in list(coll.objects):
        if ob is root:
            continue
        if ob.name.startswith("_"):
            continue
        ob.parent = root
    # markers used by Godot (empties)
    for mk, loc in (("Mk_Cockpit", (sw_pos[0], seat[1] - 0.05, seat[2] + spec.get("eye_z", 0.98))),
                    ("Mk_Hood", (0.0, s_get(spec, "cowl_y") - 0.25, f["zt"](spec["cowl_y"] - 0.25) + 0.25)),
                    ("Mk_Bumper", (0.0, f["yf_end"] + 0.05, f["zb"](f["yf_end"]) + 0.32))):
        e = bpy.data.objects.new(mk, None)
        coll.objects.link(e)
        e.location = loc
        e.parent = root
    for ob in coll.objects:
        if ob.type == "MESH":
            ob.data.name = ob.name
    report = {"name": name, "tris": sum(len(o.data.loop_triangles) if o.data.loop_triangles else
                                        sum(len(p.vertices) - 2 for p in o.data.polygons)
                                        for o in coll.objects if o.type == "MESH")}
    if export_path:
        export_collection(coll, root, export_path)
        report["export"] = export_path
    return report


def s_get(spec, k):
    return spec[k]


def canonical_names(coll):
    """Give this collection's objects their plain names (Body, Wheel_FL...) for export."""
    for ob in list(coll.all_objects):
        base = ob.name.split(".")[0]
        if ob.name != base:
            other = bpy.data.objects.get(base)
            if other is not None and other is not ob:
                other.name = base + "_x"
            ob.name = base


def export_collection(coll, root, path):
    canonical_names(coll)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in coll.all_objects:
        if not ob.name.startswith("_"):
            ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_extras=True,
                              export_materials="EXPORT", export_texcoords=True, export_normals=True)
    bpy.ops.object.select_all(action="DESELECT")
