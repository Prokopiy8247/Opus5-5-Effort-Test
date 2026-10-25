# Executed inside the project's Blender instance (port 9877) via tools/bl.py.
# Builds the 10 player cars + 6 traffic vehicles as lofted bodies, separate wheels,
# glass, lights, interior. Front of every vehicle points to Blender +Y (= Godot -Z).
import bpy, bmesh, math, os
from mathutils import Vector

PROJ = os.path.dirname(bpy.data.filepath)
OUT = os.path.join(PROJ, "assets", "imported", "vehicles")
os.makedirs(OUT, exist_ok=True)

def mat(name, col, metal=0.0, rough=0.5, emit=None, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 2.0
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    return m

M = {
    "Paint": mat("Paint", (0.8, 0.1, 0.05), 0.3, 0.3),
    "Glass": mat("Glass", (0.02, 0.03, 0.04), 0.3, 0.03, alpha=0.82),
    "Trim": mat("Trim", (0.03, 0.03, 0.035), 0.0, 0.6),
    "Chrome": mat("Chrome", (0.8, 0.8, 0.8), 1.0, 0.15),
    "Tire": mat("Tire", (0.02, 0.02, 0.02), 0.0, 0.9),
    "Rim": mat("Rim", (0.6, 0.6, 0.62), 0.9, 0.3),
    "Disc": mat("Disc", (0.3, 0.3, 0.3), 0.8, 0.4),
    "LightF": mat("LightF", (1, 1, 0.9), 0.0, 0.1, emit=(1, 1, 0.9)),
    "LightR": mat("LightR", (0.8, 0.0, 0.0), 0.0, 0.2, emit=(1, 0, 0)),
    "Interior": mat("Interior", (0.08, 0.07, 0.07), 0.0, 0.8),
}

def interp(pts, u):
    if u <= pts[0][0]: return pts[0][1]
    for (a, za), (b, zb) in zip(pts, pts[1:]):
        if u <= b:
            t = (u - a) / (b - a)
            t = t * t * (3 - 2 * t)
            return za + (zb - za) * t
    return pts[-1][1]

def link(obj, coll):
    for c in obj.users_collection: c.objects.unlink(obj)
    coll.objects.link(obj)

PREFIX = [""]
recalc = [True]
def new_obj(name, bm, coll, material_names):
    name = PREFIX[0] + name
    me = bpy.data.meshes.new(name)
    if recalc[0]: bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    for n in material_names: me.materials.append(M[n])
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    for p in me.polygons: p.use_smooth = True
    return o

def loft(bm, sections, close_ends=True, mat_index=0):
    rows = [[bm.verts.new(p) for p in s] for s in sections]
    n = len(sections[0])
    for r0, r1 in zip(rows, rows[1:]):
        for i in range(n if close_ends else n - 1):
            f = bm.faces.new((r0[i], r0[(i + 1) % n], r1[(i + 1) % n], r1[i]))
            f.material_index = mat_index
    if close_ends:
        f = bm.faces.new(rows[0][::-1]); f.material_index = mat_index
        f = bm.faces.new(rows[-1]); f.material_index = mat_index
    return rows

def body_section(y, hw, zb, zt, k=0.35, n=24):
    pts = []
    zm, hh = (zb + zt) / 2, (zt - zb) / 2
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        x = hw * math.copysign(abs(c) ** k, c)
        z = zm + hh * math.copysign(abs(s) ** k, s)
        pts.append(Vector((x, y, z)))
    return pts

def box(bm, c, s, mi=0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]:
        v.co = Vector((c[0] + v.co.x * s[0], c[1] + v.co.y * s[1], c[2] + v.co.z * s[2]))
    for f in {f for v in r["verts"] for f in v.link_faces}: f.material_index = mi

def wheel(name, coll, r, w, rim_style, loc):
    bm = bmesh.new()
    seg = 28
    # tyre: profile rings rotated around X axis (lateral)
    prof = [(-w/2, r*0.62), (-w/2, r*0.92), (-w*0.42, r), (w*0.42, r), (w/2, r*0.92), (w/2, r*0.62)]
    rows = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        rows.append([bm.verts.new((x, math.cos(a) * rr, math.sin(a) * rr)) for x, rr in prof])
    for i in range(seg):
        r0, r1 = rows[i], rows[(i + 1) % seg]
        for j in range(len(prof) - 1):
            bm.faces.new((r0[j], r1[j], r1[j + 1], r0[j + 1])).material_index = 0
    # rim discs (both sides) with spokes pattern via ring of verts
    for side in (-1, 1):
        x = side * w * 0.45
        ctr = bm.verts.new((x - side * 0.03, 0, 0))
        ring = [bm.verts.new((x, math.cos(2*math.pi*i/seg) * r*0.62, math.sin(2*math.pi*i/seg) * r*0.62)) for i in range(seg)]
        for i in range(seg):
            f = bm.faces.new((ctr, ring[i], ring[(i + 1) % seg]) if side > 0 else (ctr, ring[(i + 1) % seg], ring[i]))
            f.material_index = 1
    # spokes
    ns = rim_style
    for i in range(ns):
        a = 2 * math.pi * i / ns
        for side in (-1, 1):
            c = (side * w * 0.47, math.cos(a) * r * 0.33, math.sin(a) * r * 0.33)
            r_ = bmesh.ops.create_cube(bm, size=1.0)
            ca, sa = math.cos(a), math.sin(a)
            for v in r_["verts"]:
                lx, ly, lz = v.co.x * 0.03, v.co.y * r * 0.55, v.co.z * 0.07
                v.co = Vector((c[0] + lx, c[1] + ly * ca - lz * sa, c[2] + ly * sa + lz * ca))
            for f in {f for v in r_["verts"] for f in v.link_faces}: f.material_index = 1
    o = new_obj(name, bm, coll, ["Tire", "Rim"])
    o.location = loc
    return o

def disc(name, coll, r, loc):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=r * 0.5, radius2=r * 0.5, depth=0.03)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(math.pi / 2, 3, "Y"))
    o = new_obj(name, bm, coll, ["Disc"])
    o.location = loc
    return o

