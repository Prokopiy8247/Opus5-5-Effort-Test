"""Sunward Roads - ROADSIDE kit (Blender side, fully procedural bpy/bmesh).

Builds the collection SUNWARD_GODOT/Roadside/RoadsideKit with one joined mesh object per prop (exact names from
docs/SYSTEM_CONTRACTS.md "Props"), origin at the base centre on the ground (Blender Z = 0):

  Sign_SpeedLimit, Sign_Chevron, Sign_Danger_Jump, Sign_Direction, Delineator_Post, GuardRail_Post, Lamp_Street,
  Utility_Pole, Fence_Wood, Wall_Stone, Hedge, Bus_Stop, Bench, Mailbox, Bin, Barrier_Jersey, Cone, Bridge_Pier,
  Tunnel_Portal, Speed_Trap_Camera, Checkpoint_Arch, Festival_Banner, Flag_Pole, Fuel_Pump, Billboard

Axes / placement contract (Blender -> Godot: +Y -> -Z, +Z -> +Y):
  * Fronts face Blender +Y (= Godot -Z, the side that looks at the road when placed with yaw "face").
    Sign faces, the street-lamp arm, camera lens, bus-stop opening, bench seat, billboard panel all point +Y.
  * Linear pieces run along X: Fence_Wood / Wall_Stone / Hedge are 4 m segments centred on the origin
    (x = -2..+2, Hedge overlaps its neighbours by ~0.1 m), Barrier_Jersey is 2 m (x = -1..+1).
  * Roads pass along Y: through the Tunnel_Portal opening (origin = opening centre at road level, wall depth
    y = -0.6..+0.6, front face +Y) and over the Bridge_Pier (hammerhead cap spans X, top of the bearings at
    exactly Z = 10 m, so Godot can scale Y by deck_height / 10).
  * Sign_SpeedLimit: white centre disc r = 0.31 m at Z = 2.10, front face at Y = +0.065 (Label3D goes there).
    Sign_Direction: green field 2.48 x 1.28 m centred at Z = 2.40, front face at Y = +0.085.
    Sign_Chevron: chevrons point to the viewer's right (Blender -X); mirror with scale.x = -1 for left bends.
  * Lamp_Street: luminaire centre at (0, 1.75, 6.2) like scripts/env/lamp_pool.gd (LAMP_HEIGHT 6.2, ARM 1.75),
    emissive lens material "LampLens" on its underside. Billboard: 8 x 4 m panel, material "BillboardPanel",
    UV 0..1 across the visible face (u from the viewer's left), panel bottom at Z = 3.0.
  * Utility_Pole: the line runs along X (cross-arm along Y, perpendicular to the wires).

Style: semi-realistic low poly, plain PBR materials (prefix RK_, plus LampLens / BillboardPanel) whose base colour is
multiplied by the corner colour attribute "Col" (AO / grime / variation, exported as COLOR_0). Posts and walls
continue below Z = 0 so props sit into uneven terrain. In Blender the kit is laid out in a QA grid around
x = +80..+140 m, y = +120..+160 m (far from the player cars at the origin); export moves each prop to the origin.

Run inside Blender through the project MCP client (see tools/blender/props/run.sh):
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__', 'STEP': 'build'})
STEP: build (ONLY=[names] optional) | report | ref_on | ref_off | solo | unsolo | sheet | export | save | all
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
GLB_PATH = os.path.join(PROJECT, 'assets', 'imported', 'props', 'roadside_kit.glb')
SHEET_PATH = os.path.join(PROJECT, 'docs', 'blender_props', 'roadside_kit.png')
TILE_DIR = os.path.join(PROJECT, 'qa_output', 'blender_look', 'roadside_tiles')
KIT = 'RoadsideKit'
PI = math.pi

NAMES = ['Sign_SpeedLimit', 'Sign_Chevron', 'Sign_Danger_Jump', 'Sign_Direction', 'Delineator_Post',
         'GuardRail_Post', 'Lamp_Street', 'Utility_Pole', 'Fence_Wood', 'Wall_Stone', 'Hedge', 'Bus_Stop', 'Bench',
         'Mailbox', 'Bin', 'Barrier_Jersey', 'Cone', 'Bridge_Pier', 'Tunnel_Portal', 'Speed_Trap_Camera',
         'Checkpoint_Arch', 'Festival_Banner', 'Flag_Pole', 'Fuel_Pump', 'Billboard']

# QA grid (Blender world XY of each prop origin), far from the cars at the origin and from the nature kit (y < 0)
LAYOUT = {
    'Sign_SpeedLimit': (80, 120), 'Sign_Chevron': (83, 120), 'Sign_Danger_Jump': (86, 120),
    'Sign_Direction': (90, 120), 'Delineator_Post': (93.5, 120), 'GuardRail_Post': (95.5, 120),
    'Cone': (97.5, 120), 'Mailbox': (99.5, 120), 'Bin': (101.5, 120), 'Bench': (104, 120),
    'Barrier_Jersey': (108, 120), 'Fuel_Pump': (113, 120), 'Lamp_Street': (118, 120), 'Utility_Pole': (122, 120),
    'Speed_Trap_Camera': (126, 120), 'Flag_Pole': (130, 120), 'Festival_Banner': (133, 120),
    'Fence_Wood': (82, 132), 'Wall_Stone': (88, 132), 'Hedge': (94, 132), 'Bus_Stop': (101, 132),
    'Billboard': (112, 132),
    'Bridge_Pier': (82, 150), 'Tunnel_Portal': (98, 150), 'Checkpoint_Arch': (120, 150),
}

# budgets (evaluated triangles)
BUDGET = {'Sign_': 400, 'Hedge': 600, 'Bus_Stop': 1500, 'Billboard': 1500, 'Bridge_Pier': 1500,
          'Tunnel_Portal': 8000, 'Checkpoint_Arch': 4000, '': 800}

# name: dict(c = sRGB base, r = roughness, m = metallic, e = sRGB emission, es = emission strength,
#            ds = double sided, a = alpha (< 1 -> blended))
MATS = {
    'RK_SteelGalv': dict(c=(178, 182, 184), r=0.42, m=0.7),
    'RK_PoleGrey': dict(c=(80, 85, 90), r=0.45, m=0.45),
    'RK_Alu': dict(c=(208, 211, 214), r=0.3, m=0.8),
    'RK_SignWhite': dict(c=(240, 240, 234), r=0.4),
    'RK_SignRed': dict(c=(200, 22, 30), r=0.4),
    'RK_SignYellow': dict(c=(250, 196, 18), r=0.4),
    'RK_SignGreen': dict(c=(10, 104, 64), r=0.4),
    'RK_SignBack': dict(c=(150, 154, 158), r=0.5, m=0.5),
    'RK_Black': dict(c=(20, 20, 22), r=0.5),
    'RK_PlasticWhite': dict(c=(236, 236, 230), r=0.5),
    'RK_ReflectorAmber': dict(c=(255, 150, 20), r=0.25, e=(255, 138, 18), es=0.6),
    'RK_ReflectorWhite': dict(c=(240, 240, 236), r=0.25, e=(235, 235, 228), es=0.3),
    'LampLens': dict(c=(255, 244, 224), r=0.2, e=(255, 218, 166), es=1.0),
    'RK_Concrete': dict(c=(172, 168, 160), r=0.9),
    'RK_ConcreteLight': dict(c=(194, 190, 182), r=0.88),
    'RK_WoodFence': dict(c=(146, 116, 84), r=0.9),
    'RK_WoodPole': dict(c=(116, 92, 68), r=0.92),
    'RK_Porcelain': dict(c=(216, 216, 208), r=0.2),
    'RK_Stone': dict(c=(170, 164, 152), r=0.92),
    'RK_StoneGap': dict(c=(74, 72, 66), r=0.95),
    'RK_Hedge_Leaf': dict(c=(78, 116, 50), r=0.8),
    'RK_PaintTeal': dict(c=(16, 138, 140), r=0.4),
    'RK_PaintOrange': dict(c=(244, 122, 22), r=0.4),
    'RK_PaintYellow': dict(c=(246, 194, 30), r=0.45),
    'RK_PaintWhite': dict(c=(236, 238, 238), r=0.38),
    'RK_ShelterFrame': dict(c=(40, 78, 72), r=0.42, m=0.35),
    'RK_ShelterRoof': dict(c=(196, 200, 202), r=0.5, m=0.1),
    'RK_Glass': dict(c=(168, 188, 194), r=0.05, ds=True, a=0.3),
    'RK_AdPanel': dict(c=(236, 236, 232), r=0.5, e=(240, 240, 236), es=0.35),
    'RK_BenchWood': dict(c=(156, 108, 66), r=0.7),
    'RK_CastIron': dict(c=(38, 42, 42), r=0.55, m=0.45),
    'RK_MailRed': dict(c=(170, 34, 28), r=0.42, m=0.15),
    'RK_BinGreen': dict(c=(36, 82, 60), r=0.5, m=0.3),
    'RK_Rubber': dict(c=(30, 30, 32), r=0.85),
    'RK_ConeOrange': dict(c=(255, 96, 14), r=0.5),
    'RK_ReflectBand': dict(c=(242, 242, 240), r=0.3),
    'RK_PumpDark': dict(c=(52, 56, 60), r=0.45, m=0.2),
    'RK_PumpScreen': dict(c=(20, 40, 48), r=0.15, e=(60, 200, 230), es=0.5),
    'RK_NozzleGreen': dict(c=(34, 140, 70), r=0.45),
    'RK_CameraGlass': dict(c=(14, 18, 24), r=0.08),
    'RK_FlashLens': dict(c=(236, 240, 244), r=0.15, e=(220, 230, 255), es=0.4),
    'RK_LightBarOrange': dict(c=(255, 130, 30), r=0.3, e=(255, 110, 10), es=1.0),
    'RK_FloodLens': dict(c=(240, 238, 230), r=0.2, e=(255, 240, 210), es=0.5),
    'BillboardPanel': dict(c=(240, 240, 236), r=0.6),
    'RK_Inflatable_Orange': dict(c=(248, 118, 24), r=0.35),
    'RK_Inflatable_Magenta': dict(c=(222, 40, 128), r=0.35),
    'RK_Inflatable_Yellow': dict(c=(252, 204, 40), r=0.35),
    'RK_Inflatable_Teal': dict(c=(18, 160, 164), r=0.35),
    'RK_FabricDark': dict(c=(40, 46, 64), r=0.8),
    'RK_BannerWhite': dict(c=(244, 244, 240), r=0.6),
    'RK_Flag_Orange': dict(c=(246, 120, 24), r=0.75, ds=True),
    'RK_Flag_Teal': dict(c=(16, 146, 150), r=0.75, ds=True),
    'RK_Flag_Magenta': dict(c=(214, 36, 122), r=0.75, ds=True),
    'RK_Gold': dict(c=(230, 180, 70), r=0.3, m=0.9),
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


def V(x, y, z):
    return Vector((x, y, z))


def rv(R, s=100.0):
    return Vector((R.uniform(0, s), R.uniform(0, s), R.uniform(0, s)))


def newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    k = len(pts)
    for i in range(k):
        a, b = pts[i], pts[(i + 1) % k]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def signed_volume(verts, faces):
    vol = 0.0
    for f in faces:
        for i in range(1, len(f) - 1):
            vol += verts[f[0]].dot(verts[f[i]].cross(verts[f[i + 1]]))
    return vol / 6.0


def rot_x(a):
    return Matrix.Rotation(a, 3, 'X')


def rot_y(a):
    return Matrix.Rotation(a, 3, 'Y')


def rot_z(a):
    return Matrix.Rotation(a, 3, 'Z')


def check_file():
    fp = bpy.data.filepath
    if os.path.normcase(os.path.abspath(fp)) != os.path.normcase(EXPECTED_BLEND):
        raise RuntimeError('BLOCKED: wrong blend file %s' % fp)


# ------------------------------------------------------------------------------------------------------ materials
def _sock(node, ident, out=False):
    return next(s for s in (node.outputs if out else node.inputs) if s.identifier == ident)


def make_mat(name):
    d = MATS[name]
    lin = srgb2lin(d['c'])
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
    _sock(bsdf, 'Roughness').default_value = d.get('r', 0.6)
    _sock(bsdf, 'Metallic').default_value = d.get('m', 0.0)
    if d.get('e'):
        el = srgb2lin(d['e'])
        _sock(bsdf, 'Emission Color').default_value = (el[0], el[1], el[2], 1.0)
        _sock(bsdf, 'Emission Strength').default_value = d.get('es', 1.0)
    else:
        _sock(bsdf, 'Emission Strength').default_value = 0.0
    alpha = d.get('a', 1.0)
    _sock(bsdf, 'Alpha').default_value = alpha
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    mat.use_backface_culling = not d.get('ds', False)
    mat.diffuse_color = (lin[0], lin[1], lin[2], alpha)
    mat.roughness = d.get('r', 0.6)
    mat.metallic = d.get('m', 0.0)
    methods = [i.identifier for i in bpy.types.Material.bl_rna.properties['surface_render_method'].enum_items]
    want = 'BLENDED' if alpha < 1.0 else 'DITHERED'
    if want in methods:
        mat.surface_render_method = want
    return mat


# ------------------------------------------------------------------------------------------------------ builder
class PB:
    """One prop = one bmesh; parts are appended with per-face material, smooth flag and corner colour."""

    def __init__(self, name, seed):
        self.name = name
        self.R = random.Random(seed)
        self.bm = bmesh.new()
        self.cl = self.bm.loops.layers.float_color.new('Col')
        self.mats = []
        self.uvo = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def add(self, verts, faces, mat, smooth=False, fcol=None, vcols=None, vfn=None, hint=None, uvfn=None):
        """hint: Vector or callable(face centre) -> wanted normal direction (faces are reversed to match).
        fcol: colour or callable(centre, normal) per face; vcols: colour per vertex index; vfn(co) per vertex."""
        bm = self.bm
        verts = [Vector(v) for v in verts]
        bv = [bm.verts.new(v) for v in verts]
        out = []
        for k, f in enumerate(faces):
            f = list(f)
            if len(set(f)) < 3:
                continue
            pts = [verts[i] for i in f]
            nrm = newell(pts)
            if nrm.length < 1e-12:
                continue
            if hint is not None:
                cen = sum(pts, Vector()) / len(pts)
                h = hint(cen) if callable(hint) else Vector(hint)
                if nrm.dot(h) < 0.0:
                    f.reverse()
                    nrm = -nrm
            try:
                face = bm.faces.new([bv[i] for i in f])
            except ValueError:
                continue
            face.material_index = self.mi(mat[k] if isinstance(mat, (list, tuple)) else mat)
            face.smooth = smooth[k] if isinstance(smooth, (list, tuple)) else smooth
            face.normal_update()
            if vcols is not None or vfn is not None:
                for lp, i in zip(face.loops, f):
                    c = clamp01(vcols[i] if vcols is not None else vfn(verts[i]))
                    lp[self.cl] = (c[0], c[1], c[2], 1.0)
            else:
                if callable(fcol):
                    c = fcol(face.calc_center_median(), face.normal)
                else:
                    c = fcol or (1.0, 1.0, 1.0)
                c = clamp01(c)
                for lp in face.loops:
                    lp[self.cl] = (c[0], c[1], c[2], 1.0)
            if uvfn is not None:
                self.uvo.append((face, uvfn))
            out.append(face)
        return out


def shell(pb, verts, faces, mat, **kw):
    """Closed shell: orientation fixed by the signed volume (outward normals)."""
    verts = [Vector(v) for v in verts]
    if signed_volume(verts, faces) < 0:
        faces = [tuple(reversed(f)) for f in faces]
    return pb.add(verts, faces, mat, **kw)


def extrude(pb, poly, to3d, d0, d1, mat, side_mat=None, cap_mats=None, mids=(), cap0=True, cap1=True,
            smooth=False, **kw):
    """Extrude a simple 2D polygon (any winding, may be concave) along d. to3d(u, v, d) -> world.
    side_mat(i, j) per side face (i = ring interval), cap_mats = (back, front)."""
    n = len(poly)
    cu = sum(p[0] for p in poly) / n
    cv = sum(p[1] for p in poly) / n
    nf = newell([to3d(u, v, d1) for u, v in poly])
    if nf.dot(to3d(cu, cv, d1) - to3d(cu, cv, d0)) < 0:
        poly = list(reversed(poly))
    ds = [d0] + list(mids) + [d1]
    verts = [to3d(u, v, d) for d in ds for (u, v) in poly]
    faces, mats, sm = [], [], []
    for i in range(len(ds) - 1):
        for j in range(n):
            j1 = (j + 1) % n
            faces.append((i * n + j, i * n + j1, (i + 1) * n + j1, (i + 1) * n + j))
            mats.append(side_mat(i, j) if callable(side_mat) else (side_mat or mat))
            sm.append(smooth)
    cm = cap_mats or (mat, mat)
    if cap0:
        faces.append(tuple(reversed(range(n))))
        mats.append(cm[0] or mat)
        sm.append(False)
    if cap1:
        faces.append(tuple(range((len(ds) - 1) * n, len(ds) * n)))
        mats.append(cm[1] or mat)
        sm.append(False)
    return pb.add(verts, faces, mats, smooth=sm, **kw)


def box(pb, c, s, mat, rot=None, side_mat=None, cap_mats=None, **kw):
    hx, hy, hz = s[0] / 2.0, s[1] / 2.0, s[2] / 2.0
    M = rot or Matrix.Identity(3)
    c = Vector(c)
    poly = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    return extrude(pb, poly, lambda u, v, d: c + M @ Vector((u, v, d)), -hz, hz, mat, side_mat=side_mat,
                   cap_mats=cap_mats, **kw)


def box2(pb, lo, hi, mat, **kw):
    lo, hi = Vector(lo), Vector(hi)
    return box(pb, (lo + hi) / 2, hi - lo, mat, **kw)


def hexa(pb, pts, mat, **kw):
    """8 corners: 4 bottom then the 4 matching top corners (same order)."""
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)] + [(i, (i + 1) % 4, 4 + (i + 1) % 4, 4 + i) for i in range(4)]
    return shell(pb, pts, faces, mat, **kw)


def loft(pb, rings, mat, side_mat=None, cap_mats=(None, None), cap0=True, cap1=True, smooth=False, **kw):
    """Side faces between consecutive rings (same vertex count) + optional caps; outward orientation."""
    N, n = len(rings), len(rings[0])
    verts = [Vector(p) for r in rings for p in r]
    faces, mats, sm = [], [], []
    for i in range(N - 1):
        for j in range(n):
            j1 = (j + 1) % n
            faces.append((i * n + j, i * n + j1, (i + 1) * n + j1, (i + 1) * n + j))
            mats.append(side_mat(i, j) if side_mat else mat)
            sm.append(smooth)
    if cap0:
        faces.append(tuple(reversed(range(n))))
        mats.append(cap_mats[0] or mat)
        sm.append(False)
    if cap1:
        faces.append(tuple(range((N - 1) * n, N * n)))
        mats.append(cap_mats[1] or mat)
        sm.append(False)
    if cap0 and cap1:
        flip = signed_volume(verts, faces) < 0
    else:
        c0 = sum(rings[0], Vector()) / n
        f = faces[0]
        fc = sum((verts[i] for i in f), Vector()) / 4
        flip = newell([verts[i] for i in f]).dot(fc - c0) < 0
    if flip:
        faces = [tuple(reversed(f)) for f in faces]
    return pb.add(verts, faces, mats, smooth=sm, **kw)


def tube(pb, pts, radii, mat, sides=6, cap0=True, cap1=True, tip=0.0, smooth=True, rfn=None, vfn=None,
         side_mat=None, cap_mat=None, phase=0.0):
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
            a = phase + 2 * PI * j / sides
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
        c = pts[-1] + T[-1] * tip
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
    return pb.add(verts, faces, fmats, smooth=fsm, vcols=cols)


def sphere(pb, c, r, mat, seg=8, rings=5, scale=(1.0, 1.0, 1.0), smooth=True, **kw):
    c = Vector(c)
    verts = [c + V(0, 0, -r * scale[2])]
    for k in range(1, rings):
        th = PI * k / rings
        z, rr = -math.cos(th) * r, math.sin(th) * r
        for j in range(seg):
            a = 2 * PI * j / seg
            verts.append(c + V(rr * math.cos(a) * scale[0], rr * math.sin(a) * scale[1], z * scale[2]))
    verts.append(c + V(0, 0, r * scale[2]))
    top = len(verts) - 1
    faces = []
    for j in range(seg):
        faces.append((0, 1 + (j + 1) % seg, 1 + j))
    for k in range(rings - 2):
        b0, b1 = 1 + k * seg, 1 + (k + 1) * seg
        for j in range(seg):
            j1 = (j + 1) % seg
            faces.append((b0 + j, b0 + j1, b1 + j1, b1 + j))
    bl = 1 + (rings - 2) * seg
    for j in range(seg):
        faces.append((bl + j, bl + (j + 1) % seg, top))
    return shell(pb, verts, faces, mat, smooth=smooth, **kw)


_ICO = {}


def ico_data(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub + 1, radius=1.0)
        bm.verts.index_update()
        _ICO[sub] = ([v.co.copy() for v in bm.verts], [tuple(v.index for v in f.verts) for f in bm.faces])
        bm.free()
    return _ICO[sub]


def blob(pb, c, r, mat, sub=0, amp=0.2, freq=1.4, squash=0.25, fcol=None):
    vs, fs = ico_data(sub)
    R = pb.R
    off, off2 = rv(R), rv(R)
    out = []
    for v in vs:
        d = v.normalized()
        k = 1.0 + amp * noise.noise(d * freq + off) + 0.5 * amp * noise.noise(d * freq * 2.3 + off2)
        p = Vector((d.x * r[0], d.y * r[1], d.z * r[2] * ((1.0 - squash) if d.z < 0 else 1.0))) * k
        out.append(Vector(c) + p)
    return pb.add(out, fs, mat, smooth=False, fcol=fcol)


# ---- 2D outlines (sign coordinates: sx = viewer's right, sy = up, counter-clockwise)
def circle2(r, n, a0=0.0):
    return [(r * math.cos(a0 + 2 * PI * k / n), r * math.sin(a0 + 2 * PI * k / n)) for k in range(n)]


def rrect2(w, h, r, seg=3):
    if r <= 0.0:
        return [(w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2), (-w / 2, -h / 2)]
    out = []
    for cx, cy, a0 in ((w / 2 - r, -h / 2 + r, -PI / 2), (w / 2 - r, h / 2 - r, 0.0),
                       (-w / 2 + r, h / 2 - r, PI / 2), (-w / 2 + r, -h / 2 + r, PI)):
        for k in range(seg + 1):
            a = a0 + (PI / 2) * k / seg
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def rot2(poly, a, ox=0.0, oy=0.0):
    c, s = math.cos(a), math.sin(a)
    return [(ox + x * c - y * s, oy + x * s + y * c) for x, y in poly]


def inset2(poly, d):
    """Offset a convex counter-clockwise polygon inwards by d (mitred)."""
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((-e1.y, e1.x))
        n2 = Vector((-e2.y, e2.x))
        k = 1.0 + n1.dot(n2)
        q = p1 + (n1 + n2) * (d / max(k, 1e-6))
        out.append((q.x, q.y))
    return out


class SignFrame:
    """Plane of a sign: O centre, N front normal, U up; R = viewer's right (R x U = N)."""

    def __init__(self, O, N=(0, 1, 0), U=(0, 0, 1)):
        self.O = Vector(O)
        self.N = Vector(N).normalized()
        self.U = Vector(U).normalized()
        self.R = self.U.cross(self.N)

    def p(self, sx, sy, t=0.0):
        return self.O + self.R * sx + self.U * sy + self.N * t


