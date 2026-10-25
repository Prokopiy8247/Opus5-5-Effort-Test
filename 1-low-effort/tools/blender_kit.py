# Executed inside the project's Blender instance (port 9877) via tools/bl.py.
# Builds the road-furniture kit, nature set and building kit, then exports three GLBs.
# Convention: Blender +Y = Godot forward (-Z). Origins at ground level unless noted.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

PROJ = os.path.dirname(bpy.data.filepath)
OUT = os.path.join(PROJ, "assets", "imported", "props")
os.makedirs(OUT, exist_ok=True)

def mat(name, col, metal=0.0, rough=0.7, emit=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = False
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 3.0
    return m

MATS = {
    "Steel": mat("K_Steel", (0.62, 0.64, 0.66), 0.9, 0.35), "White": mat("K_White", (0.9, 0.9, 0.88)),
    "Black": mat("K_Black", (0.03, 0.03, 0.03)), "Concrete": mat("K_Concrete", (0.52, 0.5, 0.47), 0, 0.9),
    "Stone": mat("K_Stone", (0.45, 0.42, 0.38), 0, 0.95), "Lamp": mat("K_Lamp", (1, 0.9, 0.7), 0, 0.3, (1, 0.85, 0.55)),
    "Red": mat("K_Red", (0.75, 0.08, 0.06)), "Yellow": mat("K_Yellow", (0.95, 0.75, 0.05)), "Pink": mat("K_Pink", (1, 0.25, 0.6), 0, 0.4, (1, 0.2, 0.55)),
    "Wood": mat("K_Wood", (0.38, 0.24, 0.13)), "Bark": mat("K_Bark", (0.25, 0.17, 0.1)), "Leaf": mat("K_Leaf", (0.17, 0.33, 0.1)),
    "Pine": mat("K_Pine", (0.08, 0.22, 0.1)), "Palm": mat("K_PalmLeaf", (0.2, 0.42, 0.12)), "Cactus": mat("K_Cactus", (0.22, 0.42, 0.2)),
    "Rock": mat("K_Rock", (0.42, 0.39, 0.36), 0, 0.95), "Grass": mat("K_Grass", (0.3, 0.45, 0.15)), "Bush": mat("K_Bush", (0.18, 0.3, 0.1)),
    "Plaster": mat("K_Plaster", (0.88, 0.84, 0.74)), "Plaster2": mat("K_Plaster2", (0.85, 0.7, 0.55)), "Plaster3": mat("K_Plaster3", (0.7, 0.78, 0.8)),
    "Roof": mat("K_Roof", (0.55, 0.2, 0.12)), "Roof2": mat("K_Roof2", (0.25, 0.27, 0.3)), "Window": mat("K_Window", (0.12, 0.18, 0.25), 0.5, 0.1),
    "BarnRed": mat("K_BarnRed", (0.55, 0.1, 0.07)), "Blue": mat("K_Blue", (0.1, 0.3, 0.7)), "Green": mat("K_Green", (0.1, 0.5, 0.25)),
}

def new_bm():
    return bmesh.new()

def tag(bm, faces, mi):
    for f in faces: f.material_index = mi

def box(bm, c, s, mi=0, rot_z=0.0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Rotation(rot_z, 4, "Z")
    for v in r["verts"]:
        v.co = m @ Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2])) + Vector(c)
    tag(bm, {f for v in r["verts"] for f in v.link_faces}, mi)

def cyl(bm, c, r1, r2, h, seg=12, mi=0, axis="Z"):
    r = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r1, radius2=r2, depth=h)
    rot = Matrix.Identity(4)
    if axis == "X": rot = Matrix.Rotation(math.pi / 2, 4, "Y")
    if axis == "Y": rot = Matrix.Rotation(math.pi / 2, 4, "X")
    for v in r["verts"]: v.co = rot @ v.co + Vector(c)
    tag(bm, {f for v in r["verts"] for f in v.link_faces}, mi)

