"""Hauler 2500 - full-size crew-cab pickup truck, RWD-biased 4x4 (car #9 of Sunward Roads).

Rebuilds Cars/Car_hauler_2500 from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero image
and exports assets/imported/cars/hauler_2500.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\hauler_2500.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking), DEBUG (bool).

Spec: L 5.60 (front bumper -> hitch receiver), W 2.00 over the body (tow mirrors excluded), H 1.90 roof, wheelbase 3.55,
track 1.72 / 1.72, wheel R 0.40 (18" chrome 8-spoke rims, 275-wide all-terrain tyres with raised tread blocks).
Original design (no real brand / model): crew cab (4 doors) + separate open load bed with a 3.5 cm cab/bed gap.
Two separate shells:
  * cab + front end: kit LoftBody (slab sides, crisp shoulder crease at z 1.30 running nose -> tailgate, flat hood
    with a low raised centre panel, tall blunt nose, ~45 deg windscreen, flat roof, near-vertical rear window);
  * load bed: a "wall loft" of rounded-rectangle rings (outer skin with the cab's exact side section so the character
    lines continue across the gap, black rail caps, bed-liner inner walls, ribbed floor, wheel-well humps, tailgate),
    rear wheel arch cut with the kit's boolean + bevelled lip.
Big chrome grille with three heavy bars and rectangular quad lamps, chrome wrap-around bumpers (rear step bumper with
step pads, plate recess and a receiver hitch), tall towing mirrors, 5 amber roof clearance lamps, running boards,
chrome tube bed rails, vertical tail lamps, sliding rear window, visible ladder frame / solid axles / leaf springs /
spare tyre underneath. Interior: 2 front seats + 3-seat rear bench, tall dash with a 4-dial binnacle, big 4-spoke
wheel, centre console, door cards. Default paint dark metallic charcoal #2F3337.
"""
import sys
import os
import math
import importlib

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender'))
import car_kit as ck  # noqa: E402
importlib.reload(ck)
import bmesh  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

CAR_ID = 'hauler_2500'
CAR_NAME = 'Hauler 2500'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
DEBUG = globals().get('DEBUG', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 3.55
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.775)
TRACK_F, TRACK_R = 1.72, 1.72
WHEEL_R, WHEEL_W = 0.400, 0.275
ARCH_R, ARCH_Z = 0.433, 0.407                  # ~3.3 cm gap at the sides, ~4 cm above the tyre
W_NOM = 1.000                                  # nominal half width used in the station table
X_SHIFT = 0.012                                # every section x is pulled in by this -> waist 0.988
HALF_W = W_NOM - X_SHIFT                       # body half width at the waist (doors / bed sides)
FLARE_X = 1.000                                # body-colour wheel-arch flares -> W 2.00 overall
NOSE_Y, TAIL_Y = 2.648, -0.950                 # cab shell cap poles (fascia / cab back wall)
Y_BED_F, Y_BED_R = -0.985, -2.775              # load bed outer front wall / tailgate face (3.5 cm cab gap)
Y_FBUMP = 2.700                                # front bumper face (plate frame -> 2.705)
Y_RBUMP = -2.865                               # rear step bumper face
Y_HITCH = -2.895                               # receiver hitch end -> overall length 5.60

# ---------------------------------------------------------------- cab shell stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs), K3 waist / widest
# (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr), K8 crown (zc).
# Hood stations: K5 = hood shut line on the sloped fender top, K6 = hood point, K7 (rail + bulge) = edge of the raised
# centre panel, K8 = hood centre. Cab back: the roof folds down over 4 cm into the near-vertical rear window.
CAB = dict(zb=0.500, wb=0.700, zs=0.565, ws=0.960, zw=0.940, ww=W_NOM, zh=1.275, wh=0.990, zg=1.362, wg=0.948,
           zr=1.845, wr=0.845, zc=1.900, rail=0.075, bulge=0.0)
HOOD = dict(zb=0.505, wb=0.690, zs=0.570, ws=0.960, zw=0.940, ww=W_NOM, zh=1.275, wh=0.990, zg=1.335, wg=0.885,
            zr=1.345, wr=0.570, zc=1.372, rail=0.075, bulge=0.013)


def cab(**kw):
    d = dict(CAB)
    d.update(kw)
    return d


def hood(**kw):
    d = dict(HOOD)
    d.update(kw)
    return d


Y_HEADER = 0.640          # windscreen header
Y_COWL = 1.080            # windscreen base
Y_SAIL = 0.985            # front door glass front edge (black mirror sail ahead of it)
Y_BPIL = (0.050, 0.120)   # black B-pillar
Y_QTR = -0.790            # rear door glass rear edge (base y of the slanted grid line)
Y_ROOF_END = -0.895       # roof rear edge (fold starts)

S = [
    # ---- cab back: roof folds into the rear window, plan-view corner rounding
    dict(y=-0.937, zb=0.508, wb=0.640, zs=0.570, ws=0.918, zw=0.940, ww=0.958, zh=1.271, wh=0.948, zg=1.355,
         wg=0.908, zr=1.364, wr=0.800, zc=1.370, rail=0.130, bulge=0.0),
    dict(y=-0.925, zb=0.505, wb=0.665, zs=0.568, ws=0.940, zw=0.940, ww=0.980, zh=1.273, wh=0.970, zg=1.358,
         wg=0.928, zr=1.545, wr=0.822, zc=1.570, rail=0.150),
    dict(y=-0.910, zb=0.502, wb=0.690, zs=0.566, ws=0.953, zw=0.940, ww=0.993, zh=1.275, wh=0.983, zg=1.361,
         wg=0.941, zr=1.788, wr=0.838, zc=1.830, rail=0.160),
    cab(y=Y_ROOF_END, sharp=dict(zc=0.7, zr=0.7)),
    # ---- cabin: slab sides, flat roof
    cab(y=-0.600),
    cab(y=0.000),
    cab(y=Y_HEADER, sharp=dict(zc=0.6, zr=0.6, wr=0.3)),
    # ---- raked windscreen (~45 deg) down to the cowl
    cab(y=Y_COWL, zg=1.364, wg=0.946, zr=1.372, wr=0.925, zc=1.375, sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- cowl -> flat hood with a low raised centre panel
    hood(y=1.135, zb=0.503, zg=1.349, wg=0.905, zr=1.358, wr=0.760, zc=1.374, bulge=0.007),
    hood(y=1.230),
    hood(y=YF),
    hood(y=2.300),
    # ---- tall blunt nose: plan-view corner rounding over the last 18 cm
    hood(y=2.470, zb=0.520, wb=0.660, zs=0.580, ws=0.956, ww=0.996, wh=0.986, zg=1.333, wg=0.880, zr=1.343,
         wr=0.566, zc=1.369),
    hood(y=2.560, zb=0.535, wb=0.645, zs=0.588, ws=0.944, ww=0.984, zh=1.273, wh=0.974, zg=1.329, wg=0.870,
         zr=1.339, wr=0.560, zc=1.364),
    hood(y=2.600, zb=0.545, wb=0.630, zs=0.594, ws=0.924, ww=0.964, zh=1.269, wh=0.954, zg=1.323, wg=0.855,
         zr=1.333, wr=0.552, zc=1.357),
    hood(y=2.626, zb=0.552, wb=0.610, zs=0.600, ws=0.898, ww=0.938, zh=1.263, wh=0.928, zg=1.315, wg=0.835,
         zr=1.325, wr=0.540, zc=1.348),
]

for _s in S:                                   # pull every section in by X_SHIFT (room for the arch flares)
    for _k in ('wb', 'ws', 'ww', 'wh', 'wg', 'wr'):
        if _k in _s:
            _s[_k] = round(_s[_k] - X_SHIFT, 4)
KEY_SHARP = (0, 0.7, 0.6, 0.85, 0.85, 0.55, 0.55, 0.0, 0)    # K3 creased: waist character line
for _s in S:                                   # hood stations: creases along the raised centre panel edges
    if _s.get('bulge', 0.0) > 0.0:
        _s['ks'] = {6: 0.55, 7: 0.6}
NOSE = dict(y=NOSE_Y, z=0.950, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8)
TAIL = dict(y=TAIL_Y, z=0.940, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8)
BANDS = [3, 3, 3, 4, 2, 4, 2, 5]
WARPS = [dict(y=Y_QTR, t=(5.0, 6.0), y_t=(-0.815, -0.757), margin=0.095)]   # rear door glass edge leans forward


def _rear_glass_range(z_top=1.790, z_bot=1.440):
    """Base-y range of the fold where the roof crown passes z_top .. z_bot (rear window between them)."""
    tmp = ck.LoftBody(stations=S, band_segments=BANDS, key_sharp=KEY_SHARP, nose=NOSE, tail=TAIL)
    ys = [Y_ROOF_END - 0.0005 * k for k in range(0, 85)]
    zc = [tmp.params_at(y)['zc'] for y in ys]

    def find(zt):
        for a, b, za, zb in zip(ys[:-1], ys[1:], zc[:-1], zc[1:]):
            if (za - zt) * (zb - zt) <= 0 and abs(zb - za) > 1e-9:
                return a + (b - a) * (zt - za) / (zb - za)
        raise RuntimeError('rear glass z %.3f not in the fold' % zt)
    return round(find(z_bot), 4), round(find(z_top), 4)


YG0, YG1 = _rear_glass_range()

RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),        # windscreen
    dict(bands=(5, 5), y=(Y_QTR, Y_SAIL), role='glass'),           # front + rear door glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),           # mirror sail
    dict(bands=(5, 5), y=Y_BPIL, role='trim'),                     # B-pillar (black)
    dict(bands=(7, 7), y=(YG0, YG1), role='glass'),                # sliding rear window
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.050), role='trim'),   # scuttle / cowl panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=BANDS,
    key_sharp=KEY_SHARP,
    rules=RULES,
    default_roles={0: 'under'},
    nose=NOSE,
    tail=TAIL,
    step=0.070,
    rail=0.075,
    warps=WARPS,
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.620)]            # front only (the rear arch is cut into the bed)
BED_ARCH = dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.700)
INNER = dict(y=(-0.937, 1.060), d=0.035, dy_ramp=(-0.860, -0.937), center_z=1.20,
             band_mats={0: 'InteriorDark', 1: 'InteriorDark', 2: 'InteriorDark', 3: 'Interior', 4: 'InteriorDark',
                        5: 'Interior', 6: 'Headliner', 7: 'Headliner'})