def plate(pb, F, outline, t0, t1, bands, side_mat, back_mat=None, back_bands=None, fcol=None):
    """Flat sign plate between t0 (back) and t1 (front) along F.N. bands = [(inset, mat), ...] from the edge in
    (first inset 0); the last band fills the centre. The front gets planar UVs 0..1 over the outline."""
    n = len(outline)
    xs = [p[0] for p in outline]
    ys = [p[1] for p in outline]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)

    def uvf(co):
        d = co - F.O
        return ((d.dot(F.R) - x0) / (x1 - x0), (d.dot(F.U) - y0) / (y1 - y0))

    def side(bnds, t, hint):
        loops = [outline] + [inset2(outline, b[0]) for b in bnds[1:]]
        for k in range(len(loops)):
            if k < len(loops) - 1:
                A, B = loops[k], loops[k + 1]
                verts = [F.p(x, y, t) for x, y in A] + [F.p(x, y, t) for x, y in B]
                faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
                pb.add(verts, faces, bnds[k][1], fcol=fcol, hint=hint, uvfn=uvf)
            else:
                pb.add([F.p(x, y, t) for x, y in loops[k]], [tuple(range(n))], bnds[k][1], fcol=fcol, hint=hint,
                       uvfn=uvf)
    side(bands, t1, F.N)
    if back_bands:
        side(back_bands, t0, -F.N)
    else:
        pb.add([F.p(x, y, t0) for x, y in outline], [tuple(range(n))], back_mat or side_mat, fcol=fcol, hint=-F.N)
    verts = [F.p(x, y, t0) for x, y in outline] + [F.p(x, y, t1) for x, y in outline]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    pb.add(verts, faces, side_mat, fcol=fcol, hint=lambda c: (c - F.O) - F.N * (c - F.O).dot(F.N))


def decal(pb, F, poly, t0, t1, mat, fcol=None):
    """Raised pictogram shape on a sign face (open at the back, which sits inside the plate)."""
    return extrude(pb, poly, lambda u, v, d: F.p(u, v, d), t0, t1, mat, cap0=False, fcol=fcol)


# ---- colour helpers
def grime(R, z0=-0.2, z1=0.5, dark=0.72, lo=0.93, hi=1.0, tint=(1.0, 1.0, 1.0)):
    def f(c, n):
        k = lerp(dark, 1.0, smoothstep(z0, z1, c.z)) * R.uniform(lo, hi)
        return (k * tint[0], k * tint[1], k * tint[2])
    return f


