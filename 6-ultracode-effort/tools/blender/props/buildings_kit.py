"""Sunward Roads - BUILDINGS + LANDMARKS kit (Blender side, fully procedural bpy/bmesh).

Builds the collection SUNWARD_GODOT/Settlements/BuildingsKit with one joined mesh object per prop (exact names from
docs/SYSTEM_CONTRACTS.md "Props"):

  House_Cottage_A, House_Cottage_B, House_Townhouse, Farmhouse, Barn_Red, Silo, Shed_Small, House_Chalet, House_Adobe,
  Gas_Station, Diner, Church, Harbour_Shed, Boathouse, Pier_Section, Boat_Fishing, Lighthouse, Castle_Ruin_Wall,
  Castle_Ruin_Tower, Wind_Turbine_Tower, Wind_Turbine_Rotor, Water_Tower, Festival_Stage, Festival_Tent, Viewpoint_Deck

This file is the core (materials, mesh builder, building parts, QA, contact sheet, export). The props themselves are
modelled in two sub-scripts that are exec'd into this namespace:
  buildings_kit_houses.py     houses, farm buildings, commercial, church, harbour buildings
  buildings_kit_landmarks.py  pier, boat, lighthouse, castle ruins, wind turbine, water tower, festival, viewpoint

Axes / placement contract (Blender -> Godot: +Y -> -Z, +Z -> +Y):
  * Origin at the base centre on the ground (Blender Z = 0), front door facing Blender +Y (= Godot -Z).
    Buildings carry a foundation reaching 2.5 m below the origin (like the Godot placeholders) so they sit on slopes.
  * Pier_Section: 10 m along Y (y = -5..+5, tiles end to end), origin at the deck surface centre (deck top = Z 0).
  * Boat_Fishing: 7 m, bow +Y, origin at the waterline (Z 0 = waterline).
  * Lighthouse: origin on the tower axis; lamp-room glass (material "LampLens") centred at 0.86 x total height,
    matching scripts/world/settlements.gd (beam pivot = bb.end.y * 0.86).
  * Wind_Turbine_Tower: origin at the tower axis base. Hub centre = (0, maxY + 0.6, maxZ - 2.1) of the tower bounds
    (scripts/world/dressing_settlement_plan.gd _wind_farm). Wind_Turbine_Rotor: separate object, origin at the hub
    centre, 3 blades of radius 35 m in the XZ plane, rotation axis Blender Y.
  * Gas_Station: canopy 18 x 10 m at the front, shop behind; the forecourt is flat at Z 0 where the Godot dressing
    drops Fuel_Pump props (x = +-0.18 size_x, y = maxY - size_y * (0.25 +- 0.12)); columns stand in line with them.
  * Glass of every building uses the material "Window" (slightly emissive warm, for night).

Style: semi-realistic low poly, plain PBR materials (prefix BK_, plus Window / LampLens) whose base colour is
multiplied by the corner colour attribute "Col" (stone blocks, boards, grime, AO; exported as COLOR_0).
In Blender the kit is laid out in a QA grid around x = +80..+260 m, y = +220..+420 m (far from the cars at the
origin and from the nature / roadside kits); export moves each prop to the origin.

Run inside Blender through the project MCP client (see tools/blender/props/run.sh):
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__', 'STEP': 'build'})
STEP: build (ONLY=[names] or GROUP=name) | report | solo | unsolo | focus | sheet | export | save | all
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
HERE = os.path.join(PROJECT, 'tools', 'blender', 'props')
GLB_PATH = os.path.join(PROJECT, 'assets', 'imported', 'props', 'buildings_kit.glb')
SHEET_PATH = os.path.join(PROJECT, 'docs', 'blender_props', 'buildings_kit.png')
TILE_DIR = os.path.join(PROJECT, 'qa_output', 'blender_look', 'buildings_tiles')
KIT = 'BuildingsKit'
PARENT = 'Settlements'
PI = math.pi
TAU = 2.0 * PI

NAMES = ['House_Cottage_A', 'House_Cottage_B', 'House_Townhouse', 'Farmhouse', 'Barn_Red', 'Silo', 'Shed_Small',
         'House_Chalet', 'House_Adobe', 'Gas_Station', 'Diner', 'Church', 'Harbour_Shed', 'Boathouse', 'Pier_Section',
         'Boat_Fishing', 'Lighthouse', 'Castle_Ruin_Wall', 'Castle_Ruin_Tower', 'Wind_Turbine_Tower',
         'Wind_Turbine_Rotor', 'Water_Tower', 'Festival_Stage', 'Festival_Tent', 'Viewpoint_Deck']

GROUPS = {
    'houses': ['House_Cottage_A', 'House_Cottage_B', 'House_Townhouse', 'Farmhouse', 'House_Chalet', 'House_Adobe'],
    'farm': ['Barn_Red', 'Silo', 'Shed_Small'],
    'commercial': ['Gas_Station', 'Diner', 'Church'],
    'harbour': ['Harbour_Shed', 'Boathouse', 'Pier_Section', 'Boat_Fishing', 'Lighthouse'],
    'landmarks': ['Castle_Ruin_Wall', 'Castle_Ruin_Tower', 'Wind_Turbine_Tower', 'Wind_Turbine_Rotor', 'Water_Tower',
                  'Festival_Stage', 'Festival_Tent', 'Viewpoint_Deck'],
}

# QA grid (Blender world position of each prop origin)
LAYOUT = {
    'House_Cottage_A': (90, 230, 0), 'House_Cottage_B': (110, 230, 0), 'House_Townhouse': (130, 230, 0),
    'Farmhouse': (150, 230, 0), 'House_Chalet': (174, 230, 0), 'House_Adobe': (196, 230, 0),
    'Shed_Small': (212, 230, 0),
    'Barn_Red': (92, 268, 0), 'Silo': (110, 268, 0), 'Gas_Station': (136, 268, 0), 'Diner': (166, 268, 0),
    'Church': (194, 268, 0),
    'Harbour_Shed': (92, 312, 0), 'Boathouse': (112, 312, 0), 'Pier_Section': (126, 312, 0),
    'Boat_Fishing': (136, 312, 0), 'Lighthouse': (152, 312, 0), 'Water_Tower': (172, 312, 0),
    'Festival_Tent': (190, 312, 0), 'Viewpoint_Deck': (204, 312, 0),
    'Castle_Ruin_Wall': (100, 356, 0), 'Castle_Ruin_Tower': (128, 356, 0), 'Festival_Stage': (160, 356, 0),
    'Wind_Turbine_Tower': (240, 400, 0), 'Wind_Turbine_Rotor': None,   # placed on the tower hub (see place_rotor)
}

# props whose origin is not the footprint centre (contract origins), everything else is re-centred in XY
NO_RECENTRE = {'Pier_Section', 'Boat_Fishing', 'Wind_Turbine_Tower', 'Wind_Turbine_Rotor', 'Lighthouse',
               'Castle_Ruin_Tower', 'Silo', 'Water_Tower'}

BUDGET = {'Lighthouse': 12000, 'Castle_Ruin_Wall': 12000, 'Castle_Ruin_Tower': 12000, 'Wind_Turbine_Tower': 12000,
          'Wind_Turbine_Rotor': 12000, 'Festival_Stage': 12000, '': 8000}

# name: dict(c = sRGB base, r = roughness, m = metallic, e = sRGB emission, es = emission strength, ds = double sided)
MATS = {
    'BK_Plaster_Cream': dict(c=(232, 220, 190), r=0.92),
    'BK_Plaster_White': dict(c=(236, 234, 226), r=0.9),
    'BK_Plaster_Ochre': dict(c=(224, 182, 124), r=0.9),
    'BK_Plaster_Rose': dict(c=(214, 158, 136), r=0.9),
    'BK_Stone_Wall': dict(c=(172, 162, 146), r=0.93),
    'BK_Stone_Grey': dict(c=(156, 154, 148), r=0.93),
    'BK_Stone_Dark': dict(c=(112, 108, 100), r=0.95),
    'BK_Stone_Light': dict(c=(200, 192, 174), r=0.9),
    'BK_Brick': dict(c=(150, 80, 60), r=0.9),
    'BK_Adobe': dict(c=(200, 148, 106), r=0.95),
    'BK_Concrete': dict(c=(174, 172, 166), r=0.9),
    'BK_Render_White': dict(c=(234, 234, 230), r=0.85),
    'BK_Roof_Tile': dict(c=(172, 80, 52), r=0.8),
    'BK_Roof_Slate': dict(c=(72, 78, 88), r=0.7),
    'BK_Roof_Shingle': dict(c=(86, 72, 62), r=0.85),
    'BK_Roof_Metal': dict(c=(120, 124, 128), r=0.45, m=0.6),
    'BK_Roof_Metal_Red': dict(c=(132, 46, 38), r=0.5, m=0.35),
    'BK_Wood_Dark': dict(c=(86, 62, 44), r=0.85),
    'BK_Wood_Mid': dict(c=(130, 94, 64), r=0.8),
    'BK_Wood_Light': dict(c=(172, 134, 94), r=0.78),
    'BK_Wood_Weathered': dict(c=(136, 124, 108), r=0.9),
    'BK_Timber_Chalet': dict(c=(122, 78, 46), r=0.8),
    'BK_Barn_Red': dict(c=(152, 40, 32), r=0.8),
    'BK_Falu_Red': dict(c=(132, 38, 32), r=0.82),
    'BK_Trim_White': dict(c=(238, 238, 232), r=0.55),
    'BK_Paint_Green': dict(c=(48, 94, 68), r=0.5),
    'BK_Paint_Blue': dict(c=(48, 84, 126), r=0.5),
    'BK_Paint_Red': dict(c=(152, 38, 34), r=0.5),
    'BK_Paint_Teal': dict(c=(22, 128, 132), r=0.45),
    'BK_Paint_Turquoise': dict(c=(40, 150, 160), r=0.5),
    'BK_Paint_Orange': dict(c=(236, 120, 28), r=0.45),
    'BK_Paint_Yellow': dict(c=(236, 190, 50), r=0.5),
    'BK_Paint_Cream': dict(c=(240, 230, 204), r=0.5),
    'BK_Brass': dict(c=(200, 160, 80), r=0.3, m=0.9),
    'BK_Metal_Galv': dict(c=(172, 176, 178), r=0.4, m=0.75),
    'BK_Metal_Dark': dict(c=(58, 62, 66), r=0.5, m=0.5),
    'BK_Metal_Rust': dict(c=(124, 74, 48), r=0.75, m=0.3),
    'BK_Chrome': dict(c=(216, 220, 224), r=0.18, m=0.95),
    'BK_Steel_Brushed': dict(c=(200, 204, 210), r=0.32, m=0.8),
    'BK_Alu': dict(c=(200, 204, 208), r=0.35, m=0.8),
    'BK_Black': dict(c=(26, 26, 28), r=0.6),
    'Window': dict(c=(62, 78, 94), r=0.1, m=0.1, e=(255, 196, 124), es=0.1),
    'LampLens_Lighthouse': dict(c=(255, 246, 222), r=0.15, e=(255, 228, 172), es=1.0),
    'BK_LightPanel': dict(c=(246, 246, 240), r=0.3, e=(255, 250, 236), es=1.0),
    'BK_LampWarm': dict(c=(255, 236, 200), r=0.3, e=(255, 214, 150), es=0.8),
    'BK_Neon_Pink': dict(c=(255, 96, 172), r=0.3, e=(255, 60, 150), es=1.0),
    'BK_Neon_Cyan': dict(c=(86, 230, 255), r=0.3, e=(40, 220, 255), es=1.0),
    'BK_Beacon_Red': dict(c=(222, 32, 26), r=0.3, e=(255, 30, 20), es=1.0),
    'BK_Nav_Green': dict(c=(30, 200, 80), r=0.3, e=(20, 255, 80), es=0.8),
    'BK_StageLens': dict(c=(250, 246, 236), r=0.2, e=(255, 240, 210), es=0.7),
    'BK_LED_Gold': dict(c=(255, 172, 52), r=0.4, e=(255, 160, 40), es=0.9),
    'BK_LED_Magenta': dict(c=(240, 72, 122), r=0.4, e=(240, 60, 120), es=0.9),
    'BK_LED_Violet': dict(c=(122, 62, 202), r=0.4, e=(110, 50, 210), es=0.9),
    'BK_Shadow': dict(c=(28, 26, 24), r=0.95),
    'BK_Fabric_Dark': dict(c=(42, 42, 46), r=0.85),
    'BK_Canvas_White': dict(c=(242, 240, 232), r=0.7),
    'BK_Canvas_Red': dict(c=(198, 48, 46), r=0.7),
    'BK_Tent_Window': dict(c=(184, 196, 202), r=0.3),
    'BK_Lighthouse_White': dict(c=(242, 242, 238), r=0.6),
    'BK_Lighthouse_Red': dict(c=(188, 32, 30), r=0.55),
    'BK_Turbine_White': dict(c=(234, 236, 238), r=0.4),
    'BK_Hull_White': dict(c=(238, 238, 234), r=0.45),
    'BK_Hull_Blue': dict(c=(36, 80, 130), r=0.45),
    'BK_Antifouling': dict(c=(140, 42, 36), r=0.8),
    'BK_Deck_Wood': dict(c=(152, 122, 88), r=0.85),
    'BK_Rope': dict(c=(192, 172, 122), r=0.9),
    'BK_Buoy_Orange': dict(c=(242, 112, 26), r=0.5),
    'BK_Blossom_Red': dict(c=(208, 36, 46), r=0.7),
    'BK_Blossom_Pink': dict(c=(238, 122, 162), r=0.7),
    'BK_Planting_Green': dict(c=(72, 112, 48), r=0.8),
    'BK_Ivy': dict(c=(58, 86, 42), r=0.85),
    'BK_Rubble': dict(c=(120, 112, 100), r=0.95),
    'BK_Earth': dict(c=(106, 88, 68), r=0.95),
    'BK_Terracotta': dict(c=(178, 94, 62), r=0.85),
}
# Blender-side name -> exported glTF material name (the roadside kit already owns a Blender material "LampLens";
# it is renamed out of the way only for the duration of the export, see export())
EXPORT_RENAME = {'LampLens_Lighthouse': 'LampLens'}

BUILDERS = {}


def register(name):
    def deco(fn):
        BUILDERS[name] = fn
        return fn
    return deco


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


def hrand(*v):
    h = 0.0
    for i, x in enumerate(v):
        h += x * (12.9898 + 31.4159 * i)
    s = math.sin(h * 1.37 + 0.71) * 43758.5453
    return s - math.floor(s)


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


def grime(z, z0=0.0, z1=1.4, dark=0.78):
    return lerp(dark, 1.0, smoothstep(z0, z1, z))


def kcol(k, tint=(1.0, 1.0, 1.0)):
    return (k * tint[0], k * tint[1], k * tint[2])


def vary(R, lo=0.92, hi=1.02, z0=None, z1=1.4, dark=0.8, tint=(1.0, 1.0, 1.0)):
    """Per-face colour: random value in [lo, hi] (optionally darkened near the ground)."""
    def f(c, n):
        k = R.uniform(lo, hi)
        if z0 is not None:
            k *= grime(c.z, z0, z1, dark)
        return kcol(k, tint)
    return f


def flat(k=1.0, tint=(1.0, 1.0, 1.0)):
    return kcol(k, tint)


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
    _sock(bsdf, 'Alpha').default_value = 1.0
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    mat.use_backface_culling = not d.get('ds', False)
    mat.diffuse_color = (lin[0], lin[1], lin[2], 1.0)
    mat.roughness = d.get('r', 0.6)
    mat.metallic = d.get('m', 0.0)
    methods = [i.identifier for i in bpy.types.Material.bl_rna.properties['surface_render_method'].enum_items]
    if 'DITHERED' in methods:
        mat.surface_render_method = 'DITHERED'
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
        self.info = {}

    def mi(self, m):
        if m not in MATS:
            raise KeyError('unknown material %s' % m)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def add(self, verts, faces, mat, smooth=False, fcol=None, fcols=None, vcols=None, vfn=None, hint=None,
            uvfn=None):
        """hint: Vector, callable(face centre) or per-face list -> wanted normal direction (faces are reversed to
        match). fcol: colour or callable(centre, normal); fcols: per-face list; vcols per vertex; vfn(co) per vertex."""
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
            if nrm.length < 2e-6:          # zero-area face (e.g. collapsed frame edge)
                continue
            if hint is not None:
                cen = sum(pts, Vector()) / len(pts)
                if isinstance(hint, list):
                    h = Vector(hint[k])
                elif callable(hint):
                    h = hint(cen)
                else:
                    h = Vector(hint)
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
                if fcols is not None:
                    c = fcols[k]
                elif callable(fcol):
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
    side_mat(i, j) per side face (i = ring interval, j = ORIGINAL polygon edge index j -> j+1), cap_mats=(d0, d1)."""
    n = len(poly)
    cu = sum(p[0] for p in poly) / n
    cv = sum(p[1] for p in poly) / n
    order = list(range(n))
    nf = newell([to3d(u, v, d1) for u, v in poly])
    if nf.dot(to3d(cu, cv, d1) - to3d(cu, cv, d0)) < 0:
        order.reverse()
    P = [poly[i] for i in order]
    ds = [d0] + list(mids) + [d1]
    verts = [to3d(u, v, d) for d in ds for (u, v) in P]
    faces, mats, sm = [], [], []
    for i in range(len(ds) - 1):
        for j in range(n):
            j1 = (j + 1) % n
            faces.append((i * n + j, i * n + j1, (i + 1) * n + j1, (i + 1) * n + j))
            a, b = order[j], order[j1]
            jo = a if (b - a) % n == 1 else b
            mats.append(side_mat(i, jo) if callable(side_mat) else (side_mat or mat))
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
    """8 corners: 4 of one face then the 4 matching corners of the opposite face (same order)."""
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)] + [(i, (i + 1) % 4, 4 + (i + 1) % 4, 4 + i) for i in range(4)]
    return shell(pb, pts, faces, mat, **kw)


