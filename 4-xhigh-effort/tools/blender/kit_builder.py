"""World kit for VALORIA: vegetation, settlement buildings, landmarks, road furniture and activity
props, all generated procedurally in the master .blend and exported one piece per .glb to
res://assets/imported/kit/<name>.glb.

Conventions (Blender, Z up, metres):
  * every piece is built around the origin with the ground at z = 0;
  * the "front" of a building (door / street side) faces +Y, which becomes Godot -Z on export;
  * material names are the keys of scripts/world/kit_materials.gd (the engine swaps in its own);
  * vegetation pieces are a single mesh plus a "<name>_LOD1" mesh (used beyond ~250 m);
  * multi-part pieces keep separate objects only where the engine animates them ("_Rotor").
"""
import contextlib
import io
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import vgk_common as C

KIT_DIR = os.path.join(C.PROJECT_DIR, "assets", "imported", "kit")

# Blender preview colours only; the engine uses KitMaterials.
KIT_COLORS = {
    "Leaves": (0.2, 0.33, 0.1, 1), "LeavesBroad": (0.22, 0.36, 0.11, 1), "LeavesPine": (0.1, 0.2, 0.1, 1),
    "LeavesOlive": (0.32, 0.38, 0.2, 1), "LeavesDry": (0.45, 0.4, 0.22, 1), "PalmLeaf": (0.25, 0.42, 0.12, 1),
    "Bark": (0.25, 0.18, 0.12, 1), "BarkPale": (0.5, 0.45, 0.38, 1), "Cactus": (0.25, 0.38, 0.18, 1),
    "Rock": (0.45, 0.43, 0.4, 1), "Grass": (0.3, 0.42, 0.14, 1), "Plaster": (0.9, 0.85, 0.74, 1),
    "PlasterOchre": (0.86, 0.66, 0.4, 1), "PlasterPink": (0.88, 0.7, 0.66, 1), "PlasterBlue": (0.62, 0.75, 0.82, 1),
    "RoofTile": (0.62, 0.25, 0.14, 1), "RoofSlate": (0.22, 0.24, 0.27, 1), "Wood": (0.36, 0.22, 0.12, 1),
    "WoodDark": (0.2, 0.13, 0.08, 1), "Stone": (0.58, 0.55, 0.5, 1), "StoneDark": (0.38, 0.36, 0.33, 1),
    "Concrete": (0.62, 0.61, 0.58, 1), "Metal": (0.62, 0.63, 0.65, 1), "MetalRed": (0.7, 0.12, 0.08, 1),
    "WindowGlass": (0.15, 0.2, 0.25, 1), "WindowLit": (0.2, 0.24, 0.28, 1), "Lamp": (1.0, 0.95, 0.8, 1),
    "SignWhite": (0.92, 0.92, 0.9, 1), "SignRed": (0.8, 0.1, 0.08, 1), "SignBlue": (0.1, 0.3, 0.7, 1),
    "SignGreen": (0.05, 0.4, 0.2, 1), "SignYellow": (0.95, 0.75, 0.1, 1), "Reflector": (1.0, 0.6, 0.1, 1),
    "Fabric": (0.92, 0.9, 0.85, 1), "FabricRed": (0.85, 0.15, 0.25, 1), "FabricBlue": (0.15, 0.45, 0.85, 1),
    "FabricYellow": (0.98, 0.75, 0.1, 1), "Flower": (0.9, 0.85, 0.3, 1), "White": (0.94, 0.94, 0.92, 1),
    "Black": (0.04, 0.04, 0.045, 1), "BarnRed": (0.55, 0.13, 0.09, 1), "Steel": (0.6, 0.6, 0.62, 1),
}


def kmat(name):
    return C.mat(name, KIT_COLORS.get(name))


# ---------------------------------------------------------------- mesh builder
class MB:
    """bmesh accumulator with material names and a transform stack."""

    def __init__(self, seed=1):
        self.bm = bmesh.new()
        self.mats = []
        self.M = Matrix.Identity(4)
        self.rng = random.Random(seed)

    @contextlib.contextmanager
    def xf(self, m):
        old = self.M
        self.M = old @ m
        try:
            yield
        finally:
            self.M = old

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _finish(self, verts, mat, smooth):
        idx = self.mi(mat)
        for v in verts:
            v.co = self.M @ v.co
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = idx
            f.smooth = smooth
        return verts

    def box(self, size, center, mat, rot=None, smooth=False):
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        R = rot if rot is not None else Matrix.Identity(3)
        for v in res["verts"]:
            v.co = R @ Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
        return self._finish(res["verts"], mat, smooth)

    def cyl(self, r0, r1, h, base, mat, seg=8, axis=None, smooth=True, cap=True):
        """Frustum from base along axis (default +Z) of length h."""
        res = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=seg,
                                    radius1=r0, radius2=max(r1, 1e-4), depth=h)
        d = Vector(axis).normalized() if axis is not None else Vector((0, 0, 1))
        R = d.to_track_quat("Z", "Y").to_matrix()
        for v in res["verts"]:
            v.co = R @ (v.co + Vector((0, 0, h / 2))) + Vector(base)
        vs = self._finish(res["verts"], mat, smooth)
        if smooth and cap:  # keep caps flat
            for f in {f for v in vs for f in v.link_faces}:
                if len(f.verts) > 4:
                    f.smooth = False
        return vs

    def blob(self, scale, center, mat, subdiv=1, amp=0.15, freq=1.4, seed=0.0, smooth=True, flat_bottom=None):
        # bmesh counts the bare icosahedron as one level: subdiv 0 = 20 faces, 1 = 80, 2 = 320
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv + 1, radius=1.0)
        off = Vector((seed * 7.31, seed * 3.17, seed * 5.53))
        for v in res["verts"]:
            n = v.co.normalized()
            k = 1.0 + amp * noise.noise(n * freq + off)
            p = Vector((n.x * scale[0] * k, n.y * scale[1] * k, n.z * scale[2] * k))
            if flat_bottom is not None:
                p.z = max(p.z, -scale[2] * flat_bottom)
            v.co = p + Vector(center)
        return self._finish(res["verts"], mat, smooth)

    def poly_prism(self, pts, y0, y1, mat, smooth=False):
        """Extrude a convex XZ polygon (counter-clockwise seen from -Y) from y0 to y1."""
        a = [self.bm.verts.new((x, y0, z)) for x, z in pts]
        b = [self.bm.verts.new((x, y1, z)) for x, z in pts]
        n = len(pts)
        faces = [self.bm.faces.new(a), self.bm.faces.new(b[::-1])]
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((a[j], a[i], b[i], b[j])))
        vs = a + b
        self._finish(vs, mat, smooth)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        return vs

    def quad_strip(self, rows, mat, smooth=True):
        """rows: list of vertex rows (each a list of Vector); faces between consecutive rows."""
        vr = [[self.bm.verts.new(p) for p in row] for row in rows]
        for r in range(len(vr) - 1):
            a, b = vr[r], vr[r + 1]
            for i in range(len(a) - 1):
                if len(b) == len(a):
                    self.bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
                elif len(b) == 1:
                    self.bm.faces.new((a[i], a[i + 1], b[0]))
        return self._finish([v for row in vr for v in row], mat, smooth)

    def to_object(self, name, col):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=3e-4)
        ob = C.bm_to_object(bm, name, col, [kmat(m) for m in self.mats], smooth=False)
        return ob


def rot_z(a):
    return Matrix.Rotation(a, 4, "Z")


def tr(x, y, z):
    return Matrix.Translation((x, y, z))


# ------------------------------------------------------------ building parts
WALLS = {"front": (0.0, 1.0, 0.0), "back": (math.pi, -1.0, 0.0), "right": (-math.pi / 2, 0.0, 1.0),
         "left": (math.pi / 2, 0.0, -1.0)}


def wall(W, D, side):
    """Matrix placing a local frame (x along wall, +y outwards, z up) on a box wall."""
    a, fy, fx = WALLS[side]
    return tr(fx * W / 2, fy * D / 2, 0) @ rot_z(a)


def window(mb, u, z, w, h, frame="White", shutters=None, lit=None, mullion=True):
    lit = mb.rng.random() < 0.55 if lit is None else lit
    glass = "WindowLit" if lit else "WindowGlass"
    mb.box((w, 0.06, h), (u, 0.0, z + h / 2), glass)
    mb.box((w + 0.16, 0.12, 0.08), (u, 0.03, z + h + 0.04), frame)
    mb.box((w + 0.3, 0.22, 0.07), (u, 0.08, z - 0.035), frame)
    for s in (-1, 1):
        mb.box((0.08, 0.12, h), (u + s * (w / 2 + 0.04), 0.03, z + h / 2), frame)
    if mullion and w > 0.8:
        mb.box((0.05, 0.09, h), (u, 0.03, z + h / 2), frame)
        mb.box((w, 0.09, 0.05), (u, 0.03, z + h * 0.62), frame)
    if shutters:
        for s in (-1, 1):
            mb.box((w * 0.5, 0.05, h + 0.05), (u + s * (w * 0.75 + 0.1), 0.04, z + h / 2), shutters)


def door(mb, u, w=1.1, h=2.2, mat="WoodDark", frame="White", step="Stone", glass=False):
    mb.box((w, 0.08, h), (u, 0.0, h / 2), "WindowGlass" if glass else mat)
    mb.box((w + 0.24, 0.14, 0.12), (u, 0.03, h + 0.06), frame)
    for s in (-1, 1):
        mb.box((0.12, 0.14, h), (u + s * (w / 2 + 0.06), 0.03, h / 2), frame)
    if step:
        mb.box((w + 0.7, 0.6, 0.2), (u, 0.3, -0.1), step)


def foundation(mb, W, D, mat="Stone", top=0.3, depth=2.0):
    mb.box((W + 0.3, D + 0.3, depth + top), (0, 0, (top - depth) / 2), mat)