# ---------------------------------------------------------------- load bed (wall loft of rounded-rectangle rings)
Z_FLOOR = 0.900                 # bed floor (load height)
Z_BED_UNDER = 0.872             # underside of the floor slab (2.8 cm above the arch top)
BED_RC_F, BED_RC_R = 0.045, 0.055
BED_NA, BED_NX, BED_NY = 5, 8, 14       # ring resolution: corner arc segments, front/rear edge, side segments

# ---------------------------------------------------------------- cockpit
EYE = Vector((-0.450, 0.020, 1.620))        # driver eye point (LHD, driver on the left = -X), high truck seating
HUB = Vector((-0.450, 0.500, 1.220))        # steering wheel hub
COLUMN_TILT = 24.0                          # deg, column descends toward the dash
SW_R = 0.200                                # big 4-spoke steering wheel
D_IN = INNER['d']
SEAT_Z = 0.800                              # front seat base (runners stay above the cabin floor at 0.535)
SEAT_Y = (0.300, -0.220)
SEAT_RECLINE, SEAT_BACK_H = 16.0, 0.860
BENCH_Y, BENCH_Z, BENCH_RECLINE, BENCH_BACK_H, BENCH_W = (-0.360, -0.700), 0.820, 13.0, 0.620, 1.420


# =====================================================================================================
# helpers
# =====================================================================================================
def isolate(on=True):
    """Hide the other cars (view-layer exclude only, no datablock change) while looking / rendering."""
    import bpy
    root = bpy.context.view_layer.layer_collection.children.get('SUNWARD_GODOT')
    lc_cars = root.children.get('Cars') if root is not None else None
    if lc_cars is None:
        return []
    out = []
    for lc in lc_cars.children:
        if lc.name != 'Car_' + CAR_ID:
            lc.exclude = bool(on)
            out.append(lc.name)
    return out


def snap_pts(S_, spec):
    out = []
    for view, a, b in spec:
        p = S_.snap(view, a, b)
        if p is None:
            raise RuntimeError('snap miss %s %s %s' % (view, a, b))
        out.append(p)
    return out


def lathe_y(profile, segs, mats, center, sign=1):
    """Revolve a profile [(a, r)] about the Y axis (a measured along sign*Y), placed at `center`."""
    p = ck.revolve(profile, segs, mats)
    M = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(90.0 * sign), 4, 'Z')
    return p.transformed(M)


def body_x(y, z):
    """x of the outer cab side (right) at (y, z) from the analytic loft section."""
    h = BODY.half(y)
    best = None
    for a, b in zip(h[:-1], h[1:]):
        if (a.y - z) * (b.y - z) <= 0 and abs(b.y - a.y) > 1e-9 and max(a.x, b.x) > 0.3:
            t = (z - a.y) / (b.y - a.y)
            x = a.x + (b.x - a.x) * t
            best = x if best is None else max(best, x)
    return best if best is not None else HALF_W


def inner_x(y, z, d=None):
    """x of the inner cabin surface (right side) at (y, z), from the analytic loft section."""
    h = BODY.half(y, inset=D_IN if d is None else d)
    best = None
    for a, b in zip(h[:-1], h[1:]):
        if (a.y - z) * (b.y - z) <= 0 and abs(b.y - a.y) > 1e-9 and a.x > 0.3:
            t = (z - a.y) / (b.y - a.y)
            x = a.x + (b.x - a.x) * t
            best = x if best is None else max(best, x)
    return best


def frame_box(c, axis_u, axis_v, nrm, w, h, bar, depth, mat, back_mat=None, back_off=0.002):
    """Rectangular recess frame (4 bars) centred at c on a flat face with outward normal nrm (number plates)."""
    P = ck.Part()
    u, v, n = Vector(axis_u), Vector(axis_v), Vector(nrm)
    for (a, b) in (((-w / 2, h / 2), (w / 2, h / 2)), ((-w / 2, -h / 2), (w / 2, -h / 2))):
        p0 = c + u * a[0] + v * a[1] + n * (depth / 2)
        p1 = c + u * b[0] + v * b[1] + n * (depth / 2)
        P.extend(ck.box_between(p0 - u * bar / 2, p1 + u * bar / 2, bar, depth, mat, up=tuple(n)))
    for sx in (-1, 1):
        p0 = c + u * (sx * w / 2) + v * (-h / 2) + n * (depth / 2)
        p1 = c + u * (sx * w / 2) + v * (h / 2) + n * (depth / 2)
        P.extend(ck.box_between(p0, p1, bar, depth, mat, up=tuple(n)))
    if back_mat:
        P.extend(quad(c + n * back_off, u, v, w, h, n, back_mat))
    return P


