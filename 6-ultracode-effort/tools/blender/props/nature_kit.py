"""Sunward Roads - NATURE kit (Blender side, fully procedural bpy/bmesh).

Builds the collection SUNWARD_GODOT/Nature/NatureKit with one joined mesh object per prop (exact names from
docs/SYSTEM_CONTRACTS.md "Props"), origin at the base centre on the ground (Blender Z = 0), +Y = front:

  Tree_Oak_A, Tree_Oak_B, Tree_Pine_A, Tree_Pine_B, Tree_Poplar, Tree_Birch, Tree_Palm, Tree_Olive, Tree_Dead,
  Bush_A, Bush_B, Bush_Desert, Cactus_A, Cactus_B, Rock_A, Rock_B, Rock_C, Rock_Large, Rock_Red,
  Grass_Tuft, Flowers_Tuft, Reeds, Hay_Bale, Log_Pile

Style: semi-realistic low poly. Plain PBR materials (prefix NK_) whose base colour is multiplied by the corner colour
attribute "Col" (per-face / per-vertex tint, AO and colour variation; exported as COLOR_0). Foliage is solid faceted
clusters (no alpha), thin blades / palm fronds use double-sided materials. Trunks, rocks and roots continue a little
below Z = 0 so props sit into uneven terrain without gaps. In Blender the props are spread in a QA grid around
x = +80..+180 m, y = -120..-146 m (away from the player cars at the origin); the export moves each one to the origin.

Run inside Blender through the project MCP client (see tools/blender/props/run.sh):
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__', 'STEP': 'build'})
STEP: build (ONLY=[names] optional) | report | ref_on | ref_off | solo | unsolo | sheet | export | save | all
  report  per prop: height / below-ground depth / footprint / evaluated tris vs budget / islands / inverted closed
          shells / floating islands (BVH proximity + inside tests, ground = z <= 0.02) / degenerate faces / UV / Col
  ref_on  1.8 m reference posts next to every prop (collection _QA_NatureRef), ref_off deletes them
  solo    viewport-hide all other kit props for look() (tools/blender/props/look.sh), unsolo restores
  sheet   EEVEE contact sheet docs/blender_props/nature_kit.png (temporary camera/sun/ground in _QA, all restored)
  export  assets/imported/props/nature_kit.glb (each prop moved to the origin for the export, then restored) + verify
"""
import bpy
import bmesh
import json
import math
import os
import random
import struct
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree

EXPECTED_BLEND = (r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort"
                  r"\6.-opus-5.5-forza-ultracode-effort\Opus55ForzaUltracodeEffort.blend")
PROJECT = os.path.dirname(EXPECTED_BLEND)
GLB_PATH = os.path.join(PROJECT, 'assets', 'imported', 'props', 'nature_kit.glb')
SHEET_PATH = os.path.join(PROJECT, 'docs', 'blender_props', 'nature_kit.png')
TILE_DIR = os.path.join(PROJECT, 'qa_output', 'blender_look', 'nature_tiles')
PI = math.pi
Z = Vector((0.0, 0.0, 1.0))

NAMES = ['Tree_Oak_A', 'Tree_Oak_B', 'Tree_Pine_A', 'Tree_Pine_B', 'Tree_Poplar', 'Tree_Birch', 'Tree_Palm',
         'Tree_Olive', 'Tree_Dead', 'Bush_A', 'Bush_B', 'Bush_Desert', 'Cactus_A', 'Cactus_B', 'Rock_A', 'Rock_B',
         'Rock_C', 'Rock_Large', 'Rock_Red', 'Grass_Tuft', 'Flowers_Tuft', 'Reeds', 'Hay_Bale', 'Log_Pile']

# QA grid (Blender world XY of each prop origin)
LAYOUT = {
    'Tree_Oak_A': (80, -120), 'Tree_Oak_B': (95, -120), 'Tree_Pine_A': (109, -120), 'Tree_Pine_B': (120, -120),
    'Tree_Poplar': (130, -120), 'Tree_Birch': (140, -120), 'Tree_Palm': (151, -120), 'Tree_Olive': (162, -120),
    'Tree_Dead': (171, -120),
    'Rock_Large': (82, -136), 'Rock_Red': (93, -136), 'Rock_A': (100, -136), 'Rock_B': (105, -136),
    'Rock_C': (111, -136), 'Cactus_A': (117, -136), 'Cactus_B': (122, -136), 'Bush_A': (127, -136),
    'Bush_B': (131, -136), 'Bush_Desert': (135, -136),
    'Grass_Tuft': (82, -146), 'Flowers_Tuft': (84, -146), 'Reeds': (87, -146), 'Hay_Bale': (91, -146),
    'Log_Pile': (96, -146),
}

# budgets (evaluated triangles)
BUDGET = {'Tree_': 2500, 'Bush_': 600, 'Cactus_': 800, 'Rock_Large': 2000, 'Rock_': 700, 'Grass_Tuft': 80,
          'Flowers_Tuft': 80, 'Reeds': 800, 'Hay_Bale': 800, 'Log_Pile': 800}

# name: (sRGB 0-255, roughness, double_sided)
MATS = {
    'NK_Bark_Oak': ((96, 74, 54), 0.92, False),
    'NK_Bark_Pine': ((98, 68, 50), 0.92, False),
    'NK_Bark_PineUpper': ((168, 104, 66), 0.85, False),
    'NK_Bark_Birch': ((232, 228, 216), 0.75, False),
    'NK_Bark_BirchMark': ((56, 50, 44), 0.9, False),
    'NK_Bark_Palm': ((150, 128, 98), 0.9, False),
    'NK_Bark_Olive': ((122, 112, 96), 0.92, False),
    'NK_Wood_Dead': ((186, 174, 156), 0.85, False),
    'NK_Leaf_Oak': ((92, 128, 50), 0.8, False),
    'NK_Leaf_Oak2': ((112, 136, 52), 0.8, False),
    'NK_Leaf_Spruce': ((56, 92, 56), 0.82, False),
    'NK_Leaf_Pine': ((70, 102, 60), 0.82, False),
    'NK_Leaf_Poplar': ((96, 132, 52), 0.8, False),
    'NK_Leaf_Birch': ((134, 164, 66), 0.78, False),
    'NK_Leaf_Palm': ((96, 138, 56), 0.75, True),
    'NK_Leaf_PalmDry': ((164, 134, 82), 0.85, True),
    'NK_Palm_Crown': ((118, 118, 66), 0.85, False),
    'NK_Coconut': ((118, 92, 52), 0.7, False),
    'NK_Leaf_Olive': ((140, 154, 116), 0.8, False),
    'NK_Leaf_Bush': ((84, 120, 50), 0.82, False),
    'NK_Leaf_Bush2': ((66, 100, 52), 0.82, False),
    'NK_Leaf_Sage': ((150, 162, 132), 0.88, False),
    'NK_Wood_Sage': ((104, 90, 72), 0.92, False),
    'NK_Cactus': ((82, 128, 70), 0.6, False),
    'NK_Flower': ((255, 255, 255), 0.7, True),
    'NK_Rock': ((146, 143, 136), 0.88, False),
    'NK_Sandstone_1': ((206, 132, 88), 0.9, False),
    'NK_Sandstone_2': ((180, 102, 66), 0.9, False),
    'NK_Sandstone_3': ((226, 176, 124), 0.9, False),
    'NK_Sandstone_4': ((156, 84, 58), 0.9, False),
    'NK_Grass': ((112, 150, 60), 0.85, True),
    'NK_Reed': ((128, 140, 70), 0.85, True),
    'NK_Cattail': ((104, 68, 40), 0.9, False),
    'NK_Hay': ((214, 184, 108), 0.95, False),
    'NK_Log_Bark': ((96, 72, 52), 0.92, False),
    'NK_Log_End': ((204, 168, 118), 0.85, False),
}


# ------------------------------------------------------------------------------------------------------ utils
def srgb2lin(rgb):
    def c(x):
        x = x / 255.0
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return tuple(c(v) for v in rgb)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(a, b, x):
    if b == a:
        return 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def clamp01(c):
    return tuple(max(0.0, min(1.0, x)) for x in c)


def mul(c, k):
    if isinstance(k, (int, float)):
        return (c[0] * k, c[1] * k, c[2] * k)
    return (c[0] * k[0], c[1] * k[1], c[2] * k[2])


def rv(R, s=100.0):
    return Vector((R.uniform(0, s), R.uniform(0, s), R.uniform(0, s)))


def rotz(v, a):
    c, s = math.cos(a), math.sin(a)
    return Vector((v.x * c - v.y * s, v.x * s + v.y * c, v.z))


def dir_from(az, el):
    return Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))


def grow(R, start, d, length, segs, up=0.1, jitter=0.12):
    pts = [Vector(start)]
    d = Vector(d).normalized()
    step = length / segs
    for _ in range(segs):
        d = (d + Vector((R.uniform(-jitter, jitter), R.uniform(-jitter, jitter),
                         R.uniform(-jitter, jitter) + up))).normalized()
        pts.append(pts[-1] + d * step)
    return pts


def check_file():
    fp = bpy.data.filepath
    if os.path.normcase(os.path.abspath(fp)) != os.path.normcase(EXPECTED_BLEND):
        raise RuntimeError('BLOCKED: wrong blend file %s' % fp)


# ------------------------------------------------------------------------------------------------------ materials
def _sock(node, ident, out=False):
    return next(s for s in (node.outputs if out else node.inputs) if s.identifier == ident)


def make_mat(name):
    rgb, rough, double = MATS[name]
    lin = srgb2lin(rgb)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    out.location = (420, 0)
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (120, 0)
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.location = (-140, 80)
    vc = nt.nodes.new('ShaderNodeVertexColor')
    vc.layer_name = 'Col'
    vc.location = (-400, -40)
    _sock(mix, 'Factor_Float').default_value = 1.0
    _sock(mix, 'A_Color').default_value = (lin[0], lin[1], lin[2], 1.0)
    nt.links.new(_sock(vc, 'Color', True), _sock(mix, 'B_Color'))
    nt.links.new(_sock(mix, 'Result_Color', True), _sock(bsdf, 'Base Color'))
    _sock(bsdf, 'Roughness').default_value = rough
    _sock(bsdf, 'Metallic').default_value = 0.0
    _sock(bsdf, 'Emission Strength').default_value = 0.0
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    mat.use_backface_culling = not double
    mat.diffuse_color = (lin[0], lin[1], lin[2], 1.0)
    mat.roughness = rough
    mat.metallic = 0.0
    if 'DITHERED' in [i.identifier for i in bpy.types.Material.bl_rna.properties['surface_render_method'].enum_items]:
        mat.surface_render_method = 'DITHERED'
    return mat


# ------------------------------------------------------------------------------------------------------ builder
class PB:
    """One prop = one bmesh; parts are appended with per-face material, smooth flag and colour."""

    def __init__(self, name, seed):
        self.name = name
        self.R = random.Random(seed)
        self.bm = bmesh.new()
        self.cl = self.bm.loops.layers.float_color.new('Col')
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def add(self, verts, faces, mat, smooth=False, fcol=None, vcols=None):
        bm = self.bm
        bv = [bm.verts.new(Vector(v)) for v in verts]
        out = []
        for k, f in enumerate(faces):
            if len(set(f)) < 3:
                continue
            try:
                face = bm.faces.new([bv[i] for i in f])
            except ValueError:
                continue
            face.material_index = self.mi(mat[k] if isinstance(mat, (list, tuple)) else mat)
            face.smooth = smooth[k] if isinstance(smooth, (list, tuple)) else smooth
            face.normal_update()
            if vcols is not None:
                for lp, i in zip(face.loops, f):
                    c = clamp01(vcols[i])
                    lp[self.cl] = (c[0], c[1], c[2], 1.0)
            else:
                if callable(fcol):
                    c = fcol(face.calc_center_median(), face.normal)
                else:
                    c = fcol or (1.0, 1.0, 1.0)
                c = clamp01(c)
                for lp in face.loops:
                    lp[self.cl] = (c[0], c[1], c[2], 1.0)
            out.append(face)
        return out


_ICO = {}