def slabs(mb, pts, y0, y1, t, mat):
    """Roof shell: one slab per profile segment (x, z), thickness t above the profile line."""
    L = y1 - y0
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz)
        ang = math.atan2(-dz, dx)  # rotation about +Y that maps +X onto the segment
        R = Matrix.Rotation(ang, 3, "Y")
        nrm = Vector((-dz, 0, dx)) / ln  # left normal (upwards for a left-to-right profile)
        c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)) + nrm * (t / 2)
        mb.box((ln + t * 0.6, L, t), c, mat, rot=R)


def gable_roof(mb, W, D, z0, h, o, mat, wall_mat, ridge="Y", t=0.18):
    """Pitched roof over a W x D box whose walls end at z0. ridge 'Y' puts the gables at front/back."""
    if ridge == "X":
        with mb.xf(rot_z(math.pi / 2)):
            gable_roof(mb, D, W, z0, h, o, mat, wall_mat, "Y", t)
        return
    k = h / (W / 2)
    pts = [(-W / 2 - o, z0 - o * k), (0.0, z0 + h), (W / 2 + o, z0 - o * k)]
    slabs(mb, pts, -D / 2 - o, D / 2 + o, t, mat)
    mb.poly_prism([(-W / 2, z0), (W / 2, z0), (0.0, z0 + h)], -D / 2, D / 2, wall_mat)
    mb.box((0.3, D + 2 * o + 0.1, 0.14), (0, 0, z0 + h + t + 0.02), mat)


def hip_roof(mb, W, D, z0, h, o, mat):
    w, d = W / 2 + o, D / 2 + o
    zb = z0 - 0.12
    if W >= D:
        r = max(w - d, 0.0)
        top = [(-r, 0.0), (r, 0.0)]
    else:
        r = max(d - w, 0.0)
        top = [(0.0, -r), (0.0, r)]
    bm = mb.bm
    b = [bm.verts.new(p) for p in [(-w, -d, zb), (w, -d, zb), (w, d, zb), (-w, d, zb)]]
    t0 = bm.verts.new((top[0][0], top[0][1], z0 + h))
    t1 = bm.verts.new((top[1][0], top[1][1], z0 + h))
    faces = [bm.faces.new((b[3], b[2], b[1], b[0]))]
    if W >= D:
        faces += [bm.faces.new((b[0], b[1], t1, t0)), bm.faces.new((b[1], b[2], t1)),
                  bm.faces.new((b[2], b[3], t0, t1)), bm.faces.new((b[3], b[0], t0))]
    else:
        faces += [bm.faces.new((b[0], b[1], t0)), bm.faces.new((b[1], b[2], t1, t0)),
                  bm.faces.new((b[2], b[3], t1)), bm.faces.new((b[3], b[0], t0, t1))]
    mb._finish(b + [t0, t1], mat, False)
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def flat_roof(mb, W, D, z0, mat="Concrete", parapet=0.7, pmat="White"):
    mb.box((W, D, 0.25), (0, 0, z0 + 0.12), mat)
    for s in (-1, 1):
        mb.box((W + 0.2, 0.25, parapet), (0, s * (D / 2 - 0.02), z0 + parapet / 2), pmat)
        mb.box((0.25, D + 0.2, parapet), (s * (W / 2 - 0.02), 0, z0 + parapet / 2), pmat)


def chimney(mb, x, y, z0, z1, mat="Stone"):
    mb.box((0.7, 0.7, z1 - z0), (x, y, (z0 + z1) / 2), mat)
    mb.box((0.85, 0.85, 0.15), (x, y, z1), "StoneDark")


def railing(mb, x0, x1, y, z, mat="Wood", post_gap=0.55, h=1.0):
    n = max(2, int(abs(x1 - x0) / post_gap) + 1)
    for i in range(n):
        x = x0 + (x1 - x0) * i / (n - 1)
        mb.box((0.06, 0.06, h), (x, y, z + h / 2), mat)
    mb.box((abs(x1 - x0) + 0.1, 0.09, 0.07), ((x0 + x1) / 2, y, z + h), mat)
    mb.box((abs(x1 - x0) + 0.1, 0.05, 0.05), ((x0 + x1) / 2, y, z + 0.15), mat)


# ------------------------------------------------------------------- buildings
def b_house_a(mb):
    W, D, z0, H = 9.0, 7.5, 0.3, 5.8
    foundation(mb, W, D)
    mb.box((W, D, H), (0, 0, z0 + H / 2), "Plaster")
    gable_roof(mb, W, D, z0 + H, 2.6, 0.5, "RoofTile", "Plaster", ridge="X")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        door(mb, 0.0, h=2.3)
        for u in (-2.6, 2.6):
            window(mb, u, 1.0, 1.2, 1.4, shutters="WoodDark")
        for u in (-2.6, 0.0, 2.6):
            window(mb, u, 3.6, 1.1, 1.3, shutters="WoodDark")
        mb.box((2.2, 1.1, 0.12), (0, 0.55, 2.75), "RoofTile")
        for s in (-1, 1):
            mb.box((0.1, 0.9, 0.1), (s * 0.95, 0.45, 2.6), "WoodDark")
    with mb.xf(wall(W, D, "back") @ tr(0, 0, z0)):
        for u in (-2.6, 0.0, 2.6):
            window(mb, u, 1.0, 1.1, 1.3)
            window(mb, u, 3.6, 1.1, 1.3)
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-1.6, 1.6):
                window(mb, u, 1.0, 0.9, 1.3)
                window(mb, u, 3.6, 0.9, 1.3)
    chimney(mb, 2.6, -1.2, z0 + H, z0 + H + 3.0)


def b_house_b(mb):
    W, D, z0, H = 8.0, 9.0, 0.3, 4.0
    foundation(mb, W, D)
    mb.box((W, D, H), (0, 0, z0 + H / 2), "PlasterOchre")
    gable_roof(mb, W, D, z0 + H, 3.6, 0.45, "RoofTile", "PlasterOchre", ridge="Y")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        door(mb, 1.7, h=2.2, mat="SignGreen")
        window(mb, -1.8, 0.95, 1.4, 1.4, shutters="SignGreen")
        window(mb, 0.0, H + 0.9, 0.9, 1.1, mullion=False)
    with mb.xf(wall(W, D, "back") @ tr(0, 0, z0)):
        for u in (-1.8, 1.8):
            window(mb, u, 0.95, 1.2, 1.3)
        window(mb, 0.0, H + 0.9, 0.9, 1.1, mullion=False)
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-2.6, 0.4, 3.0):
                window(mb, u, 0.95, 1.0, 1.3, shutters="SignGreen")
    # garage annex on the left
    with mb.xf(tr(-W / 2 - 1.8, -0.8, 0)):
        mb.box((3.8, 6.0, 2.2), (0, 0, -0.8), "Stone")
        mb.box((3.6, 5.8, 2.6), (0, 0, z0 + 1.3), "PlasterOchre")
        slabs(mb, [(-2.1, z0 + 2.45), (2.1, z0 + 2.95)], -3.1, 3.1, 0.14, "RoofSlate")
        with mb.xf(wall(3.6, 5.8, "front") @ tr(0, 0, z0)):
            mb.box((2.6, 0.08, 2.1), (0, 0.0, 1.05), "White")
            for k in range(5):
                mb.box((2.6, 0.1, 0.03), (0, 0.02, 0.25 + k * 0.42), "Concrete")


def b_house_c(mb):
    W, D, z0, H = 7.0, 8.0, 0.3, 8.4
    foundation(mb, W, D)
    mb.box((W, D, H), (0, 0, z0 + H / 2), "PlasterPink")
    mb.box((W + 0.3, D + 0.3, 0.3), (0, 0, z0 + H - 0.1), "White")
    mb.box((W + 0.1, D + 0.1, 0.5), (0, 0, z0 + 0.25), "StoneDark")
    hip_roof(mb, W, D, z0 + H + 0.05, 2.0, 0.4, "RoofSlate")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        door(mb, -2.0, h=2.4, mat="WoodDark")
        window(mb, 1.0, 0.8, 2.4, 1.7, frame="WoodDark")
        for z in (3.3, 6.0):
            for u in (-2.0, 0.0, 2.0):
                window(mb, u, z, 0.9, 1.5, shutters="SignBlue")
        mb.box((5.6, 1.0, 0.15), (0, 0.5, 3.15), "Stone")
        railing(mb, -2.75, 2.75, 0.95, 3.2, mat="Black", post_gap=0.25, h=0.95)
    with mb.xf(wall(W, D, "back") @ tr(0, 0, z0)):
        for z in (0.9, 3.3, 6.0):
            for u in (-1.6, 1.6):
                window(mb, u, z, 0.9, 1.4)
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for z in (3.3, 6.0):
                window(mb, 0.0, z, 0.9, 1.4)


def b_shop(mb):
    W, D, z0, H = 12.0, 9.0, 0.3, 4.6
    foundation(mb, W, D, mat="Concrete")
    mb.box((W, D, H), (0, 0, z0 + H / 2), "Plaster")
    flat_roof(mb, W, D, z0 + H, parapet=0.8, pmat="Plaster")
    mb.box((W + 0.3, 0.3, 0.2), (0, D / 2, z0 + H + 0.8), "White")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        for u in (-3.4, 3.4):
            mb.box((4.4, 0.08, 2.5), (u, 0.0, 0.6 + 1.25), "WindowLit")
            mb.box((4.6, 0.16, 0.12), (u, 0.04, 0.55), "Metal")
            mb.box((4.6, 0.16, 0.12), (u, 0.04, 3.15), "Metal")
            for k in (-1, 0, 1):
                mb.box((0.08, 0.14, 2.5), (u + k * 2.2, 0.04, 1.85), "Metal")
        door(mb, 0.0, w=1.6, h=2.6, glass=True, frame="Metal", step="Concrete")
        # awning
        aw = Matrix.Rotation(math.radians(-18), 3, "X")
        mb.box((11.0, 1.8, 0.07), (0, 0.85, 3.55), "FabricRed", rot=aw)
        mb.box((11.0, 0.05, 0.3), (0, 1.72, 3.12), "FabricRed")
        mb.box((8.4, 0.22, 0.95), (0, 0.12, 4.15), "SignBlue")
        mb.box((7.2, 0.1, 0.55), (0, 0.24, 4.15), "SignWhite")
    with mb.xf(wall(W, D, "back") @ tr(0, 0, z0)):
        door(mb, -3.5, h=2.2, mat="Metal", frame="Concrete", step="Concrete")
        window(mb, 2.5, 1.6, 1.2, 1.0)
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            window(mb, 0.0, 1.4, 1.4, 1.3)
    mb.box((1.6, 1.2, 0.9), (2.5, -1.5, z0 + H + 0.6), "Metal")