def flat(k=1.0, tint=(1.0, 1.0, 1.0)):
    return (k * tint[0], k * tint[1], k * tint[2])


def clean(R, lo=0.96, hi=1.0):
    def f(c, n):
        k = R.uniform(lo, hi)
        return (k, k, k)
    return f


def post_tube(pb, x, y, z0, z1, r=0.038, sides=8, mat='RK_SteelGalv', cap_top=True):
    R = pb.R

    def vf(i, j, p):
        k = lerp(0.7, 1.0, smoothstep(-0.1, 0.45, p.z)) * R.uniform(0.95, 1.0)
        return (k, k, k)
    tube(pb, [V(x, y, z0), V(x, y, 0.02), V(x, y, z1)], [r, r, r], mat, sides=sides, cap0=True, cap1=not cap_top,
         vfn=vf)
    if cap_top:
        tube(pb, [V(x, y, z1 - 0.01), V(x, y, z1 + 0.02)], [r * 1.12, r * 1.12], 'RK_Black', sides=sides, cap0=True,
             cap1=True, tip=0.012, smooth=False)


# ------------------------------------------------------------------------------------------------------ signs
def sign_speedlimit():
    pb = PB('Sign_SpeedLimit', 11)
    zc = 2.10
    post_tube(pb, 0, 0, -0.35, zc + 0.34)
    for dz in (-0.22, 0.22):
        box(pb, V(0, 0.004, zc + dz), (0.1, 0.098, 0.045), 'RK_SteelGalv', fcol=flat(0.85))
    F = SignFrame(V(0, 0, zc))
    plate(pb, F, circle2(0.40, 28, PI / 28), 0.045, 0.065,
          [(0.0, 'RK_SignWhite'), (0.012, 'RK_SignRed'), (0.088, 'RK_SignWhite')], 'RK_SignBack',
          fcol=clean(pb.R, 0.97, 1.0))
    return pb


def sign_chevron():
    pb = PB('Sign_Chevron', 12)
    zc = 1.55
    post_tube(pb, 0, 0, -0.35, zc + 0.26)
    for dz in (-0.17, 0.17):
        box(pb, V(0, 0.004, zc + dz), (0.1, 0.098, 0.045), 'RK_SteelGalv', fcol=flat(0.85))
    F = SignFrame(V(0, 0, zc))
    plate(pb, F, rrect2(0.80, 0.60, 0.035, 2), 0.045, 0.065, [(0.0, 'RK_SignYellow')], 'RK_SignBack',
          fcol=clean(pb.R, 0.97, 1.0))
    t, dd, h = 0.12, 0.17, 0.44
    for x0 in (-0.32, 0.03):
        poly = [(x0, h / 2), (x0 + t, h / 2), (x0 + t + dd, 0.0), (x0 + t, -h / 2), (x0, -h / 2), (x0 + dd, 0.0)]
        decal(pb, F, poly, 0.058, 0.07, 'RK_Black')
    return pb


def sign_danger_jump():
    pb = PB('Sign_Danger_Jump', 13)
    zc = 2.25
    post_tube(pb, 0, 0, -0.35, zc + 0.42)
    for dz in (-0.26, 0.26):
        box(pb, V(0, 0.004, zc + dz), (0.1, 0.098, 0.045), 'RK_SteelGalv', fcol=flat(0.85))
    F = SignFrame(V(0, 0, zc))
    outline = rot2(rrect2(0.90, 0.90, 0.05, 3), PI / 4)
    plate(pb, F, outline, 0.045, 0.065,
          [(0.0, 'RK_SignYellow'), (0.016, 'RK_Black'), (0.05, 'RK_SignYellow')], 'RK_SignBack',
          fcol=clean(pb.R, 0.97, 1.0))
    # pictogram: hump on a ground line + a car leaping off its crest + two speed dashes (all raised black geometry)
    t0, t1 = 0.058, 0.0715
    gy, gt, gx = -0.215, 0.03, 0.30
    hx, ha, hb = -0.07, 0.16, 0.105
    hump = [(-gx, gy - gt), (gx, gy - gt), (gx, gy), (hx + ha, gy)]
    hump += [(hx + ha * math.cos(a), gy + hb * math.sin(a)) for a in [PI * k / 10 for k in range(1, 10)]]
    hump += [(hx - ha, gy), (-gx, gy)]
    decal(pb, F, hump, t0, t1, 'RK_Black')
    s = 1.2
    body = [(-0.17, 0.012), (0.17, 0.012), (0.178, 0.052), (0.075, 0.068), (0.032, 0.112), (-0.088, 0.115),
            (-0.138, 0.074), (-0.178, 0.064)]
    ang, cx, cy = math.radians(15.0), 0.075, -0.045
    decal(pb, F, rot2([(x * s, y * s) for x, y in body], ang, cx, cy), t0, t1, 'RK_Black')
    for wx in (-0.105, 0.108):
        wheel = [(wx * s + 0.042 * s * math.cos(a), 0.012 * s + 0.042 * s * math.sin(a))
                 for a in [2 * PI * k / 8 for k in range(8)]]
        decal(pb, F, rot2(wheel, ang, cx, cy), t0, t1, 'RK_Black')
    for (dx, dy, ln) in ((-0.265, 0.03, 0.1), (-0.255, 0.085, 0.08)):
        dash = [(-ln / 2, -0.012), (ln / 2, -0.012), (ln / 2, 0.012), (-ln / 2, 0.012)]
        decal(pb, F, rot2(dash, ang, dx, dy), t0, t1, 'RK_Black')
    return pb


def sign_direction():
    pb = PB('Sign_Direction', 14)
    zc = 2.40
    for x in (-0.8, 0.8):
        post_tube(pb, x, 0, -0.4, 3.02, r=0.045)
        for z in (1.95, 2.85):
            box(pb, V(x, 0.0, z), (0.12, 0.115, 0.07), 'RK_SteelGalv', fcol=flat(0.85))
    for z in (1.95, 2.85):
        box2(pb, V(-1.22, 0.035, z - 0.03), V(1.22, 0.062, z + 0.03), 'RK_SignBack', fcol=flat(0.8))
    F = SignFrame(V(0, 0, zc))
    plate(pb, F, rrect2(2.60, 1.40, 0.06, 3), 0.06, 0.085,
          [(0.0, 'RK_SignGreen'), (0.025, 'RK_SignWhite'), (0.06, 'RK_SignGreen')], 'RK_SignBack',
          fcol=clean(pb.R, 0.97, 1.0))
    return pb


# ------------------------------------------------------------------------------------------------------ small posts
def delineator_post():
    pb = PB('Delineator_Post', 21)
    prof = [(-0.06, -0.045), (0.06, -0.045), (0.06, 0.03), (0.035, 0.058), (-0.035, 0.058), (-0.06, 0.03)]
    zs = [-0.3, 0.02, 0.86, 1.10]
    rings = [[V(x, y, z) for x, y in prof] for z in zs]
    R = pb.R

    def col(c, n):
        k = lerp(0.62, 1.0, smoothstep(-0.1, 0.5, c.z)) * R.uniform(0.96, 1.0)
        return (k, k, k * 0.98)
    loft(pb, rings, 'RK_PlasticWhite', side_mat=lambda i, j: 'RK_Black' if i == 2 else 'RK_PlasticWhite',
         cap_mats=('RK_PlasticWhite', 'RK_Black'), fcol=col)
    box2(pb, V(-0.024, 0.052, 0.91), V(0.024, 0.066, 1.05), 'RK_ReflectorAmber')
    for x in (-0.025, 0.025):
        box2(pb, V(x - 0.012, -0.053, 0.96), V(x + 0.012, -0.04, 0.99), 'RK_ReflectorWhite')
    return pb


def guardrail_post():
    pb = PB('GuardRail_Post', 22)
    w, d, t = 0.12, 0.055, 0.006
    # C profile, web on the road side (+Y), flanges pointing back
    prof = [(-w / 2, d / 2), (w / 2, d / 2), (w / 2, -d / 2), (w / 2 - t, -d / 2), (w / 2 - t, d / 2 - t),
            (-w / 2 + t, d / 2 - t), (-w / 2 + t, -d / 2), (-w / 2, -d / 2)]
    col = grime(pb.R, -0.1, 0.4, 0.62, 0.96, 1.0)
    extrude(pb, prof, lambda u, v, dd: V(u, v, dd), -0.4, 0.8, 'RK_SteelGalv', mids=(0.03,), fcol=col)
    # spacer block with bolt heads (the W-beam is built by Godot)
    box2(pb, V(-0.05, 0.026, 0.42), V(0.05, 0.17, 0.76), 'RK_SteelGalv', fcol=flat(0.92))
    for z in (0.52, 0.66):
        tube(pb, [V(0, 0.169, z), V(0, 0.19, z)], [0.016, 0.016], 'RK_SteelGalv', sides=6, smooth=False)
    return pb


def cone():
    pb = PB('Cone', 23)
    base = [(0.19, 0.12), (0.12, 0.19), (-0.12, 0.19), (-0.19, 0.12), (-0.19, -0.12), (-0.12, -0.19),
            (0.12, -0.19), (0.19, -0.12)]
    extrude(pb, base, lambda u, v, d: V(u, v, d), -0.01, 0.035, 'RK_Rubber', fcol=clean(pb.R, 0.9, 1.0))
    zs = [0.03, 0.36, 0.44, 0.53, 0.59, 0.70]
    rr = [lerp(0.165, 0.026, (z - 0.03) / 0.67) for z in zs]

    def sm(i, j):
        return 'RK_ReflectBand' if i in (1, 3) else 'RK_ConeOrange'
    tube(pb, [V(0, 0, z) for z in zs], rr, 'RK_ConeOrange', sides=12, cap0=True, cap1=True, side_mat=sm,
         vfn=lambda i, j, p: (lerp(0.8, 1.0, smoothstep(0.0, 0.3, p.z)),) * 3)
    return pb


def mailbox():
    pb = PB('Mailbox', 24)
    R = pb.R
    box2(pb, V(-0.045, -0.045, -0.4), V(0.045, 0.045, 1.0), 'RK_WoodFence', fcol=grime(R, -0.1, 0.5, 0.6, 0.9, 1.0),
         mids=())
    box2(pb, V(-0.1, -0.24, 0.985), V(0.1, 0.3, 1.015), 'RK_WoodFence', fcol=flat(0.9))
    box2(pb, V(-0.03, -0.12, 0.86), V(0.03, -0.045, 0.99), 'RK_WoodFence', fcol=flat(0.85))
    prof = [(-0.09, 1.015), (0.09, 1.015), (0.09, 1.16)]
    prof += [(0.09 * math.cos(a), 1.16 + 0.09 * math.sin(a)) for a in [PI * k / 6 for k in range(1, 6)]]
    prof += [(-0.09, 1.16)]
    extrude(pb, prof, lambda u, v, d: V(u, d, v), -0.22, 0.26, 'RK_MailRed', fcol=clean(R, 0.92, 1.0))
    door = [(x * 1.06, 1.088 + (y - 1.088) * 1.06) for x, y in prof]
    extrude(pb, door, lambda u, v, d: V(u, d, v), 0.25, 0.272, 'RK_MailRed', fcol=flat(0.86))
    box2(pb, V(-0.025, 0.27, 1.19), V(0.025, 0.292, 1.21), 'RK_SteelGalv')
    # signal flag (raised) on the viewer's right (Blender -X)
    box2(pb, V(-0.102, -0.13, 1.06), V(-0.09, -0.105, 1.33), 'RK_PaintYellow')
    box2(pb, V(-0.104, -0.105, 1.24), V(-0.092, 0.0, 1.32), 'RK_PaintYellow')
    return pb


def bin_():
    pb = PB('Bin', 25)
    R = pb.R
    pts = [V(0, 0, -0.05), V(0, 0, 0.04), V(0, 0, 0.04), V(0, 0, 0.42), V(0, 0, 0.8), V(0, 0, 0.8), V(0, 0, 0.9)]
    rad = [0.25, 0.25, 0.27, 0.28, 0.29, 0.305, 0.305]

    def sm(i, j):
        if i == 0 or i == 1:
            return 'RK_Black'
        if i == 5:
            return 'RK_Black' if j in (2,) else 'RK_BinGreen'
        if i == 4:
            return 'RK_Black'
        return 'RK_BinGreen'

    def vf(i, j, p):
        k = (0.86 if j % 2 else 1.0) * lerp(0.75, 1.0, smoothstep(0.0, 0.5, p.z))
        return (k, k, k)
    tube(pb, pts, rad, 'RK_BinGreen', sides=12, cap0=True, cap1=False, smooth=False, side_mat=sm, vfn=vf,
         phase=PI / 12)
    # domed lid
    lid = [V(0, 0, 0.9), V(0, 0, 0.94), V(0, 0, 0.975)]
    tube(pb, lid, [0.305, 0.25, 0.12], 'RK_BinGreen', sides=12, cap0=False, cap1=True, tip=0.012, smooth=True,
         phase=PI / 12, vfn=lambda i, j, p: (0.95, 0.95, 0.95))
    return pb