def ico_data(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        # Blender counts the base icosahedron as subdivisions=1: sub 0 -> 20 tris, 1 -> 80, 2 -> 320
        bmesh.ops.create_icosphere(bm, subdivisions=sub + 1, radius=1.0)
        bm.verts.index_update()
        _ICO[sub] = ([v.co.copy() for v in bm.verts], [tuple(v.index for v in f.verts) for f in bm.faces])
        bm.free()
    return _ICO[sub]


def tube(pb, pts, radii, mat, sides=6, cap0=True, cap1=True, tip=0.0, tip_off=None, smooth=True, rfn=None,
         vfn=None, side_mat=None, cap_mat=None, twist=0.0, phase=0.0, post=None):
    """Generalised cylinder along a polyline (parallel-transport frames), outward winding, optional caps.
    rfn(i, j, a) radius multiplier; vfn(i, j, p) vertex colour; side_mat(i, j) per side-face material."""
    pts = [Vector(p) for p in pts]
    N = len(pts)
    T = []
    for i in range(N):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, N - 1)]
        T.append((b - a).normalized())
    ref = Vector((1, 0, 0)) if abs(T[0].x) < 0.9 else Vector((0, 1, 0))
    n = (ref - T[0] * ref.dot(T[0])).normalized()
    verts, cols = [], []
    for i in range(N):
        if i:
            n = T[i - 1].rotation_difference(T[i]) @ n
            n = (n - T[i] * n.dot(T[i])).normalized()
        b = T[i].cross(n)
        for j in range(sides):
            a = phase + twist * i + 2 * PI * j / sides
            r = radii[i] * (rfn(i, j, a) if rfn else 1.0)
            p = pts[i] + (n * math.cos(a) + b * math.sin(a)) * r
            verts.append(p)
            cols.append(vfn(i, j, p) if vfn else (1.0, 1.0, 1.0))
    faces, fmats, fsm = [], [], []
    for i in range(N - 1):
        for j in range(sides):
            j1 = (j + 1) % sides
            faces.append((i * sides + j, i * sides + j1, (i + 1) * sides + j1, (i + 1) * sides + j))
            fmats.append(side_mat(i, j) if side_mat else mat)
            fsm.append(smooth)
    if cap1:
        c = pts[-1] + T[-1] * tip + (Vector(tip_off) if tip_off is not None else Vector())
        verts.append(c)
        cols.append(vfn(N - 1, -1, c) if vfn else (1.0, 1.0, 1.0))
        ci = len(verts) - 1
        base = (N - 1) * sides
        for j in range(sides):
            faces.append((ci, base + j, base + (j + 1) % sides))
            fmats.append(cap_mat or mat)
            fsm.append(smooth and tip > 0.0)
    if cap0:
        c = pts[0]
        verts.append(c)
        cols.append(vfn(0, -1, c) if vfn else (1.0, 1.0, 1.0))
        ci = len(verts) - 1
        for j in range(sides):
            faces.append((ci, (j + 1) % sides, j))
            fmats.append(cap_mat or mat)
            fsm.append(False)
    if post:
        verts = [post(v) for v in verts]
    return pb.add(verts, faces, fmats, smooth=fsm, vcols=cols)


def blob(pb, c, r, mat, sub=1, amp=0.2, freq=1.4, squash=0.25, fcol=None, rot=None):
    """Faceted noise-displaced ellipsoid (leaf cluster / clump)."""
    vs, fs = ico_data(sub)
    R = pb.R
    off, off2 = rv(R), rv(R)
    out = []
    for v in vs:
        d = v.normalized()
        k = 1.0 + amp * noise.noise(d * freq + off) + 0.5 * amp * noise.noise(d * freq * 2.3 + off2)
        p = Vector((d.x * r[0], d.y * r[1], d.z * r[2] * ((1.0 - squash) if d.z < 0 else 1.0))) * k
        if rot is not None:
            p = rot @ p
        out.append(Vector(c) + p)
    return pb.add(out, fs, mat, smooth=False, fcol=fcol)


def leaf_fcol(R, z0, z1, tint, lo=0.58):
    def f(c, n):
        h = smoothstep(z0, z1, c.z)
        k = (lo + (1.0 - lo) * h) * (1.0 + 0.24 * min(0.0, n.z)) * R.uniform(0.86, 1.0)
        y = max(0.0, n.z) * 0.07
        return (tint[0] * k * (1 + y), tint[1] * k * (1 + 0.5 * y), tint[2] * k)
    return f


def bark_vfn(R, z0=-0.3, z1=1.2, lo=0.62, jit=(0.86, 1.0)):
    def f(i, j, p):
        k = lerp(lo, 1.0, smoothstep(z0, z1, p.z)) * R.uniform(*jit)
        return (k, k, k)
    return f


def lumpy(R, amp_base=0.16, amp=0.05, rings_base=2, freq=1.3):
    off = rv(R)

    def f(i, j, a):
        A = amp_base if i < rings_base else amp
        return 1.0 + A * noise.noise(Vector((math.cos(a) * freq, math.sin(a) * freq, i * 0.6)) + off)
    return f


def pine_tier(pb, c, z_rim, z_top, Rr, n, mat, rand=0.12, droop=0.25, notch=0.68, fcol=None, shift=(0.0, 0.0)):
    """Closed drooping conifer tier: apex on the trunk axis, jagged branch-tip rim, concave underside."""
    R = pb.R
    h = z_top - z_rim
    cx, cy = c[0], c[1]
    m = 2 * n
    ph = R.uniform(0, 2 * PI)
    rad = [Rr * (R.uniform(1 - rand, 1 + rand) if k % 2 == 0 else notch * R.uniform(0.92, 1.05)) for k in range(m)]
    angs = [ph + 2 * PI * k / m + (R.uniform(-0.1, 0.1) if k % 2 == 0 else 0.0) for k in range(m)]
    dz_tip = [droop * rad[k] * R.uniform(0.8, 1.2) for k in range(m)]

    def ring(fr, zf, off):
        return [Vector((cx + shift[0] * off + math.cos(angs[k]) * rad[k] * fr,
                        cy + shift[1] * off + math.sin(angs[k]) * rad[k] * fr, zf(k))) for k in range(m)]
    M = ring(0.5, lambda k: z_top - 0.42 * h - (0.08 * h if k % 2 == 0 else 0.0), 0.5)
    E = ring(1.0, lambda k: (z_rim - dz_tip[k]) if k % 2 == 0 else (z_rim + 0.12 * h), 1.0)
    U = ring(0.48, lambda k: z_rim + 0.22 * h, 0.6)
    verts = [Vector((cx, cy, z_top))] + M + E + U + [Vector((cx, cy, z_rim + 0.32 * h))]
    iM, iE, iU, iB = 1, 1 + m, 1 + 2 * m, 1 + 3 * m
    faces = []
    for k in range(m):
        k1 = (k + 1) % m
        faces.append((0, iM + k, iM + k1))
        faces.append((iM + k, iE + k, iE + k1, iM + k1))
        faces.append((iE + k, iU + k, iU + k1, iE + k1))
        faces.append((iB, iU + k1, iU + k))
    return pb.add(verts, faces, mat, smooth=False, fcol=fcol)


def blade(pb, base, azim, h, w, lean, curl, segs, mat, vfn, side_twist=0.0):
    """Curved tapering blade (open surface, double-sided material); vfn(t) -> colour along the blade."""
    dirh = Vector((math.cos(azim), math.sin(azim), 0.0))
    side = Vector((-math.sin(azim + side_twist), math.cos(azim + side_twist), 0.0))
    L = h * 1.04
    step = L / segs
    pts = [Vector(base)]
    for k in range(segs):
        t = (k + 0.5) / segs
        th = lean + curl * t * t
        pts.append(pts[-1] + (dirh * math.sin(th) + Z * math.cos(th)) * step)
    verts, cols, faces = [], [], []
    for k in range(segs):
        t = k / segs
        wk = w * (1.0 - t) ** 0.7 * 0.5
        verts += [pts[k] - side * wk, pts[k] + side * wk]
        cols += [vfn(t), vfn(t)]
    verts.append(pts[segs])
    cols.append(vfn(1.0))
    tipi = len(verts) - 1
    for k in range(segs - 1):
        a, b = 2 * k, 2 * k + 1
        faces.append((a, b, b + 2, a + 2))
    k = segs - 1
    faces.append((2 * k, 2 * k + 1, tipi))
    return pb.add(verts, faces, mat, smooth=True, vcols=cols)


def frond(pb, base, az, elev, L, width, droop, mat, K=10, fcol=None, fold=0.45):
    """Palm frond: arching midrib with a solid, serrated, Lambda-folded leaf blade (double-sided material)."""
    dirh = Vector((math.cos(az), math.sin(az), 0.0))
    pts = []
    for k in range(K + 1):
        s = k / K
        d = L * s
        pts.append(Vector(base) + dirh * (d * math.cos(elev)) + Z * (d * math.sin(elev) - droop * s * s * L))
    verts, faces = [], []
    for k in range(K):
        s = k / K
        Tk = (pts[min(k + 1, K)] - pts[max(k - 1, 0)]).normalized()
        S = Tk.cross(Z)
        if S.length < 1e-6:
            S = rotz(dirh, -PI / 2)
        S.normalize()
        U = S.cross(Tk).normalized()
        full = (k % 2 == 0)
        w = width * math.sin(PI * min(1.0, 0.1 + s * 0.92)) ** 0.7 * (1.0 if full else 0.6)
        fwd = Tk * (w * 0.35 if full else 0.0)
        C = pts[k]
        verts += [C, C + S * w - U * w * fold + fwd, C - S * w - U * w * fold + fwd]
    verts.append(pts[K])
    tipi = len(verts) - 1
    for k in range(K - 1):
        c0, r0, l0 = 3 * k, 3 * k + 1, 3 * k + 2
        c1, r1, l1 = c0 + 3, r0 + 3, l0 + 3
        faces.append((c0, r0, r1, c1))
        faces.append((c0, c1, l1, l0))
    k = K - 1
    faces.append((3 * k, 3 * k + 1, tipi))
    faces.append((3 * k, tipi, 3 * k + 2))
    return pb.add(verts, faces, mat, smooth=False, fcol=fcol)


def rock_mass(pb, center, size, mat, cuts=6, amp=0.12, sub=2, fcol=None, bottom=-0.55, cut_range=(0.62, 0.86),
              el_range=(-0.35, 1.2)):
    """Displaced icosphere with random planar facets (fractured look) and a flat bottom at unit z = bottom."""
    R = pb.R
    vs, fs = ico_data(sub)
    off, off2 = rv(R), rv(R)
    planes = []
    for _ in range(cuts):
        planes.append((dir_from(R.uniform(0, 2 * PI), R.uniform(*el_range)), R.uniform(*cut_range)))
    planes.append((Vector((0, 0, -1)), -bottom))
    pts = []
    for v in vs:
        p = v.normalized()
        p = p * (1.0 + amp * noise.noise(p * 1.6 + off) + 0.45 * amp * noise.noise(p * 3.7 + off2))
        for nrm, d in planes:
            k = p.dot(nrm)
            if k > d:
                p = p - nrm * (k - d)
        pts.append(Vector((center[0] + p.x * size[0], center[1] + p.y * size[1], center[2] + p.z * size[2])))
    return pb.add(pts, fs, mat, smooth=False, fcol=fcol)


def loft(pb, rings, seg_mats, top_c, bot_c, top_mat, bot_mat, fcol=None, smooth=False):
    """Closed loft through rings (each CCW seen from +Z, equal vertex count), fan caps at top/bottom centres."""
    m = len(rings[0])
    verts = [p for rg in rings for p in rg]
    faces, mats = [], []
    for i in range(len(rings) - 1):
        for j in range(m):
            j1 = (j + 1) % m
            faces.append((i * m + j, i * m + j1, (i + 1) * m + j1, (i + 1) * m + j))
            mats.append(seg_mats[i])
    verts.append(Vector(top_c))
    ti = len(verts) - 1
    base = (len(rings) - 1) * m
    for j in range(m):
        faces.append((ti, base + j, base + (j + 1) % m))
        mats.append(top_mat)
    verts.append(Vector(bot_c))
    bi = len(verts) - 1
    for j in range(m):
        faces.append((bi, (j + 1) % m, j))
        mats.append(bot_mat)
    return pb.add(verts, faces, mats, smooth=smooth, fcol=fcol)