def ico(bm, c, r, sub=1, mi=0, sc=(1, 1, 1), jitter=0.0, seed=1):
    import random
    rnd = random.Random(seed)
    res = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    for v in res["verts"]:
        j = 1.0 + rnd.uniform(-jitter, jitter)
        v.co = Vector((v.co.x * sc[0] * j, v.co.y * sc[1] * j, v.co.z * sc[2] * j)) + Vector(c)
    tag(bm, {f for v in res["verts"] for f in v.link_faces}, mi)

def prism_roof(bm, c, w, d, h, mi, overhang=0.4):
    # gable roof ridge along Y
    x, y, z = c
    hw, hd = w / 2 + overhang, d / 2 + overhang
    vs = [bm.verts.new(p) for p in [(x - hw, y - hd, z), (x + hw, y - hd, z), (x + hw, y + hd, z), (x - hw, y + hd, z), (x, y - hd, z + h), (x, y + hd, z + h)]]
    fs = [bm.faces.new((vs[0], vs[1], vs[4])), bm.faces.new((vs[2], vs[3], vs[5])), bm.faces.new((vs[1], vs[2], vs[5], vs[4])), bm.faces.new((vs[3], vs[0], vs[4], vs[5])), bm.faces.new((vs[3], vs[2], vs[1], vs[0]))]
    tag(bm, fs, mi)

def finish(name, bm, mats, coll):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for m in mats: me.materials.append(MATS[m])
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    return o

def windows(bm, w, d, floors, mi_win, z0=0.9, fh=2.8):
    for f in range(floors):
        z = z0 + f * fh + 0.6
        for k in range(max(1, int(w / 2.5))):
            x = -w / 2 + (k + 0.5) * w / max(1, int(w / 2.5))
            box(bm, (x, d / 2 + 0.03, z), (0.9, 0.08, 1.1), mi_win)
            box(bm, (x, -d / 2 - 0.03, z), (0.9, 0.08, 1.1), mi_win)

# ------------------------------------------------------------------ build
root = bpy.data.collections.get("FORZA_GODOT")
def fresh(name):
    c = bpy.data.collections.get(name)
    if c:
        for o in list(c.objects): bpy.data.objects.remove(o)
    else:
        c = bpy.data.collections.new(name); root.children.link(c)
    return c

road = fresh("Roadside")
nature = fresh("Nature")
bld = fresh("Settlements")
for m in list(bpy.data.meshes):
    if m.users == 0: bpy.data.meshes.remove(m)
nature = fresh("Nature")
bld = fresh("Settlements")

# --- road furniture
bm = new_bm()  # W-beam guard rail, 4 m along Y, centred; posts down to ground
box(bm, (0, 0, 0.0), (0.06, 4.02, 0.32), 0)
box(bm, (0.04, 0, 0.0), (0.03, 4.02, 0.12), 0)
for y in (-1.0, 1.0): box(bm, (-0.08, y, -0.35), (0.1, 0.1, 0.75), 0)
finish("GuardRail", bm, ["Steel"], road)

bm = new_bm()  # delineator post with reflector, 1 m tall centred
box(bm, (0, 0, 0), (0.1, 0.1, 1.0), 0)
box(bm, (0, -0.06, 0.32), (0.07, 0.02, 0.18), 1)
box(bm, (0, 0, 0.12), (0.11, 0.11, 0.2), 2)
finish("RoadPost", bm, ["White", "Lamp", "Black"], road)

bm = new_bm()  # bridge pillar 1 m tall (scaled), cap at top
box(bm, (0, 0, 0), (1.4, 1.4, 1.0), 0)
finish("BridgePillar", bm, ["Concrete"], road)

bm = new_bm()  # street lamp, origin at base, arm reaching towards -X (road side)
cyl(bm, (0, 0, 3.5), 0.11, 0.08, 7.0, 10, 0)
box(bm, (-0.9, 0, 6.95), (1.9, 0.12, 0.1), 0)
box(bm, (-1.75, 0, 6.82), (0.55, 0.3, 0.12), 1)
finish("StreetLamp", bm, ["Steel", "Lamp"], road)