def beam(pb, a, b, w, h, mat, up=(0.0, 0.0, 1.0), **kw):
    """Box from centre a to centre b (w across, h along `up` projected), any direction."""
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-6:
        return []
    d.normalize()
    u = Vector(up)
    if abs(d.dot(u.normalized())) > 0.98:
        u = Vector((1.0, 0.0, 0.0)) if abs(d.x) < 0.9 else Vector((0.0, 1.0, 0.0))
    s = d.cross(u).normalized()
    u2 = s.cross(d).normalized()
    pts = []
    for p in (a, b):
        pts += [p - s * w / 2 - u2 * h / 2, p + s * w / 2 - u2 * h / 2, p + s * w / 2 + u2 * h / 2,
                p - s * w / 2 + u2 * h / 2]
    return hexa(pb, pts, mat, **kw)


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
         side_mat=None, cap_mat=None, phase=0.0, closed=False):
    """Generalised cylinder along a polyline (parallel-transport frames), outward winding, optional caps.
    closed=True: the polyline is a loop (no caps, last ring joins the first)."""
    pts = [Vector(p) for p in pts]
    if isinstance(radii, (int, float)):
        radii = [float(radii)] * len(pts)
    N = len(pts)
    T = []
    for i in range(N):
        if closed:
            a, b = pts[(i - 1) % N], pts[(i + 1) % N]
        else:
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, N - 1)]
        T.append((b - a).normalized())
    ref = Vector((1, 0, 0)) if abs(T[0].x) < 0.9 else Vector((0, 1, 0))
    if closed:
        ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
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
    rng = N if closed else N - 1
    for i in range(rng):
        i1 = (i + 1) % N
        for j in range(sides):
            j1 = (j + 1) % sides
            faces.append((i * sides + j, i * sides + j1, i1 * sides + j1, i1 * sides + j))
            fmats.append(side_mat(i, j) if side_mat else mat)
            fsm.append(smooth)
    if not closed and cap1:
        c = pts[-1] + T[-1] * tip
        verts.append(c)
        cols.append(vfn(N - 1, -1, c) if vfn else (1.0, 1.0, 1.0))
        ci = len(verts) - 1
        base = (N - 1) * sides
        for j in range(sides):
            faces.append((ci, base + j, base + (j + 1) % sides))
            fmats.append(cap_mat or mat)
            fsm.append(smooth and tip > 0.0)
    if not closed and cap0:
        c = pts[0]
        verts.append(c)
        cols.append(vfn(0, -1, c) if vfn else (1.0, 1.0, 1.0))
        ci = len(verts) - 1
        for j in range(sides):
            faces.append((ci, (j + 1) % sides, j))
            fmats.append(cap_mat or mat)
            fsm.append(False)
    if closed:
        # orientation: first face normal should point away from the local tube axis
        f = faces[0]
        fc = sum((verts[i] for i in f), Vector()) / 4
        if newell([verts[i] for i in f]).dot(fc - (pts[0] + pts[1]) / 2) < 0:
            faces = [tuple(reversed(f)) for f in faces]
    return pb.add(verts, faces, fmats, smooth=fsm, vcols=cols)