# ------------------------------------------------------------------------------------------------------ trees
def tree_broadleaf(name, seed, P):
    pb = PB(name, seed)
    R = pb.R
    bark, leaf = P['bark'], P['leaf']
    th, r0 = P['trunk_h'], P['r0']
    lx, ly = P.get('lean', (0.0, 0.0))
    zs = [-0.3, 0.0, 0.5, 1.2, 2.0, th * 0.8, th]
    tp = []
    for k, z in enumerate(zs):
        f = max(z, 0.0) / th
        jx = R.uniform(-0.05, 0.05) if 0 < k < len(zs) - 1 else 0.0
        jy = R.uniform(-0.05, 0.05) if 0 < k < len(zs) - 1 else 0.0
        tp.append(Vector((lx * f * f + jx, ly * f * f + jy, z)))
    tr = [r0 * 1.5, r0 * 1.32, r0 * 1.08, r0, r0 * 0.94, r0 * 0.86, r0 * 0.8]
    tube(pb, tp, tr, bark, sides=8, rfn=lumpy(R, 0.2, 0.05), vfn=bark_vfn(R))
    top = tp[-1]
    tips, mids = [], []
    nl = P['limbs']
    a0 = R.uniform(0, 2 * PI)
    for k in range(nl):
        az = a0 + 2 * PI * k / nl + R.uniform(-0.3, 0.3)
        el = math.radians(R.uniform(*P['elev']))
        d = dir_from(az, el)
        start = top - Vector((0, 0, 0.3 + 0.35 * (k % 2)))
        L = R.uniform(*P['limb_len'])
        pts = grow(R, start, d, L, 5, up=P['limb_up'], jitter=0.12)
        rr = [lerp(r0 * 0.62, 0.07, (i / 5) ** 0.8) for i in range(6)]
        tube(pb, pts, rr, bark, sides=6, tip=0.12, vfn=bark_vfn(R, lo=0.85))
        tips.append((pts[-1], R.uniform(*P['cl_tip'])))
        mids.append((pts[3] + Vector((0, 0, P.get('mid_up', 0.7))), R.uniform(*P['cl_mid'])))
        for s in range(P['subs']):
            bi = 2 + s
            sgn = 1 if s % 2 == 0 else -1
            sd = rotz(d, sgn * R.uniform(0.55, 0.9))
            sd.z = max(sd.z, 0.0) + R.uniform(0.25, 0.5)
            spts = grow(R, pts[bi], sd, R.uniform(*P['sub_len']), 3, up=0.1, jitter=0.1)
            tube(pb, spts, [0.1, 0.075, 0.05, 0.03], bark, sides=4, tip=0.08, vfn=bark_vfn(R, lo=0.85))
            tips.append((spts[-1], R.uniform(*P['cl_sub'])))
    lpts = grow(R, top - Vector((0, 0, 0.3)), Vector((R.uniform(-0.1, 0.1), R.uniform(-0.1, 0.1), 1.0)),
                P['leader_len'], 4, up=0.0, jitter=0.07)
    tube(pb, lpts, [r0 * 0.55, r0 * 0.45, r0 * 0.35, 0.1, 0.06], bark, sides=6, tip=0.1, vfn=bark_vfn(R, lo=0.85))
    tips.append((lpts[-1] + Vector((0, 0, 0.2)), P['cl_leader']))
    for extra in P.get('extra', []):
        # filler cluster attached to the leader / trunk top by a short twig
        ex = Vector(extra[0])
        src = lpts[min(int(extra[2]), len(lpts) - 1)]
        tube(pb, [src, src.lerp(ex, 0.5), ex], [0.09, 0.06, 0.035], bark, sides=4, tip=0.05,
             vfn=bark_vfn(R, lo=0.85))
        tips.append((ex, extra[1]))
    clusters = tips + mids
    z0 = min(c.z - r for c, r in clusters)
    z1 = max(c.z + r for c, r in clusters)
    for c, r in clusters:
        tint = P['tints'][R.randrange(len(P['tints']))]
        rz = r * P.get('cl_flat', 0.82)
        blob(pb, c, (r * R.uniform(0.95, 1.12), r * R.uniform(0.95, 1.12), rz), leaf, sub=1, amp=0.2,
             squash=0.3, fcol=leaf_fcol(R, z0, z1, tint), rot=Matrix.Rotation(R.uniform(0, PI), 3, 'Z'))
    return pb


def tree_oak_a():
    return tree_broadleaf('Tree_Oak_A', 11, dict(
        bark='NK_Bark_Oak', leaf='NK_Leaf_Oak', trunk_h=3.2, r0=0.4, lean=(0.15, 0.1), limbs=5, elev=(22, 40),
        limb_len=(4.3, 5.1), limb_up=0.05, subs=1, sub_len=(1.9, 2.5), leader_len=4.3,
        cl_tip=(2.0, 2.4), cl_sub=(1.65, 2.0), cl_mid=(1.55, 1.85), cl_leader=2.4, cl_flat=0.72, mid_up=0.85,
        extra=[((1.7, -1.3, 7.9), 1.8, 3), ((-1.5, 1.6, 7.7), 1.8, 3)],
        tints=[(1.0, 1.0, 1.0), (0.9, 0.98, 0.82), (1.0, 0.96, 0.78), (0.86, 0.92, 0.84)]))


def tree_oak_b():
    return tree_broadleaf('Tree_Oak_B', 23, dict(
        bark='NK_Bark_Oak', leaf='NK_Leaf_Oak2', trunk_h=3.6, r0=0.36, lean=(-0.2, 0.12), limbs=4, elev=(38, 54),
        limb_len=(3.7, 4.3), limb_up=0.08, subs=2, sub_len=(1.6, 2.1), leader_len=4.6,
        cl_tip=(1.9, 2.25), cl_sub=(1.5, 1.8), cl_mid=(1.45, 1.7), cl_leader=2.3, cl_flat=0.85, mid_up=0.7,
        extra=[((1.4, 1.0, 9.6), 1.7, 3), ((-1.3, -1.1, 9.3), 1.7, 3)],
        tints=[(1.0, 1.0, 1.0), (0.94, 1.0, 0.86), (1.0, 0.94, 0.74), (0.9, 0.95, 0.9)]))


def conifer_fcol(R, H, tint):
    def f(c, n):
        h = smoothstep(0.0, H, c.z)
        if n.z >= 0.0:
            k = (0.74 + 0.26 * h) * R.uniform(0.84, 1.0)
            y = 0.06 * n.z
            return (tint[0] * k * (1 + y), tint[1] * k * (1 + 0.5 * y), tint[2] * k)
        k = (0.42 + 0.14 * h) * R.uniform(0.9, 1.0)
        return mul(tint, k)
    return f


def tree_conifer(name, seed, P):
    pb = PB(name, seed)
    R = pb.R
    H = P['H']
    r0 = P['r0']
    zt = H - 1.0
    nz = 8
    tp, tr = [], []
    for k in range(nz + 1):
        t = k / nz
        z = lerp(-0.3, zt, t)
        tp.append(Vector((R.uniform(-0.03, 0.03) if 0 < k < nz else 0.0,
                          R.uniform(-0.03, 0.03) if 0 < k < nz else 0.0, z)))
        tr.append(lerp(r0, 0.05, t ** 0.9) * (1.35 if k == 0 else 1.0))
    upper = P.get('upper_bark')
    upper_z = P.get('upper_z', 1e9)
    side_mat = (lambda i, j: upper if tp[i].z >= upper_z else P['bark']) if upper else None
    tube(pb, tp, tr, P['bark'], sides=7, tip=0.3, rfn=lumpy(R, 0.14, 0.04, 1), vfn=bark_vfn(R), side_mat=side_mat)
    fcol = conifer_fcol(R, H, P['tint'])
    n_t = P['n_tiers']
    z_last = H - P['top_gap']
    spacing = (z_last - P['z_first']) / (n_t - 1)
    for i in range(n_t):
        t = i / (n_t - 1)
        z_rim = P['z_first'] + spacing * i
        Rr = lerp(P['R_bottom'], P['R_top'], t ** P.get('r_pow', 1.0))
        h = P['h_factor'] * spacing
        sh = (R.uniform(-1, 1) * P.get('shift', 0.0), R.uniform(-1, 1) * P.get('shift', 0.0))
        pine_tier(pb, (0.0, 0.0), z_rim, z_rim + h, Rr, P['n_tips'], P['leaf'], rand=P.get('rand', 0.12),
                  droop=P['droop'], notch=P.get('notch', 0.68), fcol=fcol, shift=sh)
    # spire
    pine_tier(pb, (0.0, 0.0), H - P['spire'], H, P['R_spire'], 6, P['leaf'], rand=0.08, droop=0.2, notch=0.65,
              fcol=fcol)
    for (z, az, L) in P.get('stubs', []):
        d = dir_from(az, math.radians(R.uniform(-15, 20)))
        p0 = Vector((0, 0, z))
        tube(pb, [p0, p0 + d * L * 0.5, p0 + d * L], [0.06, 0.04, 0.02], P['bark'], sides=4, tip=0.05,
             vfn=bark_vfn(R, lo=0.9))
    return pb


def tree_pine_a():
    return tree_conifer('Tree_Pine_A', 31, dict(
        H=14.6, r0=0.3, bark='NK_Bark_Pine', leaf='NK_Leaf_Spruce', tint=(1.0, 1.0, 1.0), n_tiers=8, z_first=1.25,
        top_gap=2.7, R_bottom=3.2, R_top=0.95, r_pow=0.9, h_factor=1.8, n_tips=10, droop=0.32, rand=0.12,
        spire=2.6, R_spire=0.85))


def tree_pine_b():
    return tree_conifer('Tree_Pine_B', 37, dict(
        H=18.6, r0=0.36, bark='NK_Bark_Pine', upper_bark='NK_Bark_PineUpper', upper_z=8.5, leaf='NK_Leaf_Pine',
        tint=(1.0, 1.0, 1.0), n_tiers=7, z_first=6.4, top_gap=2.4, R_bottom=3.4, R_top=1.35, r_pow=1.0,
        h_factor=0.74, n_tips=9, droop=0.22, rand=0.22, notch=0.6, shift=0.25, spire=2.2, R_spire=1.0,
        stubs=[(2.6, 0.4, 0.55), (3.6, 2.6, 0.7), (4.7, 4.4, 0.6), (5.8, 1.6, 0.8), (6.3, 5.4, 0.5)]))


def tree_poplar():
    pb = PB('Tree_Poplar', 41)
    R = pb.R
    H = 16.0
    tp = [Vector((R.uniform(-0.04, 0.04) if 0 < k < 9 else 0.0, R.uniform(-0.04, 0.04) if 0 < k < 9 else 0.0,
                  lerp(-0.3, 14.0, k / 9))) for k in range(10)]
    tr = [lerp(0.3, 0.06, (k / 9) ** 0.9) * (1.35 if k == 0 else 1.0) for k in range(10)]
    tube(pb, tp, tr, 'NK_Bark_Oak', sides=7, tip=0.3, rfn=lumpy(R, 0.14, 0.04, 1), vfn=bark_vfn(R))
    for z, az in ((2.0, 0.3), (2.4, 2.4), (2.8, 4.4), (3.3, 1.3)):
        p0 = Vector((0, 0, z))
        d = dir_from(az, math.radians(62))
        pts = grow(R, p0, d, 1.6, 3, up=0.15, jitter=0.05)
        tube(pb, pts, [0.07, 0.05, 0.035, 0.02], 'NK_Bark_Oak', sides=4, tip=0.06, vfn=bark_vfn(R, lo=0.9))
    tints = [(1.0, 1.0, 1.0), (0.92, 0.98, 0.85), (1.0, 0.97, 0.8)]
    cl = []
    n = 13
    for k in range(n):
        t = k / (n - 1)
        z = lerp(3.3, 14.4, t)
        r = 0.45 + 1.25 * math.sin(PI * (0.14 + 0.86 * t) ** 0.78)
        cl.append(((R.uniform(-0.2, 0.2), R.uniform(-0.2, 0.2), z), (r * 0.95, r * 0.88, 1.35 + 0.35 * r)))
    for k in range(7):
        t = R.uniform(0.1, 0.8)
        z = lerp(3.3, 14.4, t)
        r = 0.45 + 1.25 * math.sin(PI * (0.14 + 0.86 * t) ** 0.78)
        a = R.uniform(0, 2 * PI)
        cl.append(((math.cos(a) * r * 0.75, math.sin(a) * r * 0.75, z), (0.7, 0.7, 1.0)))
    z0 = min(c[2] - r[2] for c, r in cl)
    z1 = max(c[2] + r[2] for c, r in cl)
    for c, r in cl:
        blob(pb, c, r, 'NK_Leaf_Poplar', sub=1, amp=0.18, squash=0.15,
             fcol=leaf_fcol(R, z0, z1, tints[R.randrange(3)], lo=0.6), rot=Matrix.Rotation(R.uniform(0, PI), 3, 'Z'))
    return pb