# ------------------------------------------------------------------------------------------------------ lamp / poles
def lamp_street():
    pb = PB('Lamp_Street', 31)
    R = pb.R
    tube(pb, [V(0, 0, -0.3), V(0, 0, 0.06)], [0.22, 0.22], 'RK_Concrete', sides=8, smooth=False,
         vfn=lambda i, j, p: (0.75 + 0.2 * i,) * 3)
    tube(pb, [V(0, 0, 0.0), V(0, 0, 0.5), V(0, 0, 0.56)], [0.14, 0.13, 0.095], 'RK_PoleGrey', sides=8, cap0=False,
         cap1=False, vfn=lambda i, j, p: (lerp(0.75, 1.0, min(1.0, p.z * 2)),) * 3)
    tube(pb, [V(0, 0, 0.5), V(0, 0, 3.0), V(0, 0, 5.9)], [0.088, 0.073, 0.058], 'RK_PoleGrey', sides=8, cap0=False,
         cap1=True, vfn=lambda i, j, p: (R.uniform(0.95, 1.0),) * 3)
    arm = [V(0, 0, 5.45), V(0, 0, 5.85), V(0, 0.05, 6.05), V(0, 0.18, 6.19), V(0, 0.4, 6.27), V(0, 0.75, 6.3),
           V(0, 1.1, 6.3), V(0, 1.45, 6.28)]
    tube(pb, arm, [0.056, 0.055, 0.052, 0.05, 0.048, 0.046, 0.044, 0.042], 'RK_PoleGrey', sides=6, cap0=False,
         cap1=True)
    # luminaire (flat LED head), centre ~ (0, 1.75, 6.2)
    y0, y1 = 1.36, 2.14

    def zb(y):
        return lerp(6.2, 6.17, (y - y0) / (y1 - y0))
    hw0, hw1, zt0, zt1 = 0.12, 0.16, 6.34, 6.24
    body = [V(-hw0, y0, zb(y0)), V(hw0, y0, zb(y0)), V(hw1, y1, zb(y1)), V(-hw1, y1, zb(y1)),
            V(-hw0 * 0.8, y0, zt0), V(hw0 * 0.8, y0, zt0), V(hw1 * 0.85, y1, zt1), V(-hw1 * 0.85, y1, zt1)]
    hexa(pb, body, 'RK_PoleGrey', fcol=lambda c, n: (0.8, 0.8, 0.8) if n.z < -0.5 else (1.0, 1.0, 1.0))
    ly0, ly1 = 1.5, 2.04

    def hw(y):
        return lerp(hw0, hw1, (y - y0) / (y1 - y0)) - 0.03
    lens = [V(-hw(ly0), ly0, zb(ly0) - 0.014), V(hw(ly0), ly0, zb(ly0) - 0.014), V(hw(ly1), ly1, zb(ly1) - 0.014),
            V(-hw(ly1), ly1, zb(ly1) - 0.014),
            V(-hw(ly0), ly0, zb(ly0) + 0.006), V(hw(ly0), ly0, zb(ly0) + 0.006), V(hw(ly1), ly1, zb(ly1) + 0.006),
            V(-hw(ly1), ly1, zb(ly1) + 0.006)]
    hexa(pb, lens, 'LampLens')
    tube(pb, [V(0, 1.52, 6.3), V(0, 1.52, 6.36)], [0.03, 0.03], 'RK_Black', sides=6, smooth=False, tip=0.012)
    return pb


def utility_pole():
    pb = PB('Utility_Pole', 32)
    R = pb.R
    zs = [-0.5, 0.0, 0.6, 2.5, 4.5, 6.5, 8.0, 9.0]
    off = rv(R)
    pts = [V(0.03 * math.sin(z * 0.35), 0.02 * math.sin(z * 0.27 + 1.0), z) for z in zs]
    rad = [lerp(0.152, 0.112, (z + 0.5) / 9.5) for z in zs]

    def rf(i, j, a):
        return 1.0 + 0.045 * noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, i * 0.7)) + off)

    def vf(i, j, p):
        k = R.uniform(0.86, 1.0) * (lerp(0.55, 1.0, smoothstep(0.2, 0.9, p.z)))
        g = smoothstep(4.0, 9.0, p.z) * 0.12
        return (k * (1 - g * 0.5), k * (1 - g * 0.4), k * (1 - g * 0.1))
    tube(pb, pts, rad, 'RK_WoodPole', sides=8, cap0=True, cap1=True, tip=0.03, smooth=True, rfn=rf, vfn=vf)
    top = pts[-1]
    ax = top.x + 0.15
    za = 8.55
    box(pb, V(ax, 0.0, za), (0.09, 2.4, 0.11), 'RK_WoodPole', fcol=grime(R, 0, 1, 1, 0.82, 0.95))
    for s in (-1, 1):
        tube(pb, [V(ax - 0.01, s * 0.7, za - 0.05), V(top.x + 0.1, 0.0, 7.92)], [0.022, 0.022], 'RK_SteelGalv',
             sides=4, smooth=False, phase=PI / 4)
    prof = [(0.0, 0.026), (0.03, 0.066), (0.048, 0.042), (0.08, 0.056), (0.1, 0.036), (0.14, 0.034)]
    for y in (-1.0, -0.38, 1.0):
        tube(pb, [V(ax, y, za + 0.04), V(ax, y, za + 0.09)], [0.012, 0.012], 'RK_SteelGalv', sides=5, smooth=False)
        tube(pb, [V(ax, y, za + 0.075 + dz) for dz, r in prof], [r for dz, r in prof], 'RK_Porcelain', sides=7,
             cap0=True, cap1=True, tip=0.012, smooth=True)
    # pole tag
    r2 = lerp(0.152, 0.112, 2.5 / 9.5)
    box(pb, V(0.03 * math.sin(2.0 * 0.35), r2 + 0.004, 2.0), (0.08, 0.012, 0.11), 'RK_Alu')
    return pb


def speed_trap_camera():
    pb = PB('Speed_Trap_Camera', 33)
    R = pb.R
    box2(pb, V(-0.35, -0.35, -0.2), V(0.35, 0.35, 0.1), 'RK_Concrete', fcol=grime(R, -0.2, 0.1, 0.7, 0.95, 1.0))
    box2(pb, V(-0.21, -0.21, 0.1), V(0.21, 0.21, 0.13), 'RK_SteelGalv')
    zs = [0.12, 2.55, 2.75, 2.95, 3.15, 4.02]

    def sm(i, j):
        return 'RK_PaintOrange' if i in (1, 3) else 'RK_PoleGrey'
    tube(pb, [V(0, 0, z) for z in zs], [lerp(0.09, 0.075, (z - 0.12) / 3.9) for z in zs], 'RK_PoleGrey', sides=8,
         cap0=False, cap1=True, side_mat=sm, vfn=lambda i, j, p: (lerp(0.8, 1.0, min(1.0, p.z)),) * 3)
    box2(pb, V(-0.11, -0.12, 3.98), V(0.11, 0.25, 4.05), 'RK_PoleGrey')
    # camera housing (faces +Y)
    box2(pb, V(-0.2, -0.22, 4.05), V(0.2, 0.46, 4.47), 'RK_PaintWhite', fcol=clean(R, 0.94, 1.0))
    box2(pb, V(-0.205, -0.225, 4.12), V(0.205, 0.465, 4.19), 'RK_PaintTeal')
    box2(pb, V(-0.24, -0.25, 4.47), V(0.24, 0.57, 4.505), 'RK_PoleGrey')
    box2(pb, V(-0.15, 0.455, 4.2), V(0.15, 0.475, 4.43), 'RK_CameraGlass')
    tube(pb, [V(0, 0.46, 4.315), V(0, 0.5, 4.315)], [0.07, 0.07], 'RK_Black', sides=10, cap0=False, cap1=True,
         cap_mat='RK_CameraGlass', smooth=True)
    # flash unit on the side
    box2(pb, V(0.195, 0.12, 4.16), V(0.36, 0.36, 4.38), 'RK_PoleGrey')
    box2(pb, V(0.215, 0.355, 4.19), V(0.34, 0.372, 4.35), 'RK_FlashLens')
    # orange festival light bar under the camera, facing the traffic
    box2(pb, V(-0.06, 0.0, 3.5), V(0.06, 0.08, 3.6), 'RK_PoleGrey')
    box2(pb, V(-0.56, 0.06, 3.47), V(0.56, 0.17, 3.63), 'RK_Black')
    for k in range(6):
        x0 = -0.525 + k * 0.178
        box2(pb, V(x0, 0.165, 3.49), V(x0 + 0.16, 0.19, 3.61), 'RK_LightBarOrange')
    return pb


# ------------------------------------------------------------------------------------------------------ linear pieces
def fence_wood():
    pb = PB('Fence_Wood', 41)
    R = pb.R
    c = 0.022
    oct_ = [(0.065, -0.065 + c), (0.065, 0.065 - c), (0.065 - c, 0.065), (-0.065 + c, 0.065), (-0.065, 0.065 - c),
            (-0.065, -0.065 + c), (-0.065 + c, -0.065), (0.065 - c, -0.065)]
    for x in (-2.0, 0.0, 2.0):
        a = R.uniform(-0.15, 0.15)
        lean = V(R.uniform(-0.012, 0.012), R.uniform(-0.012, 0.012), 0)
        top = 1.15 + R.uniform(-0.02, 0.02)
        rings = []
        for z in (-0.4, 0.05, 0.6):
            rings.append([V(x, 0, 0) + rot_z(a) @ V(u, v, 0) + V(0, 0, z) + lean * z for u, v in oct_])
        rings.append([V(x, 0, 0) + rot_z(a) @ V(u, v, 0) + V(0, 0, top + 0.35 * v) + lean * top for u, v in oct_])
        tint = R.uniform(0.85, 1.0)
        loft(pb, rings, 'RK_WoodFence',
             fcol=lambda cc, n, t=tint: (lambda k: (k, k * 0.98, k * 0.95))(
                 t * lerp(0.55, 1.0, smoothstep(-0.1, 0.5, cc.z)) * R.uniform(0.9, 1.0)))
    # split rails through the posts (ends hidden inside the posts)
    for z in (0.36, 0.70, 1.02):
        for x0, x1 in ((-2.0, 0.0), (0.0, 2.0)):
            zz0 = z + R.uniform(-0.02, 0.02)
            zz1 = z + R.uniform(-0.02, 0.02)
            prof = [(0.0, 0.05), (0.022, 0.02), (0.02, -0.045), (-0.02, -0.048), (-0.024, 0.018)]
            twist = R.uniform(-0.3, 0.3)
            p2 = rot2(prof, twist)
            sag = R.uniform(0.0, 0.02)
            rings = []
            for t in (0.0, 0.5, 1.0):
                xx = lerp(x0, x1, t)
                zc = lerp(zz0, zz1, t) - sag * math.sin(PI * t)
                rings.append([V(xx, u, zc + v) for u, v in p2])
            tint = R.uniform(0.85, 1.05)
            loft(pb, rings, 'RK_WoodFence', cap0=False, cap1=False,
                 fcol=lambda cc, n, t=tint: (lambda k: (k, k * 0.97, k * 0.93))(
                     t * (0.82 + 0.18 * max(0.0, n.z)) * R.uniform(0.92, 1.0)))
    return pb