def quad(c, u, v, w, h, n, mat):
    """Single rectangle centred at c spanned by unit vectors u, v (w x h), facing n."""
    q = ck.Part()
    u, v, n = Vector(u), Vector(v), Vector(n)
    ids = [q.vert(c + u * (sx * w / 2) + v * (sy * h / 2)) for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    q.face(ids, mat)
    if q.face_normal(0).dot(n) < 0:
        q.f[0] = tuple(reversed(q.f[0]))
    return q


def plan_path(y_face, y_end, x_side, r, n_arc=8, n_face=12, n_side=3, z=0.0):
    """Bumper plan path travelling counter-clockwise seen from above (so sweep_path's u = outward):
    y_face > y_end -> front bumper (right side -> front face -> left side); y_face < y_end -> rear bumper
    (left side -> rear face -> right side). Corner arcs of radius r join the face line and the side lines."""
    pts = []
    if y_face > y_end:      # front
        for k in range(n_side):
            pts.append(Vector((x_side, ck.lerp(y_end, y_face - r, k / n_side), z)))
        c = (x_side - r, y_face - r)
        for k in range(n_arc + 1):
            a = math.radians(90.0 * k / n_arc)
            pts.append(Vector((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z)))
        for k in range(1, n_face):
            pts.append(Vector((ck.lerp(x_side - r, -x_side + r, k / n_face), y_face, z)))
        c = (-x_side + r, y_face - r)
        for k in range(n_arc + 1):
            a = math.radians(90.0 + 90.0 * k / n_arc)
            pts.append(Vector((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z)))
        for k in range(1, n_side + 1):
            pts.append(Vector((-x_side, ck.lerp(y_face - r, y_end, k / n_side), z)))
    else:                   # rear
        for k in range(n_side):
            pts.append(Vector((-x_side, ck.lerp(y_end, y_face + r, k / n_side), z)))
        c = (-x_side + r, y_face + r)
        for k in range(n_arc + 1):
            a = math.radians(180.0 + 90.0 * k / n_arc)
            pts.append(Vector((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z)))
        for k in range(1, n_face):
            pts.append(Vector((ck.lerp(-x_side + r, x_side - r, k / n_face), y_face, z)))
        c = (x_side - r, y_face + r)
        for k in range(n_arc + 1):
            a = math.radians(270.0 + 90.0 * k / n_arc)
            pts.append(Vector((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z)))
        for k in range(1, n_side + 1):
            pts.append(Vector((x_side, ck.lerp(y_face + r, y_end, k / n_side), z)))
    return pts


def drop_slivers(part, min_area=2e-8):
    """Remove near-zero-area faces (e.g. the last segment of a resampled ribbon) from a Part."""
    keep_f, keep_m = [], []
    for fi, (f, m) in enumerate(zip(part.f, part.m)):
        if part.face_normal(fi).length * 0.5 >= min_area:
            keep_f.append(f)
            keep_m.append(m)
    part.f, part.m = keep_f, keep_m
    return part


def bm_to_part(bm, keys):
    """BMesh -> Part with material keys (keys: material index -> key)."""
    P = ck.Part()
    bm.verts.index_update()
    P.v = [v.co.copy() for v in bm.verts]
    for f in bm.faces:
        P.f.append(tuple(v.index for v in f.verts))
        P.m.append(keys.get(f.material_index, 'Paint'))
    return P


# =====================================================================================================
# load bed
# =====================================================================================================
def cab_side_samples(y=-0.600):
    """(t, x, z) samples of the cab's right side section from the sill (t=2) to the glass base (t=5)."""
    K, Sh = BODY.keys_at(y)
    Tin, Tout = ck._section_tangents(K, Sh)
    out = []
    n = 300
    for k in range(n + 1):
        t = 2.0 + 3.0 * k / n
        p = ck._section_eval(K, Tin, Tout, t)
        out.append((t, p.x, p.y))
    return out


def _x_at_z(samples, z):
    for (t0, x0, z0), (t1, x1, z1) in zip(samples[:-1], samples[1:]):
        if (z0 - z) * (z1 - z) <= 0 and abs(z1 - z0) > 1e-9:
            return x0 + (x1 - x0) * (z - z0) / (z1 - z0)
    return samples[0][1] if z < samples[0][2] else samples[-1][1]


def bed_levels():
    """Cross-section of the bed wall as levels (dx, dyF, dyR, z, material to the next level): inset of the ring
    from the outer plan outline at the sides / front wall / tailgate. Outer skin = the cab's exact side section,
    so the shoulder crease and the beltline continue across the cab/bed gap."""
    sm = cab_side_samples()

    def dsk(z):
        return HALF_W - _x_at_z(sm, z)

    def at_t(t):
        for (tt, x, z) in sm:
            if tt >= t - 1e-9:
                return HALF_W - x, z
        return HALF_W - sm[-1][1], sm[-1][2]
    L = []

    def same(d, z, m):
        L.append((d, d, d, z, m))
    same(0.190, Z_BED_UNDER, 'Underbody')          # underside of the floor slab (bottom cap inside this ring)
    same(0.046, Z_BED_UNDER, 'Underbody')
    same(0.036, 0.655, 'Underbody')                # inner face of the side skin
    same(0.027, 0.627, 'Paint')                    # hemmed lower edge
    d0 = dsk(0.650)
    same(d0 + 0.009, 0.622, 'Paint')
    same(d0 + 0.002, 0.633, 'Paint')
    for z in (0.650, 0.720, 0.790, 0.860, 0.910):
        same(dsk(z), z, 'Paint')
    d3, z3 = at_t(3.0)                              # waist crease (K3)
    same(d3, z3, 'Paint')
    for z in (0.975, 1.050, 1.125, 1.190, 1.240):
        same(dsk(z), z, 'Paint')
    for t in (4.0, 4.30, 4.62):
        d, z = at_t(t)
        same(d, z, 'Paint')
    d5, z5 = at_t(5.0)                              # glass base of the cab -> bed rail top outer edge
    same(d5, z5, 'Trim')                            # black rail caps from here
    same(d5 + 0.006, z5 + 0.007, 'Trim')
    same(d5 + 0.016, z5 + 0.012, 'Trim')
    L.append((0.122, 0.072, 0.084, z5 + 0.012, 'Trim'))
    L.append((0.132, 0.079, 0.091, z5 + 0.006, 'Trim'))
    L.append((0.137, 0.083, 0.095, z5 - 0.006, 'BedLiner'))
    L.append((0.141, 0.086, 0.098, z5 - 0.030, 'BedLiner'))
    L.append((0.147, 0.090, 0.103, Z_FLOOR + 0.024, 'BedLiner'))
    L.append((0.152, 0.094, 0.107, Z_FLOOR + 0.005, 'BedLiner'))
    L.append((0.159, 0.100, 0.113, Z_FLOOR, None))   # floor ring (top cap inside it)
    return L


def rrect_ring(xh, y0, y1, rF, rR, z, na=BED_NA, nx=BED_NX, ny=BED_NY):
    """Rounded rectangle x in [-xh, xh], y in [y0, y1] (front corners rF, rear corners rR), counter-clockwise from
    above, starting on the right side. Same vertex count for every size -> rings loft into clean quads."""
    corners = [((xh - rF, y1 - rF), rF, 0.0), ((-xh + rF, y1 - rF), rF, 90.0),
               ((-xh + rR, y0 + rR), rR, 180.0), ((xh - rR, y0 + rR), rR, 270.0)]
    pts = []
    for ci, ((cx, cy), r, a0) in enumerate(corners):
        for k in range(na + 1):
            a = math.radians(a0 + 90.0 * k / na)
            pts.append(Vector((cx + r * math.cos(a), cy + r * math.sin(a), z)))
        (ncx, ncy), nr, na0 = corners[(ci + 1) % 4]
        a = math.radians(na0)
        p_end = pts[-1].copy()
        p_next = Vector((ncx + nr * math.cos(a), ncy + nr * math.sin(a), z))
        nseg = nx if ci in (0, 2) else ny
        for j in range(1, nseg):
            pts.append(p_end.lerp(p_next, j / nseg))
    return pts


def bed_ring(dx, dyF, dyR, z):
    rF = max(BED_RC_F - min(dx, dyF), 0.010)
    rR = max(BED_RC_R - min(dx, dyR), 0.010)
    return rrect_ring(HALF_W - dx, Y_BED_R + dyR, Y_BED_F - dyF, rF, rR, z)


BED_KEYS = {i: k for i, k in enumerate(ck.BODY_MATS)}
BED_KEYS[ck.BODY_MATS.index('Carbon')] = 'BedLiner'     # the Carbon slot carries the bed liner through the boolean


def build_bed(car):
    """Closed thick-walled bed tub (BMesh, BODY_MATS indices) with the rear wheel arches cut and lipped."""
    L = bed_levels()
    midx = {k: i for i, k in enumerate(ck.BODY_MATS)}
    midx['BedLiner'] = midx['Carbon']
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in bed_ring(dx, dyF, dyR, z)] for (dx, dyF, dyR, z, m) in L]
    n = len(rings[0])
    for k in range(len(rings) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            f = bm.faces.new((rings[k][j], rings[k][j2], rings[k + 1][j2], rings[k + 1][j]))
            f.material_index = midx[L[k][4]]
    fb = bm.faces.new(rings[0])
    fb.material_index = midx['Underbody']
    ft = bm.faces.new(list(rings[-1]))
    ft.material_index = midx['BedLiner']
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    vol = sum(f.calc_center_median().dot(f.normal) * f.calc_area() for f in bm.faces)
    if vol < 0:
        for f in bm.faces:
            f.normal_flip()
    bm = ck._boolean_arches(car, bm, [BED_ARCH], midx['Underbody'], 'EXACT')
    ck._bevel_arch_lips(bm, [BED_ARCH], {k: i for i, k in enumerate(ck.BODY_MATS)}, 0.009, 2)
    bm.normal_update()
    return bm


def bed_inner_x(z):
    """x of the bed's inner side wall (right) at height z (from the last 5 levels = the bed-liner wall)."""
    pts = sorted([(l[3], HALF_W - l[0]) for l in bed_levels()[-5:]])
    for (z0, x0), (z1, x1) in zip(pts[:-1], pts[1:]):
        if z0 <= z <= z1:
            return x0 + (x1 - x0) * (z - z0) / max(z1 - z0, 1e-9)
    return pts[0][1] if z < pts[0][0] else pts[-1][1]


# =====================================================================================================
# build
# =====================================================================================================
WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=18, spokes=8, style='single', segs=36, rim_segs=36,
                  spoke_w=(0.060, 0.022), spoke_thick=0.026, spoke_dish=0.042, hub_r=0.080, nuts=8,
                  tyre='tall', blocks=dict(n=26, h=0.013),
                  disc_r=0.185, caliper_angle=150.0, caliper_span=46.0)


def make_materials():
    paint = (0.0284, 0.0331, 0.0382)          # #2F3337 (sRGB) -> linear
    mats = ck.default_materials(paint=paint, paint_metallic=0.55, paint_rough=0.30, paint_coat=0.85,
                                rim=(0.80, 0.81, 0.83), rim_metallic=1.0, rim_rough=0.10,
                                caliper=(0.090, 0.090, 0.095),
                                interior=(0.160, 0.075, 0.035), interior_dark=(0.018, 0.017, 0.016))
    mats['Glass'] = dict(base=(0.008, 0.010, 0.012), roughness=0.03, alpha=0.30, double_sided=True)
    mats['BedLiner'] = dict(base=(0.030, 0.030, 0.032), roughness=0.92)
    mats['Plastic'] = dict(base=(0.026, 0.026, 0.028), roughness=0.78)
    mats['Steel'] = dict(base=(0.060, 0.060, 0.064), metallic=0.65, roughness=0.48)
    mats['Alu'] = dict(base=(0.60, 0.61, 0.63), metallic=1.0, roughness=0.36)
    mats['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.35)
    mats['Headliner'] = dict(base=(0.30, 0.285, 0.26), roughness=0.85)
    mats['Screen'] = dict(base=(0.010, 0.014, 0.020), roughness=0.25, emission=(0.10, 0.20, 0.34), strength=0.8)
    mats['ScreenMap'] = dict(base=(0.02, 0.05, 0.03), roughness=0.3, emission=(0.12, 0.42, 0.22), strength=0.7)
    return mats


def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials())
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Glass', shell.glass)
    car.add('Interior', shell.inner)
    bed_bm = build_bed(car)
    car.bed_surface = ck.Surface(bed_bm)
    car.add('Body', bm_to_part(bed_bm, BED_KEYS))
    if STAGE != 'body':
        body_details(car, shell.surface, car.bed_surface)
        interior(car)
        ck.add_wheels(car, WHEEL_SPEC, axles=dict(front=(YF, TRACK_F / 2), rear=(YR, TRACK_R / 2)))
        car.socket('Socket_CamHood', (0.0, 1.250, 1.560))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, Y_FBUMP + 0.120, 0.700))
    car.finalize()
    return car, shell


# =====================================================================================================
# exterior details
# =====================================================================================================
FB_PROF = [(-0.150, 0.470), (-0.012, 0.470), (0.000, 0.488), (0.004, 0.560), (-0.010, 0.574), (-0.010, 0.588),
           (0.006, 0.602), (0.008, 0.700), (0.000, 0.724), (-0.012, 0.742), (-0.150, 0.742)]
RB_PROF = [(-0.150, 0.415), (-0.012, 0.415), (0.000, 0.432), (0.005, 0.520), (0.000, 0.606), (-0.010, 0.625),
           (-0.150, 0.625)]


