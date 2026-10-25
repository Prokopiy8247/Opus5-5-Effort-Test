# Props kit for the master .blend: nature, settlement buildings, roadside furniture and activity gates.
# Requires car_builder.py helpers (box, cyl, join, mat, coll, export_glb). Each prop lives in KIT_<name>.
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise

def pmats():
    return {
        "Bark": mat("Bark", (0.25, 0.16, 0.09), 0, 0.9),
        "BarkLight": mat("BarkLight", (0.62, 0.58, 0.5), 0, 0.85),
        "LeafPine": mat("LeafPine", (0.07, 0.2, 0.08), 0, 0.85),
        "LeafOak": mat("LeafOak", (0.15, 0.32, 0.08), 0, 0.8),
        "LeafOakB": mat("LeafOakB", (0.24, 0.38, 0.1), 0, 0.8),
        "LeafPalm": mat("LeafPalm", (0.2, 0.42, 0.12), 0, 0.75),
        "Cactus": mat("Cactus", (0.2, 0.38, 0.17), 0, 0.7),
        "Shrub": mat("Shrub", (0.36, 0.36, 0.18), 0, 0.9),
        "Rock": mat("Rock", (0.42, 0.4, 0.37), 0, 0.92),
        "RockRed": mat("RockRed", (0.6, 0.33, 0.2), 0, 0.92),
        "Wall": mat("Wall", (0.88, 0.84, 0.74), 0, 0.85),
        "WallB": mat("WallB", (0.75, 0.55, 0.42), 0, 0.85),
        "Roof": mat("Roof", (0.55, 0.18, 0.12), 0, 0.75),
        "RoofDark": mat("RoofDark", (0.18, 0.2, 0.24), 0, 0.7),
        "Wood": mat("Wood", (0.45, 0.28, 0.14), 0, 0.85),
        "BarnRed": mat("BarnRed", (0.55, 0.1, 0.08), 0, 0.85),
        "Window": mat("Window", (0.12, 0.16, 0.2), 0.3, 0.1, emit=(0.0, 0.0, 0.0)),
        "WindowLit": mat("WindowLit", (0.9, 0.75, 0.4), 0, 0.3, emit=(1.0, 0.75, 0.35)),
        "Metal": mat("Metal", (0.7, 0.72, 0.74), 0.85, 0.35),
        "White": mat("White", (0.92, 0.92, 0.9), 0, 0.6),
        "Red": mat("Red", (0.8, 0.08, 0.06), 0, 0.5),
        "Yellow": mat("Yellow", (0.95, 0.72, 0.05), 0, 0.5),
        "Blue": mat("Blue", (0.1, 0.3, 0.75), 0, 0.5),
        "Pink": mat("Pink", (0.95, 0.3, 0.6), 0, 0.5),
        "Stone": mat("Stone", (0.55, 0.53, 0.5), 0, 0.95),
        "Concrete": mat("Concrete", (0.6, 0.6, 0.58), 0, 0.9),
        "Hay": mat("Hay", (0.8, 0.66, 0.3), 0, 0.95),
        "Lamp": mat("Lamp", (1.0, 0.9, 0.7), 0, 0.3, emit=(1.0, 0.85, 0.55)),
        "Asphalt": mat("Asphalt", (0.1, 0.1, 0.11), 0, 0.9),
        "Trim": mat("Trim", (0.03, 0.03, 0.035), 0.0, 0.6),
        "Tire": mat("Tire", (0.03, 0.03, 0.03), 0.0, 0.85),
        "Glass": mat("Glass", (0.05, 0.07, 0.09), 0.0, 0.05, alpha=0.45),
    }

def kit(name):
    root_colls()
    parent = bpy.data.collections["FORZA_GODOT"].children[KIT_PARENT.get(name, "Props")]
    cname = "KIT_" + name
    old = bpy.data.collections.get(cname)
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    return coll(cname, parent)

KIT_PARENT = {}

