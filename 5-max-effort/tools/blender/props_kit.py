"""Project-owned prop, building and vegetation kit (Blender, via the verified MCP connection).

Every asset is built from code into FORZA_GODOT/<Category>/PROP_<name> and exported as
assets/imported/props/<name>.glb with its origin on the ground at the asset's centre.
Material names are tags that the Godot side recognises (foliage wind, night windows, lamps);
all other materials are used as authored (base colours exported through glTF).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import kit_common as K

OUT_DIR = os.path.join(K.PROJECT_DIR, "assets", "imported", "props")

MAT_DEFS = {
    "Bark": ((0.27, 0.18, 0.11), 0.0, 0.9), "LeavesConifer": ((0.07, 0.2, 0.07), 0.0, 0.85),
    "LeavesBroad": ((0.17, 0.34, 0.09), 0.0, 0.8), "LeavesPoplar": ((0.2, 0.38, 0.11), 0.0, 0.8),
    "LeavesPine": ((0.13, 0.28, 0.1), 0.0, 0.85), "LeavesDry": ((0.42, 0.38, 0.16), 0.0, 0.85),
    "Rock": ((0.44, 0.42, 0.39), 0.0, 0.9), "RockRed": ((0.56, 0.32, 0.2), 0.0, 0.9),
    "Cactus": ((0.24, 0.4, 0.18), 0.0, 0.7), "LeavesGrass": ((0.24, 0.44, 0.12), 0.0, 0.8),
    "LeavesWheat": ((0.74, 0.6, 0.24), 0.0, 0.8), "FlowerYellow": ((0.95, 0.8, 0.15), 0.0, 0.6),
    "FlowerPurple": ((0.55, 0.25, 0.75), 0.0, 0.6), "FlowerWhite": ((0.95, 0.95, 0.92), 0.0, 0.6),
    "WallPlaster": ((0.88, 0.84, 0.74), 0.0, 0.85), "WallPlasterB": ((0.86, 0.72, 0.52), 0.0, 0.85),
    "WallPlasterC": ((0.72, 0.8, 0.82), 0.0, 0.85), "WallStone": ((0.58, 0.55, 0.49), 0.0, 0.92),
    "WallBrick": ((0.55, 0.26, 0.18), 0.0, 0.9), "WallWood": ((0.46, 0.3, 0.18), 0.0, 0.85),
    "WallRed": ((0.55, 0.12, 0.08), 0.0, 0.8), "RoofTile": ((0.55, 0.22, 0.14), 0.0, 0.75),
    "RoofSlate": ((0.2, 0.22, 0.26), 0.0, 0.7), "RoofMetal": ((0.48, 0.5, 0.53), 0.6, 0.45),
    "WoodDark": ((0.24, 0.15, 0.09), 0.0, 0.8), "WoodLight": ((0.62, 0.47, 0.3), 0.0, 0.8),
    "FrameWhite": ((0.92, 0.92, 0.9), 0.0, 0.6), "WindowGlass": ((0.08, 0.12, 0.16), 0.3, 0.08),
    "Door": ((0.36, 0.2, 0.12), 0.0, 0.6), "Concrete": ((0.63, 0.62, 0.59), 0.0, 0.9),
    "Metal": ((0.62, 0.64, 0.67), 0.85, 0.35), "MetalDark": ((0.14, 0.14, 0.15), 0.6, 0.5),
    "MetalRed": ((0.78, 0.1, 0.08), 0.3, 0.45), "MetalWhite": ((0.9, 0.9, 0.9), 0.3, 0.4),
    "SignWhite": ((0.95, 0.95, 0.95), 0.0, 0.5), "SignRed": ((0.82, 0.06, 0.06), 0.0, 0.5),
    "SignGreen": ((0.03, 0.38, 0.18), 0.0, 0.5), "SignYellow": ((0.96, 0.76, 0.08), 0.0, 0.5),
    "SignBlack": ((0.02, 0.02, 0.02), 0.0, 0.5), "SignBlue": ((0.05, 0.22, 0.6), 0.0, 0.5),
    "Reflector": ((1.0, 0.55, 0.05), 0.0, 0.2), "LampLight": ((1.0, 0.9, 0.7), 0.0, 0.2),
    "FabricRed": ((0.82, 0.14, 0.1), 0.0, 0.9), "FabricBlue": ((0.1, 0.28, 0.75), 0.0, 0.9),
    "FabricYellow": ((0.97, 0.74, 0.12), 0.0, 0.9), "FabricWhite": ((0.94, 0.94, 0.92), 0.0, 0.9),
    "FabricOrange": ((1.0, 0.5, 0.08), 0.0, 0.9), "FabricTeal": ((0.06, 0.62, 0.62), 0.0, 0.9),
    "LedScreen": ((0.05, 0.05, 0.08), 0.0, 0.2), "Rubber": ((0.03, 0.03, 0.03), 0.0, 0.9),
    "Hay": ((0.78, 0.66, 0.34), 0.0, 0.95), "Water": ((0.1, 0.3, 0.4), 0.0, 0.1),
    "PaintBoatWhite": ((0.92, 0.92, 0.9), 0.0, 0.4), "PaintBoatBlue": ((0.1, 0.25, 0.55), 0.0, 0.4),
    "Checker": ((0.9, 0.9, 0.9), 0.0, 0.6), "Asphalt": ((0.15, 0.15, 0.16), 0.0, 0.9),
}


def mat(name):
    c, m, r = MAT_DEFS[name]
    em = None
    es = 0.0
    if name in ("LampLight", "Reflector", "LedScreen"):
        em = c if name != "LedScreen" else (0.2, 0.6, 1.0)
        es = 2.0
    return K.material(name, c, m, r, emission=em, emission_strength=es)


class Asset:
    """Collects bmesh parts per material and builds one object (plus optional extra objects)."""

    def __init__(self, name):
        self.name = name
        self.parts = {}
        self.extra = []

    def add(self, bm, m):
        if m not in self.parts:
            self.parts[m] = bmesh.new()
        K.join_bm(self.parts[m], bm)
        return self

    def build(self, col, smooth=35, name=None):
        out = bmesh.new()
        mats = []
        for i, (m, bm) in enumerate(self.parts.items()):
            K.join_bm(out, bm, i)
            mats.append(mat(m))
        obj = K.mesh_object(name or self.name, out, col, mats)
        K.shade_auto(obj, smooth)
        return obj


# ---------------------------------------------------------------------------------------------
# primitives
def box(size, center=(0, 0, 0), bevel=0.0, rot_z=0.0):
    bm = K.rounded_box_bm(size, (0, 0, 0), bevel, 1 if bevel > 0 else 0) if bevel > 0 else _plain_box(size)
    if rot_z:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot_z, 3, "Z"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def _plain_box(size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return bm


def cyl(r, h, segs=12, center=(0, 0, 0), r2=None, axis="Z", cap=True):
    bm = bmesh.new()
    rot = Matrix.Identity(4)
    if axis == "X":
        rot = Matrix.Rotation(math.radians(90), 4, "Y")
    elif axis == "Y":
        rot = Matrix.Rotation(math.radians(90), 4, "X")
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                          depth=h, matrix=Matrix.Translation(Vector(center)) @ rot)
    return bm


def blob(radius, center, subdiv=1, jitter=0.25, scale=(1, 1, 1), seed=0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    rnd = random.Random(seed)
    off = Vector((rnd.random() * 100, rnd.random() * 100, rnd.random() * 100))
    for v in bm.verts:
        n = noise.noise(v.co * (1.6 / radius) + off)
        v.co *= 1.0 + n * jitter
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def gable_roof(w, l, h, base_z, overhang=0.4, thick=0.18, center=(0, 0)):
    """Prism roof along Y with overhang (two slabs)."""
    bm = bmesh.new()
    hw = w / 2 + overhang
    hl = l / 2 + overhang
    cx, cy = center
    for side in (-1, 1):
        v = [bm.verts.new((cx + side * hw, cy - hl, base_z)), bm.verts.new((cx, cy - hl, base_z + h)),
             bm.verts.new((cx, cy + hl, base_z + h)), bm.verts.new((cx + side * hw, cy + hl, base_z))]
        vt = [bm.verts.new(p.co + Vector((0, 0, thick))) for p in v]
        faces = [(v[0], v[1], v[2], v[3]), (vt[3], vt[2], vt[1], vt[0]), (v[0], v[3], vt[3], vt[0]),
                 (v[1], vt[1], vt[2], v[2]), (v[0], vt[0], vt[1], v[1]), (v[3], v[2], vt[2], vt[3])]
        for f in faces:
            bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def gable_wall(w, l, wall_h, roof_h, center=(0, 0, 0)):
    """Box walls with triangular gable ends (closed mesh)."""
    bm = bmesh.new()
    cx, cy, cz = center
    hw, hl = w / 2, l / 2
    pts = [(-hw, 0), (hw, 0), (hw, wall_h), (0, wall_h + roof_h), (-hw, wall_h)]
    front = [bm.verts.new((cx + x, cy - hl, cz + z)) for x, z in pts]
    back = [bm.verts.new((cx + x, cy + hl, cz + z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def windows_on_wall(asset, axis, plane, centers, size=(1.0, 1.3), depth=0.06, frame=True):
    """Glass panes with frames on a wall plane. axis 'x' -> wall normal along X at x=plane."""
    for c in centers:
        if axis == "x":
            asset.add(box((depth, size[0], size[1]), (plane, c[0], c[1])), "WindowGlass")
            if frame:
                asset.add(box((depth * 1.4, size[0] + 0.14, 0.08), (plane, c[0], c[1] - size[1] / 2 - 0.04)), "FrameWhite")
                asset.add(box((depth * 1.4, size[0] + 0.14, 0.06), (plane, c[0], c[1] + size[1] / 2 + 0.03)), "FrameWhite")
                asset.add(box((depth * 1.2, 0.05, size[1]), (plane, c[0], c[1])), "FrameWhite")
        else:
            asset.add(box((size[0], depth, size[1]), (c[0], plane, c[1])), "WindowGlass")
            if frame:
                asset.add(box((size[0] + 0.14, depth * 1.4, 0.08), (c[0], plane, c[1] - size[1] / 2 - 0.04)), "FrameWhite")
                asset.add(box((size[0] + 0.14, depth * 1.4, 0.06), (c[0], plane, c[1] + size[1] / 2 + 0.03)), "FrameWhite")
                asset.add(box((0.05, depth * 1.2, size[1]), (c[0], plane, c[1])), "FrameWhite")


# ---------------------------------------------------------------------------------------------
# nature
def tree_conifer(a, seed=1, h=11.0):
    rnd = random.Random(seed)
    a.add(cyl(0.28, h * 0.45, 7, (0, 0, h * 0.22), r2=0.12), "Bark")
    tiers = 6
    for t in range(tiers):
        f = t / (tiers - 1)
        r = 2.7 * (1 - f) + 0.55
        z = h * 0.18 + f * h * 0.68
        cone = cyl(r, h * 0.26, 9, (0, 0, z), r2=0.05)
        for v in cone.verts:
            if v.co.z < z - h * 0.1:
                v.co.x += (rnd.random() - 0.5) * 0.35
                v.co.y += (rnd.random() - 0.5) * 0.35
                v.co.z -= rnd.random() * 0.3
        bmesh.ops.rotate(cone, cent=(0, 0, z), matrix=Matrix.Rotation(rnd.random() * 3.0, 3, "Z"), verts=cone.verts)
        a.add(cone, "LeavesConifer")


def tree_broadleaf(a, seed=2):
    rnd = random.Random(seed)
    a.add(cyl(0.34, 4.2, 8, (0, 0, 2.1), r2=0.22), "Bark")
    for k in range(3):
        ang = k * 2.1 + rnd.random()
        br = cyl(0.12, 2.4, 6, (0, 0, 1.2), r2=0.06)
        bmesh.ops.rotate(br, cent=(0, 0, 0), matrix=Matrix.Rotation(0.75, 3, "X"), verts=br.verts)
        bmesh.ops.rotate(br, cent=(0, 0, 0), matrix=Matrix.Rotation(ang, 3, "Z"), verts=br.verts)
        bmesh.ops.translate(br, vec=(0, 0, 3.2), verts=br.verts)
        a.add(br, "Bark")
    centers = [(0, 0, 6.2, 2.6), (1.6, 0.4, 5.3, 1.9), (-1.5, 0.6, 5.4, 2.0), (0.3, -1.6, 5.2, 1.9),
               (-0.4, 1.5, 5.6, 1.8), (0.8, 0.9, 7.0, 1.6), (-0.9, -0.8, 6.6, 1.7)]
    for i, (x, y, z, r) in enumerate(centers):
        a.add(blob(r, (x, y, z), 2, 0.3, (1, 1, 0.82), seed * 10 + i), "LeavesBroad")


def tree_poplar(a, seed=3):
    a.add(cyl(0.22, 3.0, 7, (0, 0, 1.5), r2=0.14), "Bark")
    a.add(blob(1.0, (0, 0, 7.5), 3, 0.16, (1.25, 1.25, 5.2), seed), "LeavesPoplar")


def tree_umbrella_pine(a, seed=4):
    rnd = random.Random(seed)
    trunk = cyl(0.3, 6.5, 7, (0, 0, 3.25), r2=0.18)
    for v in trunk.verts:
        v.co.x += (v.co.z / 6.5) ** 2 * 0.9
    a.add(trunk, "Bark")
    for i, (x, y, z, r) in enumerate([(0.9, 0, 7.2, 3.0), (2.4, 0.8, 6.8, 2.0), (-0.6, -1.2, 6.9, 2.1)]):
        a.add(blob(r, (x, y, z), 2, 0.22, (1.25, 1.25, 0.42), seed * 7 + i), "LeavesPine")


def bush(a, seed=5, mat_name="LeavesBroad"):
    rnd = random.Random(seed)
    for i in range(3):
        a.add(blob(0.75 + rnd.random() * 0.3, ((rnd.random() - 0.5) * 1.1, (rnd.random() - 0.5) * 1.1, 0.55),
                   2, 0.3, (1, 1, 0.8), seed * 3 + i), mat_name)


def rock(a, seed=6, mat_name="Rock", scale=(1.6, 1.2, 0.9)):
    a.add(blob(1.0, (0, 0, 0.35), 3, 0.4, scale, seed), mat_name)


def cactus(a, seed=7):
    a.add(cyl(0.32, 5.2, 8, (0, 0, 2.6)), "Cactus")
    a.add(blob(0.32, (0, 0, 5.2), 1, 0.05), "Cactus")
    for side, (hz, ah) in ((1, (2.2, 1.6)), (-1, (2.9, 1.3))):
        arm = cyl(0.22, 0.7, 8, (side * 0.55, 0, hz), axis="X")
        a.add(arm, "Cactus")
        a.add(cyl(0.22, ah, 8, (side * 0.9, 0, hz + ah / 2)), "Cactus")
        a.add(blob(0.22, (side * 0.9, 0, hz + ah), 1, 0.05), "Cactus")


def dead_tree(a, seed=8):
    rnd = random.Random(seed)
    a.add(cyl(0.22, 4.0, 6, (0, 0, 2.0), r2=0.1), "Bark")
    for k in range(5):
        br = cyl(0.07, 1.8, 5, (0, 0, 0.9), r2=0.02)
        bmesh.ops.rotate(br, cent=(0, 0, 0), matrix=Matrix.Rotation(0.6 + rnd.random() * 0.5, 3, "X"), verts=br.verts)
        bmesh.ops.rotate(br, cent=(0, 0, 0), matrix=Matrix.Rotation(rnd.random() * 6.28, 3, "Z"), verts=br.verts)
        bmesh.ops.translate(br, vec=(0, 0, 2.2 + k * 0.4), verts=br.verts)
        a.add(br, "Bark")


def grass_clump(a, seed=9, mat_name="LeavesGrass", blades=9, height=0.7):
    rnd = random.Random(seed)
    bm = bmesh.new()
    for i in range(blades):
        ang = rnd.random() * math.tau
        r = rnd.random() * 0.25
        x, y = math.cos(ang) * r, math.sin(ang) * r
        lean = Vector((math.cos(ang), math.sin(ang), 0)) * (0.15 + rnd.random() * 0.2)
        hgt = height * (0.6 + rnd.random() * 0.6)
        side = Vector((-math.sin(ang), math.cos(ang), 0)) * 0.045
        p0 = Vector((x, y, 0))
        v1 = bm.verts.new(p0 - side)
        v2 = bm.verts.new(p0 + side)
        v3 = bm.verts.new(p0 + lean * 0.5 + side * 0.6 + Vector((0, 0, hgt * 0.55)))
        v4 = bm.verts.new(p0 + lean * 0.5 - side * 0.6 + Vector((0, 0, hgt * 0.55)))
        v5 = bm.verts.new(p0 + lean + Vector((0, 0, hgt)))
        bm.faces.new((v1, v2, v3, v4))
        bm.faces.new((v4, v3, v5))
    a.add(bm, mat_name)


def flowers(a, seed=10):
    grass_clump(a, seed, "LeavesGrass", 6, 0.45)
    rnd = random.Random(seed)
    for i in range(5):
        c = (rnd.random() - 0.5) * 0.5, (rnd.random() - 0.5) * 0.5, 0.42 + rnd.random() * 0.15
        a.add(blob(0.06, c, 1, 0.0), ["FlowerYellow", "FlowerPurple", "FlowerWhite"][i % 3])


def hay_bale(a):
    a.add(cyl(0.75, 1.2, 14, (0, 0, 0.75), axis="X"), "Hay")


# ---------------------------------------------------------------------------------------------
# buildings
def house(a, w=8.0, l=6.5, wall_h=5.4, roof_h=2.6, wall="WallPlaster", roof="RoofTile", storeys=2, seed=11, chimney=True):
    a.add(box((w + 0.3, l + 0.3, 0.5), (0, 0, 0.25)), "Concrete")
    a.add(gable_wall(w, l, wall_h, roof_h, (0, 0, 0.45)), wall)
    a.add(gable_roof(w, l, roof_h + 0.05, wall_h + 0.45, 0.45, 0.2), roof)
    if chimney:
        a.add(box((0.7, 0.7, 2.4), (w * 0.25, l * 0.2, wall_h + roof_h * 0.6)), "WallBrick")
    # windows on the long walls (x = +-w/2), doors on the front (y = -l/2)
    rows = [1.6, 4.0] if storeys == 2 else [1.7]
    for side in (-1, 1):
        cs = []
        for z in rows:
            for yy in (-l * 0.28, l * 0.28):
                cs.append((yy, z + 0.45))
        windows_on_wall(a, "x", side * (w / 2 + 0.02), cs)
    fc = [(-w * 0.28, rows[-1] + 0.45)] + ([(w * 0.28, rows[-1] + 0.45)] if storeys == 2 else [(w * 0.3, 1.9)])
    windows_on_wall(a, "y", -(l / 2 + 0.02), fc)
    a.add(box((1.1, 0.12, 2.15), (w * 0.1 if storeys == 1 else 0.0, -(l / 2 + 0.03), 1.55)), "Door")
    a.add(box((1.6, 1.2, 0.18), (w * 0.1 if storeys == 1 else 0.0, -(l / 2 + 0.6), 0.5)), "Concrete")
    windows_on_wall(a, "y", (l / 2 + 0.02), [(0.0, rows[-1] + 0.45)])


def church(a):
    house(a, 9.0, 16.0, 7.5, 4.0, "WallStone", "RoofSlate", 1, chimney=False)
    a.add(box((4.4, 4.4, 15.0), (0, -10.2, 7.5)), "WallStone")
    tower_top = 15.0
    sp = bmesh.new()
    bmesh.ops.create_cone(sp, cap_ends=True, segments=4, radius1=3.2, radius2=0.05, depth=8.0,
                          matrix=Matrix.Translation((0, -10.2, tower_top + 4.0)) @ Matrix.Rotation(math.pi / 4, 4, "Z"))
    a.add(sp, "RoofSlate")
    windows_on_wall(a, "y", -12.42, [(0.0, 11.0)], (1.0, 1.8))
    a.add(cyl(0.8, 0.1, 16, (0, -12.43, 11.0), axis="Y"), "FrameWhite")
    a.add(box((1.6, 0.14, 2.8), (0, -12.42, 1.9)), "Door")


def barn(a):
    w, l, wall_h = 11.0, 15.0, 4.8
    a.add(box((w + 0.3, l + 0.3, 0.4), (0, 0, 0.2)), "Concrete")
    a.add(box((w, l, wall_h), (0, 0, wall_h / 2 + 0.3)), "WallRed")
    # gambrel roof as two stacked gable sections
    a.add(gable_roof(w, l, 1.6, wall_h + 0.3, 0.5, 0.18), "RoofMetal")
    a.add(gable_roof(w * 0.58, l, 2.6, wall_h + 1.55, 0.35, 0.18), "RoofMetal")
    a.add(gable_wall(w, l - 0.02, 0.01, 4.0, (0, 0, wall_h + 0.3)), "WallRed")
    for yy in (-(l / 2 + 0.03), l / 2 + 0.03):
        a.add(box((4.2, 0.12, 3.8), (0, yy, 2.2)), "WallWood")
        for sgn in (-1, 1):
            d = box((5.4, 0.08, 0.16), (0, yy + 0.04 * (1 if yy > 0 else -1), 2.2))
            bmesh.ops.rotate(d, cent=(0, yy, 2.2), matrix=Matrix.Rotation(sgn * 0.74, 3, "Y"), verts=d.verts)
            a.add(d, "FrameWhite")
        a.add(box((4.4, 0.1, 0.16), (0, yy, 4.15)), "FrameWhite")
        a.add(box((1.4, 0.1, 1.2), (0, yy, 6.0)), "WallWood")


def silo(a):
    a.add(cyl(2.6, 13.0, 20, (0, 0, 6.5)), "Metal")
    dome = bmesh.new()
    bmesh.ops.create_uvsphere(dome, u_segments=20, v_segments=8, radius=2.6, matrix=Matrix.Translation((0, 0, 13.0)))
    bmesh.ops.delete(dome, geom=[v for v in dome.verts if v.co.z < 12.95], context="VERTS")
    a.add(dome, "Metal")
    for z in range(1, 13, 2):
        a.add(cyl(2.64, 0.12, 20, (0, 0, float(z))), "MetalDark")
    a.add(box((0.5, 0.2, 13.0), (0, -2.7, 6.5)), "MetalDark")


def shop(a):
    w, l, h = 9.0, 7.5, 4.2
    a.add(box((w + 0.3, l + 0.3, 0.4), (0, 0, 0.2)), "Concrete")
    a.add(box((w, l, h), (0, 0, h / 2 + 0.35)), "WallPlasterB")
    a.add(box((w + 0.2, l + 0.2, 0.5), (0, 0, h + 0.6)), "WallBrick")
    a.add(box((w * 0.7, 0.08, 2.2), (-0.6, -(l / 2 + 0.03), 1.75)), "WindowGlass")
    a.add(box((1.2, 0.1, 2.3), (w * 0.38, -(l / 2 + 0.04), 1.5)), "Door")
    aw = box((w + 0.4, 1.6, 0.12), (0, -(l / 2 + 0.8), 3.4))
    bmesh.ops.rotate(aw, cent=(0, -(l / 2), 3.4), matrix=Matrix.Rotation(-0.22, 3, "X"), verts=aw.verts)
    a.add(aw, "FabricRed")
    a.add(box((w * 0.6, 0.15, 0.8), (0, -(l / 2 + 0.09), 4.0)), "SignWhite")
    windows_on_wall(a, "x", w / 2 + 0.02, [(0.0, 2.2)])


def gas_station(a):
    # canopy on four posts, two pump islands, kiosk diner and price pylon
    a.add(box((16.0, 10.0, 0.7), (0, 0, 5.4)), "MetalWhite")
    a.add(box((16.2, 10.2, 0.25), (0, 0, 5.0)), "MetalRed")
    for x in (-5.5, 5.5):
        for y in (-3.0, 3.0):
            a.add(box((0.45, 0.45, 5.0), (x, y, 2.5)), "MetalWhite")
    for y in (-2.5, 2.5):
        a.add(box((5.0, 1.2, 0.25), (0, y, 0.12)), "Concrete")
        for x in (-1.4, 1.4):
            a.add(box((0.7, 0.5, 1.7), (x, y, 1.1)), "MetalRed")
            a.add(box((0.6, 0.52, 0.5), (x, y, 1.55)), "LedScreen")
    a.add(box((18.0, 14.0, 0.1), (0, 0, 0.05)), "Concrete")
    # kiosk / diner
    a.add(box((10.0, 6.0, 3.8), (0, 9.0, 1.9)), "WallPlaster")
    a.add(box((10.4, 6.4, 0.4), (0, 9.0, 4.0)), "MetalRed")
    a.add(box((8.0, 0.08, 2.1), (0, 5.97, 1.6)), "WindowGlass")
    a.add(box((4.0, 0.12, 0.7), (0, 5.9, 4.6)), "SignWhite")
    # price pylon
    a.add(box((0.4, 0.4, 7.0), (9.5, -6.0, 3.5)), "MetalWhite")
    a.add(box((2.4, 0.4, 2.8), (9.5, -6.0, 7.6)), "MetalRed")
    a.add(box((2.0, 0.45, 1.6), (9.5, -6.0, 7.4)), "LedScreen")


def boathouse(a):
    house(a, 7.0, 9.0, 3.4, 2.2, "WallWood", "RoofSlate", 1, chimney=False)


def pier(a):
    a.add(box((4.0, 34.0, 0.3), (0, 0, 1.2)), "WoodLight")
    for y in range(-16, 17, 4):
        for x in (-1.8, 1.8):
            a.add(cyl(0.16, 4.0, 6, (x, float(y), -0.6)), "WoodDark")
    for x in (-1.95, 1.95):
        a.add(box((0.1, 34.0, 0.1), (x, 0, 2.2)), "WoodDark")
        for y in range(-16, 17, 4):
            a.add(box((0.1, 0.1, 1.0), (x, float(y), 1.75)), "WoodDark")


def boat(a):
    hull = bmesh.new()
    prof = [(-3.2, 0.0), (-3.0, 1.2), (2.0, 1.25), (3.6, 0.0)]
    rows = []
    for (y, hw) in prof:
        rows.append([hull.verts.new((-hw, y, 1.3)), hull.verts.new((-hw * 0.6, y, 0.0)), hull.verts.new((0, y, -0.3)),
                     hull.verts.new((hw * 0.6, y, 0.0)), hull.verts.new((hw, y, 1.3))])
    for i in range(len(rows) - 1):
        for j in range(4):
            hull.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]))
    hull.faces.new(list(reversed(rows[0])))
    hull.faces.new(rows[-1])
    deck = [hull.verts.new((v.co.x, v.co.y, 1.3)) for v in []]
    bmesh.ops.recalc_face_normals(hull, faces=hull.faces)
    a.add(hull, "PaintBoatWhite")
    a.add(box((2.3, 6.2, 0.12), (0, -0.2, 1.2)), "WoodLight")
    a.add(box((1.8, 2.0, 1.6), (0, -0.8, 2.0)), "PaintBoatBlue")
    a.add(box((1.85, 0.06, 0.6), (0, 0.22, 2.3)), "WindowGlass")
    a.add(cyl(0.06, 3.0, 6, (0, -0.8, 3.9)), "Metal")


def lighthouse(a):
    for i in range(6):
        z0 = i * 3.6
        r0 = 3.1 - i * 0.16
        a.add(cyl(r0, 3.6, 20, (0, 0, z0 + 1.8), r2=r0 - 0.16), "MetalRed" if i % 2 == 0 else "MetalWhite")
    top = 21.6
    a.add(cyl(2.9, 0.35, 20, (0, 0, top + 0.18)), "MetalDark")
    for k in range(16):
        ang = k * math.tau / 16
        a.add(box((0.06, 0.06, 1.0), (math.cos(ang) * 2.75, math.sin(ang) * 2.75, top + 0.85)), "MetalDark")
    a.add(cyl(2.8, 0.06, 20, (0, 0, top + 1.35)), "MetalDark")
    a.add(cyl(1.6, 2.4, 16, (0, 0, top + 1.55)), "WindowGlass")
    a.add(cyl(0.8, 1.2, 12, (0, 0, top + 1.45)), "LampLight")
    dome = bmesh.new()
    bmesh.ops.create_uvsphere(dome, u_segments=16, v_segments=8, radius=1.8, matrix=Matrix.Translation((0, 0, top + 2.75)))
    bmesh.ops.delete(dome, geom=[v for v in dome.verts if v.co.z < top + 2.7], context="VERTS")
    a.add(dome, "MetalRed")
    windows_on_wall(a, "y", -3.0, [(0.0, 6.0), (0.0, 12.0)], (0.7, 1.1))
    a.add(box((1.1, 0.2, 2.1), (0, -3.05, 1.05)), "Door")
    # keeper's cottage
    cot = Asset("tmp")
    house(cot, 6.0, 5.0, 3.2, 2.0, "WallPlaster", "RoofSlate", 1, chimney=True)
    for m, bm in cot.parts.items():
        bmesh.ops.translate(bm, vec=(7.5, 2.0, 0), verts=bm.verts)
        a.add(bm, m)


def castle_ruin(a, seed=12):
    rnd = random.Random(seed)
    corners = [(-14, -11), (14, -11), (14, 11), (-14, 11)]
    for i in range(4):
        x0, y0 = corners[i]
        x1, y1 = corners[(i + 1) % 4]
        seg_n = 6
        for s in range(seg_n):
            if i == 0 and s in (2, 3):
                continue  # gate gap
            t0 = s / seg_n
            t1 = (s + 1) / seg_n
            cx = x0 + (x1 - x0) * (t0 + t1) / 2
            cy = y0 + (y1 - y0) * (t0 + t1) / 2
            length = math.hypot(x1 - x0, y1 - y0) / seg_n
            h = 6.5 if rnd.random() > 0.3 else rnd.uniform(2.0, 5.0)
            horiz = abs(x1 - x0) > abs(y1 - y0)
            size = (length + 0.05, 1.8, h) if horiz else (1.8, length + 0.05, h)
            a.add(box(size, (cx, cy, h / 2)), "WallStone")
            if h > 6.0:
                for m in range(3):
                    off = (m - 1) * length / 3
                    mc = (cx + off, cy, h + 0.45) if horiz else (cx, cy + off, h + 0.45)
                    a.add(box((0.9, 1.8, 0.9) if horiz else (1.8, 0.9, 0.9), mc), "WallStone")
    for (x, y) in corners:
        th = rnd.uniform(8.0, 12.0)
        a.add(cyl(3.0, th, 14, (x, y, th / 2)), "WallStone")
        for m in range(8):
            ang = m * math.tau / 8
            a.add(box((0.9, 0.9, 0.9), (x + math.cos(ang) * 2.7, y + math.sin(ang) * 2.7, th + 0.45)), "WallStone")
    a.add(box((5.2, 2.4, 1.2), (0, -11, 6.0)), "WallStone")
    for k in range(10):
        a.add(blob(rnd.uniform(0.5, 1.2), (rnd.uniform(-12, 12), rnd.uniform(-9, 9), 0.2), 1, 0.4, (1, 1, 0.6), seed + k), "WallStone")


def wind_turbine_parts(col):
    a = Asset("wind_turbine")
    a.add(cyl(2.1, 62.0, 18, (0, 0, 31.0), r2=1.25), "MetalWhite")
    a.add(cyl(3.0, 0.6, 18, (0, 0, 0.3)), "Concrete")
    a.add(box((3.2, 9.0, 3.4), (0, 0.9, 63.2), 0.5), "MetalWhite")
    tower = a.build(col)
    r = Asset("Rotor")
    hub = cyl(1.0, 2.2, 14, (0, 0, 0), r2=0.15, axis="Y")
    r.add(hub, "MetalWhite")
    for k in range(3):
        bl = box((1.6, 0.3, 30.0), (0, 0, 15.5))
        for v in bl.verts:
            t = v.co.z / 30.0
            v.co.x *= 1.0 - 0.8 * t
        bmesh.ops.rotate(bl, cent=(0, 0, 0), matrix=Matrix.Rotation(k * math.tau / 3, 3, "Y"), verts=bl.verts)
        r.add(bl, "MetalWhite")
    rotor = r.build(col, name="Rotor")
    rotor.location = (0, -4.4, 63.2)
    return [tower, rotor]


# ---------------------------------------------------------------------------------------------
# roadside
def street_lamp(a):
    a.add(cyl(0.11, 6.6, 8, (0, 0, 3.3), r2=0.07), "MetalDark")
    arm = box((0.08, 1.6, 0.08), (0, -0.75, 6.5))
    a.add(arm, "MetalDark")
    a.add(box((0.45, 0.7, 0.18), (0, -1.5, 6.38), 0.04), "MetalDark")
    a.add(box((0.36, 0.58, 0.05), (0, -1.5, 6.27)), "LampLight")
    a.add(cyl(0.22, 0.4, 8, (0, 0, 0.2)), "Concrete")


def reflector_post(a):
    a.add(box((0.12, 0.12, 1.1), (0, 0, 0.55)), "SignWhite")
    a.add(box((0.125, 0.125, 0.22), (0, 0, 0.88)), "SignBlack")
    a.add(box((0.05, 0.13, 0.12), (0, 0, 0.88)), "Reflector")


def _post(a, h=2.2, x=0.0):
    a.add(cyl(0.04, h, 8, (x, 0.05, h / 2)), "Metal")


def chevron(a):
    _post(a, 1.4)
    a.add(box((0.8, 0.04, 0.6), (0, 0, 1.6)), "SignBlack")
    for k in range(2):
        for sgn in (-1, 1):
            st = box((0.32, 0.05, 0.07), (0, -0.01, 1.6))
            bmesh.ops.rotate(st, cent=(0, 0, 1.6), matrix=Matrix.Rotation(sgn * 0.7, 3, "Y"), verts=st.verts)
            bmesh.ops.translate(st, vec=(-0.15 + k * 0.28 + 0.06, 0, sgn * 0.09), verts=st.verts)
            a.add(st, "SignYellow")


def sign_triangle(a, curve_dir=1):
    _post(a, 1.6)
    tri = bmesh.new()
    pts = [(-0.55, 1.45), (0.55, 1.45), (0.0, 2.4)]
    vs = [tri.verts.new((x, 0.0, z)) for x, z in pts]
    vs2 = [tri.verts.new((x, 0.03, z)) for x, z in pts]
    tri.faces.new(vs)
    tri.faces.new(list(reversed(vs2)))
    for i in range(3):
        tri.faces.new((vs[i], vs[(i + 1) % 3], vs2[(i + 1) % 3], vs2[i]))
    bmesh.ops.recalc_face_normals(tri, faces=tri.faces)
    a.add(tri, "SignRed")
    inner = bmesh.new()
    pts2 = [(-0.4, 1.55), (0.4, 1.55), (0.0, 2.22)]
    v3 = [inner.verts.new((x, -0.01, z)) for x, z in pts2]
    inner.faces.new(v3)
    a.add(inner, "SignWhite")
    a.add(box((0.06, 0.02, 0.3), (-0.04 * curve_dir, -0.02, 1.72)), "SignBlack")
    arc = box((0.24, 0.02, 0.06), (0.08 * curve_dir, -0.02, 1.88))
    bmesh.ops.rotate(arc, cent=(0, -0.02, 1.88), matrix=Matrix.Rotation(-0.5 * curve_dir, 3, "Y"), verts=arc.verts)
    a.add(arc, "SignBlack")


def sign_speed(a):
    _post(a, 1.8)
    a.add(cyl(0.38, 0.04, 24, (0, 0, 2.15), axis="Y"), "SignRed")
    a.add(cyl(0.3, 0.05, 24, (0, -0.01, 2.15), axis="Y"), "SignWhite")


def sign_route(a):
    _post(a, 2.6, -0.9)
    _post(a, 2.6, 0.9)
    a.add(box((2.6, 0.06, 1.0), (0, 0, 2.6)), "SignGreen")
    a.add(box((2.5, 0.065, 0.9), (0, -0.002, 2.6)), "SignGreen")
    a.add(box((2.62, 0.05, 0.03), (0, -0.01, 3.08)), "SignWhite")
    a.add(box((2.62, 0.05, 0.03), (0, -0.01, 2.12)), "SignWhite")


def sign_region(a):
    for x in (-1.6, 1.6):
        a.add(box((0.2, 0.2, 3.0), (x, 0, 1.5)), "WoodDark")
    a.add(box((3.8, 0.12, 1.4), (0, 0, 2.6)), "WoodLight")
    a.add(box((3.9, 0.14, 0.12), (0, 0, 3.35)), "WoodDark")


def fence_wood(a):
    for x in (-2.0, 0.0, 2.0):
        a.add(box((0.12, 0.12, 1.2), (x, 0, 0.6)), "WoodDark")
    for z in (0.45, 0.95):
        a.add(box((4.1, 0.06, 0.14), (0, 0, z)), "WoodLight")


def wall_stone(a, seed=13):
    rnd = random.Random(seed)
    a.add(box((4.0, 0.55, 0.95), (0, 0, 0.47)), "WallStone")
    for k in range(5):
        a.add(blob(0.24, (-1.7 + k * 0.85, 0, 1.0), 1, 0.2, (1.4, 1.0, 0.6), seed + k), "WallStone")


def viewpoint(a):
    a.add(box((2.0, 0.5, 0.1), (0, 0, 0.5)), "WoodLight")
    a.add(box((2.0, 0.08, 0.5), (0, 0.22, 0.8)), "WoodLight")
    for x in (-0.85, 0.85):
        a.add(box((0.1, 0.45, 0.5), (x, 0, 0.25)), "MetalDark")
    a.add(cyl(0.06, 1.3, 8, (2.2, 0, 0.65)), "MetalDark")
    a.add(cyl(0.12, 0.5, 10, (2.2, 0.1, 1.4), axis="Y"), "Metal")
    a.add(box((1.2, 0.08, 0.8), (-2.4, 0, 1.3)), "SignBlue")
    a.add(box((0.08, 0.08, 1.2), (-2.4, 0.05, 0.6)), "MetalDark")


# ---------------------------------------------------------------------------------------------
# festival and activities
def festival_stage(a):
    a.add(box((18.0, 10.0, 1.3), (0, 0, 0.65)), "MetalDark")
    for x in (-8.5, 8.5):
        for y in (-4.5, 4.5):
            a.add(box((0.4, 0.4, 9.0), (x, y, 5.8)), "Metal")
    for y in (-4.5, 4.5):
        a.add(box((17.4, 0.4, 0.5), (0, y, 10.2)), "Metal")
    a.add(box((18.4, 10.6, 0.25), (0, 0, 10.6)), "FabricWhite")
    a.add(box((14.0, 0.3, 6.0), (0, 4.4, 5.0)), "LedScreen")
    for x in (-7.8, 7.8):
        a.add(box((1.4, 1.2, 3.6), (x, -3.5, 3.1)), "MetalDark")
    a.add(box((18.2, 0.1, 1.2), (0, -5.0, 9.6)), "FabricOrange")


def festival_tent(a):
    a.add(box((6.0, 6.0, 0.1), (0, 0, 0.05)), "WoodLight")
    for x in (-2.8, 2.8):
        for y in (-2.8, 2.8):
            a.add(cyl(0.06, 2.6, 6, (x, y, 1.3)), "Metal")
    roof = bmesh.new()
    bmesh.ops.create_cone(roof, cap_ends=True, segments=4, radius1=4.3, radius2=0.05, depth=2.4,
                          matrix=Matrix.Translation((0, 0, 3.8)) @ Matrix.Rotation(math.pi / 4, 4, "Z"))
    a.add(roof, "FabricWhite")
    a.add(box((6.1, 0.05, 0.5), (0, -3.0, 2.45)), "FabricRed")
    a.add(box((6.1, 0.05, 0.5), (0, 3.0, 2.45)), "FabricRed")
    a.add(box((2.4, 1.0, 0.95), (0, 1.0, 0.5)), "WoodLight")


def festival_flag(a):
    a.add(cyl(0.07, 9.0, 8, (0, 0, 4.5)), "MetalWhite")
    a.add(box((0.04, 1.4, 4.2), (0, 0.72, 6.5)), "FabricOrange")
    a.add(box((0.045, 1.4, 0.4), (0, 0.72, 4.3)), "FabricTeal")


def festival_arch(a):
    segs = 18
    for k in range(segs):
        t0 = math.pi * k / segs
        t1 = math.pi * (k + 1) / segs
        a0 = (math.cos(t0) * 9.0, math.sin(t0) * 8.0)
        a1 = (math.cos(t1) * 9.0, math.sin(t1) * 8.0)
        cx, cz = (a0[0] + a1[0]) / 2, (a0[1] + a1[1]) / 2
        ln = math.hypot(a1[0] - a0[0], a1[1] - a0[1])
        seg = box((ln + 0.1, 1.6, 1.6), (0, 0, 0), 0.6)
        ang = math.atan2(a1[1] - a0[1], a1[0] - a0[0])
        bmesh.ops.rotate(seg, cent=(0, 0, 0), matrix=Matrix.Rotation(-ang, 3, "Y"), verts=seg.verts)
        bmesh.ops.translate(seg, vec=(cx, 0, cz), verts=seg.verts)
        a.add(seg, "FabricOrange" if k % 2 == 0 else "FabricTeal")
    a.add(box((8.0, 0.2, 1.6), (0, -0.85, 6.8)), "FabricWhite")


def ramp_jump(a):
    w, l, h = 6.0, 13.0, 2.3
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in [(-w / 2, l / 2, 0), (w / 2, l / 2, 0), (w / 2, -l / 2, h), (-w / 2, -l / 2, h),
                                    (-w / 2, -l / 2, 0), (w / 2, -l / 2, 0)]]
    bm.faces.new((v[0], v[1], v[2], v[3]))
    bm.faces.new((v[3], v[2], v[5], v[4]))
    bm.faces.new((v[0], v[3], v[4]))
    bm.faces.new((v[1], v[5], v[2]))
    bm.faces.new((v[0], v[4], v[5], v[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    a.add(bm, "WoodLight")
    for k in range(6):
        y = l / 2 - (k + 0.5) * (l / 6)
        z = h * (k + 0.5) / 6 + 0.02
        a.add(box((w, 0.25, 0.04), (0, y, z), 0.0), "SignYellow" if k % 2 == 0 else "SignBlack")
    for x in (-w / 2 - 0.1, w / 2 + 0.1):
        rail = box((0.12, l, 0.12), (x, 0, h / 2 + 0.5))
        bmesh.ops.rotate(rail, cent=(x, 0, h / 2 + 0.5), matrix=Matrix.Rotation(-math.atan2(h, l), 3, "X"), verts=rail.verts)
        a.add(rail, "MetalRed")


def checkpoint_gate(a):
    for x in (-6.5, 6.5):
        a.add(box((0.8, 0.8, 6.5), (x, 0, 3.25), 0.2), "FabricOrange")
    a.add(box((14.0, 0.6, 1.4), (0, 0, 6.3), 0.2), "FabricTeal")
    a.add(box((12.0, 0.65, 0.3), (0, 0, 6.3)), "LedScreen")


def speed_camera(a):
    a.add(box((0.25, 0.25, 4.0), (0, 0, 2.0)), "MetalDark")
    a.add(box((0.6, 0.5, 0.45), (0, -0.2, 4.1), 0.05), "SignYellow")
    a.add(cyl(0.12, 0.12, 12, (0, -0.47, 4.1), axis="Y"), "WindowGlass")
    a.add(box((1.2, 0.08, 0.9), (0, 0.15, 3.2)), "FabricOrange")


def smash_board(a):
    for x in (-1.1, 1.1):
        a.add(box((0.15, 0.15, 2.2), (x, 0, 1.1)), "WoodDark")
    a.add(box((2.6, 0.1, 1.3), (0, 0, 1.9)), "FabricYellow")
    a.add(box((1.6, 0.11, 0.5), (0, -0.01, 1.9)), "FabricTeal")


# ---------------------------------------------------------------------------------------------
REGISTRY = {
    # name: (category, builder, kwargs)
    "tree_conifer": ("Nature", tree_conifer, {}), "tree_conifer_b": ("Nature", tree_conifer, {"seed": 21, "h": 14.0}),
    "tree_broadleaf": ("Nature", tree_broadleaf, {}), "tree_broadleaf_b": ("Nature", tree_broadleaf, {"seed": 22}),
    "tree_poplar": ("Nature", tree_poplar, {}), "tree_umbrella_pine": ("Nature", tree_umbrella_pine, {}),
    "bush": ("Nature", bush, {}), "bush_dry": ("Nature", bush, {"seed": 23, "mat_name": "LeavesDry"}),
    "rock_a": ("Nature", rock, {}), "rock_b": ("Nature", rock, {"seed": 24, "scale": (1.1, 1.0, 1.4)}),
    "rock_red": ("Nature", rock, {"seed": 25, "mat_name": "RockRed", "scale": (2.0, 1.4, 1.1)}),
    "cactus": ("Nature", cactus, {}), "dead_tree": ("Nature", dead_tree, {}),
    "grass_clump": ("Nature", grass_clump, {}), "wheat_clump": ("Nature", grass_clump, {"seed": 26, "mat_name": "LeavesWheat", "blades": 12, "height": 0.95}),
    "flowers": ("Nature", flowers, {}), "hay_bale": ("Nature", hay_bale, {}),
    "house_a": ("Settlements", house, {}), "house_b": ("Settlements", house, {"w": 10.0, "l": 7.0, "wall_h": 3.2, "roof_h": 2.2, "wall": "WallPlasterC", "roof": "RoofSlate", "storeys": 1}),
    "house_c": ("Settlements", house, {"w": 7.0, "l": 5.5, "wall_h": 4.0, "roof_h": 2.6, "wall": "WallStone", "roof": "RoofSlate", "storeys": 1}),
    "farmhouse": ("Settlements", house, {"w": 12.0, "l": 8.0, "wall_h": 5.8, "roof_h": 3.0, "wall": "WallPlasterB", "roof": "RoofTile"}),
    "church": ("Settlements", church, {}), "barn": ("Settlements", barn, {}), "silo": ("Settlements", silo, {}),
    "shop": ("Settlements", shop, {}), "gas_station": ("Settlements", gas_station, {}), "boathouse": ("Settlements", boathouse, {}),
    "pier": ("Settlements", pier, {}), "boat": ("Settlements", boat, {}),
    "lighthouse": ("Landmarks", lighthouse, {}), "castle_ruin": ("Landmarks", castle_ruin, {}),
    "street_lamp": ("Roadside", street_lamp, {}), "reflector_post": ("Roadside", reflector_post, {}),
    "chevron": ("Roadside", chevron, {}), "sign_curve_l": ("Roadside", sign_triangle, {"curve_dir": -1}),
    "sign_curve_r": ("Roadside", sign_triangle, {"curve_dir": 1}), "sign_speed": ("Roadside", sign_speed, {}),
    "sign_route": ("Roadside", sign_route, {}), "sign_region": ("Roadside", sign_region, {}),
    "fence_wood": ("Roadside", fence_wood, {}), "wall_stone": ("Roadside", wall_stone, {}), "viewpoint": ("Roadside", viewpoint, {}),
    "festival_stage": ("Festival", festival_stage, {}), "festival_tent": ("Festival", festival_tent, {}),
    "festival_flag": ("Festival", festival_flag, {}), "festival_arch": ("Festival", festival_arch, {}),
    "ramp_jump": ("Activities", ramp_jump, {}), "checkpoint_gate": ("Activities", checkpoint_gate, {}),
    "speed_camera": ("Activities", speed_camera, {}), "smash_board": ("Activities", smash_board, {}),
}


def build_prop(name, export=True):
    K.guard()
    cat, fn, kw = ("Landmarks", None, {}) if name == "wind_turbine" else REGISTRY[name]
    parent = K.sub_collection(cat)
    col_name = "PROP_" + name
    col = bpy.data.collections.get(col_name)
    if col is not None:
        K.clear_collection(col)
    col = K.collection(col_name, parent)
    if name == "wind_turbine":
        objs = wind_turbine_parts(col)
    else:
        a = Asset(name)
        fn(a, **kw)
        objs = [a.build(col, smooth=30 if cat == "Nature" else 35)]
    for o in objs:
        K.box_uv(o, 0.5)
    path = None
    if export:
        path = os.path.join(OUT_DIR, name + ".glb")
        K.export_glb(objs, path)
    return col, path


def build_all(names=None):
    names = names or (list(REGISTRY.keys()) + ["wind_turbine"])
    report = []
    for n in names:
        col, path = build_prop(n)
        tris = 0
        for o in col.objects:
            if o.type == "MESH":
                o.data.calc_loop_triangles()
                tris += len(o.data.loop_triangles)
        report.append("%s:%d" % (n, tris))
    return report