bm = new_bm()  # tunnel portal: frame around an arched opening 14 m wide / 6.6 m high
seg = 14
outer_w, outer_h, depth = 9.5, 9.0, 1.5
verts_front, verts_back = [], []
for side, yy in ((0, -depth / 2), (1, depth / 2)):
    pts = []
    for k in range(seg + 1):
        a = math.pi * k / seg
        pts.append(bm.verts.new((math.cos(a) * 7.0, yy, -0.5 + math.sin(a) * 6.6)))
    outer = [bm.verts.new((9.5, yy, -0.5)), bm.verts.new((9.5, yy, outer_h)), bm.verts.new((-9.5, yy, outer_h)), bm.verts.new((-9.5, yy, -0.5))]
    (verts_front if side == 0 else verts_back).append((pts, outer))
for (pts, outer) in verts_front + verts_back:
    # fan between arch and outer rectangle
    n = len(pts)
    for k in range(n - 1):
        corner = outer[1] if pts[k].co.x > 0 else outer[2]
        try: bm.faces.new((pts[k], pts[k + 1], corner))
        except ValueError: pass
    try:
        bm.faces.new((outer[0], outer[1], pts[0]))
        bm.faces.new((pts[-1], outer[2], outer[3]))
    except ValueError: pass
    mid = min(range(n), key=lambda i: abs(pts[i].co.x))
    try: bm.faces.new((outer[1], outer[2], pts[mid]))
    except ValueError: pass
# inner arch soffit
fp, bp = verts_front[0][0], verts_back[0][0]
for k in range(len(fp) - 1):
    bm.faces.new((fp[k], bp[k], bp[k + 1], fp[k + 1]))
box(bm, (0, -depth / 2 - 0.15, outer_h + 0.2), (19.4, 0.4, 0.4), 1)
finish("TunnelPortal", bm, ["Concrete", "Stone"], road)

bm = new_bm()  # tunnel ceiling light strip, centred, along Y
box(bm, (0, 0, 0), (0.35, 1.2, 0.1), 0)
finish("TunnelLight", bm, ["Lamp"], road)

bm = new_bm()  # event gate: 12 m wide arch, origin at road level
for x in (-6.0, 6.0): box(bm, (x, 0, 3.0), (0.5, 0.5, 6.0), 1)
box(bm, (0, 0, 6.1), (12.5, 0.6, 1.2), 0)
box(bm, (0, -0.32, 6.1), (11.5, 0.05, 0.8), 1)
finish("EventGate", bm, ["Pink", "Black"], road)

bm = new_bm()  # jump ramp 6 x 14 x 0.6 centred, hazard stripes on the lip
box(bm, (0, 0, 0), (6.0, 14.0, 0.6), 0)
for k in range(6):
    box(bm, (-2.5 + k * 1.0, 6.95, 0.0), (0.5, 0.12, 0.62), 1 if k % 2 == 0 else 2)
finish("JumpRamp", bm, ["Concrete", "Yellow", "Black"], road)

bm = new_bm()  # danger sign: triangle on a post
cyl(bm, (0, 0, 1.2), 0.05, 0.05, 2.4, 8, 0)
v = [bm.verts.new(p) for p in [(-0.8, -0.06, 1.9), (0.8, -0.06, 1.9), (0, -0.06, 3.2)]]
tag(bm, [bm.faces.new(v)], 1)
v = [bm.verts.new(p) for p in [(-0.55, -0.08, 2.05), (0.55, -0.08, 2.05), (0, -0.08, 2.95)]]
tag(bm, [bm.faces.new(v)], 2)
finish("DangerSign", bm, ["Steel", "Red", "Yellow"], road)

for nm, col in (("SignVillage", "Yellow"), ("SignGas", "Blue")):
    bm = new_bm()
    for x in (-0.8, 0.8): cyl(bm, (x, 0, 1.2), 0.05, 0.05, 2.4, 8, 0)
    box(bm, (0, -0.06, 2.1), (2.2, 0.06, 0.9), 1)
    box(bm, (0, -0.1, 2.1), (1.8, 0.02, 0.5), 2)
    finish(nm, bm, ["Steel", col, "White"], road)

bm = new_bm()  # wooden fence section 4 m along Y
for y in (-2.0, 0.0, 2.0): box(bm, (0, y, 0.6), (0.12, 0.12, 1.2), 0)
for z in (0.45, 0.95): box(bm, (0, 0, z), (0.06, 4.1, 0.12), 0)
finish("Fence", bm, ["Wood"], road)