def build_vehicle(key, d, parent_coll):
    PREFIX[0] = key + "_"
    coll = bpy.data.collections.new(key)
    parent_coll.children.link(coll)
    L, W = d["L"], d["W"]
    hw0 = W / 2
    N = 32
    secs = []
    for i in range(N + 1):
        u = i / N
        y = -L / 2 + u * L
        edge = min(u, 1 - u)
        tap = 1.0 - d.get("taper", 0.18) * max(0.0, 1 - edge / 0.12) ** 2
        zt = interp(d["belt"], u)
        zb = interp(d.get("sill", [(0, d["zb"]), (1, d["zb"])]), u)
        nose = max(0.0, 1 - edge / 0.04)
        zb2 = zb + (zt - zb) * 0.35 * nose
        zt2 = zt - (zt - zb) * 0.25 * nose
        secs.append(body_section(y, hw0 * tap * (1 - 0.15 * nose), zb2, zt2, min(1.0, d.get("k", 0.35) * 1.6)))
    bm = bmesh.new()
    loft(bm, secs)
    # details on body: bumpers, grille, mirrors, extras
    box(bm, (0, L / 2 - 0.16, d["zb"] + 0.12), (W * 0.78, 0.12, 0.12), 1)
    box(bm, (0, -L / 2 + 0.16, d["zb"] + 0.12), (W * 0.78, 0.12, 0.12), 1)
    box(bm, (0, L / 2 + 0.01, interp(d["belt"], 0.98) - 0.12), (W * 0.45, 0.06, 0.1), 1)
    if d.get("cab"):
        cy = -L / 2 + d["cab"][0][0] * L + 0.25 * L * (d["cab"][-1][0] - d["cab"][0][0]) * 2.2
        bz = interp(d["belt"], d["cab"][-1][0])
        for s in (-1, 1):
            box(bm, (s * (hw0 + 0.06), -L / 2 + d["cab"][-1][0] * L - 0.15, bz + 0.06), (0.12, 0.08, 0.08), 0)
    for e in d.get("extras", []):
        box(bm, e[0], e[1], e[2])
    body = new_obj("Body", bm, coll, ["Paint", "Trim", "Chrome"])

    # greenhouse (glass) + roof panel (paint)
    if d.get("cab"):
        cab = d["cab"]
        u0, u1 = cab[0][0], cab[-1][0]
        gsecs, rsecs = [], []
        M_ = 14
        for i in range(M_ + 1):
            u = u0 + (u1 - u0) * i / M_
            y = -L / 2 + u * L
            zb = interp(d["belt"], u) - 0.02
            zr = interp(cab, u)
            zr = max(zr, zb + 0.03)
            wb = hw0 * 0.93
            wr = hw0 * d.get("tumble", 0.74)
            gsecs.append([Vector((-wb, y, zb)), Vector((wb, y, zb)), Vector((wr, y, zr)), Vector((-wr, y, zr))])
            rsecs.append([Vector((-wr * 1.01, y, zr - 0.005)), Vector((wr * 1.01, y, zr - 0.005)),
                          Vector((wr * 0.95, y, zr + 0.03)), Vector((-wr * 0.95, y, zr + 0.03))])
        # painted greenhouse shell: only pillars and roof are kept; window areas are open
        bm = bmesh.new()
        rows = [[bm.verts.new(p) for p in sec] for sec in gsecs]
        u_front, u_rear = cab[-2][0], cab[1][0]
        u_mid_b = (u0 + u1) / 2
        for i in range(M_):
            um = u0 + (u1 - u0) * (i + 0.5) / M_
            r0, r1 = rows[i], rows[i + 1]
            side_window = (u0 + 0.03 < um < u1 - 0.03) and abs(um - u_mid_b) > 0.025
            top_glass = um > u_front + 0.01 or um < u_rear - 0.01
            if not side_window:
                bm.faces.new((r0[1], r1[1], r1[2], r0[2]))
                bm.faces.new((r0[3], r1[3], r1[0], r0[0]))
            if not top_glass:
                bm.faces.new((r0[2], r1[2], r1[3], r0[3]))
        # thin painted window frames along the belt line
        o = new_obj("Cabin", bm, coll, ["Paint"]); o.parent = body
        def gpanel(ua, ub, kind):
            secs = []
            for i in range(9):
                u = ua + (ub - ua) * i / 8
                y = -L / 2 + u * L
                zb = interp(d["belt"], u) + 0.03; zr = max(interp(cab, u) - 0.035, zb + 0.02)
                wb = hw0 * 0.93; wr = hw0 * d.get("tumble", 0.74)
                if kind == "side":
                    for sd in (-1, 1): pass
                    secs.append((y, zb, zr, wb, wr))
                else:
                    secs.append((y, zb, zr, wb, wr))
            bm = bmesh.new()
            if kind == "side":
                for sd in (-1, 1):
                    rows = []
                    for y, zb, zr, wb, wr in secs:
                        n = Vector((sd * (zr - zb), 0, (wb - wr))).normalized() * 0.012
                        a = Vector((sd * wb, y, zb)) * 0.96 + Vector((sd * wr, y, zr)) * 0.04
                        b = Vector((sd * wr, y, zr)) * 0.96 + Vector((sd * wb, y, zb)) * 0.04
                        rows.append([a + n, b + n])
                    loft(bm, rows if sd < 0 else [r[::-1] for r in rows], close_ends=False)
            else:
                rows = []
                for y, zb, zr, wb, wr in secs:
                    rows.append([Vector((wr * 0.88, y, zr + 0.045)), Vector((-wr * 0.88, y, zr + 0.045))])
                loft(bm, rows, close_ends=False)
            return bm
        bm = gpanel(u0 + 0.025, u1 - 0.025, "side")
        g = new_obj("Glass", bm, coll, ["Glass"])
        # windscreen + rear screen over the sloped ends of the cabin
        for nm, ua, ub in (("GlassFront", cab[-2][0] + 0.01, u1 - 0.005), ("GlassRear", u0 + 0.005, cab[1][0] - 0.01)):
            if ub - ua > 0.02:
                o = new_obj(nm, gpanel(ua, ub, "top"), coll, ["Glass"])
    elif d.get("windscreen"):
        u = d["windscreen"]; y = -L / 2 + u * L; zb = interp(d["belt"], u)
        bm = bmesh.new(); box(bm, (0, y, zb + 0.18), (W * 0.75, 0.03, 0.34), 0)
        new_obj("Glass", bm, coll, ["Glass"])

    # lights
    bm = bmesh.new()
    zf = interp(d["belt"], 0.97) - 0.08
    for s in (-1, 1):
        box(bm, (s * hw0 * 0.55, L / 2 - 0.09, zf), (W * 0.18, 0.06, 0.08), 0)
    new_obj("Lights_Front", bm, coll, ["LightF"])
    bm = bmesh.new()
    zr_ = interp(d["belt"], 0.03) - 0.08
    for s in (-1, 1):
        box(bm, (s * hw0 * 0.55, -L / 2 + 0.07, zr_), (W * 0.2, 0.06, 0.07), 0)
    new_obj("Lights_Rear", bm, coll, ["LightR"])

    # interior: seats, dash, steering wheel
    seat_u = d.get("seat_u", 0.45)
    sy = -L / 2 + seat_u * L
    fz = d["zb"] + 0.1
    bm = bmesh.new()
    for s in (-1, 1):
        box(bm, (s * W * 0.2, sy, fz + 0.15), (0.45, 0.5, 0.15), 0)
        box(bm, (s * W * 0.2, sy - 0.25, fz + 0.45), (0.45, 0.12, 0.6), 0)
    box(bm, (0, sy + 0.85, fz + 0.5), (W * 0.85, 0.3, 0.2), 0)
    new_obj("Interior", bm, coll, ["Interior"])
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=16, radius1=0.18, radius2=0.18, depth=0.03)
    import mathutils
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(70), 3, "X"))
    sw = new_obj("SteeringWheel", bm, coll, ["Trim"])
    sw.location = (-W * 0.2, sy + 0.55, fz + 0.62)

    # wheels
    wr, tw = d["wr"], d.get("tw", 0.24)
    tx = hw0 - tw / 2 + d.get("poke", 0.02)
    yf = d["wb"] / 2 + d.get("wb_off", 0.0)
    yr = -d["wb"] / 2 + d.get("wb_off", 0.0)
    for nm, x, y in (("FL", -tx, yf), ("FR", tx, yf), ("RL", -tx, yr), ("RR", tx, yr)):
        wheel("Wheel_" + nm, coll, wr, tw, d.get("spokes", 5), (x, y, wr))
        disc("Brake_" + nm, coll, wr, (x * 0.86, y, wr))

    # simple box collision proxy (Godot -colonly)
    bm = bmesh.new()
    zb, zt = d["zb"] + 0.05, max(z for _, z in (d.get("cab") or d["belt"]))
    box(bm, (0, d.get("wb_off", 0) * 0, (zb + zt) / 2), (W * 0.95, L * 0.97, zt - zb), 0)
    col = new_obj("Collision-colonly", bm, coll, ["Trim"])
    col.display_type = "WIRE"; col.hide_render = True
    return coll