def wall_stone():
    pb = PB('Wall_Stone', 42)
    R = pb.R
    L = 2.0
    zb, ztop = -0.25, 0.8

    def yf(z):
        return 0.30 - 0.1375 * z
    core = [(-yf(zb), zb), (yf(zb), zb), (yf(ztop), ztop), (-yf(ztop), ztop)]
    extrude(pb, core, lambda u, v, d: V(d, u, v), -L, L, 'RK_StoneGap', cap_mats=('RK_Stone', 'RK_Stone'),
            fcol=lambda c, n: (0.62, 0.6, 0.57) if abs(n.x) > 0.9 else (1.0, 1.0, 1.0))
    courses = [(-0.14, 0.13), (0.13, 0.33), (0.33, 0.50), (0.50, 0.65), (0.65, 0.79)]
    gap = 0.013
    for side in (1, -1):
        nrm = V(0, side, 0.1375).normalized()
        x = -L
        for ci, (za, zb_) in enumerate(courses):
            lmin, lmax = (0.38, 0.62) if ci < 2 else (0.26, 0.46)
            x = -L - R.uniform(0.0, lmax * 0.8)
            while x < L:
                ln = R.uniform(lmin, lmax)
                xa, xb = max(x, -L), min(x + ln, L)
                x += ln
                if xb - xa < 0.08:
                    continue
                ex = 0.0 if xa <= -L + 1e-6 else gap
                ex2 = 0.0 if xb >= L - 1e-6 else gap
                q = [(xa + ex + R.uniform(0, 0.025) * (ex > 0), za + gap + R.uniform(-0.006, 0.01)),
                     (xb - ex2 - R.uniform(0, 0.025) * (ex2 > 0), za + gap + R.uniform(-0.006, 0.01)),
                     (xb - ex2 - R.uniform(0, 0.02) * (ex2 > 0), zb_ - gap - R.uniform(-0.004, 0.012)),
                     (xa + ex + R.uniform(0, 0.02) * (ex > 0), zb_ - gap - R.uniform(-0.004, 0.012))]
                pts = [V(qx, side * (yf(qz) + 0.012), qz) for qx, qz in q]
                cx = sum(qx for qx, qz in q) / 4 + R.uniform(-0.05, 0.05) * (xb - xa)
                cz = sum(qz for qx, qz in q) / 4 + R.uniform(-0.2, 0.2) * (zb_ - za)
                bulge = R.uniform(0.035, 0.065)
                cen = V(cx, side * yf(cz), cz) + nrm * bulge
                verts = pts + [cen]
                faces = [(i, (i + 1) % 4, 4) for i in range(4)]
                k = R.uniform(0.72, 1.08)
                warm = R.uniform(-0.05, 0.05)
                moss = 0.12 if R.random() < 0.18 else 0.0
                base = (k * (1 + warm) * (1 - moss), k * (1 + moss * 0.6), k * (1 - warm) * (1 - moss * 1.2))
                dk = lerp(0.68, 1.0, smoothstep(-0.15, 0.35, cz))

                def fc(c, n, b=base, d=dk):
                    f = 0.92 + 0.1 * R.random()
                    return (b[0] * d * f, b[1] * d * f, b[2] * d * f)
                pb.add(verts, faces, 'RK_Stone', fcol=fc, hint=nrm)
    # cock-and-hen coping on edge along the top
    x = -L
    tall = True
    while x < L - 0.05:
        w = R.uniform(0.12, 0.19)
        xa, xb = x, min(x + w, L)
        x += w + R.uniform(0.0, 0.012)
        h = R.uniform(0.17, 0.22) if tall else R.uniform(0.12, 0.16)
        tall = not tall if R.random() < 0.85 else tall
        dy = R.uniform(0.2, 0.24)
        lean = R.uniform(-0.03, 0.03)
        z0 = ztop - 0.03
        jt = [R.uniform(-0.012, 0.012) for _ in range(8)]
        pts = [V(xa, -dy, z0), V(xb, -dy, z0), V(xb, dy, z0), V(xa, dy, z0),
               V(xa + lean + jt[0], -dy + 0.02, z0 + h + jt[4]), V(xb + lean + jt[1], -dy + 0.02, z0 + h + jt[5]),
               V(xb + lean + jt[2], dy - 0.02, z0 + h + jt[6]), V(xa + lean + jt[3], dy - 0.02, z0 + h + jt[7])]
        k = R.uniform(0.75, 1.05)
        hexa(pb, pts, 'RK_Stone', fcol=lambda c, n, k=k: (k * (0.95 + 0.08 * max(0.0, n.z)),) * 3)
    return pb


def hedge():
    pb = PB('Hedge', 43)
    R = pb.R
    prof = [(0.50, -0.12), (0.545, 0.35), (0.525, 0.82), (0.47, 1.2), (0.33, 1.48), (0.0, 1.6), (-0.33, 1.48),
            (-0.47, 1.2), (-0.525, 0.82), (-0.545, 0.35), (-0.50, -0.12)]
    NX = 14
    off, off2 = rv(R), rv(R)
    rings = []
    for i in range(NX + 1):
        x = lerp(-1.98, 1.98, i / NX) + (R.uniform(-0.06, 0.06) if 0 < i < NX else 0.0)
        ring = []
        for j, (y, z) in enumerate(prof):
            p = V(x, y, z)
            if z > 0.0:
                c = V(0, 0, 0.75)
                d = V(0, p.y, p.z - c.z)
                d = d.normalized() if d.length > 1e-6 else V(0, 0, 1)
                amp = 0.1 * noise.noise(p * 1.5 + off) + 0.065 * noise.noise(p * 3.4 + off2) + R.uniform(-0.03, 0.04)
                p = p + d * amp + V(R.uniform(-0.04, 0.04), R.uniform(-0.02, 0.02), R.uniform(-0.03, 0.03))
                p.z = min(p.z, 1.6)
            ring.append(p)
        rings.append(ring)
    n = len(prof)
    verts = [p for r in rings for p in r]
    faces = []
    for i in range(NX):
        for j in range(n - 1):
            faces.append((i * n + j, i * n + j + 1, (i + 1) * n + j + 1, (i + 1) * n + j))
    for e, s in ((0, -1), (NX, 1)):
        c = V(s * 2.11, R.uniform(-0.05, 0.05), 0.72)
        verts.append(c)
        ci = len(verts) - 1
        for j in range(n - 1):
            faces.append((ci, e * n + j, e * n + j + 1))
        faces.append((ci, e * n + n - 1, e * n))
    def leaf(c, nn):
        h = smoothstep(-0.1, 1.5, c.z)
        k = lerp(0.52, 1.0, h) * R.uniform(0.8, 1.12) * (1.0 + 0.2 * min(0.0, nn.z))
        y = max(0.0, nn.z) * 0.1 + (0.08 if R.random() < 0.12 else 0.0)
        return (k * (1 + y), k * (1 + 0.6 * y), k * (1 - 0.3 * y))

    def outward(cc):
        d = V(cc.x - max(-1.9, min(1.9, cc.x)), cc.y, cc.z - 0.7)
        return d
    pb.add(verts, faces, 'RK_Hedge_Leaf', fcol=leaf, hint=outward)
    # leafy clumps breaking the clipped silhouette (top edges, top and both faces)
    spots = []
    for k in range(5):
        x = lerp(-1.75, 1.75, (k + R.uniform(0.15, 0.85)) / 5)
        spots.append(V(x, R.choice((-1, 1)) * 0.36, 1.42))
    for k in range(3):
        x = lerp(-1.6, 1.6, (k + R.uniform(0.15, 0.85)) / 3)
        spots.append(V(x, R.uniform(-0.15, 0.15), 1.52))
    for k in range(6):
        x = lerp(-1.75, 1.75, (k + R.uniform(0.1, 0.9)) / 6)
        spots.append(V(x, (1 if k % 2 else -1) * 0.46, R.uniform(0.45, 1.15)))
    for c in spots:
        r = R.uniform(0.17, 0.26)
        out = V(0, c.y, c.z - 0.75).normalized()
        c = c + out * r * 0.25
        c.z = min(c.z, 1.6 - r * 0.85)
        tint = R.uniform(1.0, 1.18)
        blob(pb, c, (r * 1.4, r * 0.9, r * 0.75), 'RK_Hedge_Leaf', sub=0, amp=0.2, squash=0.15,
             fcol=lambda cc, nn, t=tint: (lambda k: (k * 1.06, k * 1.05, k * 0.88))(
                 t * R.uniform(0.9, 1.05) * lerp(0.7, 1.0, smoothstep(0.2, 1.5, cc.z)) *
                 (1.0 + 0.15 * max(0.0, nn.z))))
    return pb


def barrier_jersey():
    pb = PB('Barrier_Jersey', 44)
    R = pb.R
    full = [(0.305, -0.05), (0.305, 0.075), (0.18, 0.33), (0.075, 0.81), (-0.075, 0.81), (-0.18, 0.33),
            (-0.305, 0.075), (-0.305, -0.05)]
    slot = [(0.293, 0.1), (0.18, 0.33), (0.075, 0.81), (-0.075, 0.81), (-0.18, 0.33), (-0.293, 0.1)]
    tint = R.uniform(0.95, 1.02)

    def vfn(p):
        k = tint * lerp(0.62, 1.0, smoothstep(-0.05, 0.4, p.z)) * (0.94 + 0.08 * noise.noise(p * 2.3))
        return (k, k * 0.99, k * 0.96)
    for x0, x1, prof in ((-1.0, -0.62, full), (-0.62, -0.38, slot), (-0.38, 0.38, full), (0.38, 0.62, slot),
                         (0.62, 1.0, full)):
        extrude(pb, prof, lambda u, v, d: V(d, u, v), x0, x1, 'RK_Concrete', vfn=vfn)
    for x in (-0.55, 0.55):
        box2(pb, V(x - 0.04, -0.012, 0.8), V(x + 0.04, 0.012, 0.85), 'RK_SteelGalv', fcol=flat(0.7))
    return pb


# ------------------------------------------------------------------------------------------------------ furniture
def bench():
    pb = PB('Bench', 51)
    R = pb.R
    bars = [((0.26, 0.0), (0.24, 0.43)), ((-0.25, 0.0), (-0.19, 0.42)), ((0.29, 0.415), (-0.23, 0.395)),
            ((-0.2, 0.37), (-0.31, 0.9)), ((-0.26, 0.66), (0.31, 0.645)), ((0.27, 0.42), (0.29, 0.655))]
    for x in (-0.78, 0.78):
        for (y0, z0), (y1, z1) in bars:
            tube(pb, [V(x, y0, z0), V(x, y1, z1)], [0.03, 0.03], 'RK_CastIron', sides=4, smooth=False, phase=PI / 4)
        box2(pb, V(x - 0.04, 0.2, -0.02), V(x + 0.04, 0.32, 0.02), 'RK_CastIron')
        box2(pb, V(x - 0.04, -0.31, -0.02), V(x + 0.04, -0.19, 0.02), 'RK_CastIron')

    def zr(y):
        return lerp(0.415, 0.395, (0.29 - y) / 0.52)
    for y in (0.2, 0.075, -0.05, -0.175):
        tint = R.uniform(0.88, 1.05)
        box(pb, V(0, y, zr(y) + 0.04), (1.82, 0.105, 0.034), 'RK_BenchWood', rot=rot_x(math.radians(-2.0)),
            fcol=lambda c, n, t=tint: (t * (0.85 + 0.15 * max(0.0, n.z)),) * 3)
    lean = math.atan2(0.11, 0.53)
    for s in (0.62, 0.79):
        y = lerp(-0.2, -0.31, (s - 0.37) / 0.53) + 0.034
        tint = R.uniform(0.88, 1.05)
        box(pb, V(0, y, s), (1.82, 0.034, 0.12), 'RK_BenchWood', rot=rot_x(lean),
            fcol=lambda c, n, t=tint: (t * (0.85 + 0.15 * max(0.0, n.y)),) * 3)
    return pb


def bus_stop():
    pb = PB('Bus_Stop', 52)
    R = pb.R
    box2(pb, V(-2.0, -1.0, -0.25), V(2.0, 1.0, 0.05), 'RK_Concrete',
         fcol=lambda c, n: (0.92 * R.uniform(0.95, 1.0),) * 3 if n.z > 0.5 else (0.7, 0.7, 0.68))
    fr = 'RK_ShelterFrame'
    for x in (-1.66, 1.66):
        for y in (-0.72, 0.62):
            box2(pb, V(x - 0.04, y - 0.04, 0.0), V(x + 0.04, y + 0.04, 2.44), fr, fcol=grime(R, 0, 0.6, 0.8))
        box2(pb, V(x - 0.03, -0.72, 2.29), V(x + 0.03, 0.62, 2.35), fr)
        box2(pb, V(x - 0.03, -0.72, 0.1), V(x + 0.03, 0.62, 0.16), fr)
    box2(pb, V(-1.66, -0.75, 2.29), V(1.66, -0.69, 2.35), fr)
    box2(pb, V(-1.66, -0.75, 0.1), V(1.66, -0.69, 0.16), fr)
    roof = [V(-1.85, -0.9, 2.42), V(1.85, -0.9, 2.42), V(1.85, 0.85, 2.48), V(-1.85, 0.85, 2.48),
            V(-1.85, -0.9, 2.5), V(1.85, -0.9, 2.5), V(1.85, 0.85, 2.56), V(-1.85, 0.85, 2.56)]
    hexa(pb, roof, 'RK_ShelterRoof', fcol=lambda c, n: (0.78, 0.78, 0.8) if n.z < -0.5 else (1.0, 1.0, 1.0))
    box2(pb, V(-1.87, 0.8, 2.4), V(1.87, 0.88, 2.62), 'RK_PaintTeal')
    # glass: back wall + right side; advertising light box on the left side
    box2(pb, V(-1.62, -0.726, 0.16), V(1.62, -0.714, 2.29), 'RK_Glass')
    box2(pb, V(1.654, -0.68, 0.16), V(1.666, 0.58, 2.29), 'RK_Glass')
    box2(pb, V(-1.73, -0.69, 0.15), V(-1.59, 0.59, 2.3), fr)
    for x in (-1.735, -1.585):
        box2(pb, V(x - 0.006, -0.6, 0.26), V(x + 0.006, 0.5, 2.19), 'RK_AdPanel')
    # perch bench
    box2(pb, V(-1.0, -0.66, 0.46), V(1.2, -0.38, 0.51), 'RK_BenchWood', fcol=clean(R, 0.9, 1.0))
    for x in (-0.8, 1.0):
        box2(pb, V(x - 0.025, -0.55, 0.05), V(x + 0.025, -0.49, 0.46), fr)
    # bus stop flag on its own pole (faces along the road, both sides)
    post_tube(pb, 2.2, 0.75, -0.3, 2.3, r=0.035, cap_top=False)
    F = SignFrame(V(2.2, 0.75, 2.52), N=(1, 0, 0))
    bands = [(0.0, 'RK_SignGreen'), (0.05, 'RK_SignWhite')]
    plate(pb, F, circle2(0.25, 20), -0.012, 0.012, bands, 'RK_SignGreen', back_bands=bands)
    return pb


