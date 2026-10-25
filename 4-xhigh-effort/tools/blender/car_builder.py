"""Parametric car builder for VALORIA (runs inside the project's Blender via MCP).

A car is described by a spec dict (see car_specs.py). The body is a lofted "station lattice":
cross-sections at stations along +Y (front) built from side-view profiles (top, belt, bottom)
and plan-view profiles (half widths), subdivided with creased character lines. Wheel arches are
boolean cuts; lights, grilles, vents and panel gaps are surface-projected decal meshes.

Parts produced (all prefixed with the asset id):
  Body, Glass, Interior, Steering, Wheel_FL/FR/RL/RR (pivot at axle centre),
  Caliper_FL/FR/RL/RR, Lights_Head, Lights_Tail, Lights_Reverse, Lights_Indicator,
  Socket_* empties (cameras, lights, exhaust).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import vgk_common as C

HALF_POINTS = 14  # P0..P6, S1..S3, E, R1, R2, Ctop
SEG_BOTTOM = (0, 1)
SEG_LOWER = (2, 3, 4, 5)
SEG_BELT = 6
SEG_SIDEGLASS = (7, 8)
SEG_RAIL = 9
SEG_PILLAR = 10
SEG_ROOF = (11, 12)


def _enum_has(rna_prop_owner, prop, value):
    try:
        return value in [i.identifier for i in rna_prop_owner.bl_rna.properties[prop].enum_items]
    except KeyError:
        return False


class Body:
    def __init__(self, s):
        self.s = s
        L = s["L"]
        self.yF, self.yR = L / 2.0, -L / 2.0
        self.axF = self.yF - s["front_overhang"]
        self.axR = self.axF - s["wheelbase"]
        self.top = C.pchip(s["top"])
        self.belt = C.pchip(s["belt"])
        self.bottom = C.pchip(s["bottom"])
        self.hw = C.pchip(s["hw"])
        self.hwr = C.pchip(s["hwr"])
        g = s.get("glass", {})
        self.ws = g.get("ws")      # (y_top, y_base) windshield: top is rearward of base
        self.rw = g.get("rw")      # (y_base, y_top) rear window
        self.side = g.get("side")  # list of (y0, y1) side window ranges
        self.open_top = s.get("open_top", False)

    # ---------------------------------------------------------------- profiles
    def bulge(self, y, axle, length):
        d = (y - axle) / length
        return math.exp(-d * d * 2.2)

    def cab(self, y):
        if self.open_top or not self.ws:
            return 0.0
        wt, wb = self.ws
        rb, rt = self.rw if self.rw else (self.yR - 1.0, self.yR - 0.5)  # no rear window: cabin runs to the tail
        if y >= wb or y <= rb:
            return 0.0
        f = 1.0 if y <= wt else (wb - y) / (wb - wt)
        r = 1.0 if y >= rt else (y - rb) / (rt - rb)
        return max(0.0, min(f, r))

    def section(self, y):
        s = self.s
        fb = s.get("fender", {})
        bw, bh, bl = fb.get("w", 0.0), fb.get("h", 0.0), fb.get("len", 0.6)
        bulge = max(self.bulge(y, self.axF, bl), self.bulge(y, self.axR, bl) * fb.get("rear_mul", 1.0))
        hw = self.hw(y) + bw * bulge
        zb = self.bottom(y)
        zt = self.belt(y) + bh * bulge
        ztop = self.top(y)
        hwt = hw - s.get("shoulder_in", 0.045)
        zs = zb + (zt - zb) * s.get("zs_frac", 0.55)
        rocker = s.get("rocker_h", 0.09)
        cab = self.cab(y)
        crown = s.get("roof_crown", 0.035)
        # roof edge E: deck version vs cabin version, blended by cab factor
        e_deck = (hwt * s.get("deck_edge", 0.86), zt + (ztop - zt) * 0.30)
        e_cab = (self.hwr(y), ztop - crown)
        ex = C.lerp(e_deck[0], e_cab[0], cab)
        ez = C.lerp(e_deck[1], e_cab[1], cab)

        def upper(f):  # parabolic crown from E (f=1) to centre (f=0)
            return (ex * f, ztop - (ztop - ez) * f * f)

        # side points between shoulder P6 and E
        p6 = (hwt, zt)
        d1 = (C.lerp(p6[0], ex, 0.25) + 0.004, C.lerp(p6[1], ez, 0.25))
        d2 = (C.lerp(p6[0], ex, 0.52) + 0.006, C.lerp(p6[1], ez, 0.52))
        d3 = (C.lerp(p6[0], ex, 0.80) + 0.004, C.lerp(p6[1], ez, 0.80))
        gb = s.get("glass_inset", 0.03)
        c1 = (hwt - gb, zt + 0.03)
        c3 = (ex + 0.012, ez - 0.045)
        c2 = ((c1[0] + c3[0]) * 0.5 + 0.014, (c1[1] + c3[1]) * 0.5)
        s1 = (C.lerp(d1[0], c1[0], cab), C.lerp(d1[1], c1[1], cab))
        s2 = (C.lerp(d2[0], c2[0], cab), C.lerp(d2[1], c2[1], cab))
        s3 = (C.lerp(d3[0], c3[0], cab), C.lerp(d3[1], c3[1], cab))
        pts = [
            (0.0, zb),
            (hw * 0.62, zb),
            (hw - 0.055, zb + 0.012),
            (hw - 0.012, zb + rocker),
            (hw, zs),
            (hw - 0.01, C.lerp(zs, zt, 0.62)),
            p6, s1, s2, s3,
            upper(1.0), upper(0.86), upper(0.48), (0.0, ztop),
        ]
        return pts

    # --------------------------------------------------------------- stations
    def stations(self):
        s = self.s
        n = s.get("stations", 44)
        ys = [C.lerp(self.yR, self.yF, i / (n - 1)) for i in range(n)]
        keys = []
        r = s["wheel_r"] + s.get("arch_gap", 0.04)
        for ax in (self.axF, self.axR):
            keys += [ax - r, ax - r * 0.7, ax, ax + r * 0.7, ax + r]
        if self.ws:
            keys += list(self.ws)
        if self.rw:
            keys += list(self.rw)
        for (a, b) in (self.side or []):
            keys += [a, b]
        keys += s.get("extra_stations", [])
        # denser at the ends for rounded bumpers
        for d in (0.03, 0.08, 0.15, 0.25):
            keys += [self.yF - d, self.yR + d]
        allys = sorted(set(round(y, 4) for y in ys + keys if self.yR <= y <= self.yF))
        out = []
        for y in allys:
            if out and y - out[-1] < 0.022:
                # keep key stations, drop the uniform neighbour
                if any(abs(y - k) < 1e-3 for k in keys):
                    out[-1] = y
                continue
            out.append(y)
        return out

    # ------------------------------------------------------------- materials
    def face_material(self, seg, ymid):
        """Material slot for lattice face (segment index on the half ring, mid station y)."""
        s = self.s
        if seg in SEG_BOTTOM:
            return 3
        if self.open_top and seg >= SEG_SIDEGLASS[0]:
            return 0
        in_side = any(a + 0.001 < ymid < b - 0.001 for (a, b) in (self.side or []))
        if seg in SEG_SIDEGLASS:
            return 1 if in_side else s.get("pillar_mat", 0)
        if seg == SEG_BELT and in_side and s.get("belt_trim"):
            return 4 if s["belt_trim"] == "Chrome" else 2
        if seg == SEG_RAIL and in_side and s.get("frame_trim"):
            return 2
        if seg in SEG_ROOF:
            if self.ws and self.ws[0] + 0.001 < ymid < self.ws[1] - 0.001:
                return 1
            if self.rw and self.rw[0] + 0.001 < ymid < self.rw[1] - 0.001:
                return 1
            if s.get("roof_mat") is not None and self.ws and self.rw and self.rw[1] <= ymid <= self.ws[0]:
                return s["roof_mat"]
        if seg == SEG_PILLAR:
            if s.get("pillar_mat") is not None and self.cab(ymid) > 0.01:
                return s["pillar_mat"]
            if s.get("roof_mat") is not None and self.ws and self.rw and self.rw[1] <= ymid <= self.ws[0]:
                return s["roof_mat"]
        return 0

    # ----------------------------------------------------------------- build
    def build_mesh(self):
        bm = bmesh.new()
        crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
        ys = self.stations()
        rings = []
        for y in ys:
            half = self.section(y)
            ring = [(x, z) for (x, z) in half] + [(-x, z) for (x, z) in reversed(half[1:-1])]
            rings.append([bm.verts.new((x, y, z)) for (x, z) in ring])
        nring = len(rings[0])
        # end caps: shrink twice then close
        cap_rings = {}
        for end, sign in (("front", 1), ("rear", -1)):
            base = rings[-1] if end == "front" else rings[0]
            cx = sum(v.co.x for v in base) / nring
            cz = sum(v.co.z for v in base) / nring
            yb = base[0].co.y
            r1 = [bm.verts.new((cx + (v.co.x - cx) * 0.80, yb + sign * 0.022, cz + (v.co.z - cz) * 0.80)) for v in base]
            r2 = [bm.verts.new((cx + (v.co.x - cx) * 0.38, yb + sign * 0.036, cz + (v.co.z - cz) * 0.38)) for v in base]
            cap_rings[end] = (r1, r2)
        seq = [cap_rings["rear"][1], cap_rings["rear"][0]] + rings + [cap_rings["front"][0], cap_rings["front"][1]]
        mids = [ys[0]] * 2 + ys + [ys[-1]] * 2
        for i in range(len(seq) - 1):
            a, b = seq[i], seq[i + 1]
            ymid = 0.5 * (mids[i] + mids[i + 1]) if 2 <= i < len(seq) - 3 else (ys[0] if i < 2 else ys[-1])
            for j in range(nring):
                jn = (j + 1) % nring
                f = bm.faces.new((a[j], a[jn], b[jn], b[j]))
                seg = j if j < HALF_POINTS - 1 else (nring - 1 - j)
                f.material_index = self.face_material(seg, ymid) if 2 <= i < len(seq) - 3 else 0
                if i < 2 or i >= len(seq) - 3:
                    f.material_index = 3 if seg in SEG_BOTTOM else 0
        for end_ring in (seq[0], seq[-1]):
            bm.faces.new(end_ring)
        bm.normal_update()
        # orientation: make normals point outward
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # creases: material borders sharp, shoulder line medium
        for e in bm.edges:
            mats = {f.material_index for f in e.link_faces}
            if len(mats) > 1 and (1 in mats or 2 in mats or 4 in mats):
                e[crease] = 0.9
        shoulder = self.s.get("shoulder_crease", 0.55)
        for ring in rings:
            for idx in (6, nring - 6):
                v = ring[idx]
                for e in v.link_edges:
                    o = e.other_vert(v)
                    if abs(o.co.y - v.co.y) > 1e-4 and abs(abs(o.co.x) - abs(v.co.x)) < 0.06 and abs(o.co.z - v.co.z) < 0.08:
                        e[crease] = max(e[crease], shoulder)
        return bm


def material_slots():
    return ["Paint", "Glass", "Trim", "Underbody", "Chrome", "WheelWell", "Grille", "Plate",
            "LightHead", "LightTail", "LightReverse", "LightIndicator", "Carbon", "Rubber", "Steel"]


SLOT = {n: i for i, n in enumerate(material_slots())}


def make_cutter_cylinder(name, col, radius, x0, x1, y, z, segs=48):
    bm = bmesh.new()
    C.cylinder_bm(radius, x1 - x0, segments=segs, axis="X", center=((x0 + x1) / 2, y, z), bm=bm)
    ob = C.bm_to_object(bm, name, col, ["WheelWell"], smooth=False)
    ob.hide_render = True
    return ob


def boolean(target, cutter, op="DIFFERENCE"):
    mod = target.modifiers.new("bool_" + cutter.name, "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    if _enum_has(mod, "solver", "EXACT"):
        mod.solver = "EXACT"
    if hasattr(mod, "material_mode"):
        mod.material_mode = "TRANSFER"
    C.apply_modifiers(target)
    data = cutter.data
    bpy.data.objects.remove(cutter, do_unlink=True)
    if data.users == 0:
        bpy.data.meshes.remove(data)


# --------------------------------------------------------------------- decals
def superellipse(theta, a, b, n):
    c, s = math.cos(theta), math.sin(theta)
    x = a * math.copysign(abs(c) ** (2.0 / n), c)
    y = b * math.copysign(abs(s) ** (2.0 / n), s)
    return x, y


def _dir_frame(d):
    """Return (ray direction, axis_u, axis_v) for a projection direction keyword."""
    if d == "front":
        return Vector((0, -1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1))
    if d == "rear":
        return Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1))
    if d == "right":
        return Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    if d == "left":
        return Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    if d == "top":
        return Vector((0, 0, -1)), Vector((1, 0, 0)), Vector((0, 1, 0))
    raise ValueError(d)


def project_decal(bm, bvh, d, center, size, n=4.0, offset=0.004, thick=0.006, mat_index=0,
                  rot=0.0, skew=0.0, rings=3, segs=28, start=4.0, taper=0.0):
    """Add a superellipse patch projected onto the body along direction d into bm."""
    ray, au, av = _dir_frame(d)
    origin_base = -ray * start
    cu, cv = center
    a, b = size

    def world(pu, pv):
        cr, sr = math.cos(rot), math.sin(rot)
        u = pu * cr - pv * sr + skew * pv
        v = pu * sr + pv * cr
        u *= (1.0 - taper * (pv / b if b else 0))
        return origin_base + au * (cu + u) + av * (cv + v)

    grid = []
    pts2 = [[(0.0, 0.0)]]
    for k in range(1, rings + 1):
        fr = k / rings
        ring = []
        for i in range(segs):
            th = 2 * math.pi * i / segs
            x, y = superellipse(th, a * fr, b * fr, n)
            ring.append((x, y))
        pts2.append(ring)
    hits = []
    for ring in pts2:
        row = []
        for (pu, pv) in ring:
            o = world(pu, pv)
            loc, nor, _i, _d = bvh.ray_cast(o, ray, start * 2.5)
            if loc is None:
                return False
            row.append((loc, nor))
        hits.append(row)
    top = []
    for row in hits:
        top.append([bm.verts.new(loc + nor * offset) for (loc, nor) in row])
    faces = []
    c0 = top[0][0]
    for i in range(segs):
        faces.append(bm.faces.new((c0, top[1][i], top[1][(i + 1) % segs])))
    for k in range(1, rings):
        r0, r1 = top[k], top[k + 1]
        for i in range(segs):
            faces.append(bm.faces.new((r0[i], r1[i], r1[(i + 1) % segs], r0[(i + 1) % segs])))
    # skirt down into the body so the decal reads as a raised part with no gap
    outer = top[-1]
    base = [bm.verts.new(loc - nor * (thick if thick > 0 else 0.002)) for (loc, nor) in hits[-1]]
    for i in range(segs):
        faces.append(bm.faces.new((outer[i], base[i], base[(i + 1) % segs], outer[(i + 1) % segs])))
    for f in faces:
        f.material_index = mat_index
    # orient outward: compare centre fan normal with the surface normal at the centre hit
    faces[0].normal_update()
    if faces[0].normal.dot(hits[0][0][1]) < 0:
        bmesh.ops.reverse_faces(bm, faces=faces)
    return True


# ---------------------------------------------------------------------- wheels
def build_wheel_mesh(s, name, col):
    R = s["wheel_r"]
    W = s["tire_w"]
    Rr = s.get("rim_r", R * 0.68)
    style = s.get("rim_style", "5spoke")
    side = s.get("tire_sidewall_bulge", 0.012)
    hw = W / 2
    prof = [
        (Rr - 0.004, -hw + 0.012), (Rr + (R - Rr) * 0.35, -hw - side * 0.6), (Rr + (R - Rr) * 0.72, -hw - side),
        (R - 0.018, -hw + 0.004), (R - 0.004, -hw + 0.022), (R, -hw + 0.04),
    ]
    grooves = s.get("tire_grooves", 3)
    tread_pts = []
    span = W - 0.08
    for k in range(grooves + 1):
        x0 = -hw + 0.04 + span * k / (grooves + 1)
        x1 = -hw + 0.04 + span * (k + 1) / (grooves + 1)
        tread_pts.append((R, x0 + 0.006))
        if k < grooves:
            tread_pts += [(R, x1 - 0.006), (R - 0.009, x1 - 0.004), (R - 0.009, x1 + 0.004)]
    prof += tread_pts[1:]
    prof += [(R, hw - 0.04), (R - 0.004, hw - 0.022), (R - 0.018, hw - 0.004),
             (Rr + (R - Rr) * 0.72, hw + side), (Rr + (R - Rr) * 0.35, hw + side * 0.6), (Rr - 0.004, hw - 0.012)]
    bm = C.revolve(prof, 56, axis="X", uv_repeat=8.0)
    # the profile runs -X -> +X across the tread, which winds the faces inwards; flip them so the
    # tyre survives back-face culling in the engine
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.material_index = 0  # Rubber
    # chunky staggered tread blocks for off-road tyres
    if s.get("offroad_tires"):
        nb = 30
        for i in range(nb):
            for sx in (-1, 1):
                ang = 2 * math.pi * (i + (0.5 if sx > 0 else 0.0)) / nb
                res = bmesh.ops.create_cube(bm, size=1.0)
                m = Matrix.Rotation(ang, 3, "X")
                for v in res["verts"]:
                    lv = Vector((v.co.x * W * 0.34 + sx * W * 0.2, v.co.y * 0.075, v.co.z * 0.024 + R + 0.004))
                    v.co = m @ lv
                for f in {f for v in res["verts"] for f in v.link_faces}:
                    f.material_index = 0
    # rim barrel + face (outer face towards +X)
    face_x = hw - 0.025
    rim_prof = [
        (Rr - 0.02, -hw + 0.02), (Rr - 0.012, -hw + 0.01), (Rr + 0.006, -hw + 0.012), (Rr + 0.008, -hw + 0.024),
        (Rr - 0.006, -hw + 0.03), (Rr - 0.012, face_x - 0.02), (Rr + 0.004, face_x - 0.004),
        (Rr + 0.014, face_x + 0.006), (Rr + 0.004, face_x + 0.014), (Rr - 0.018, face_x + 0.006),
        (Rr - 0.03, face_x - 0.01),
    ]
    rbm = C.revolve(rim_prof, 56, axis="X", uv_repeat=4.0)
    for f in rbm.faces:
        f.material_index = 1  # Rim
    me_tmp = bpy.data.meshes.new("_rim")
    rbm.to_mesh(me_tmp)
    rbm.free()
    bm.from_mesh(me_tmp)
    bpy.data.meshes.remove(me_tmp)
    # hub
    hub_r = s.get("hub_r", 0.075)
    hub = C.revolve([(0.0, face_x - 0.01), (hub_r * 0.55, face_x + 0.004), (hub_r, face_x - 0.006),
                     (hub_r, face_x - 0.05), (hub_r * 0.8, face_x - 0.07)], 24, axis="X")
    for f in hub.faces:
        f.material_index = 1
    me_tmp = bpy.data.meshes.new("_hub")
    hub.to_mesh(me_tmp)
    hub.free()
    bm.from_mesh(me_tmp)
    bpy.data.meshes.remove(me_tmp)
    # spokes
    _add_spokes(bm, style, Rr, hub_r, face_x, s)
    # brake disc (spins with the wheel)
    disc_r = min(Rr - 0.04, s.get("disc_r", Rr * 0.82))
    C.cylinder_bm(disc_r, 0.026, segments=40, axis="X", center=(face_x - 0.085, 0, 0), bm=bm, mat_index=2)
    C.cylinder_bm(disc_r * 0.45, 0.06, segments=24, axis="X", center=(face_x - 0.06, 0, 0), bm=bm, mat_index=2)
    # lug nuts
    for i in range(5):
        a = 2 * math.pi * i / 5
        C.cylinder_bm(0.011, 0.02, segments=8, axis="X",
                      center=(face_x + 0.006, math.cos(a) * hub_r * 0.62, math.sin(a) * hub_r * 0.62), bm=bm, mat_index=3)
    bm.normal_update()
    ob = C.bm_to_object(bm, name, col, ["Rubber", "Rim", "BrakeDisc", "Chrome"], smooth=True)
    _sharpen_by_angle(ob, 40.0)
    return ob


def _sharpen_by_angle(ob, deg):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    lim = math.radians(deg)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()


def _add_spokes(bm, style, Rr, hub_r, face_x, s):
    def spoke(angle, width_in, width_out, depth, r0, r1, dish=0.02, twist=0.0, x_off=0.0):
        # a tapered box from r0 to r1 at angle, slightly dished inward towards the hub
        res = bmesh.ops.create_cube(bm, size=1.0)
        vs = res["verts"]
        for v in vs:
            t = v.co.z + 0.5  # 0 at hub, 1 at rim
            r = C.lerp(r0, r1, t)
            w = C.lerp(width_in, width_out, t)
            x = face_x + x_off - dish * (1 - t) + v.co.x * depth
            y = v.co.y * w
            ang = angle + twist * t
            v.co = Vector((x, math.cos(ang) * y - math.sin(ang) * r, math.sin(ang) * y + math.cos(ang) * r))
        for f in {f for v in vs for f in v.link_faces}:
            f.material_index = 1

    r0, r1 = hub_r * 0.85, Rr - 0.012
    if style == "5spoke":
        for i in range(5):
            spoke(2 * math.pi * i / 5, 0.05, 0.034, 0.03, r0, r1, dish=0.03)
    elif style == "split5":
        for i in range(5):
            a = 2 * math.pi * i / 5
            spoke(a - 0.09, 0.03, 0.018, 0.026, r0, r1, dish=0.025, twist=-0.08)
            spoke(a + 0.09, 0.03, 0.018, 0.026, r0, r1, dish=0.025, twist=0.08)
    elif style == "10spoke":
        for i in range(10):
            spoke(2 * math.pi * i / 10, 0.026, 0.02, 0.024, r0, r1, dish=0.02)
    elif style == "mesh":
        for i in range(12):
            a = 2 * math.pi * i / 12
            spoke(a, 0.016, 0.012, 0.02, r0, r1, dish=0.015, twist=0.32)
            spoke(a, 0.016, 0.012, 0.02, r0, r1, dish=0.015, twist=-0.32, x_off=-0.006)
    elif style == "turbine":
        for i in range(14):
            spoke(2 * math.pi * i / 14, 0.024, 0.03, 0.016, r0, r1, dish=0.01, twist=0.45)
    elif style == "steel":
        disc = C.revolve([(hub_r, face_x - 0.004), (Rr * 0.55, face_x - 0.012), (Rr * 0.75, face_x - 0.02),
                          (Rr - 0.01, face_x - 0.004)], 40, axis="X")
        me_tmp = bpy.data.meshes.new("_disc")
        disc.to_mesh(me_tmp)
        disc.free()
        bm.from_mesh(me_tmp)
        bpy.data.meshes.remove(me_tmp)
        for f in bm.faces:
            pass
        for i in range(6):
            a = 2 * math.pi * i / 6
            C.cylinder_bm(0.026, 0.01, segments=12, axis="X",
                          center=(face_x - 0.008, math.cos(a) * Rr * 0.66, math.sin(a) * Rr * 0.66), bm=bm, mat_index=3)
    elif style == "wire":
        for i in range(32):
            a = 2 * math.pi * i / 32
            spoke(a, 0.005, 0.005, 0.005, r0 * 0.9, r1, dish=0.06 if i % 2 else 0.02, twist=0.35 if i % 2 else -0.35)
        C.cylinder_bm(hub_r * 0.75, 0.05, segments=8, axis="X", center=(face_x + 0.02, 0, 0), bm=bm, mat_index=3)
    elif style == "offroad":
        for i in range(6):
            spoke(2 * math.pi * i / 6, 0.07, 0.06, 0.04, r0, r1, dish=0.035)
        for i in range(16):
            a = 2 * math.pi * i / 16
            C.cylinder_bm(0.008, 0.012, segments=6, axis="X",
                          center=(face_x + 0.012, math.cos(a) * (Rr + 0.004), math.sin(a) * (Rr + 0.004)), bm=bm, mat_index=3)
    elif style == "dish":
        disc = C.revolve([(hub_r, face_x - 0.004), (Rr * 0.7, face_x - 0.006), (Rr - 0.01, face_x + 0.004)], 40, axis="X")
        me_tmp = bpy.data.meshes.new("_disc")
        disc.to_mesh(me_tmp)
        disc.free()
        bm.from_mesh(me_tmp)
        bpy.data.meshes.remove(me_tmp)
        for i in range(8):
            a = 2 * math.pi * i / 8
            C.cylinder_bm(0.018, 0.012, segments=10, axis="X",
                          center=(face_x - 0.002, math.cos(a) * Rr * 0.5, math.sin(a) * Rr * 0.5), bm=bm, mat_index=2)
    else:
        for i in range(6):
            spoke(2 * math.pi * i / 6, 0.04, 0.03, 0.026, r0, r1)


def build_caliper(s, name, col, front):
    Rr = s.get("rim_r", s["wheel_r"] * 0.68)
    disc_r = min(Rr - 0.04, s.get("disc_r", Rr * 0.82))
    face_x = s["tire_w"] / 2 - 0.025
    bm = bmesh.new()
    # arc-shaped caliper hugging the disc edge
    seg = 6
    a0, a1 = math.radians(20), math.radians(70) if front else math.radians(60)
    verts_o, verts_i = [], []
    for i in range(seg + 1):
        a = C.lerp(a0, a1, i / seg)
        for (r, store) in ((disc_r + 0.012, verts_o), (disc_r - 0.05, verts_i)):
            y = -math.cos(a) * r
            z = math.sin(a) * r
            store.append((y, z))
    xs = (face_x - 0.12, face_x - 0.05)
    grid = []
    for x in xs:
        row = [bm.verts.new((x, y, z)) for (y, z) in verts_o] + [bm.verts.new((x, y, z)) for (y, z) in reversed(verts_i)]
        grid.append(row)
    n = len(grid[0])
    for j in range(n):
        bm.faces.new((grid[0][j], grid[0][(j + 1) % n], grid[1][(j + 1) % n], grid[1][j]))
    bm.faces.new(grid[0][::-1])
    bm.faces.new(grid[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = C.bm_to_object(bm, name, col, ["Caliper"], smooth=False)
    return ob


# -------------------------------------------------------------------- interior
def build_interior(s, body, col, prefix, glass_mat_index):
    """Inner shell (inverted body minus glass) + seats + dashboard + console + steering."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    glass = [f for f in bm.faces if f.material_index == glass_mat_index]
    bmesh.ops.delete(bm, geom=glass, context="FACES")
    for f in bm.faces:
        f.material_index = 0
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.normal_update()
    for v in bm.verts:
        v.co -= v.normal * -0.012  # normals already inverted, so move inward
    inner = C.bm_to_object(bm, prefix + "_Interior", col, ["Interior", "Seat", "Gauges", "Chrome", "Wood"])
    W = s["hw"][len(s["hw"]) // 2][1]
    seat_y = s.get("seat_y", 0.0)
    floor_z = s.get("floor_z", s["bottom"][len(s["bottom"]) // 2][1] + 0.12)
    driver_x = s.get("driver_x", -0.36)
    parts = []
    seat_xs = [driver_x, -driver_x] if not s.get("single_seat") else [driver_x]
    rows = [seat_y] + ([seat_y - 0.85] if s.get("rear_seats") else [])
    for ri, sy in enumerate(rows):
        for sx in seat_xs:
            parts.append(C.rounded_box(prefix + "_tmpseat", col, (0.46, 0.5, 0.12), (sx, sy, floor_z + 0.2), 0.04, ["Seat"]))
            back = C.rounded_box(prefix + "_tmpback", col, (0.46, 0.12, 0.62), (sx, sy - 0.27, floor_z + 0.5), 0.05, ["Seat"],
                                 rot=(math.radians(-14), 0, 0))
            parts.append(back)
            if ri == 0 and not s.get("no_headrest"):
                parts.append(C.rounded_box(prefix + "_tmphead", col, (0.24, 0.1, 0.16), (sx, sy - 0.36, floor_z + 0.9), 0.04, ["Seat"]))
    dash_y = s.get("dash_y", seat_y + 0.85)
    belt_mid = s["belt"][len(s["belt"]) // 2][1]
    dash_z = s.get("dash_z", belt_mid - 0.04)
    dw = s.get("dash_w", W * 1.65)
    parts.append(C.rounded_box(prefix + "_tmpdash", col, (dw, 0.36, 0.2), (0, dash_y, dash_z - 0.06), 0.06, ["Interior"]))
    cl = C.rounded_box(prefix + "_tmpclu", col, (0.34, 0.08, 0.12), (driver_x, dash_y - 0.16, dash_z + 0.03), 0.02, ["Gauges"])
    parts.append(cl)
    parts.append(C.rounded_box(prefix + "_tmpcons", col, (0.22, 0.7, 0.18), (0, seat_y + 0.25, floor_z + 0.12), 0.04, ["Interior"]))
    parts.append(C.rounded_box(prefix + "_tmpshift", col, (0.04, 0.04, 0.12), (0, seat_y + 0.38, floor_z + 0.28), 0.015, ["Chrome"]))
    C.join_into(inner, parts)
    # steering wheel: own object, pivot at the hub, rim faces the driver
    st_y = dash_y - 0.32
    st_z = dash_z + 0.0
    bm = bmesh.new()
    ring_r, tube = 0.18, 0.016
    seg, sides = 36, 8
    ring = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            r = ring_r + tube * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), tube * math.sin(b), r * math.sin(a))))
        ring.append(row)
    for i in range(seg):
        for j in range(sides):
            bm.faces.new((ring[i][j], ring[(i + 1) % seg][j], ring[(i + 1) % seg][(j + 1) % sides], ring[i][(j + 1) % sides]))
    for ang in (0.0, math.pi, -math.pi / 2):
        res = bmesh.ops.create_cube(bm, size=1.0)
        for v in res["verts"]:
            lv = Vector((v.co.x * 0.03, v.co.y * 0.018, v.co.z * ring_r + ring_r * 0.5))
            v.co = Matrix.Rotation(ang - math.pi / 2, 3, "Y") @ lv
    C.cylinder_bm(0.05, 0.05, segments=16, axis="Y", center=(0, 0.01, 0), bm=bm, mat_index=0)
    for f in bm.faces:
        f.material_index = 0
    steer = C.bm_to_object(bm, prefix + "_Steering", col, ["Interior"], location=(driver_x, st_y, st_z))
    steer.rotation_euler = (math.radians(-22), 0, 0)
    return inner, steer