def b_church(mb):
    W, D, z0, H = 10.0, 18.0, 0.3, 8.0
    foundation(mb, W, D, mat="StoneDark")
    mb.box((W, D, H), (0, 0, z0 + H / 2), "Stone")
    gable_roof(mb, W, D, z0 + H, 5.5, 0.4, "RoofSlate", "Stone", ridge="Y")
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-6.0, -3.0, 0.0, 3.0, 6.0):
                window(mb, u, 2.4, 1.0, 3.4, frame="StoneDark", lit=True, mullion=False)
            for u in (-7.5, -4.5, -1.5, 1.5, 4.5):
                mb.box((0.6, 0.8, 5.4), (u, 0.4, 2.7), "StoneDark")
    # apse
    mb.cyl(3.6, 3.6, 6.6, (0, -D / 2, z0), "Stone", seg=12, smooth=False)
    mb.cyl(4.0, 0.3, 3.0, (0, -D / 2, z0 + 6.6), "RoofSlate", seg=12, smooth=False)
    # tower
    T = 4.8
    ty = D / 2 - 1.2
    with mb.xf(tr(0, ty, 0)):
        mb.box((T + 0.4, T + 0.4, 2.3), (0, 0, -0.85), "StoneDark")
        mb.box((T, T, 19.0), (0, 0, z0 + 9.5), "Stone")
        mb.box((T + 0.3, T + 0.3, 0.4), (0, 0, z0 + 19.0), "StoneDark")
        hip_roof(mb, T + 0.2, T + 0.2, z0 + 19.2, 9.5, 0.1, "RoofSlate")
        mb.box((0.1, 0.1, 2.4), (0, 0, z0 + 29.6), "Metal")
        mb.box((1.2, 0.1, 0.1), (0, 0, z0 + 30.2), "Metal")
        for side in WALLS:
            with mb.xf(wall(T, T, side)):
                mb.box((1.3, 0.1, 2.4), (0, 0.0, z0 + 16.0), "Black")
                mb.box((1.6, 0.2, 0.15), (0, 0.06, z0 + 14.75), "StoneDark")
                mb.cyl(0.85, 0.85, 0.12, (0, 0.0, z0 + 12.6), "White", seg=16, axis=(0, 1, 0), smooth=False)
                mb.box((0.06, 0.05, 0.65), (0, 0.13, z0 + 12.85), "Black")
                mb.box((0.5, 0.05, 0.06), (0.22, 0.13, z0 + 12.6), "Black")
        with mb.xf(wall(T, T, "front") @ tr(0, 0, z0)):
            door(mb, 0.0, w=1.8, h=3.2, mat="WoodDark", frame="StoneDark", step="StoneDark")
            window(mb, 0.0, 5.0, 1.0, 2.6, frame="StoneDark", lit=True, mullion=False)


def b_shed(mb):
    W, D, z0, H = 5.0, 4.0, 0.15, 2.6
    foundation(mb, W, D, mat="Concrete", top=0.15, depth=1.2)
    mb.box((W, D, H), (0, 0, z0 + H / 2), "Wood")
    for k in range(11):
        mb.box((0.05, D + 0.04, H), (-W / 2 + 0.25 + k * 0.45, 0, z0 + H / 2), "WoodDark")
    gable_roof(mb, W, D, z0 + H, 1.2, 0.3, "Metal", "Wood", ridge="X", t=0.08)
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        door(mb, 1.0, w=1.0, h=2.0, mat="WoodDark", frame="Wood", step=None)
        window(mb, -1.2, 1.1, 0.8, 0.7, frame="Wood", lit=False, mullion=False)


def b_boathouse(mb):
    W, D, z0, H = 7.0, 10.0, 0.3, 4.0
    foundation(mb, W, D, mat="StoneDark")
    mb.box((W, D, H), (0, 0, z0 + H / 2), "Wood")
    for k in range(15):
        mb.box((0.06, D + 0.04, H), (-W / 2 + 0.2 + k * 0.47, 0, z0 + H / 2), "WoodDark")
    gable_roof(mb, W, D, z0 + H, 2.4, 0.45, "RoofSlate", "Wood", ridge="Y")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        mb.box((4.6, 0.1, 3.4), (0, 0.02, 1.7), "WoodDark")
        mb.box((4.9, 0.16, 0.15), (0, 0.05, 3.45), "White")
        for s in (-1, 1):
            mb.box((0.15, 0.16, 3.4), (s * 2.37, 0.05, 1.7), "White")
        mb.box((0.06, 0.12, 3.3), (0, 0.06, 1.7), "White")
        window(mb, 0.0, H + 0.6, 0.8, 0.8, lit=False, mullion=False)
        mb.cyl(0.38, 0.38, 0.1, (2.9, 0.06, 2.4), "FabricRed", seg=12, axis=(0, 1, 0), smooth=False)
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-3.0, 0.0, 3.0):
                window(mb, u, 1.5, 0.9, 0.9, frame="White", mullion=False)


def b_chalet(mb):
    W, D, z0 = 10.0, 9.0, 0.3
    H1, H2 = 3.0, 2.8
    foundation(mb, W, D, mat="StoneDark")
    mb.box((W, D, H1), (0, 0, z0 + H1 / 2), "Stone")
    mb.box((W + 0.1, D + 0.1, H2), (0, 0, z0 + H1 + H2 / 2), "Wood")
    for k in range(9):
        mb.box((W + 0.14, D + 0.14, 0.05), (0, 0, z0 + H1 + 0.15 + k * 0.32), "WoodDark")
    gable_roof(mb, W + 0.1, D + 0.1, z0 + H1 + H2, 3.4, 1.1, "RoofSlate", "Wood", ridge="Y", t=0.22)
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        door(mb, 0.0, w=1.2, h=2.2)
        for u in (-3.0, 3.0):
            window(mb, u, 0.9, 1.2, 1.2, shutters="WoodDark")
        z1 = H1
        mb.box((W + 0.6, 1.5, 0.22), (0, 0.75, z1 + 0.0), "WoodDark")
        railing(mb, -W / 2 - 0.2, W / 2 + 0.2, 1.42, z1 + 0.1, mat="Wood", post_gap=0.22, h=1.0)
        for s in (-1, 1):
            mb.box((0.18, 0.18, H1), (s * (W / 2 + 0.1), 1.35, H1 / 2 - 0.1), "WoodDark")
        with mb.xf(tr(0, 0, z1 + 0.12)):
            door(mb, 0.0, w=1.4, h=2.2, mat="WoodDark", frame="Wood", step=None, glass=True)
        for u in (-3.2, 3.2):
            window(mb, u, z1 + 0.9, 1.0, 1.2, frame="Wood", shutters="WoodDark")
            mb.box((1.0, 0.25, 0.2), (u, 1.25, z1 + 1.15), "Flower")
        window(mb, 0.0, z1 + H2 + 0.9, 0.9, 1.0, frame="Wood", mullion=False)
    with mb.xf(wall(W, D, "back") @ tr(0, 0, z0)):
        for u in (-2.5, 2.5):
            window(mb, u, 1.0, 1.0, 1.1)
            window(mb, u, H1 + 0.8, 1.0, 1.1, frame="Wood")
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-2.0, 2.0):
                window(mb, u, 1.0, 0.9, 1.1)
                window(mb, u, H1 + 0.8, 0.9, 1.1, frame="Wood")
    chimney(mb, -2.5, -1.5, z0 + H1 + H2, z0 + H1 + H2 + 4.0, mat="StoneDark")


def b_barn(mb):
    W, D, z0, H = 12.0, 16.0, 0.2, 5.0
    foundation(mb, W, D, mat="Concrete", top=0.2)
    mb.box((W, D, H), (0, 0, z0 + H / 2), "BarnRed")
    for k in range(25):
        mb.box((W + 0.04, 0.05, H), (0, -D / 2 + 0.3 + k * 0.64, z0 + H / 2), "BarnRed")
    zt = z0 + H
    pts = [(-W / 2 - 0.35, zt - 0.3), (-W * 0.33, zt + 2.6), (0.0, zt + 4.0), (W * 0.33, zt + 2.6), (W / 2 + 0.35, zt - 0.3)]
    slabs(mb, pts, -D / 2 - 0.4, D / 2 + 0.4, 0.2, "RoofSlate")
    mb.poly_prism([(-W / 2, zt), (W / 2, zt), (W * 0.31, zt + 2.55), (0.0, zt + 3.9), (-W * 0.31, zt + 2.55)], -D / 2, D / 2, "BarnRed")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        for s in (-1, 1):
            u = s * 1.6
            mb.box((3.0, 0.12, 3.8), (u, 0.03, 1.9), "BarnRed")
            for zz in (0.06, 3.74):
                mb.box((3.0, 0.16, 0.12), (u, 0.06, zz), "White")
            for uu in (-1.44, 1.44):
                mb.box((0.12, 0.16, 3.8), (u + uu, 0.06, 1.9), "White")
            ang = math.atan2(3.6, 2.8)
            for a in (ang, -ang):
                mb.box((4.4, 0.14, 0.12), (u, 0.07, 1.9), "White", rot=Matrix.Rotation(a, 3, "Y"))
        mb.box((6.6, 0.25, 0.25), (0, 0.15, 4.0), "Metal")
        mb.box((1.8, 0.1, 1.6), (0, 0.02, H + 1.2), "WoodDark")
        mb.box((2.0, 0.14, 0.12), (0, 0.05, H + 2.06), "White")
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-5.0, 0.0, 5.0):
                window(mb, u, 2.4, 1.0, 0.9, lit=False, mullion=False)
    with mb.xf(tr(0, 0, zt + 3.9)):
        mb.box((1.5, 1.5, 1.3), (0, 0, 0.6), "White")
        hip_roof(mb, 1.5, 1.5, 1.25, 1.0, 0.25, "RoofSlate")