def front_details(car, S_, R, C, LH, AM):
    D = ck.densify
    yF = S_.snap('front', 0.0, 1.00).y
    # ---- big chrome grille: heavy chrome surround, dark insert, vertical slats, three heavy chrome bars
    GX, GZ0, GZ1 = 0.600, 0.770, 1.235
    gr = D(ck.fillet_poly([(-GX, GZ0), (GX, GZ0), (GX, GZ1), (-GX, GZ1)], 0.045, n=3), 0.06)
    C.extend(S_.patch(gr, 'front', offset=0.0015, depth=0.005, res=0.10, mat='Grille', smooth=False))
    C.extend(S_.rim(gr, 'front', width=0.042, offset=0.020, depth=0.006, mat='Chrome', smooth=False))
    for k in range(19):
        x = -0.540 + 0.060 * k
        yy = S_.snap('front', x, 1.0).y
        C.extend(ck.box_between((x, yy + 0.007, GZ0 + 0.012), (x, yy + 0.007, GZ1 - 0.012), 0.010, 0.012, 'Trim',
                                up=(0, 1, 0)))
    for zb in (0.925, 1.080):
        yy = S_.snap('front', 0.0, zb).y
        prof = [(yy - 0.004, zb - 0.026), (yy + 0.012, zb - 0.026), (yy + 0.022, zb - 0.016), (yy + 0.026, zb),
                (yy + 0.022, zb + 0.016), (yy + 0.012, zb + 0.026), (yy - 0.004, zb + 0.026)]
        xs = [-0.585, -0.575, 0.575, 0.585]
        profs = []
        for x in xs:
            sh = 0.006 if abs(x) > 0.58 else 0.0
            profs.append([(y - sh, z + (sh if z < zb else -sh) * 0.8) for (y, z) in prof])
        C.extend(ck.sweep_axis('x', xs, profs, 'Chrome'))
    # ---- rectangular quad headlamps (chrome bezel, chrome reflector, two projector lenses, DRL bar)
    lamp = D(ck.fillet_poly([(0.656, 1.022), (0.928, 1.022), (0.928, 1.228), (0.656, 1.228)], 0.018, n=3), 0.03)
    R.extend(S_.patch(lamp, 'front', offset=0.002, depth=0.006, res=0.035, mat='Grille', smooth=False))
    R.extend(S_.rim(lamp, 'front', width=0.012, offset=0.010, depth=0.005, mat='Chrome', smooth=False))
    refl = D(ck.fillet_poly([(0.668, 1.068), (0.916, 1.068), (0.916, 1.216), (0.668, 1.216)], 0.012, n=2), 0.03)
    R.extend(S_.patch(refl, 'front', offset=0.0035, depth=0.003, res=0.0, mat='Chrome', smooth=False))
    cs = []
    for x in (0.728, 0.856):
        z = 1.140
        yl = S_.snap('front', x, z).y + 0.003
        R.extend(lathe_y([(0.000, 0.052), (0.006, 0.050), (0.004, 0.045), (-0.006, 0.040)], 24, 'Chrome', (x, yl, z)))
        LH.extend(lathe_y([(0.001, 0.0405), (0.010, 0.036), (0.017, 0.024), (0.020, 0.0)], 24, 'HeadlightLens',
                          (x, yl, z)))
        cs.append(Vector((x, yl + 0.02, z)))
    drl = [S_.snap('front', x, 1.043) for x in (0.672, 0.75, 0.83, 0.912)]
    LH.extend(S_.line3d(drl, width=0.014, offset=0.0060, mat='HeadlightLens', step=0.03))
    hc = (cs[0] + cs[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))
    # ---- amber indicators below the lamps, front side markers
    ind = D(ck.fillet_poly([(0.660, 0.945), (0.924, 0.945), (0.924, 0.995), (0.660, 0.995)], 0.010, n=2), 0.03)
    R.extend(S_.patch(ck.offset_poly(ind, 0.007), 'front', offset=0.002, depth=0.005, res=0.0, mat='Trim',
                      smooth=False))
    R.extend(S_.patch(ind, 'front', offset=0.0050, depth=0.004, res=0.0, mat='Amber', smooth=False))
    mk = D(ck.fillet_poly([(2.470, 1.120), (2.560, 1.120), (2.560, 1.155), (2.470, 1.155)], 0.008, n=2), 0.02)
    R.extend(S_.patch(ck.offset_poly(mk, 0.005), 'right', offset=0.002, depth=0.005, res=0.0, mat='Trim',
                      smooth=False))
    R.extend(S_.patch(mk, 'right', offset=0.0045, depth=0.004, res=0.0, mat='Amber', smooth=False))
    # ---- black corner vents with a chrome surround below the indicators
    vent = D(ck.fillet_poly([(0.676, 0.800), (0.912, 0.800), (0.912, 0.892), (0.676, 0.892)], 0.014, n=2), 0.03)
    R.extend(S_.patch(vent, 'front', offset=0.0015, depth=0.005, res=0.0, mat='Grille', smooth=False))
    R.extend(S_.rim(vent, 'front', width=0.010, offset=0.008, depth=0.005, mat='Chrome', smooth=False))
    for zv in (0.830, 0.862):
        yy = S_.snap('front', 0.794, zv).y
        R.extend(ck.box_between((0.684, yy + 0.006, zv), (0.904, yy + 0.006, zv), 0.010, 0.010, 'Trim'))
    # ---- hood shut line across the nose
    C.extend(S_.line(D([(-0.925, 1.268), (0.925, 1.268)], 0.02, closed=False), 'front', offset=0.0015, smooth=False,
                     step=0.025))

    # ---- chrome two-tier front bumper wrapping round the corners to the wheel arches
    path = plan_path(Y_FBUMP - 0.008, 2.300, 0.990, 0.200)
    C.extend(ck.sweep_path(path, FB_PROF, 'Chrome'))
    # black lower air dam with tow hooks
    path = plan_path(Y_FBUMP - 0.040, 2.430, 0.922, 0.180)
    C.extend(ck.sweep_path(path, [(-0.120, 0.395), (-0.006, 0.395), (0.000, 0.405), (0.000, 0.474),
                                  (-0.120, 0.474)], 'Plastic'))
    for sx in (-1, 1):
        C.extend(ck.torus((sx * 0.420, Y_FBUMP - 0.070, 0.385), (1, 0, 0), 0.032, 0.010, 'Steel', nu=12, nv=5))
    # plate recess on the bumper centre, fog lamps in the lower tier
    C.extend(frame_box(Vector((0.0, Y_FBUMP - 0.005, 0.600)), (1, 0, 0), (0, 0, 1), (0, 1, 0), 0.330, 0.170, 0.012,
                       0.010, 'Trim', back_mat='Grille', back_off=0.009))
    y_low = Y_FBUMP - 0.008 + 0.002                 # lower-tier bumper face at the fog lamp height
    for sx in (1,):
        x = 0.700 * sx
        R.extend(ck.box_between((x - 0.080, y_low + 0.001, 0.524), (x + 0.080, y_low + 0.001, 0.524), 0.010, 0.060,
                                'Grille'))
        LH.extend(ck.disc((x - 0.035, y_low + 0.0068, 0.524), (0, 1, 0), 0.022, 'HeadlightLens', n=16))
        LH.extend(ck.disc((x + 0.035, y_low + 0.0068, 0.524), (0, 1, 0), 0.022, 'HeadlightLens', n=16))
        R.extend(ck.disc((x - 0.035, y_low + 0.0061, 0.524), (0, 1, 0), 0.0265, 'Chrome', n=16))
        R.extend(ck.disc((x + 0.035, y_low + 0.0061, 0.524), (0, 1, 0), 0.0265, 'Chrome', n=16))
    return yF


def hood_details(S_, R, C, AM):
    # ---- hood shut lines along the sloped fender tops
    edge = [BODY.point(y, 5.0, 1) for y in (Y_COWL + 0.07, 1.35, 1.70, 2.05, 2.40, 2.56, 2.610)]
    R.extend(S_.line3d(edge, step=0.04))
    # ---- washer jets, wipers parked at the windscreen base
    for sx in (-1, 1):
        p = S_.snap('top', sx * 0.26, Y_COWL + 0.13)
        C.extend(ck.ellipsoid(p + Vector((0, 0, 0.004)), (0.010, 0.016, 0.007), 'Trim', nu=8, nv=5))
    F = S_.frame('front')
    for (x0, x1, px) in ((-0.78, -0.08, -0.40), (-0.02, 0.70, 0.34)):
        l0, n0 = S_.hit(F, x0, 1.415)
        l1, n1 = S_.hit(F, x1, 1.415)
        a0, a1 = l0 + n0 * 0.010, l1 + n1 * 0.010
        C.extend(ck.box_between(a0, a1, 0.013, 0.014, 'Trim', up=tuple(n0)))
        pivot = S_.snap('top', px, Y_COWL + 0.030) + Vector((0, 0, 0.010))
        mid = (a0 + a1) / 2 + n0 * 0.006
        C.extend(ck.box_between(pivot, mid, 0.012, 0.008, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.016, 0.016, 0.010), 'Trim', nu=10, nv=6))
    # ---- five amber roof clearance lamps above the windscreen
    for x in (-0.36, -0.18, 0.0, 0.18, 0.36):
        p = S_.snap('top', x, Y_HEADER - 0.055)
        C.extend(ck.box_between(p + Vector((0, -0.002, 0.002)), p + Vector((0, 0.002, 0.002)), 0.082, 0.010, 'Trim'))
        AM.extend(ck.ellipsoid(p + Vector((0, 0, 0.006)), (0.034, 0.016, 0.013), 'Amber', nu=10, nv=6, exp=2.6))