# --------------------------------------------------------------------- extras
def build_extras(s, col, prefix, body_bvh, yF, yR):
    parts = []
    for ex in s.get("extras", []):
        kind = ex["kind"]
        if kind == "mirror":
            x, y, z = ex["pos"]
            for sx in (-1, 1):
                parts.append(C.rounded_box(prefix + "_tmpm", col, (0.08, 0.13, 0.08), (sx * (x + 0.06), y, z), 0.025,
                                           [ex.get("mat", "Paint")]))
                parts.append(C.rounded_box(prefix + "_tmpms", col, (0.07, 0.03, 0.025), (sx * (x - 0.005), y + 0.02, z - 0.03), 0.008, ["Trim"]))
        elif kind == "wing":
            parts += _wing(ex, col, prefix)
        elif kind == "box":
            sz, pos = ex["size"], ex["pos"]
            mirror = ex.get("mirror", False)
            for sx in ((-1, 1) if mirror else (1,)):
                parts.append(C.rounded_box(prefix + "_tmpbox", col, sz, (sx * pos[0], pos[1], pos[2]), ex.get("bevel", 0.01),
                                           [ex.get("mat", "Trim")], rot=ex.get("rot")))
        elif kind == "exhaust":
            for (x, y, z) in ex["pos"]:
                bm = bmesh.new()
                C.cylinder_bm(ex.get("r", 0.045), 0.16, segments=20, axis="Y", center=(x, y, z), bm=bm, mat_index=0, cap=False)
                C.cylinder_bm(ex.get("r", 0.045) * 0.8, 0.02, segments=20, axis="Y", center=(x, y - 0.06, z), bm=bm, mat_index=1)
                ob = C.bm_to_object(bm, prefix + "_tmpex", col, ["Chrome", "Underbody"])
                parts.append(ob)
        elif kind == "cyl":
            bm = bmesh.new()
            C.cylinder_bm(ex["r"], ex["len"], segments=ex.get("segs", 20), axis=ex.get("axis", "Y"),
                          center=tuple(ex["pos"]), bm=bm, mat_index=0)
            ob = C.bm_to_object(bm, prefix + "_tmpcyl", col, [ex.get("mat", "Chrome")])
            if ex.get("mirror"):
                bm2 = bmesh.new()
                p = ex["pos"]
                C.cylinder_bm(ex["r"], ex["len"], segments=ex.get("segs", 20), axis=ex.get("axis", "Y"),
                              center=(-p[0], p[1], p[2]), bm=bm2, mat_index=0)
                parts.append(C.bm_to_object(bm2, prefix + "_tmpcyl2", col, [ex.get("mat", "Chrome")]))
            parts.append(ob)
        elif kind == "tube":  # roll bars, bull bars, roof rails: polyline tube
            parts.append(_tube(ex, col, prefix))
        elif kind == "spare":
            w = build_wheel_mesh(dict(s, rim_style=s.get("rim_style", "steel")), prefix + "_tmpspare", col)
            w.rotation_euler = (0, 0, math.pi / 2)
            w.location = ex["pos"]
            C.apply_modifiers(w)
            w.data.transform(w.matrix_basis)
            w.matrix_basis = Matrix.Identity(4)
            parts.append(w)
    return parts


