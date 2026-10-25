"""Modular prop / nature / building kit for Velora Roads (run inside the project's Blender).

Every prop is built from project-owned procedural geometry, gets materials and UVs, lives in
FORZA_GODOT/<Group>/<name>, and is exported as its own .glb (origin on the ground).
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix, noise
import carkit as ck

PROPS = {}


def prop(group):
    def deco(fn):
        PROPS[fn.__name__] = (group, fn)
        return fn
    return deco


def mat(name, color, metal=0.0, rough=0.7, emission=None, strength=0.0, alpha=1.0):
    return ck.material(name, color, metal, rough, emission=emission, emit_strength=strength, alpha=alpha)


def M():
    return {
        "bark": mat("P_Bark", (0.22, 0.15, 0.1), 0, 0.9),
        "leaf": mat("P_Leaf", (0.2, 0.36, 0.12), 0, 0.8),
        "leaf_dark": mat("P_LeafDark", (0.1, 0.22, 0.1), 0, 0.85),
        "leaf_dry": mat("P_LeafDry", (0.42, 0.42, 0.18), 0, 0.85),
        "rock": mat("P_Rock", (0.36, 0.35, 0.33), 0, 0.9),
        "rock_red": mat("P_RockRed", (0.55, 0.3, 0.18), 0, 0.9),
        "cactus": mat("P_Cactus", (0.24, 0.4, 0.2), 0, 0.7),
        "wall": mat("P_WallWhite", (0.86, 0.83, 0.76), 0, 0.85),
        "wall2": mat("P_WallStone", (0.62, 0.58, 0.5), 0, 0.9),
        "wall3": mat("P_WallYellow", (0.86, 0.72, 0.45), 0, 0.85),
        "roof": mat("P_RoofTile", (0.55, 0.2, 0.12), 0, 0.75),
        "roof2": mat("P_RoofSlate", (0.2, 0.22, 0.25), 0, 0.7),
        "wood": mat("P_Wood", (0.42, 0.28, 0.16), 0, 0.85),
        "barn": mat("P_BarnRed", (0.55, 0.12, 0.08), 0, 0.8),
        "metal": mat("P_Metal", (0.7, 0.72, 0.74), 0.8, 0.35),
        "dark": mat("P_Dark", (0.05, 0.05, 0.06), 0, 0.6),
        "glass": mat("P_Window", (0.15, 0.2, 0.25), 0.3, 0.1),
        "white": mat("P_White", (0.92, 0.92, 0.92), 0, 0.5),
        "red": mat("P_Red", (0.8, 0.1, 0.08), 0, 0.5),
        "yellow": mat("P_Yellow", (0.95, 0.75, 0.1), 0, 0.5),
        "blue": mat("P_Blue", (0.1, 0.3, 0.75), 0, 0.5),
        "concrete": mat("P_Concrete", (0.62, 0.61, 0.58), 0, 0.9),
        "lamp": mat("P_LampGlow", (1.0, 0.85, 0.6), 0, 0.3, emission=(1.0, 0.8, 0.5), strength=3.0),
        "canvas": mat("P_Canvas", (0.95, 0.6, 0.15), 0, 0.8),
        "canvas2": mat("P_Canvas2", (0.15, 0.6, 0.65), 0, 0.8),
        "sign": mat("P_SignGreen", (0.1, 0.4, 0.22), 0, 0.5),
        "sign_white": mat("P_SignWhite", (0.95, 0.95, 0.95), 0, 0.4),
        "chevron": mat("P_Chevron", (0.95, 0.55, 0.05), 0, 0.4),
        "water": mat("P_Hull", (0.15, 0.3, 0.5), 0, 0.5),
    }


# ----------------------------------------------------------------- helpers
def blob(name, radius, coll, material, loc, seed, segs=2, squash=(1, 1, 1), rough=0.25):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=segs, radius=radius)
    random.seed(seed)
    off = Vector((random.random() * 50, random.random() * 50, random.random() * 50))
    for v in bm.verts:
        n = noise.noise(v.co * 1.7 / radius + off)
        v.co *= 1.0 + n * rough
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]
    bmesh.ops.translate(bm, verts=bm.verts, vec=loc)
    ob = ck.new_obj(name, bm, coll, [material])
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def cone(name, r1, r2, h, coll, material, loc=(0, 0, 0), segs=10):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(loc[0], loc[1], loc[2] + h / 2))
    ob = ck.new_obj(name, bm, coll, [material])
    return ob


def gable_roof(name, w, d, h, coll, material, z, overhang=0.35):
    bm = bmesh.new()
    hw = w / 2 + overhang
    hd = d / 2 + overhang
    v = [bm.verts.new(p) for p in [(-hw, -hd, z), (hw, -hd, z), (hw, hd, z), (-hw, hd, z), (0, -hd, z + h), (0, hd, z + h)]]
    bm.faces.new((v[0], v[1], v[4]))
    bm.faces.new((v[3], v[5], v[2]))
    bm.faces.new((v[1], v[2], v[5], v[4]))
    bm.faces.new((v[0], v[4], v[5], v[3]))
    bm.faces.new((v[0], v[3], v[2], v[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    r = bmesh.ops.extrude_face_region(bm, geom=[f for f in bm.faces])
    ob = ck.new_obj(name, bm, coll, [material])
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def box(name, size, loc, coll, material, bevel=0.02):
    return ck.rounded_box(name, size, coll, material, bevel=bevel, segs=1, loc=loc)


def windows(coll, mm, w, d, z0, rows, cols_x, cols_y):
    out = []
    for r in range(rows):
        z = z0 + r * 2.8
        for i in range(cols_x):
            x = -w / 2 + w * (i + 0.5) / cols_x
            for sy in (-1, 1):
                out.append(box("win", (0.8, 0.06, 1.0), (x, sy * (d / 2 + 0.01), z), coll, mm["glass"], 0.01))
                out.append(box("sill", (0.95, 0.12, 0.08), (x, sy * (d / 2 + 0.03), z - 0.55), coll, mm["white"], 0.01))
        for i in range(cols_y):
            y = -d / 2 + d * (i + 0.5) / cols_y
            for sx in (-1, 1):
                out.append(box("win", (0.06, 0.8, 1.0), (sx * (w / 2 + 0.01), y, z), coll, mm["glass"], 0.01))
    return out


# ----------------------------------------------------------------- nature
@prop("Nature")
def tree_broadleaf(coll, mm, seed=1):
    trunk = cone("trunk", 0.32, 0.18, 4.2, coll, mm["bark"], segs=8)
    parts = [trunk]
    random.seed(seed)
    for k in range(5):
        a = k / 5 * math.tau + random.random()
        r = 1.3 + random.random() * 0.6
        parts.append(blob("crown", 2.0 + random.random() * 0.6, coll, mm["leaf"],
                          (math.cos(a) * r, math.sin(a) * r, 5.0 + random.random() * 1.5), seed * 10 + k, squash=(1, 1, 0.8)))
    parts.append(blob("crown", 2.6, coll, mm["leaf"], (0, 0, 6.6), seed * 10 + 7, squash=(1, 1, 0.85)))
    return ck.join(parts, "tree_broadleaf")


@prop("Nature")
def tree_pine(coll, mm, seed=2):
    parts = [cone("trunk", 0.25, 0.1, 9.0, coll, mm["bark"], segs=7)]
    z = 1.8
    r = 2.6
    for k in range(5):
        parts.append(cone("tier", r, 0.05, 3.2, coll, mm["leaf_dark"], loc=(0, 0, z), segs=9))
        z += 1.55
        r *= 0.78
    return ck.join(parts, "tree_pine")


@prop("Nature")
def tree_poplar(coll, mm, seed=3):
    parts = [cone("trunk", 0.2, 0.1, 3.0, coll, mm["bark"], segs=7)]
    parts.append(blob("crown", 1.4, coll, mm["leaf"], (0, 0, 7.0), seed, squash=(1, 1, 3.6), rough=0.15))
    return ck.join(parts, "tree_poplar")


@prop("Nature")
def tree_umbrella(coll, mm, seed=4):
    parts = [cone("trunk", 0.3, 0.16, 5.5, coll, mm["bark"], segs=7)]
    parts.append(blob("crown", 3.2, coll, mm["leaf_dark"], (0.4, 0, 6.6), seed, squash=(1.2, 1.1, 0.4), rough=0.2))
    return ck.join(parts, "tree_umbrella")


@prop("Nature")
def cactus(coll, mm, seed=5):
    parts = [ck.cylinder("stem", 0.28, 3.4, coll, mm["cactus"], loc=(0, 0, 1.7), axis="Z", segs=10)]
    parts.append(blob("top", 0.28, coll, mm["cactus"], (0, 0, 3.4), seed, segs=1, rough=0.05))
    for sx, h in ((1, 1.6), (-1, 2.1)):
        arm = ck.cylinder("arm", 0.18, 0.7, coll, mm["cactus"], loc=(sx * 0.5, 0, h), axis="X", segs=8)
        up = ck.cylinder("armup", 0.18, 1.0, coll, mm["cactus"], loc=(sx * 0.82, 0, h + 0.5), axis="Z", segs=8)
        parts += [arm, up]
    return ck.join(parts, "cactus")


@prop("Nature")
def shrub(coll, mm, seed=6):
    parts = [blob("b", 0.9, coll, mm["leaf"], (0, 0, 0.6), seed, squash=(1.2, 1, 0.75)),
             blob("b", 0.7, coll, mm["leaf"], (0.7, 0.3, 0.5), seed + 1, squash=(1, 1, 0.8))]
    return ck.join(parts, "shrub")


@prop("Nature")
def shrub_dry(coll, mm, seed=7):
    parts = [blob("b", 0.7, coll, mm["leaf_dry"], (0, 0, 0.45), seed, squash=(1.3, 1.1, 0.6), rough=0.4)]
    return ck.join(parts, "shrub_dry")


@prop("Nature")
def rock_a(coll, mm, seed=8):
    return ck.join([blob("r", 1.0, coll, mm["rock"], (0, 0, 0.35), seed, segs=2, squash=(1.3, 1, 0.75), rough=0.35)], "rock_a")


@prop("Nature")
def rock_b(coll, mm, seed=9):
    return ck.join([blob("r", 1.6, coll, mm["rock"], (0, 0, 0.6), seed, segs=2, squash=(1, 1.4, 0.9), rough=0.4),
                    blob("r", 0.8, coll, mm["rock"], (1.3, 0.4, 0.3), seed + 3, segs=1, rough=0.3)], "rock_b")


@prop("Nature")
def rock_red(coll, mm, seed=10):
    return ck.join([blob("r", 1.4, coll, mm["rock_red"], (0, 0, 0.7), seed, segs=2, squash=(1, 1.2, 1.1), rough=0.3)], "rock_red")


# ----------------------------------------------------------------- buildings
@prop("Settlements")
def house_cottage(coll, mm, seed=11):
    w, d, h = 8.0, 6.0, 3.2
    parts = [box("walls", (w, d, h), (0, 0, h / 2), coll, mm["wall"])]
    parts.append(gable_roof("roof", w, d, 2.6, coll, mm["roof"], h))
    parts.append(box("chimney", (0.6, 0.6, 1.8), (2.2, 0.8, h + 1.8), coll, mm["wall2"]))
    parts.append(box("door", (1.0, 0.08, 2.1), (0.0, -d / 2 - 0.02, 1.05), coll, mm["wood"]))
    parts += windows(coll, mm, w, d, 1.6, 1, 3, 2)
    return ck.join(parts, "house_cottage")


@prop("Settlements")
def house_townhouse(coll, mm, seed=12):
    w, d, h = 7.0, 8.0, 6.0
    parts = [box("walls", (w, d, h), (0, 0, h / 2), coll, mm["wall3"])]
    parts.append(gable_roof("roof", w, d, 2.4, coll, mm["roof2"], h))
    parts.append(box("door", (1.1, 0.08, 2.2), (-1.5, -d / 2 - 0.02, 1.1), coll, mm["wood"]))
    parts += windows(coll, mm, w, d, 1.6, 2, 3, 3)
    parts.append(box("base", (w + 0.1, d + 0.1, 0.5), (0, 0, 0.25), coll, mm["wall2"]))
    return ck.join(parts, "house_townhouse")


@prop("Settlements")
def house_farm(coll, mm, seed=13):
    w, d, h = 11.0, 7.0, 4.0
    parts = [box("walls", (w, d, h), (0, 0, h / 2), coll, mm["wall2"])]
    parts.append(gable_roof("roof", w, d, 3.0, coll, mm["roof"], h))
    parts.append(box("porch", (4.0, 2.0, 0.15), (0, -d / 2 - 1.0, 2.6), coll, mm["wood"]))
    for x in (-1.8, 1.8):
        parts.append(box("post", (0.15, 0.15, 2.6), (x, -d / 2 - 1.9, 1.3), coll, mm["wood"]))
    parts.append(box("door", (1.1, 0.08, 2.2), (0, -d / 2 - 0.02, 1.1), coll, mm["wood"]))
    parts += windows(coll, mm, w, d, 1.7, 1, 4, 2)
    return ck.join(parts, "house_farm")


@prop("Settlements")
def barn(coll, mm, seed=14):
    w, d, h = 12.0, 18.0, 6.0
    parts = [box("walls", (w, d, h), (0, 0, h / 2), coll, mm["barn"])]
    parts.append(gable_roof("roof", w, d, 4.0, coll, mm["roof2"], h, overhang=0.5))
    parts.append(box("doors", (5.0, 0.1, 4.6), (0, -d / 2 - 0.03, 2.3), coll, mm["wood"]))
    for x in (-1.25, 1.25):
        parts.append(box("cross", (0.18, 0.12, 6.4), (x, -d / 2 - 0.08, 2.3), coll, mm["white"]))
    return ck.join(parts, "barn")


@prop("Settlements")
def silo(coll, mm, seed=15):
    parts = [ck.cylinder("tube", 2.4, 12.0, coll, mm["metal"], loc=(0, 0, 6.0), axis="Z", segs=24)]
    parts.append(cone("cap", 2.5, 0.3, 1.8, coll, mm["metal"], loc=(0, 0, 12.0), segs=24))
    for z in range(1, 12, 2):
        parts.append(ck.cylinder("ring", 2.45, 0.12, coll, mm["dark"], loc=(0, 0, z), axis="Z", segs=24))
    return ck.join(parts, "silo")


@prop("Settlements")
def gas_station(coll, mm, seed=16):
    parts = [box("canopy", (14.0, 9.0, 0.8), (0, 0, 5.2), coll, mm["white"], 0.05)]
    parts.append(box("canopy_band", (14.1, 9.1, 0.35), (0, 0, 4.85), coll, mm["red"], 0.02))
    for x in (-5.0, 5.0):
        for y in (-3.0, 3.0):
            parts.append(box("column", (0.45, 0.45, 4.8), (x, y, 2.4), coll, mm["white"]))
    for x in (-2.5, 2.5):
        parts.append(box("island", (1.2, 4.0, 0.25), (x, 0, 0.12), coll, mm["concrete"]))
        for y in (-1.0, 1.0):
            parts.append(box("pump", (0.7, 0.5, 1.7), (x, y, 1.1), coll, mm["red"]))
            parts.append(box("pumpface", (0.55, 0.52, 0.5), (x, y, 1.5), coll, mm["dark"]))
    shop = box("shop", (10.0, 7.0, 3.6), (0, 11.0, 1.8), coll, mm["wall"])
    parts.append(shop)
    parts.append(box("shopglass", (6.0, 0.08, 2.2), (0, 7.48, 1.5), coll, mm["glass"]))
    parts.append(box("shoproof", (10.6, 7.6, 0.3), (0, 11.0, 3.75), coll, mm["red"]))
    parts.append(box("lights", (12.0, 0.25, 0.08), (0, 0, 4.78), coll, mm["lamp"]))
    parts.append(box("totem", (0.8, 2.5, 7.5), (8.5, -4.0, 3.75), coll, mm["red"]))
    parts.append(box("totemsign", (0.85, 2.2, 2.0), (8.5, -4.0, 6.0), coll, mm["yellow"]))
    return ck.join(parts, "gas_station")


@prop("Settlements")
def diner(coll, mm, seed=17):
    parts = [box("body", (16.0, 8.0, 3.6), (0, 0, 1.8), coll, mm["metal"], 0.4)]
    parts.append(box("stripe", (16.1, 8.1, 0.5), (0, 0, 1.3), coll, mm["red"], 0.2))
    parts.append(box("glass", (13.0, 0.08, 1.4), (0, -4.02, 2.3), coll, mm["glass"]))
    parts.append(box("roof", (16.6, 8.6, 0.4), (0, 0, 3.8), coll, mm["white"], 0.15))
    parts.append(box("signpost", (0.4, 0.4, 6.0), (9.0, -6.0, 3.0), coll, mm["metal"]))
    parts.append(box("signboard", (0.5, 5.0, 1.8), (9.0, -6.0, 6.3), coll, mm["canvas2"], 0.1))
    parts.append(box("signneon", (0.55, 4.4, 0.25), (9.0, -6.0, 6.3), coll, mm["lamp"], 0.05))
    return ck.join(parts, "diner")


@prop("Landmarks")
def lighthouse(coll, mm, seed=18):
    parts = []
    for i in range(6):
        r = 2.6 - i * 0.22
        parts.append(ck.cylinder("band", r, 3.0, coll, mm["red"] if i % 2 else mm["white"], loc=(0, 0, 1.5 + i * 3.0), axis="Z", segs=24, r2=r - 0.22))
    parts.append(ck.cylinder("gallery", 1.9, 0.35, coll, mm["dark"], loc=(0, 0, 18.2), axis="Z", segs=24))
    parts.append(ck.cylinder("lantern", 1.1, 2.0, coll, mm["lamp"], loc=(0, 0, 19.4), axis="Z", segs=16))
    parts.append(cone("cap", 1.4, 0.2, 1.6, coll, mm["red"], loc=(0, 0, 20.4), segs=16))
    parts.append(box("house", (6.0, 5.0, 3.2), (4.5, 0, 1.6), coll, mm["wall"]))
    parts.append(gable_roof("roof", 6.0, 5.0, 1.8, coll, mm["roof2"], 3.2))
    for ob in parts[-1:]:
        ob.location.x = 4.5
    return ck.join(parts, "lighthouse")


@prop("Landmarks")
def wind_turbine_tower(coll, mm, seed=19):
    parts = [ck.cylinder("tower", 1.6, 60.0, coll, mm["white"], loc=(0, 0, 30.0), axis="Z", segs=16, r2=0.9)]
    parts.append(box("nacelle", (2.0, 6.0, 2.2), (0, 0.8, 61.0), coll, mm["white"], 0.3))
    return ck.join(parts, "wind_turbine_tower")


@prop("Landmarks")
def wind_turbine_rotor(coll, mm, seed=20):
    parts = [blob("hub", 1.1, coll, mm["white"], (0, 0, 0), seed, segs=2, squash=(1, 1.4, 1), rough=0.0)]
    for k in range(3):
        b = box("blade", (1.4, 0.35, 26.0), (0, 0, 13.5), coll, mm["white"], 0.15)
        b.data.transform(Matrix.Rotation(k * math.tau / 3, 4, "Y"))
        parts.append(b)
    return ck.join(parts, "wind_turbine_rotor")


@prop("Landmarks")
def castle_ruin(coll, mm, seed=21):
    random.seed(seed)
    parts = []
    # broken curtain walls on a square, with a round keep
    for i in range(4):
        a = i * math.pi / 2
        for k in range(6):
            t = -12 + k * 4.5
            hgt = 5.0 + random.random() * 4.0 if k not in (2,) else 2.0
            x = math.cos(a) * 14 - math.sin(a) * t
            y = math.sin(a) * 14 + math.cos(a) * t
            seg = box("wall", (1.6, 4.6, hgt), (x, y, hgt / 2), coll, mm["wall2"], 0.1)
            seg.data.transform(Matrix.Translation((x, y, 0)) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Translation((-x, -y, 0)))
            parts.append(seg)
    keep = ck.cylinder("keep", 5.0, 16.0, coll, mm["wall2"], loc=(0, 0, 8.0), axis="Z", segs=20)
    parts.append(keep)
    for k in range(10):
        a = k / 10 * math.tau
        if k % 3 == 0:
            continue
        parts.append(box("merlon", (1.2, 1.0, 1.4), (math.cos(a) * 4.6, math.sin(a) * 4.6, 16.7), coll, mm["wall2"]))
    for k in range(8):
        parts.append(blob("rubble", 1.2, coll, mm["wall2"], (random.uniform(-12, 12), random.uniform(-12, 12), 0.3), seed + k, segs=1, rough=0.4))
    return ck.join(parts, "castle_ruin")


@prop("Roadside")
def bridge_pier(coll, mm, seed=22):
    # unit pier: 10 m wide cap, 20 m tall column; scaled in Godot
    parts = [box("cap", (10.0, 2.0, 1.2), (0, 0, -0.6), coll, mm["concrete"], 0.1)]
    parts.append(box("column", (3.0, 1.8, 20.0), (0, 0, -10.6), coll, mm["concrete"], 0.25))
    parts.append(box("footing", (4.4, 3.0, 1.0), (0, 0, -20.2), coll, mm["concrete"], 0.1))
    return ck.join(parts, "bridge_pier")


@prop("Roadside")
def tunnel_portal(coll, mm, seed=23):
    # facade 11 m wide opening, origin at road level, facing -Y (out of the tunnel)
    parts = []
    w = 5.5
    hgt = 6.8
    for sx in (-1, 1):
        parts.append(box("pylon", (4.0, 1.4, 10.5), (sx * (w + 2.0), 0, 5.25), coll, mm["concrete"], 0.05))
    parts.append(box("lintel", (2 * w + 8.0, 1.4, 3.5), (0, 0, hgt + 1.75), coll, mm["concrete"], 0.05))
    parts.append(box("band", (2 * w + 8.2, 1.5, 0.5), (0, -0.05, hgt + 3.3), coll, mm["chevron"], 0.02))
    for sx in (-1, 1):
        wing = box("wing", (8.0, 1.0, 6.0), (sx * (w + 7.5), 3.0, 3.0), coll, mm["wall2"], 0.05)
        wing.data.transform(Matrix.Translation((sx * (w + 4.0), 0, 0)) @ Matrix.Rotation(sx * -0.5, 4, "Z") @ Matrix.Translation((-sx * (w + 4.0), 0, 0)))
        parts.append(wing)
    return ck.join(parts, "tunnel_portal")


@prop("Roadside")
def sign_chevron(coll, mm, seed=24):
    parts = [box("post", (0.08, 0.08, 1.6), (0, 0, 0.8), coll, mm["metal"], 0.01)]
    parts.append(box("board", (0.8, 0.05, 0.8), (0, 0, 1.75), coll, mm["chevron"], 0.01))
    for k in range(2):
        a = box("arrow", (0.1, 0.06, 0.45), (-0.15 + k * 0.3, -0.02, 1.75), coll, mm["dark"], 0.005)
        a.data.transform(Matrix.Translation((-0.15 + k * 0.3, 0, 1.75)) @ Matrix.Rotation(0.6, 4, "Y") @ Matrix.Translation((0.15 - k * 0.3, 0, -1.75)))
        parts.append(a)
    return ck.join(parts, "sign_chevron")


@prop("Roadside")
def sign_board(coll, mm, seed=25):
    parts = [box("post", (0.12, 0.12, 2.6), (-1.2, 0, 1.3), coll, mm["metal"], 0.01),
             box("post", (0.12, 0.12, 2.6), (1.2, 0, 1.3), coll, mm["metal"], 0.01),
             box("board", (3.2, 0.08, 1.3), (0, 0, 2.4), coll, mm["sign"], 0.02),
             box("frame", (3.3, 0.06, 1.4), (0, 0.02, 2.4), coll, mm["sign_white"], 0.02)]
    return ck.join(parts, "sign_board")


@prop("Roadside")
def lamp_post(coll, mm, seed=26):
    parts = [ck.cylinder("pole", 0.09, 6.5, coll, mm["dark"], loc=(0, 0, 3.25), axis="Z", segs=10, r2=0.06)]
    parts.append(box("arm", (0.08, 1.2, 0.08), (0, 0.55, 6.4), coll, mm["dark"], 0.01))
    parts.append(box("head", (0.35, 0.6, 0.18), (0, 1.1, 6.32), coll, mm["dark"], 0.03))
    parts.append(box("glow", (0.28, 0.5, 0.04), (0, 1.1, 6.21), coll, mm["lamp"], 0.01))
    return ck.join(parts, "lamp_post")


@prop("Roadside")
def fence(coll, mm, seed=27):
    parts = []
    for x in (-2.0, 0.0, 2.0):
        parts.append(box("post", (0.12, 0.12, 1.2), (x, 0, 0.6), coll, mm["wood"], 0.01))
    for z in (0.45, 0.95):
        parts.append(box("rail", (4.2, 0.06, 0.12), (0, 0, z), coll, mm["wood"], 0.01))
    return ck.join(parts, "fence")


@prop("Festival")
def festival_stage(coll, mm, seed=28):
    parts = [box("deck", (18.0, 10.0, 1.4), (0, 0, 0.7), coll, mm["dark"], 0.05)]
    for x in (-8.5, 8.5):
        for y in (-4.5, 4.5):
            parts.append(box("truss", (0.5, 0.5, 9.0), (x, y, 5.9), coll, mm["metal"], 0.02))
    parts.append(box("roof", (19.0, 11.0, 0.6), (0, 0, 10.5), coll, mm["canvas"], 0.2))
    parts.append(box("screen", (10.0, 0.3, 5.0), (0, 4.6, 5.0), coll, mm["lamp"], 0.05))
    parts.append(box("backwall", (18.0, 0.4, 8.5), (0, 4.9, 5.6), coll, mm["dark"], 0.05))
    return ck.join(parts, "festival_stage")


@prop("Festival")
def festival_tent(coll, mm, seed=29):
    parts = [box("base", (6.0, 6.0, 2.4), (0, 0, 1.2), coll, mm["white"], 0.05)]
    parts.append(cone("top", 4.4, 0.1, 2.6, coll, mm["canvas2"], loc=(0, 0, 2.4), segs=4))
    parts[-1].data.transform(Matrix.Rotation(math.pi / 4, 4, "Z"))
    return ck.join(parts, "festival_tent")


@prop("Festival")
def festival_arch(coll, mm, seed=30):
    parts = []
    for sx in (-1, 1):
        parts.append(box("leg", (1.4, 1.4, 8.0), (sx * 8.0, 0, 4.0), coll, mm["canvas"], 0.3))
    parts.append(box("beam", (17.4, 1.6, 2.4), (0, 0, 8.6), coll, mm["canvas"], 0.3))
    parts.append(box("panel", (12.0, 1.7, 1.6), (0, 0, 8.6), coll, mm["dark"], 0.1))
    return ck.join(parts, "festival_arch")


@prop("Festival")
def festival_flag(coll, mm, seed=31):
    parts = [ck.cylinder("pole", 0.07, 9.0, coll, mm["metal"], loc=(0, 0, 4.5), axis="Z", segs=8)]
    parts.append(box("banner", (0.05, 1.3, 4.0), (0, 0.7, 6.4), coll, mm["canvas"], 0.01))
    return ck.join(parts, "festival_flag")


@prop("Landmarks")
def harbour_pier(coll, mm, seed=32):
    parts = [box("deck", (4.0, 40.0, 0.4), (0, 20.0, 1.6), coll, mm["wood"], 0.02)]
    for y in range(0, 41, 5):
        for sx in (-1.8, 1.8):
            parts.append(ck.cylinder("pile", 0.18, 6.0, coll, mm["wood"], loc=(sx, y, -1.0), axis="Z", segs=8))
    return ck.join(parts, "harbour_pier")


@prop("Landmarks")
def boat(coll, mm, seed=33):
    bm = bmesh.new()
    L, W, H = 7.0, 2.4, 1.2
    ring = []
    for i, y in enumerate([-L / 2, -L / 4, 0, L / 4, L / 2]):
        wy = W / 2 * (1.0 - (max(0, y) / (L / 2)) ** 2 * 0.95)
        pts = [(-wy, y, H), (-wy * 0.8, y, H * 0.3), (0, y, 0.0), (wy * 0.8, y, H * 0.3), (wy, y, H)]
        ring.append([bm.verts.new(p) for p in pts])
    for i in range(len(ring) - 1):
        for j in range(4):
            bm.faces.new((ring[i][j], ring[i][j + 1], ring[i + 1][j + 1], ring[i + 1][j]))
    bm.faces.new(list(reversed(ring[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    hull = ck.new_obj("hull", bm, coll, [mm["water"]])
    cabin = box("cabin", (1.6, 2.2, 1.2), (0, -0.8, H + 0.6), coll, mm["white"], 0.1)
    return ck.join([hull, cabin], "boat")


def build_all(only=None):
    mm = M()
    out = {}
    for name, (group, fn) in PROPS.items():
        if only and name not in only:
            continue
        coll = ck.get_coll("FORZA_GODOT/" + group + "/PROP_" + name)
        ck.clear_coll(coll)
        ob = fn(coll, mm)
        ob.name = name
        ob.data.name = name
        ck.uv_project(ob)
        out[name] = (group, sum(len(p.vertices) - 2 for p in ob.data.polygons))
    return out


def export_all(out_dir, only=None):
    import os
    os.makedirs(out_dir, exist_ok=True)
    res = []
    for name, (group, fn) in PROPS.items():
        if only and name not in only:
            continue
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        keep = ob.location.copy()
        ob.location = (0, 0, 0)
        path = os.path.join(out_dir, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False, export_materials="EXPORT")
        ob.location = keep
        res.append((name, os.path.getsize(path)))
    return res