# ---------- vehicle definitions (u = 0 rear .. 1 front; z metres) ----------
V = {
 "car01_kestrel": dict(L=3.95, W=1.76, wr=0.31, wb=2.5, zb=0.2, taper=0.2,
    belt=[(0, 0.82), (0.15, 0.95), (0.6, 0.92), (0.9, 0.78), (1, 0.6)],
    cab=[(0.06, 0.98), (0.14, 1.4), (0.55, 1.45), (0.78, 1.0)], seat_u=0.4, spokes=5,
    extras=[((0, -1.92, 1.42), (1.2, 0.18, 0.04), 0)]),
 "car02_meridian": dict(L=4.75, W=1.82, wr=0.32, wb=2.8, zb=0.22,
    belt=[(0, 0.82), (0.12, 0.92), (0.3, 0.92), (0.75, 0.88), (0.92, 0.8), (1, 0.62)],
    cab=[(0.2, 0.93), (0.32, 1.42), (0.6, 1.45), (0.74, 0.9)], seat_u=0.45, spokes=6),
 "car03_ironhorse": dict(L=4.95, W=1.9, wr=0.34, wb=2.85, zb=0.22, k=0.25, taper=0.08,
    belt=[(0, 0.82), (0.08, 0.86), (0.35, 0.86), (0.6, 0.86), (0.95, 0.86), (1, 0.7)],
    cab=[(0.22, 0.87), (0.32, 1.28), (0.5, 1.3), (0.62, 0.86)], seat_u=0.4, spokes=5, tw=0.28,
    extras=[((0, 1.35, 0.92), (0.5, 0.7, 0.12), 1), ((0, -2.45, 0.92), (1.6, 0.12, 0.05), 0)]),
 "car04_arrow": dict(L=4.3, W=1.8, wr=0.33, wb=2.55, zb=0.18,
    belt=[(0, 0.78), (0.1, 0.84), (0.4, 0.82), (0.8, 0.72), (1, 0.52)],
    cab=[(0.12, 0.85), (0.3, 1.25), (0.5, 1.27), (0.68, 0.76)], seat_u=0.42, spokes=10),
 "car05_solstice": dict(L=4.85, W=1.92, wr=0.35, wb=2.9, zb=0.18, wb_off=0.05,
    belt=[(0, 0.8), (0.1, 0.88), (0.35, 0.86), (0.85, 0.74), (1, 0.55)],
    cab=[(0.1, 0.88), (0.28, 1.28), (0.45, 1.3), (0.6, 0.8)], seat_u=0.36, spokes=7, tumble=0.7),
 "car06_vortex": dict(L=4.5, W=1.98, wr=0.34, wb=2.65, zb=0.12, taper=0.25,
    belt=[(0, 0.82), (0.1, 0.9), (0.35, 0.88), (0.6, 0.7), (0.85, 0.6), (1, 0.38)],
    cab=[(0.32, 0.86), (0.45, 1.13), (0.62, 1.12), (0.82, 0.64)], seat_u=0.56, spokes=10, tumble=0.66, tw=0.28,
    extras=[((0, -2.05, 1.12), (1.8, 0.3, 0.04), 1), ((0.7, -2.05, 0.98), (0.04, 0.18, 0.3), 1), ((-0.7, -2.05, 0.98), (0.04, 0.18, 0.3), 1)]),
 "car07_dustrunner": dict(L=4.2, W=1.82, wr=0.33, wb=2.55, zb=0.3, taper=0.2,
    belt=[(0, 0.95), (0.15, 1.05), (0.6, 1.02), (0.9, 0.9), (1, 0.72)],
    cab=[(0.08, 1.06), (0.18, 1.5), (0.55, 1.52), (0.75, 1.05)], seat_u=0.42, spokes=6,
    extras=[((0, -2.0, 1.58), (1.6, 0.35, 0.05), 1), ((0, 2.1, 0.88), (0.9, 0.05, 0.18), 1), ((0, 0.4, 1.58), (0.3, 0.6, 0.1), 1)]),
 "car08_ridgeback": dict(L=4.7, W=1.95, wr=0.4, wb=2.8, zb=0.42, k=0.22, taper=0.1,
    belt=[(0, 1.18), (0.1, 1.22), (0.75, 1.2), (0.92, 1.1), (1, 0.95)],
    cab=[(0.03, 1.22), (0.06, 1.85), (0.62, 1.88), (0.78, 1.2)], seat_u=0.45, spokes=6, tw=0.3, tumble=0.86,
    extras=[((0, 0.0, 1.98), (1.5, 2.2, 0.06), 1), ((0, 2.38, 0.7), (1.6, 0.1, 0.25), 1)]),
 "car09_haulmark": dict(L=5.45, W=2.0, wr=0.4, wb=3.4, zb=0.45, k=0.22, taper=0.06,
    belt=[(0, 1.2), (0.5, 1.2), (0.85, 1.18), (1, 1.0)],
    cab=[(0.44, 1.2), (0.47, 1.92), (0.65, 1.95), (0.76, 1.2)], seat_u=0.6, spokes=6, tw=0.3, tumble=0.86,
    extras=[((0, -1.4, 1.19), (1.75, 2.4, 0.03), 1), ((0, 2.75, 0.75), (1.7, 0.1, 0.3), 2)]),
 "car10_breeze": dict(L=3.85, W=1.6, wr=0.36, wb=2.3, zb=0.28, taper=0.3, k=0.45,
    belt=[(0, 0.78), (0.2, 0.92), (0.5, 0.88), (0.8, 0.9), (1, 0.66)],
    windscreen=0.6, seat_u=0.42, spokes=16, tw=0.18, poke=0.1,
    extras=[((0, 1.94, 0.6), (0.4, 0.05, 0.35), 2)]),
 # traffic
 "tr01_compact": dict(L=3.6, W=1.65, wr=0.29, wb=2.35, zb=0.2,
    belt=[(0, 0.85), (0.6, 0.9), (0.9, 0.78), (1, 0.6)], cab=[(0.04, 0.95), (0.1, 1.45), (0.6, 1.48), (0.8, 0.9)], seat_u=0.45),
 "tr02_van": dict(L=4.9, W=1.95, wr=0.33, wb=3.0, zb=0.3, k=0.18, taper=0.08,
    belt=[(0, 1.1), (0.85, 1.1), (1, 0.85)], cab=[(0.02, 1.15), (0.03, 2.2), (0.76, 2.2), (0.9, 1.1)], seat_u=0.75, tumble=0.9),
 "tr03_lorry": dict(L=8.5, W=2.4, wr=0.5, wb=5.0, zb=0.6, k=0.12, taper=0.04,
    belt=[(0, 3.2), (0.72, 3.2), (0.74, 1.6), (1, 1.6)], cab=[(0.76, 1.6), (0.78, 2.9), (0.96, 2.9), (0.99, 1.6)], seat_u=0.86, tumble=0.95, tw=0.36, roof=True),
 "tr04_bus": dict(L=11.0, W=2.5, wr=0.5, wb=6.0, zb=0.4, k=0.12, taper=0.04,
    belt=[(0, 1.5), (1, 1.5)], cab=[(0.02, 1.5), (0.03, 2.9), (0.97, 2.9), (0.99, 1.5)], seat_u=0.9, tumble=0.97, tw=0.36),
 "tr05_tractor": dict(L=3.8, W=1.9, wr=0.75, wb=2.2, zb=0.6, k=0.2, taper=0.1, tw=0.45, poke=0.25,
    belt=[(0, 1.3), (0.35, 1.3), (0.4, 1.5), (1, 1.4)], cab=[(0.1, 1.5), (0.12, 2.6), (0.42, 2.6), (0.45, 1.5)], seat_u=0.3, tumble=0.9),
 "tr06_pickup": dict(L=5.2, W=1.95, wr=0.38, wb=3.2, zb=0.4, k=0.22, taper=0.06,
    belt=[(0, 1.12), (1, 1.1)], cab=[(0.45, 1.12), (0.48, 1.85), (0.68, 1.88), (0.78, 1.12)], seat_u=0.6, tumble=0.86,
    extras=[((0, -1.3, 1.11), (1.7, 2.3, 0.03), 1)]),
}