def tree_birch():
    pb = PB('Tree_Birch', 53)
    R = pb.R
    stems = []
    for (sx, sy, tx, ty, top, r0, nr) in ((0.0, 0.0, 0.35, 0.15, 8.4, 0.17, 14), (0.06, 0.04, -1.1, 0.5, 6.9, 0.12, 11)):
        pts = []
        for k in range(nr + 1):
            t = k / nr
            z = lerp(-0.25, top, t)
            sw = math.sin(t * PI * 0.9) * 0.12
            pts.append(Vector((sx + tx * t ** 1.4 + sw * (1 if tx > 0 else -1), sy + ty * t ** 1.4, z)))
        rad = [lerp(r0, 0.035, (k / nr) ** 0.95) * (1.3 if k == 0 else 1.0) for k in range(nr + 1)]
        marks = set()
        for i in range(nr):
            if pts[i].z < 0.55:
                marks.update((i, j) for j in range(7))
            elif R.random() < 0.6:
                j0 = R.randrange(7)
                for d in range(R.choice((1, 2, 2, 3))):
                    marks.add((i, (j0 + d) % 7))
        tube(pb, pts, rad, 'NK_Bark_Birch', sides=7, tip=0.25, vfn=bark_vfn(R, lo=0.9, jit=(0.92, 1.0)),
             side_mat=lambda i, j, mk=marks: 'NK_Bark_BirchMark' if (i, j) in mk else 'NK_Bark_Birch',
             rfn=lumpy(R, 0.12, 0.03, 1))
        stems.append(pts)
    tips = []
    for si, pts in enumerate(stems):
        nb = 7 if si == 0 else 5
        for b in range(nb):
            idx = int(lerp(len(pts) * 0.42, len(pts) - 2, b / max(1, nb - 1)))
            p0 = pts[idx]
            out = Vector((p0.x, p0.y, 0.0))
            base_az = math.atan2(out.y, out.x) if out.length > 0.08 else (0.3 if si == 0 else 3.4)
            az = base_az + (b * 2.39) % (2 * PI) - PI * 0.5 + R.uniform(-0.4, 0.4)
            d = dir_from(az, math.radians(R.uniform(30, 50)))
            L = R.uniform(1.6, 2.4) * (1.0 - 0.35 * b / nb)
            bp = grow(R, p0, d, L, 3, up=-0.04, jitter=0.1)
            tube(pb, bp, [0.05, 0.035, 0.025, 0.015], 'NK_Bark_Birch', sides=4, tip=0.05,
                 vfn=bark_vfn(R, lo=0.95))
            tips.append((bp[-1] + Vector((0, 0, -0.1)), R.uniform(0.8, 1.05)))
            if b % 2 == 0:
                tips.append((bp[2] + Vector((0, 0, 0.25)), R.uniform(0.62, 0.82)))
        tips.append((pts[-1] + Vector((0, 0, -0.2)), 1.05))
    z0 = min(c.z - r for c, r in tips)
    z1 = max(c.z + r for c, r in tips)
    tints = [(1.0, 1.0, 1.0), (0.94, 1.0, 0.82), (1.0, 0.95, 0.72), (0.88, 0.95, 0.86)]
    for c, r in tips:
        blob(pb, c, (r * 1.08, r * 1.0, r * 0.85), 'NK_Leaf_Birch', sub=1, amp=0.22, squash=0.25,
             fcol=leaf_fcol(R, z0, z1, tints[R.randrange(4)], lo=0.62), rot=Matrix.Rotation(R.uniform(0, PI), 3, 'Z'))
    return pb


def tree_palm():
    pb = PB('Tree_Palm', 61)
    R = pb.R
    N = 17
    Ht = 8.2
    pts, rad = [], []
    for k in range(N + 1):
        t = k / N
        pts.append(Vector((1.45 * t ** 1.7, 0.3 * t ** 2.0, lerp(-0.3, Ht, t))))
        if t < 0.1:
            r = lerp(0.36, 0.25, t / 0.1)
        else:
            r = lerp(0.24, 0.17, (t - 0.1) / 0.9)
        rad.append(r)
    ring_f = lambda i, j, a: (1.07 if i % 2 == 0 else 0.96) if i >= 2 else 1.0

    def palm_v(i, j, p):
        k = (1.0 if i % 2 == 0 else 0.78) * lerp(0.7, 1.0, smoothstep(-0.3, 1.5, p.z)) * R.uniform(0.92, 1.0)
        return (k, k, k)
    tube(pb, pts, rad, 'NK_Bark_Palm', sides=8, cap1=True, rfn=ring_f, vfn=palm_v)
    top = pts[-1]
    Tt = (pts[-1] - pts[-2]).normalized()
    crown = top + Tt * 0.22
    blob(pb, crown, (0.3, 0.3, 0.45), 'NK_Palm_Crown', sub=1, amp=0.08, squash=0.0,
         fcol=lambda c, n: mul((1, 1, 1), R.uniform(0.8, 1.0) * (0.75 + 0.25 * max(0.0, n.z))))
    for k in range(5):
        a = 2 * PI * k / 5 + R.uniform(-0.2, 0.2)
        cpos = crown + Vector((math.cos(a) * 0.27, math.sin(a) * 0.27, -0.28 + R.uniform(-0.05, 0.05)))
        blob(pb, cpos, (0.13, 0.13, 0.15), 'NK_Coconut', sub=1, amp=0.05, squash=0.0,
             fcol=lambda c, n: mul((1, 1, 1), R.uniform(0.75, 1.0)))

    def frond_col(dry):
        def f(c, n):
            k = R.uniform(0.8, 1.0) * (0.72 + 0.28 * abs(n.z))
            t = (0.95, 0.9, 0.8) if dry else (1.0, 1.0, 1.0)
            return mul(t, k)
        return f
    nf = 11
    for f in range(nf):
        az = 2 * PI * f / nf + R.uniform(-0.15, 0.15)
        el = math.radians(R.uniform(12, 52))
        frond(pb, crown + dir_from(az, 0.0) * 0.12 + Vector((0, 0, 0.12)), az, el, R.uniform(3.4, 4.1),
              R.uniform(0.42, 0.5), R.uniform(0.6, 0.95), 'NK_Leaf_Palm', K=10, fcol=frond_col(False))
    for f in range(3):
        az = 2 * PI * f / 3 + 0.6
        frond(pb, crown + Vector((0, 0, 0.25)), az, math.radians(72), 2.2, 0.32, 0.35, 'NK_Leaf_Palm', K=8,
              fcol=frond_col(False))
    for f in range(2):
        az = PI * f + 1.1
        frond(pb, crown + dir_from(az, 0.0) * 0.1 - Vector((0, 0, 0.1)), az, math.radians(-55), 2.4, 0.3, 0.12,
              'NK_Leaf_PalmDry', K=8, fcol=frond_col(True), fold=0.3)
    return pb


def tree_olive():
    pb = PB('Tree_Olive', 71)
    R = pb.R
    zs = [-0.25, 0.0, 0.35, 0.7, 1.05, 1.4]
    tp = [Vector((0.0 if k < 2 else R.uniform(-0.14, 0.14), 0.0 if k < 2 else R.uniform(-0.14, 0.14), z))
          for k, z in enumerate(zs)]
    tr = [0.46, 0.4, 0.33, 0.3, 0.29, 0.27]
    tube(pb, tp, tr, 'NK_Bark_Olive', sides=9, twist=0.35, rfn=lumpy(R, 0.24, 0.2, 2, freq=1.8),
         vfn=bark_vfn(R, lo=0.7))
    top = tp[-1]
    tips = []
    a0 = R.uniform(0, 2 * PI)
    for k in range(3):
        az = a0 + 2 * PI * k / 3 + R.uniform(-0.3, 0.3)
        d = dir_from(az, math.radians(R.uniform(30, 48)))
        pts = grow(R, top - Vector((0, 0, 0.15)), d, R.uniform(1.8, 2.3), 5, up=0.05, jitter=0.25)
        tube(pb, pts, [0.2, 0.17, 0.14, 0.11, 0.08, 0.055], 'NK_Bark_Olive', sides=6, tip=0.08,
             rfn=lumpy(R, 0.12, 0.12, 1, freq=2.0), vfn=bark_vfn(R, lo=0.85), twist=0.3)
        tips.append((pts[-1] + Vector((0, 0, 0.2)), R.uniform(1.1, 1.3)))
        for s in range(2):
            sd = rotz(d, (1 if s == 0 else -1) * R.uniform(0.6, 1.0))
            sd.z = abs(sd.z) + 0.3
            spts = grow(R, pts[2 + s], sd, R.uniform(0.9, 1.3), 3, up=0.1, jitter=0.2)
            tube(pb, spts, [0.07, 0.05, 0.035, 0.02], 'NK_Bark_Olive', sides=4, tip=0.05, vfn=bark_vfn(R, lo=0.9))
            tips.append((spts[-1] + Vector((0, 0, 0.1)), R.uniform(0.85, 1.05)))
    tips.append((Vector((top.x, top.y, 3.55)), 1.15))
    tube(pb, [top - Vector((0, 0, 0.2)), Vector((top.x * 0.5, top.y * 0.5, 2.6)), Vector((top.x, top.y, 3.4))],
         [0.12, 0.08, 0.04], 'NK_Bark_Olive', sides=5, tip=0.05, vfn=bark_vfn(R, lo=0.9))
    z0 = min(c.z - r * 0.7 for c, r in tips)
    z1 = max(c.z + r * 0.7 for c, r in tips)
    tints = [(1.0, 1.0, 1.0), (0.9, 0.96, 0.88), (1.0, 1.0, 0.92), (0.86, 0.9, 0.86)]
    for c, r in tips:
        blob(pb, c, (r * 1.15, r * 1.05, r * 0.68), 'NK_Leaf_Olive', sub=1, amp=0.24, squash=0.35,
             fcol=leaf_fcol(R, z0, z1, tints[R.randrange(4)], lo=0.6), rot=Matrix.Rotation(R.uniform(0, PI), 3, 'Z'))
    return pb


def tree_dead():
    pb = PB('Tree_Dead', 83)
    R = pb.R
    zs = [-0.25, 0.0, 0.6, 1.4, 2.2, 3.0, 3.7, 4.25]
    tp = [Vector((0.06 * (z / 4.25) + (R.uniform(-0.07, 0.07) if 0 < k < 7 else 0.0),
                  -0.1 * (z / 4.25) ** 2 + (R.uniform(-0.07, 0.07) if 0 < k < 7 else 0.0), z))
          for k, z in enumerate(zs)]
    tr = [0.36, 0.3, 0.25, 0.22, 0.19, 0.16, 0.14, 0.12]

    def dead_v(i, j, p):
        k = lerp(0.62, 1.0, smoothstep(-0.25, 1.4, p.z)) * R.uniform(0.82, 1.0)
        return (k, k * 0.98, k * 0.96)
    tube(pb, tp, tr, 'NK_Wood_Dead', sides=7, tip=0.45, tip_off=(0.09, 0.05, 0.0), rfn=lumpy(R, 0.2, 0.06, 2),
         vfn=dead_v, twist=0.15)
    for (k_i, az, el, L) in ((2, 0.4, 34, 1.7), (3, 2.5, 42, 2.0), (4, 4.3, 50, 1.6), (5, 1.4, 58, 1.4),
                             (5, 5.6, 30, 1.2)):
        p0 = tp[k_i]
        d = dir_from(az + R.uniform(-0.2, 0.2), math.radians(el))
        pts = grow(R, p0, d, L, 4, up=0.08, jitter=0.25)
        tube(pb, pts, [0.1, 0.075, 0.055, 0.035, 0.02], 'NK_Wood_Dead', sides=5, tip=0.06, vfn=dead_v)
        for s in range(1 if L < 1.5 else 2):
            sd = rotz(d, (1 if s == 0 else -1) * R.uniform(0.5, 0.9))
            sd.z = abs(sd.z) + 0.25
            spts = grow(R, pts[2 + s], sd, R.uniform(0.5, 0.9), 2, up=0.1, jitter=0.25)
            tube(pb, spts, [0.035, 0.022, 0.012], 'NK_Wood_Dead', sides=4, tip=0.04, vfn=dead_v)
    return pb