# --- nature
bm = new_bm()  # pine: trunk + 4 stacked cones
cyl(bm, (0, 0, 1.5), 0.25, 0.18, 3.0, 8, 0)
for k, (z, r) in enumerate([(3.2, 2.6), (5.0, 2.1), (6.7, 1.6), (8.3, 1.0)]):
    cyl(bm, (0, 0, z), r, 0.15, 2.8, 9, 1)
finish("TreePine", bm, ["Bark", "Pine"], nature)

bm = new_bm()  # broadleaf: trunk + lumpy crown blobs
cyl(bm, (0, 0, 1.6), 0.32, 0.22, 3.2, 8, 0)
for k, (c, r) in enumerate([((0, 0, 4.6), 2.6), ((1.3, 0.4, 4.0), 1.8), ((-1.2, -0.5, 4.2), 1.9), ((0.2, 1.1, 5.4), 1.7), ((-0.3, -1.0, 5.6), 1.5)]):
    ico(bm, c, r, 1, 1, (1, 1, 0.85), 0.12, k)
finish("TreeOak", bm, ["Bark", "Leaf"], nature)

bm = new_bm()  # palm: leaning trunk segments + fronds
for k in range(6):
    cyl(bm, (k * 0.12, 0, 0.75 + k * 1.4), 0.22 - k * 0.015, 0.2 - k * 0.015, 1.45, 8, 0)
top = Vector((0.7, 0, 8.6))
for k in range(7):
    a = 2 * math.pi * k / 7
    d = Vector((math.cos(a), math.sin(a), 0))
    p0 = top; p1 = top + d * 3.4 + Vector((0, 0, -1.2))
    side = Vector((-d.y, d.x, 0)) * 0.55
    vs = [bm.verts.new(p0 - side * 0.3), bm.verts.new(p0 + side * 0.3), bm.verts.new(p1 + side * 0.2 + Vector((0, 0, 0.4))), bm.verts.new(p1 - side * 0.2 + Vector((0, 0, 0.4))), bm.verts.new(p1 + d * 0.6 + Vector((0, 0, -0.6)))]
    tag(bm, [bm.faces.new((vs[0], vs[1], vs[2], vs[3])), bm.faces.new((vs[3], vs[2], vs[4]))], 1)
finish("TreePalm", bm, ["Bark", "Palm"], nature)

bm = new_bm()  # saguaro-style cactus
cyl(bm, (0, 0, 1.6), 0.28, 0.24, 3.2, 10, 0)
ico(bm, (0, 0, 3.2), 0.25, 1, 0)
for s, h in ((1, 1.4), (-1, 1.9)):
    cyl(bm, (s * 0.45, 0, h), 0.15, 0.15, 0.7, 8, 0, "X")
    cyl(bm, (s * 0.75, 0, h + 0.55), 0.16, 0.14, 1.1, 8, 0)
    ico(bm, (s * 0.75, 0, h + 1.1), 0.15, 1, 0)
finish("Cactus", bm, ["Cactus"], nature)

bm = new_bm()
ico(bm, (0, 0, 0.3), 1.0, 2, 0, (1.3, 1.0, 0.75), 0.18, 7)
ico(bm, (0.9, 0.4, 0.1), 0.55, 1, 0, (1, 1, 0.8), 0.2, 3)
finish("Rock", bm, ["Rock"], nature)

bm = new_bm()
for k, (c, r) in enumerate([((0, 0, 0.55), 0.8), ((0.55, 0.2, 0.45), 0.6), ((-0.5, -0.2, 0.4), 0.6)]):
    ico(bm, c, r, 1, 0, (1, 1, 0.8), 0.15, k + 11)
finish("Bush", bm, ["Bush"], nature)