def cyl(pb, c, r, z0, z1, mat, sides=12, r1=None, cap0=True, cap1=True, smooth=False, phase=0.0, **kw):
    """Vertical (truncated) cylinder / cone, closed."""
    c = Vector(c)
    r1 = r if r1 is None else r1
    ring0 = [Vector((c.x + r * math.cos(phase + TAU * k / sides), c.y + r * math.sin(phase + TAU * k / sides), z0))
             for k in range(sides)]
    ring1 = [Vector((c.x + r1 * math.cos(phase + TAU * k / sides), c.y + r1 * math.sin(phase + TAU * k / sides), z1))
             for k in range(sides)]
    return loft(pb, [ring0, ring1], mat, cap0=cap0, cap1=cap1, smooth=smooth, **kw)


def ring_pts(c, r, z, sides, phase=0.0, sx=1.0, sy=1.0):
    return [Vector((c[0] + r * sx * math.cos(phase + TAU * k / sides), c[1] + r * sy * math.sin(phase + TAU * k / sides),
                    z)) for k in range(sides)]


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
    if isinstance(r, (int, float)):
        r = (r, r, r)
    for v in vs:
        d = v.normalized()
        k = 1.0 + amp * noise.noise(d * freq + off) + 0.5 * amp * noise.noise(d * freq * 2.3 + off2)
        p = Vector((d.x * r[0], d.y * r[1], d.z * r[2] * ((1.0 - squash) if d.z < 0 else 1.0))) * k
        out.append(Vector(c) + p)
    return shell(pb, out, fs, mat, smooth=False, fcol=fcol)


def stone_block(pb, c, s, mat, R, rot=0.0, tilt=0.0, k=None):
    """Rough cut block (slightly irregular hexahedron)."""
    c = Vector(c)
    M = rot_z(rot) @ rot_x(tilt)
    pts = []
    for z in (-1, 1):
        for (x, y) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            j = Vector((R.uniform(-0.12, 0.12) * s[0], R.uniform(-0.12, 0.12) * s[1], R.uniform(-0.1, 0.1) * s[2]))
            pts.append(c + M @ (Vector((x * s[0] / 2, y * s[1] / 2, z * s[2] / 2)) + j))
    kk = k if k is not None else R.uniform(0.8, 1.05)
    return hexa(pb, pts, mat, fcol=lambda cc, n: kcol(kk * (0.85 + 0.15 * max(0.0, n.z))))


# ---- 2D outlines (frame coordinates sx, z)
def circle2(r, n, a0=0.0, cx=0.0, cy=0.0):
    return [(cx + r * math.cos(a0 + 2 * PI * k / n), cy + r * math.sin(a0 + 2 * PI * k / n)) for k in range(n)]