def b_farmhouse(mb):
    W, D, z0, H = 12.0, 9.0, 0.4, 5.8
    foundation(mb, W, D, top=0.4)
    mb.box((W, D, H), (0, 0, z0 + H / 2), "Plaster")
    hip_roof(mb, W, D, z0 + H, 2.8, 0.55, "RoofTile")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        door(mb, 0.0, w=1.2, h=2.3, mat="WoodDark", step=None)
        for u in (-4.5, -2.4, 2.4, 4.5):
            window(mb, u, 0.9, 1.1, 1.4, shutters="SignGreen")
        for u in (-4.0, -1.4, 1.4, 4.0):
            window(mb, u, 3.5, 1.0, 1.3, shutters="SignGreen")
        mb.box((W + 0.4, 2.6, 0.35), (0, 1.3, -0.2), "Wood")
        mb.box((W + 0.6, 3.0, 0.14), (0, 1.4, 2.95), "RoofTile", rot=Matrix.Rotation(math.radians(-8), 3, "X"))
        for k in range(6):
            mb.box((0.2, 0.2, 2.9), (-W / 2 + 0.2 + k * (W - 0.4) / 5, 2.45, 1.45), "Wood")
        railing(mb, -W / 2, -1.0, 2.5, 0.0, post_gap=0.3, h=0.9)
        railing(mb, 1.0, W / 2, 2.5, 0.0, post_gap=0.3, h=0.9)
    with mb.xf(wall(W, D, "back") @ tr(0, 0, z0)):
        door(mb, 3.0, h=2.2, step="Stone")
        for u in (-4.0, -1.0):
            window(mb, u, 0.9, 1.0, 1.3)
        for u in (-4.0, -1.0, 2.0, 4.5):
            window(mb, u, 3.5, 1.0, 1.3)
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            for u in (-2.0, 2.0):
                window(mb, u, 0.9, 1.0, 1.3)
                window(mb, u, 3.5, 1.0, 1.3)
    chimney(mb, -3.0, 0.0, z0 + H, z0 + H + 3.6)
    chimney(mb, 3.6, 0.0, z0 + H, z0 + H + 3.4)


def b_silo(mb):
    R, H = 2.6, 13.0
    mb.cyl(R + 0.35, R + 0.35, 1.4, (0, 0, -0.8), "Concrete", seg=20)
    mb.cyl(R, R, H, (0, 0, 0.5), "Steel", seg=24)
    for k in range(1, 7):
        mb.cyl(R + 0.05, R + 0.05, 0.12, (0, 0, 0.5 + k * H / 7), "Metal", seg=24)
    mb.cyl(R + 0.15, 0.35, 2.2, (0, 0, 0.5 + H), "Steel", seg=24)
    mb.cyl(0.4, 0.3, 0.5, (0, 0, 0.5 + H + 2.1), "Metal", seg=10)
    for s in (-1, 1):
        mb.box((0.06, 0.08, H + 1.0), (s * 0.25, R + 0.3, 0.5 + (H + 1.0) / 2), "Metal")
    for k in range(int(H / 0.4)):
        mb.box((0.5, 0.05, 0.04), (0, R + 0.3, 1.0 + k * 0.4), "Metal")
    mb.box((0.4, 0.3, 0.06), (0, R + 0.15, 0.5 + H + 1.0), "Metal")
    # small feed hopper and auger
    mb.box((2.0, 2.0, 2.2), (R + 2.2, 0, 1.1), "Steel")
    mb.cyl(0.18, 0.18, 9.0, (R + 2.2, 0, 2.0), "Metal", seg=8, axis=(-0.55, 0, 0.83))


def b_gas_station(mb):
    mb.box((22.0, 20.0, 0.4), (0, 0, -0.05), "Concrete")
    # canopy over the pumps (front half)
    cy = 3.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.5, 0.5, 5.2), (sx * 4.5, cy + sy * 2.6, 2.6), "White")
    mb.box((14.0, 9.0, 0.6), (0, cy, 5.5), "White")
    mb.box((14.1, 9.1, 0.4), (0, cy, 5.05), "SignRed")
    mb.box((13.4, 8.4, 0.05), (0, cy, 4.82), "Lamp")
    for x in (-2.5, 2.5):
        mb.box((1.2, 4.6, 0.22), (x, cy, 0.25), "Concrete")
        for y in (-1.2, 1.2):
            mb.box((0.75, 0.5, 1.8), (x, cy + y, 1.25), "SignRed")
            mb.box((0.8, 0.55, 0.3), (x, cy + y, 2.3), "White")
            mb.box((0.5, 0.56, 0.4), (x, cy + y, 1.65), "Black")
    # shop
    sy0 = -5.5
    with mb.xf(tr(0, sy0, 0)):
        W, D, H = 12.0, 6.5, 3.8
        mb.box((W, D, H), (0, 0, 0.15 + H / 2), "White")
        flat_roof(mb, W, D, 0.15 + H, parapet=0.9, pmat="SignRed")
        with mb.xf(wall(W, D, "front") @ tr(0, 0, 0.15)):
            mb.box((8.0, 0.08, 2.4), (-1.2, 0.0, 1.5), "WindowLit")
            for k in range(5):
                mb.box((0.08, 0.14, 2.4), (-5.2 + k * 2.0, 0.04, 1.5), "Metal")
            door(mb, 4.0, w=1.6, h=2.4, glass=True, frame="Metal", step=None)
        with mb.xf(wall(W, D, "back") @ tr(0, 0, 0.15)):
            door(mb, 3.0, h=2.2, mat="Metal", frame="Concrete", step=None)
        mb.box((1.4, 1.0, 0.8), (-3.0, -1.0, 0.15 + H + 0.5), "Metal")
    # price sign
    with mb.xf(tr(8.5, 8.0, 0)):
        mb.box((0.3, 0.3, 4.2), (0, 0, 2.1), "Metal")
        mb.box((2.0, 0.35, 2.8), (0, 0, 5.4), "SignRed")
        for k in range(3):
            mb.box((1.6, 0.4, 0.5), (0, 0, 4.6 + k * 0.7), "SignWhite")
    # air & water post, bins
    mb.box((0.5, 0.4, 1.3), (-8.0, 6.5, 0.8), "SignBlue")
    for x in (-7.0, 7.0):
        mb.cyl(0.3, 0.3, 0.9, (x, 0.0, 0.15), "SignGreen", seg=10)


def b_diner(mb):
    W, D, z0, H = 16.0, 8.0, 0.3, 3.6
    foundation(mb, W, D, mat="Concrete")
    mb.box((W, D, H), (0, 0, z0 + H / 2), "White")
    mb.box((W + 0.1, D + 0.1, 0.9), (0, 0, z0 + 0.45), "Metal")
    mb.box((W + 0.12, D + 0.12, 0.25), (0, 0, z0 + 2.75), "SignRed")
    flat_roof(mb, W, D, z0 + H, parapet=0.6, pmat="SignRed")
    with mb.xf(wall(W, D, "front") @ tr(0, 0, z0)):
        for u in (-4.5, 4.5):
            mb.box((5.6, 0.08, 1.4), (u, 0.0, 1.0 + 0.7), "WindowLit")
            for k in range(5):
                mb.box((0.06, 0.12, 1.4), (u - 2.8 + k * 1.4, 0.03, 1.7), "Metal")
        door(mb, 0.0, w=1.8, h=2.4, glass=True, frame="Metal", step="Concrete")
        mb.box((3.4, 1.8, 0.16), (0, 0.9, 2.95), "SignRed")
    for side in ("left", "right"):
        with mb.xf(wall(W, D, side) @ tr(0, 0, z0)):
            mb.box((5.0, 0.08, 1.4), (0, 0.0, 1.7), "WindowLit")
    with mb.xf(tr(0, 0, z0 + H + 0.2)):
        for s in (-1, 1):
            mb.box((0.2, 0.2, 2.2), (s * 2.6, 0.5, 1.1), "Metal")
        mb.box((6.2, 0.35, 1.8), (0, 0.5, 2.6), "SignYellow")
        mb.box((5.4, 0.45, 1.1), (0, 0.5, 2.6), "SignRed")
        mb.box((4.8, 0.5, 0.12), (0, 0.5, 2.6), "Lamp")
    with mb.xf(tr(0, -D / 2 - 1.5, 0)):
        mb.box((5.0, 3.0, 3.0), (2.5, 0, 1.5), "Concrete")
        mb.cyl(0.2, 0.2, 2.0, (3.5, 0.0, 3.0), "Metal", seg=8)
        mb.box((1.2, 1.2, 1.0), (-2.0, 0.0, 0.5), "SignGreen")


BUILDINGS = {
    "house_a": b_house_a, "house_b": b_house_b, "house_c": b_house_c, "shop": b_shop, "church": b_church,
    "shed": b_shed, "boathouse": b_boathouse, "chalet": b_chalet, "barn": b_barn, "farmhouse": b_farmhouse,
    "silo": b_silo, "gas_station": b_gas_station, "diner": b_diner,
}