bm = new_bm()  # grass tuft: 3 crossed blades planes
for k in range(3):
    a = math.pi * k / 3
    d = Vector((math.cos(a), math.sin(a), 0)) * 0.45
    vs = [bm.verts.new(-d), bm.verts.new(d), bm.verts.new(d * 0.6 + Vector((0, 0, 0.55))), bm.verts.new(-d * 0.6 + Vector((0, 0, 0.6)))]
    tag(bm, [bm.faces.new(vs)], 0)
    vs = [bm.verts.new(-d), bm.verts.new(-d * 0.6 + Vector((0, 0, 0.6))), bm.verts.new(d * 0.6 + Vector((0, 0, 0.55))), bm.verts.new(d)]
    tag(bm, [bm.faces.new(vs)], 0)
finish("GrassTuft", bm, ["Grass"], nature)

# --- buildings (front = +Y, origin at ground centre, foundation to -2 m)
def house(name, w, d, floors, wall, roof, roof_h=2.6, chimney=True):
    bm = new_bm()
    h = floors * 2.8 + 0.4
    box(bm, (0, 0, -1.0), (w + 0.3, d + 0.3, 2.0), 3)
    box(bm, (0, 0, h / 2), (w, d, h), 0)
    prism_roof(bm, (0, 0, h), d, w, roof_h, 1) if False else None
    # ridge along X for the street-facing gable look
    x0, x1 = -w / 2 - 0.4, w / 2 + 0.4
    y0, y1 = -d / 2 - 0.4, d / 2 + 0.4
    vs = [bm.verts.new(p) for p in [(x0, y0, h), (x1, y0, h), (x1, y1, h), (x0, y1, h), (x0, 0, h + roof_h), (x1, 0, h + roof_h)]]
    tag(bm, [bm.faces.new((vs[0], vs[1], vs[5], vs[4])), bm.faces.new((vs[2], vs[3], vs[4], vs[5])), bm.faces.new((vs[1], vs[2], vs[5])), bm.faces.new((vs[3], vs[0], vs[4])), bm.faces.new((vs[3], vs[2], vs[1], vs[0]))], 1)
    windows(bm, w, d, floors, 2)
    box(bm, (0, d / 2 + 0.05, 1.1), (1.1, 0.1, 2.2), 4)
    if chimney: box(bm, (w * 0.3, -d * 0.2, h + roof_h * 0.7), (0.6, 0.6, 1.8), 3)
    return finish(name, bm, [wall, roof, "Window", "Stone", "Wood"], bld)

house("HouseA", 8, 7, 2, "Plaster", "Roof")
house("HouseB", 10, 8, 2, "Plaster2", "Roof2")
house("HouseC", 7, 6, 1, "Plaster3", "Roof", 2.2)

bm = new_bm()  # church with tower
box(bm, (0, 0, -1), (9, 16, 2), 3)
box(bm, (0, -1.5, 3.5), (8, 13, 7), 0)
vs = [bm.verts.new(p) for p in [(-4.4, -8.4, 7), (4.4, -8.4, 7), (4.4, 5.4, 7), (-4.4, 5.4, 7), (0, -8.4, 10.5), (0, 5.4, 10.5)]]
tag(bm, [bm.faces.new((vs[1], vs[2], vs[5], vs[4])), bm.faces.new((vs[3], vs[0], vs[4], vs[5])), bm.faces.new((vs[0], vs[1], vs[4])), bm.faces.new((vs[2], vs[3], vs[5]))], 1)
box(bm, (0, 6.5, 7.5), (4, 4, 15), 0)
cyl(bm, (0, 6.5, 17.5), 2.9, 0.1, 5, 4, 1)
for z in (3, 9, 12): box(bm, (0, 8.55, z), (1.2, 0.1, 2.0), 2)
finish("Church", bm, ["Plaster", "Roof2", "Window", "Stone"], bld)