def fuel_pump():
    pb = PB('Fuel_Pump', 53)
    R = pb.R
    isl = [(1.95, 0.35), (1.7, 0.6), (-1.7, 0.6), (-1.95, 0.35), (-1.95, -0.35), (-1.7, -0.6), (1.7, -0.6),
           (1.95, -0.35)]
    extrude(pb, isl, lambda u, v, d: V(u, v, d), -0.1, 0.18, 'RK_PaintYellow', cap_mats=('RK_Concrete', 'RK_Concrete'),
            fcol=lambda c, n: (0.95, 0.95, 0.92) if n.z > 0.5 else (0.9, 0.9, 0.9))
    for x in (-1.62, 1.62):
        tube(pb, [V(x, 0, 0.17), V(x, 0, 0.95)], [0.065, 0.065], 'RK_PaintYellow', sides=8, cap0=False, cap1=False,
             vfn=lambda i, j, p: (0.85 + 0.15 * i,) * 3)
        tube(pb, [V(x, 0, 0.95), V(x, 0, 0.97)], [0.067, 0.067], 'RK_Black', sides=8, cap0=False, cap1=True,
             tip=0.04)
    box2(pb, V(-0.5, -0.24, 0.18), V(0.5, 0.24, 1.85), 'RK_PaintWhite', fcol=clean(R, 0.95, 1.0))
    box2(pb, V(-0.51, -0.25, 0.18), V(0.51, 0.25, 0.36), 'RK_PumpDark')
    box2(pb, V(-0.53, -0.27, 1.85), V(0.53, 0.27, 2.15), 'RK_PaintTeal')
    box2(pb, V(-0.54, -0.28, 1.85), V(0.54, 0.28, 1.91), 'RK_PaintOrange')
    for s in (1, -1):
        box2(pb, V(-0.21, s * 0.235, 1.37), V(0.21, s * 0.255, 1.63), 'RK_PumpScreen')
        box2(pb, V(-0.13, s * 0.235, 1.14), V(0.13, s * 0.255, 1.3), 'RK_PumpDark')
        for bx, grip in ((-0.36, 'RK_NozzleGreen'), (0.36, 'RK_Black')):
            box2(pb, V(bx - 0.06, s * 0.23, 0.94), V(bx + 0.06, s * 0.31, 1.16), 'RK_PumpDark')
            box2(pb, V(bx - 0.03, s * 0.3, 0.99), V(bx + 0.03, s * 0.35, 1.2), grip)
            box2(pb, V(bx - 0.012, s * 0.27, 1.12), V(bx + 0.012, s * 0.31, 1.24), 'RK_SteelGalv')
            path = [V(bx * 1.2, s * 0.23, 1.72), V(bx * 1.25, s * 0.3, 1.64), V(bx * 1.3, s * 0.36, 1.3),
                    V(bx * 1.28, s * 0.39, 0.78), V(bx * 1.15, s * 0.385, 0.6), V(bx * 1.02, s * 0.36, 0.76),
                    V(bx, s * 0.33, 1.0)]
            tube(pb, path, [0.018] * len(path), 'RK_Black', sides=5, cap0=False, cap1=False)
    return pb


# ------------------------------------------------------------------------------------------------------ structures
def bridge_pier():
    pb = PB('Bridge_Pier', 61)
    R = pb.R
    box2(pb, V(-2.3, -1.6, -0.6), V(2.3, 1.6, 0.2), 'RK_Concrete', fcol=lambda c, n: (0.78, 0.77, 0.74))

    def octo(w, d, ch, z):
        hw, hd = w / 2, d / 2
        return [V(hw, -hd + ch, z), V(hw, hd - ch, z), V(hw - ch, hd, z), V(-hw + ch, hd, z), V(-hw, hd - ch, z),
                V(-hw, -hd + ch, z), V(-hw + ch, -hd, z), V(hw - ch, -hd, z)]
    rings = [octo(2.6, 1.5, 0.3, z) for z in (0.15, 0.7, 1.6, 4.0, 6.5, 8.0)]
    rings += [octo(7.4, 1.9, 0.15, 9.0), octo(7.4, 1.9, 0.15, 9.75)]
    off = rv(R)

    def vfn(p):
        k = lerp(0.66, 1.0, smoothstep(0.1, 1.8, p.z))
        k *= lerp(1.0, 0.82, smoothstep(6.8, 8.3, p.z) * (1.0 - smoothstep(8.6, 9.0, p.z)))
        k *= 0.93 + 0.1 * noise.noise(V(p.x * 0.9, p.y * 0.9, p.z * 0.12) + off)
        return (k, k * 0.99, k * 0.965)
    loft(pb, rings, 'RK_Concrete', vfn=vfn)
    for x in (-2.5, 2.5):
        box2(pb, V(x - 0.4, -0.4, 9.74), V(x + 0.4, 0.4, 9.85), 'RK_ConcreteLight')
        box2(pb, V(x - 0.27, -0.27, 9.85), V(x + 0.27, 0.27, 10.0), 'RK_Rubber')
    return pb


def tunnel_portal():
    pb = PB('Tunnel_Portal', 62)
    R = pb.R
    a, hs, cw = 4.75, 2.05, 0.6
    W, zb, zt = 8.0, -0.8, 9.6
    yb, yf, yc = -0.6, 0.4, 0.6
    off = rv(R)

    def vfn(p):
        k = 0.94 + 0.09 * noise.noise(V(p.x * 0.35, p.y * 0.35, p.z * 0.35) + off)
        k *= lerp(0.62, 1.0, smoothstep(-0.3, 1.3, p.z))
        d = math.hypot(p.x, (p.z - 6.6) * 1.3)
        soot = 1.0 - 0.38 * (1.0 - smoothstep(0.8, 4.6, d))
        if p.y < yc - 0.01 and abs(p.x) <= a + 0.01 and p.z < hs + a + 0.05:
            soot = min(soot, lerp(0.6, 0.85, smoothstep(yb, yc, p.y)))
        k *= soot
        k *= lerp(1.0, 0.86, smoothstep(8.4, 9.6, p.z))
        return (k, k * 0.99, k * 0.965)

    th_c = math.atan2(zt - hs, W)
    ths = sorted(set([round(PI * k / 18, 9) for k in range(19)] + [th_c, PI - th_c]), reverse=True)

    def arc(r, th):
        return (r * math.cos(th), hs + r * math.sin(th))

    def bound(th):
        c, s = math.cos(th), math.sin(th)
        t = 1e9
        if abs(c) > 1e-9:
            t = min(t, W / abs(c))
        if s > 1e-9:
            t = min(t, (zt - hs) / s)
        return (t * c, hs + t * s)

    def P(xz, y):
        return V(xz[0], y, xz[1])

    def mid(p, q, t=0.5):
        return (lerp(p[0], q[0], t), lerp(p[1], q[1], t))
    CON = 'RK_Concrete'
    FRONT, BACK = V(0, 1, 0), V(0, -1, 0)
    rows = [zb, 0.0, 1.0, hs]

    def strip(x0, x1, y, hint, xs_mid=()):
        xs = [x0] + list(xs_mid) + [x1]
        verts, faces = [], []
        for zi, z in enumerate(rows):
            for x in xs:
                verts.append(V(x, y, z))
        nx = len(xs)
        for zi in range(len(rows) - 1):
            for xi in range(nx - 1):
                faces.append((zi * nx + xi, zi * nx + xi + 1, (zi + 1) * nx + xi + 1, (zi + 1) * nx + xi))
        pb.add(verts, faces, CON, vfn=vfn, hint=hint)

    def ring_band(curveA, curveB, y, hint, steps=1):
        verts, faces = [], []
        m = len(ths)
        for t in range(steps + 1):
            for k in range(m):
                verts.append(P(mid(curveA[k], curveB[k], t / steps), y))
        for t in range(steps):
            for k in range(m - 1):
                faces.append((t * m + k, t * m + k + 1, (t + 1) * m + k + 1, (t + 1) * m + k))
        pb.add(verts, faces, CON, vfn=vfn, hint=hint)

    def sweep(curve, ys, hint):
        verts, faces = [], []
        m = len(curve)
        for y in ys:
            for k in range(m):
                verts.append(P(curve[k], y))
        for t in range(len(ys) - 1):
            for k in range(m - 1):
                faces.append((t * m + k, t * m + k + 1, (t + 1) * m + k + 1, (t + 1) * m + k))
        pb.add(verts, faces, CON, vfn=vfn, hint=hint)

    I_ = [arc(a, th) for th in ths]
    O_ = [arc(a + cw, th) for th in ths]
    B_ = [bound(th) for th in ths]
    # front wall (y = yf) around the collar, collar face (y = yc), collar outer step, intrados, back face (y = yb)
    ring_band(O_, B_, yf, FRONT, steps=2)
    xm = -(a + cw + W) / 2
    strip(-W, -(a + cw), yf, FRONT, (xm,))
    strip(a + cw, W, yf, FRONT, (-xm,))
    ring_band(I_, O_, yc, FRONT)
    strip(-(a + cw), -a, yc, FRONT)
    strip(a, a + cw, yc, FRONT)
    sweep(O_, (yf, yc), lambda c: V(c.x, 0, c.z - hs))
    for sx in (-1, 1):
        verts = [V(sx * (a + cw), y, z) for z in rows for y in (yf, yc)]
        faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(len(rows) - 1)]
        pb.add(verts, faces, CON, vfn=vfn, hint=V(sx, 0, 0))
    ysw = (yb, 0.0, yc)
    sweep(I_, ysw, lambda c: V(-c.x, 0, -(c.z - hs)))
    for sx in (-1, 1):
        verts = [V(sx * a, y, z) for z in rows for y in ysw]
        faces = [(3 * i + j, 3 * i + j + 1, 3 * (i + 1) + j + 1, 3 * (i + 1) + j) for i in range(len(rows) - 1)
                 for j in range(2)]
        pb.add(verts, faces, CON, vfn=vfn, hint=V(-sx, 0, 0))
    ring_band(I_, B_, yb, BACK, steps=2)
    xmb = -(a + W) / 2
    strip(-W, -a, yb, BACK, (xmb,))
    strip(a, W, yb, BACK, (-xmb,))
    # ends, top, bottom
    zs_end = sorted(set(round(z, 6) for z in rows + [b[1] for b in B_ if abs(abs(b[0]) - W) < 1e-6 and
                                                     hs + 1e-4 < b[1] < zt - 1e-4] + [zt]))
    for sx in (-1, 1):
        verts = [V(sx * W, y, z) for z in zs_end for y in (yb, yf)]
        faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(len(zs_end) - 1)]
        pb.add(verts, faces, CON, vfn=vfn, hint=V(sx, 0, 0))
    xs_top = sorted(set(round(x, 6) for x in [-W, W] + [b[0] for b in B_ if abs(b[1] - zt) < 1e-6]))
    verts = [V(x, y, zt) for x in xs_top for y in (yb, yf)]
    faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(len(xs_top) - 1)]
    pb.add(verts, faces, CON, vfn=vfn, hint=V(0, 0, 1))
    for sx in (-1, 1):
        poly = [(-W, yb), (xmb, yb), (-a, yb), (-a, 0.0), (-a, yc), (-(a + cw), yc), (-(a + cw), yf), (xm, yf),
                (-W, yf)]
        pb.add([V(sx * x, y, zb) for x, y in poly], [tuple(range(len(poly)))], CON, vfn=vfn, hint=V(0, 0, -1))
    # coping, pilasters, blank name plaque
    box2(pb, V(-W, yb, zt - 0.05), V(W, yf + 0.1, 10.0), 'RK_ConcreteLight',
         fcol=lambda c, n: (0.8, 0.8, 0.78) if n.z < -0.5 else (0.95, 0.95, 0.93))
    for sx in (-1, 1):
        box2(pb, V(min(sx * 7.2, sx * W), yf - 0.02, zb), V(max(sx * 7.2, sx * W), yf + 0.15, zt - 0.05), CON,
             vfn=vfn)
    box2(pb, V(-2.4, yf - 0.02, 7.75), V(2.4, yf + 0.08, 8.6), 'RK_ConcreteLight', fcol=flat(0.93))
    return pb