# ------------------------------------------------------------------------------------------------------ bushes / cacti
def bush(name, seed, mat, clusters, stems=(), tints=((1, 1, 1),), stem_mat='NK_Bark_Oak', sub=1, amp=0.22):
    pb = PB(name, seed)
    R = pb.R
    for s in stems:
        tube(pb, s, [0.035, 0.028, 0.02, 0.012][:len(s)], stem_mat, sides=4, tip=0.03,
             vfn=bark_vfn(R, z0=-0.05, z1=0.4, lo=0.7))
    z0 = min(c[2] - r[2] for c, r, *_ in clusters)
    z1 = max(c[2] + r[2] for c, r, *_ in clusters)
    for cl in clusters:
        c, r = cl[0], cl[1]
        sb = cl[2] if len(cl) > 2 else sub
        blob(pb, c, r, mat, sub=sb, amp=amp, squash=0.3, fcol=leaf_fcol(R, z0, z1, tints[R.randrange(len(tints))], 0.55),
             rot=Matrix.Rotation(R.uniform(0, PI), 3, 'Z'))
    return pb


def bush_a():
    cl = [((0.0, 0.0, 0.42), (0.72, 0.68, 0.52)), ((0.5, 0.18, 0.28), (0.5, 0.48, 0.4)),
          ((-0.46, 0.28, 0.3), (0.5, 0.5, 0.42)), ((0.1, -0.5, 0.27), (0.5, 0.48, 0.38)),
          ((-0.25, -0.28, 0.64), (0.46, 0.46, 0.4)), ((0.18, 0.16, 0.78), (0.46, 0.44, 0.34))]
    st = [[(0.0, 0.0, -0.05), (0.04, 0.02, 0.2), (0.06, 0.0, 0.4)],
          [(0.04, -0.03, -0.05), (0.2, -0.12, 0.14), (0.3, -0.25, 0.28)]]
    return bush('Bush_A', 101, 'NK_Leaf_Bush', cl, stems=st,
                tints=((1, 1, 1), (0.92, 1.0, 0.84), (1.0, 0.95, 0.78)))


def bush_b():
    cl = [((0.0, 0.0, 0.74), (0.5, 0.5, 0.48)), ((0.28, 0.14, 1.02), (0.42, 0.42, 0.4)),
          ((-0.24, 0.2, 1.05), (0.4, 0.4, 0.4)), ((0.06, -0.28, 0.96), (0.42, 0.42, 0.38)),
          ((0.02, 0.04, 1.22), (0.36, 0.36, 0.28)), ((0.3, -0.18, 0.52), (0.36, 0.36, 0.34))]
    st = [[(0.0, 0.0, -0.05), (0.03, 0.02, 0.3), (0.05, 0.0, 0.62)],
          [(0.05, 0.03, -0.05), (0.15, -0.06, 0.28), (0.24, -0.14, 0.5)],
          [(-0.03, 0.02, -0.05), (-0.12, 0.08, 0.35), (-0.18, 0.16, 0.8)]]
    return bush('Bush_B', 103, 'NK_Leaf_Bush2', cl, stems=st,
                tints=((1, 1, 1), (0.9, 0.98, 0.9), (1.0, 0.96, 0.84)))


def bush_desert():
    R = random.Random(107)
    cl = []
    for k in range(10):
        a = 2 * PI * k / 10 + R.uniform(-0.3, 0.3)
        rr = R.uniform(0.18, 0.42)
        cl.append(((math.cos(a) * rr, math.sin(a) * rr, R.uniform(0.38, 0.64)),
                   (R.uniform(0.17, 0.24), R.uniform(0.17, 0.24), R.uniform(0.13, 0.18)), 0))
    cl += [((0.0, 0.0, 0.55), (0.34, 0.32, 0.24), 1), ((0.22, -0.12, 0.42), (0.28, 0.26, 0.2), 1),
           ((-0.2, 0.14, 0.45), (0.28, 0.27, 0.2), 1)]
    st = []
    for k in range(4):
        a = 2 * PI * k / 4 + 0.4
        st.append([(math.cos(a) * 0.03, math.sin(a) * 0.03, -0.05), (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.18),
                   (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.38)])
    return bush('Bush_Desert', 109, 'NK_Leaf_Sage', cl, stems=st, stem_mat='NK_Wood_Sage',
                tints=((1, 1, 1), (0.92, 0.95, 1.0), (1.0, 0.97, 0.88)), amp=0.25)


def cactus_v(R):
    def f(i, j, p):
        k = (1.0 if j % 2 == 0 else 0.72) * lerp(0.75, 1.0, smoothstep(-0.2, 0.8, p.z)) * R.uniform(0.94, 1.0)
        return (k, k, k * 0.95)
    return f


def cactus_a():
    pb = PB('Cactus_A', 121)
    R = pb.R
    zs = [-0.25, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 2.9, 3.15, 3.32, 3.42]
    rr = [0.27, 0.28, 0.28, 0.28, 0.275, 0.27, 0.265, 0.255, 0.235, 0.19, 0.11]
    rib = lambda i, j, a: 1.0 if j % 2 == 0 else 0.84
    tube(pb, [(0, 0, z) for z in zs], rr, 'NK_Cactus', sides=16, tip=0.03, rfn=rib, vfn=cactus_v(R))
    # review fix: the second arm used zt 2.48 < z0 + 0.75 + 0.3, so its path rose to 2.47, dropped to 2.18 and rose
    # again -> the tube folded into a crumpled lump at the arm tip. Tip raised to 2.92 and the elbow height clamped so
    # the vertical part of every arm is monotonic.
    for (az, z0, zt, out) in ((0.15, 1.2, 2.62, 0.74), (3.5, 1.72, 2.92, 0.62)):
        d = Vector((math.cos(az), math.sin(az), 0.0))
        z_elbow = min(z0 + 0.75, zt - 0.42)
        path = [d * 0.0 + Vector((0, 0, z0)), d * 0.3 + Vector((0, 0, z0 + 0.05)), d * (out - 0.18) + Vector((0, 0, z0 + 0.16)),
                d * (out - 0.04) + Vector((0, 0, z0 + 0.42)), d * out + Vector((0, 0, z_elbow)),
                d * out + Vector((0, 0, zt - 0.3)), d * out + Vector((0, 0, zt - 0.1)), d * out + Vector((0, 0, zt))]
        ra = [0.15, 0.165, 0.17, 0.17, 0.17, 0.165, 0.145, 0.085]
        tube(pb, path, ra, 'NK_Cactus', sides=12, tip=0.02, rfn=lambda i, j, a: 1.0 if j % 2 == 0 else 0.84,
             vfn=cactus_v(R))
    return pb


def cactus_b():
    pb = PB('Cactus_B', 127)
    R = pb.R
    cols = [(0.0, 0.0, 2.85, 0.17), (0.6, 0.22, 2.3, 0.15), (2.0, 0.2, 1.85, 0.14), (3.5, 0.21, 2.6, 0.155),
            (5.0, 0.2, 1.55, 0.135)]
    tops = []
    for k, (az, off, h, r) in enumerate(cols):
        d = Vector((math.cos(az), math.sin(az), 0.0))
        o = d * off
        lean = d * (0.05 + 0.25 * off)
        path = [o * 0.3 + Vector((0, 0, -0.25)), o * 0.6 + Vector((0, 0, 0.12)), o + lean * 0.6 + Vector((0, 0, 0.5)),
                o + lean + Vector((0, 0, 1.0)), o + lean * 1.15 + Vector((0, 0, h - 0.5)),
                o + lean * 1.2 + Vector((0, 0, h - 0.14)), o + lean * 1.2 + Vector((0, 0, h))]
        rad = [r * 1.1, r * 1.05, r, r, r * 0.98, r * 0.82, r * 0.42]
        tube(pb, path, rad, 'NK_Cactus', sides=10, tip=0.02, rfn=lambda i, j, a: 1.0 if j % 2 == 0 else 0.82,
             vfn=cactus_v(R), phase=k * 0.4)
        tops.append(path[-1])
    for k in (0, 3):
        blob(pb, tops[k] + Vector((0.0, 0.0, 0.03)), (0.07, 0.07, 0.05), 'NK_Flower', sub=0, amp=0.1, squash=0.0,
             fcol=lambda c, n: srgb2lin((236, 96, 140)))
    return pb


# ------------------------------------------------------------------------------------------------------ rocks
def rock_fcol(R, lichen=True):
    """Per-facet tint: driven by the face normal so coplanar fracture faces share one tone (no triangle speckle),
    gentle large-scale variation, darker undersides, lichen-tinted up-facing facets."""
    off = rv(R)

    def f(c, n):
        v = noise.noise(Vector(n) * 2.7 + off)
        k = (0.86 + 0.14 * v) * (0.72 + 0.28 * max(0.0, n.z) + 0.12 * min(0.0, n.z))
        k *= 0.95 + 0.05 * noise.noise(Vector(c) * 1.3 + off)
        lich = lichen and n.z > 0.6 and noise.noise(Vector(c) * 0.9 + off * 0.5) > -0.15
        return mul((0.92, 0.97, 0.84) if lich else (1.0, 1.0, 1.0), k)
    return f


def rock_single(name, seed, size, cuts, amp, sink=0.15, el_range=(-0.35, 1.2), cut_range=(0.62, 0.86)):
    pb = PB(name, seed)
    R = pb.R
    bottom = -0.55
    c = (0.0, 0.0, -sink - bottom * size[2])
    rock_mass(pb, c, size, 'NK_Rock', cuts=cuts, amp=amp, fcol=rock_fcol(R), bottom=bottom, el_range=el_range,
              cut_range=cut_range)
    return pb


def rock_a():
    return rock_single('Rock_A', 131, (0.8, 0.68, 0.9), 7, 0.16, sink=0.12)


def rock_b():
    return rock_single('Rock_B', 137, (1.0, 0.78, 0.66), 7, 0.12, sink=0.1, el_range=(-0.2, 0.9))


def rock_c():
    return rock_single('Rock_C', 139, (0.85, 0.72, 1.62), 8, 0.1, sink=0.18, cut_range=(0.55, 0.8))


def rock_large():
    pb = PB('Rock_Large', 149)
    R = pb.R
    bottom = -0.55
    sink = 0.35
    masses = [((0.0, 0.0), (3.3, 2.8, 4.6), 8), ((2.2, 0.9), (2.3, 2.0, 3.0), 7), ((-2.3, -0.6), (2.0, 1.9, 2.6), 7),
              ((0.9, -1.5), (1.4, 1.3, 5.4), 8), ((-1.0, 1.7), (1.7, 1.4, 2.0), 6)]
    for (x, y), s, cuts in masses:
        c = (x, y, -sink - bottom * s[2])
        rock_mass(pb, c, s, 'NK_Rock', cuts=cuts, amp=0.1, fcol=rock_fcol(R), bottom=bottom, cut_range=(0.6, 0.84))
    return pb