def _wing(ex, col, prefix):
    chord, span, th = ex.get("chord", 0.26), ex.get("span", 1.4), ex.get("thick", 0.03)
    x0, y0, z0 = ex["pos"]
    prof = []
    for i in range(9):
        t = i / 8
        prof.append((t, th * 0.5 * math.sin(math.pi * t) + ex.get("camber", 0.02) * t))
    prof += [(t, -th * 0.15 * math.sin(math.pi * t)) for (t, _) in reversed(prof[1:-1])]
    bm = bmesh.new()
    rows = []
    for sx in (-span / 2, span / 2):
        rows.append([bm.verts.new((sx, y0 - t * chord, z0 + z)) for (t, z) in prof])
    n = len(prof)
    for j in range(n):
        bm.faces.new((rows[0][j], rows[0][(j + 1) % n], rows[1][(j + 1) % n], rows[1][j]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out = [C.bm_to_object(bm, prefix + "_tmpwing", col, [ex.get("mat", "Carbon")], smooth=False)]
    for sx in (-1, 1):
        out.append(C.rounded_box(prefix + "_tmpend", col, (0.012, chord * 1.15, ex.get("plate_h", 0.12)),
                                 (sx * span / 2, y0 - chord * 0.5, z0 + 0.01), 0.004, [ex.get("mat", "Carbon")]))
        sh = ex.get("strut_h", 0.18)
        out.append(C.rounded_box(prefix + "_tmpstrut", col, (0.016, chord * 0.5, sh),
                                 (sx * ex.get("strut_x", span * 0.32), y0 - chord * 0.45, z0 - sh * 0.5), 0.004, [ex.get("strut_mat", "Carbon")]))
    return out


def _tube(ex, col, prefix):
    pts = [Vector(p) for p in ex["points"]]
    r = ex.get("r", 0.025)
    sides = 10
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            d = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            d = (pts[-1] - pts[-2]).normalized()
        else:
            d = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        v = d.cross(u).normalized()
        rings.append([bm.verts.new(p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r)
                      for k in range(sides)])
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = C.bm_to_object(bm, prefix + "_tmptube", col, [ex.get("mat", "Chrome")])
    if ex.get("mirror"):
        bm2 = bmesh.new()
        bm2.from_mesh(ob.data)
        bmesh.ops.scale(bm2, vec=(-1, 1, 1), verts=bm2.verts)
        bmesh.ops.reverse_faces(bm2, faces=bm2.faces)
        ob2 = C.bm_to_object(bm2, prefix + "_tmptube2", col, [ex.get("mat", "Chrome")])
        C.join_into(ob, [ob2])
    return ob


# ------------------------------------------------------------------------ main
def build_car(s, category="Cars"):
    C.guard()
    prefix = s["id"]
    col = C.collection("%s/%s/%s" % (C.ROOT, category, prefix))
    C.clear_collection(col)
    body_def = Body(s)
    bm = body_def.build_mesh()
    body = C.bm_to_object(bm, prefix + "_Body", col, material_slots())
    sub = body.modifiers.new("subd", "SUBSURF")
    sub.levels = s.get("subd", 2)
    sub.render_levels = s.get("subd", 2)
    if hasattr(sub, "use_creases"):
        sub.use_creases = True
    C.apply_modifiers(body)
    # wheel arches
    R = s["wheel_r"]
    RR = s.get("wheel_r_rear", R)
    gap = s.get("arch_gap", 0.04)
    for ax, track, rad, tw in ((body_def.axF, s["track_f"], R, s["tire_w"]), (body_def.axR, s["track_r"], RR, s.get("tire_w_rear", s["tire_w"]))):
        for sx in (-1, 1):
            inner = track / 2 - tw / 2 - 0.07
            x0, x1 = (inner, 2.2) if sx > 0 else (-2.2, -inner)
            cut = make_cutter_cylinder(prefix + "_cut", col, rad + gap, x0, x1, ax, rad + s.get("arch_z", 0.0))
            boolean(body, cut)
    for cut_def in s.get("cuts", []):  # pickup beds, open cockpits, intakes
        bm2 = C.box_bm(*cut_def["size"], center=cut_def["pos"])
        cut = C.bm_to_object(bm2, prefix + "_cutbox", col, [cut_def.get("mat", "Interior")], smooth=False)
        mod = cut.modifiers.new("bev", "BEVEL")
        mod.width = cut_def.get("bevel", 0.04)
        mod.segments = 3
        C.apply_modifiers(cut)
        boolean(body, cut)
    # decals projected onto the body surface
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(body, dg)
    lights = {"LightHead": bmesh.new(), "LightTail": bmesh.new(), "LightReverse": bmesh.new(), "LightIndicator": bmesh.new()}
    deco = bmesh.new()
    missed = []
    for d in s.get("decals", []):
        dirs = [d["dir"]]
        centers = [tuple(d["c"])]
        if d.get("mirror", True) and d["dir"] in ("front", "rear", "top") and abs(d["c"][0]) > 1e-4:
            dirs.append(d["dir"])
            centers.append((-d["c"][0], d["c"][1]))
        if d["dir"] == "side":
            dirs = ["right", "left"]
            centers = [tuple(d["c"]), tuple(d["c"])]
        for dd, cc in zip(dirs, centers):
            m = d["mat"]
            rot = d.get("rot", 0.0)
            skew = d.get("skew", 0.0)
            if dd in ("front", "rear", "top") and cc[0] < 0:
                rot, skew = -rot, -skew
            if m in lights:
                ok = project_decal(lights[m], bvh, dd, cc, d["size"], n=d.get("n", 4), offset=d.get("off", 0.005),
                                   thick=d.get("thick", 0.008), mat_index=0, rot=rot, skew=skew, taper=d.get("taper", 0.0))
            else:
                ok = project_decal(deco, bvh, dd, cc, d["size"], n=d.get("n", 4), offset=d.get("off", 0.003),
                                   thick=d.get("thick", 0.004), mat_index=SLOT[m], rot=rot, skew=skew, taper=d.get("taper", 0.0))
            if not ok:
                missed.append((d["mat"], dd, cc))
    deco_ob = C.bm_to_object(deco, prefix + "_tmpdeco", col, material_slots())
    extras = build_extras(s, col, prefix, bvh, body_def.yF, body_def.yR)
    # glass out of the body
    gbm = bmesh.new()
    gbm.from_mesh(body.data)
    bmesh.ops.delete(gbm, geom=[f for f in gbm.faces if f.material_index != SLOT["Glass"]], context="FACES")
    glass = C.bm_to_object(gbm, prefix + "_Glass", col, material_slots())
    if s.get("opaque_glass"):
        glass.data.materials[SLOT["Glass"]] = C.mat("GlassDark", (0.03, 0.04, 0.05, 1))
    if s.get("no_interior"):
        interior, steer = None, None
    else:
        interior, steer = build_interior(s, body, col, prefix, SLOT["Glass"])
    bbm = bmesh.new()
    bbm.from_mesh(body.data)
    bmesh.ops.delete(bbm, geom=[f for f in bbm.faces if f.material_index == SLOT["Glass"]], context="FACES")
    bbm.to_mesh(body.data)
    bbm.free()
    C.join_into(body, [deco_ob] + extras)
    _clean_slots(glass)
    _clean_slots(body)
    light_names = {"LightHead": "Lights_Head", "LightTail": "Lights_Tail", "LightReverse": "Lights_Reverse",
                   "LightIndicator": "Lights_Indicator"}
    light_obs = []
    for m, lbm in lights.items():
        if len(lbm.faces) == 0:
            lbm.free()
            continue
        light_obs.append(C.bm_to_object(lbm, prefix + "_" + light_names[m], col, [m]))
    # wheels (+X outward face built once, linked duplicates for the 4 corners)
    wheel_src = build_wheel_mesh(s, prefix + "_Wheel_FR", col)
    wheel_src.location = (s["track_f"] / 2, body_def.axF, R)
    rear_spec = dict(s)
    for k in ("wheel_r", "tire_w", "rim_r", "rim_style"):
        if k + "_rear" in s:
            rear_spec[k] = s[k + "_rear"]
    rear_src = wheel_src.data if rear_spec == s else build_wheel_mesh(rear_spec, prefix + "_tmprearwheel", col).data
    wheels = {"FR": wheel_src}
    for key, (x, y, rad, data) in {"FL": (-s["track_f"] / 2, body_def.axF, R, wheel_src.data),
                                   "RR": (s["track_r"] / 2, body_def.axR, RR, rear_src),
                                   "RL": (-s["track_r"] / 2, body_def.axR, RR, rear_src)}.items():
        ob = C.new_object(prefix + "_Wheel_" + key, data, col, location=(x, y, rad))
        if x < 0:
            ob.rotation_euler = (0, 0, math.pi)
        wheels[key] = ob
    for o in list(col.objects):
        if "_tmprearwheel" in o.name:
            bpy.data.objects.remove(o, do_unlink=True)
    calipers = []
    for key, w in wheels.items():
        front = key[0] == "F"
        cal = build_caliper(s if front else rear_spec, prefix + "_Caliper_" + key, col, front)
        cal.location = w.location
        if w.location.x < 0:  # mirror across X so it sits on the inner side, still at the rear-top
            cbm = bmesh.new()
            cbm.from_mesh(cal.data)
            bmesh.ops.scale(cbm, vec=(-1, 1, 1), verts=cbm.verts)
            bmesh.ops.reverse_faces(cbm, faces=cbm.faces)
            cbm.to_mesh(cal.data)
            cbm.free()
        calipers.append(cal)
    # sockets for Godot (cameras, lights, exhaust)
    sk = s.get("sockets", {})
    driver_x = s.get("driver_x", -0.36)
    seat_y = s.get("seat_y", 0.0)
    floor_z = s.get("floor_z", s["bottom"][len(s["bottom"]) // 2][1] + 0.12)
    defaults = {
        "Cockpit": (driver_x, seat_y - 0.12, floor_z + 0.95),
        "Hood": (0.0, body_def.axF - 0.35, body_def.belt(body_def.axF) + 0.42),
        "Bumper": (0.0, body_def.yF - 0.05, max(0.45, body_def.bottom(body_def.yF) + 0.3)),
    }
    defaults.update({k: tuple(v) for k, v in sk.items()})
    sockets = [C.new_empty(prefix + "_Socket_" + k, col, v) for k, v in defaults.items()]
    for o in [body, glass, interior, steer] + light_obs + calipers:
        if o is not None:
            C.box_uv(o)
    for o in (body, glass, interior):
        if o is not None:
            _sharpen_by_angle(o, s.get("sharp_angle", 50.0))
    meta = dict(id=prefix, axle_f=body_def.axF, axle_r=body_def.axR, wheel_r=R, track_f=s["track_f"],
                track_r=s["track_r"], missed_decals=missed)
    body["valoria_meta"] = str(meta)
    return col, meta


def _clean_slots(ob):
    """Drop unused material slots (keeps glTF primitives minimal)."""
    me = ob.data
    used = sorted({p.material_index for p in me.polygons})
    if not used:
        return
    mats = [me.materials[i] for i in used]
    remap = {old: new for new, old in enumerate(used)}
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", idx)
    me.update()


def export_car(prefix, out_path, category="Cars"):
    col = bpy.data.collections[prefix]
    objs = [o for o in col.all_objects]
    return C.export_glb(objs, out_path)