def mirror(R):
    """Tall towing mirror on two arms from the door's front upper corner (right side)."""
    mc = Vector((1.125, 1.010, 1.500))
    rx, ry, rz = 0.095, 0.052, 0.185

    def flat_back(q):
        if q.y < -0.55 * ry:
            q.y = -0.55 * ry
        return q
    head = ck.ellipsoid(mc, (rx, ry, rz), 'Plastic', nu=16, nv=10, exp=4.6, deform=flat_back)
    R.extend(head)
    mg = ck.Part()
    gp = ck.superellipse_pts(0.0, 0.0, 0.082, 0.168, e=5.0, n=24)
    cen = mg.vert(mc + Vector((0, -0.55 * ry - 0.0012, 0)))
    ring = [mg.vert(mc + Vector((p.x, -0.55 * ry - 0.0012, p.y))) for p in gp]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    # arms + base plate on the door
    for (zb_, zh_) in ((1.405, 1.625), (1.345, 1.395)):
        b = Vector((body_x(1.000, zb_) - 0.004, 1.000, zb_))
        R.extend(ck.box_between(b, Vector((mc.x - rx + 0.010, 1.008, zh_)), 0.030, 0.022, 'Plastic'))
    b = Vector((body_x(1.000, 1.375) - 0.002, 1.000, 1.375))
    R.extend(ck.box_between(b + Vector((0, -0.030, 0)), b + Vector((0, 0.040, 0)), 0.024, 0.110, 'Plastic',
                            up=(1, 0, 0)))


def side_details(car, S_, R, C, AM):
    D = ck.densify
    # ---- door shut lines (front door, B-pillar, rear door incl. the C-pillar edge), lower door edge
    R.extend(S_.line([(1.200, 0.598), (1.205, 0.95), (1.200, 1.275), (1.175, 1.345), (1.125, 1.364)], 'right',
                     step=0.03))
    R.extend(S_.line([(0.085, 0.598), (0.086, 0.95), (0.085, 1.364)], 'right', step=0.03))
    R.extend(S_.line([(-0.845, 0.598), (-0.847, 0.95), (-0.845, 1.362), (-0.818, 1.600), (-0.790, 1.836)], 'right',
                     step=0.03))
    R.extend(S_.line(D([(1.200, 0.598), (-0.845, 0.598)], 0.05, closed=False), 'right', smooth=False, step=0.05))
    # ---- chrome door handles in black recesses
    for yc in (0.300, -0.660):
        R.extend(S_.patch(D(ck.rrect_pts(yc, 1.212, 0.175, 0.042, 0.014, n=3), 0.02), 'right', offset=0.0050,
                          depth=0.006, res=0.0, mat='Trim', smooth=False))
        R.extend(S_.patch(D(ck.rrect_pts(yc, 1.212, 0.150, 0.022, 0.010, n=3), 0.02), 'right', offset=0.0105,
                          depth=0.006, res=0.0, mat='Chrome', smooth=False))
    # ---- chrome beltline strip under the door glass
    belt = [BODY.point(y, 4.93, 1) for y in (-0.780, -0.40, 0.0, 0.40, 0.80, 1.050)]
    R.extend(S_.line3d(belt, width=0.010, offset=0.0025, mat='Chrome', step=0.06))
    # ---- running boards: black step on three brackets with an aluminium tread strip
    xs0, zs0 = 0.900, 0.446
    R.extend(ck.box_between((xs0, -0.870, zs0), (xs0, 1.210, zs0), 0.165, 0.040, 'Plastic'))
    for k in range(3):
        xx = xs0 - 0.045 + 0.045 * k
        R.extend(ck.box_between((xx, -0.840, zs0 + 0.021), (xx, 1.180, zs0 + 0.021), 0.026, 0.004, 'Alu'))
    for y in (-0.600, 0.200, 0.950):
        R.extend(ck.box_between((0.515, y, 0.430), (xs0 - 0.060, y, zs0 - 0.004), 0.050, 0.028, 'Steel'))
    mirror(R)
    # ---- body-colour wheel-arch flares (front on the cab, rear on the bed side)
    sm = cab_side_samples()
    for (ya, xb, a0, a1) in ((YF, body_x, 24.0, 156.0), (YR, lambda yy, zz: _x_at_z(sm, zz), 30.0, 150.0)):
        R.extend(ck.arch_flare(ya, ARCH_Z, ARCH_R - 0.003, ARCH_R + 0.078, FLARE_X, xb, a0=a0, a1=a1, segs=22,
                               mat='Paint', embed=0.006))
    # ---- drip rails along the roof edges (body colour)
    rail = [BODY.point(y, 6.22, 1) for y in (Y_ROOF_END + 0.02, -0.40, 0.10, 0.50, Y_HEADER - 0.01)]
    R.extend(S_.line3d(rail, width=0.008, offset=0.0035, mat='Paint', step=0.08))


def bed_details(car, SB, R, C, LT, LB, LR, AM):
    D = ck.densify
    z5 = BODY.point(-0.600, 5.0, 1).z
    z_rail = z5 + 0.012
    # ---- tailgate: shut lines at the bed walls, handle
    for sx in (-1, 1):
        x = sx * 0.838
        C.extend(SB.line(D([(x, 0.630), (x, z5 - 0.004)], 0.03, closed=False), 'rear', smooth=False, step=0.03,
                         offset=0.0012))
        C.extend(SB.line(D([(x, Y_BED_R - 0.004), (x, Y_BED_R + 0.086)], 0.02, closed=False), 'top', smooth=False,
                         step=0.02, offset=0.0012))
    C.extend(SB.patch(D(ck.rrect_pts(0.0, 1.268, 0.300, 0.070, 0.018, n=3), 0.02), 'rear', offset=0.0045,
                      depth=0.006, res=0.0, mat='Trim', smooth=False))
    C.extend(SB.patch(D(ck.rrect_pts(0.0, 1.268, 0.230, 0.030, 0.012, n=3), 0.02), 'rear', offset=0.0100,
                      depth=0.006, res=0.0, mat='Chrome', smooth=False))
    # ---- vertical tail lamps on the bed-side ends: brake / tail / reverse
    house = D(ck.fillet_poly([(0.856, 0.905), (0.976, 0.905), (0.976, 1.310), (0.856, 1.310)], 0.016, n=2), 0.03)
    R.extend(SB.patch(house, 'rear', offset=0.002, depth=0.006, res=0.025, mat='Chrome', smooth=False))
    secs = [(1.170, 1.298, 'BrakeLens', LB), (1.032, 1.164, 'TaillightLens', LT), (0.918, 1.026, 'ReverseLens', LR)]
    for (z0, z1, mat, tgt) in secs:
        sec = D(ck.fillet_poly([(0.866, z0), (0.967, z0), (0.967, z1), (0.866, z1)], 0.008, n=2), 0.025)
        tgt.extend(SB.patch(sec, 'rear', offset=0.0050, depth=0.004, res=0.02, mat=mat, smooth=False))
    # rear side markers (red) on the bed sides
    mk = D(ck.fillet_poly([(-2.700, 1.175), (-2.630, 1.175), (-2.630, 1.207), (-2.700, 1.207)], 0.008, n=2), 0.02)
    R.extend(SB.patch(ck.offset_poly(mk, 0.005), 'right', offset=0.002, depth=0.005, res=0.0, mat='Trim',
                      smooth=False))
    LT.extend(SB.patch(mk, 'right', offset=0.0045, depth=0.004, res=0.0, mat='TaillightLens', smooth=False))
    # ---- moulded mud flaps behind both wheels
    R.extend(ck.box_between((0.912, -2.234, 0.330), (0.912, -2.234, 0.640), 0.150, 0.010, 'Plastic', up=(0, 1, 0)))
    R.extend(ck.box_between((0.905, 1.318, 0.340), (0.905, 1.318, 0.585), 0.140, 0.010, 'Plastic', up=(0, 1, 0)))
    # ---- fuel filler door on the left bed side, ahead of the rear wheel
    fuel = D(ck.rrect_pts(-1.165, 1.095, 0.170, 0.140, 0.020, n=3), 0.02)
    C.extend(SB.line(fuel, 'left', closed=True, smooth=False, step=0.012))
    loc, nor = SB.hit(SB.frame('left'), -1.105, 1.095)
    if loc is not None:
        C.extend(ck.box_between(loc + nor * 0.004, loc + nor * 0.004 + Vector((0, 0.020, 0)), 0.040, 0.008, 'Trim',
                                up=(1, 0, 0)))
    # ---- bed interior: ribbed floor, wheel-well humps, tie-down cleats
    y_in_f, y_in_r = Y_BED_F - 0.100, Y_BED_R + 0.113
    for x in (-0.44, -0.27, -0.10, 0.10, 0.27, 0.44):
        C.extend(ck.box_between((x, y_in_f - 0.015, Z_FLOOR + 0.004), (x, y_in_r + 0.015, Z_FLOOR + 0.004), 0.040,
                                0.014, 'BedLiner'))
    A, H, E = 0.460, 0.215, 3.0

    def hump_prof(a, h):
        pts = [(YR + a, Z_FLOOR - 0.012)]
        n = 14
        for k in range(n + 1):
            th = math.pi * k / n
            c, s = math.cos(th), math.sin(th)
            pts.append((YR + a * math.copysign(abs(c) ** (2 / E), c), Z_FLOOR + h * abs(s) ** (2 / E)))
        pts.append((YR - a, Z_FLOOR - 0.012))
        return pts
    xw = bed_inner_x(Z_FLOOR + 0.1) + 0.014
    hump = ck.sweep_axis('x', [0.615, 0.630, xw], [hump_prof(A - 0.012, H - 0.012), hump_prof(A, H), hump_prof(A, H)],
                         'BedLiner')
    R.extend(hump)
    for (y, sx) in ((y_in_f + 0.03, 1), (y_in_r - 0.03, 1)):
        x = bed_inner_x(1.27) - 0.006
        R.extend(ck.box_between((x, y - 0.035, 1.270), (x, y + 0.035, 1.270), 0.014, 0.022, 'Steel'))
    # ---- chrome tube bed rails on the black rail caps
    xr = HALF_W - 0.095
    y0, y1 = Y_BED_F - 0.130, Y_BED_R + 0.140
    hgt = 0.072
    tube = [Vector((xr, y0, z_rail - 0.004)), Vector((xr, y0 - 0.010, z_rail + hgt * 0.75)),
            Vector((xr, y0 - 0.045, z_rail + hgt)), Vector((xr, (y0 + y1) / 2, z_rail + hgt)),
            Vector((xr, y1 + 0.045, z_rail + hgt)), Vector((xr, y1 + 0.010, z_rail + hgt * 0.75)),
            Vector((xr, y1, z_rail - 0.004))]
    R.extend(ck.rod_path(ck.cr_resample(tube, closed=False, sub=3), 0.0145, 'Chrome', n=8))
    ym = (y0 + y1) / 2
    R.extend(ck.rod((xr, ym, z_rail - 0.004), (xr, ym, z_rail + hgt), 0.012, 'Chrome', n=8))
    for y in (y0, ym, y1):
        R.extend(ck.box_between((xr, y - 0.030, z_rail + 0.002), (xr, y + 0.030, z_rail + 0.002), 0.040, 0.008,
                                'Plastic'))