def rect2(x0, z0, x1, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def arch2(cx, z0, w, h, seg=6, pointed=False):
    """Window/door outline: vertical sides, round (or pointed) top; counter-clockwise; vertex count 4 + seg - 1."""
    r = w / 2.0
    out = [(cx - r, z0), (cx + r, z0)]
    if not pointed:
        zs = z0 + h - r
        for k in range(seg + 1):
            a = PI * k / seg
            out.append((cx + r * math.cos(a), zs + r * math.sin(a)))
        return out
    # two arcs of radius Rr (lancet) meeting at the apex; seg must be even
    Rr = w * 0.8
    th = math.acos((Rr - r) / Rr)
    zs = z0 + h - Rr * math.sin(th)
    half = max(1, seg // 2)

    def rx(a):
        return r - Rr + Rr * math.cos(a)
    for k in range(half + 1):
        a = th * k / half
        out.append((cx + rx(a), zs + Rr * math.sin(a)))
    for k in range(half - 1, -1, -1):
        a = th * k / half
        out.append((cx - rx(a), zs + Rr * math.sin(a)))
    return out


def rrect2(w, h, r, seg=3, cx=0.0, cy=0.0):
    if r <= 0.0:
        return [(cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2), (cx - w / 2, cy - h / 2)]
    out = []
    for ccx, ccy, a0 in ((w / 2 - r, -h / 2 + r, -PI / 2), (w / 2 - r, h / 2 - r, 0.0),
                         (-w / 2 + r, h / 2 - r, PI / 2), (-w / 2 + r, -h / 2 + r, PI)):
        for k in range(seg + 1):
            a = a0 + (PI / 2) * k / seg
            out.append((cx + ccx + r * math.cos(a), cy + ccy + r * math.sin(a)))
    return out


def stadium2(L, W, seg=6, n_straight=1):
    """Plan outline: straight part L (along x) with semicircular ends of radius W/2 (counter-clockwise)."""
    r = W / 2.0
    out = []
    for k in range(seg + 1):
        a = -PI / 2 + PI * k / seg
        out.append((L / 2 + r * math.cos(a), r * math.sin(a)))
    for k in range(1, n_straight):
        out.append((L / 2 - L * k / n_straight, r))
    for k in range(seg + 1):
        a = PI / 2 + PI * k / seg
        out.append((-L / 2 + r * math.cos(a), r * math.sin(a)))
    for k in range(1, n_straight):
        out.append((-L / 2 + L * k / n_straight, -r))
    return out


# ------------------------------------------------------------------------------------------------------ wall frames
class Frame:
    """Plane of a wall: O origin on the plane, N outward normal, Rv in-plane horizontal axis; p(sx, z, t)."""

    def __init__(self, O, N, Rv):
        self.O = Vector(O)
        self.N = Vector(N).normalized()
        self.Rv = Vector(Rv).normalized()
        self.U = Vector((0.0, 0.0, 1.0))

    def p(self, sx, z, t=0.0):
        return self.O + self.Rv * sx + self.U * z + self.N * t


def FY(y, sgn=1):
    """Wall at world y facing +-Y; sx = world x."""
    return Frame((0.0, y, 0.0), (0.0, sgn, 0.0), (1.0, 0.0, 0.0))


def FX(x, sgn=1):
    """Wall at world x facing +-X; sx = world y."""
    return Frame((x, 0.0, 0.0), (sgn, 0.0, 0.0), (0.0, 1.0, 0.0))


def FR(cx, cy, ang, r):
    """Tangent frame on a vertical cylinder of radius r at angle ang; sx along the tangent (0 at the frame point)."""
    c, s = math.cos(ang), math.sin(ang)
    return Frame((cx + r * c, cy + r * s, 0.0), (c, s, 0.0), (-s, c, 0.0))


def fbox(pb, F, x0, x1, z0, z1, t0, t1, mat, **kw):
    pts = [F.p(x0, z0, t0), F.p(x1, z0, t0), F.p(x1, z1, t0), F.p(x0, z1, t0),
           F.p(x0, z0, t1), F.p(x1, z0, t1), F.p(x1, z1, t1), F.p(x0, z1, t1)]
    return hexa(pb, pts, mat, **kw)


def fprism(pb, F, poly, t0, t1, mat, **kw):
    return extrude(pb, poly, lambda u, v, d: F.p(u, v, d), t0, t1, mat, **kw)


def ring_frame(pb, F, outer, inner, t0, t1, mat, fcol=None):
    """Closed frame between two outlines (same vertex count, same order) from t0 to t1 along F.N."""
    n = len(outer)
    vs = ([F.p(x, z, t0) for x, z in outer] + [F.p(x, z, t1) for x, z in outer] +
          [F.p(x, z, t0) for x, z in inner] + [F.p(x, z, t1) for x, z in inner])
    O0, O1, I0, I1 = 0, n, 2 * n, 3 * n
    cx = sum(p[0] for p in inner) / n
    cz = sum(p[1] for p in inner) / n
    C = F.p(cx, cz, (t0 + t1) / 2)
    faces, hints = [], []
    for i in range(n):
        i1 = (i + 1) % n
        faces.append((O1 + i, O1 + i1, I1 + i1, I1 + i))
        hints.append(F.N)
        faces.append((O0 + i, O0 + i1, I0 + i1, I0 + i))
        hints.append(-F.N)
        fo = (vs[O0 + i] + vs[O0 + i1]) / 2
        d = fo - C
        d -= F.N * d.dot(F.N)
        faces.append((O0 + i, O0 + i1, O1 + i1, O1 + i))
        hints.append(d)
        fi = (vs[I0 + i] + vs[I0 + i1]) / 2
        d = fi - C
        d -= F.N * d.dot(F.N)
        faces.append((I0 + i, I0 + i1, I1 + i1, I1 + i))
        hints.append(-d)
    return pb.add(vs, faces, mat, fcol=fcol, hint=hints)


# ---- wall surfaces with per-block / per-board colour
def courses(z0, z1, h, breaks=()):
    pts = sorted(set([z0, z1] + [b for b in breaks if z0 + 1e-6 < b < z1 - 1e-6]))
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(round((b - a) / h)))
        for k in range(1, n + 1):
            out.append(a + (b - a) * k / n)
    return out


def half_at(shape, z):
    """shape: [(z, half_width), ...] with increasing z; piecewise-linear half width."""
    if z <= shape[0][0]:
        return shape[0][1]
    for (za, ha), (zb, hb) in zip(shape[:-1], shape[1:]):
        if za - 1e-9 <= z <= zb + 1e-9:
            if zb - za < 1e-9:
                return hb
            return ha + (hb - ha) * (z - za) / (zb - za)
    return shape[-1][1]


def top_at(shape, d):
    """Highest z where half(z) >= d (shape halves non-increasing with z)."""
    best = shape[0][0]
    for (za, ha), (zb, hb) in zip(shape[:-1], shape[1:]):
        if ha + 1e-9 >= d:
            if hb >= d - 1e-9:
                best = zb
            elif ha - hb > 1e-9:
                best = za + (zb - za) * (ha - d) / (ha - hb)
    return best


STONE_TINTS = [(1.0, 1.0, 1.0), (1.03, 1.0, 0.95), (0.97, 0.99, 1.03), (1.02, 0.98, 0.94), (0.96, 0.97, 0.98)]


def grid_face(pb, F, cx, shape, mat, kind='stone', course=0.42, blk=(0.45, 0.95), board=0.3, t=0.0, lo=0.8,
              hi=1.06, ground=0.0, dark=0.74, tints=None, alt=0.9):
    """Flat wall surface on frame F (facing F.N) centred at sx = cx, outline given by `shape` (half widths by z).
    kind 'stone': staggered blocks per course; 'hboard': horizontal boards (rows); 'vboard': vertical boards
    (columns, the top follows the outline); 'plain': one face per shape segment."""
    R = random.Random(pb.R.random())
    tints = tints or STONE_TINTS
    zbot, ztop = shape[0][0], shape[-1][0]
    H = max(s[1] for s in shape)
    if kind == 'vboard':
        xs = set()
        k0 = int(math.floor(-H / board))
        for m in range(k0, -k0 + 1):
            x = m * board
            if -H + 0.02 < x < H - 0.02:
                xs.add(round(x, 5))
        for z, h in shape:
            if h > 1e-6:
                xs.add(round(h, 5))
                xs.add(round(-h, 5))
        xs.add(round(-H, 5))
        xs.add(round(H, 5))
        xs = sorted(xs)
        verts, faces, fcols = [], [], []
        for i in range(len(xs) - 1):
            xa, xb = xs[i], xs[i + 1]
            ta, tb = top_at(shape, abs(xa)), top_at(shape, abs(xb))
            if xa < 0 < xb:
                pass
            base = len(verts)
            verts += [F.p(cx + xa, zbot, t), F.p(cx + xb, zbot, t), F.p(cx + xb, tb, t), F.p(cx + xa, ta, t)]
            if ta - zbot < 1e-4:
                faces.append((base, base + 1, base + 2))
            elif tb - zbot < 1e-4:
                faces.append((base, base + 1, base + 3))
            else:
                faces.append((base, base + 1, base + 2, base + 3))
            col = int(math.floor((xa + xb) / 2 / board))
            k = (1.0 if col % 2 == 0 else alt) * R.uniform(0.93, 1.04)
            fcols.append(kcol(k * grime((zbot + ta) / 2 - ground, 0.0, 1.6, dark + 0.08)))
        pb.add(verts, faces, mat, fcols=fcols, hint=F.N)
        return
    step = course if kind in ('stone', 'hboard') else 1e9
    zs = courses(zbot, ztop, step, [s[0] for s in shape])
    for k in range(len(zs) - 1):
        za, zb = zs[k], zs[k + 1]
        ha, hb = half_at(shape, za), half_at(shape, zb)
        if ha < 1e-4 and hb < 1e-4:
            continue
        il, ir = -min(ha, hb), min(ha, hb)
        js = []
        if kind == 'stone':
            x = il + R.uniform(0.1, blk[1] * 0.9)
            while x < ir - 0.12:
                js.append(x)
                x += R.uniform(blk[0], blk[1])
        bot = [-ha] + js + [ha]
        top = [-hb] + js + [hb]
        m = len(bot)
        verts = [F.p(cx + x, za, t) for x in bot] + [F.p(cx + x, zb, t) for x in top]
        faces = []
        if hb < 1e-4 and m == 2:
            faces.append((0, 1, 2))
        else:
            for i in range(m - 1):
                faces.append((i, i + 1, m + i + 1, m + i))
        fcols = []
        zc = (za + zb) / 2 - ground
        for i in range(len(faces)):
            if kind == 'stone':
                kk = R.uniform(lo, hi)
                tt = tints[R.randrange(len(tints))]
            elif kind == 'hboard':
                kk = (1.0 if k % 2 == 0 else alt) * R.uniform(0.95, 1.03)
                tt = (1.0, 1.0, 1.0)
            else:
                kk = 1.0
                tt = (1.0, 1.0, 1.0)
            fcols.append(kcol(kk * grime(zc, 0.0, 1.6, dark), tt))
        pb.add(verts, faces, mat, fcols=fcols, hint=F.N)


def gable_shape(z0, eave, ridge, half):
    return [(z0, half), (eave, half), (ridge, 0.0)]


def wall_set(pb, x0, x1, y0, y1, z0, eave, ridge, axis, mat, kind, gmat=None, gkind=None, gshape=None, **kw):
    """Four walls of a gabled box (ridge along `axis`), each a grid_face. gshape: custom gable outline above z0
    (list of (z, half)); gable walls may use another material / kind above the eave (gmat / gkind)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if axis == 'X':
        long_f = [(FY(y1, 1), cx, (x1 - x0) / 2), (FY(y0, -1), cx, (x1 - x0) / 2)]
        gab_f = [(FX(x1, 1), cy, (y1 - y0) / 2), (FX(x0, -1), cy, (y1 - y0) / 2)]
    else:
        long_f = [(FX(x1, 1), cy, (y1 - y0) / 2), (FX(x0, -1), cy, (y1 - y0) / 2)]
        gab_f = [(FY(y1, 1), cx, (x1 - x0) / 2), (FY(y0, -1), cx, (x1 - x0) / 2)]
    for F, c, h in long_f:
        grid_face(pb, F, c, [(z0, h), (eave, h)], mat, kind, **kw)
    for F, c, h in gab_f:
        shp = gshape or gable_shape(z0, eave, ridge, h)
        if gmat is None:
            grid_face(pb, F, c, shp, mat, kind, **kw)
        else:
            lower = [s for s in shp if s[0] <= eave + 1e-6]
            upper = [s for s in shp if s[0] >= eave - 1e-6]
            grid_face(pb, F, c, lower, mat, kind, **kw)
            grid_face(pb, F, c, upper, gmat, gkind or kind, **kw)


# ------------------------------------------------------------------------------------------------------ roofs
def axis_map(cx, cy, axis):
    if axis == 'X':
        return lambda a, z, s: Vector((cx + s, cy + a, z))
    return lambda a, z, s: Vector((cx + a, cy + s, z))


def slab_frame(A, B):
    """Section-plane frame of a roof slab from A (lower, eave) to B (upper): returns (L, d up-slope, n outward)."""
    A, B = Vector(A), Vector(B)
    d = B - A
    L = d.length
    d.normalize()
    n1 = Vector((-d.y, d.x))
    n = n1 if n1.y > 0 else -n1
    return L, d, n


def roof_slab(pb, cx, cy, axis, A, B, s0, s1, t=0.14, style='tile', mat='BK_Roof_Tile', under='BK_Wood_Dark',
              course=0.34, step=0.035, seg=1.2, rib=0.3, vary_amp=0.1, barge=None, bw=0.05, fascia=None,
              gutter=None, seed=0, eave_cut=True):
    """Roof slab (tiles / slates / shingles as stepped courses, or ribbed metal) between section points A (eave)
    and B (top) in the (across, z) plane, extruded from s0 to s1 along the ridge axis."""
    M = axis_map(cx, cy, axis)
    L, d, n = slab_frame(A, B)
    Bv = Vector(B)

    def P(u, h):
        q = Bv - d * u + n * h
        return (q.x, q.y)
    if style == 'metal':
        prof = [(0.0, 0.0), (0.0, t), (L, t), (L, 0.0)]
        mids = []
        k = int((s1 - s0) / rib)
        for i in range(1, k):
            mids.append(s0 + (s1 - s0) * i / k)
        top_h = t
    else:
        N = max(2, int(round(L / course)))
        c = L / N
        prof = [(0.0, 0.0), (0.0, t)]
        for k in range(1, N + 1):
            prof.append((k * c, t + step))
            if k < N:
                prof.append((k * c, t))
        prof.append((L, 0.0))
        nseg = max(1, int(round((s1 - s0) / seg)))
        mids = [s0 + (s1 - s0) * i / nseg for i in range(1, nseg)]
        top_h = t + step
    poly = [P(u, h) for u, h in prof]
    np_ = len(poly)
    R = random.Random(seed or pb.R.random())
    cols_cache = {}

    def side_mat(i, j):
        if j == np_ - 1:
            return under
        return mat

    def along(cv):
        return (cv.x - cx) if axis == 'X' else (cv.y - cy)

    def fcol(cv, nv):
        if nv.z < -0.2:
            return kcol(0.72)
        if style == 'metal':
            idx = int(math.floor((along(cv) - s0) / rib + 1e-4))
            return kcol((1.0 if idx % 2 == 0 else 0.86) * (0.97 + 0.03 * hrand(idx, seed)))
        key = (round(cv.x * 2.0), round(cv.y * 2.0), round(cv.z * 2.0))
        if key not in cols_cache:
            cols_cache[key] = 1.0 + vary_amp * (R.random() * 2.0 - 1.0)
        k = cols_cache[key]
        if nv.z < 0.35 and style != 'metal':
            k *= 0.8       # butt ends of the courses read as shadow lines
        return kcol(k)
    extrude(pb, poly, lambda a, z, s: M(a, z, s), s0, s1, mat, side_mat=side_mat, mids=mids, fcol=fcol)
    if barge:
        for sa, sb in ((s0 - bw, s0), (s1, s1 + bw)):
            pts = []
            for s in (sa, sb):
                for (u, h) in ((-0.02, -0.16), (L + 0.03, -0.16), (L + 0.03, top_h + 0.04), (-0.02, top_h + 0.04)):
                    a, z = P(u, h)
                    pts.append(M(a, z, s))
            hexa(pb, pts, barge, fcol=flat(0.95))
    if fascia:
        pts = []
        for s in (s0 - (bw if barge else 0.0), s1 + (bw if barge else 0.0)):
            for (u, h) in ((L - 0.01, -0.2), (L + 0.035, -0.2), (L + 0.035, top_h + 0.02), (L - 0.01, top_h + 0.02)):
                a, z = P(u, h)
                pts.append(M(a, z, s))
        hexa(pb, pts, fascia, fcol=flat(0.95))
    if gutter:
        a, z = P(L + 0.035 + 0.07, -0.08)
        e0 = s0 - (bw if barge else 0.0)
        e1 = s1 + (bw if barge else 0.0)
        tube(pb, [M(a, z, e0), M(a, z, e1)], [0.075, 0.075], gutter, sides=6, smooth=False)
    return dict(L=L, d=d, n=n, P=P, top_h=top_h)


def ridge_cap(pb, cx, cy, axis, a, z, s0, s1, r, mat, sides=6):
    M = axis_map(cx, cy, axis)
    tube(pb, [M(a, z, s0), M(a, z, s1)], [r, r], mat, sides=sides, smooth=False, phase=PI / sides)


def gable_roof(pb, cx, cy, axis, span, length, eave, ridge, oh_e=0.45, oh_g=0.3, t=0.14, style='tile',
               mat='BK_Roof_Tile', under='BK_Wood_Dark', barge='BK_Wood_Dark', fascia=None, gutter='BK_Metal_Dark',
               course=0.34, step=0.035, seg=1.2, rib=0.3, ridge_mat=None, vary_amp=0.1, seed=0, bw=0.05):
    """Symmetric gable roof over walls `span` across x `length` along `axis`, wall top at eave, apex at ridge."""
    sl = (ridge - eave) / (span / 2.0)
    out = []
    for side in (1, -1):
        A = (side * (span / 2 + oh_e), eave - oh_e * sl)
        B = (0.0, ridge)
        out.append(roof_slab(pb, cx, cy, axis, A, B, -length / 2 - oh_g, length / 2 + oh_g, t=t, style=style, mat=mat,
                             under=under, course=course, step=step, seg=seg, rib=rib, barge=barge, bw=bw,
                             fascia=fascia or barge, gutter=gutter, vary_amp=vary_amp, seed=seed + side))
    n = out[0]['n']
    top = out[0]['top_h']
    zc = ridge + n.y * t - 0.02
    r = math.hypot(n.x * top, 0.02) + 0.07
    ridge_cap(pb, cx, cy, axis, 0.0, zc, -length / 2 - oh_g - (bw if barge else 0), length / 2 + oh_g +
              (bw if barge else 0), r, ridge_mat or mat)
    return dict(slope=sl, zsurf=lambda a: ridge - abs(a) * sl + t / math.cos(math.atan(sl)))


def house_body(pb, cx, cy, axis, span, length, z0, eave, ridge, mat, dark=0.82):
    """Plaster gable body: pentagon prism (closed); vertex colours darken towards the ground."""
    M = axis_map(cx, cy, axis)
    poly = [(-span / 2, z0), (span / 2, z0), (span / 2, eave), (0.0, ridge), (-span / 2, eave)]
    extrude(pb, poly, lambda a, z, s: M(a, z, s), -length / 2, length / 2, mat,
            vfn=lambda co: kcol(grime(co.z, z0, z0 + 2.0, dark)))


def foundation(pb, x0, x1, y0, y1, top=0.35, mat='BK_Stone_Dark', bottom=-2.5, k=0.9):
    box2(pb, (x0, y0, bottom), (x1, y1, top), mat, fcol=vary(pb.R, k - 0.04, k + 0.04))


# ------------------------------------------------------------------------------------------------------ openings
def window(pb, F, x, zb, w, h, frame='BK_Trim_White', glass='Window', cols=2, rows=2, sill='BK_Stone_Light',
           lintel=None, shutters=None, depth=0.09, fw=0.08, arch=False, flower=None, mull=0.045, seg=6):
    """Window on wall frame F: glass (embedded), frame ring, glazing bars, sill, optional lintel/shutters/flowers.
    x = centre along the wall, zb = bottom of the glass, w/h = glass size."""
    R = pb.R
    gk = R.uniform(0.82, 1.05)
    if arch:
        inner = arch2(x, zb, w, h, seg)
        outer = arch2(x, zb - fw, w + 2 * fw, h + 2 * fw, seg)
        fprism(pb, F, inner, -0.08, 0.012, glass, fcol=flat(gk))
        ring_frame(pb, F, outer, inner, -0.04, depth, frame, fcol=flat(0.96))
        zs = zb + h - w / 2
        for i in range(1, cols):
            xm = x - w / 2 + w * i / cols
            zt = zs + math.sqrt(max(0.0, (w / 2) ** 2 - (xm - x) ** 2)) - 0.01
            fbox(pb, F, xm - mull / 2, xm + mull / 2, zb, zt, -0.03, depth * 0.6, frame)
        for j in range(1, rows):
            zm = zb + (zs - zb) * j / rows
            fbox(pb, F, x - w / 2, x + w / 2, zm - mull / 2, zm + mull / 2, -0.03, depth * 0.6, frame)
    else:
        fbox(pb, F, x - w / 2, x + w / 2, zb, zb + h, -0.08, 0.012, glass, fcol=flat(gk))
        ring_frame(pb, F, rect2(x - w / 2 - fw, zb - fw, x + w / 2 + fw, zb + h + fw), rect2(x - w / 2, zb, x + w / 2, zb + h),
                   -0.04, depth, frame, fcol=flat(0.96))
        for i in range(1, cols):
            xm = x - w / 2 + w * i / cols
            fbox(pb, F, xm - mull / 2, xm + mull / 2, zb, zb + h, -0.03, depth * 0.6, frame)
        for j in range(1, rows):
            zm = zb + h * j / rows
            fbox(pb, F, x - w / 2, x + w / 2, zm - mull / 2, zm + mull / 2, -0.03, depth * 0.6, frame)
    if sill:
        fbox(pb, F, x - w / 2 - fw - 0.06, x + w / 2 + fw + 0.06, zb - fw - 0.07, zb - fw + 0.005, -0.04, depth + 0.07,
             sill, fcol=flat(0.92))
    if lintel and not arch:
        fbox(pb, F, x - w / 2 - fw - 0.1, x + w / 2 + fw + 0.1, zb + h + fw - 0.005, zb + h + fw + 0.2, -0.04, 0.045,
             lintel, fcol=flat(0.95))
    if shutters:
        for s in (-1, 1):
            xa = x + s * (w / 2 + fw + 0.03)
            xb = x + s * (w / 2 + fw + 0.03 + w / 2)
            x0, x1 = min(xa, xb), max(xa, xb)
            fbox(pb, F, x0, x1, zb - fw + 0.02, zb + h + fw - 0.02, -0.02, 0.045, shutters, fcol=flat(0.95))
            for zz in (zb + h * 0.25, zb + h * 0.75):
                fbox(pb, F, x0 + 0.04, x1 - 0.04, zz - 0.035, zz + 0.035, 0.04, 0.065, shutters, fcol=flat(0.8))
    if flower:
        flower_box(pb, F, x, zb - fw - 0.07, w + 2 * fw + 0.1, flower)


def flower_box(pb, F, x, ztop, w, colours=('BK_Blossom_Red', 'BK_Blossom_Pink')):
    R = pb.R
    fbox(pb, F, x - w / 2, x + w / 2, ztop - 0.24, ztop - 0.02, 0.0, 0.26, 'BK_Wood_Dark', fcol=flat(0.9))
    n = max(2, int(w / 0.3))
    for i in range(n):
        xx = x - w / 2 + 0.12 + (w - 0.24) * (i + 0.5) / n
        mat = 'BK_Planting_Green' if i % 3 == 1 else colours[i % len(colours)]
        p = F.p(xx, ztop + 0.02, 0.13)
        blob(pb, p, (0.14, 0.14, 0.11), mat, sub=0, amp=0.25, freq=2.0, squash=0.3,
             fcol=lambda c, nn: kcol(R.uniform(0.85, 1.05)))


def door(pb, F, x, z0, w, h, leaf='BK_Paint_Green', frame='BK_Trim_White', step='BK_Stone_Dark', panels=2,
         glass_top=False, arch=False, knob='BK_Brass', ground=0.0, fw=0.1, depth=0.1, double=False, seg=6,
         step_w=None):
    """Door on wall frame F: frame (jambs + head), recessed leaf with raised panels, knob, steps down to ground."""
    R = pb.R
    if arch:
        inner = arch2(x, z0, w, h, seg)
        outer = arch2(x, z0, w + 2 * fw, h + fw, seg)
        outer[0] = (x - w / 2 - fw, z0)
        outer[1] = (x + w / 2 + fw, z0)
        ring_frame(pb, F, outer, inner, -0.05, depth, frame, fcol=flat(0.95))
        fprism(pb, F, inner, -0.1, 0.0, leaf, fcol=flat(0.92))
        hp = h - w / 2
    else:
        fbox(pb, F, x - w / 2 - fw, x - w / 2, z0, z0 + h, -0.05, depth, frame, fcol=flat(0.95))
        fbox(pb, F, x + w / 2, x + w / 2 + fw, z0, z0 + h, -0.05, depth, frame, fcol=flat(0.95))
        fbox(pb, F, x - w / 2 - fw, x + w / 2 + fw, z0 + h, z0 + h + fw, -0.05, depth, frame, fcol=flat(0.95))
        fbox(pb, F, x - w / 2, x + w / 2, z0, z0 + h, -0.1, 0.0, leaf, fcol=flat(0.92))
        hp = h
    leaves = 2 if double else 1
    lw = w / leaves
    for li in range(leaves):
        lx0 = x - w / 2 + li * lw
        if double:
            fbox(pb, F, lx0 + lw - 0.015, lx0 + lw + 0.015, z0, z0 + hp - 0.02, -0.02, 0.012, frame)
        if glass_top:
            fbox(pb, F, lx0 + 0.12, lx0 + lw - 0.12, z0 + hp * 0.55, z0 + hp - 0.15, -0.02, 0.01, 'Window',
                 fcol=flat(0.95))
            np_ = 1
            ph = hp * 0.38
        else:
            np_ = panels
            ph = (hp - 0.3 - 0.12 * (np_ - 1)) / max(1, np_)
        for k in range(np_):
            zz = z0 + 0.15 + k * (ph + 0.12)
            fbox(pb, F, lx0 + 0.12, lx0 + lw - 0.12, zz, zz + ph, -0.02, 0.018, leaf, fcol=flat(0.82))
    kx = x + w / 2 - 0.14 if not double else x + 0.12
    fbox(pb, F, kx - 0.03, kx + 0.03, z0 + 0.95, z0 + 1.05, 0.0, 0.07, knob)
    rise = z0 - ground
    sw = step_w or (w + 2 * fw + 0.3)
    if rise > 0.05:
        n = max(1, int(round(rise / 0.18)))
        for k in range(n):
            ztop = z0 - rise * k / n
            fbox(pb, F, x - sw / 2, x + sw / 2, ground - 0.4, ztop, -0.06, 0.32 + 0.3 * k, step, fcol=vary(R, 0.85, 0.95))
    else:
        fbox(pb, F, x - sw / 2, x + sw / 2, z0 - 0.3, z0 + 0.03, -0.06, 0.3, step, fcol=vary(R, 0.85, 0.95))


def chimney(pb, x, y, zb, zt, sx=0.8, sy=0.6, mat='BK_Brick', cap='BK_Stone_Dark', pots=2, pot_mat='BK_Terracotta'):
    R = pb.R
    box2(pb, (x - sx / 2, y - sy / 2, zb), (x + sx / 2, y + sy / 2, zt), mat,
         fcol=lambda c, n: kcol(R.uniform(0.86, 1.0)))
    box2(pb, (x - sx / 2 - 0.06, y - sy / 2 - 0.06, zt - 0.3), (x + sx / 2 + 0.06, y + sy / 2 + 0.06, zt - 0.18), mat,
         fcol=flat(0.85))
    box2(pb, (x - sx / 2 - 0.05, y - sy / 2 - 0.05, zt - 0.02), (x + sx / 2 + 0.05, y + sy / 2 + 0.05, zt + 0.07), cap,
         fcol=flat(0.9))
    for i in range(pots):
        px = x + (i - (pots - 1) / 2) * (sx / max(1, pots))
        cyl(pb, (px, y, 0), 0.12, zt + 0.05, zt + 0.42, pot_mat, sides=8, r1=0.1, fcol=flat(0.9))


def quoins(pb, x0, x1, y0, y1, z0, z1, mat='BK_Stone_Light', h=0.32, la=0.55, lb=0.3, proud=0.035, corners=None):
    R = pb.R
    cs = corners or [(x0, y0, -1, -1), (x1, y0, 1, -1), (x1, y1, 1, 1), (x0, y1, -1, 1)]
    zs = courses(z0, z1, h)
    for (xc, yc, sx, sy) in cs:
        for k in range(len(zs) - 1):
            a, b = (la, lb) if k % 2 == 0 else (lb, la)
            xa, xb = sorted((xc - sx * a, xc + sx * proud))
            ya, yb = sorted((yc - sy * b, yc + sy * proud))
            box2(pb, (xa, ya, zs[k] + 0.012), (xb, yb, zs[k + 1] - 0.012), mat, fcol=vary(R, 0.88, 1.0))


def downpipe(pb, top, out, z_bottom=0.05, r=0.045, mat='BK_Metal_Dark', wall_gap=0.05):
    """Downpipe from a gutter point `top` to the ground; `out` = (wall point at the same height, outward normal)."""
    top = Vector(top)
    wp, nrm = Vector(out[0]), Vector(out[1]).normalized()
    w = wp + nrm * (r + wall_gap * 0.1)
    pts = [top + Vector((0, 0, 0.03)), top - Vector((0, 0, 0.22)),
           Vector((w.x, w.y, top.z - 0.65)), Vector((w.x, w.y, z_bottom + 0.3)),
           Vector((w.x, w.y, z_bottom + 0.08)) + nrm * 0.16]
    tube(pb, pts, [r] * len(pts), mat, sides=6, smooth=False)


def railing(pb, pts, z, h=1.0, post_mat='BK_Wood_Mid', rail_mat='BK_Wood_Mid', bal_mat=None, post_every=1.6,
            bal=0.14, bal_w=0.05, post_w=0.1, rail_w=0.1, rail_h=0.06, bottom=0.12, closed=False, style='bal'):
    """Railing along a polyline of plan points at deck height z: posts, top + bottom rail, balusters or boards."""
    P = [Vector((p[0], p[1], z)) for p in pts]
    segs = list(zip(P[:-1], P[1:]))
    if closed:
        segs.append((P[-1], P[0]))
    R = pb.R
    for a, b in segs:
        d = b - a
        L = d.length
        n = max(1, int(math.ceil(L / post_every)))
        for k in range(n + 1):
            if k == n and closed:
                continue
            p = a + d * (k / n)
            box2(pb, (p.x - post_w / 2, p.y - post_w / 2, z - 0.02), (p.x + post_w / 2, p.y + post_w / 2, z + h + 0.04),
                 post_mat, fcol=vary(R, 0.85, 0.95))
        beam(pb, a + Vector((0, 0, h)), b + Vector((0, 0, h)), rail_w, rail_h, rail_mat, fcol=flat(0.95))
        if bottom:
            beam(pb, a + Vector((0, 0, bottom)), b + Vector((0, 0, bottom)), rail_w * 0.6, rail_h * 0.8, rail_mat,
                 fcol=flat(0.85))
        if style == 'bal' and bal:
            m = int(L / bal)
            for k in range(1, m):
                p = a + d * (k / m)
                box2(pb, (p.x - bal_w / 2, p.y - bal_w / 2, z + (bottom or 0.0)), (p.x + bal_w / 2, p.y + bal_w / 2,
                                                                                    z + h - rail_h / 2),
                     bal_mat or rail_mat, fcol=vary(R, 0.85, 1.0))
        elif style == 'mid':
            beam(pb, a + Vector((0, 0, h * 0.55)), b + Vector((0, 0, h * 0.55)), rail_w * 0.6, rail_h * 0.8,
                 rail_mat, fcol=flat(0.9))


def truss(pb, a, b, w=0.4, h=0.4, cr=0.035, dr=0.02, step=0.8, mat='BK_Alu', faces=('L', 'R', 'B', 'T'),
          up=(0.0, 0.0, 1.0)):
    """Box truss from a to b (centre line): 4 chords + zig-zag diagonals on the chosen faces."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    d.normalize()
    u = Vector(up)
    if abs(d.dot(u)) > 0.95:
        u = Vector((0.0, 1.0, 0.0))
    s = d.cross(u).normalized()
    u2 = s.cross(d).normalized()
    cs = {'LB': -s * w / 2 - u2 * h / 2, 'RB': s * w / 2 - u2 * h / 2, 'RT': s * w / 2 + u2 * h / 2,
          'LT': -s * w / 2 + u2 * h / 2}
    for k in cs.values():
        tube(pb, [a + k, b + k], [cr, cr], mat, sides=5, smooth=False)
    n = max(1, int(round(L / step)))
    pairs = {'L': ('LB', 'LT'), 'R': ('RB', 'RT'), 'B': ('LB', 'RB'), 'T': ('LT', 'RT')}
    for f in faces:
        c0, c1 = pairs[f]
        for i in range(n):
            p0 = a + d * (L * i / n) + (cs[c0] if i % 2 == 0 else cs[c1])
            p1 = a + d * (L * (i + 1) / n) + (cs[c1] if i % 2 == 0 else cs[c0])
            tube(pb, [p0, p1], [dr, dr], mat, sides=4, smooth=False, cap0=False, cap1=False)


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
    par = ensure_child(PARENT, root)
    return ensure_child(KIT, par)


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
    # re-centre the footprint (above-ground part) in XY unless the prop has a contract origin
    if pb.name not in NO_RECENTRE:
        vs = [v.co for v in bm.verts if v.co.z > -0.25]
        cx = round((min(v.x for v in vs) + max(v.x for v in vs)) / 2, 3)
        cy = round((min(v.y for v in vs) + max(v.y for v in vs)) / 2, 3)
        if abs(cx) > 1e-4 or abs(cy) > 1e-4:
            bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((-cx, -cy, 0.0)))
        pb.info['recentred'] = (cx, cy)
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
    place_object(ob)
    return ob