# ------------------------------------------------------------------- landmarks
def l_lighthouse(mb):
    H = 22.0

    def r_at(z):
        return 3.0 - z / H * 1.0

    mb.cyl(3.8, 3.8, 2.2, (0, 0, -0.9), "Stone", seg=16, smooth=False)
    mb.cyl(r_at(0), r_at(H), H, (0, 0, 1.3), "White", seg=20)
    for za, zb in ((6.0, 9.0), (14.0, 17.0)):
        mb.cyl(r_at(za) + 0.03, r_at(zb) + 0.03, zb - za, (0, 0, 1.3 + za), "SignRed", seg=20, cap=False)
    zt = 1.3 + H
    mb.cyl(3.0, 3.0, 0.4, (0, 0, zt), "Concrete", seg=20, smooth=False)
    for k in range(16):
        a = 2 * math.pi * k / 16
        mb.box((0.06, 0.06, 1.0), (math.cos(a) * 2.85, math.sin(a) * 2.85, zt + 0.9), "Black")
    mb.cyl(2.9, 2.9, 0.06, (0, 0, zt + 1.35), "Black", seg=20, cap=False)
    mb.cyl(2.92, 2.92, 0.06, (0, 0, zt + 1.4), "Black", seg=20, smooth=False)
    mb.cyl(1.6, 1.6, 0.6, (0, 0, zt + 0.4), "Black", seg=16, smooth=False)
    mb.cyl(1.45, 1.45, 2.4, (0, 0, zt + 1.0), "Lamp", seg=16, smooth=False)
    for k in range(8):
        a = 2 * math.pi * k / 8
        mb.box((0.08, 0.08, 2.4), (math.cos(a) * 1.48, math.sin(a) * 1.48, zt + 2.2), "Black")
    mb.cyl(1.9, 0.25, 1.6, (0, 0, zt + 3.4), "MetalRed", seg=16)
    mb.blob((0.35, 0.35, 0.35), (0, 0, zt + 5.1), "MetalRed", subdiv=1, amp=0.0)
    with mb.xf(tr(0, r_at(0) - 0.1, 1.3)):
        door(mb, 0.0, w=1.1, h=2.1, mat="SignRed", frame="White", step="Stone")
    for z in (7.5, 15.5):
        with mb.xf(tr(0, r_at(z) - 0.05, 1.3 + 0.0)):
            window(mb, 0.0, z - 0.6, 0.6, 0.9, frame="White", lit=True, mullion=False)
    # keeper's cottage
    with mb.xf(tr(6.5, -3.5, 0)):
        W, D, H2 = 6.0, 5.0, 3.0
        foundation(mb, W, D)
        mb.box((W, D, H2), (0, 0, 0.3 + H2 / 2), "White")
        gable_roof(mb, W, D, 0.3 + H2, 1.8, 0.35, "RoofSlate", "White", ridge="X")
        with mb.xf(wall(W, D, "front") @ tr(0, 0, 0.3)):
            door(mb, -1.2, h=2.1, mat="SignBlue")
            window(mb, 1.3, 0.9, 1.0, 1.1, shutters="SignBlue")
        chimney(mb, 1.8, 0.0, 0.3 + H2, 0.3 + H2 + 2.2)


def _merlons(mb, x0, y0, x1, y1, z, mat="Stone", gap=1.6, size=0.8, thick=1.4):
    L = math.hypot(x1 - x0, y1 - y0)
    n = max(1, int(L / gap))
    ang = math.atan2(y1 - y0, x1 - x0)
    R = Matrix.Rotation(ang, 3, "Z")
    for i in range(n):
        t = (i + 0.5) / n
        mb.box((size, thick, 0.9), (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z + 0.45), mat, rot=R)


def l_castle(mb):
    X, Y, Hw, T = 13.0, 11.0, 7.0, 1.6
    # curtain walls (front split by the gate, right wall partly ruined)
    mb.box((2 * X, T, Hw + 2.0), (0, -Y, Hw / 2 - 1.0), "Stone")
    mb.box((T, 2 * Y, Hw + 2.0), (-X, 0, Hw / 2 - 1.0), "Stone")
    mb.box((T, Y, Hw + 2.0), (X, -Y / 2, Hw / 2 - 1.0), "Stone")
    mb.box((T, Y, 4.5), (X, Y / 2, 1.25), "Stone")
    for k in range(5):
        mb.box((T * 0.9, 1.2, 0.8 + (k % 3) * 0.7), (X, Y * 0.15 + k * 1.7, 3.6 + (k % 3) * 0.35), "StoneDark")
    for s in (-1, 1):
        mb.box((X - 3.5, T, Hw + 2.0), (s * (X + 3.5) / 2, Y, Hw / 2 - 1.0), "Stone")
    mb.box((7.0, T, 2.4), (0, Y, Hw - 1.2), "Stone")
    mb.box((4.4, T + 0.1, 0.4), (0, Y, 4.3), "StoneDark")
    _merlons(mb, -X, -Y, X, -Y, Hw)
    _merlons(mb, -X, -Y, -X, Y, Hw)
    _merlons(mb, X, -Y, X, 0.0, Hw)
    _merlons(mb, -X, Y, -3.5, Y, Hw)
    _merlons(mb, 3.5, Y, X, Y, Hw)
    # corner and gate towers
    for (x, y, r, h) in ((-X, -Y, 3.0, 11.0), (X, -Y, 3.0, 12.0), (-X, Y, 3.0, 11.5), (X, Y, 2.6, 6.5),
                         (-3.6, Y + 0.4, 2.2, 10.0), (3.6, Y + 0.4, 2.2, 10.0)):
        mb.cyl(r, r * 0.92, h + 2.0, (x, y, -2.0), "StoneDark" if r > 2.8 else "Stone", seg=12, smooth=False)
        if h > 7:
            mb.cyl(r + 0.3, r + 0.3, 0.5, (x, y, h - 0.2), "Stone", seg=12, smooth=False)
            for k in range(10):
                a = 2 * math.pi * k / 10
                mb.box((0.7, 0.7, 0.9), (x + math.cos(a) * (r + 0.05), y + math.sin(a) * (r + 0.05), h + 0.75), "Stone",
                       rot=Matrix.Rotation(a, 3, "Z"))
            for a in (0.4, 2.2, 4.0):
                mb.box((0.35, 0.3, 1.3), (x + math.cos(a) * (r * 0.95), y + math.sin(a) * (r * 0.95), h * 0.6), "Black",
                       rot=Matrix.Rotation(a + math.pi / 2, 3, "Z"))
    # keep
    with mb.xf(tr(-3.0, -4.0, 0)):
        mb.box((10.0, 9.0, 18.0), (0, 0, 7.0), "StoneDark")
        mb.box((10.6, 9.6, 0.5), (0, 0, 16.2), "Stone")
        _merlons(mb, -5.1, -4.6, 5.1, -4.6, 16.4, thick=0.8)
        _merlons(mb, -5.1, 4.6, 5.1, 4.6, 16.4, thick=0.8)
        _merlons(mb, -5.1, -4.6, -5.1, 4.6, 16.4, thick=0.8)
        _merlons(mb, 5.1, -4.6, 5.1, 4.6, 16.4, thick=0.8)
        for side in WALLS:
            with mb.xf(wall(10.0, 9.0, side)):
                for u in (-2.5, 2.5):
                    mb.box((0.4, 0.1, 1.6), (u, 0.0, 9.0), "Black")
                mb.box((0.5, 0.1, 1.8), (0, 0.0, 12.5), "Black")
        with mb.xf(wall(10.0, 9.0, "front")):
            door(mb, 0.0, w=1.6, h=2.8, mat="WoodDark", frame="Stone", step="StoneDark")
        mb.box((0.12, 0.12, 5.0), (3.5, 3.0, 19.0), "Metal")
        mb.box((0.04, 2.0, 1.2), (3.5, 4.0, 20.8), "FabricRed")


def l_festival(mb):
    # entry arch facing the road
    for s in (-1, 1):
        mb.box((1.4, 1.4, 10.0), (s * 8.0, 11.0, 5.0), "White")
        mb.box((1.6, 1.6, 0.6), (s * 8.0, 11.0, 0.3), "FabricRed")
    mb.box((17.4, 1.6, 2.6), (0, 11.0, 10.3), "FabricRed")
    mb.box((13.0, 1.7, 1.4), (0, 11.0, 10.3), "SignWhite")
    mb.box((17.6, 1.8, 0.2), (0, 11.0, 11.7), "Lamp")
    # main stage
    with mb.xf(tr(0, -8.0, 0)):
        mb.box((14.0, 8.0, 1.6), (0, 0, 0.3), "Black")
        for sx in (-1, 1):
            for sy in (-1, 1):
                mb.box((0.45, 0.45, 9.0), (sx * 6.8, sy * 3.8, 4.5), "Metal")
                mb.box((1.4, 1.4, 3.2), (sx * 8.4, 3.0 + sy * 0.0, 1.6), "Black")
        mb.box((14.6, 8.6, 0.7), (0, 0, 9.2), "FabricBlue")
        mb.box((14.6, 0.5, 1.4), (0, 4.1, 8.6), "Metal")
        mb.box((11.0, 0.3, 5.5), (0, -3.6, 4.5), "SignBlue")
        mb.box((10.0, 0.35, 4.7), (0, -3.6, 4.5), "Lamp")
    # tents
    for (x, y, m) in ((-12.0, 1.0, "FabricRed"), (12.0, 1.0, "FabricBlue"), (-11.0, -9.0, "FabricYellow"), (11.0, -9.0, "FabricRed")):
        mb.box((4.4, 4.4, 2.3), (x, y, 1.15), "Fabric")
        hip_roof(mb, 4.4, 4.4, 2.3, 2.2, 0.3, m)
        mb.box((0.06, 0.06, 1.0), (x, y, 5.0), "Metal")
    # flag poles along the front
    fabrics = ["FabricRed", "FabricBlue", "FabricYellow"]
    for k in range(8):
        x = -16.0 + k * (32.0 / 7)
        if abs(x) < 9.0:
            continue
        mb.box((0.12, 0.12, 8.0), (x, 14.0, 4.0), "Metal")
        mb.box((0.04, 1.4, 2.4), (x, 14.75, 6.6), fabrics[k % 3])
    # bunting posts and benches in the plaza
    for (x, y) in ((-5.0, 3.0), (5.0, 3.0), (-5.0, -1.0), (5.0, -1.0)):
        mb.box((2.2, 0.6, 0.45), (x, y, 0.45), "Wood")
        mb.box((2.2, 0.08, 0.5), (x, y - 0.3, 0.9), "Wood")