def rear_details(car, S_, SB, R, C, LT, LB, LR, LBC):
    # ---- cab back: third brake lamp on the roof fold, sliding rear window frames
    loc, nor = S_.hit(S_.frame('rear'), 0.0, 1.842)
    C.extend(ck.box_between((-0.160, loc.y - 0.004, 1.842), (0.160, loc.y - 0.004, 1.842), 0.016, 0.030, 'Trim'))
    LBC.extend(ck.box_between((-0.145, loc.y - 0.0125, 1.842), (0.145, loc.y - 0.0125, 1.842), 0.002, 0.016,
                              'BrakeLens'))
    for x in (-0.245, 0.245):
        a = S_.snap('rear', x, 1.470)
        b = S_.snap('rear', x, 1.785)
        n = Vector((0, -1, 0))
        C.extend(ck.box_between(a + n * 0.001 + Vector((0, 0, -0.006)), b + n * 0.001 + Vector((0, 0, 0.006)), 0.024,
                                0.010, 'Trim', up=(0, -1, 0)))
    # ---- chrome rear step bumper with black step pads, plate recess, receiver hitch
    path = plan_path(Y_RBUMP + 0.005, -2.550, 0.990, 0.160)
    C.extend(ck.sweep_path(path, RB_PROF, 'Chrome'))
    for (x0, x1) in ((-0.800, -0.520), (-0.200, 0.200), (0.520, 0.800)):
        C.extend(ck.box_between((x0, Y_RBUMP + 0.062, 0.628), (x1, Y_RBUMP + 0.062, 0.628), 0.096, 0.007, 'Plastic'))
    C.extend(frame_box(Vector((0.0, Y_RBUMP - 0.001, 0.519)), (1, 0, 0), (0, 0, 1), (0, -1, 0), 0.330, 0.170, 0.012,
                       0.010, 'Trim', back_mat='Grille', back_off=0.004))
    zh = 0.372
    C.extend(ck.box_between((0.0, -2.600, zh), (0.0, Y_HITCH, zh), 0.068, 0.068, 'Steel'))
    C.extend(ck.box_between((0.0, Y_HITCH + 0.026, zh), (0.0, Y_HITCH + 0.002, zh), 0.082, 0.082, 'Steel'))
    C.extend(quad(Vector((0.0, Y_HITCH - 0.0005, zh)), (1, 0, 0), (0, 0, 1), 0.050, 0.050, (0, -1, 0), 'Grille'))
    C.extend(ck.rod((-0.058, Y_HITCH + 0.045, zh), (0.058, Y_HITCH + 0.045, zh), 0.007, 'Alu', n=8))
    C.extend(ck.torus((0.062, Y_HITCH + 0.045, zh - 0.018), (1, 0, 0), 0.016, 0.004, 'Alu', nu=10, nv=4))
    for sx in (-1, 1):
        C.extend(ck.torus((sx * 0.110, -2.800, 0.345), (1, 0, 0), 0.022, 0.006, 'Steel', nu=10, nv=4))
    C.extend(ck.box_between((-0.500, -2.620, 0.420), (0.500, -2.620, 0.420), 0.070, 0.080, 'Steel'))
    for sx in (-1, 1):
        C.extend(ck.box_between((sx * 0.480, -2.620, 0.400), (sx * 0.480, -2.620, 0.620), 0.060, 0.060, 'Steel'))
    # ---- exhaust tip (right, under the bumper)
    p1 = Vector((0.620, -2.712, 0.360))
    C.extend(ck.tube(Vector((0.620, -2.520, 0.372)), p1, 0.040, 0.034, 'Chrome', 'Trim', n=20, inner_depth=0.06))
    car.socket('Socket_Exhaust', p1)


def underbody(C):
    """Ladder frame (kicked up over the rear axle), solid axles with diff housings, leaf springs, coil towers,
    driveshafts, transfer case, fuel tank, exhaust, spare tyre under the bed, rear wheelhouse liners."""
    rect = [(-0.035, -0.075), (0.035, -0.075), (0.035, 0.075), (-0.035, 0.075)]
    for sx in (-1, 1):
        pts = [Vector((sx * 0.480, y, z)) for (y, z) in ((2.520, 0.560), (1.500, 0.560), (1.440, 0.553),
                                                         (1.210, 0.432), (1.150, 0.425), (-0.880, 0.425),
                                                         (-0.945, 0.433), (-1.185, 0.592), (-1.250, 0.600),
                                                         (-2.700, 0.600))]
        C.extend(ck.sweep_path(pts, rect, 'Underbody'))
    for (ya, xd) in ((YF, 0.110), (YR, 0.0)):
        C.extend(ck.rod((-0.820, ya, WHEEL_R), (0.820, ya, WHEEL_R), 0.046, 'Steel', n=10))
        C.extend(ck.ellipsoid((xd, ya, 0.405), (0.150, 0.150, 0.140), 'Steel', nu=14, nv=8))
    for sx in (-1, 1):                                   # rear leaf springs
        pts = [Vector((sx * 0.480, YR + 0.640, 0.535)), Vector((sx * 0.480, YR + 0.300, 0.476)),
               Vector((sx * 0.480, YR, 0.462)), Vector((sx * 0.480, YR - 0.300, 0.476)),
               Vector((sx * 0.480, YR - 0.600, 0.535))]
        C.extend(ck.sweep_path(ck.cr_resample(pts, closed=False, sub=2), [(-0.033, -0.022), (0.033, -0.022),
                                                                          (0.033, 0.022), (-0.033, 0.022)], 'Steel'))
        C.extend(ck.rod((sx * 0.560, YF - 0.080, WHEEL_R + 0.040), (sx * 0.560, YF - 0.080, 0.600), 0.058, 'Steel',
                        n=10))                           # front coil towers
        C.extend(ck.rod((sx * 0.620, YR + 0.150, 0.420), (sx * 0.560, YR + 0.250, 0.600), 0.022, 'Steel', n=8))
    C.extend(ck.box_between((0.0, 0.050, 0.420), (0.0, 0.450, 0.420), 0.240, 0.120, 'Underbody'))     # transfer case
    C.extend(ck.rod((0.0, YR + 0.150, 0.415), (0.0, 0.050, 0.420), 0.036, 'Steel', n=8))
    C.extend(ck.rod((0.100, YF - 0.150, 0.405), (0.060, 0.450, 0.420), 0.032, 'Steel', n=8))
    C.extend(ck.box_between((-0.660, -0.700, 0.425), (-0.660, 0.300, 0.425), 0.240, 0.120, 'Plastic'))  # fuel tank
    ex = [Vector((0.300, 1.300, 0.430)), Vector((0.320, 0.900, 0.380)), Vector((0.320, -0.900, 0.380)),
          Vector((0.560, -1.150, 0.420)), Vector((0.620, -1.450, 0.500)), Vector((0.620, -2.100, 0.500)),
          Vector((0.620, -2.400, 0.380)), Vector((0.620, -2.540, 0.372))]
    C.extend(ck.rod_path(ck.cr_resample(ex, closed=False, sub=2), 0.030, 'Steel', n=8))
    C.extend(ck.ellipsoid((0.320, -0.350, 0.385), (0.105, 0.290, 0.068), 'Steel', nu=12, nv=6))
    # spare tyre slung under the bed floor between the frame rails
    rr = 17 * 0.0254 / 2
    prof = ck._tyre_profile(WHEEL_R, rr, WHEEL_W / 2, WHEEL_W / 2 - 0.012, 'tall')
    prof = prof + [(-a, r) for (a, r) in reversed(prof)]
    spare = ck.revolve(prof, 24, 'Rubber')
    spare.extend(ck.disc((-WHEEL_W / 2 + 0.030, 0, 0), (-1, 0, 0), rr, 'Steel', n=24))
    M = Matrix.Translation((0.0, -2.320, 0.735)) @ Matrix.Rotation(math.radians(90.0), 4, 'Y')
    C.extend(spare.transformed(M))
    # rear wheelhouse liners (seen through the bed's arch openings)
    for sx in (1, -1):
        lin = ck.revolve([(0.957, ARCH_R + 0.014), (0.615, ARCH_R + 0.014)], 30, 'Underbody',
                         theta0=math.radians(14.0), theta1=math.radians(166.0))
        lin = lin.translated((0, YR, ARCH_Z))
        C.extend(lin if sx > 0 else lin.mirrored_x())