def checkpoint_arch():
    pb = PB('Checkpoint_Arch', 63)
    R = pb.R
    hw, top, rc, z0, rad = 6.4, 6.4, 1.8, 0.25, 0.6
    dense = []
    for k in range(60):
        dense.append(V(-hw, 0, lerp(z0, top - rc, k / 60)))
    for k in range(40):
        a = PI - (PI / 2) * k / 40
        dense.append(V(-hw + rc + rc * math.cos(a), 0, top - rc + rc * math.sin(a)))
    for k in range(80):
        dense.append(V(lerp(-hw + rc, hw - rc, k / 80), 0, top))
    for k in range(40):
        a = PI / 2 - (PI / 2) * k / 40
        dense.append(V(hw - rc + rc * math.cos(a), 0, top - rc + rc * math.sin(a)))
    for k in range(61):
        dense.append(V(hw, 0, lerp(top - rc, z0, k / 60)))
    cum = [0.0]
    for i in range(1, len(dense)):
        cum.append(cum[-1] + (dense[i] - dense[i - 1]).length)
    L = cum[-1]

    def at(s):
        for i in range(1, len(cum)):
            if cum[i] >= s:
                t = (s - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-9)
                return dense[i - 1].lerp(dense[i], t)
        return dense[-1].copy()
    S = 17
    PER = 4
    pts, radii, seg_of = [], [], []
    for k in range(S):
        for q in range(PER):
            f = q / PER
            pts.append(at(L * (k + f) / S))
            radii.append(rad * (0.86 + 0.14 * math.sin(PI * f)))
            seg_of.append(k)
    pts.append(at(L))
    radii.append(rad * 0.86)
    pal = ['RK_Inflatable_Orange', 'RK_Inflatable_Magenta', 'RK_Inflatable_Yellow', 'RK_Inflatable_Teal']

    def sm(i, j):
        k = seg_of[i]
        return pal[min(k, S - 1 - k) % 4]

    def vf(i, j, p):
        k = lerp(0.8, 1.0, smoothstep(0.2, 1.4, p.z))
        return (k, k, k)
    tube(pb, pts, radii, 'RK_Inflatable_Orange', sides=12, cap0=True, cap1=True, side_mat=sm, vfn=vf, smooth=True)
    for sx in (-1, 1):
        box2(pb, V(sx * hw - 0.75, -0.75, -0.03), V(sx * hw + 0.75, 0.75, 0.42), 'RK_FabricDark',
             fcol=lambda c, n: (0.8, 0.8, 0.8) if abs(n.z) < 0.5 else (1.0, 1.0, 1.0))
    F = SignFrame(V(0, 0, 5.35))
    bands = [(0.0, 'RK_PaintTeal'), (0.07, 'RK_BannerWhite')]
    plate(pb, F, rrect2(8.0, 1.3, 0.0), -0.025, 0.025, bands, 'RK_PaintTeal', back_bands=bands)
    return pb


def festival_banner():
    pb = PB('Festival_Banner', 64)
    R = pb.R
    tube(pb, [V(0, 0, -0.02), V(0, 0, 0.08)], [0.32, 0.32], 'RK_Rubber', sides=10, cap0=True, cap1=False,
         smooth=False)
    tube(pb, [V(0, 0, 0.08), V(0, 0, 0.16)], [0.32, 0.1], 'RK_Rubber', sides=10, cap0=False, cap1=True, smooth=False)
    path = [V(0, 0, 0.12), V(0, 0, 1.0), V(0, 0, 2.0), V(0, 0, 2.95), V(0.02, 0, 3.3), V(0.1, 0, 3.6),
            V(0.24, 0, 3.83), V(0.42, 0, 3.96), V(0.62, 0, 4.0)]
    tube(pb, path, [lerp(0.021, 0.012, i / (len(path) - 1)) for i in range(len(path))], 'RK_Alu', sides=6,
         cap0=False, cap1=True)
    # hoist curve = pole above z 1.05, fly edge runs down from the tip
    dense = []
    for i in range(len(path) - 1):
        for k in range(10):
            dense.append(path[i].lerp(path[i + 1], k / 10))
    dense.append(path[-1])
    dense = [p for p in dense if p.z >= 1.05]
    cum = [0.0]
    for i in range(1, len(dense)):
        cum.append(cum[-1] + (dense[i] - dense[i - 1]).length)

    def hoist(u):
        s = u * cum[-1]
        for i in range(1, len(cum)):
            if cum[i] >= s:
                t = (s - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-9)
                return dense[i - 1].lerp(dense[i], t)
        return dense[-1].copy()

    def fly(u):
        z = lerp(1.32, 3.86, u)
        x = 0.6 + 0.035 * math.sin(PI * u)
        return V(x, 0, z)
    NR, NC = 10, 4
    verts = []
    for i in range(NR):
        u = i / NR
        for j in range(NC + 1):
            v = j / NC
            p = hoist(u).lerp(fly(u), v)
            p.y += 0.07 * v * math.sin(2 * PI * (v * 0.9 + u * 1.3))
            verts.append(p)
    verts.append(path[-1].copy())
    tipi = len(verts) - 1
    faces, mats = [], []

    def mat_of(i, j):
        if j == 0:
            return 'RK_Flag_Teal'
        if i <= 1:
            return 'RK_Flag_Magenta'
        return 'RK_Flag_Orange'
    for i in range(NR):
        for j in range(NC):
            a0 = i * (NC + 1) + j
            if i < NR - 1:
                faces.append((a0, a0 + 1, a0 + NC + 2, a0 + NC + 1))
            else:
                faces.append((a0, a0 + 1, tipi))
            mats.append(mat_of(i, j))
    pb.add(verts, faces, mats, smooth=True, fcol=(0.97, 0.97, 0.97), hint=V(0, 1, 0))
    return pb


def flag_pole():
    pb = PB('Flag_Pole', 65)
    R = pb.R
    box2(pb, V(-0.35, -0.35, -0.15), V(0.35, 0.35, 0.2), 'RK_Concrete', fcol=grime(R, -0.15, 0.2, 0.75, 0.95, 1.0))
    tube(pb, [V(0, 0, 0.19), V(0, 0, 0.32)], [0.095, 0.085], 'RK_Alu', sides=8, cap0=False, cap1=True,
         smooth=False)
    tube(pb, [V(0, 0, 0.3), V(0, 0, 4.0), V(0, 0, 7.86)], [0.065, 0.055, 0.042], 'RK_Alu', sides=8, cap0=False,
         cap1=True)
    tube(pb, [V(0, 0, 7.83), V(0, 0, 7.88)], [0.055, 0.055], 'RK_Alu', sides=8, smooth=False)
    sphere(pb, V(0, 0, 7.94), 0.065, 'RK_Gold', seg=8, rings=5)
    # waving flag: 2.4 x 1.5 m, orange field with a teal hoist triangle (cells split along the triangle edges)
    Wf, Hf, x0, z0 = 2.4, 1.5, 0.04, 6.22
    NC, NR, K = 8, 6, 3
    cw, ch = Wf / NC, Hf / NR

    def pos(c, r):
        x = c * cw
        z = r * ch
        t = x / Wf
        y = 0.17 * (t ** 0.85) * math.sin(2 * PI * (x / 1.35) - 0.5 + 0.35 * z) + 0.025 * t * math.sin(5.0 * z)
        return V(x0 + x, y, z0 + z - 0.07 * t * t - 0.02 * t * math.sin(PI * z / Hf))
    verts = [pos(c, r) for r in range(NR + 1) for c in range(NC + 1)]

    def vi(c, r):
        return r * (NC + 1) + c
    faces, mats = [], []
    for r in range(NR):
        for c in range(NC):
            BL, BR, TR, TL = vi(c, r), vi(c + 1, r), vi(c + 1, r + 1), vi(c, r + 1)
            if c >= K:
                faces.append((BL, BR, TR, TL))
                mats.append('RK_Flag_Orange')
                continue
            lower = r < NR // 2
            rr = r if lower else NR - 1 - r
            if rr > c:
                faces.append((BL, BR, TR, TL))
                mats.append('RK_Flag_Teal')
            elif rr < c:
                faces.append((BL, BR, TR, TL))
                mats.append('RK_Flag_Orange')
            elif lower:
                faces += [(BL, TR, TL), (BL, BR, TR)]
                mats += ['RK_Flag_Teal', 'RK_Flag_Orange']
            else:
                faces += [(BL, BR, TL), (BR, TR, TL)]
                mats += ['RK_Flag_Teal', 'RK_Flag_Orange']
    pb.add(verts, faces, mats, smooth=True, fcol=(0.97, 0.97, 0.97), hint=V(0, 1, 0))
    return pb


def billboard():
    pb = PB('Billboard', 66)
    R = pb.R
    st = 'RK_PoleGrey'
    for x in (-2.6, 2.6):
        box2(pb, V(x - 0.45, -0.85, -0.25), V(x + 0.45, 0.05, 0.2), 'RK_Concrete',
             fcol=grime(R, -0.25, 0.2, 0.7, 0.95, 1.0))
        tube(pb, [V(x, -0.4, 0.18), V(x, -0.4, 3.0), V(x, -0.4, 6.6)], [0.17, 0.165, 0.16], st, sides=8, cap0=False,
             cap1=True, vfn=lambda i, j, p: (lerp(0.8, 1.0, min(1.0, p.z / 2.0)),) * 3)
        box2(pb, V(x - 0.25, -0.65, 0.17), V(x + 0.25, -0.15, 0.22), st)
    for z in (3.55, 6.35):
        box2(pb, V(-3.9, -0.3, z - 0.08), V(3.9, -0.12, z + 0.08), st)
    for x in (-3.0, -1.0, 1.0, 3.0):
        box2(pb, V(x - 0.05, -0.22, 3.05), V(x + 0.05, -0.12, 6.95), st)
    # panel: 8 x 4 m visible face, UV 0..1 from the viewer's left (+X) to right, bottom to top
    box2(pb, V(-4.0, -0.13, 3.0), V(4.0, -0.012, 7.0), 'RK_PoleGrey', fcol=flat(0.85))
    face = [V(4.0, 0.0, 3.0), V(-4.0, 0.0, 3.0), V(-4.0, 0.0, 7.0), V(4.0, 0.0, 7.0)]
    pb.add(face, [(0, 1, 2, 3)], 'BillboardPanel', hint=V(0, 1, 0),
           uvfn=lambda co: ((4.0 - co.x) / 8.0, (co.z - 3.0) / 4.0))
    fr = 'RK_PaintWhite'
    box2(pb, V(-4.14, -0.14, 6.99), V(4.14, 0.04, 7.13), fr)
    box2(pb, V(-4.14, -0.14, 2.8), V(4.14, 0.04, 3.01), fr)
    for sx in (-1, 1):
        box2(pb, V(min(sx * 3.99, sx * 4.14), -0.14, 3.0), V(max(sx * 3.99, sx * 4.14), 0.04, 7.0), fr)
    # catwalk
    box2(pb, V(-4.0, 0.04, 2.74), V(4.0, 0.74, 2.8), st, fcol=lambda c, n: (0.7, 0.7, 0.7) if n.z > 0.5 else
         (0.85, 0.85, 0.85))
    for x in (-3.0, 0.0, 3.0):
        box2(pb, V(x - 0.03, -0.12, 2.66), V(x + 0.03, 0.72, 2.74), st)
    # floodlights on goosenecks above the panel
    for x in (-2.7, 0.0, 2.7):
        tube(pb, [V(x, -0.07, 7.1), V(x, -0.05, 7.4), V(x, 0.3, 7.55), V(x, 0.72, 7.5)], [0.035] * 4, st, sides=5,
             cap0=False, cap1=False)
        head = rot_x(math.radians(-35.0))
        box(pb, V(x, 0.8, 7.47), (0.36, 0.22, 0.12), st, rot=head)
        box(pb, V(x, 0.8, 7.47) + head @ V(0, 0, -0.065), (0.3, 0.17, 0.012), 'RK_FloodLens', rot=head)
    return pb


BUILDERS = {
    'Sign_SpeedLimit': sign_speedlimit, 'Sign_Chevron': sign_chevron, 'Sign_Danger_Jump': sign_danger_jump,
    'Sign_Direction': sign_direction, 'Delineator_Post': delineator_post, 'GuardRail_Post': guardrail_post,
    'Lamp_Street': lamp_street, 'Utility_Pole': utility_pole, 'Fence_Wood': fence_wood, 'Wall_Stone': wall_stone,
    'Hedge': hedge, 'Bus_Stop': bus_stop, 'Bench': bench, 'Mailbox': mailbox, 'Bin': bin_,
    'Barrier_Jersey': barrier_jersey, 'Cone': cone, 'Bridge_Pier': bridge_pier, 'Tunnel_Portal': tunnel_portal,
    'Speed_Trap_Camera': speed_trap_camera, 'Checkpoint_Arch': checkpoint_arch, 'Festival_Banner': festival_banner,
    'Flag_Pole': flag_pole, 'Fuel_Pump': fuel_pump, 'Billboard': billboard,
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
    roadside = ensure_child('Roadside', root)
    return ensure_child(KIT, roadside)


def remove_object(ob):
    me = ob.data if ob.type == 'MESH' else None
    bpy.data.objects.remove(ob, do_unlink=True)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)


def finish(pb, coll):
    old = bpy.data.objects.get(pb.name)
    if old is not None:
        if old.name not in coll.objects and old.users_collection:
            raise RuntimeError('object %s exists outside %s: %s' % (pb.name, KIT, [c.name for c in old.users_collection]))
        remove_object(old)
    oldme = bpy.data.meshes.get(pb.name)
    if oldme is not None and oldme.users == 0:
        bpy.data.meshes.remove(oldme)
    bm = pb.bm
    uv = bm.loops.layers.uv.new('UVMap')
    over = {}
    for f, fn in pb.uvo:
        over[f] = fn
    for f in bm.faces:
        fn = over.get(f)
        if fn is not None:
            for lp in f.loops:
                lp[uv].uv = fn(lp.vert.co)
            continue
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
    for m in ('LampLens', 'BillboardPanel'):
        mat = bpy.data.materials.get(m)
        if mat is not None:
            users = [o.name for o in bpy.data.objects if o.type == 'MESH' and mat.name in [s.name for s in o.data.materials if s]]
            if any(u not in NAMES for u in users):
                raise RuntimeError('material %s is used outside the kit: %s' % (m, users))
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


