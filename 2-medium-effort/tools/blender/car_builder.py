# Parametric car builder for the master .blend (run inside Blender via the MCP).
# Cars face +Y in Blender (-> -Z forward in glTF/Godot), Z up, 1 unit = 1 m.
# Usage inside Blender:  exec(open(PATH).read()); build_car(SPECS["hatch"])
import bpy, bmesh, math
from mathutils import Vector, Matrix

ROOT_COLL = "FORZA_GODOT"

def coll(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c

def root_colls():
    r = coll(ROOT_COLL)
    for n in ("Cars", "Traffic", "Props", "Settlements", "Roadside", "Nature", "Collision"):
        coll(n, r)
    return r

def mat(name, color, metallic=0.0, rough=0.5, emit=None, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emit is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emit, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 3.0
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = (*color, alpha)
    return m

def std_mats():
    return {
        "Paint": mat("Paint", (0.8, 0.1, 0.08), 0.4, 0.3),
        "Glass": mat("Glass", (0.05, 0.07, 0.09), 0.0, 0.05, alpha=0.45),
        "Trim": mat("Trim", (0.03, 0.03, 0.035), 0.0, 0.6),
        "Chrome": mat("Chrome", (0.9, 0.9, 0.92), 1.0, 0.12),
        "Tire": mat("Tire", (0.03, 0.03, 0.03), 0.0, 0.85),
        "Rim": mat("Rim", (0.7, 0.72, 0.75), 0.9, 0.25),
        "HeadLight": mat("HeadLight", (0.95, 0.95, 0.9), 0.0, 0.1, emit=(1.0, 0.97, 0.85)),
        "TailLight": mat("TailLight", (0.6, 0.02, 0.02), 0.0, 0.2, emit=(0.9, 0.02, 0.01)),
        "ReverseLight": mat("ReverseLight", (0.9, 0.9, 0.9), 0.0, 0.2),
        "Indicator": mat("Indicator", (1.0, 0.45, 0.0), 0.0, 0.2),
        "Interior": mat("Interior", (0.12, 0.11, 0.1), 0.0, 0.8),
        "Seat": mat("Seat", (0.25, 0.08, 0.05), 0.0, 0.7),
        "Disc": mat("Disc", (0.35, 0.35, 0.36), 0.8, 0.4),
        "Caliper": mat("Caliper", (0.8, 0.1, 0.05), 0.2, 0.4),
        "Grille": mat("Grille", (0.02, 0.02, 0.02), 0.3, 0.5),
        "Plate": mat("Plate", (0.92, 0.9, 0.75), 0.0, 0.5),
        "Wood": mat("Wood", (0.35, 0.2, 0.1), 0.0, 0.7),
    }

# ---------------------------------------------------------------- helpers
def interp(keys, u):
    """keys: list of (u, value) sorted. smooth (cosine) interpolation."""
    if u <= keys[0][0]:
        return keys[0][1]
    for (u0, v0), (u1, v1) in zip(keys, keys[1:]):
        if u <= u1:
            t = (u - u0) / max(1e-6, (u1 - u0))
            t = 0.5 - 0.5 * math.cos(math.pi * t)
            return v0 + (v1 - v0) * t
    return keys[-1][1]

def ring(y, zb, zt, hw, top_ratio, n_pts, expo, bot_ratio=0.96):
    pts = []
    zc = (zb + zt) * 0.5
    hz = max(0.002, (zt - zb) * 0.5)
    for i in range(n_pts):
        a = 2 * math.pi * i / n_pts
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2.0 / expo), c) * hw
        z = math.copysign(abs(s) ** (2.0 / expo), s)
        x *= (1.0 + (top_ratio - 1.0) * max(0.0, z)) * (1.0 + (bot_ratio - 1.0) * max(0.0, -z))
        pts.append(Vector((x, y, zc + z * hz)))
    return pts

def loft(name, rings, mats, coll_obj):
    bm = bmesh.new()
    vrows = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vrows, vrows[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(vrows[0])))
    bm.faces.new(vrows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll_obj.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    return ob

def box(name, coll_obj, m, center, size, bevel=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll_obj.objects.link(ob)
    me.materials.append(m)
    if bevel > 0:
        md = ob.modifiers.new("bev", "BEVEL")
        md.width = bevel
        md.segments = 2
    return ob

def cyl(name, coll_obj, m, center, radius, depth, axis="X", verts=20, cap=True):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, segments=verts, radius1=radius, radius2=radius, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(center))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll_obj.objects.link(ob)
    me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    return ob

def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in objs:
        for md in list(o.modifiers):
            ctx = {"object": o}
            with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
                bpy.ops.object.modifier_apply(modifier=md.name)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs, object=objs[0]):
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]