def place_object(ob):
    if ob.name == 'Wind_Turbine_Rotor':
        tw = bpy.data.objects.get('Wind_Turbine_Tower')
        base = Vector(LAYOUT['Wind_Turbine_Tower'])
        hub = turbine_hub(tw) if tw is not None else Vector((0.0, 5.0, 70.4))
        ob.location = base + hub
    else:
        ob.location = LAYOUT[ob.name]


def turbine_hub(tower_ob):
    """Hub centre in tower-local Blender coordinates, as Godot derives it from the tower AABB."""
    vs = [v.co for v in tower_ob.data.vertices]
    return Vector((0.0, max(v.y for v in vs) + 0.6, max(v.z for v in vs) - 2.1))


def load_builders():
    for fn in ('buildings_kit_houses.py', 'buildings_kit_landmarks.py'):
        p = os.path.join(HERE, fn)
        if os.path.exists(p):
            exec(compile(open(p, encoding='utf-8').read(), p, 'exec'), globals())


def build(only=None):
    mat = bpy.data.materials.get('Window')
    if mat is not None:
        users = [o.name for o in bpy.data.objects if o.type == 'MESH' and
                 mat.name in [s.name for s in o.data.materials if s]]
        if any(u not in NAMES for u in users):
            raise RuntimeError('material Window is used outside the kit: %s' % users)
    load_builders()
    coll = kit_collection()
    out = []
    order = [n for n in NAMES if n != 'Wind_Turbine_Rotor'] + ['Wind_Turbine_Rotor']
    for name in order:
        if only and name not in only:
            continue
        pb = BUILDERS[name]()
        ob = finish(pb, coll)
        out.append((ob.name, pb.info))
    # keep the rotor on the hub whenever the tower is rebuilt
    rot = bpy.data.objects.get('Wind_Turbine_Rotor')
    if rot is not None:
        place_object(rot)
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
        samp = list(vco)
        seen_e = set()
        for f in comp:
            samp.append(f.calc_center_median().copy())
            for e in f.edges:
                if e.index in seen_e:
                    continue
                seen_e.add(e.index)
                a, b = e.verts[0].co, e.verts[1].co
                k = int((b - a).length / 0.25)
                for t in range(1, min(k, 40)):
                    samp.append(a.lerp(b, t / k))
        step = max(1, len(samp) // 300)
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
    order = sorted(range(n), key=lambda i: info[i]['mn'].x)
    for oi, i in enumerate(order):
        A = info[i]
        for j in order[oi + 1:]:
            B = info[j]
            if B['mn'].x - tol > A['mx'].x:
                break
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
    floating = [i for i in range(n) if find(i) != find(n)]
    vs = [v.co for v in me.vertices]
    mn = Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs)))
    mx = Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs)))
    budget = budget_of(ob.name)
    return dict(name=ob.name, height=round(mx.z, 2), below=round(mn.z, 2), size_x=round(mx.x - mn.x, 2),
                size_y=round(mx.y - mn.y, 2), x_range=(round(mn.x, 2), round(mx.x, 2)),
                y_range=(round(mn.y, 2), round(mx.y, 2)), tris=tris, budget=budget,
                ok_budget=tris <= budget, n_mats=len(me.materials), islands=n,
                open_islands=sum(1 for a in info if not a['closed']),
                inverted=sum(1 for a in info if a['closed'] and a['vol'] < 0), floating=len(floating),
                floating_at=[tuple(round(c, 2) for c in (info[i]['mn'] + info[i]['mx']) / 2) for i in floating[:6]],
                degenerate=degen, uv=len(me.uv_layers), col=[a.name for a in me.color_attributes],
                loc=tuple(round(c, 2) for c in ob.location))


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