bm = new_bm()  # barn
box(bm, (0, 0, -1), (12.3, 18.3, 2), 3)
box(bm, (0, 0, 3), (12, 18, 6), 0)
vs = [bm.verts.new(p) for p in [(-6.6, -9.4, 6), (6.6, -9.4, 6), (6.6, 9.4, 6), (-6.6, 9.4, 6), (-3.5, -9.4, 9), (3.5, -9.4, 9), (3.5, 9.4, 9), (-3.5, 9.4, 9), (0, -9.4, 10.2), (0, 9.4, 10.2)]]
tag(bm, [bm.faces.new((vs[0], vs[3], vs[7], vs[4])), bm.faces.new((vs[2], vs[1], vs[5], vs[6])), bm.faces.new((vs[4], vs[7], vs[9], vs[8])), bm.faces.new((vs[6], vs[5], vs[8], vs[9]))], 1)
tag(bm, [bm.faces.new((vs[0], vs[4], vs[8], vs[5], vs[1])), bm.faces.new((vs[2], vs[6], vs[9], vs[7], vs[3]))], 0)
box(bm, (0, 9.05, 2.4), (4.5, 0.12, 4.8), 2)
box(bm, (0, 9.12, 2.4), (4.6, 0.05, 0.25), 4)
finish("Barn", bm, ["BarnRed", "Roof2", "Wood", "Stone", "White"], bld)

bm = new_bm()
cyl(bm, (0, 0, 7), 2.6, 2.6, 14, 16, 0)
ico(bm, (0, 0, 14), 2.6, 2, 1, (1, 1, 0.5))
finish("Silo", bm, ["Steel", "Steel"], bld)

bm = new_bm()  # gas station: canopy + pumps + shop
box(bm, (0, 0, -0.9), (22, 18, 1.8), 2)
for x in (-6, 6):
    for y in (-3, 3): box(bm, (x, y, 2.5), (0.35, 0.35, 5), 0)
box(bm, (0, 0, 5.2), (16, 10, 0.6), 1)
box(bm, (0, 5.1, 5.2), (16.2, 0.2, 0.7), 3)
for x in (-3, 3): box(bm, (x, 0, 0.8), (0.8, 0.5, 1.6), 3)
box(bm, (0, -7, 2), (12, 5, 4), 4)
box(bm, (0, -4.45, 1.7), (8, 0.1, 2), 5)
finish("GasStation", bm, ["Steel", "White", "Concrete", "Blue", "Plaster", "Window"], bld)

bm = new_bm()  # roadside diner
box(bm, (0, 0, -1), (16.3, 8.3, 2), 2)
box(bm, (0, 0, 1.8), (16, 8, 3.6), 0)
cyl(bm, (0, 0, 3.6), 4.3, 4.3, 16.6, 16, 1, "X")
box(bm, (0, 4.06, 1.7), (13, 0.1, 1.6), 3)
box(bm, (0, 4.3, 4.6), (6, 0.3, 1.5), 4)
finish("Diner", bm, ["Plaster3", "Steel", "Concrete", "Window", "Pink"], bld)

bm = new_bm()
box(bm, (0, 0, -1), (14.3, 10.3, 2), 2)
box(bm, (0, 0, 3), (14, 10, 6), 0)
vs = [bm.verts.new(p) for p in [(-7.3, -5.3, 6), (7.3, -5.3, 6), (7.3, 5.3, 6), (-7.3, 5.3, 6), (-7.3, 0, 7.6), (7.3, 0, 7.6)]]
tag(bm, [bm.faces.new((vs[0], vs[1], vs[5], vs[4])), bm.faces.new((vs[2], vs[3], vs[4], vs[5])), bm.faces.new((vs[1], vs[2], vs[5])), bm.faces.new((vs[3], vs[0], vs[4]))], 1)
box(bm, (0, 5.06, 2.2), (5, 0.1, 4.4), 3)
finish("Warehouse", bm, ["Blue", "Roof2", "Concrete", "Steel"], bld)

bm = new_bm()  # pier: deck top at origin, along +Y
box(bm, (0, 20, -0.25), (4, 40, 0.5), 0)
for y in range(0, 41, 5):
    for x in (-1.8, 1.8): cyl(bm, (x, y, -2.5), 0.2, 0.2, 5, 8, 0)
finish("Pier", bm, ["Wood"], bld)

bm = new_bm()  # small fishing boat
for k in range(9):
    y = -3 + k * 0.75
    t = 1 - abs((k - 3.5) / 4.5) ** 2
    box(bm, (0, y, 0.6), (2.2 * max(t, 0.3), 0.76, 1.2), 0)