def set_origin(ob, point):
    point = Vector(point)
    ob.data.transform(Matrix.Translation(-point + ob.location * 0))
    ob.location = point

def boolean_diff(target, cutter):
    md = target.modifiers.new("cut", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.object = cutter
    try:
        md.solver = "EXACT"
    except Exception:
        pass
    with bpy.context.temp_override(object=target, active_object=target, selected_objects=[target]):
        bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

def assign_by(ob, mat_index, pred):
    me = ob.data
    for p in me.polygons:
        c = p.center
        if pred(c, p.normal):
            p.material_index = mat_index

# ---------------------------------------------------------------- wheel
def build_wheel(name, cobj, M, r, w, side, style):
    """Wheel centred on origin, axis X. side=+1 right (outer face +X), -1 left."""
    parts = []
    tire = cyl(name + "_tire", cobj, M["Tire"], (0, 0, 0), r, w, "X", 28)
    bev = tire.modifiers.new("bev", "BEVEL")
    bev.width = min(0.05, w * 0.25)
    bev.segments = 3
    bev.limit_method = "ANGLE"
    parts.append(tire)
    rim_r = r * (0.62 if style != "offroad" else 0.55)
    rim = cyl(name + "_rim", cobj, M["Rim"], (side * (w * 0.5 + 0.004), 0, 0), rim_r, 0.012, "X", 24)
    parts.append(rim)
    hub = cyl(name + "_hub", cobj, M["Chrome"], (side * (w * 0.5 + 0.02), 0, 0), rim_r * 0.22, 0.04, "X", 12)
    parts.append(hub)
    spokes = {"sport": 5, "classic": 12, "offroad": 6, "multi": 10, "steel": 0}.get(style, 5)
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        sp = box(name + "_sp%d" % i, cobj, M["Rim"], (0, 0, 0), (0.025, rim_r * 0.85, 0.035 if style != "classic" else 0.012))
        sp.data.transform(Matrix.Translation((0, rim_r * 0.45, 0)))
        sp.data.transform(Matrix.Rotation(a, 4, "X"))
        sp.data.transform(Matrix.Translation((side * (w * 0.5 + 0.012), 0, 0)))
        parts.append(sp)
    if style == "steel":
        cap = cyl(name + "_cap", cobj, M["Chrome"], (side * (w * 0.5 + 0.015), 0, 0), rim_r * 0.75, 0.02, "X", 20)
        parts.append(cap)
    return join(parts, name)

# ---------------------------------------------------------------- car
def build_car(S, target_coll="Cars"):
    root_colls()
    M = std_mats()
    key = S["key"]
    parent = coll(target_coll, bpy.data.collections[ROOT_COLL])
    cname = ("CAR_" if target_coll == "Cars" else "TRF_") + key
    old = bpy.data.collections.get(cname)
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    cobj = coll(cname, parent)

    L, W = S["L"], S["W"]
    y0 = -L * 0.5
    U = lambda u: y0 + u * L
    ride = S["ride"]
    nseg = 48
    npts = 28
    belt = S["belt"]
    expo = S.get("expo", 3.2)
    zt_keys = S.get("zt_keys") or [
        (0.0, S["deck"] - 0.10), (0.035, S["deck"]), (S["rw"], belt + S.get("deck_rise", 0.0)),
        (S["ws"], belt), (0.93, S["hood"]), (1.0, S["hood"] - S["nose"])]
    zb_keys = [(0.0, ride + 0.12), (0.06, ride), (0.94, ride), (1.0, ride + 0.10)]
    hw_keys = [(0.0, W * 0.44), (0.07, W * 0.5), (0.5, W * 0.5 * S.get("waist", 1.0)), (0.93, W * 0.49), (1.0, W * S.get("nose_w", 0.43))]
    rings = []
    for i in range(nseg + 1):
        u = i / nseg
        rings.append(ring(U(u), interp(zb_keys, u), interp(zt_keys, u), interp(hw_keys, u), S.get("top_ratio", 0.93), npts, expo))
    body = loft("Body", rings, [M["Paint"], M["Trim"], M["Grille"]], cobj)
    # lower sill / bumpers trim: faces near the bottom
    assign_by(body, 1, lambda c, n: c.z < ride + 0.07)

    # wheel arches
    ar, af = S["axle_r"], S["axle_f"]
    wr, ww = S["wheel_r"], S["wheel_w"]
    for uy in (ar, af):
        cut = cyl("cut", cobj, M["Trim"], (0, U(uy), wr), wr + 0.055, W + 0.5, "X", 32)
        boolean_diff(body, cut)

    parts_body = [body]
    # greenhouse
    glass_obj = None
    if S.get("roof", True) or S.get("windshield_only"):
        gr = []
        rw, ws = S["rw"], S["ws"]
        rr, rf = S["roof_r"], S["roof_f"]
        roof = S["roof_h"]
        zt_g = [(rw, belt + 0.01), (rr, roof), (rf, roof), (ws, belt + 0.01)]
        gseg = 32
        if S.get("windshield_only"):
            # roadster: only a raked windscreen frame
            pass
        else:
            for i in range(gseg + 1):
                u = rw + (ws - rw) * i / gseg
                gr.append(ring(U(u), belt - 0.06, interp(zt_g, u), W * 0.5 * S.get("tumble", 0.86), S.get("g_top", 0.82), 24, S.get("g_expo", 3.5), 1.0))
            gh = loft("Greenhouse", gr, [M["Glass"], M["Paint"], M["Trim"]], cobj)
            ymid = U((rr + rf) * 0.5)
            pill = S.get("pillars", [0.5])
            def gpred(c, n, roof=roof):
                return c.z > roof - 0.05 and n.z > 0.6
            assign_by(gh, 1, gpred)
            # pillars (trim strips across the side glass)
            for pu in pill:
                py = U(rr + (rf - rr) * pu)
                assign_by(gh, 2, lambda c, n, py=py: abs(c.y - py) < 0.05 and abs(n.z) < 0.6)
            # lower greenhouse band below beltline in paint
            assign_by(gh, 1, lambda c, n: c.z < belt + 0.015)
            # black window surround just above the beltline and along the roof edge
            assign_by(gh, 2, lambda c, n: belt + 0.015 <= c.z < belt + 0.05 and n.z < 0.7)
            assign_by(gh, 2, lambda c, n, roof=roof: roof - 0.09 < c.z <= roof - 0.05 and n.z < 0.6 and c.z > belt + 0.1)
            # split glass faces into Glass object
            bpy.ops.object.select_all(action="DESELECT")
            me = gh.data
            bm = bmesh.new(); bm.from_mesh(me)
            gl_faces = [f for f in bm.faces if f.material_index == 0]
            rest = [f for f in bm.faces if f.material_index != 0]
            bm2 = bm.copy()
            bmesh.ops.delete(bm, geom=gl_faces, context="FACES")
            bm.to_mesh(me); bm.free()
            bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if f.material_index != 0], context="FACES")
            gme = bpy.data.meshes.new("Glass")
            bm2.to_mesh(gme); bm2.free()
            glass_obj = bpy.data.objects.new("Glass", gme)
            cobj.objects.link(glass_obj)
            gme.materials.clear(); gme.materials.append(M["Glass"])
            for p in gme.polygons:
                p.material_index = 0
                p.use_smooth = True
            parts_body.append(gh)
    if S.get("windshield_only"):
        ws = S["ws"]
        h = S.get("screen_h", 0.32)
        frame = box("screen", cobj, M["Glass"], (0, U(ws) - 0.05, belt + h * 0.5), (W * 0.42, 0.02, h))
        frame.data.transform(Matrix.Translation((0, -U(ws) + 0.05, -belt)))
        frame.data.transform(Matrix.Rotation(-0.45, 4, "X"))
        frame.data.transform(Matrix.Translation((0, U(ws) - 0.05, belt)))
        glass_obj = frame
        glass_obj.name = "Glass"
        fr = box("screenframe", cobj, M["Chrome"], (0, U(ws) - 0.05, belt + h), (W * 0.43, 0.03, 0.03))
        fr.data.transform(Matrix.Translation((0, -U(ws) + 0.05, -belt)))
        fr.data.transform(Matrix.Rotation(-0.45, 4, "X"))
        fr.data.transform(Matrix.Translation((0, U(ws) - 0.05, belt)))
        parts_body.append(fr)

    # details --------------------------------------------------------
    front_y = U(1.0)
    rear_y = U(0.0)
    hood_front = S["hood"] - S["nose"]
    # grille
    gw = W * S.get("grille_w", 0.5)
    gz = ride + (hood_front - ride) * 0.45
    gh_ = (hood_front - ride) * S.get("grille_h", 0.45)
    parts_body.append(box("grille", cobj, M["Grille"], (0, front_y - 0.01, gz), (gw, 0.06, gh_)))
    # bumpers (trim)
    parts_body.append(box("bumper_f", cobj, M["Trim"] if not S.get("chrome_bumpers") else M["Chrome"], (0, front_y + 0.02, ride + 0.14), (W * 0.86, 0.1, 0.12), 0.03))
    parts_body.append(box("bumper_r", cobj, M["Trim"] if not S.get("chrome_bumpers") else M["Chrome"], (0, rear_y - 0.02, ride + 0.16), (W * 0.84, 0.1, 0.12), 0.03))
    # plates
    parts_body.append(box("plate_r", cobj, M["Plate"], (0, rear_y - 0.08, ride + 0.3), (0.46, 0.01, 0.11)))
    # mirrors
    if S.get("roof", True):
        my = U(S["ws"]) - 0.12
        for sx in (-1, 1):
            parts_body.append(box("mirror", cobj, M["Paint"], (sx * (W * 0.5 + 0.06), my, belt + 0.1), (0.14, 0.08, 0.08), 0.02))
    # exhausts
    for ex in S.get("exhaust", [0.25]):
        parts_body.append(cyl("exh", cobj, M["Chrome"], (ex * W, rear_y - 0.04, ride + 0.08), 0.045, 0.2, "Y", 12))
        if ex != 0:
            pass
    # hood scoop / spoiler / extras
    if S.get("scoop"):
        parts_body.append(box("scoop", cobj, M["Paint"], (0, U(0.8), S["hood"] + 0.04), (0.5, 0.6, 0.1), 0.04))
        parts_body.append(box("scoop_in", cobj, M["Grille"], (0, U(0.8) + 0.3, S["hood"] + 0.05), (0.42, 0.02, 0.06)))
    if S.get("wing"):
        wz = S["deck"] + S["wing"]
        parts_body.append(box("wing", cobj, M["Trim"] if S.get("wing_trim", True) else M["Paint"], (0, U(0.04), wz), (W * 0.92, 0.32, 0.04), 0.01))
        for sx in (-0.33, 0.33):
            parts_body.append(box("wing_post", cobj, M["Trim"], (sx * W, U(0.06), (wz + S["deck"]) * 0.5), (0.05, 0.12, S["wing"])))
    if S.get("lip"):
        parts_body.append(box("lip", cobj, M["Trim"], (0, U(0.012), S["deck"] + 0.02), (W * 0.8, 0.08, 0.04)))
    if S.get("splitter"):
        parts_body.append(box("splitter", cobj, M["Trim"], (0, front_y + 0.04, ride + 0.03), (W * 0.9, 0.2, 0.025)))
    if S.get("side_intake"):
        for sx in (-1, 1):
            parts_body.append(box("intake", cobj, M["Grille"], (sx * W * 0.495, U(0.33), belt - 0.15), (0.03, 0.5, 0.18)))
    if S.get("roof_rack"):
        rz = S["roof_h"] + 0.06
        for sx in (-1, 1):
            parts_body.append(box("rack", cobj, M["Trim"], (sx * W * 0.36, U((S["roof_r"] + S["roof_f"]) * 0.5), rz), (0.04, (S["roof_f"] - S["roof_r"]) * L * 0.9, 0.04)))
        for t in (0.2, 0.5, 0.8):
            parts_body.append(box("rackx", cobj, M["Trim"], (0, U(S["roof_r"] + (S["roof_f"] - S["roof_r"]) * t), rz + 0.02), (W * 0.74, 0.04, 0.03)))
    if S.get("bullbar"):
        parts_body.append(box("bull_h", cobj, M["Chrome"], (0, front_y + 0.12, hood_front - 0.05), (W * 0.7, 0.05, 0.05)))
        for sx in (-0.3, 0.3):
            parts_body.append(box("bull_v", cobj, M["Chrome"], (sx * W, front_y + 0.12, (hood_front + ride) * 0.5), (0.05, 0.05, hood_front - ride)))
    if S.get("spare"):
        parts_body.append(cyl("spare", cobj, M["Tire"], (0, rear_y - 0.12, ride + 0.55), wr * 0.95, wr * 0.6, "Y", 24))
    if S.get("mudflaps"):
        for sx in (-1, 1):
            for uy in (ar, af):
                parts_body.append(box("flap", cobj, M["Trim"], (sx * (W * 0.5 - ww * 0.5), U(uy) - wr - 0.08, ride + 0.05), (ww, 0.01, 0.2)))
    if S.get("bed"):
        # pickup bed: dark tub inset in the rear deck
        b0, b1 = S["bed"]
        parts_body.append(box("bed", cobj, M["Trim"], (0, U((b0 + b1) * 0.5), S["deck"] - 0.02), (W * 0.84, (b1 - b0) * L, 0.06)))
        parts_body.append(box("bed_rail", cobj, M["Trim"], (W * 0.44, U((b0 + b1) * 0.5), S["deck"] + 0.02), (0.06, (b1 - b0) * L, 0.05)))
        parts_body.append(box("bed_rail2", cobj, M["Trim"], (-W * 0.44, U((b0 + b1) * 0.5), S["deck"] + 0.02), (0.06, (b1 - b0) * L, 0.05)))
    if S.get("stripes_body"):
        pass
    if S.get("fender_flares"):
        for sx in (-1, 1):
            for uy in (ar, af):
                fl = cyl("flare", cobj, M["Trim"], (sx * (W * 0.5 + 0.005), U(uy), wr), wr + 0.1, 0.08, "X", 24)
                cut = cyl("flc", cobj, M["Trim"], (sx * (W * 0.5 + 0.005), U(uy), wr), wr + 0.045, 0.2, "X", 24)
                boolean_diff(fl, cut)
                # remove lower half
                bm = bmesh.new(); bm.from_mesh(fl.data)
                bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < wr - 0.02], context="VERTS")
                bm.to_mesh(fl.data); bm.free()
                parts_body.append(fl)
    body = join(parts_body, "Body")

    # lights ----------------------------------------------------------
    hl_parts = []
    hl_y = front_y - S.get("hl_inset", 0.03)
    hl_z = S.get("hl_z", hood_front - 0.07)
    for sx in (-1, 1):
        if S.get("round_lights"):
            hl_parts.append(cyl("hl", cobj, M["HeadLight"], (sx * W * 0.34, hl_y + 0.02, hl_z), 0.085, 0.06, "Y", 20))
        else:
            hl_parts.append(box("hl", cobj, M["HeadLight"], (sx * W * 0.36, hl_y, hl_z), (W * S.get("hl_w", 0.2), 0.08, S.get("hl_h", 0.07)), 0.01))
    join(hl_parts, "Lights_Head")
    tl_parts = []
    tl_z = S.get("tl_z", S["deck"] - 0.1)
    for sx in (-1, 1):
        if S.get("round_tail"):
            tl_parts.append(cyl("tl", cobj, M["TailLight"], (sx * W * 0.36, rear_y + 0.0, tl_z), 0.06, 0.06, "Y", 16))
        else:
            tl_parts.append(box("tl", cobj, M["TailLight"], (sx * W * 0.36, rear_y + 0.01, tl_z), (W * S.get("tl_w", 0.2), 0.06, 0.07), 0.01))
    if S.get("tl_bar"):
        tl_parts.append(box("tlbar", cobj, M["TailLight"], (0, rear_y + 0.01, tl_z), (W * 0.5, 0.05, 0.025)))
    join(tl_parts, "Lights_Tail")
    rv = [box("rev", cobj, M["ReverseLight"], (sx * W * 0.2, rear_y - 0.005, tl_z - 0.08), (0.08, 0.04, 0.04)) for sx in (-1, 1)]
    join(rv, "Lights_Reverse")

    # interior --------------------------------------------------------
    ip = []
    seat_y = U(S.get("seat_u", (S["ws"] + S["rw"]) * 0.5 - 0.02))
    floor_z = ride + 0.12
    for sx in (-0.22, 0.22):
        ip.append(box("seat", cobj, M["Seat"], (sx * W, seat_y, floor_z + 0.18), (0.42, 0.45, 0.12), 0.03))
        ip.append(box("seatb", cobj, M["Seat"], (sx * W, seat_y - 0.24, floor_z + 0.48), (0.42, 0.1, 0.55), 0.03))
    dash_y = U(S["ws"]) - 0.05
    ip.append(box("dash", cobj, M["Interior"], (0, dash_y - 0.15, belt - 0.05), (W * 0.84, 0.35, 0.18), 0.03))
    ip.append(box("tub", cobj, M["Interior"], (0, (dash_y + seat_y) * 0.5 - 0.2, floor_z), (W * 0.84, abs(dash_y - seat_y) + 1.0, 0.05)))
    ip.append(box("console", cobj, M["Interior"], (0, seat_y + 0.25, floor_z + 0.15), (0.18, 0.7, 0.22)))
    join(ip, "Interior")
    sw_c = Vector((-W * 0.22, dash_y - 0.42, belt + 0.02))
    swp = []
    tor = bpy.data.meshes.new("SteeringWheel")
    bm = bmesh.new()
    seg, rs = 24, 8
    R, rr_ = 0.18, 0.018
    verts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(rs):
            b = 2 * math.pi * j / rs
            p = Vector(((R + rr_ * math.cos(b)) * math.cos(a), rr_ * math.sin(b), (R + rr_ * math.cos(b)) * math.sin(a)))
            row.append(bm.verts.new(p))
        verts.append(row)
    for i in range(seg):
        for j in range(rs):
            bm.faces.new((verts[i][j], verts[(i + 1) % seg][j], verts[(i + 1) % seg][(j + 1) % rs], verts[i][(j + 1) % rs]))
    bm.to_mesh(tor); bm.free()
    swo = bpy.data.objects.new("SteeringWheel", tor)
    cobj.objects.link(swo)
    tor.materials.append(M["Trim"])
    spk = box("swspoke", cobj, M["Trim"], (0, 0, 0), (0.34, 0.02, 0.04))
    hubs = cyl("swhub", cobj, M["Interior"], (0, 0, 0), 0.05, 0.05, "Y", 12)
    swo = join([swo, spk, hubs], "SteeringWheel")
    swo.rotation_euler = (math.radians(-20), 0, 0)
    swo.location = sw_c
    bpy.context.view_layer.update()
    with bpy.context.temp_override(object=swo, active_object=swo, selected_objects=[swo], selected_editable_objects=[swo]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    # wheels + brakes -------------------------------------------------
    tx = W * 0.5 - ww * 0.5 - S.get("wheel_in", 0.03)
    for tag, uy in (("FL", af), ("FR", af), ("RL", ar), ("RR", ar)):
        side = -1 if tag[1] == "L" else 1
        wo = build_wheel("Wheel_" + tag, cobj, M, wr, ww, side, S.get("rim", "sport"))
        wo.location = (side * tx, U(uy), wr)
        disc = cyl("disc", cobj, M["Disc"], (side * 0.01, 0, 0), wr * 0.48, 0.025, "X", 20)
        cal = box("cal", cobj, M["Caliper"], (side * 0.02, -wr * 0.35, wr * 0.15), (0.05, 0.1, 0.16))
        bo = join([disc, cal], "Brake_" + tag)
        bo.location = (side * (tx - ww * 0.2), U(uy), wr)
    return cobj

def export_glb(cobj, path):
    bpy.ops.object.select_all(action="DESELECT")
    objs = list(cobj.all_objects)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    return path

def only_show(cname):
    for c in bpy.data.collections:
        if c.name.startswith("CAR_") or c.name.startswith("TRF_") or c.name.startswith("KIT_"):
            lc = find_layer_coll(bpy.context.view_layer.layer_collection, c.name)
            if lc:
                lc.hide_viewport = (c.name != cname)

def find_layer_coll(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        r = find_layer_coll(ch, name)
        if r:
            return r
    return None

def shift_coll(cobj, dx, dy=0.0):
    for o in cobj.objects:
        o.location.x += dx
        o.location.y += dy

def build_all(specs, target="Cars"):
    out = []
    for k, s in specs.items():
        out.append(build_car(s, target))
    return out

def rebuild_and_export(specs, target, out_dir):
    res = []
    for k, s in specs.items():
        c = build_car(s, target)
        p = export_glb(c, out_dir + "\\" + k + ".glb")
        res.append((k, len(c.objects), sum(len(o.data.polygons) for o in c.objects if o.type == "MESH")))
    return res