def contract_checks():
    """Numbers the Godot code relies on."""
    out = {}
    tw = bpy.data.objects.get('Wind_Turbine_Tower')
    rot = bpy.data.objects.get('Wind_Turbine_Rotor')
    if tw is not None:
        hub = turbine_hub(tw)
        out['turbine_hub_local'] = tuple(round(c, 3) for c in hub)
        if rot is not None:
            out['rotor_loc_minus_tower'] = tuple(round(c, 3) for c in (rot.location - tw.location))
            rv_ = [v.co for v in rot.data.vertices]
            out['rotor_radius'] = round(max(math.hypot(v.x, v.z) for v in rv_), 3)
            out['rotor_y_range'] = (round(min(v.y for v in rv_), 3), round(max(v.y for v in rv_), 3))
            # clearance between blades and tower (assembled): min distance of rotor verts to tower surface in XY
    lh = bpy.data.objects.get('Lighthouse')
    if lh is not None:
        vs = [v.co for v in lh.data.vertices]
        top = max(v.z for v in vs)
        idx = [i for i, m in enumerate(lh.data.materials) if m and m.name == 'LampLens_Lighthouse']
        zs = [lh.data.vertices[vi].co.z for p in lh.data.polygons if p.material_index in idx for vi in p.vertices]
        if zs:
            out['lighthouse'] = dict(top=round(top, 3), beam_pivot=round(top * 0.86, 3),
                                     lens_z=(round(min(zs), 3), round(max(zs), 3)))
    gs = bpy.data.objects.get('Gas_Station')
    if gs is not None:
        vs = [v.co for v in gs.data.vertices]
        mnx, mxx = min(v.x for v in vs), max(v.x for v in vs)
        mny, mxy = min(v.y for v in vs), max(v.y for v in vs)
        sx, sy = mxx - mnx, mxy - mny
        out['gas_pumps_at'] = [(round(px * sx * 0.18, 2), round(mxy - sy * (0.25 + pz), 2))
                               for px in (-1, 1) for pz in (-0.12, 0.12)]
    for nm in ('Pier_Section', 'Boat_Fishing'):
        o = bpy.data.objects.get(nm)
        if o is not None:
            vs = [v.co for v in o.data.vertices]
            out[nm] = dict(z=(round(min(v.z for v in vs), 2), round(max(v.z for v in vs), 2)),
                           y=(round(min(v.y for v in vs), 2), round(max(v.y for v in vs), 2)),
                           x=(round(min(v.x for v in vs), 2), round(max(v.x for v in vs), 2)))
    return out