def l_viewpoint(mb):
    mb.box((5.0, 3.0, 0.25), (0, 0, 0.75), "Wood")
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.2, 0.2, 1.8), (sx * 2.3, sy * 1.3, 0.0), "WoodDark")
    railing(mb, -2.45, 2.45, -1.45, 0.87, mat="Wood", post_gap=0.6)
    with mb.xf(rot_z(math.pi / 2)):
        railing(mb, -1.45, 1.45, 2.45, 0.87, mat="Wood", post_gap=0.6)
        railing(mb, -1.45, 1.45, -2.45, 0.87, mat="Wood", post_gap=0.6)
    mb.box((1.8, 0.45, 0.08), (-1.0, 0.3, 1.32), "Wood")
    for s in (-1, 1):
        mb.box((0.08, 0.4, 0.45), (-1.0 + s * 0.8, 0.3, 1.1), "WoodDark")
    mb.box((0.12, 0.12, 1.2), (1.4, -0.6, 1.47), "Metal")
    mb.box((0.45, 0.25, 0.22), (1.4, -0.65, 2.15), "SignGreen")
    for s in (-1, 1):
        mb.cyl(0.06, 0.06, 0.15, (1.4 + s * 0.1, -0.78, 2.18), "Black", seg=8, axis=(0, -1, 0))
    with mb.xf(tr(0, 2.6, 0)):
        for s in (-1, 1):
            mb.box((0.1, 0.1, 1.6), (s * 0.6, 0, 0.8), "WoodDark")
        mb.box((1.4, 0.08, 0.9), (0, 0, 1.4), "SignGreen")
        mb.box((1.2, 0.1, 0.7), (0, 0.0, 1.4), "SignWhite")


def l_wind_turbine(mb):
    mb.cyl(3.2, 3.2, 1.6, (0, 0, -0.8), "Concrete", seg=16, smooth=False)
    mb.cyl(1.9, 1.1, 62.0, (0, 0, 0.6), "White", seg=16)
    mb.box((2.3, 5.8, 2.3), (0, -0.9, 63.6), "White")
    mb.box((2.35, 1.5, 0.3), (0, -2.8, 64.6), "Metal")


def l_wind_turbine_rotor(mb):
    """Hub at the origin, rotation axis +Y (the engine spins it)."""
    mb.cyl(1.1, 0.15, 2.0, (0, 0.2, 0), "White", seg=14, axis=(0, 1, 0))
    mb.cyl(1.15, 1.15, 0.6, (0, -0.4, 0), "White", seg=14, axis=(0, 1, 0))
    for k in range(3):
        a = 2 * math.pi * k / 3
        R = Matrix.Rotation(a, 4, "Y")
        with mb.xf(R):
            rows = []
            for i in range(8):
                t = i / 7
                r = 0.9 + t * 30.0
                chord = 2.4 * (1 - t) + 0.45 * t if t > 0.12 else 1.2 + t * 9.0
                thick = 0.42 * (1 - t) + 0.08 * t
                tw = math.radians(14.0 * (1 - t))
                c, s = math.cos(tw), math.sin(tw)
                pts = [(-chord * 0.3, -thick / 2), (chord * 0.7, 0.0), (-chord * 0.3, thick / 2)]
                rows.append([Vector((x * c - y * s, x * s + y * c, r)) for x, y in pts] +
                            [Vector((pts[0][0] * c - pts[0][1] * s, pts[0][0] * s + pts[0][1] * c, r))])
            mb.quad_strip(rows, "White", smooth=True)


LANDMARKS = {"lighthouse": l_lighthouse, "castle": l_castle, "festival": l_festival, "viewpoint": l_viewpoint,
             "wind_turbine": l_wind_turbine}


# ---------------------------------------------------------------- road kit
def r_bridge_pillar(mb):
    """Unit pier 8 (across) x 2.2 (along) x 10 (high); the engine scales it per bridge."""
    mb.box((7.0, 2.6, 0.8), (0, 0, 0.4), "Concrete")
    for s in (-1, 1):
        mb.cyl(0.95, 0.85, 8.4, (s * 2.4, 0, 0.6), "Concrete", seg=8, smooth=False)
    mb.box((8.0, 2.2, 1.1), (0, 0, 9.45), "Concrete")
    mb.box((7.4, 1.9, 0.5), (0, 0, 8.7), "Concrete")
    mb.box((8.1, 0.15, 0.25), (0, 1.1, 9.85), "StoneDark")
    mb.box((8.1, 0.15, 0.25), (0, -1.1, 9.85), "StoneDark")