def budget_of(name):
    return next(v for k, v in BUDGET.items() if name.startswith(k))


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
        # sample points: vertices, face centres and points along long edges (catches long overlapping members)
        samp = list(vco)
        seen_e = set()
        for f in comp:
            samp.append(f.calc_center_median().copy())
            for e in f.edges:
                if e.index in seen_e:
                    continue
                seen_e.add(e.index)
                a, b = e.verts[0].co, e.verts[1].co
                k = int((b - a).length / 0.2)
                for t in range(1, k):
                    samp.append(a.lerp(b, t / k))
        step = max(1, len(samp) // 400)
        info.append(dict(bvh=BVHTree.FromPolygons(vco, polys), pts=samp[::step], closed=closed, vol=vol, mn=mn,
                         mx=mx))
    degen = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    bm.free()
    n = len(info)
    parent = list(range(n + 1))

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
            if not hit:
                for p in B['pts']:
                    r = A['bvh'].find_nearest(p)
                    if r[0] is not None and r[3] <= tol:
                        hit = True
                        break
            if not hit:
                hit = len(A['bvh'].overlap(B['bvh'])) > 0
            if not hit and B['closed']:
                hit = any(_inside(B['bvh'], p) for p in A['pts'][:40])
            if not hit and A['closed']:
                hit = any(_inside(A['bvh'], p) for p in B['pts'][:40])
            if hit:
                union(i, j)
    # repeat the union pass once so chains resolved late propagate
    floating = [i for i in range(n) if find(i) != find(n)]
    vs = [v.co for v in me.vertices]
    mn = Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs)))
    mx = Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs)))
    budget = budget_of(ob.name)
    return dict(name=ob.name, height=round(mx.z, 2), below=round(mn.z, 2), size_x=round(mx.x - mn.x, 2),
                size_y=round(mx.y - mn.y, 2), y_range=(round(mn.y, 3), round(mx.y, 3)), tris=tris, budget=budget,
                ok_budget=tris <= budget, mats=[m.name for m in me.materials], islands=n,
                open_islands=sum(1 for a in info if not a['closed']),
                inverted=sum(1 for a in info if a['closed'] and a['vol'] < 0), floating=len(floating),
                floating_at=[tuple(round(c, 2) for c in (info[i]['mn'] + info[i]['mx']) / 2) for i in floating[:5]],
                degenerate=degen, uv=len(me.uv_layers), col=[a.name for a in me.color_attributes],
                loc=tuple(round(c, 2) for c in ob.location),
                center_xy=(round((mn.x + mx.x) / 2, 2), round((mn.y + mx.y) / 2, 2)))


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
REF_COLL = '_QA_RoadsideRef'


def ref_on(only=None):
    col = bpy.data.collections.get(REF_COLL) or bpy.data.collections.new(REF_COLL)
    if col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    mat = bpy.data.materials.get('QA_RoadsideRefMat') or bpy.data.materials.new('QA_RoadsideRefMat')
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
    m = bpy.data.materials.get('QA_RoadsideRefMat')
    if m is not None and m.users == 0:
        bpy.data.materials.remove(m)
    return n


def focus(name, local, size=1.0):
    """'QA_Focus': 8 loose vertices (no faces, nothing is drawn) forming a size-m box around a point in the prop's
    local coordinates, so look() auto-frames that box for close-ups."""
    col = bpy.data.collections.get(REF_COLL) or bpy.data.collections.new(REF_COLL)
    if col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    old = bpy.data.objects.get('QA_Focus')
    if old is not None:
        remove_object(old)
    h = size / 2.0
    me = bpy.data.meshes.new('QA_Focus')
    me.from_pydata([(x, y, z) for x in (-h, h) for y in (-h, h) for z in (-h, h)], [], [])
    e = bpy.data.objects.new('QA_Focus', me)
    col.objects.link(e)
    e.location = bpy.data.objects[name].location + Vector(local)
    return tuple(e.location)


def _qa_others():
    out = list(kit_collection().objects) + list(getattr(bpy.data.collections.get(REF_COLL), 'objects', []))
    nat = bpy.data.collections.get('NatureKit')
    if nat is not None:
        out += list(nat.objects)
    return out


def solo(only):
    """Viewport-hide every other kit prop / scale ref (and the nature kit) so look() sees only the targets."""
    keep = set(only or [])
    keep |= {'QA_Ref1p8_' + n for n in keep}
    hidden = []
    for ob in _qa_others():
        h = ob.name not in keep
        ob.hide_set(h)
        if h:
            hidden.append(ob.name)
    return len(hidden)


def unsolo():
    n = 0
    for ob in _qa_others():
        if ob.hide_get():
            ob.hide_set(False)
            n += 1
    return n


# ------------------------------------------------------------------------------------------------------ contact sheet
def _qa_collection():
    col = bpy.data.collections.get('_QA')
    if col is None:
        col = bpy.data.collections.new('_QA')
        bpy.context.scene.collection.children.link(col)
        col.hide_viewport = True
    elif col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    return col


def _remove_any(o):
    data = o.data
    bpy.data.objects.remove(o, do_unlink=True)
    if data is not None and data.users == 0:
        if isinstance(data, bpy.types.Camera):
            bpy.data.cameras.remove(data)
        elif isinstance(data, bpy.types.Light):
            bpy.data.lights.remove(data)


VIEW = {'Tunnel_Portal': (0.42, 0.88, 0.22), 'Billboard': (0.45, 0.85, 0.2), 'Checkpoint_Arch': (0.4, 0.88, 0.25)}


def contact_sheet(tile=400, gap=4, cols=5, names=None):
    import numpy as np
    names = names or NAMES
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
    # everything else (player cars, traffic, nature kit, scale refs) stays out of the renders; restored below
    kit_names = {o.name for o in kit}
    others = {o.name: o.hide_render for o in sc.objects if o.name not in kit_names and o.name not in hidden_qa}
    for nm in others:
        sc.objects[nm].hide_render = True
    made = []
    os.makedirs(TILE_DIR, exist_ok=True)
    tiles = []
    stats = {d['name']: d for d in report()}
    try:
        qa.hide_viewport = False
        qa.hide_render = False
        if lc is not None:
            lc.hide_viewport = False
        world = bpy.data.worlds.new('QA_RoadsideWorld')
        try:
            world.use_nodes = True
        except Exception:
            pass
        bg = next((nd for nd in world.node_tree.nodes if nd.type == 'BACKGROUND'), None)
        if bg is not None:
            bg.inputs[0].default_value = (0.5, 0.62, 0.8, 1.0)
            bg.inputs[1].default_value = 0.85
        gm = bpy.data.meshes.new('QA_RoadsideGround')
        gbm = bmesh.new()
        bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=250.0)
        gbm.to_mesh(gm)
        gbm.free()
        gmat = bpy.data.materials.new('QA_RoadsideGroundMat')
        gmat.diffuse_color = (0.25, 0.25, 0.22, 1.0)
        try:
            gmat.use_nodes = True
            b = next(nd for nd in gmat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
            _sock(b, 'Base Color').default_value = (0.2, 0.2, 0.17, 1.0)
            _sock(b, 'Roughness').default_value = 0.95
        except Exception:
            pass
        gm.materials.append(gmat)
        ground = bpy.data.objects.new('QA_RoadsideGround', gm)
        ground.location = (110.0, 135.0, -0.002)
        qa.objects.link(ground)
        made.append(ground)
        cam = bpy.data.objects.new('QA_RoadsideCam', bpy.data.cameras.new('QA_RoadsideCam'))
        cam.data.lens = 50.0
        cam.data.clip_end = 1000.0
        qa.objects.link(cam)
        made.append(cam)
        sun = bpy.data.objects.new('QA_RoadsideSun', bpy.data.lights.new('QA_RoadsideSun', 'SUN'))
        sun.data.energy = 4.0
        try:
            sun.data.angle = math.radians(3.0)
        except Exception:
            pass
        Ls = Vector((-0.35, 0.75, 0.62)).normalized()
        sun.rotation_euler = Ls.to_track_quat('Z', 'Y').to_euler()
        qa.objects.link(sun)
        made.append(sun)
        refmat = bpy.data.materials.new('QA_RoadsideRefMat2')
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
            rbm = bmesh.new()
            bmesh.ops.create_cone(rbm, cap_ends=True, segments=10, radius1=0.2, radius2=0.16, depth=1.8,
                                  matrix=Matrix.Translation((0, 0, 0.9)))
            rme = bpy.data.meshes.new('QA_RoadsideRef')
            rbm.to_mesh(rme)
            rbm.free()
            rme.materials.append(refmat)
            ref = bpy.data.objects.new('QA_RoadsideRef', rme)
            # reference on the far-left side of the prop (away from the camera) so it never hides small props
            ref.location = (mn.x - 0.45, (mn.y + mx.y) / 2 - 0.25, 0.0)
            qa.objects.link(ref)
            mn.x -= 0.7
            mn.y = min(mn.y, (mn.y + mx.y) / 2 - 0.5)
            mx.z = max(mx.z, 1.8)
            c = (mn + mx) / 2
            rad = (mx - mn).length / 2
            view = Vector(VIEW.get(name, (0.5, 0.82, 0.32))).normalized()
            dist = rad / math.sin(fov / 2) * 1.02
            cam.location = c + view * dist
            cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
            cam.data.clip_start = max(0.01, dist * 0.02)
            st = stats.get(name, {})
            r.stamp_note_text = '%s   h %.2f m   %d tris' % (name, st.get('height', mx.z), st.get('tris', 0))
            png = os.path.join(TILE_DIR, name + '.png')
            r.filepath = png
            bpy.ops.render.render(write_still=True)
            tiles.append((name, png))
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
        out = bpy.data.images.new('QA_RoadsideSheet', W, H, alpha=False)
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
        o = bpy.data.objects.get('QA_RoadsideRef')
        if o is not None:
            remove_object(o)
        for nm, hr in hidden_qa.items():
            if bpy.data.objects.get(nm):
                bpy.data.objects[nm].hide_render = hr
        for nm, hr in others.items():
            if bpy.data.objects.get(nm):
                bpy.data.objects[nm].hide_render = hr
        qa.hide_viewport = saved['qa_hv']
        qa.hide_render = saved['qa_hr']
        if lc is not None:
            lc.hide_viewport = saved['lc_hv']
        for coll, nm in ((bpy.data.worlds, 'QA_RoadsideWorld'), (bpy.data.materials, 'QA_RoadsideGroundMat'),
                         (bpy.data.materials, 'QA_RoadsideRefMat2'), (bpy.data.cameras, 'QA_RoadsideCam'),
                         (bpy.data.lights, 'QA_RoadsideSun')):
            d = coll.get(nm)
            if d is not None and d.users == 0:
                coll.remove(d)
    return SHEET_PATH, [t[0] for t in tiles]


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
    hidden = [o for o in obs if o.hide_get()]
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    try:
        for o in hidden:
            o.hide_set(False)
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
        for o in hidden:
            o.hide_set(True)
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

        def rng(axis, f):
            return f(acc[p['attributes']['POSITION']][('min' if f is min else 'max')][axis] for p in prims)
        bb = [(round(rng(a, min), 2), round(rng(a, max), 2)) for a in range(3)] if prims else None
        tri = sum(acc[p['indices']]['count'] // 3 for p in prims if 'indices' in p)
        per.append(dict(name=nd.get('name'), mesh=m.get('name') if m else None, prims=len(prims),
                        children=len(nd.get('children', [])),
                        transform=[k for k in ('translation', 'rotation', 'scale', 'matrix') if k in nd],
                        bbox_godot=bb, tris=tri, attrs=sorted({a for p in prims for a in p['attributes']})))
    names = [p['name'] for p in per]
    mat_named = {m['name']: m for m in mats}
    return dict(magic=magic.decode(), version=version, bytes=len(raw), chunk=ctype.decode(), n_top=len(top),
                names_ok=sorted(names) == sorted(NAMES) and len(names) == len(set(names)),
                missing=[n for n in NAMES if n not in names], extra=[n for n in names if n not in NAMES],
                n_nodes=len(nodes), n_meshes=len(meshes), n_materials=len(mats), cameras=len(js.get('cameras', [])),
                animations=len(js.get('animations', [])),
                lights='KHR_lights_punctual' in js.get('extensionsUsed', []), extensions=js.get('extensionsUsed', []),
                double_sided=sorted(m['name'] for m in mats if m.get('doubleSided')),
                alpha=sorted(m['name'] for m in mats if m.get('alphaMode', 'OPAQUE') != 'OPAQUE'),
                emissive=sorted(m['name'] for m in mats if any(c > 0 for c in m.get('emissiveFactor', [0, 0, 0]))),
                lamp_lens=mat_named.get('LampLens', {}).get('emissiveFactor'),
                billboard_panel='BillboardPanel' in mat_named,
                mat_factors={m['name']: [round(c, 3) for c in m.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])[:3]]
                             for m in mats if m['name'] in ('RK_SignRed', 'RK_SignYellow', 'LampLens', 'BillboardPanel')},
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
    elif STEP_ == 'focus':
        print('focus', focus(ONLY_[0], globals().get('AT', (0, 0, 0)), globals().get('SIZE', 1.0)))
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