box(bm, (0, -0.8, 1.8), (1.4, 1.6, 1.2), 1)
cyl(bm, (0, 0.8, 3.5), 0.06, 0.06, 4.5, 6, 2)
finish("Boat", bm, ["White", "Blue", "Wood"], bld)

bm = new_bm()  # lighthouse
box(bm, (0, 0, -1), (7, 7, 2), 3)
for k in range(6):
    cyl(bm, (0, 0, 1.5 + k * 3), 2.4 - k * 0.2, 2.2 - k * 0.2, 3, 16, 0 if k % 2 == 0 else 1)
cyl(bm, (0, 0, 19.2), 1.9, 1.9, 0.4, 16, 3)
cyl(bm, (0, 0, 20.4), 1.3, 1.3, 2.0, 12, 2)
cyl(bm, (0, 0, 22.2), 1.6, 0.2, 1.6, 12, 1)
box(bm, (0, 3.5, 1.2), (4, 3, 2.4), 4)
finish("Lighthouse", bm, ["White", "Red", "Lamp", "Stone", "Plaster"], bld)

bm = new_bm()  # ruined castle: broken curtain walls and two towers
import random
rnd = random.Random(5)
box(bm, (0, 0, -1), (34, 34, 2), 0)
for (cx, cy, sx, sy) in [(0, 15, 30, 2.5), (0, -15, 30, 2.5), (15, 0, 2.5, 30), (-15, 0, 2.5, 30)]:
    n = 8
    for k in range(n):
        t = (k + 0.5) / n - 0.5
        h = rnd.uniform(4, 10) if (k + int(cx + cy)) % 5 else rnd.uniform(1, 3)
        box(bm, (cx + t * (sx if sx > sy else 0), cy + t * (sy if sy > sx else 0), h / 2), (sx / n + 0.05 if sx > sy else sx, sy / n + 0.05 if sy > sx else sy, h), 0)
for (x, y, h) in [(15, 15, 16), (-15, -15, 12), (-15, 15, 7)]:
    cyl(bm, (x, y, h / 2), 3.6, 3.2, h, 12, 0)
box(bm, (0, 15.5, 2.5), (4, 3, 5), 1)
finish("CastleRuin", bm, ["Stone", "Wood"], bld)

bm = new_bm()  # wind turbine tower + nacelle (rotor separate), hub at z=48, nacelle towards +Y
cyl(bm, (0, 0, 24), 1.6, 0.9, 48, 14, 0)
box(bm, (0, 1.0, 48), (2.2, 5.0, 2.2), 0)
box(bm, (0, 0, -0.5), (6, 6, 1), 1)
finish("WindTurbine", bm, ["White", "Concrete"], bld)

bm = new_bm()  # rotor: 3 blades in the XZ plane, origin at hub
ico(bm, (0, 0, 0), 1.2, 1, 0, (1, 1.6, 1))
for k in range(3):
    a = 2 * math.pi * k / 3
    d = Vector((math.cos(a), 0, math.sin(a)))
    s = Vector((-d.z, 0, d.x))
    vs = [bm.verts.new(d * 1.0 + s * 0.9), bm.verts.new(d * 1.0 - s * 0.5), bm.verts.new(d * 22 - s * 0.25), bm.verts.new(d * 22 + s * 0.35)]
    tag(bm, [bm.faces.new(vs)], 0)
finish("TurbineRotor", bm, ["White"], bld)

# ------------------------------------------------------------------ export
def export(coll, fname):
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, fname), use_selection=True, export_format="GLB", export_apply=True)

# lay out for inspection (export uses object origins so spread them in the file only after export)
export(road, "kit.glb"); export(nature, "nature.glb"); export(bld, "buildings.glb")
for i, o in enumerate(road.objects): o.location = (i * 5.0 - 30, 40, 0)
for i, o in enumerate(nature.objects): o.location = (i * 6.0 - 20, 55, 0)
for i, o in enumerate(bld.objects): o.location = ((i % 6) * 40.0 - 100, 90 + (i // 6) * 40.0, 0)
bpy.ops.wm.save_mainfile()
print("kit ok", len(road.objects), len(nature.objects), len(bld.objects))