# ------------------------------------------------------------------------------------------------------ QA helpers
REF_COLL = '_QA_BuildingsRef'
SOLO_KEY = 'bk_solo_state'


def _ref_col():
    col = bpy.data.collections.get(REF_COLL) or bpy.data.collections.new(REF_COLL)
    if col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    return col


def ref_on(only=None):
    col = _ref_col()
    mat = bpy.data.materials.get('QA_BuildingsRefMat') or bpy.data.materials.new('QA_BuildingsRefMat')
    mat.diffuse_color = (0.9, 0.15, 0.1, 1.0)
    made = []
    for name in NAMES:
        if only and name not in only:
            continue
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        xs = [v.co.x for v in ob.data.vertices]
        ys = [v.co.y for v in ob.data.vertices]
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
        zr = 0.0 if name not in ('Boat_Fishing',) else 0.6
        r.location = ob.location + Vector((max(xs) + 0.6, max(ys) - 0.3, zr))
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
    m = bpy.data.materials.get('QA_BuildingsRefMat')
    if m is not None and m.users == 0:
        bpy.data.materials.remove(m)
    return n


def focus(name, local, size=1.0):
    col = _ref_col()
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


def solo(only):
    """Viewport-hide every other kit prop / ref, the other kits and the Cars + Traffic collections, so look() sees
    only the targets. The previous state is stored on the scene and restored by unsolo()."""
    sc = bpy.context.scene
    if SOLO_KEY in sc:
        unsolo()
    keep = set(only or [])
    keep |= {'QA_Ref1p8_' + n for n in keep}
    keep.add('QA_Focus')
    hidden = []
    pool = list(kit_collection().objects) + list(getattr(bpy.data.collections.get(REF_COLL), 'objects', []))
    for cn in ('NatureKit', 'RoadsideKit'):
        c = bpy.data.collections.get(cn)
        if c is not None:
            pool += list(c.objects)
    for ob in pool:
        if ob.name not in keep and not ob.hide_get():
            ob.hide_set(True)
            hidden.append(ob.name)
    lcs = {}
    root = bpy.context.view_layer.layer_collection.children.get('SUNWARD_GODOT')
    if root is not None:
        for cn in ('Cars', 'Traffic'):
            lc = root.children.get(cn)
            if lc is not None:
                lcs[cn] = lc.hide_viewport
                lc.hide_viewport = True
    sc[SOLO_KEY] = json.dumps(dict(objs=hidden, lcs=lcs))
    return len(hidden)


def unsolo():
    sc = bpy.context.scene
    if SOLO_KEY not in sc:
        return 0
    st = json.loads(sc[SOLO_KEY])
    n = 0
    for nm in st['objs']:
        ob = bpy.data.objects.get(nm)
        if ob is not None:
            ob.hide_set(False)
            n += 1
    root = bpy.context.view_layer.layer_collection.children.get('SUNWARD_GODOT')
    if root is not None:
        for cn, v in st['lcs'].items():
            lc = root.children.get(cn)
            if lc is not None:
                lc.hide_viewport = v
    del sc[SOLO_KEY]
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
        elif isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)


VIEW = {'Pier_Section': (0.75, 0.6, 0.45), 'Boat_Fishing': (0.8, 0.55, 0.35), 'Wind_Turbine_Rotor': (0.3, 1.0, 0.1),
        'Wind_Turbine_Tower': (0.7, 0.75, 0.15), 'Castle_Ruin_Wall': (0.35, 1.0, 0.3),
        'Festival_Stage': (0.4, 1.0, 0.3), 'Gas_Station': (0.55, 0.85, 0.35), 'Lighthouse': (0.45, 0.85, 0.15)}
