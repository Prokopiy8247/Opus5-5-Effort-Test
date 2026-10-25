"""Procedural vehicle builder for the project's original cars (Blender, run via MCP).

A car is described by silhouette profiles (side top line, beltline, underbody line, plan-view
half width) plus cabin/glass stations, wheels and a list of detail features. The builder:
  1. lofts a quad cage of cross-section rings along +Y and assigns material tags per face,
  2. subdivides it (Catmull-Clark with creased feature lines) into a smooth body shell,
  3. cuts wheel arches (boolean) and adds arch liners,
  4. separates glass, builds an inner interior shell, dashboard, seats, steering wheel,
  5. projects lights, grille, plates and panel lines onto the body (BVH ray casts),
  6. builds four wheels (tyre, rim, brake disc) with pivots at the axle centre + calipers,
  7. adds a convex Collision_Hull and gameplay empties (CAM_*, FX_*, LIGHT_*),
  8. UV-unwraps everything and exports a .glb for Godot.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import kit_common as K

# Material slot order used on the body shell
BODY_MATS = ["Paint", "Glass", "Trim", "Under", "TrimMatte", "Chrome", "Carbon"]
I_PAINT, I_GLASS, I_TRIM, I_UNDER, I_TRIMMATTE, I_CHROME, I_CARBON = range(7)
I_WELL = 7  # faces removed after subdivision to open a cockpit tub / pickup bed (spec["wells"])


# =============================================================================================
# body shell
def _stations(spec):
    yr, yf = spec["y_rear"], spec["y_front"]
    step = spec.get("station_step", 0.14)
    keys = [yr, yf]
    c = spec["cabin"]
    keys += [c["ws_base"], c["ws_top"], c["rw_top"], c["rw_base"]]
    keys += [c.get("sw_front", c["ws_top"]), c.get("sw_rear", c["rw_top"])]
    for b in spec.get("b_pillars", []):
        keys += [b - 0.035, b + 0.035]
    keys += spec.get("extra_stations", [])
    for w in spec.get("wells", []):
        keys += [w["y0"], w["y1"]]
    n = max(2, int(round((yf - yr) / step)))
    ys = [yr + (yf - yr) * i / n for i in range(n + 1)] + keys
    ys = sorted(set(round(y, 4) for y in ys if yr - 1e-6 <= y <= yf + 1e-6))
    out = []
    for y in ys:
        if out and y - out[-1] < 0.025:
            if y in keys:
                out[-1] = y
            continue
        out.append(y)
    return out


def _greenhouse_weight(spec, y):
    if spec.get("open_top", False):
        return 0.0
    c = spec["cabin"]
    if y >= c["ws_base"] or y <= c["rw_base"]:
        return 0.0
    if y >= c["ws_top"]:
        return K.smoothstep(c["ws_base"], c["ws_top"], y) if c["ws_top"] < c["ws_base"] else 1.0
    if y >= c["rw_top"]:
        return 1.0
    return K.smoothstep(c["rw_base"], c["rw_top"], y)


def _ring(spec, f, y):
    """Right-half key points (x, z) from bottom centre (index 0) to top centre (index 9).
    Feature lines: 1 floor edge, 3 max width, 4 shoulder, 5 glass base, 6 side-window top /
    pillar outer edge, 7 pillar inner edge (windshield / rear-window edge), 8 roof mid."""
    hw = f["hw"](y)
    zb = f["zb"](y)
    zsh = f["zsh"](y)
    zt = f["zt"](y)
    g = _greenhouse_weight(spec, y)
    rr = spec.get("roof_ratio", 0.76)
    tumble = spec.get("glass_base_ratio", 0.93)
    zsh = min(zsh, zt - 0.03)
    crown = spec.get("crown", 0.02)
    edge_z = zsh + min(spec.get("hood_edge", 0.055), (zt - zsh) * 0.5)
    deck = [
        (hw * 0.95, edge_z),
        (hw * 0.86, zt - crown * 0.75),
        (hw * 0.70, zt - crown * 0.45),
        (hw * 0.38, zt - crown * 0.12),
    ]
    cab = [
        (hw * tumble, zsh + 0.025),
        (hw * rr + 0.012, zt - 0.065),
        (hw * rr - 0.045, zt - 0.028),
        (hw * rr * 0.5, zt - 0.006),
    ]
    up = [(deck[i][0] * (1 - g) + cab[i][0] * g, deck[i][1] * (1 - g) + cab[i][1] * g) for i in range(4)]
    flare = f["flare"](y)
    pts = [
        (0.0, zb),
        (hw * 0.80, zb),
        (hw * 0.962 + flare * 0.5, zb + (zsh - zb) * 0.24),
        (hw + flare, zb + (zsh - zb) * 0.6),
        (hw * 0.988 + flare * 0.4, zsh),
    ] + up + [(0.0, zt)]
    return pts


HALF_N = 10  # points per half ring including both centre points


def _face_material(spec, y0, y1, band):
    """band = index of the lower ring point of the face (0..8)."""
    c = spec["cabin"]
    ym = 0.5 * (y0 + y1)
    if band == 0:
        return I_UNDER
    for w in spec.get("wells", []):
        if w["y0"] < ym < w["y1"] and band in w.get("bands", (6, 7, 8)):
            return I_WELL
    if spec.get("open_top", False):
        return I_PAINT
    if band == 5:
        sw_front = c.get("sw_front", c["ws_top"])
        sw_rear = c.get("sw_rear", c["rw_top"])
        if sw_rear < ym < sw_front:
            for b in spec.get("b_pillars", []):
                if abs(ym - b) < spec.get("b_pillar_w", 0.04):
                    return I_TRIM if spec.get("black_pillars", True) else I_PAINT
            return I_GLASS
        return I_PAINT
    if band == 6:
        if spec.get("roof_trim", False) and c["rw_base"] < ym < c["ws_base"]:
            return I_TRIM
        return I_PAINT
    if band in (7, 8):
        m = 0.012
        if c["ws_top"] + m < ym < c["ws_base"] - m:
            return I_GLASS
        if spec.get("rear_window", True) and c["rw_base"] + m < ym < c["rw_top"] - m:
            return I_GLASS
        if spec.get("glass_roof", False) and c["rw_top"] < ym < c["ws_top"] and band == 8:
            return I_GLASS
        if spec.get("roof_trim", False) and c["rw_top"] < ym < c["ws_top"]:
            return I_TRIM
        return I_PAINT
    return I_PAINT


def build_body(spec, col, mats):
    f = {
        "hw": K.pchip(spec["halfwidth"]),
        "zb": K.pchip(spec["bottom"]),
        "zsh": K.pchip(spec["shoulder"]),
        "zt": K.pchip(spec["top"]),
        "flare": K.pchip(spec.get("flare", [(spec["y_rear"], 0.0), (spec["y_front"], 0.0)])),
    }
    ys = _stations(spec)
    bm = bmesh.new()
    rings = []
    half_rings = []
    for y in ys:
        half = _ring(spec, f, y)
        half_rings.append(half)
    def full_loop(half):
        return [(x, z) for (x, z) in half] + [(-x, z) for (x, z) in reversed(half[1:-1])]
    for y, half in zip(ys, half_rings):
        rings.append([bm.verts.new((x, y, z)) for (x, z) in full_loop(half)])
    n = len(rings[0])
    # inset end rings give the bumpers a crisp but rounded edge
    def inset_ring(half, y, k):
        cz = sum(z for _, z in half) / len(half)
        return [bm.verts.new((x * k, y, cz + (z - cz) * k)) for (x, z) in full_loop(half)]
    end_r = inset_ring(half_rings[0], ys[0] - spec.get("end_round", 0.012), spec.get("end_inset", 0.955))
    end_f = inset_ring(half_rings[-1], ys[-1] + spec.get("end_round", 0.012), spec.get("end_inset", 0.955))
    all_rings = [end_r] + rings + [end_f]
    all_ys = [ys[0]] + ys + [ys[-1]]
    ring_band_y = []
    for i in range(len(all_rings) - 1):
        r0, r1 = all_rings[i], all_rings[i + 1]
        for j in range(n):
            k = (j + 1) % n
            face = bm.faces.new((r0[j], r0[k], r1[k], r1[j]))
            band = j if j < HALF_N - 1 else (n - 1 - j)
            face.material_index = _face_material(spec, all_ys[i], all_ys[i + 1], band)
    for ring, flip in ((end_r, True), (end_f, False)):
        verts = list(reversed(ring)) if flip else list(ring)
        cap = bm.faces.new(verts)
        cap.material_index = I_PAINT
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Body_" + spec["id"])
    bm.to_mesh(me)
    # creases on feature lines
    try:
        attr = me.attributes.get("crease_edge") or me.attributes.new("crease_edge", "FLOAT", "EDGE")
        c = spec["cabin"]
        for e in me.edges:
            a, b = e.vertices
            ra, ja = divmod(a, n)
            rb, jb = divmod(b, n)
            val = 0.0
            n_main = len(ys) * n
            if a >= n_main and b >= n_main and ra == rb:
                attr.data[e.index].value = spec.get("end_crease", 0.55)
                continue
            if ra != rb and ja == jb and (a >= n_main or b >= n_main):
                attr.data[e.index].value = spec.get("end_crease", 0.55) * 0.5
                continue
            if ra != rb and ja == jb:
                band = ja if ja < HALF_N else (n - ja)
                ym = 0.5 * (me.vertices[a].co.y + me.vertices[b].co.y)
                in_cabin = c["rw_base"] < ym < c["ws_base"] and not spec.get("open_top", False)
                in_sidewin = c.get("sw_rear", c["rw_top"]) - 0.02 < ym < c.get("sw_front", c["ws_top"]) + 0.02                     and not spec.get("open_top", False)
                if band == 4:
                    val = spec.get("shoulder_crease", 0.45)
                elif band == 1:
                    val = 0.9
                elif band in (5, 6) and in_sidewin:
                    val = 0.7
                elif band == 7 and in_cabin:
                    val = 0.65
            attr.data[e.index].value = val
    except Exception as ex:  # creases are cosmetic
        print("crease warning", ex)
    bm.free()
    obj = bpy.data.objects.new("Body", me)
    col.objects.link(obj)
    for m in BODY_MATS:
        me.materials.append(mats[m])
    if spec.get("wells"):
        me.materials.append(mats[spec["wells"][0].get("mat", "Interior")])
    cage_points = [Vector(v.co) for v in me.vertices]
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = spec.get("subdiv", 2)
    sub.render_levels = sub.levels
    try:
        sub.use_creases = True
    except Exception:
        pass
    K.apply_modifiers(obj)
    return obj, cage_points, f


def cut_wheel_arches(body, spec, col, mats):
    r = spec["wheel_radius"]
    clear = spec.get("arch_clearance", 0.045)
    all_cutters = []
    # wheel_xy lists the right-side wheels; cutters are made for both sides
    for idx, (wx, wy) in enumerate(spec["wheel_xy"]):
        rr = spec["wheel_radius_front"] if idx == 0 else spec["wheel_radius_rear"]
        for side in (-1, 1):
            x0 = side * (abs(wx) - spec.get("wheel_width", 0.22) * 0.5 - 0.06)
            x1 = side * 2.0
            depth = abs(x1 - x0)
            cx = (x0 + x1) * 0.5
            bm = K.cylinder_bm(rr + clear, depth, segments=48, axis="X", center=(cx, wy, rr))
            all_cutters.append(K.mesh_object("_cutter", bm, col))
    for c in all_cutters:
        mod = body.modifiers.new("Arch", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = c
        try:
            mod.solver = "EXACT"
        except Exception:
            pass
    K.apply_modifiers(body)
    for c in all_cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    # the boolean adds an empty material slot for the cutter; drop unused trailing slots
    used = {p.material_index for p in body.data.polygons}
    while len(body.data.materials) > 0 and body.data.materials[-1] is None and (len(body.data.materials) - 1) not in used:
        body.data.materials.pop(index=len(body.data.materials) - 1)
    # arch liners (half tubes, normals facing the tyre)
    liner_bm = bmesh.new()
    for (wx, wy) in spec["wheel_xy"]:
        for side in (-1, 1):
            inner = abs(wx) - spec.get("wheel_width", 0.22) * 0.5 - 0.07
            outer_x = None
            rad = r + clear - 0.004
            segs = 18
            ring_in, ring_out = [], []
            for s in range(segs + 1):
                a = math.radians(-10 + 200 * s / segs)
                yy = wy + math.cos(a) * rad
                zz = r + math.sin(a) * rad
                ring_in.append(liner_bm.verts.new((side * inner, yy, zz)))
                ring_out.append(liner_bm.verts.new((side * (inner + 0.42), yy, zz)))
            for s in range(segs):
                fv = (ring_in[s], ring_out[s], ring_out[s + 1], ring_in[s + 1])
                if side < 0:
                    fv = tuple(reversed(fv))
                liner_bm.faces.new(fv)
            # inner wall disc
            centre = liner_bm.verts.new((side * inner, wy, r))
            for s in range(segs):
                fv = (centre, ring_in[s + 1], ring_in[s])
                if side < 0:
                    fv = tuple(reversed(fv))
                liner_bm.faces.new(fv)
    liner = K.mesh_object("ArchLiners", liner_bm, col, [mats["Under"]])
    # flip so normals face inward towards the wheel
    bm = bmesh.new()
    bm.from_mesh(liner.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(liner.data)
    bm.free()
    return liner


def open_wells(body, spec, mats):
    """Removes the I_WELL faces (tagged before subdivision, so the opening follows a smooth
    cage loop) and extrudes the opening down to a flat floor: roadster cockpit tub, pickup bed."""
    wells = spec.get("wells", [])
    if not wells:
        return
    me = body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for w in wells:
        bm.faces.ensure_lookup_table()
        kill = [f for f in bm.faces if f.material_index == I_WELL
                and w["y0"] - 0.05 < f.calc_center_median().y < w["y1"] + 0.05]
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        edges = [e for e in bm.edges if e.is_boundary
                 and all(w["y0"] - 0.08 < v.co.y < w["y1"] + 0.08 for v in e.verts)]
        ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
        new_verts = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
        for v in new_verts:
            v.co.z = w["floor"]
            v.co.x *= w.get("taper", 0.985)
        for g in ret["geom"]:
            if isinstance(g, bmesh.types.BMFace):
                g.material_index = I_WELL
        floor_edges = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMEdge)
                       and all(v in new_verts for v in g.verts)]
        res = bmesh.ops.holes_fill(bm, edges=floor_edges, sides=0)
        for f in res.get("faces", []):
            f.material_index = I_WELL
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    # the arch boolean can clear the extra slot (duplicate material); restore it explicitly
    mat = mats[wells[0].get("mat", "Interior")]
    while len(me.materials) <= I_WELL:
        me.materials.append(mat)
    me.materials[I_WELL] = mat


def separate_glass(body, col, mats):
    me = body.data
    glass_idx = I_GLASS
    bm = bmesh.new()
    bm.from_mesh(me)
    gfaces = [f for f in bm.faces if f.material_index == glass_idx]
    gbm = bmesh.new()
    vmap = {}
    for f in gfaces:
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = gbm.verts.new(v.co)
            vs.append(vmap[v.index])
        gbm.faces.new(vs)
    bmesh.ops.delete(bm, geom=gfaces, context="FACES_ONLY")
    bm.to_mesh(me)
    bm.free()
    glass = K.mesh_object("Glass", gbm, col, [mats["Glass"]])
    # window seals: one ring of body faces around every glass opening turns black
    bm = bmesh.new()
    bm.from_mesh(me)
    for e in bm.edges:
        if e.is_boundary:
            for fc in e.link_faces:
                if fc.material_index == I_PAINT:
                    fc.material_index = I_TRIM
    bm.to_mesh(me)
    bm.free()
    # tiny inward offset keeps the glass behind the window seals
    for v in glass.data.vertices:
        pass
    return glass


def interior_shell(body, col, mats, thickness=0.014):
    """Inner lining so the cabin never shows backfaces/sky from the cockpit camera."""
    me = body.data.copy()
    obj = bpy.data.objects.new("Interior_Shell", me)
    col.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    for v in bm.verts:
        v.co -= v.normal * thickness
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mats["Interior"])
    for p in me.polygons:
        p.material_index = 0
    dec = obj.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = 0.35
    K.apply_modifiers(obj)
    return obj


# =============================================================================================
# projected details
class Projector:
    def __init__(self, body):
        dg = bpy.context.evaluated_depsgraph_get()
        self.bvh = BVHTree.FromObject(body, dg)

    def hit(self, origin, direction, dist=5.0):
        loc, nor, idx, d = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized(), dist)
        return loc, nor

    def hit_or_nearest(self, origin, direction, dist=5.0):
        """Ray hit; when the ray slips past a rounded edge, snap to the closest body point instead
        of leaving the vertex floating in the projection plane."""
        loc, nor = self.hit(origin, direction, dist)
        if loc is None:
            probe = Vector(origin) + Vector(direction).normalized() * 0.6
            loc, nor, idx, d = self.bvh.find_nearest(probe)
        return loc, nor


def _shape_outline(shape, w, h, n=24):
    pts = []
    if shape == "round":
        for i in range(n):
            a = 2 * math.pi * i / n
            pts.append((math.cos(a) * w * 0.5, math.sin(a) * h * 0.5))
    elif shape == "slim":
        # rounded slot
        r = h * 0.5
        for i in range(n // 2 + 1):
            a = -math.pi / 2 + math.pi * i / (n // 2)
            pts.append((w * 0.5 - r + math.cos(a) * r, math.sin(a) * r))
        for i in range(n // 2 + 1):
            a = math.pi / 2 + math.pi * i / (n // 2)
            pts.append((-w * 0.5 + r + math.cos(a) * r, math.sin(a) * r))
    else:  # rounded rectangle
        r = min(w, h) * 0.22
        corners = [(w * 0.5 - r, h * 0.5 - r, 0), (-w * 0.5 + r, h * 0.5 - r, 90),
                   (-w * 0.5 + r, -h * 0.5 + r, 180), (w * 0.5 - r, -h * 0.5 + r, 270)]
        for cx, cz, a0 in corners:
            for i in range(5):
                a = math.radians(a0 + 90 * i / 4)
                pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def projected_patch(proj, name, col, mat, center, size, shape="rect", direction=(0, -1, 0), offset=0.004,
                    thickness=0.012, skew=0.0, grid=6, mirror=True, tilt=0.0):
    """Creates a surface-conforming patch (light lens, grille, plate...) by casting the vertices
    of an outline grid onto the body along `direction` (pointing INTO the body)."""
    d = Vector(direction).normalized()
    # local frame on the projection plane
    up = Vector((0, 0, 1))
    u = up.cross(d)
    if u.length < 1e-4:
        u = Vector((1, 0, 0))
    u.normalize()
    v = d.cross(u).normalized()
    if tilt:
        rot = Matrix.Rotation(tilt, 3, d)
        u = rot @ u
        v = rot @ v
    w, h = size
    outline = _shape_outline(shape, w, h)
    bm = bmesh.new()
    sides = [1, -1] if mirror else [1]
    for side in sides:
        c = Vector(center)
        if side < 0:
            c.x = -c.x
        dd = d.copy()
        uu = u.copy()
        if side < 0:
            dd.x = -dd.x
            uu = Vector((0, 0, 1)).cross(dd).normalized()
        vv = dd.cross(uu).normalized()
        if tilt:
            rot = Matrix.Rotation(tilt * side, 3, dd)
            uu = rot @ uu
            vv = rot @ vv
        ring_pts = []
        for (px, pz) in outline:
            p_plane = c + uu * (px + skew * pz) + vv * pz - dd * 0.6
            loc, nor = proj.hit_or_nearest(p_plane, dd, 2.0)
            if loc is None:
                loc = p_plane + dd * 0.6
                nor = -dd
            ring_pts.append(loc - dd * offset)
        centre_plane = c - dd * 0.6
        cl, cn = proj.hit(centre_plane, dd, 2.0)
        if cl is None:
            cl = c
        cv = bm.verts.new(cl - dd * offset)
        verts = [bm.verts.new(p) for p in ring_pts]
        centre = cv.co.copy()
        for i in range(len(verts)):
            a, b = verts[i], verts[(i + 1) % len(verts)]
            fc = bm.faces.new((cv, a, b))
            fc.normal_update()
            if fc.normal.dot(-dd) < 0:
                fc.normal_flip()
        # rim (thickness) towards the body
        if thickness > 0:
            back = [bm.verts.new(vt.co + dd * thickness) for vt in verts]
            for i in range(len(verts)):
                a, b = verts[i], verts[(i + 1) % len(verts)]
                a2, b2 = back[i], back[(i + 1) % len(verts)]
                fc = bm.faces.new((a, a2, b2, b))
                fc.normal_update()
                if fc.normal.dot(fc.calc_center_median() - centre) < 0:
                    fc.normal_flip()
    obj = K.mesh_object(name, bm, col, [mat])
    K.shade_auto(obj, 35)
    return obj


def projected_strip(proj, name, col, mat, points, width=0.006, direction=(-1, 0, 0), offset=0.0015, mirror=True):
    """Thin line (panel gap / trim strip) following a polyline [(x, y, z)] cast onto the body."""
    d = Vector(direction).normalized()
    bm = bmesh.new()
    for side in ([1, -1] if mirror else [1]):
        dd = d.copy()
        if side < 0:
            dd.x = -dd.x
        prev = None
        pts = []
        for p in points:
            pp = Vector(p)
            if side < 0:
                pp.x = -pp.x
            loc, nor = proj.hit(pp - dd * 0.5, dd, 2.0)
            if loc is None:
                continue
            pts.append((loc - dd * offset, nor))
        for i in range(len(pts) - 1):
            a, na = pts[i]
            b, nb = pts[i + 1]
            t = (b - a)
            if t.length < 1e-5:
                continue
            side_v = t.cross(na).normalized() * width * 0.5
            v1 = bm.verts.new(a - side_v)
            v2 = bm.verts.new(a + side_v)
            v3 = bm.verts.new(b + side_v)
            v4 = bm.verts.new(b - side_v)
            fc = bm.faces.new((v1, v2, v3, v4))
            fc.normal_update()
            if fc.normal.dot(na) < 0:
                fc.normal_flip()
    obj = K.mesh_object(name, bm, col, [mat])
    # make every strip face point away from the body
    return obj


# =============================================================================================
# wheels
def _revolve_profile(bm, profile, segments, x_sign=1.0, lug=None):
    """profile: list of (x, r) around the X axis. lug(x, angle) -> radius delta (tread blocks)."""
    rings = []
    for (px, pr) in profile:
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            rr = pr + (lug(px, a) if lug is not None else 0.0)
            ring.append(bm.verts.new((px * x_sign, math.cos(a) * rr, math.sin(a) * rr)))
        rings.append(ring)
    faces = []
    for i in range(len(rings) - 1):
        for s in range(segments):
            t = (s + 1) % segments
            fv = (rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s])
            faces.append(bm.faces.new(fv))
    return rings, faces


def build_tire(radius, width, rim_radius, segments=48, sidewall_bulge=0.012, tread="road"):
    w = width * 0.5
    sh = min(0.035, (radius - rim_radius) * 0.4)
    profile = [
        (-w * 0.82, rim_radius - 0.008),
        (-w * 0.98, rim_radius + (radius - rim_radius) * 0.35),
        (-w - sidewall_bulge * 0.3, radius - sh * 1.4),
        (-w * 0.9, radius - sh * 0.35),
        (-w * 0.78, radius),
        (-w * 0.40, radius),
        (-w * 0.36, radius - 0.008),
        (-w * 0.26, radius - 0.008),
        (-w * 0.22, radius),
        (-w * 0.05, radius),
        (-w * 0.02, radius - 0.008),
        (w * 0.02, radius - 0.008),
        (w * 0.05, radius),
        (w * 0.22, radius),
        (w * 0.26, radius - 0.008),
        (w * 0.36, radius - 0.008),
        (w * 0.40, radius),
        (w * 0.78, radius),
        (w * 0.9, radius - sh * 0.35),
        (w + sidewall_bulge * 0.3, radius - sh * 1.4),
        (w * 0.98, rim_radius + (radius - rim_radius) * 0.35),
        (w * 0.82, rim_radius - 0.008),
    ]
    lug = None
    if tread == "lug":
        # chevron lugs for tractor / off-road tyres
        nlugs = 22
        def lug(px, a, w=w, r=radius):
            if abs(px) > w * 0.95 or r - 0.001 > 0 and False:
                return 0.0
            t = (a / (2 * math.pi)) * nlugs + (abs(px) / max(w, 1e-3)) * 0.45
            return 0.045 * radius if (t % 1.0) < 0.42 else 0.0
        profile = [(px, pr) for (px, pr) in profile]
    bm = bmesh.new()
    _revolve_profile(bm, profile, segments, 1.0, lug)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _segment_box(bm, p0, p1, t):
    """Thin square bar between two points (wire spokes, frames)."""
    d = p1 - p0
    length = d.length
    if length < 1e-5:
        return
    sb = bmesh.new()
    bmesh.ops.create_cube(sb, size=1.0)
    bmesh.ops.scale(sb, vec=(t, t, length), verts=sb.verts)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(sb, cent=(0, 0, 0), matrix=rot, verts=sb.verts)
    bmesh.ops.translate(sb, vec=(p0 + p1) * 0.5, verts=sb.verts)
    K.join_bm(bm, sb)


def build_rim(rim_radius, width, style="5spoke", spokes=5, segments=48, dish=0.03):
    """Rim barrel + face; face points to +X."""
    bm = bmesh.new()
    w = width * 0.5
    r_out = rim_radius
    barrel = [
        (w * 0.86, r_out - 0.004),
        (w * 0.95, r_out + 0.012),
        (w * 0.98, r_out + 0.006),
        (w * 0.9, r_out - 0.018),
        (-w * 0.85, r_out - 0.02),
        (-w * 0.9, r_out + 0.008),
    ]
    _revolve_profile(bm, barrel, segments)
    face_x = w * 0.78 - dish
    hub_r = 0.075 if rim_radius > 0.2 else 0.06
    # hub disc
    hub = bmesh.new()
    bmesh.ops.create_cone(hub, cap_ends=True, segments=24, radius1=hub_r, radius2=hub_r * 0.92, depth=0.05,
                          matrix=Matrix.Translation((face_x - 0.01, 0, 0)) @ Matrix.Rotation(math.radians(90), 4, "Y"))
    K.join_bm(bm, hub)
    if style == "wire":
        # laced wire wheel: two crossed layers of thin spokes + chrome knock-off spinner
        n = max(spokes, 24)
        for layer, (xo, twist) in enumerate(((face_x - 0.045, 0.32), (face_x - 0.012, -0.32))):
            for i in range(n):
                a0 = 2 * math.pi * i / n
                p0 = Vector((xo + 0.02, math.cos(a0) * hub_r * 0.9, math.sin(a0) * hub_r * 0.9))
                a1 = a0 + twist
                p1 = Vector((xo - 0.01, math.cos(a1) * (r_out - 0.012), math.sin(a1) * (r_out - 0.012)))
                _segment_box(bm, p0, p1, 0.0045)
        spin = bmesh.new()
        bmesh.ops.create_cone(spin, cap_ends=True, segments=3, radius1=hub_r * 1.25, radius2=hub_r * 0.7, depth=0.03,
                              matrix=Matrix.Translation((face_x + 0.03, 0, 0)) @ Matrix.Rotation(math.radians(90), 4, "Y"))
        K.join_bm(bm, spin)
    elif style == "steel":
        # steel wheel: solid dish with holes look + chrome hubcap
        disc = bmesh.new()
        bmesh.ops.create_cone(disc, cap_ends=True, segments=36, radius1=r_out - 0.01, radius2=r_out * 0.55,
                              depth=0.035, matrix=Matrix.Translation((face_x - 0.03, 0, 0)) @ Matrix.Rotation(math.radians(90), 4, "Y"))
        K.join_bm(bm, disc)
        cap = bmesh.new()
        bmesh.ops.create_uvsphere(cap, u_segments=20, v_segments=8, radius=r_out * 0.42,
                                  matrix=Matrix.Translation((face_x - 0.03, 0, 0)) @ Matrix.Scale(0.25, 4, (1, 0, 0)))
        K.join_bm(bm, cap)
    else:
        n = spokes
        for i in range(n):
            a = 2 * math.pi * i / n
            if style == "mesh":
                pairs = [a - 0.12, a + 0.12]
            elif style == "split":
                pairs = [a - 0.09, a + 0.09]
            else:
                pairs = [a]
            for aa in pairs:
                sb = bmesh.new()
                length = r_out - hub_r * 0.8
                thick_w = (0.05 if style in ("5spoke", "dish") else 0.03) * (r_out / 0.22)
                bmesh.ops.create_cube(sb, size=1.0)
                bmesh.ops.scale(sb, vec=(0.03, thick_w, length), verts=sb.verts)
                # taper towards the barrel and add dish (concave) offset
                for vtx in sb.verts:
                    t = vtx.co.z / length + 0.5
                    vtx.co.y *= (1.0 - 0.35 * t)
                    vtx.co.x -= dish * t * 1.2
                bmesh.ops.translate(sb, vec=(face_x - 0.012, 0, hub_r * 0.8 + length * 0.5), verts=sb.verts)
                bmesh.ops.rotate(sb, cent=(0, 0, 0), matrix=Matrix.Rotation(aa, 3, "X"), verts=sb.verts)
                K.join_bm(bm, sb)
    # lug nuts
    for i in range(5):
        a = 2 * math.pi * i / 5 + 0.3
        nb = bmesh.new()
        bmesh.ops.create_cone(nb, cap_ends=True, segments=6, radius1=0.011, radius2=0.011, depth=0.02,
                              matrix=Matrix.Translation((face_x + 0.018, math.cos(a) * hub_r * 0.6, math.sin(a) * hub_r * 0.6))
                              @ Matrix.Rotation(math.radians(90), 4, "Y"))
        K.join_bm(bm, nb)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_wheel(spec, key, pos, col, mats):
    r = spec["wheel_radius_front"] if key.startswith("F") else spec["wheel_radius_rear"]
    width = spec.get("wheel_width_front", spec.get("wheel_width", 0.22)) if key.startswith("F") \
        else spec.get("wheel_width_rear", spec.get("wheel_width", 0.22))
    rim_r = r * spec.get("rim_ratio", 0.66)
    bm = build_tire(r, width, rim_r, segments=spec.get("tire_segments", 48), sidewall_bulge=spec.get("sidewall", 0.012),
                    tread=spec.get("tread", "road"))
    rim = build_rim(rim_r, width, spec.get("rim_style", "5spoke"), spec.get("spokes", 5), dish=spec.get("rim_dish", 0.025))
    K.join_bm(bm, rim, 1)
    # brake disc (spins with the wheel)
    disc_r = rim_r - 0.035
    disc = bmesh.new()
    bmesh.ops.create_cone(disc, cap_ends=True, segments=32, radius1=disc_r, radius2=disc_r, depth=0.026,
                          matrix=Matrix.Translation((width * 0.08, 0, 0)) @ Matrix.Rotation(math.radians(90), 4, "Y"))
    K.join_bm(bm, disc, 2)
    left = key.endswith("L")
    if left:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi, 3, "Z"), verts=bm.verts)
    rim_mat = mats[spec.get("rim_material", "Rim")]
    wheel = K.mesh_object("Wheel_" + key, bm, col, [mats["Rubber"], rim_mat, mats["Disc"]])
    K.shade_auto(wheel, 32)
    wheel.location = pos
    # caliper (steers but does not spin), pivot at the axle centre
    cb = bmesh.new()
    seg = 8
    inner, outer = disc_r - 0.055, disc_r + 0.012
    ring_i, ring_o = [], []
    for s in range(seg + 1):
        a = math.radians(95 + 70 * s / seg)  # upper rear quadrant
        ring_i.append((math.cos(a), math.sin(a)))
    xs = (width * 0.08 - 0.03, width * 0.08 + 0.03)
    verts = {}
    for xi, x in enumerate(xs):
        for ri, rad in enumerate((inner, outer)):
            for s, (ca, sa) in enumerate(ring_i):
                verts[(xi, ri, s)] = cb.verts.new((x, ca * rad, sa * rad))
    for s in range(seg):
        for xi in range(2):
            cb.faces.new((verts[(xi, 0, s)], verts[(xi, 0, s + 1)], verts[(xi, 1, s + 1)], verts[(xi, 1, s)]))
        for ri in range(2):
            cb.faces.new((verts[(0, ri, s)], verts[(0, ri, s + 1)], verts[(1, ri, s + 1)], verts[(1, ri, s)]))
    for xi in range(2):
        pass
    bmesh.ops.recalc_face_normals(cb, faces=cb.faces)
    if left:
        bmesh.ops.rotate(cb, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi, 3, "Z"), verts=cb.verts)
    cal = K.mesh_object("Caliper_" + key, cb, col, [mats["Caliper"]])
    cal.location = pos
    return wheel, cal


# =============================================================================================
# interior
def build_interior(spec, col, mats, f):
    c = spec["cabin"]
    parts = bmesh.new()
    hw_cab = f["hw"]((c["ws_top"] + c["rw_top"]) * 0.5)
    floor_z = spec.get("floor_z", f["zb"]((c["ws_top"] + c["rw_top"]) * 0.5) + 0.06)
    zsh_ws = f["zsh"](c["ws_base"])
    dash_y0 = c["ws_base"] - 0.06
    dash_depth = spec.get("dash_depth", 0.42)
    # dashboard
    dash = K.rounded_box_bm((hw_cab * 1.75, dash_depth, 0.26), (0, dash_y0 - dash_depth * 0.5, zsh_ws - 0.08), 0.04, 2)
    K.join_bm(parts, dash, 0)
    seat_y = spec.get("seat_y", c["ws_base"] - 1.15)
    seat_x = spec.get("seat_x", min(0.37, hw_cab * 0.45))
    seat_z = floor_z + spec.get("seat_h", 0.16)
    seats = [(-seat_x, seat_y), (seat_x, seat_y)]
    if spec.get("rear_seats", False):
        seats_rear = spec.get("rear_seat_y", seat_y - 0.85)
    for (sx, sy) in seats:
        base = K.rounded_box_bm((0.48, 0.5, 0.12), (sx, sy + 0.03, seat_z), 0.04, 2)
        K.join_bm(parts, base, 1)
        back = K.rounded_box_bm((0.48, 0.13, 0.62), (0, 0, 0), 0.045, 2)
        bmesh.ops.rotate(back, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-14), 3, "X"), verts=back.verts)
        bmesh.ops.translate(back, vec=(sx, sy - 0.25, seat_z + 0.34), verts=back.verts)
        K.join_bm(parts, back, 1)
        head = K.rounded_box_bm((0.26, 0.1, 0.18), (sx, sy - 0.33, seat_z + 0.74), 0.04, 2)
        K.join_bm(parts, head, 1)
    if spec.get("rear_seats", False):
        ry = spec.get("rear_seat_y", seat_y - 0.82)
        bench = K.rounded_box_bm((hw_cab * 1.6, 0.48, 0.13), (0, ry, seat_z - 0.02), 0.05, 2)
        K.join_bm(parts, bench, 1)
        rback = K.rounded_box_bm((hw_cab * 1.6, 0.13, 0.55), (0, 0, 0), 0.05, 2)
        bmesh.ops.rotate(rback, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-18), 3, "X"), verts=rback.verts)
        bmesh.ops.translate(rback, vec=(0, ry - 0.24, seat_z + 0.3), verts=rback.verts)
        K.join_bm(parts, rback, 1)
    # centre console
    cons = K.rounded_box_bm((0.2, 0.7, 0.18), (0, seat_y + 0.15, floor_z + 0.12), 0.03, 2)
    K.join_bm(parts, cons, 0)
    # gear lever
    lever = K.cylinder_bm(0.008, 0.14, 8, "Z", (0, seat_y + 0.32, floor_z + 0.27))
    K.join_bm(parts, lever, 0)
    knob = bmesh.new()
    bmesh.ops.create_uvsphere(knob, u_segments=10, v_segments=6, radius=0.025,
                              matrix=Matrix.Translation((0, seat_y + 0.32, floor_z + 0.35)))
    K.join_bm(parts, knob, 2)
    # floor carpet
    carpet = K.rounded_box_bm((hw_cab * 1.7, (c["ws_base"] - c["rw_top"]) * 0.95, 0.03),
                              (0, (c["ws_base"] + c["rw_top"]) * 0.5 - 0.1, floor_z), 0.01, 1)
    K.join_bm(parts, carpet, 3)
    # gauges
    gauge_y = dash_y0 - 0.02 - dash_depth + 0.12
    for gx in (-seat_x - 0.07, -seat_x + 0.07):
        g = bmesh.new()
        bmesh.ops.create_cone(g, cap_ends=True, segments=20, radius1=0.045, radius2=0.045, depth=0.01,
                              matrix=Matrix.Translation((gx, gauge_y - 0.005, zsh_ws - 0.02))
                              @ Matrix.Rotation(math.radians(70), 4, "X"))
        K.join_bm(parts, g, 4)
    interior = K.mesh_object("Interior", parts, col, [mats["Dash"], mats["Seat"], mats["Chrome"], mats["Interior"], mats["Gauge"]])
    K.shade_auto(interior, 40)
    # steering wheel (own object, rotates about its local Y = column axis)
    sw = bmesh.new()
    sw_r = spec.get("steering_radius", 0.185)
    bmesh.ops.create_cone(sw, cap_ends=False, segments=28, radius1=sw_r, radius2=sw_r, depth=0.03)
    # make a torus-like rim: use a thin cylinder ring plus spokes (cheap, reads fine at cockpit distance)
    sw2 = bmesh.new()
    torus_major, torus_minor = sw_r, 0.016
    segs_major, segs_minor = 32, 8
    rings = []
    for i in range(segs_major):
        a = 2 * math.pi * i / segs_major
        ring = []
        for j in range(segs_minor):
            b = 2 * math.pi * j / segs_minor
            x = (torus_major + math.cos(b) * torus_minor) * math.cos(a)
            z = (torus_major + math.cos(b) * torus_minor) * math.sin(a)
            y = math.sin(b) * torus_minor
            ring.append(sw2.verts.new((x, y, z)))
        rings.append(ring)
    for i in range(segs_major):
        for j in range(segs_minor):
            a, b = rings[i][j], rings[(i + 1) % segs_major][j]
            c2, d = rings[(i + 1) % segs_major][(j + 1) % segs_minor], rings[i][(j + 1) % segs_minor]
            sw2.faces.new((a, b, c2, d))
    sw.free()
    for ang in (0, 120, 240) if spec.get("sw_spokes", 3) == 3 else (0, 90, 180, 270):
        sp = bmesh.new()
        bmesh.ops.create_cube(sp, size=1.0)
        bmesh.ops.scale(sp, vec=(sw_r * 0.95, 0.02, 0.03), verts=sp.verts)
        bmesh.ops.translate(sp, vec=(sw_r * 0.475, 0.01, 0), verts=sp.verts)
        bmesh.ops.rotate(sp, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(ang - 90), 3, "Y"), verts=sp.verts)
        K.join_bm(sw2, sp)
    hub = K.cylinder_bm(0.055, 0.05, 16, "Y", (0, 0.01, 0))
    K.join_bm(sw2, hub)
    column = K.cylinder_bm(0.03, 0.3, 10, "Y", (0, 0.17, 0))
    K.join_bm(sw2, column)
    bmesh.ops.recalc_face_normals(sw2, faces=sw2.faces)
    steer = K.mesh_object("SteeringWheel", sw2, col, [mats["Dash"]])
    K.shade_auto(steer, 40)
    tilt = math.radians(spec.get("steering_tilt_deg", 22))
    steer.rotation_euler = (tilt, 0, 0)
    steer.location = (-seat_x, dash_y0 - dash_depth - 0.06, zsh_ws + spec.get("steering_dz", -0.02))
    return interior, steer, (-seat_x, seat_y, seat_z)


# =============================================================================================
def build_car(spec, export_path=None, extras=None):
    """Builds the car described by spec into collection FORZA_GODOT/Cars/CAR_<id>."""
    K.guard()
    if extras is None:
        extras = spec.get("extras")
    cars = K.sub_collection(spec.get("collection", "Cars"))
    col_name = "CAR_" + spec["id"]
    col = bpy.data.collections.get(col_name)
    if col is not None:
        K.clear_collection(col)
    col = K.collection(col_name, cars)
    mats = K.std_materials(spec.get("paint", (0.8, 0.1, 0.1)))
    body, cage_pts, f = build_body(spec, col, mats)
    liner = cut_wheel_arches(body, spec, col, mats)
    open_wells(body, spec, mats)
    if spec.get("post_body"):
        spec["post_body"](spec, body, col, mats)
    glass = separate_glass(body, col, mats)
    shell = interior_shell(body, col, mats)
    K.shade_auto(body, spec.get("smooth_angle", 50))
    K.shade_auto(glass, 60)
    proj = Projector(body)
    objs = [body, liner, glass, shell]
    # lights, grille, plates, strips ...
    for feat in spec.get("features", []):
        kind = feat["kind"]
        mat = mats[feat.get("mat", "Trim")]
        if kind == "patch":
            o = projected_patch(proj, feat["name"], col, mat, feat["center"], feat["size"], feat.get("shape", "rect"),
                                feat.get("dir", (0, -1, 0)), feat.get("offset", 0.004), feat.get("thick", 0.012),
                                feat.get("skew", 0.0), mirror=feat.get("mirror", True), tilt=feat.get("tilt", 0.0))
            objs.append(o)
        elif kind == "lamp":
            lens_mat = mats[feat.get("mat", "LightHead")]
            w, h = feat["size"]
            d = feat.get("dir", (0, -1, 0))
            o1 = projected_patch(proj, feat["name"] + "_Housing", col, mats[feat.get("housing", "Trim")], feat["center"],
                                 (w + 0.03, h + 0.025), feat.get("shape", "rect"), d, 0.003, 0.012, feat.get("skew", 0.0),
                                 mirror=feat.get("mirror", True), tilt=feat.get("tilt", 0.0))
            o2 = projected_patch(proj, feat["name"], col, lens_mat, feat["center"], (w, h), feat.get("shape", "rect"), d,
                                 0.008, 0.006, feat.get("skew", 0.0), mirror=feat.get("mirror", True), tilt=feat.get("tilt", 0.0))
            objs += [o1, o2]
            for k, inner in enumerate(feat.get("inner", [])):
                o3 = projected_patch(proj, "%s_Inner%d" % (feat["name"], k), col, mats[inner.get("mat", "Chrome")],
                                     inner["center"], inner["size"], inner.get("shape", "round"), d, 0.011, 0.003,
                                     mirror=feat.get("mirror", True), tilt=feat.get("tilt", 0.0))
                objs.append(o3)
        elif kind == "strip":
            o = projected_strip(proj, feat["name"], col, mat, feat["points"], feat.get("width", 0.006),
                                feat.get("dir", (-1, 0, 0)), mirror=feat.get("mirror", True))
            objs.append(o)
        elif kind == "box":
            bm = K.rounded_box_bm(feat["size"], feat["center"], feat.get("bevel", 0.01), feat.get("segments", 2))
            if feat.get("mirror", False):
                bm2 = K.rounded_box_bm(feat["size"], (-feat["center"][0], feat["center"][1], feat["center"][2]),
                                       feat.get("bevel", 0.01), feat.get("segments", 2))
                K.join_bm(bm, bm2)
            if feat.get("rot"):
                # Euler XYZ degrees about each box's own centre (mirrored copy gets mirrored Y/Z angles)
                rx, ry, rz = feat["rot"]
                for sgn, ctr in ((1, feat["center"]), (-1, (-feat["center"][0], feat["center"][1], feat["center"][2]))):
                    if sgn < 0 and not feat.get("mirror", False):
                        continue
                    from mathutils import Euler
                    m = Euler((math.radians(rx), math.radians(ry * sgn), math.radians(rz * sgn)), "XYZ").to_matrix()
                    near = [v for v in bm.verts if (v.co - Vector(ctr)).length < max(feat["size"]) * 1.5]
                    bmesh.ops.rotate(bm, cent=ctr, matrix=m, verts=near)
            o = K.mesh_object(feat["name"], bm, col, [mat])
            K.shade_auto(o, 40)
            objs.append(o)
        elif kind == "cyl":
            bm = K.cylinder_bm(feat["radius"], feat["depth"], feat.get("segments", 16), feat.get("axis", "Y"), feat["center"])
            if feat.get("mirror", False):
                c2 = (-feat["center"][0], feat["center"][1], feat["center"][2])
                K.join_bm(bm, K.cylinder_bm(feat["radius"], feat["depth"], feat.get("segments", 16), feat.get("axis", "Y"), c2))
            o = K.mesh_object(feat["name"], bm, col, [mat])
            K.shade_auto(o, 40)
            objs.append(o)
    if extras is not None:
        objs += extras(spec, col, mats, proj, f) or []
    interior, steer, seat = build_interior(spec, col, mats, f)
    objs += [interior, steer]
    # wheels
    for key, (x, y) in (("FL", (-spec["track_front"] / 2, spec["wheelbase"] / 2)),
                        ("FR", (spec["track_front"] / 2, spec["wheelbase"] / 2)),
                        ("RL", (-spec["track_rear"] / 2, -spec["wheelbase"] / 2)),
                        ("RR", (spec["track_rear"] / 2, -spec["wheelbase"] / 2))):
        r = spec["wheel_radius_front"] if key.startswith("F") else spec["wheel_radius_rear"]
        w, cal = build_wheel(spec, key, (x, y, r), col, mats)
        objs += [w, cal]
    # collision hull from the cage (convex), slightly above the ground
    hb = bmesh.new()
    for p in cage_pts:
        hb.verts.new((p.x * 0.98, p.y * 0.99, max(p.z, spec.get("hull_floor", 0.2))))
    for p in spec.get("hull_extra", []):
        hb.verts.new(p)
    res = bmesh.ops.convex_hull(hb, input=hb.verts)
    drop = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if drop:
        bmesh.ops.delete(hb, geom=drop, context="VERTS")
    hull = K.mesh_object("Collision_Hull", hb, col)
    hull.display_type = "WIRE"
    colcol = K.sub_collection("Collision")
    if hull.name not in colcol.objects:
        colcol.objects.link(hull)
    objs.append(hull)
    # gameplay empties
    c = spec["cabin"]
    custom = {e[0] for e in spec.get("empties", [])}
    if "CAM_Cockpit" not in custom:
        K.empty("CAM_Cockpit", col, (seat[0], seat[1] - 0.05, seat[2] + spec.get("eye_h", 0.68)))
    if "CAM_Hood" not in custom:
        K.empty("CAM_Hood", col, (0, c["ws_base"] + 0.25, f["zt"](c["ws_base"] + 0.25) + 0.32))
    if "CAM_Bumper" not in custom:
        K.empty("CAM_Bumper", col, (0, spec["y_front"] + 0.02, spec.get("bumper_cam_z", 0.5)))
    for e in spec.get("empties", []):
        K.empty(e[0], col, e[1])
    for o in col.objects:
        if o.type == "MESH":
            K.box_uv(o)
    objs = [o for o in col.objects]
    if export_path:
        K.export_glb(objs, export_path)
    hull.hide_set(True)
    return col


def preview_and_export(spec, export_dir=None):
    """Builds a car, shows only its collection (for visual QA) with its design paint colour and,
    when export_dir is given, exports <export_dir>/<id>.glb. Returns the body object name."""
    import os
    path = os.path.join(export_dir, spec["id"] + ".glb") if export_dir else None
    col = build_car(spec, path)
    paint = bpy.data.materials.get("Paint")
    if paint is not None and paint.node_tree is not None:
        node = next(n for n in paint.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        node.inputs["Base Color"].default_value = tuple(spec.get("paint", (0.8, 0.1, 0.1))) + (1.0,)
    for c in bpy.data.collections:
        if c.name.startswith("CAR_"):
            for o in c.objects:
                o.hide_set(c.name != col.name or o.name.startswith("Collision"))
    return [o.name for o in col.objects if o.name.startswith("Body")][0]