def rock_red():
    pb = PB('Rock_Red', 157)
    R = pb.R
    m = 18
    sx, sy = 1.65, 1.25
    off = rv(R)
    base = []
    for k in range(m):
        a = 2 * PI * k / m
        c, sn = math.cos(a), math.sin(a)
        rr = 1.0 / ((abs(c) ** 3.0 + abs(sn) ** 3.0) ** (1.0 / 3.0))  # blocky superellipse footprint
        rr *= 1.0 + 0.2 * noise.noise(Vector((c * 1.3, sn * 1.3, 0.3)) + off)
        base.append((c * rr, sn * rr))
    zb = [0.0, 0.34, 0.86, 1.3, 1.62, 2.34, 2.56, 3.12, 3.46]
    sc = [1.08, 0.97, 1.0, 0.9, 0.93, 0.8, 0.84, 0.68]
    bmats = ['NK_Sandstone_3', 'NK_Sandstone_1', 'NK_Sandstone_2', 'NK_Sandstone_4', 'NK_Sandstone_1',
             'NK_Sandstone_3', 'NK_Sandstone_2', 'NK_Sandstone_1']
    lean = (0.1, -0.05)
    dip = (0.045, 0.02)
    jit = [R.uniform(-0.03, 0.03) for _ in range(m * len(zb))]

    def ring(z, s_, bi, zi, erode):
        out = []
        for k in range(m):
            bx, by = base[k]
            e = (1.0 + erode * noise.noise(Vector((bx * 2.4, by * 2.4, bi * 1.9)) + off)
                 + 0.5 * erode * noise.noise(Vector((bx * 5.0, by * 5.0, bi * 3.1)) + off))
            x = bx * s_ * e * sx + lean[0] * max(z, 0.0)
            y = by * s_ * e * sy + lean[1] * max(z, 0.0)
            if z > -0.1:
                zz = z + x * dip[0] + y * dip[1] + (jit[zi * m + k] if 0 < zi < len(zb) - 1 else 0.0)
            else:
                zz = z
            out.append(Vector((x, y, zz)))
        return out
    rings = [ring(-0.25, sc[0] * 1.03, 0, 0, 0.06)]
    for b in range(len(sc)):
        rings.append(ring(zb[b], sc[b], b, b, 0.12))
        rings.append(ring(zb[b + 1], sc[b] * 0.955, b, b + 1, 0.12))
    # one material per loft segment: skirt, then per band its side and the ledge above it
    mats = [bmats[0]]
    for b in range(len(sc)):
        mats.append(bmats[b])
        if b + 1 < len(sc):
            mats.append(bmats[b] if sc[b + 1] < sc[b] else bmats[b + 1])
    zt = zb[-1]
    ctr = Vector((lean[0] * zt, lean[1] * zt, 0.0))
    top_in = [p.lerp(Vector((ctr.x, ctr.y, p.z)), 0.5) + Vector((0, 0, R.uniform(0.02, 0.12))) for p in rings[-1]]
    rings.append(top_in)
    mats.append(bmats[-1])
    top_c = Vector((ctr.x + 0.2, ctr.y - 0.1, zt + 0.16))
    # fracture planes: flat banded cliff faces on some sides, one bevelled top corner
    allp = [q for rg in rings for q in rg]
    a0 = R.uniform(0, 2 * PI)
    cuts = []
    for k in range(4):
        nrm = dir_from(a0 + k * PI / 2 + R.uniform(-0.45, 0.45), 0.0)
        cuts.append((nrm, max(q.dot(nrm) for q in allp) * R.uniform(0.72, 0.86)))
    nrm = dir_from(a0 + R.uniform(0.5, 1.2), math.radians(40))
    cuts.append((nrm, max(q.dot(nrm) for q in allp) - 0.75))

    def cut(q):
        q = q.copy()
        for nrm, d in cuts:
            k = q.dot(nrm)
            if k > d:
                q = q - nrm * (k - d)
        return q
    rings = [[cut(q) for q in rg] for rg in rings]
    top_c = cut(top_c)

    def fc(c, n):
        k = (0.9 + 0.1 * noise.noise(Vector(n) * 2.5 + off)) * (0.8 + 0.2 * max(0.0, n.z) + 0.15 * min(0.0, n.z))
        return (k, k, k)
    loft(pb, rings, mats, top_c, (0.0, 0.0, -0.25), bmats[-1], bmats[0], fcol=fc)
    # ledges flattened onto a fracture plane collapse: weld them and drop the degenerate slivers
    bmesh.ops.remove_doubles(pb.bm, verts=list(pb.bm.verts), dist=0.004)
    bmesh.ops.dissolve_degenerate(pb.bm, dist=0.004, edges=list(pb.bm.edges))
    return pb


# ------------------------------------------------------------------------------------------------------ small plants
def grass_v(base=(0.45, 0.5, 0.4), tipc=(1.0, 1.0, 0.82)):
    return lambda t: (lerp(base[0], tipc[0], t), lerp(base[1], tipc[1], t), lerp(base[2], tipc[2], t))


def grass_tuft():
    pb = PB('Grass_Tuft', 171)
    R = pb.R
    n = 15
    for i in range(n):
        a = 2 * PI * i / n + R.uniform(-0.3, 0.3)
        rb = R.uniform(0.0, 0.07)
        base = Vector((math.cos(a) * rb, math.sin(a) * rb, -0.03))
        blade(pb, base, a + R.uniform(-0.4, 0.4), R.uniform(0.28, 0.47), R.uniform(0.03, 0.045), R.uniform(0.1, 0.42),
              R.uniform(0.25, 0.75), 3, 'NK_Grass', grass_v(), side_twist=R.uniform(-0.5, 0.5))
    return pb


def flowers_tuft():
    pb = PB('Flowers_Tuft', 173)
    R = pb.R
    for i in range(12):
        a = 2 * PI * i / 12 + R.uniform(-0.3, 0.3)
        rb = R.uniform(0.0, 0.08)
        blade(pb, Vector((math.cos(a) * rb, math.sin(a) * rb, -0.03)), a + R.uniform(-0.4, 0.4),
              R.uniform(0.2, 0.36), R.uniform(0.03, 0.042), R.uniform(0.15, 0.5), R.uniform(0.3, 0.8), 2, 'NK_Grass',
              grass_v(), side_twist=R.uniform(-0.5, 0.5))
    pal = [srgb2lin(c) for c in ((246, 206, 46), (246, 244, 236), (168, 104, 214), (238, 120, 156), (246, 206, 46))]
    for k in range(5):
        a = 2 * PI * k / 5 + R.uniform(-0.25, 0.25)
        rb = R.uniform(0.03, 0.09)
        h = R.uniform(0.34, 0.48)
        base = Vector((math.cos(a) * rb, math.sin(a) * rb, -0.03))
        lean = R.uniform(0.05, 0.22)
        dirh = Vector((math.cos(a), math.sin(a), 0.0))
        top = base + dirh * (h * math.sin(lean)) + Z * (h * math.cos(lean))
        side = Vector((-math.sin(a), math.cos(a), 0.0))
        pb.add([base - side * 0.008, base + side * 0.008, top], [(0, 1, 2)], 'NK_Grass', smooth=True,
               vcols=[(0.45, 0.5, 0.4), (0.45, 0.5, 0.4), (0.85, 0.9, 0.7)])
        rh = R.uniform(0.035, 0.05)
        ph = R.uniform(0, 2 * PI)
        vs = [top + Vector((0, 0, -0.012))] + [top + Vector((math.cos(ph + 2 * PI * j / 5) * rh,
                                                             math.sin(ph + 2 * PI * j / 5) * rh, 0.01))
                                               for j in range(5)]
        col = pal[k]
        pb.add(vs, [(0, 1 + j, 1 + (j + 1) % 5) for j in range(5)], 'NK_Flower', smooth=False,
               vcols=[mul(col, 0.8)] + [col] * 5)
    return pb


def reeds():
    pb = PB('Reeds', 177)
    R = pb.R
    for i in range(14):
        a = 2 * PI * i / 14 + R.uniform(-0.3, 0.3)
        rb = R.uniform(0.0, 0.16)
        blade(pb, Vector((math.cos(a) * rb, math.sin(a) * rb, -0.04)), a + R.uniform(-0.3, 0.3),
              R.uniform(1.05, 1.7), R.uniform(0.035, 0.05), R.uniform(0.04, 0.22), R.uniform(0.15, 0.6), 3, 'NK_Reed',
              grass_v((0.5, 0.52, 0.42), (1.0, 0.98, 0.8)), side_twist=R.uniform(-0.6, 0.6))
    for k in range(4):
        a = 2 * PI * k / 4 + R.uniform(-0.3, 0.3)
        rb = R.uniform(0.02, 0.1)
        h = R.uniform(1.45, 1.78)
        base = Vector((math.cos(a) * rb, math.sin(a) * rb, -0.05))
        lean = Vector((math.cos(a), math.sin(a), 0.0)) * R.uniform(0.04, 0.12)
        top = base + lean + Vector((0, 0, h))
        tube(pb, [base, base.lerp(top, 0.5) + lean * 0.2, top], [0.009, 0.008, 0.007], 'NK_Reed', sides=3,
             tip=0.13, vfn=lambda i, j, p: (lerp(0.5, 0.9, p.z / 1.8),) * 3)
        hb = base.lerp(top, (h - 0.34) / h)
        ht = base.lerp(top, (h - 0.06) / h)
        tube(pb, [hb, hb.lerp(ht, 0.5), ht], [0.024, 0.029, 0.026], 'NK_Cattail', sides=6, tip=0.0,
             vfn=lambda i, j, p: (R.uniform(0.8, 1.0),) * 3)
    return pb


def hay_bale():
    pb = PB('Hay_Bale', 181)
    R = pb.R
    zc = 0.72
    off = rv(R)
    xs = [-0.625, -0.622, -0.616, -0.6, -0.57, -0.45, -0.3, -0.15, 0.0, 0.15, 0.3, 0.45, 0.57, 0.6, 0.616, 0.622, 0.625]
    rs = [0.18, 0.36, 0.54, 0.665, 0.735, 0.752, 0.76, 0.765, 0.767, 0.765, 0.76, 0.752, 0.735, 0.665, 0.54, 0.36, 0.18]
    n_end = 3  # rings 0..2 and 14..16 lie on the flat ends (concentric rolled layers)

    def hay_v(i, j, p):
        if j < 0:
            return (0.72, 0.68, 0.58)
        if i < n_end or i > len(xs) - 1 - n_end:
            k = (0.98 if i % 2 == 0 else 0.8) * R.uniform(0.92, 1.0)
            return (k, k * 0.97, k * 0.86)
        a = 2 * PI * j / 20
        st = noise.noise(Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, p.x * 1.5)) + off)
        k = (0.86 + 0.14 * st) * (0.88 + 0.12 * min(1.0, p.z / 1.4)) * R.uniform(0.92, 1.0)
        return (k, k * 0.97, k * 0.88)
    tube(pb, [(x, 0.0, zc) for x in xs], rs, 'NK_Hay', sides=20, smooth=False,
         rfn=lambda i, j, a: 1.0 + (0.018 * noise.noise(Vector((math.cos(a) * 4, math.sin(a) * 4, i * 0.7)) + off)
                                    if n_end <= i <= len(xs) - 1 - n_end else 0.0),
         vfn=hay_v, post=lambda v: Vector((v.x, v.y, max(v.z, 0.0))))
    return pb


def log_pile():
    pb = PB('Log_Pile', 191)
    R = pb.R
    rows = [(-0.48, 4), (-0.32, 3), (-0.16, 2), (0.0, 1)]
    placed = []
    for y0, cnt in rows:
        for k in range(cnt):
            r = R.uniform(0.145, 0.17)
            y = y0 + k * 0.32 + R.uniform(-0.01, 0.01)
            # rest on the ground or on the logs below (octagon flats + slight bite: 0.92 of the radius sum)
            z = r * 0.95
            for (y2, z2, r2) in placed:
                dmax = (r + r2) * 0.92
                if abs(y - y2) < dmax:
                    z = max(z, z2 + math.sqrt(dmax * dmax - (y - y2) ** 2))
            placed.append((y, z, r))
            L = R.uniform(1.92, 2.04)
            x0 = R.uniform(-0.05, 0.05)
            xs = [x0 - L / 2 - 0.012, x0 - L / 2, x0 + L / 2, x0 + L / 2 + 0.012]
            rr = [r * 0.8, r, r * R.uniform(0.95, 1.02), r * 0.8]

            def lv(i, j, p, xs=xs):
                if j < 0:
                    return (1.0, 0.97, 0.92)
                if i in (0, 3):
                    return (0.82, 0.78, 0.72)
                k = R.uniform(0.75, 1.0)
                return (k, k, k)
            tube(pb, [(x, y, z) for x in xs], rr, 'NK_Log_Bark', sides=8, phase=R.uniform(0, PI),
                 side_mat=lambda i, j: 'NK_Log_End' if i in (0, 2) else 'NK_Log_Bark', cap_mat='NK_Log_End',
                 vfn=lv, rfn=lumpy(R, 0.04, 0.04, 0))
    for x in (-0.62, 0.62):
        for y in (-0.685, 0.685):
            tube(pb, [(x, y, -0.3), (x + R.uniform(-0.02, 0.02), y + (0.02 if y > 0 else -0.02), 1.0)], [0.045, 0.04],
                 'NK_Log_Bark', sides=6, vfn=lambda i, j, p: (R.uniform(0.7, 0.9),) * 3)
    return pb


BUILDERS = {
    'Tree_Oak_A': tree_oak_a, 'Tree_Oak_B': tree_oak_b, 'Tree_Pine_A': tree_pine_a, 'Tree_Pine_B': tree_pine_b,
    'Tree_Poplar': tree_poplar, 'Tree_Birch': tree_birch, 'Tree_Palm': tree_palm, 'Tree_Olive': tree_olive,
    'Tree_Dead': tree_dead, 'Bush_A': bush_a, 'Bush_B': bush_b, 'Bush_Desert': bush_desert, 'Cactus_A': cactus_a,
    'Cactus_B': cactus_b, 'Rock_A': rock_a, 'Rock_B': rock_b, 'Rock_C': rock_c, 'Rock_Large': rock_large,
    'Rock_Red': rock_red, 'Grass_Tuft': grass_tuft, 'Flowers_Tuft': flowers_tuft, 'Reeds': reeds,
    'Hay_Bale': hay_bale, 'Log_Pile': log_pile,
}


# ------------------------------------------------------------------------------------------------------ scene objects
def ensure_child(name, parent):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    if col.name not in [c.name for c in parent.children]:
        parent.children.link(col)
    return col