def blob(name, cobj, m, center, radius, squash=1.0, seed=0, detail=2, amp=0.25):
    """Noisy icosphere for foliage / rocks."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=radius)
    rnd = random.Random(seed)
    off = Vector((rnd.random() * 10, rnd.random() * 10, rnd.random() * 10))
    for v in bm.verts:
        n = noise.noise(v.co * (1.6 / radius) + off)
        v.co = v.co * (1.0 + amp * n)
        v.co.z *= squash
        v.co += Vector(center)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    cobj.objects.link(ob)
    me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    return ob

def cone(name, cobj, m, center, r1, r2, depth, verts=10):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r1, radius2=r2, depth=depth)
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(center))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    cobj.objects.link(ob)
    me.materials.append(m)
    return ob

def prism_roof(name, cobj, m, center, w, d, h, overhang=0.3):
    """Gable roof along Y."""
    cx, cy, cz = center
    hw, hd = w / 2 + overhang, d / 2 + overhang
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in [
        (cx - hw, cy - hd, cz), (cx + hw, cy - hd, cz), (cx + hw, cy + hd, cz), (cx - hw, cy + hd, cz),
        (cx, cy - hd, cz + h), (cx, cy + hd, cz + h)]]
    bm.faces.new((v[0], v[1], v[4]))
    bm.faces.new((v[2], v[3], v[5]))
    bm.faces.new((v[1], v[2], v[5], v[4]))
    bm.faces.new((v[3], v[0], v[4], v[5]))
    bm.faces.new((v[3], v[2], v[1], v[0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    cobj.objects.link(ob)
    me.materials.append(m)
    return ob

def windows(cobj, M, w, d, z0, rows, cols_x, cols_y, lit=False):
    out = []
    mm = M["WindowLit"] if lit else M["Window"]
    for r in range(rows):
        z = z0 + r * 2.8
        for i in range(cols_x):
            x = -w / 2 + (i + 0.5) * w / cols_x
            out.append(box("win", cobj, mm, (x, -d / 2 - 0.02, z), (0.8, 0.06, 1.0)))
            out.append(box("win", cobj, mm, (x, d / 2 + 0.02, z), (0.8, 0.06, 1.0)))
        for i in range(cols_y):
            y = -d / 2 + (i + 0.5) * d / cols_y
            out.append(box("win", cobj, mm, (-w / 2 - 0.02, y, z), (0.06, 0.8, 1.0)))
            out.append(box("win", cobj, mm, (w / 2 + 0.02, y, z), (0.06, 0.8, 1.0)))
    return out

# ------------------------------------------------------------------ nature
def tree_pine(lod=False):
    M = pmats(); c = kit("tree_pine_lod" if lod else "tree_pine")
    parts = [cyl("trunk", c, M["Bark"], (0, 0, 2.0), 0.28, 4.0, "Z", 6 if lod else 10)]
    layers = 2 if lod else 5
    for i in range(layers):
        t = i / max(1, layers - 1)
        r = 2.6 * (1 - t * 0.7)
        z = 2.5 + t * 7.5
        parts.append(cone("layer", c, M["LeafPine"], (0, 0, z + 1.6), r, 0.15, 3.4 if not lod else 7.0, 6 if lod else 9))
        if lod:
            break
    if not lod:
        for i, o in enumerate(parts[1:]):
            # jitter for an organic silhouette
            for v in o.data.vertices:
                v.co.x += noise.noise(v.co * 0.7 + Vector((i, 0, 0))) * 0.35
                v.co.y += noise.noise(v.co * 0.7 + Vector((0, i, 3))) * 0.35
    return join(parts, "Tree")

def tree_oak(lod=False):
    M = pmats(); c = kit("tree_oak_lod" if lod else "tree_oak")
    parts = [cyl("trunk", c, M["Bark"], (0, 0, 1.8), 0.35, 3.6, "Z", 6 if lod else 10)]
    if lod:
        parts.append(blob("crown", c, M["LeafOak"], (0, 0, 5.5), 3.6, 0.85, 1, 1, 0.2))
    else:
        parts.append(cyl("branch", c, M["Bark"], (0.6, 0, 3.8), 0.18, 2.2, "Z", 8))
        parts[-1].rotation_euler = (0, 0.5, 0)
        rnd = random.Random(3)
        for i in range(6):
            a = i / 6 * math.tau
            r = 1.8 + rnd.random() * 0.6
            ctr = (math.cos(a) * 1.6, math.sin(a) * 1.6, 5.0 + rnd.random() * 1.6)
            parts.append(blob("crown", c, M["LeafOak"] if i % 2 else M["LeafOakB"], ctr, r, 0.8, i, 2, 0.3))
        parts.append(blob("crown", c, M["LeafOak"], (0, 0, 6.8), 2.4, 0.8, 9, 2, 0.3))
    return join(parts, "Tree")

def tree_birch(lod=False):
    M = pmats(); c = kit("tree_birch_lod" if lod else "tree_birch")
    parts = [cyl("trunk", c, M["BarkLight"], (0, 0, 3.5), 0.17, 7.0, "Z", 6 if lod else 8)]
    if lod:
        parts.append(blob("crown", c, M["LeafOakB"], (0, 0, 7.0), 2.0, 1.5, 2, 1, 0.2))
    else:
        for i in range(4):
            parts.append(blob("crown", c, M["LeafOakB"], (math.sin(i * 2.1) * 0.7, math.cos(i * 2.1) * 0.7, 5.2 + i * 1.1), 1.5 - i * 0.15, 1.1, 20 + i, 2, 0.32))
    return join(parts, "Tree")

def tree_palm(lod=False):
    M = pmats(); c = kit("tree_palm_lod" if lod else "tree_palm")
    parts = []
    segs = 4 if lod else 8
    for i in range(segs):
        z = i * 1.0
        x = (i / segs) ** 2 * 1.2
        parts.append(cyl("trunk", c, M["Bark"], (x, 0, z + 0.5), 0.24 - i * 0.012, 1.05, "Z", 6 if lod else 8))
    top = Vector((1.2, 0, segs * 1.0))
    fronds = 5 if lod else 8
    for i in range(fronds):
        a = i / fronds * math.tau
        fr = box("frond", c, M["LeafPalm"], (0, 0, 0), (0.6, 3.6, 0.05))
        fr.data.transform(Matrix.Translation((0, 1.8, 0)))
        fr.data.transform(Matrix.Rotation(-0.45, 4, "X"))
        fr.data.transform(Matrix.Rotation(a, 4, "Z"))
        fr.data.transform(Matrix.Translation(top))
        parts.append(fr)
    return join(parts, "Tree")

def cactus():
    M = pmats(); c = kit("cactus")
    parts = [cyl("stem", c, M["Cactus"], (0, 0, 1.6), 0.28, 3.2, "Z", 10), blob("top", c, M["Cactus"], (0, 0, 3.2), 0.28, 1.0, 1, 1, 0.0)]
    for sx, h, l in ((1, 1.4, 0.9), (-1, 1.9, 0.7)):
        parts.append(cyl("armh", c, M["Cactus"], (sx * 0.45, 0, h), 0.17, 0.6, "X", 8))
        parts.append(cyl("armv", c, M["Cactus"], (sx * 0.72, 0, h + l / 2), 0.17, l, "Z", 8))
        parts.append(blob("armtop", c, M["Cactus"], (sx * 0.72, 0, h + l), 0.17, 1.0, 2, 1, 0.0))
    return join(parts, "Cactus")

def shrub():
    M = pmats(); c = kit("shrub")
    parts = [blob("s", c, M["Shrub"], (math.cos(i * 2.4) * 0.4, math.sin(i * 2.4) * 0.4, 0.35), 0.55, 0.7, 30 + i, 1, 0.35) for i in range(3)]
    return join(parts, "Shrub")

def bush():
    M = pmats(); c = kit("bush")
    parts = [blob("b", c, M["LeafOak"] if i % 2 else M["LeafOakB"], (math.cos(i * 2.1) * 0.6, math.sin(i * 2.1) * 0.6, 0.6), 0.9, 0.8, 40 + i, 2, 0.3) for i in range(4)]
    return join(parts, "Bush")

def rock(variant):
    M = pmats(); c = kit("rock_" + variant)
    m = M["Rock"] if variant != "red" else M["RockRed"]
    parts = [blob("r", c, m, (0, 0, 0.6), 1.4, 0.65, 60 + len(variant), 2, 0.45)]
    if variant == "b":
        parts.append(blob("r2", c, m, (1.3, 0.4, 0.3), 0.8, 0.7, 77, 1, 0.45))
    return join(parts, "Rock")

# ------------------------------------------------------------------ buildings
def house(variant=0):
    M = pmats(); c = kit("house_%d" % variant)
    w, d, h = (8.0, 6.0, 3.0) if variant == 0 else (9.0, 7.0, 5.8)
    wall = M["Wall"] if variant != 2 else M["WallB"]
    if variant == 2:
        w, d, h = 7.0, 7.0, 3.2
    parts = [box("walls", c, wall, (0, 0, h / 2), (w, d, h))]
    parts.append(prism_roof("roof", c, M["Roof"] if variant != 1 else M["RoofDark"], (0, 0, h), d, w, 2.4 if variant != 2 else 1.6, 0.4))
    parts[-1].rotation_euler = (0, 0, math.pi / 2)
    parts += windows(c, M, w, d, 1.5, 2 if variant == 1 else 1, 3, 2)
    parts.append(box("door", c, M["Wood"], (0, -d / 2 - 0.03, 1.05), (1.0, 0.08, 2.1)))
    parts.append(box("chimney", c, M["Stone"], (w * 0.25, 0, h + 1.8), (0.6, 0.6, 2.2)))
    parts.append(box("base", c, M["Stone"], (0, 0, 0.15), (w + 0.2, d + 0.2, 0.5)))
    ob = join(parts, "House")
    return ob

def barn():
    M = pmats(); c = kit("barn")
    parts = [box("walls", c, M["BarnRed"], (0, 0, 2.5), (10, 14, 5))]
    parts.append(prism_roof("roof", c, M["RoofDark"], (0, 0, 5), 10, 14, 3.5, 0.4))
    parts.append(box("door", c, M["White"], (0, -7.03, 2.0), (4.0, 0.1, 4.0)))
    parts.append(box("doorx1", c, M["BarnRed"], (0, -7.08, 2.0), (4.0, 0.08, 0.25)))
    parts.append(cyl("silo", c, M["Metal"], (7.5, 4, 5), 2.2, 10, "Z", 16))
    parts.append(blob("silotop", c, M["Metal"], (7.5, 4, 10), 2.2, 0.5, 1, 2, 0.0))
    for i in range(3):
        parts.append(cyl("hay", c, M["Hay"], (-7 + i * 0.0, -5 + i * 1.9, 0.75), 0.75, 1.3, "X", 14))
    return join(parts, "Barn")

def gas_station():
    M = pmats(); c = kit("gas_station")
    parts = [box("shop", c, M["White"], (0, 8, 2), (12, 7, 4)), box("shopband", c, M["Blue"], (0, 4.45, 3.6), (12.2, 0.15, 0.8))]
    parts += [box("shopwin", c, M["WindowLit"], (x, 4.45, 1.6), (2.4, 0.1, 1.8)) for x in (-3.5, 0.5, 3.8)]
    parts.append(box("canopy", c, M["White"], (0, -2, 5.2), (14, 9, 0.6)))
    parts.append(box("canopyband", c, M["Blue"], (0, -2, 5.2), (14.1, 9.1, 0.35)))
    for x in (-5, 5):
        for y in (-5, 1):
            parts.append(box("col", c, M["White"], (x, y, 2.5), (0.4, 0.4, 5)))
    for x in (-2.5, 2.5):
        parts.append(box("pump", c, M["Red"], (x, -2, 0.9), (0.9, 0.6, 1.8)))
        parts.append(box("pumpscr", c, M["WindowLit"], (x, -2.32, 1.3), (0.5, 0.05, 0.3)))
    parts.append(box("island", c, M["Concrete"], (0, -2, 0.1), (8, 1.5, 0.2)))
    parts.append(box("sign_pole", c, M["Metal"], (8, -7, 4), (0.3, 0.3, 8)))
    parts.append(box("sign", c, M["Blue"], (8, -7, 7.5), (2.5, 0.4, 2.5)))
    parts.append(box("sign_star", c, M["Yellow"], (8, -7.25, 7.5), (1.4, 0.05, 1.4)))
    parts.append(box("lot", c, M["Asphalt"], (0, 0, 0.03), (22, 24, 0.08)))
    return join(parts, "GasStation")

def diner():
    M = pmats(); c = kit("diner")
    parts = [box("body", c, M["Metal"], (0, 0, 1.9), (16, 6, 3.4), 0.3)]
    parts.append(box("band", c, M["Red"], (0, 0, 2.6), (16.1, 6.1, 0.4)))
    parts += [box("win", c, M["WindowLit"], (x, -3.05, 1.8), (1.6, 0.1, 1.1)) for x in range(-6, 8, 2)]
    parts.append(box("roofsign", c, M["Pink"], (0, 0, 4.4), (6, 0.4, 1.4)))
    parts.append(box("roofsign_lit", c, M["Lamp"], (0, -0.22, 4.4), (5.4, 0.05, 0.9)))
    parts.append(box("base", c, M["Concrete"], (0, 0, 0.1), (17, 7, 0.3)))
    return join(parts, "Diner")

def lighthouse():
    M = pmats(); c = kit("lighthouse")
    parts = []
    for i in range(6):
        parts.append(cyl("seg", c, M["White"] if i % 2 == 0 else M["Red"], (0, 0, i * 3.5 + 1.75), 2.6 - i * 0.18, 3.5, "Z", 16))
    parts.append(cyl("gallery", c, M["Trim"], (0, 0, 21.2), 2.2, 0.4, "Z", 16))
    parts.append(cyl("lamp", c, M["Lamp"], (0, 0, 22.6), 1.2, 2.4, "Z", 12))
    parts.append(cone("cap", c, M["Red"], (0, 0, 24.5), 1.5, 0.1, 1.6, 12))
    parts.append(box("house", c, M["Wall"], (5, 0, 1.8), (5, 6, 3.6)))
    parts.append(prism_roof("roof", c, M["Roof"], (5, 0, 3.6), 5, 6, 1.6, 0.3))
    return join(parts, "Lighthouse")

def castle():
    M = pmats(); c = kit("castle")
    parts = []
    s = 22.0
    for i, (x, y) in enumerate([(-s / 2, -s / 2), (s / 2, -s / 2), (s / 2, s / 2), (-s / 2, s / 2)]):
        hgt = [14, 10, 16, 7][i]
        parts.append(cyl("tower", c, M["Stone"], (x, y, hgt / 2), 3.2, hgt, "Z", 14))
        for k in range(8):
            a = k / 8 * math.tau
            parts.append(box("merlon", c, M["Stone"], (x + math.cos(a) * 2.9, y + math.sin(a) * 2.9, hgt + 0.6), (1.0, 1.0, 1.2)))
    for (x0, y0, x1, y1, h) in [(-s / 2, -s / 2, s / 2, -s / 2, 8), (s / 2, -s / 2, s / 2, s / 2, 5), (-s / 2, s / 2, -s / 2, -s / 2, 9)]:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        L = math.hypot(x1 - x0, y1 - y0)
        wall = box("wall", c, M["Stone"], (cx, cy, h / 2), (L if y0 == y1 else 1.8, L if x0 == x1 else 1.8, h))
        parts.append(wall)
    parts.append(box("keep", c, M["Stone"], (0, 2, 7), (9, 8, 14)))
    parts += [box("slit", c, M["Trim"], (x, -2.05, z), (0.4, 0.1, 1.4)) for x in (-2.5, 0, 2.5) for z in (5, 9)]
    for i in range(10):
        parts.append(blob("rubble", c, M["Stone"], (random.uniform(-9, 9), random.uniform(-9, -4), 0.3), random.uniform(0.4, 1.0), 0.6, 80 + i, 1, 0.4))
    return join(parts, "Castle")

def wind_turbine():
    M = pmats(); c = kit("wind_turbine")
    tower = join([cone("tower", c, M["White"], (0, 0, 22), 1.6, 0.9, 44, 14),
                  box("nacelle", c, M["White"], (0, 0.8, 44.5), (2.0, 5.0, 2.0), 0.4),
                  blob("hubcap", c, M["White"], (0, -1.9, 44.5), 0.9, 1.0, 1, 1, 0.0)], "Tower")
    blades = []
    for i in range(3):
        b = box("blade", c, M["White"], (0, 0, 0), (1.4, 0.3, 19))
        b.data.transform(Matrix.Translation((0, 0, 10.0)))
        b.data.transform(Matrix.Rotation(i * math.tau / 3, 4, "Y"))
        blades.append(b)
    rotor = join(blades, "Rotor")
    rotor.location = (0, -2.3, 44.5)
    return tower

def windmill_fence():
    M = pmats(); c = kit("fence")
    parts = [box("post", c, M["Wood"], (x, 0, 0.6), (0.14, 0.14, 1.2)) for x in (-2, 2)]
    parts += [box("rail", c, M["Wood"], (0, 0, z), (4.1, 0.08, 0.14)) for z in (0.5, 1.0)]
    return join(parts, "Fence")

def street_lamp():
    M = pmats(); c = kit("street_lamp")
    parts = [cyl("pole", c, M["Metal"], (0, 0, 3.5), 0.09, 7.0, "Z", 8), box("arm", c, M["Metal"], (0, 0.8, 7.0), (0.12, 1.7, 0.12)), box("head", c, M["Metal"], (0, 1.6, 6.95), (0.4, 0.7, 0.2)), box("bulb", c, M["Lamp"], (0, 1.6, 6.82), (0.3, 0.55, 0.05))]
    return join(parts, "Lamp")

def sign(kind):
    M = pmats(); c = kit("sign_" + kind)
    parts = [cyl("pole", c, M["Metal"], (0, 0, 1.2), 0.04, 2.4, "Z", 8)]
    if kind == "speed":
        parts.append(cyl("plate", c, M["White"], (0, -0.03, 2.2), 0.38, 0.03, "Y", 20))
        parts.append(cyl("ring", c, M["Red"], (0, -0.01, 2.2), 0.42, 0.02, "Y", 20))
    elif kind == "chevron":
        parts.append(box("plate", c, M["Yellow"], (0, -0.03, 2.0), (0.7, 0.03, 0.85)))
        for k in range(2):
            ch = box("chev", c, M["Trim"], (0, -0.06, 2.0), (0.12, 0.02, 0.5))
            ch.data.transform(Matrix.Translation((0, 0, -2.0)))
            ch.data.transform(Matrix.Rotation(0.6 if k == 0 else -0.6, 4, "Y"))
            ch.data.transform(Matrix.Translation((0.05 if k == 0 else -0.05, 0, 2.0 + (0.12 if k == 0 else -0.12))))
            parts.append(ch)
    elif kind == "danger":
        tri = cone("plate", c, M["Yellow"], (0, 0, 0), 0.6, 0.0, 0.04, 3)
        tri.data.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
        tri.data.transform(Matrix.Rotation(math.pi / 2, 4, "Y"))
        tri.data.transform(Matrix.Translation((0, -0.04, 2.1)))
        parts.append(tri)
        parts.append(box("mark", c, M["Trim"], (0, -0.08, 2.05), (0.08, 0.02, 0.35)))
    elif kind == "direction":
        parts[0].data.transform(Matrix.Translation((0, 0, 0.4)))
        parts.append(box("board", c, M["Blue"], (0, -0.04, 2.6), (2.4, 0.05, 0.9)))
        parts.append(box("text", c, M["White"], (0, -0.08, 2.6), (1.9, 0.02, 0.12)))
    return join(parts, "Sign")

def gate(kind):
    """Activity gates: festival arch (races), speed trap camera, drift banner, jump ramp."""
    M = pmats(); c = kit("gate_" + kind)
    col = {"race": M["Pink"], "trap": M["Blue"], "drift": M["Yellow"], "zone": M["Red"], "check": M["Pink"]}[kind if kind != "ramp" else "zone"]
    if kind == "ramp":
        me = bpy.data.meshes.new("ramp")
        bm = bmesh.new()
        L, W, H = 14.0, 7.0, 2.6
        v = [bm.verts.new(p) for p in [(-W / 2, 0, 0), (W / 2, 0, 0), (W / 2, L, H), (-W / 2, L, H), (-W / 2, L, 0), (W / 2, L, 0)]]
        bm.faces.new((v[0], v[1], v[2], v[3])); bm.faces.new((v[3], v[2], v[5], v[4])); bm.faces.new((v[0], v[3], v[4])); bm.faces.new((v[1], v[5], v[2])); bm.faces.new((v[0], v[4], v[5], v[1]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new("Ramp", me)
        c.objects.link(ob)
        me.materials.append(M["Wood"])
        stripes = [box("str", c, M["Yellow"] if i % 2 else M["Trim"], (0, L - 0.2, H - 0.05 - i * 0.0), (W / 8, 0.3, 0.12)) for i in range(1)]
        side = [box("rail", c, M["Red"], (sx * (W / 2 + 0.1), L / 2, H / 2), (0.2, L, 0.3)) for sx in (-1, 1)]
        return join([ob] + side, "Ramp")
    parts = []
    span = 18.0
    for sx in (-1, 1):
        parts.append(box("pillar", c, col, (sx * span / 2, 0, 3.0), (0.9, 0.9, 6.0), 0.1))
        parts.append(box("pillar_base", c, M["Trim"], (sx * span / 2, 0, 0.3), (1.3, 1.3, 0.6)))
    if kind in ("race", "check", "drift", "zone"):
        parts.append(box("banner", c, col, (0, 0, 6.2), (span + 0.9, 0.6, 1.4), 0.1))
        parts.append(box("banner_lit", c, M["Lamp"], (0, -0.32, 6.2), (span * 0.7, 0.05, 0.5)))
    if kind == "trap":
        parts.append(box("cam_arm", c, M["Metal"], (span / 2 - 1.5, 0, 6.0), (3.0, 0.25, 0.25)))
        parts.append(box("camera", c, M["Trim"], (span / 2 - 3.0, -0.3, 5.7), (0.6, 0.9, 0.5)))
        parts.append(box("cam_lens", c, M["Lamp"], (span / 2 - 3.0, -0.78, 5.7), (0.3, 0.05, 0.3)))
        parts.append(box("panel", c, col, (span / 2, 0, 4.5), (1.4, 0.3, 2.0)))
    return join(parts, "Gate")

def boat():
    M = pmats(); c = kit("boat")
    hull = []
    rings = []
    for i in range(9):
        u = i / 8
        y = -3 + u * 6.5
        hw = 1.2 * math.sin(min(1.0, u * 1.2 + 0.05) * math.pi) ** 0.5 if u < 0.9 else 0.3
        rings.append(ring(y, 0.0, 1.1, max(0.05, hw), 1.1, 12, 2.5, 0.5))
    hull.append(loft("hull", rings, [M["White"]], c))
    hull.append(box("cabin", c, M["Blue"], (0, -0.8, 1.6), (1.4, 1.8, 1.2)))
    hull.append(box("cabwin", c, M["Window"], (0, 0.12, 1.75), (1.2, 0.05, 0.5)))
    hull.append(cyl("mast", c, M["Metal"], (0, 0.8, 3.0), 0.06, 4.0, "Z", 8))
    return join(hull, "Boat")

def build_all_props(out_dir):
    builders = [
        ("tree_pine", lambda: tree_pine()), ("tree_pine_lod", lambda: tree_pine(True)),
        ("tree_oak", lambda: tree_oak()), ("tree_oak_lod", lambda: tree_oak(True)),
        ("tree_birch", lambda: tree_birch()), ("tree_birch_lod", lambda: tree_birch(True)),
        ("tree_palm", lambda: tree_palm()), ("tree_palm_lod", lambda: tree_palm(True)),
        ("cactus", cactus), ("shrub", shrub), ("bush", bush),
        ("rock_a", lambda: rock("a")), ("rock_b", lambda: rock("b")), ("rock_red", lambda: rock("red")),
        ("house_0", lambda: house(0)), ("house_1", lambda: house(1)), ("house_2", lambda: house(2)),
        ("barn", barn), ("gas_station", gas_station), ("diner", diner), ("lighthouse", lighthouse),
        ("castle", castle), ("wind_turbine", wind_turbine), ("fence", windmill_fence), ("street_lamp", street_lamp),
        ("sign_speed", lambda: sign("speed")), ("sign_chevron", lambda: sign("chevron")),
        ("sign_danger", lambda: sign("danger")), ("sign_direction", lambda: sign("direction")),
        ("gate_race", lambda: gate("race")), ("gate_check", lambda: gate("check")), ("gate_trap", lambda: gate("trap")),
        ("gate_drift", lambda: gate("drift")), ("gate_zone", lambda: gate("zone")), ("gate_ramp", lambda: gate("ramp")),
        ("boat", boat),
    ]
    nature = {"tree_pine", "tree_pine_lod", "tree_oak", "tree_oak_lod", "tree_birch", "tree_birch_lod", "tree_palm", "tree_palm_lod", "cactus", "shrub", "bush", "rock_a", "rock_b", "rock_red"}
    sett = {"house_0", "house_1", "house_2", "barn", "gas_station", "diner", "lighthouse", "castle", "wind_turbine", "boat"}
    for n, _ in builders:
        KIT_PARENT[n] = "Nature" if n in nature else ("Settlements" if n in sett else "Roadside")
    res = []
    for n, fn in builders:
        fn()
        cobj = bpy.data.collections["KIT_" + n]
        export_glb(cobj, out_dir + "\\" + n + ".glb")
        res.append((n, sum(len(o.data.polygons) for o in cobj.objects if o.type == "MESH")))
    return res