def r_bridge_abutment(mb):
    """Unit abutment 8 x 2.2 x 10, battered faces and a bearing shelf on top."""
    bm = mb.bm
    w0, w1, d0, d1 = 4.3, 4.0, 1.4, 1.1
    lo = [(-w0, -d0, 0.0), (w0, -d0, 0.0), (w0, d0, 0.0), (-w0, d0, 0.0)]
    hi = [(-w1, -d1, 9.2), (w1, -d1, 9.2), (w1, d1, 9.2), (-w1, d1, 9.2)]
    a = [bm.verts.new(p) for p in lo]
    b = [bm.verts.new(p) for p in hi]
    faces = [bm.faces.new(a[::-1]), bm.faces.new(b)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    mb._finish(a + b, "Concrete", False)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    mb.box((8.4, 2.6, 0.8), (0, 0, 9.6), "Concrete")
    for k in range(3):
        mb.box((8.5, 0.08, 0.12), (0, 1.32 - 0.02 * k, 2.5 + k * 2.5), "StoneDark")


def r_rail_post(mb):
    mb.box((0.1, 0.16, 1.0), (0, 0, 0.42), "Steel")
    mb.box((0.14, 0.2, 0.05), (0, 0, 0.93), "Steel")


def r_reflector_post(mb):
    mb.box((0.12, 0.12, 1.1), (0, 0, 0.5), "White")
    mb.box((0.13, 0.13, 0.25), (0, 0, 0.84), "Black")
    mb.box((0.07, 0.14, 0.13), (0, 0, 0.86), "Reflector")
    mb.box((0.122, 0.122, 0.04), (0, 0, 1.06), "Black")


def r_street_lamp(mb):
    mb.cyl(0.2, 0.18, 0.6, (0, 0, -0.1), "Black", seg=10)
    mb.cyl(0.09, 0.065, 5.6, (0, 0, 0.5), "Black", seg=10)
    mb.cyl(0.05, 0.05, 1.5, (0, 0, 5.95), "Black", seg=8, axis=(0, 1, 0.08))
    mb.box((0.36, 0.62, 0.16), (0, 1.35, 6.0), "Black")
    mb.box((0.28, 0.5, 0.04), (0, 1.35, 5.91), "Lamp")


PORTAL_HALF = 5.4  # tunnel tube half width (hw + 0.9) the portal is authored for


def r_tunnel_portal(col):
    """Concrete facade with the tunnel profile cut out (boolean), arch ring, cornice and wing walls.
    The tunnel runs towards -Y; the engine scales X by (hw + 0.9) / PORTAL_HALF."""
    mb = MB()
    mb.box((32.0, 1.4, 15.0), (0, 0.3, 5.0), "Concrete")
    wall_ob = mb.to_object("_tmp_portal", col)
    hw = PORTAL_HALF - 0.9
    prof = [(-PORTAL_HALF, -3.0), (-PORTAL_HALF, 4.4), (-hw * 0.55, 6.5), (0.0, 7.0), (hw * 0.55, 6.5), (PORTAL_HALF, 4.4), (PORTAL_HALF, -3.0)]
    cut = MB()
    cut.poly_prism(prof[::-1], -2.0, 3.0, "Concrete")
    cut_ob = cut.to_object("_tmp_cut", col)
    mod = wall_ob.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cut_ob
    try:
        mod.solver = "EXACT"
    except TypeError:
        pass
    C.apply_modifiers(wall_ob)
    me = cut_ob.data
    bpy.data.objects.remove(cut_ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    mb2 = MB()
    # arch ring following the opening
    pr = [(-PORTAL_HALF, -0.1)] + prof[1:-1] + [(PORTAL_HALF, -0.1)]
    for (x0, z0), (x1, z1) in zip(pr[:-1], pr[1:]):
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz)
        nrm = Vector((-dz, 0, dx)) / ln
        c = Vector(((x0 + x1) / 2, 1.2, (z0 + z1) / 2)) + nrm * 0.35
        mb2.box((ln + 0.7, 1.0, 0.7), c, "StoneDark", rot=Matrix.Rotation(math.atan2(-dz, dx), 3, "Y"))
    mb2.box((33.0, 2.2, 0.7), (0, 0.6, 12.85), "StoneDark")
    mb2.box((7.0, 0.2, 1.3), (0, 1.05, 9.2), "SignWhite")
    mb2.box((6.4, 0.25, 0.9), (0, 1.07, 9.2), "SignBlue")
    for s in (-1, 1):
        with mb2.xf(tr(s * 15.8, 0.6, 0) @ rot_z(s * math.radians(35))):
            bm = mb2.bm
            L, T = 11.0, 1.0
            pts = [(0, -T / 2, -3.0), (s * L, -T / 2, -3.0), (s * L, T / 2, -3.0), (0, T / 2, -3.0),
                   (0, -T / 2, 12.5), (s * L, -T / 2, 1.0), (s * L, T / 2, 1.0), (0, T / 2, 12.5)]
            v = [bm.verts.new(p) for p in pts]
            faces = [bm.faces.new((v[0], v[1], v[2], v[3])), bm.faces.new((v[4], v[5], v[6], v[7])),
                     bm.faces.new((v[0], v[1], v[5], v[4])), bm.faces.new((v[1], v[2], v[6], v[5])),
                     bm.faces.new((v[2], v[3], v[7], v[6])), bm.faces.new((v[3], v[0], v[4], v[7]))]
            mb2._finish(v, "Concrete", False)
            bmesh.ops.recalc_face_normals(bm, faces=faces)
    ring = mb2.to_object("_tmp_ring", col)
    C.join_into(wall_ob, [ring])
    wall_ob.name = "tunnel_portal"
    wall_ob.data.name = "tunnel_portal"
    return wall_ob


# ---------------------------------------------------------- activity props
def a_jump_ramp(mb):
    """Driving direction +Y. Linear kicker 5 m wide, 12 m long, 2.8 m high (13 deg), starting at the origin."""
    w, L, h = 2.5, 12.0, 2.8
    bm = mb.bm
    pts = [(-w, 0, 0), (w, 0, 0), (w, L, 0), (-w, L, 0), (-w, L, h), (w, L, h)]
    v = [bm.verts.new(p) for p in pts]
    top = bm.faces.new((v[0], v[1], v[5], v[4]))
    rest = [bm.faces.new((v[3], v[2], v[1], v[0])), bm.faces.new((v[2], v[3], v[4], v[5])),
            bm.faces.new((v[1], v[2], v[5])), bm.faces.new((v[0], v[4], v[3]))]
    mb._finish(v, "SignYellow", False)
    bmesh.ops.recalc_face_normals(bm, faces=[top] + rest)
    top.material_index = mb.mi("WoodDark")
    rest[1].material_index = mb.mi("Black")
    # chevrons along the sides and the lip
    for s in (-1, 1):
        for k in range(5):
            y = 1.5 + k * 2.2
            z = h * y / L
            mb.box((0.06, 0.9, 0.35), (s * (w + 0.02), y, z * 0.5), "Black", rot=Matrix.Rotation(s * 0.6, 3, "X"))
    mb.box((2 * w + 0.1, 0.25, 0.08), (0, L - 0.15, h + 0.0), "SignYellow")
    for s in (-1, 1):
        mb.box((0.15, 0.15, 1.2), (s * (w + 0.6), 0.5, 0.6), "White")
        mb.box((0.16, 0.16, 0.25), (s * (w + 0.6), 0.5, 1.05), "Reflector")


def a_speedtrap_camera(mb):
    mb.cyl(0.14, 0.12, 4.2, (0, 0, -0.2), "Metal", seg=10)
    mb.box((0.5, 0.7, 0.45), (0, 0.2, 3.9), "SignYellow")
    mb.cyl(0.13, 0.13, 0.12, (0, 0.6, 3.9), "Black", seg=12, axis=(0, 1, 0))
    mb.box((1.0, 0.08, 1.0), (0, -0.2, 2.8), "SignWhite", rot=Matrix.Rotation(math.pi / 4, 3, "Y"))
    mb.box((0.8, 0.1, 0.8), (0, -0.21, 2.8), "SignBlue", rot=Matrix.Rotation(math.pi / 4, 3, "Y"))


def a_zone_banner(mb):
    """Gate across a road; 1 unit = 10 m wide (the engine scales X to the road width)."""
    for s in (-1, 1):
        mb.box((0.35, 0.35, 6.2), (s * 5.0, 0, 3.1), "White")
        mb.box((0.6, 0.6, 0.4), (s * 5.0, 0, 0.2), "Black")
    mb.box((10.4, 0.25, 1.3), (0, 0, 5.6), "FabricRed")
    mb.box((9.0, 0.3, 0.7), (0, 0, 5.6), "SignWhite")


def a_race_arch(mb):
    """Start / finish arch; 1 unit = 10 m wide (scaled to the road)."""
    for s in (-1, 1):
        mb.box((1.0, 1.4, 7.5), (s * 5.4, 0, 3.75), "FabricBlue")
        mb.box((1.2, 1.6, 0.5), (s * 5.4, 0, 0.25), "Black")
    mb.box((11.8, 1.4, 1.8), (0, 0, 7.8), "FabricBlue")
    mb.box((9.0, 1.5, 0.9), (0, 0, 7.8), "SignWhite")
    for k in range(8):
        mb.box((0.62, 1.52, 0.42), (-3.8 + k * 1.08, 0, 7.8), "Black" if k % 2 == 0 else "SignWhite")
    mb.box((12.0, 1.6, 0.15), (0, 0, 8.8), "Lamp")


def _post(mb, x, h, r=0.045, y=-0.07):
    """Sign post behind the plate (plates face +Y)."""
    mb.cyl(r, r, h, (x, y, -0.3), "Steel", seg=8)


def r_sign_speed(mb):
    """Round speed-limit plate on a post; the face (+Y) looks at approaching traffic."""
    _post(mb, 0.0, 2.75)
    mb.cyl(0.42, 0.42, 0.03, (0, 0.03, 2.1), "SignRed", seg=24, axis=(0, 1, 0), smooth=False)
    mb.cyl(0.33, 0.33, 0.03, (0, 0.045, 2.1), "SignWhite", seg=24, axis=(0, 1, 0), smooth=False)
    for x in (-0.11, 0.11):  # stylised two-digit number
        mb.box((0.13, 0.03, 0.26), (x, 0.075, 2.1), "Black")
        mb.box((0.07, 0.035, 0.16), (x, 0.08, 2.1), "SignWhite")
    mb.cyl(0.42, 0.42, 0.02, (0, 0.0, 2.1), "Steel", seg=24, axis=(0, -1, 0), smooth=False)


def r_sign_chevron(mb):
    """Curve chevron board, faced both ways (the arrow flips correctly for each direction)."""
    _post(mb, 0.0, 1.6, y=0.0)
    for face in (1, -1):
        y = 0.06 * face
        mb.box((0.9, 0.02, 0.6), (0, y, 1.1), "SignYellow")
        for s in (1, -1):
            R = Matrix.Rotation(s * math.radians(40), 3, "Y")
            mb.box((0.36, 0.025, 0.12), (0.05 * face - 0.0, y + 0.012 * face, 1.1 + s * 0.11), "Black", rot=R)


def r_sign_warning(mb):
    """Red-bordered warning triangle (generic hazard) on a post."""
    _post(mb, 0.0, 2.6)
    k = math.sqrt(3) / 2
    big = [(-0.48, 1.62), (0.48, 1.62), (0.0, 1.62 + 0.96 * k)]
    small = [(-0.34, 1.7), (0.34, 1.7), (0.0, 1.7 + 0.68 * k)]
    mb.poly_prism(big, 0.0, 0.03, "SignRed")
    mb.poly_prism(small, 0.03, 0.05, "SignWhite")
    mb.box((0.06, 0.03, 0.2), (0, 0.06, 1.98), "Black")
    mb.box((0.06, 0.03, 0.06), (0, 0.06, 1.8), "Black")


def r_sign_direction(mb):
    """Green direction board on two posts with white border, arrow and text bars."""
    for x in (-0.85, 0.85):
        _post(mb, x, 3.2, r=0.06)
    mb.box((2.2, 0.05, 1.1), (0, 0.04, 2.4), "SignGreen")
    mb.box((2.1, 0.055, 1.0), (0, 0.042, 2.4), "SignWhite")
    mb.box((2.0, 0.06, 0.9), (0, 0.045, 2.4), "SignGreen")
    for k, w in enumerate((1.1, 0.8, 0.95)):
        mb.box((w, 0.065, 0.08), (-0.25 + (w - 1.1) / 2, 0.05, 2.65 - k * 0.22), "SignWhite")
    mb.box((0.28, 0.065, 0.1), (0.62, 0.05, 2.4), "SignWhite")
    mb.poly_prism([(0.76, 2.25), (0.93, 2.4), (0.76, 2.55)], 0.045, 0.08, "SignWhite")


PROPS = {"sign_speed": r_sign_speed, "sign_chevron": r_sign_chevron, "sign_warning": r_sign_warning,
         "sign_direction": r_sign_direction, "bridge_pillar": r_bridge_pillar, "bridge_abutment": r_bridge_abutment, "rail_post": r_rail_post,
         "reflector_post": r_reflector_post, "street_lamp": r_street_lamp, "jump_ramp": a_jump_ramp,
         "speedtrap_camera": a_speedtrap_camera, "zone_banner": a_zone_banner, "race_arch": a_race_arch}


# ------------------------------------------------------------------ vegetation
def v_tree_broadleaf(mb, lod):
    seg = 7 if lod == 0 else 5
    mb.cyl(0.34, 0.2, 4.4, (0, 0, -0.3), "Bark", seg=seg)
    if lod == 0:
        for k, (a, l) in enumerate(((0.3, 2.4), (2.4, 2.1), (4.3, 2.3))):
            d = Vector((math.cos(a) * 0.75, math.sin(a) * 0.75, 0.66))
            mb.cyl(0.13, 0.06, l, (0, 0, 3.0 + k * 0.35), "Bark", seg=5, axis=d)
        blobs = [((0.0, 0.0, 6.3), 2.6), ((1.7, 0.5, 5.4), 2.0), ((-1.6, -0.6, 5.6), 2.1), ((0.4, -1.7, 5.2), 1.9),
                 ((-0.6, 1.6, 5.8), 2.0), ((0.3, 0.2, 7.6), 1.8)]
        for i, (c, r) in enumerate(blobs):
            mb.blob((r, r, r * 0.85), c, "LeavesBroad", subdiv=1, amp=0.2, freq=1.6, seed=i * 1.7)
    else:
        mb.blob((3.0, 3.0, 2.5), (0, 0, 6.0), "LeavesBroad", subdiv=1, amp=0.12, seed=0.5)


def v_tree_conifer(mb, lod):
    seg = 7 if lod == 0 else 4
    mb.cyl(0.26, 0.12, 4.0, (0, 0, -0.3), "Bark", seg=seg)
    if lod == 0:
        for k in range(5):
            z = 1.5 + k * 1.75
            r = 2.7 - k * 0.48
            vs = mb.cyl(r, 0.0, 3.1 - k * 0.2, (0, 0, z), "LeavesPine", seg=14, smooth=True)
            ring = sorted([v for v in vs if abs(v.co.z - z) < 1e-3], key=lambda v: math.atan2(v.co.y, v.co.x))
            for i, v in enumerate(ring):
                if i % 2:
                    v.co.x *= 0.78
                    v.co.y *= 0.78
                    v.co.z += 0.35
    else:
        mb.cyl(2.6, 0.0, 6.0, (0, 0, 1.4), "LeavesPine", seg=6)
        mb.cyl(1.7, 0.0, 5.0, (0, 0, 5.4), "LeavesPine", seg=6)


def v_tree_poplar(mb, lod):
    mb.cyl(0.24, 0.12, 3.6, (0, 0, -0.3), "Bark", seg=6 if lod == 0 else 4)
    if lod == 0:
        for i, (z, r, h) in enumerate(((4.4, 1.15, 2.2), (6.6, 1.35, 3.0), (9.2, 1.0, 2.4), (11.0, 0.6, 1.4))):
            mb.blob((r, r, h), (0.05 * i, 0, z), "Leaves", subdiv=1, amp=0.16, freq=2.0, seed=i * 2.3)
    else:
        mb.blob((1.3, 1.3, 4.8), (0, 0, 7.2), "Leaves", subdiv=1, amp=0.08, seed=0.3)


def v_tree_palm(mb, lod):
    n = 8 if lod == 0 else 4
    seg = 7 if lod == 0 else 4
    H = 8.5
    pts = [Vector((0.9 * (t / n) ** 2, 0.0, H * t / n)) for t in range(n + 1)]
    for i in range(n):
        d = pts[i + 1] - pts[i]
        r0 = 0.27 - 0.07 * i / n
        mb.cyl(r0 * 1.12, r0 * 0.92, d.length + 0.05, pts[i], "BarkPale", seg=seg, axis=d)
    top = pts[-1]
    fronds = 9 if lod == 0 else 6
    steps = 6 if lod == 0 else 2
    for k in range(fronds):
        a = 2 * math.pi * k / fronds + 0.3
        dirv = Vector((math.cos(a), math.sin(a), 0.0))
        side = Vector((-dirv.y, dirv.x, 0.0))
        L = 3.6 + 0.4 * math.sin(k * 2.1)
        rows = []
        for i in range(steps + 1):
            t = i / steps
            p = top + dirv * (L * t) + Vector((0, 0, 1.0 * t - 2.4 * t * t))
            w = 0.62 * math.sin(math.pi * min(t * 1.1 + 0.08, 1.0)) ** 0.8 + 0.04
            rows.append([p + side * w - Vector((0, 0, 0.12 * w)), p + Vector((0, 0, 0.06)), p - side * w - Vector((0, 0, 0.12 * w))])
        mb.quad_strip(rows, "PalmLeaf", smooth=True)
    if lod == 0:
        for k in range(3):
            a = 2 * math.pi * k / 3
            mb.blob((0.17, 0.17, 0.2), top + Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, -0.35)), "WoodDark", subdiv=1, amp=0.0)