def kit_collection():
    root = bpy.data.collections.get('SUNWARD_GODOT')
    if root is None:
        raise RuntimeError('SUNWARD_GODOT collection missing (run tools/blender/setup_scene.py)')
    nature = ensure_child('Nature', root)
    return ensure_child('NatureKit', nature)


def remove_object(ob):
    me = ob.data if ob.type == 'MESH' else None
    bpy.data.objects.remove(ob, do_unlink=True)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)


def finish(pb, coll):
    old = bpy.data.objects.get(pb.name)
    if old is not None:
        if old.name not in coll.objects and old.users_collection:
            raise RuntimeError('object %s exists outside NatureKit: %s' % (pb.name, [c.name for c in old.users_collection]))
        remove_object(old)
    oldme = bpy.data.meshes.get(pb.name)
    if oldme is not None and oldme.users == 0:
        bpy.data.meshes.remove(oldme)
    bm = pb.bm
    uv = bm.loops.layers.uv.new('UVMap')
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            co = lp.vert.co
            if ax == 0:
                lp[uv].uv = (co.y * 0.5, co.z * 0.5)
            elif ax == 1:
                lp[uv].uv = (co.x * 0.5, co.z * 0.5)
            else:
                lp[uv].uv = (co.x * 0.5, co.y * 0.5)
    me = bpy.data.meshes.new(pb.name)
    bm.to_mesh(me)
    bm.free()
    for m in pb.mats:
        me.materials.append(make_mat(m))
    ca = me.color_attributes.get('Col')
    try:
        me.color_attributes.active_color = ca
    except Exception:
        pass
    try:
        me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
    except Exception:
        pass
    me.update()
    ob = bpy.data.objects.new(pb.name, me)
    coll.objects.link(ob)
    if ob.name != pb.name or me.name != pb.name:
        raise RuntimeError('name clash: %s / %s' % (ob.name, me.name))
    x, y = LAYOUT[pb.name]
    ob.location = (x, y, 0.0)
    return ob


def build(only=None):
    coll = kit_collection()
    out = []
    for name in NAMES:
        if only and name not in only:
            continue
        pb = BUILDERS[name]()
        out.append(finish(pb, coll).name)
    return out


# ------------------------------------------------------------------------------------------------------ QA
def _islands(bm):
    seen = set()
    comps = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        comps.append(comp)
    return comps


def _inside(bvh, p):
    d = Vector((0.2113, 0.3361, 0.9178)).normalized()
    o = p.copy()
    n = 0
    for _ in range(64):
        hit, nrm, idx, dist = bvh.ray_cast(o, d)
        if hit is None:
            break
        n += 1
        o = hit + d * 1e-4
    return n % 2 == 1


def analyze(ob, tol=0.03):
    me = ob.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    comps = _islands(bm)
    info = []
    for comp in comps:
        vset = {}
        for f in comp:
            for v in f.verts:
                if v.index not in vset:
                    vset[v.index] = len(vset)
        vco = [None] * len(vset)
        for vi, k in vset.items():
            vco[k] = bm.verts[vi].co.copy()
        polys = [[vset[v.index] for v in f.verts] for f in comp]
        fs = set(f.index for f in comp)
        closed = all(len([g for g in e.link_faces if g.index in fs]) == 2 for f in comp for e in f.edges)
        vol = 0.0
        for f in comp:
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
        mn = Vector((min(p.x for p in vco), min(p.y for p in vco), min(p.z for p in vco)))
        mx = Vector((max(p.x for p in vco), max(p.y for p in vco), max(p.z for p in vco)))
        step = max(1, len(vco) // 80)
        info.append(dict(bvh=BVHTree.FromPolygons(vco, polys), pts=vco[::step], closed=closed, vol=vol, mn=mn, mx=mx))
    degen = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    bm.free()
    n = len(info)
    parent = list(range(n + 1))  # n = ground

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        parent[find(a)] = find(b)
    for i, a in enumerate(info):
        if a['mn'].z <= 0.02:
            union(i, n)
    for i in range(n):
        A = info[i]
        for j in range(i + 1, n):
            B = info[j]
            if find(i) == find(j):
                continue
            if any(A['mn'][k] - tol > B['mx'][k] or B['mn'][k] - tol > A['mx'][k] for k in range(3)):
                continue
            hit = False
            for p in A['pts']:
                r = B['bvh'].find_nearest(p)
                if r[0] is not None and r[3] <= tol:
                    hit = True
                    break
            if not hit and B['closed']:
                hit = any(_inside(B['bvh'], p) for p in A['pts'][:40])
            if not hit and A['closed']:
                hit = any(_inside(A['bvh'], p) for p in B['pts'][:40])
            if hit:
                union(i, j)
    floating = [i for i in range(n) if find(i) != find(n)]
    vs = [v.co for v in me.vertices]
    mn = Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs)))
    mx = Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs)))
    budget = next(v for k, v in BUDGET.items() if ob.name.startswith(k))
    return dict(name=ob.name, height=round(mx.z, 2), below=round(mn.z, 2), size_x=round(mx.x - mn.x, 2),
                size_y=round(mx.y - mn.y, 2), tris=tris, budget=budget, ok_budget=tris <= budget,
                mats=[m.name for m in me.materials], islands=n, open_islands=sum(1 for a in info if not a['closed']),
                inverted=sum(1 for a in info if a['closed'] and a['vol'] < 0), floating=len(floating),
                floating_at=[tuple(round(c, 2) for c in (info[i]['mn'] + info[i]['mx']) / 2) for i in floating[:5]],
                degenerate=degen, uv=len(me.uv_layers), col=[a.name for a in me.color_attributes],
                loc=tuple(round(c, 2) for c in ob.location), center_xy=(round((mn.x + mx.x) / 2, 2), round((mn.y + mx.y) / 2, 2)))


def report(only=None):
    out = []
    for name in NAMES:
        if only and name not in only:
            continue
        ob = bpy.data.objects.get(name)
        if ob is None:
            out.append(dict(name=name, missing=True))
            continue
        out.append(analyze(ob))
    return out


# ------------------------------------------------------------------------------------------------------ scale refs
REF_COLL = '_QA_NatureRef'


def ref_on(only=None):
    col = bpy.data.collections.get(REF_COLL) or bpy.data.collections.new(REF_COLL)
    if col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    mat = bpy.data.materials.get('QA_RefMat') or bpy.data.materials.new('QA_RefMat')
    mat.diffuse_color = (0.9, 0.15, 0.1, 1.0)
    made = []
    for name in NAMES:
        if only and name not in only:
            continue
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        xs = [v.co.x for v in ob.data.vertices]
        rname = 'QA_Ref1p8_' + name
        old = bpy.data.objects.get(rname)
        if old is not None:
            remove_object(old)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.22, radius2=0.18, depth=1.8,
                              matrix=Matrix.Translation((0, 0, 0.9)))
        me = bpy.data.meshes.new(rname)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        r = bpy.data.objects.new(rname, me)
        r.location = ob.location + Vector((max(xs) + 0.5, 0.0, 0.0))
        col.objects.link(r)
        made.append(rname)
    return made


def ref_off():
    col = bpy.data.collections.get(REF_COLL)
    n = 0
    if col is not None:
        for ob in list(col.objects):
            remove_object(ob)
            n += 1
        bpy.data.collections.remove(col)
    m = bpy.data.materials.get('QA_RefMat')
    if m is not None and m.users == 0:
        bpy.data.materials.remove(m)
    return n


def solo(only):
    """Viewport-hide every other kit prop / scale ref so look() sees only the targets (undo with unsolo)."""
    keep = set(only or [])
    keep |= {'QA_Ref1p8_' + n for n in keep}
    hidden = []
    for ob in list(kit_collection().objects) + list(getattr(bpy.data.collections.get(REF_COLL), 'objects', [])):
        h = ob.name not in keep
        ob.hide_set(h)
        if h:
            hidden.append(ob.name)
    return len(hidden)


def unsolo():
    n = 0
    for ob in list(kit_collection().objects) + list(getattr(bpy.data.collections.get(REF_COLL), 'objects', [])):
        if ob.hide_get():
            ob.hide_set(False)
            n += 1
    return n


# ------------------------------------------------------------------------------------------------------ contact sheet
SHEET_ORDER = ['Tree_Oak_A', 'Tree_Oak_B', 'Tree_Pine_A', 'Tree_Pine_B', 'Tree_Poplar', 'Tree_Birch',
               'Tree_Palm', 'Tree_Olive', 'Tree_Dead', 'Cactus_A', 'Cactus_B', 'Bush_A',
               'Bush_B', 'Bush_Desert', 'Rock_A', 'Rock_B', 'Rock_C', 'Rock_Large',
               'Rock_Red', 'Grass_Tuft', 'Flowers_Tuft', 'Reeds', 'Hay_Bale', 'Log_Pile']


def _qa_collection():
    col = bpy.data.collections.get('_QA')
    if col is None:
        col = bpy.data.collections.new('_QA')
        bpy.context.scene.collection.children.link(col)
        col.hide_viewport = True
    elif col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    return col