TILE_EXTRA = {'Wind_Turbine_Tower': ['Wind_Turbine_Rotor']}


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
    kit_names = {o.name for o in kit}
    others = {o.name: o.hide_render for o in sc.objects if o.name not in kit_names and o.name not in hidden_qa}
    for nm in others:
        sc.objects[nm].hide_render = True
    made = []
    os.makedirs(TILE_DIR, exist_ok=True)
    tiles = []
    stats = {d['name']: d for d in report(names)}
    try:
        qa.hide_viewport = False
        qa.hide_render = False
        if lc is not None:
            lc.hide_viewport = False
        world = bpy.data.worlds.new('QA_BuildingsWorld')
        try:
            world.use_nodes = True
        except Exception:
            pass
        bg = next((nd for nd in world.node_tree.nodes if nd.type == 'BACKGROUND'), None)
        if bg is not None:
            bg.inputs[0].default_value = (0.5, 0.62, 0.8, 1.0)
            bg.inputs[1].default_value = 0.9
        gm = bpy.data.meshes.new('QA_BuildingsGround')
        gbm = bmesh.new()
        bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=600.0)
        gbm.to_mesh(gm)
        gbm.free()
        gmat = bpy.data.materials.new('QA_BuildingsGroundMat')
        gmat.diffuse_color = (0.25, 0.25, 0.22, 1.0)
        try:
            gmat.use_nodes = True
            b = next(nd for nd in gmat.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
            _sock(b, 'Base Color').default_value = (0.2, 0.22, 0.16, 1.0)
            _sock(b, 'Roughness').default_value = 0.95
        except Exception:
            pass
        gm.materials.append(gmat)
        ground = bpy.data.objects.new('QA_BuildingsGround', gm)
        ground.location = (170.0, 320.0, -0.004)
        qa.objects.link(ground)
        made.append(ground)
        cam = bpy.data.objects.new('QA_BuildingsCam', bpy.data.cameras.new('QA_BuildingsCam'))
        cam.data.lens = 50.0
        cam.data.clip_end = 3000.0
        qa.objects.link(cam)
        made.append(cam)
        sun = bpy.data.objects.new('QA_BuildingsSun', bpy.data.lights.new('QA_BuildingsSun', 'SUN'))
        sun.data.energy = 4.0
        try:
            sun.data.angle = math.radians(3.0)
        except Exception:
            pass
        Ls = Vector((-0.35, 0.75, 0.62)).normalized()
        sun.rotation_euler = Ls.to_track_quat('Z', 'Y').to_euler()
        qa.objects.link(sun)
        made.append(sun)
        refmat = bpy.data.materials.new('QA_BuildingsRefMat2')
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
        # review fix: the first EEVEE still of a run could come out without its prop (House_Cottage_A was missing from
        # the 10:37 sheet - materials / depsgraph not ready yet). A throwaway warm-up render of the whole kit first.
        for o in kit:
            o.hide_render = False
        allw = [o.matrix_world @ Vector(c) for o in kit for c in o.bound_box]
        kc = sum(allw, Vector()) / len(allw)
        cam.location = kc + Vector((0.55, 0.85, 0.32)).normalized() * 400.0
        cam.rotation_euler = (kc - cam.location).to_track_quat('-Z', 'Y').to_euler()
        r.stamp_note_text = 'warm-up'
        r.filepath = os.path.join(TILE_DIR, '_warmup.png')
        bpy.ops.render.render(write_still=False)
        for name in names:
            ob = bpy.data.objects.get(name)
            if ob is None:
                continue
            group = [ob] + [bpy.data.objects[e] for e in TILE_EXTRA.get(name, []) if bpy.data.objects.get(e)]
            for o in kit:
                o.hide_render = o not in group
            ws = [o.matrix_world @ v.co for o in group for v in o.data.vertices]
            zfloor = 0.0 if name != 'Pier_Section' else min(p.z for p in ws)     # boat: ground = waterline
            mn = Vector((min(p.x for p in ws), min(p.y for p in ws), max(zfloor, min(p.z for p in ws))))
            mx = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
            ground.location.z = -0.004
            if name == 'Pier_Section':
                ground.location.z = -1.2
            rbm = bmesh.new()
            bmesh.ops.create_cone(rbm, cap_ends=True, segments=10, radius1=0.2, radius2=0.16, depth=1.8,
                                  matrix=Matrix.Translation((0, 0, 0.9)))
            rme = bpy.data.meshes.new('QA_BuildingsRef')
            rbm.to_mesh(rme)
            rbm.free()
            rme.materials.append(refmat)
            ref = bpy.data.objects.new('QA_BuildingsRef', rme)
            ref.location = (mx.x + 0.6, mx.y - 0.4, 0.0)
            qa.objects.link(ref)
            mx.x += 1.0
            c = (mn + mx) / 2
            rad = (mx - mn).length / 2
            view = Vector(VIEW.get(name, (0.55, 0.85, 0.32))).normalized()
            dist = rad / math.sin(fov / 2) * 0.98
            cam.location = c + view * dist
            cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
            cam.data.clip_start = max(0.02, dist * 0.01)
            st = stats.get(name, {})
            r.stamp_note_text = '%s   h %.1f m   %d tris' % (name, st.get('height', mx.z), st.get('tris', 0))
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
        out = bpy.data.images.new('QA_BuildingsSheet', W, H, alpha=False)
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
                _remove_any(o)
            except ReferenceError:
                pass
        o = bpy.data.objects.get('QA_BuildingsRef')
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
        for coll, nm in ((bpy.data.worlds, 'QA_BuildingsWorld'), (bpy.data.materials, 'QA_BuildingsGroundMat'),
                         (bpy.data.materials, 'QA_BuildingsRefMat2'), (bpy.data.cameras, 'QA_BuildingsCam'),
                         (bpy.data.lights, 'QA_BuildingsSun'), (bpy.data.meshes, 'QA_BuildingsGround')):
            d = coll.get(nm)
            if d is not None and d.users == 0:
                coll.remove(d)
    return SHEET_PATH, [t[0] for t in tiles]


# ------------------------------------------------------------------------------------------------------ export
def _rename_for_export():
    """Give exported materials their contract names; returns the undo list."""
    undo = []
    for src, dst in EXPORT_RENAME.items():
        m = bpy.data.materials.get(src)
        if m is None:
            continue
        other = bpy.data.materials.get(dst)
        if other is not None and other is not m:
            tmp = dst + '__bk_export_tmp'
            other.name = tmp
            if other.name != tmp:
                raise RuntimeError('could not move %s out of the way' % dst)
            undo.append((other, dst))
        m.name = dst
        if m.name != dst:
            raise RuntimeError('could not rename %s to %s (got %s)' % (src, dst, m.name))
        undo.insert(0, (m, src))
    return undo


def _undo_rename(undo):
    for m, nm in undo:
        m.name = nm
    for m, nm in undo:
        if m.name != nm:
            m.name = nm


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
    undo = []
    try:
        undo = _rename_for_export()
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
        _undo_rename(undo)
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
    names_after = {m: bpy.data.materials.get(m) is not None for m in ('LampLens', 'LampLens_Lighthouse')}
    return res, dropped, names_after, verify_glb(GLB_PATH)


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
                animations=len(js.get('animations', [])), images=len(js.get('images', [])),
                lights='KHR_lights_punctual' in js.get('extensionsUsed', []), extensions=js.get('extensionsUsed', []),
                double_sided=sorted(m['name'] for m in mats if m.get('doubleSided')),
                alpha=sorted(m['name'] for m in mats if m.get('alphaMode', 'OPAQUE') != 'OPAQUE'),
                emissive=sorted(m['name'] for m in mats if any(c > 0 for c in m.get('emissiveFactor', [0, 0, 0]))),
                window=mat_named.get('Window', {}).get('emissiveFactor'),
                lamp_lens=mat_named.get('LampLens', {}).get('emissiveFactor'),
                bad_mat_names=[m['name'] for m in mats if not (m['name'].startswith('BK_') or
                                                              m['name'] in ('Window', 'LampLens'))],
                total_tris=sum(p['tris'] for p in per), nodes=per)


def save():
    check_file()
    unsolo()
    ref_off()
    root = bpy.context.view_layer.layer_collection.children.get('SUNWARD_GODOT')
    if root is not None:
        for cn in ('Cars', 'Traffic'):
            lc = root.children.get(cn)
            if lc is not None and lc.hide_viewport:
                raise RuntimeError('%s layer collection still hidden - restore before saving' % cn)
    bpy.ops.wm.save_mainfile()
    return bpy.data.filepath


# ------------------------------------------------------------------------------------------------------ main
def _sel():
    only = globals().get('ONLY')
    grp = globals().get('GROUP')
    if grp:
        only = list(GROUPS[grp]) if isinstance(grp, str) else [n for g in grp for n in GROUPS[g]]
    return only


if __name__ == '__main__':
    check_file()
    STEP_ = globals().get('STEP', 'build')
    ONLY_ = _sel()
    if STEP_ == 'build':
        for nm, inf in build(ONLY_):
            print('built', nm, inf)
        for d in report(ONLY_):
            print(d)
    elif STEP_ == 'report':
        for d in report(ONLY_):
            print(d)
        print('contract', contract_checks())
    elif STEP_ == 'ref_on':
        print('refs', ref_on(ONLY_))
    elif STEP_ == 'ref_off':
        print('refs removed', ref_off())
    elif STEP_ == 'solo':
        ref_on(ONLY_)
        print('hidden', solo(ONLY_))
    elif STEP_ == 'focus':
        print('focus', focus(ONLY_[0], globals().get('AT', (0, 0, 0)), globals().get('SIZE', 1.0)))
        print('hidden', solo(ONLY_))
    elif STEP_ == 'unsolo':
        print('unhidden', unsolo(), 'refs removed', ref_off())
        o = bpy.data.objects.get('QA_Focus')
        if o is not None:
            remove_object(o)
    elif STEP_ == 'sheet':
        print('sheet', contact_sheet(names=ONLY_))
    elif STEP_ == 'export':
        res, dropped, after, info = export()
        print('export', res, 'dropped', dropped, 'materials after', after)
        nodes = info.pop('nodes')
        print(info)
        for nd in nodes:
            print(nd)
    elif STEP_ == 'contract':
        print(contract_checks())
    elif STEP_ == 'save':
        print('saved', save())
    elif STEP_ == 'all':
        for nm, inf in build():
            print('built', nm, inf)
        bad = [d for d in report() if not d['ok_budget'] or d['floating'] or d['inverted'] or d['degenerate']]
        print('qa problems', [(d['name'], d['tris'], d['floating'], d['inverted'], d['degenerate']) for d in bad])
        print('contract', contract_checks())
        print('sheet', contact_sheet()[0])
        res, dropped, after, info = export()
        print('export', res, 'dropped', dropped, {k: v for k, v in info.items() if k != 'nodes'})
        print('saved', save())