def v_cactus(mb, lod):
    seg = 12 if lod == 0 else 6

    def column(base, h, r):
        vs = mb.cyl(r, r * 0.95, h, base, "Cactus", seg=seg, cap=False)
        if lod == 0:
            for v in vs:
                ang = math.atan2(v.co.y - base[1], v.co.x - base[0])
                k = 0.86 if (round(ang / (2 * math.pi / seg)) % 2) else 1.0
                v.co.x = base[0] + (v.co.x - base[0]) * k
                v.co.y = base[1] + (v.co.y - base[1]) * k
        mb.blob((r * 0.96, r * 0.96, r * 0.8), (base[0], base[1], base[2] + h), "Cactus", subdiv=1 if lod == 0 else 0, amp=0.0)

    column((0, 0, -0.3), 4.5, 0.38)
    for (z, dx, up, r) in ((1.7, 0.8, 1.6, 0.25), (2.5, -0.65, 1.2, 0.22)):
        s = 1 if dx > 0 else -1
        mb.cyl(r, r, abs(dx), (0, 0, z), "Cactus", seg=seg, axis=(s, 0, 0.35))
        column((dx, 0, z + 0.25), up, r)


def v_bush(mb, lod):
    if lod == 0:
        for i, (c, r) in enumerate((((0, 0, 0.55), 0.85), ((0.6, 0.3, 0.45), 0.6), ((-0.55, 0.2, 0.42), 0.62), ((0.1, -0.55, 0.4), 0.58))):
            mb.blob((r, r, r * 0.8), c, "LeavesBroad", subdiv=1, amp=0.22, freq=2.2, seed=i * 1.3, flat_bottom=0.5)
    else:
        mb.blob((1.1, 1.1, 0.75), (0, 0, 0.45), "LeavesBroad", subdiv=0, amp=0.1, flat_bottom=0.5)


def v_boulder(mb, lod):
    mb.blob((1.6, 1.25, 1.05), (0, 0, 0.35), "Rock", subdiv=2 if lod == 0 else 1, amp=0.32, freq=1.3, seed=4.2, smooth=False)


def v_tree_umbrella(mb, lod):
    seg = 7 if lod == 0 else 4
    lean = Vector((0.18, 0.05, 1.0))
    mb.cyl(0.32, 0.2, 6.6, (0, 0, -0.3), "Bark", seg=seg, axis=lean)
    top = Vector((0, 0, -0.3)) + lean.normalized() * 6.6
    if lod == 0:
        for d in (Vector((0.8, 0.4, 1.0)), Vector((-0.7, -0.3, 1.0)), Vector((0.1, -0.9, 0.9))):
            mb.cyl(0.16, 0.08, 2.2, top, "Bark", seg=5, axis=d)
        for i, (x, y, r) in enumerate(((0.0, 0.0, 2.8), (2.0, 0.8, 2.0), (-2.0, -0.5, 2.1), (0.5, -2.0, 1.9), (-0.6, 2.0, 1.9))):
            mb.blob((r, r, r * 0.42), (top.x + x, top.y + y, top.z + 1.6 + 0.25 * math.sin(i)), "LeavesOlive",
                    subdiv=1, amp=0.18, freq=1.8, seed=i * 0.9)
    else:
        mb.blob((4.2, 4.2, 1.3), (top.x, top.y, top.z + 1.6), "LeavesOlive", subdiv=1, amp=0.1, seed=1.1)


def v_shrub_dry(mb, lod):
    if lod == 0:
        for i, (c, r) in enumerate((((0, 0, 0.32), 0.55), ((0.35, 0.2, 0.25), 0.4), ((-0.3, -0.2, 0.22), 0.42))):
            mb.blob((r, r, r * 0.65), c, "LeavesDry", subdiv=1, amp=0.35, freq=3.0, seed=i * 2.7, flat_bottom=0.4)
        for k in range(4):
            a = k * 1.7
            mb.cyl(0.025, 0.01, 0.9, (0, 0, 0.0), "BarkPale", seg=4, axis=(math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0))
    else:
        mb.blob((0.7, 0.7, 0.45), (0, 0, 0.25), "LeavesDry", subdiv=0, amp=0.15, flat_bottom=0.4)


def v_grass_clump(mb, lod):
    rng = random.Random(7)
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r0 = rng.uniform(0.0, 0.14)
        base = Vector((math.cos(a) * r0, math.sin(a) * r0, -0.02))
        out = Vector((math.cos(a), math.sin(a), 0.0))
        side = Vector((-out.y, out.x, 0.0))
        h = rng.uniform(0.45, 0.8)
        lean = rng.uniform(0.12, 0.3)
        rows = []
        for i in range(3):
            t = i / 3
            p = base + out * (lean * t * t * h) + Vector((0, 0, h * t))
            w = 0.045 * (1 - t) + 0.008
            rows.append([p - side * w, p + side * w])
        rows.append([base + out * (lean * h) + Vector((0, 0, h))])
        mb.quad_strip(rows, "Grass", smooth=True)


VEGETATION = {"tree_broadleaf": v_tree_broadleaf, "tree_conifer": v_tree_conifer, "tree_poplar": v_tree_poplar,
              "tree_palm": v_tree_palm, "cactus": v_cactus, "bush": v_bush, "boulder": v_boulder,
              "tree_umbrella": v_tree_umbrella, "shrub_dry": v_shrub_dry, "grass_clump": v_grass_clump}


# ------------------------------------------------------------------ drivers
def _export(objs, name):
    path = os.path.join(KIT_DIR, name + ".glb")
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        C.export_glb(objs, path)
    return path


def build_piece(name, export=True):
    """Build (replacing) one kit piece in FORZA_GODOT/Kit/<group>/ and export it. Returns stats."""
    group = ("Vegetation" if name in VEGETATION else "Buildings" if name in BUILDINGS else
             "Landmarks" if name in LANDMARKS else "Props")
    col = C.collection("FORZA_GODOT/Kit/%s/%s" % (group, name))
    C.clear_collection(col)
    objs = []
    if name in VEGETATION:
        for lod in ((0,) if name == "grass_clump" else (0, 1)):
            mb = MB(seed=sum(map(ord, name)))
            VEGETATION[name](mb, lod)
            objs.append(mb.to_object(name if lod == 0 else name + "_LOD1", col))
    elif name == "tunnel_portal":
        objs.append(r_tunnel_portal(col))
    else:
        fn = BUILDINGS.get(name) or LANDMARKS.get(name) or PROPS[name]
        mb = MB(seed=sum(map(ord, name)))
        fn(mb)
        objs.append(mb.to_object(name, col))
        if name == "wind_turbine":
            rb = MB()
            l_wind_turbine_rotor(rb)
            rotor = rb.to_object("wind_turbine_Rotor", col)
            rotor.location = (0, 2.1, 63.6)
            objs.append(rotor)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    path = _export(objs, name) if export else None
    return {"name": name, "objects": [o.name for o in objs], "tris": tris, "path": path}


ALL = list(VEGETATION) + list(BUILDINGS) + list(LANDMARKS) + ["tunnel_portal"] + list(PROPS)


def build_all(names=None, export=True):
    C.guard()
    out = []
    for n in names or ALL:
        out.append(build_piece(n, export))
    return out