root = bpy.data.collections.get("FORZA_GODOT") or bpy.data.collections.new("FORZA_GODOT")
if root.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(root)
for nm in ("Cars", "Traffic"):
    c = bpy.data.collections.get(nm)
    if c:
        for o in list(c.all_objects): bpy.data.objects.remove(o)
        for ch in list(c.children_recursive): bpy.data.collections.remove(ch)
        bpy.data.collections.remove(c)
for o in list(bpy.data.objects):
    if o.name.split("_")[0][:3] in ("car", "tr0"): bpy.data.objects.remove(o)
for m in list(bpy.data.meshes):
    if m.users == 0: bpy.data.meshes.remove(m)
for c in list(bpy.data.collections):
    if c.name.split("_")[0][:3] in ("car", "tr0"): bpy.data.collections.remove(c)
cars = bpy.data.collections.new("Cars"); root.children.link(cars)
traf = bpy.data.collections.new("Traffic"); root.children.link(traf)
for o in ("Cube",):
    if o in bpy.data.objects: bpy.data.objects.remove(bpy.data.objects[o])

for i, (k, d) in enumerate(V.items()):
    c = build_vehicle(k, d, cars if k.startswith("car") else traf)
    off = Vector(((i % 8) * 7.0 - 24, (i // 8) * 14.0, 0))
    for o in c.objects:
        if o.parent is None: o.location += off
    # export: temporarily move to origin
    for o in c.objects:
        if o.parent is None: o.location -= off
    bpy.ops.object.select_all(action="DESELECT")
    for o in c.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, k + ".glb"), use_selection=True, export_format="GLB", export_apply=True)
    for o in c.objects:
        if o.parent is None: o.location += off
bpy.ops.wm.save_mainfile()
print("ok", len(V))