def contact_sheet(tile=400, gap=4, cols=6, names=None):
    import numpy as np
    names = names or SHEET_ORDER
    sc = bpy.context.scene
    r = sc.render
    vs = sc.view_settings
    ee = sc.eevee
    qa = _qa_collection()
    lc = bpy.context.view_layer.layer_collection.children.get('_QA')
    kit = [bpy.data.objects[n] for n in NAMES if bpy.data.objects.get(n)]
    stamp_props = [p.identifier for p in r.bl_rna.properties if p.identifier.startswith('use_stamp')]
    saved = dict(engine=r.engine, rx=r.resolution_x, ry=r.resolution_y, pct=r.resolution_percentage, fp=r.filepath,
                 fmt=r.image_settings.file_format, cam=sc.camera, world=sc.world, transparent=r.film_transparent,
                 vt=vs.view_transform, look=vs.look, exposure=vs.exposure, gamma=vs.gamma,
                 qa_hv=qa.hide_viewport, qa_hr=qa.hide_render, lc_hv=lc.hide_viewport if lc else None,
                 stamps={p: getattr(r, p) for p in stamp_props}, note=r.stamp_note_text, fsize=r.stamp_font_size,
                 sfg=tuple(r.stamp_foreground), sbg=tuple(r.stamp_background),
                 samples=getattr(ee, 'taa_render_samples', None), hr={o.name: o.hide_render for o in kit})
    hidden_qa = {}
    for o in qa.objects:
        hidden_qa[o.name] = o.hide_render
        o.hide_render = True
    made = []
    os.makedirs(TILE_DIR, exist_ok=True)
    tiles = []
    stats = {d['name']: d for d in report()}
    try:
        qa.hide_viewport = False
        qa.hide_render = False
        if lc is not None:
            lc.hide_viewport = False
        world = bpy.data.worlds.new('QA_NatureWorld')
        try:
            world.use_nodes = True
        except Exception:
            pass
        bg = next((nd for nd in world.node_tree.nodes if nd.type == 'BACKGROUND'), None)
        if bg is not None:
            bg.inputs[0].default_value = (0.5, 0.62, 0.8, 1.0)
            bg.inputs[1].default_value = 0.85
        gm = bpy.data.meshes.new('QA_NatureGround')
        gbm = bmesh.new()
        bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=250.0)
        gbm.to_mesh(gm)
        gbm.free()
        gmat = bpy.data.materials.new('QA_NatureGroundMat')
        gmat.diffuse_color = (0.25, 0.25, 0.22, 1.0)
        try:
            gmat.use_nodes = True
            b = next(nd for nd in gmat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
            _sock(b, 'Base Color').default_value = (0.2, 0.2, 0.17, 1.0)
            _sock(b, 'Roughness').default_value = 0.95
        except Exception:
            pass
        gm.materials.append(gmat)
        ground = bpy.data.objects.new('QA_NatureGround', gm)
        ground.location = (130.0, -130.0, -0.002)
        qa.objects.link(ground)
        made.append(ground)
        cam = bpy.data.objects.new('QA_NatureCam', bpy.data.cameras.new('QA_NatureCam'))
        cam.data.lens = 50.0
        cam.data.clip_end = 1000.0
        qa.objects.link(cam)
        made.append(cam)
        sun = bpy.data.objects.new('QA_NatureSun', bpy.data.lights.new('QA_NatureSun', 'SUN'))
        sun.data.energy = 4.0
        try:
            sun.data.angle = math.radians(3.0)
        except Exception:
            pass
        L = Vector((-0.35, 0.75, 0.62)).normalized()
        sun.rotation_euler = L.to_track_quat('Z', 'Y').to_euler()
        qa.objects.link(sun)
        made.append(sun)
        refmat = bpy.data.materials.new('QA_NatureRefMat')
        refmat.diffuse_color = (0.75, 0.2, 0.15, 1.0)
        try:
            refmat.use_nodes = True
            b = next(nd for nd in refmat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
            _sock(b, 'Base Color').default_value = (0.6, 0.12, 0.08, 1.0)
        except Exception:
            pass
        r.engine = 'BLENDER_EEVEE'
        r.resolution_x = r.resolution_y = tile
        r.resolution_percentage = 100
        r.image_settings.file_format = 'PNG'
        r.film_transparent = False
        vs.view_transform = 'Standard'
        vs.look = 'None'
        vs.exposure = 0.0
        vs.gamma = 1.0
        if saved['samples'] is not None:
            ee.taa_render_samples = 32
        for p in stamp_props:
            setattr(r, p, False)
        r.use_stamp = True
        r.use_stamp_note = True
        r.stamp_font_size = 15
        r.stamp_foreground = (1.0, 1.0, 1.0, 1.0)
        r.stamp_background = (0.0, 0.0, 0.0, 0.55)
        sc.camera = cam
        sc.world = world
        fov = 2 * math.atan(18.0 / 50.0)
        # review fix (same as buildings_kit.py): throwaway warm-up render of the whole kit so the first tile cannot
        # come out without its prop while EEVEE / the depsgraph is not ready yet
        for o in kit:
            o.hide_render = False
        allw = [o.matrix_world @ Vector(cb) for o in kit for cb in o.bound_box]
        kc = sum(allw, Vector()) / len(allw)
        cam.location = kc + Vector((0.5, 0.82, 0.32)).normalized() * 150.0
        cam.rotation_euler = (kc - cam.location).to_track_quat('-Z', 'Y').to_euler()
        r.stamp_note_text = 'warm-up'
        r.filepath = os.path.join(TILE_DIR, '_warmup.png')
        bpy.ops.render.render(write_still=False)
        for name in names:
            ob = bpy.data.objects.get(name)
            if ob is None:
                continue
            for o in kit:
                o.hide_render = (o is not ob)
            M = ob.matrix_world
            ws = [M @ v.co for v in ob.data.vertices]
            mn = Vector((min(p.x for p in ws), min(p.y for p in ws), max(0.0, min(p.z for p in ws))))
            mx = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
            ref = None
            if mx.z - mn.z > 0.9:
                rbm = bmesh.new()
                bmesh.ops.create_cone(rbm, cap_ends=True, segments=10, radius1=0.2, radius2=0.16, depth=1.8,
                                      matrix=Matrix.Translation((0, 0, 0.9)))
                rme = bpy.data.meshes.new('QA_NatureRef')
                rbm.to_mesh(rme)
                rbm.free()
                rme.materials.append(refmat)
                ref = bpy.data.objects.new('QA_NatureRef', rme)
                ref.location = (mx.x + 0.45, (mn.y + mx.y) / 2 + 0.3, 0.0)
                qa.objects.link(ref)
                mx.x += 0.7
                mx.z = max(mx.z, 1.8)
            c = (mn + mx) / 2
            rad = (mx - mn).length / 2
            view = Vector((0.5, 0.82, 0.32)).normalized()
            dist = rad / math.sin(fov / 2) * 0.92
            cam.location = c + view * dist
            cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
            cam.data.clip_start = max(0.01, dist * 0.02)
            st = stats.get(name, {})
            r.stamp_note_text = '%s   h %.2f m   %d tris' % (name, st.get('height', mx.z), st.get('tris', 0))
            png = os.path.join(TILE_DIR, name + '.png')
            r.filepath = png
            bpy.ops.render.render(write_still=True)
            tiles.append((name, png))
            if ref is not None:
                remove_object(ref)
        rows = (len(tiles) + cols - 1) // cols
        W = cols * tile + (cols + 1) * gap
        H = rows * tile + (rows + 1) * gap
        sheet = np.full((H, W, 4), 0.12, dtype=np.float32)
        sheet[:, :, 3] = 1.0
        for k, (name, png) in enumerate(tiles):
            img = bpy.data.images.load(png, check_existing=False)
            px = np.empty(tile * tile * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            px = px.reshape((tile, tile, 4))
            row, colk = divmod(k, cols)
            y0 = H - gap - (row + 1) * tile - row * gap
            x0 = gap + colk * (tile + gap)
            sheet[y0:y0 + tile, x0:x0 + tile, :] = px
            bpy.data.images.remove(img)
        out = bpy.data.images.new('QA_NatureSheet', W, H, alpha=False)
        out.pixels.foreach_set(sheet.ravel())
        os.makedirs(os.path.dirname(SHEET_PATH), exist_ok=True)
        out.filepath_raw = SHEET_PATH
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)
    finally:
        r.engine = saved['engine']
        r.resolution_x, r.resolution_y = saved['rx'], saved['ry']
        r.resolution_percentage = saved['pct']
        r.filepath = saved['fp']
        r.image_settings.file_format = saved['fmt']
        r.film_transparent = saved['transparent']
        vs.view_transform = saved['vt']
        vs.look = saved['look']
        vs.exposure = saved['exposure']
        vs.gamma = saved['gamma']
        for p, v in saved['stamps'].items():
            try:
                setattr(r, p, v)
            except Exception:
                pass
        r.stamp_note_text = saved['note']
        r.stamp_font_size = saved['fsize']
        r.stamp_foreground = saved['sfg']
        r.stamp_background = saved['sbg']
        if saved['samples'] is not None:
            ee.taa_render_samples = saved['samples']
        sc.camera = saved['cam']
        sc.world = saved['world']
        for o in kit:
            o.hide_render = saved['hr'][o.name]
        for o in made:
            try:
                remove_object(o) if o.type == 'MESH' else _remove_any(o)
            except ReferenceError:
                pass
        for nm in ('QA_NatureRef',):
            o = bpy.data.objects.get(nm)
            if o is not None:
                remove_object(o)
        for nm, hr in hidden_qa.items():
            if bpy.data.objects.get(nm):
                bpy.data.objects[nm].hide_render = hr
        qa.hide_viewport = saved['qa_hv']
        qa.hide_render = saved['qa_hr']
        if lc is not None:
            lc.hide_viewport = saved['lc_hv']
        for coll, nm in ((bpy.data.worlds, 'QA_NatureWorld'), (bpy.data.materials, 'QA_NatureGroundMat'),
                         (bpy.data.materials, 'QA_NatureRefMat'), (bpy.data.cameras, 'QA_NatureCam'),
                         (bpy.data.lights, 'QA_NatureSun')):
            d = coll.get(nm)
            if d is not None and d.users == 0:
                coll.remove(d)
    return SHEET_PATH, [t[0] for t in tiles]


def _remove_any(o):
    data = o.data
    bpy.data.objects.remove(o, do_unlink=True)
    if data is not None and data.users == 0:
        if isinstance(data, bpy.types.Camera):
            bpy.data.cameras.remove(data)
        elif isinstance(data, bpy.types.Light):
            bpy.data.lights.remove(data)


# ------------------------------------------------------------------------------------------------------ export
def export():
    obs = [bpy.data.objects[n] for n in NAMES]
    for ob in obs:
        if ob.parent is not None or ob.rotation_euler[:] != (0.0, 0.0, 0.0) or tuple(ob.scale) != (1.0, 1.0, 1.0):
            raise RuntimeError('%s must be unparented with identity rotation/scale' % ob.name)
    names = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kw = dict(filepath=GLB_PATH, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_materials='EXPORT', export_texcoords=True, export_normals=True, export_tangents=False,
              export_vertex_color='ACTIVE', export_all_vertex_colors=False,
              export_active_vertex_color_when_no_material=True, export_cameras=False, export_lights=False,
              export_animations=False, export_draco_mesh_compression_enable=False, export_extras=False,
              export_morph=False, export_skins=False, export_image_format='AUTO')
    dropped = [k for k in kw if k not in names and k != 'filepath']
    kw = {k: v for k, v in kw.items() if k in names or k == 'filepath'}
    saved_loc = {ob.name: ob.location.copy() for ob in obs}
    sel = [o for o in bpy.context.view_layer.objects if o.select_get()]
    active = bpy.context.view_layer.objects.active
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    try:
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for ob in obs:
            ob.location = (0.0, 0.0, 0.0)
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.context.view_layer.update()
        res = bpy.ops.export_scene.gltf(**kw)
    finally:
        for ob in obs:
            ob.location = saved_loc[ob.name]
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for o in sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        bpy.context.view_layer.objects.active = active
        bpy.context.view_layer.update()
    return res, dropped, verify_glb(GLB_PATH)


def verify_glb(path):
    with open(path, 'rb') as fh:
        raw = fh.read()
    magic, version, length = struct.unpack_from('<4sII', raw, 0)
    clen, ctype = struct.unpack_from('<I4s', raw, 12)
    js = json.loads(raw[20:20 + clen].decode('utf-8'))
    nodes = js.get('nodes', [])
    scene = js['scenes'][js.get('scene', 0)]
    top = [nodes[i] for i in scene['nodes']]
    meshes = js.get('meshes', [])
    acc = js.get('accessors', [])
    mats = js.get('materials', [])
    per = []
    for nd in top:
        m = meshes[nd['mesh']] if 'mesh' in nd else None
        prims = m['primitives'] if m else []
        ymin = min(acc[p['attributes']['POSITION']]['min'][1] for p in prims) if prims else None
        ymax = max(acc[p['attributes']['POSITION']]['max'][1] for p in prims) if prims else None
        tri = sum(acc[p['indices']]['count'] // 3 for p in prims if 'indices' in p)
        per.append(dict(name=nd.get('name'), mesh=m.get('name') if m else None, prims=len(prims),
                        children=len(nd.get('children', [])),
                        transform=[k for k in ('translation', 'rotation', 'scale', 'matrix') if k in nd],
                        y=(round(ymin, 2), round(ymax, 2)) if prims else None, tris=tri,
                        attrs=sorted({a for p in prims for a in p['attributes']})))
    names = [p['name'] for p in per]
    return dict(magic=magic.decode(), version=version, bytes=len(raw), chunk=ctype.decode(), n_top=len(top),
                names_ok=sorted(names) == sorted(NAMES) and len(names) == len(set(names)), missing=[n for n in NAMES if n not in names],
                extra=[n for n in names if n not in NAMES], n_nodes=len(nodes), n_meshes=len(meshes),
                n_materials=len(mats), cameras=len(js.get('cameras', [])), animations=len(js.get('animations', [])),
                lights='KHR_lights_punctual' in js.get('extensionsUsed', []), extensions=js.get('extensionsUsed', []),
                double_sided=sorted(m['name'] for m in mats if m.get('doubleSided')),
                alpha=sorted(m['name'] for m in mats if m.get('alphaMode', 'OPAQUE') != 'OPAQUE'),
                mat_factors={m['name']: [round(c, 3) for c in m.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])[:3]]
                             for m in mats[:6]},
                nodes=per)


def save():
    check_file()
    bpy.ops.wm.save_mainfile()
    return bpy.data.filepath


# ------------------------------------------------------------------------------------------------------ main
if __name__ == '__main__':
    check_file()
    STEP_ = globals().get('STEP', 'build')
    ONLY_ = globals().get('ONLY')
    if STEP_ == 'build':
        print('built', build(ONLY_))
        for d in report(ONLY_):
            print(d)
    elif STEP_ == 'report':
        for d in report(ONLY_):
            print(d)
    elif STEP_ == 'ref_on':
        print('refs', ref_on(ONLY_))
    elif STEP_ == 'ref_off':
        print('refs removed', ref_off())
    elif STEP_ == 'solo':
        print('hidden', solo(ONLY_))
    elif STEP_ == 'unsolo':
        print('unhidden', unsolo())
    elif STEP_ == 'sheet':
        print('sheet', contact_sheet(names=ONLY_))
    elif STEP_ == 'export':
        res, dropped, info = export()
        print('export', res, 'dropped', dropped)
        nodes = info.pop('nodes')
        print(info)
        for nd in nodes:
            print(nd)
    elif STEP_ == 'save':
        print('saved', save())
    elif STEP_ == 'all':
        print('built', build())
        for d in report():
            print(d)
        print('sheet', contact_sheet())
        res, dropped, info = export()
        print('export', res, dropped, {k: v for k, v in info.items() if k != 'nodes'})
        print('saved', save())