def body_details(car, S_, SB):
    """Exterior details, all conforming to the shells. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre / one-sided parts (not mirrored)
    LH, LT, LB, LR, LBC, AM = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    front_details(car, S_, R, C, LH, AM)
    hood_details(S_, R, C, AM)
    side_details(car, S_, R, C, AM)
    bed_details(car, SB, R, C, LT, LB, LR, AM)
    rear_details(car, S_, SB, R, C, LT, LB, LR, LBC)
    underbody(C)
    R, C = drop_slivers(R), drop_slivers(C)
    if DEBUG:
        print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris(), 'amber =', AM.tris())
    car.add('Body', R, R.mirrored_x(), C, AM)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x())
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR, LR.mirrored_x())


# =====================================================================================================
# interior
# =====================================================================================================
DASH_FACE = [(0.680, 1.140), (0.690, 1.250), (0.705, 1.380)]


def face_pt(x, z):
    for (ya, za), (yb, zb) in zip(DASH_FACE[:-1], DASH_FACE[1:]):
        if za <= z <= zb:
            return Vector((x, ya + (yb - ya) * (z - za) / (zb - za), z))
    return Vector((x, DASH_FACE[-1][0], z))


def interior(car):
    I = ck.Part()
    xa = min(inner_x(y, z) for y in (0.70, 0.85, 1.00) for z in (0.90, 1.10, 1.30, 1.38)) - 0.012
    # ---- tall two-tone dashboard (profile (y, z) swept across X)
    dash = [(1.060, 1.150), (1.035, 1.370), (0.960, 1.392), (0.820, 1.408), (0.745, 1.416), (0.722, 1.408),
            (0.705, 1.380), (0.690, 1.250), (0.680, 1.140), (0.700, 1.030), (0.760, 0.920), (0.900, 0.840),
            (1.060, 0.860)]
    dmats = ['InteriorDark'] * 6 + ['Interior', 'Interior', 'InteriorDark'] + ['InteriorDark'] * 4
    xs = [-xa, -xa + 0.012, -0.55, -0.2, 0.0, 0.2, 0.55, xa - 0.012, xa]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < xa - 0.006 else 0.010
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # ---- driver binnacle over a 4-dial cluster
    hood_p = [(0.745, 1.416), (0.726, 1.442), (0.668, 1.450), (0.644, 1.442), (0.640, 1.426), (0.668, 1.428),
              (0.705, 1.422)]
    I.extend(ck.sweep_axis('x', [-0.665, -0.653, -0.247, -0.235],
                           [[(y, z - (0.01 if k in (0, 3) else 0)) for (y, z) in hood_p] for k in range(4)],
                           'InteriorDark'))
    fn = Vector((0.0, -0.140, 0.015)).normalized()          # dash face normal (face leans back ~6 deg)
    for (x, z, r, nt) in ((-0.565, 1.305, 0.052, 11), (-0.335, 1.305, 0.052, 11), (-0.490, 1.358, 0.018, 5),
                          (-0.410, 1.358, 0.018, 5)):
        c = face_pt(x, z) + fn * 0.003
        I.extend(ck.gauge(c, fn, r, n_ticks=nt))
    up = fn.cross(Vector((1, 0, 0)))
    if up.z < 0:
        up = -up
    sc = face_pt(-0.450, 1.298) + fn * 0.0025
    I.extend(quad(sc, (1, 0, 0), up, 0.068, 0.056, fn, 'Screen'))
    for (u, v, w, h) in ((0.0, 0.016, 0.040, 0.006), (-0.012, -0.004, 0.022, 0.014), (0.016, -0.004, 0.012, 0.014)):
        I.extend(quad(sc + fn * 0.0008 + Vector((u, 0, 0)) + up * v, (1, 0, 0), up, w, h, fn, 'Gauge'))
    # ---- centre stack: screen, vents, switch row, 4x4 selector knob
    cst = face_pt(0.0, 1.300) + fn * 0.002
    I.extend(ck.box_between(cst + Vector((-0.160, 0.004, 0)), cst + Vector((0.160, 0.004, 0)), 0.150, 0.012,
                            'InteriorDark', up=tuple(fn)))
    I.extend(quad(cst + fn * 0.0075, (1, 0, 0), up, 0.240, 0.110, fn, 'Screen'))
    for (u, v, w, h) in ((-0.060, 0.032, 0.100, 0.014), (-0.060, 0.008, 0.100, 0.006), (-0.060, -0.010, 0.100, 0.006),
                         (0.058, 0.004, 0.090, 0.070), (-0.090, -0.040, 0.030, 0.016), (-0.050, -0.040, 0.030, 0.016),
                         (-0.010, -0.040, 0.030, 0.016)):
        I.extend(quad(cst + fn * 0.0083 + Vector((u, 0, 0)) + up * v, (1, 0, 0), up, w, h, fn,
                      'Gauge' if h < 0.05 else 'ScreenMap'))
    for x in (-0.720, -0.150, 0.150, 0.720):
        p = face_pt(x, 1.200) + fn * 0.002
        I.extend(ck.box_between(p + Vector((-0.055, 0, 0)), p + Vector((0.055, 0, 0)), 0.050, 0.020, 'Trim',
                                up=tuple(fn)))
        for k in range(3):
            I.extend(ck.box_between(p + Vector((-0.050, 0, -0.014 + 0.014 * k)) + fn * 0.010,
                                    p + Vector((0.050, 0, -0.014 + 0.014 * k)) + fn * 0.010, 0.004, 0.004, 'Alu'))
    for k in range(5):
        p = face_pt(-0.100 + 0.050 * k, 1.150)
        I.extend(ck.box_between(p, p + Vector((0, -0.016, 0)), 0.022, 0.014, 'Gauge' if k == 2 else 'Trim'))
    p = face_pt(0.110, 1.240)
    I.extend(ck.rod(p, p + Vector((0, -0.022, 0)), 0.020, 'Trim', n=12))
    # passenger grab handle across the dash
    gh = [Vector((0.300, 0.752, 1.410)), Vector((0.330, 0.700, 1.446)), Vector((0.650, 0.700, 1.446)),
          Vector((0.680, 0.752, 1.410))]
    I.extend(ck.rod_path(ck.cr_resample(gh, closed=False, sub=3), 0.013, 'InteriorDark', n=8))
    # ---- steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.25, 0.075, 0.085, 'InteriorDark'))
    # ---- centre console with a T-handle gear selector and an armrest lid
    cys = [0.680, 0.600, 0.420, 0.150, -0.050, -0.250]
    tops = [1.060, 0.960, 0.905, 0.895, 0.960, 0.960]
    profs = [[(-0.150, 0.535), (0.150, 0.535), (0.155, t - 0.03), (0.130, t), (-0.130, t), (-0.155, t - 0.03)]
             for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'InteriorDark', 'Interior',
                                             'InteriorDark', 'InteriorDark']))
    I.extend(ck.box_between((0.0, -0.060, 0.972), (0.0, -0.250, 0.972), 0.240, 0.030, 'Interior'))
    I.extend(ck.rod((0.0, 0.330, 0.900), (0.0, 0.310, 0.985), 0.010, 'Alu', n=8))
    I.extend(ck.box_between((-0.040, 0.308, 0.995), (0.040, 0.308, 0.995), 0.030, 0.026, 'InteriorDark'))
    for x in (-0.065, 0.065):
        I.extend(ck.disc((x, 0.180, 0.897), (0, 0, 1), 0.036, 'Trim', n=14, ring_mat='Alu', ring_w=0.004))
    # ---- 2 front seats + 3-seat rear bench with headrests (5 seats)
    for x in (-0.450, 0.450):
        I.extend(ck.bucket_seat(x, SEAT_Y[0], SEAT_Y[1], SEAT_Z, width=0.560, recline=SEAT_RECLINE,
                                back_h=SEAT_BACK_H, bolster=0.060, headrest_w=0.28))
    I.extend(ck.bucket_seat(0.0, BENCH_Y[0], BENCH_Y[1], BENCH_Z, width=BENCH_W, recline=BENCH_RECLINE,
                            back_h=BENCH_BACK_H, bolster=0.050, bench=True))
    zf_in = BODY.params_at(-0.400)['zb'] + D_IN
    I.extend(ck.box_between((0.0, BENCH_Y[0] - 0.030, (BENCH_Z + zf_in) / 2),
                            (0.0, BENCH_Y[1] + 0.040, (BENCH_Z + zf_in) / 2), BENCH_W - 0.06, BENCH_Z - zf_in,
                            'InteriorDark'))
    Mb = Matrix.Translation((0.0, BENCH_Y[1] - 0.05, BENCH_Z + 0.05)) @ Matrix.Rotation(math.radians(BENCH_RECLINE),
                                                                                        4, 'X')
    for x in (-0.480, 0.0, 0.480):
        hc = Mb @ Vector((x, 0.050, BENCH_BACK_H + 0.095))
        I.extend(ck.ellipsoid(hc, (0.125, 0.048, 0.078), 'Interior', nu=12, nv=6, exp=3.0))
        for dx in (-0.055, 0.055):
            I.extend(ck.rod(Mb @ Vector((x + dx, 0.050, BENCH_BACK_H - 0.020)), hc + Vector((dx, 0, -0.050)), 0.006,
                            'Alu', n=6))
    # ---- door cards: armrests, pulls, speakers, window switches (4 doors)
    door = ck.Part()
    for (ya, yb) in ((1.150, 0.140), (0.030, -0.820)):
        xd = min(inner_x(y, z) for y in (ya, (ya + yb) / 2, yb) for z in (0.95, 1.05)) - 0.004
        door.extend(ck.sweep_axis('y', [ya, ya - 0.020, yb + 0.020, yb],
                                  [(xd, 0.960), (xd - 0.075, 0.975), (xd - 0.080, 1.015), (xd - 0.064, 1.030),
                                   (xd, 1.035)], 'InteriorDark'))
        door.extend(ck.box_between((xd - 0.020, ya - 0.220, 1.110), (xd - 0.020, ya - 0.400, 1.110), 0.020, 0.026,
                                   'Alu'))
        door.extend(ck.disc((xd - 0.004, (ya + yb) / 2 + 0.10, 0.760), (-1, 0, 0), 0.075, 'Trim', n=16,
                            ring_mat='Alu', ring_w=0.006))
        door.extend(ck.box_between((xd - 0.006, ya - 0.10, 1.262), (xd - 0.006, yb + 0.10, 1.262), 0.012, 0.030,
                                   'Interior'))
        door.extend(ck.box_between((xd - 0.050, yb + 0.120, 1.037), (xd - 0.050, yb + 0.230, 1.037), 0.040, 0.010,
                                   'Trim'))
    I.extend(door, door.mirrored_x())
    # ---- pedals, footrest, sun visors, rear-view mirror, overhead console
    zfl = BODY.params_at(0.700)['zb'] + D_IN
    for x, w in ((-0.400, 0.090), (-0.290, 0.055)):
        I.extend(ck.box_between((x, 0.920, zfl + 0.050), (x, 0.880, zfl + 0.170), w, 0.014, 'Alu'))
    I.extend(ck.box_between((-0.640, 0.940, zfl + 0.010), (-0.640, 0.820, zfl + 0.080), 0.070, 0.012, 'Alu'))
    zr_in = BODY.params_at(0.40)['zc'] - D_IN
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.130, 0.540, zr_in - 0.032), (s * 0.540, 0.540, zr_in - 0.032), 0.160, 0.018,
                                'Headliner'))
    I.extend(ck.box_between((-0.120, 0.640, zr_in - 0.115), (0.120, 0.640, zr_in - 0.115), 0.030, 0.065,
                            'InteriorDark'))
    I.extend(ck.box_between((0.0, 0.640, zr_in - 0.080), (0.0, 0.620, zr_in - 0.010), 0.022, 0.022, 'InteriorDark'))
    I.extend(ck.box_between((0.0, 0.200, zr_in - 0.012), (0.0, 0.520, zr_in - 0.012), 0.200, 0.026, 'InteriorDark'))
    car.add('Interior', I)
    # ---- big 4-spoke steering wheel (separate object, origin at the hub)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.019, 0.023), segs=36, flat_bottom=False, hub_r=0.075, dish=0.040,
                                spoke_thick=0.018, spokes=((15.0, 0.052), (165.0, 0.052), (240.0, 0.044),
                                                           (300.0, 0.044)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


RENDER_PATH = globals().get('RENDER_TO') or os.path.join(PROJECT, 'docs', 'blender_cars', CAR_ID + '.png')
GLB_PATH = os.path.join(PROJECT, 'assets', 'imported', 'cars', CAR_ID + '.glb')
JSON_PATH = os.path.join(PROJECT, 'assets', 'imported', 'cars', CAR_ID + '.json')


def interior_in_wells(car):
    """Count Interior/SteeringWheel vertices that sit inside a wheel-well cavity (visible from outside)."""
    n = 0
    for nm in ('Interior', 'SteeringWheel'):
        ob = car.objects[nm]
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            for a in ARCHES + [BED_ARCH]:
                if abs(p.x) > a['x_in'] and math.hypot(p.y - a['y'], p.z - a['z']) < a['r']:
                    n += 1
    return n


def interior_leaks(car):
    """Interior / steering-wheel vertices that poke out of the body: a ray straight down must hit the Body
    floor, and rays to +-X must hit the Body or the Glass. Returns (count, sample points)."""
    import bpy
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    body = BVHTree.FromObject(car.objects['Body'], dg)
    glass = BVHTree.FromObject(car.objects['Glass'], dg)
    bad = []
    for nm in ('Interior', 'SteeringWheel'):
        ob = car.objects[nm]
        M = ob.matrix_world
        for v in ob.data.vertices:
            p = M @ v.co
            down = body.ray_cast(p + Vector((0, 0, 0.0005)), Vector((0, 0, -1)), 2.0)[0]
            side = []
            for sx in (1, -1):
                d = Vector((sx, 0, 0))
                side.append(body.ray_cast(p, d, 2.0)[0] is not None or glass.ray_cast(p, d, 2.0)[0] is not None)
            if down is None or not all(side):
                bad.append(p)
    return len(bad), [tuple(round(c, 3) for c in p) for p in bad[:6]]


def measure(car, tris):
    G = ck.to_godot
    body = car.objects['Body']
    M = body.matrix_world
    bv = [M @ v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in bv), min(v.y for v in bv), min(v.z for v in bv)))
    mx = Vector((max(v.x for v in bv), max(v.y for v in bv), max(v.z for v in bv)))
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 1.30)        # tow mirrors excluded
    all_mn, all_mx = ck.world_aabb([o for o in car.objects.values() if o.type == 'MESH'])
    wheels = {k: car.objects['Wheel_' + k].matrix_world.translation for k in ('FL', 'FR', 'RL', 'RR')}

    def wdims(k):
        ob = car.objects['Wheel_' + k]
        vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
        return (max(v.z for v in vs) - min(v.z for v in vs)) / 2, max(v.x for v in vs) - min(v.x for v in vs)
    rf, wf = wdims('FL')
    rr, wr = wdims('RL')
    sockets = {n: G(car.objects[n].matrix_world.translation) for n in car.sockets}
    sw = car.objects['SteeringWheel']
    mats = set()
    for o in car.objects.values():                      # materials actually used by faces (= exported)
        if o.type == 'MESH':
            used = {p.material_index for p in o.data.polygons}
            mats |= {o.data.materials[i].name for i in used if i < len(o.data.materials) and o.data.materials[i]}
    mats = sorted(mats)
    roof = max(BODY.params_at(y)['zc'] for y in car.shell.ys)
    return {
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'full-size pickup truck (crew cab, open load bed)',
        'drivetrain': 'RWD-biased 4x4', 'engine': 'front, turbo-diesel V8', 'doors': 4, 'seats': 5,
        'source_blend': 'Opus55ForzaUltracodeEffort.blend', 'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(mx.y - mn.y, 4),
        'length_bumper_to_bumper': round(Y_FBUMP - Y_RBUMP, 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(roof, 4), 'height_overall': round(all_mx.z, 4),
        'ground_clearance': round(mn.z, 4), 'cab_floor_height': round(BODY.params_at(0.0)['zb'], 4),
        'bed': {'floor_height': Z_FLOOR, 'rail_height': round(BODY.point(-0.6, 5.0, 1).z + 0.012, 4),
                'inner_length': round((Y_BED_F - 0.100) - (Y_BED_R + 0.113), 4),
                'inner_width': round(2 * bed_inner_x(1.0), 4), 'width_between_wheel_wells': 1.23,
                'tailgate_y_godot': round(-Y_BED_R, 4)},
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'tyre_width_nominal': WHEEL_W, 'wheel_width_note': 'measured over the shoulder tread lugs (nominal 0.275)',
        'rim_diameter_in_front': 18, 'rim_diameter_in_rear': 18,
        'wheels': {k: G(v) for k, v in wheels.items()},
        'sockets': sockets,
        'steering_wheel': {'position': G(sw.matrix_world.translation),
                           'column_axis': G(sw.matrix_world.to_3x3() @ Vector((0, 1, 0))), 'radius': SW_R,
                           'spin_axis_local_godot': [0.0, 0.0, -1.0],
                           'note': 'Blender local +Y (column toward dash) becomes node-local -Z after the +Y-up glTF export'},
        'wheel_spin_axis_local_godot': [1.0, 0.0, 0.0],
        'eye_point': G(EYE),
        'body_aabb': {'min': [round(mn.x, 4), round(mn.z, 4), round(-mx.y, 4)],
                      'max': [round(mx.x, 4), round(mx.z, 4), round(-mn.y, 4)]},
        'car_aabb': {'min': [round(all_mn.x, 4), round(all_mn.z, 4), round(-all_mx.y, 4)],
                     'max': [round(all_mx.x, 4), round(all_mx.z, 4), round(-all_mn.y, 4)]},
        'tris': tris,
        'materials': mats,
        'default_paint': {'hex': '#2F3337', 'linear_rgb': [0.0284, 0.0331, 0.0382], 'finish': 'metallic'},
    }


def export_all(car):
    tris = ck.tri_counts(car)
    res, info = ck.export_car(car, GLB_PATH)
    data = measure(car, tris)
    data['glb'] = {'path': 'res://assets/imported/cars/%s.glb' % CAR_ID, 'bytes': info['file_size'],
                   'nodes': [n['name'] for n in info['nodes']]}
    ck.write_car_json(car, JSON_PATH, data)
    return res, info, data


if __name__ == '__main__':
    CAR, SHELL = build()
    print('tris', ck.tri_counts(CAR))
    print('rear glass y range', YG0, YG1, 'bed levels', len(bed_levels()))
    if STAGE != 'body':
        hidden = isolate(True)
        try:
            print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W), 'interior verts in wheel wells:', interior_in_wells(CAR),
                  'interior leaks:', interior_leaks(CAR))
        finally:
            isolate(False)
    if RENDER:
        hidden = isolate(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(6.4, 7.2, 1.95), target=(0.0, -0.05, 0.95),
                                           lens=50.0, world_strength=0.9, sun_energy=3.8, exposure=0.0,
                                           sun_rot=(0.80, 0.0, 2.30)))
        finally:
            if not globals().get('KEEP_ISOLATED', False):
                isolate(False)
    elif globals().get('KEEP_ISOLATED', False):
        isolate(True)
    if EXPORT:
        RES, INFO, DATA = export_all(CAR)
        print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
        print('materials', INFO['materials'])
