"""Castellan GT - front-engine V12 grand tourer, 2-door 2+2, RWD (car #5 of Sunward Roads).

Rebuilds Cars/Car_castellan_gt from scratch with tools/blender/car_kit.py, then (optionally) renders the QA
hero image and exports assets/imported/cars/castellan_gt.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\castellan_gt.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking).

Spec: L 4.85, W 1.98, H 1.28, wheelbase 2.85, track 1.66 / 1.65, wheel R 0.35 (20" rims), tyre width
0.255 front / 0.295 rear. Original design (no real brand / model): extremely long sculpted hood with two
power creases and raised wing crowns, side vents with chrome strakes behind the front wheels, cab-backward
fastback greenhouse that tapers in plan and in side view (tapered quarter glass), muscular rear haunches
(the widest point of the car), wide shallow dark-mesh grille, slim swept headlamps, slim wrap-around tail
lamps under an integrated lip spoiler, quad exhaust tips in a dark diffuser, 5 wide polished spokes.
Metallic dark British-style green #1F3D2B; tan leather interior with walnut and metal trim.
"""
import sys
import os
import math
import importlib

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender'))
import car_kit as ck  # noqa: E402
importlib.reload(ck)
from mathutils import Vector, Matrix  # noqa: E402

CAR_ID = 'castellan_gt'
CAR_NAME = 'Castellan GT'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.85
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.425)
TRACK_F, TRACK_R = 1.66, 1.65
WHEEL_R = 0.35
WHEEL_W_F, WHEEL_W_R = 0.255, 0.295
ARCH_R, ARCH_Z = 0.378, 0.357                  # ~3 cm visible gap above the tyre
NOSE_Y, TAIL_Y = 2.407, -2.421                 # cap poles -> body length ~4.85

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs),
# K3 waist / widest (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr),
# K8 roof crown (zc). On the hood: K5 = wing crown, K6 = valley inboard of the wing, K7 (K6 moved `rail`
# toward the centre and raised by `bulge`) = power crease, K8 = hood centre. On the deck K5..K8 lie on the lid.
Y_RW = -1.940            # rear window base / deck crease
RW_TOP = -0.980          # rear window top edge
Y_HEADER = -0.270        # windscreen header
Y_COWL = 0.400           # windscreen base / hood rear edge
HOOD = dict(ks={5: 0.45, 6: 0.18, 7: 0.82})
S = [
    # ---- tail: rear face edge, deck kicks up ~1 cm into an integrated lip spoiler; strong plan taper
    dict(y=-2.405, zb=0.500, wb=0.34, zs=0.530, ws=0.530, zw=0.660, ww=0.620, zh=0.880, wh=0.602,
         zg=0.958, wg=0.555, zr=0.988, wr=0.405, zc=0.994, rail=0.05, bulge=0.0, ks={6: 0.15}),
    dict(y=-2.380, zb=0.440, wb=0.40, zs=0.480, ws=0.660, zw=0.650, ww=0.735, zh=0.885, wh=0.712,
         zg=0.954, wg=0.640, zr=0.982, wr=0.462, zc=0.988),
    dict(y=-2.330, zb=0.370, wb=0.49, zs=0.420, ws=0.775, zw=0.638, ww=0.830, zh=0.891, wh=0.808,
         zg=0.948, wg=0.705, zr=0.972, wr=0.505, zc=0.977),
    dict(y=-2.250, zb=0.310, wb=0.55, zs=0.360, ws=0.852, zw=0.628, ww=0.900, zh=0.897, wh=0.874,
         zg=0.943, wg=0.750, zr=0.964, wr=0.528, zc=0.969, ks={6: 0.3}),
    dict(y=-2.120, zb=0.260, wb=0.60, zs=0.310, ws=0.898, zw=0.620, ww=0.948, zh=0.902, wh=0.920,
         zg=0.942, wg=0.785, zr=0.961, wr=0.536, zc=0.966),
    # ---- deck crease / rear window base
    dict(y=Y_RW, zb=0.208, wb=0.62, zs=0.290, ws=0.925, zw=0.615, ww=0.976, zh=0.904, wh=0.944,
         zg=0.942, wg=0.805, zr=0.958, wr=0.528, zc=0.966, sharp=dict(zc=0.8, zr=0.6), ks={6: 0.35}),
    dict(y=-1.640, zb=0.168, wb=0.63, zs=0.277, ws=0.936, zw=0.606, ww=0.993, zh=0.904, wh=0.962,
         zg=0.940, wg=0.825, zr=1.024, wr=0.526, zc=1.048),
    # ---- haunch peak over the rear axle (widest point of the car)
    dict(y=YR, zb=0.150, wb=0.63, zs=0.272, ws=0.936, zw=0.598, ww=0.995, zh=0.900, wh=0.964,
         zg=0.934, wg=0.830, zr=1.090, wr=0.546, zc=1.124),
    dict(y=-1.150, zb=0.138, zs=0.268, ws=0.922, zw=0.578, ww=0.977, zh=0.878, wh=0.936,
         zg=0.912, wg=0.830, zr=1.170, wr=0.585, zc=1.205),
    # ---- cabin, coke-bottle waist at the doors, tumblehome greenhouse
    dict(y=-0.850, zb=0.130, wb=0.63, zs=0.264, ws=0.904, zw=0.560, ww=0.947, zh=0.854, wh=0.902,
         zg=0.890, wg=0.830, zr=1.228, wr=0.622, zc=1.262),
    dict(y=-0.550, zs=0.262, ws=0.898, zw=0.550, ww=0.940, zh=0.842, wh=0.895, zg=0.881, wg=0.830,
         zr=1.248, wr=0.650, zc=1.280),
    dict(y=Y_HEADER, zw=0.548, ww=0.940, zh=0.836, wh=0.895, zg=0.877, wg=0.832, zr=1.238, wr=0.668,
         zc=1.268, sharp=dict(zc=0.5, zr=0.5, wr=0.3)),
    dict(y=0.050, zw=0.550, ww=0.944, zh=0.830, wh=0.900, zg=0.875, wg=0.834, zr=1.096, wr=0.708,
         zc=1.126),
    dict(y=Y_COWL, zb=0.130, wb=0.63, zs=0.264, ws=0.908, zw=0.552, ww=0.952, zh=0.826, wh=0.912,
         zg=0.877, wg=0.836, zr=0.900, wr=0.748, zc=0.914, rail=0.05, bulge=0.0,
         sharp=dict(zc=1.0, zr=1.0, wr=1.0, rail=1.0, bulge=1.0, s7=1.0, s6=1.0, s5=1.0)),
    # ---- extremely long hood: raised wing crowns (K5), soft valley (K6), two power creases (K7)
    dict(y=0.720, zb=0.134, wb=0.63, zs=0.266, ws=0.916, zw=0.554, ww=0.963, zh=0.830, wh=0.934,
         zg=0.902, wg=0.840, zr=0.888, wr=0.620, zc=0.900, rail=0.06, bulge=0.014, **HOOD),
    dict(y=1.050, zb=0.140, wb=0.62, zs=0.270, ws=0.920, zw=0.556, ww=0.971, zh=0.830, wh=0.944,
         zg=0.896, wg=0.848, zr=0.873, wr=0.575, zc=0.884, rail=0.06, bulge=0.019),
    dict(y=YF, zb=0.150, wb=0.62, zs=0.274, ws=0.922, zw=0.556, ww=0.974, zh=0.822, wh=0.948,
         zg=0.878, wg=0.850, zr=0.850, wr=0.532, zc=0.860, rail=0.06, bulge=0.020),
    dict(y=1.750, zb=0.168, wb=0.60, zs=0.280, ws=0.912, zw=0.552, ww=0.964, zh=0.804, wh=0.936,
         zg=0.848, wg=0.828, zr=0.820, wr=0.488, zc=0.829, rail=0.058, bulge=0.017),
    dict(y=2.000, zb=0.190, wb=0.57, zs=0.290, ws=0.875, zw=0.546, ww=0.930, zh=0.780, wh=0.900,
         zg=0.812, wg=0.785, zr=0.790, wr=0.448, zc=0.797, rail=0.055, bulge=0.014),
    dict(y=2.150, zb=0.214, wb=0.53, zs=0.302, ws=0.825, zw=0.540, ww=0.878, zh=0.756, wh=0.846,
         zg=0.782, wg=0.728, zr=0.763, wr=0.412, zc=0.768, bulge=0.011),
    dict(y=2.250, zb=0.238, wb=0.48, zs=0.315, ws=0.758, zw=0.534, ww=0.810, zh=0.733, wh=0.776,
         zg=0.752, wg=0.660, zr=0.737, wr=0.380, zc=0.740, bulge=0.008),
    dict(y=2.320, zb=0.265, wb=0.43, zs=0.330, ws=0.680, zw=0.528, ww=0.728, zh=0.710, wh=0.694,
         zg=0.723, wg=0.590, zr=0.712, wr=0.345, zc=0.714, bulge=0.004),
    dict(y=2.365, zb=0.295, wb=0.38, zs=0.350, ws=0.600, zw=0.522, ww=0.640, zh=0.692, wh=0.610,
         zg=0.700, wg=0.520, zr=0.692, wr=0.305, zc=0.694, bulge=0.002),
    dict(y=2.390, zb=0.330, wb=0.33, zs=0.370, ws=0.510, zw=0.518, ww=0.545, zh=0.678, wh=0.520,
         zg=0.684, wg=0.445, zr=0.677, wr=0.262, zc=0.679, bulge=0.0),
    dict(y=2.403, zb=0.360, wb=0.26, zs=0.392, ws=0.420, zw=0.515, ww=0.450, zh=0.667, wh=0.430,
         zg=0.672, wg=0.368, zr=0.666, wr=0.218, zc=0.668),
]

# Quarter window: its rear edge leans forward going up -> tapering greenhouse (belt y=-1.32, rail y=-0.97)
WARP_Y = -1.150
WARP = dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.320, -0.970), margin=0.28)
Y_SAIL = 0.260           # door glass front edge / mirror sail
Y_QSPLIT = (-0.800, -0.780)   # door glass / quarter glass divider (chrome)
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),       # windscreen
    dict(bands=(5, 5), y=(WARP_Y, Y_SAIL), role='glass'),         # door + quarter glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),          # mirror sail (black)
    dict(bands=(5, 5), y=Y_QSPLIT, role='chrome'),                # frameless door / quarter divider
    dict(bands=(7, 7), y=(Y_RW + 0.030, RW_TOP), role='glass'),   # fastback rear window
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.050), role='trim'),  # cowl panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[2, 3, 5, 5, 2, 6, 2, 7],
    key_sharp=(0, 0.7, 0.5, 0.62, 0.66, 0.35, 0.42, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.515, tilt=6.0, k_edge=2.2, k_face=2.7, rings=8),
    tail=dict(y=TAIL_Y, z=0.745, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8),
    step=0.050,
    rail=0.05,
    warps=[WARP],
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.660), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.640)]
INNER = dict(y=(Y_RW + 0.040, Y_COWL + 0.040), d=0.035,
             tubs=[(YR, ARCH_Z, ARCH_R + 0.03, 0.625)],
             band_mats={0: 'InteriorDark', 1: 'InteriorDark', 2: 'InteriorAccent', 3: 'Interior', 4: 'Interior',
                        5: 'Interior', 6: 'InteriorDark', 7: 'InteriorDark'})

EYE = Vector((-0.380, -0.540, 1.062))        # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.380, -0.020, 0.775))        # steering wheel hub
COLUMN_TILT = 22.0                           # deg, column descends toward the dash
SW_R = 0.182                                 # steering wheel radius
DOOR_X = 0.878                               # door-card face (inner shell) at z ~0.75


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


def snap_pts(S, spec):
    out = []
    for view, a, b in spec:
        p = S.snap(view, a, b)
        if p is None:
            raise RuntimeError('snap miss %s %s %s' % (view, a, b))
        out.append(p)
    return out


def lamp(S, spec, house_mat, inner_mat, inset=0.006, house_off=0.002, inner_off=0.0034, res=0.02):
    """Wrap-around lamp: housing patch + inset inner patch. Returns (housing, inner, frame, pts2d)."""
    pts = snap_pts(S, spec)
    housing, frame = S.patch3d(pts, offset=house_off, depth=0.006, res=res, mat=house_mat, sub=4)
    O, U, V, D = frame
    pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in pts]
    inner2d = ck.offset_poly(ck.cr_resample(pts2d, True, 4), -inset)
    inner = S.patch(inner2d, frame, offset=inner_off, depth=0.004, res=res * 0.9, mat=inner_mat, smooth=False)
    return housing, inner, frame, pts2d


def hood_line():
    """Right half of the hood shut line: just inboard of the wing crown from the cowl panel forward, then
    across the hood front edge to the centre line (the left half is the mirror)."""
    pts = [BODY.point(y, 5.16) for y in (Y_COWL + 0.058, 0.70, 1.00, YF, 1.75, 2.00, 2.16, 2.25)]
    for k in range(1, 10):
        u = k / 9.0
        pts.append(BODY.point(2.25 + 0.115 * (u ** 1.3), 5.16 + 2.84 * u))
    return pts


def dlo_line():
    """Right-side chrome DLO surround: belt from the mirror sail to the tapered quarter-glass tip, up the
    slanted rear edge, along the roof rail and down the A-pillar to the cowl."""
    pts = []
    y_c0, y_c1 = WARP['y_t']
    for k in range(37):
        pts.append(BODY.point(ck.lerp(Y_COWL - 0.03, y_c0 - 0.010, k / 36), 4.955))
    for k in range(1, 9):
        t = 4.955 + (6.06 - 4.955) * k / 8
        u = ck.clamp(t - 5.0, 0.0, 1.0)
        pts.append(BODY.point(ck.lerp(y_c0, y_c1, u) - 0.012, t))
    for k in range(1, 33):
        pts.append(BODY.point(ck.lerp(y_c1 - 0.012, Y_HEADER, k / 32), 6.06))
    for k in range(1, 15):
        pts.append(BODY.point(ck.lerp(Y_HEADER, Y_COWL - 0.006, k / 14), 6.06))
    return pts


def body_details(car, S):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LBC, LTC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    D = ck.densify
    F = S.frame('front')

    # ================= front: wide shallow dark-mesh grille with a thin chrome surround
    grille = D(ck.fillet_poly([(-0.455, 0.398), (0.455, 0.398), (0.515, 0.452), (0.500, 0.540), (-0.500, 0.540),
                               (-0.515, 0.452)], [0.035, 0.035, 0.03, 0.04, 0.04, 0.03], n=5), 0.06)
    C.extend(S.honeycomb(grille, 'front', cell=0.049, wall=0.0065, base_offset=0.0015, height=0.008, margin=0.004,
                         smooth=False, res=0.0))
    C.extend(S.rim(grille, 'front', width=0.011, offset=0.0095, depth=0.006, mat='Chrome', smooth=False))
    # corner intakes (brake cooling), dark with a black frame
    intake = D(ck.fillet_poly([(0.585, 0.392), (0.735, 0.405), (0.758, 0.462), (0.598, 0.452)], 0.010, n=3), 0.02)
    R.extend(S.patch(intake, 'front', offset=0.0020, depth=0.005, res=0.015, mat='Grille', smooth=False))
    R.extend(S.rim(intake, 'front', width=0.008, offset=0.0065, depth=0.005, mat='Trim', smooth=False))
    # black chin lip + carbon splitter blade following the nose plan outline
    lip = D(ck.fillet_poly([(-0.62, 0.364), (0.62, 0.364), (0.66, 0.380), (-0.66, 0.380)], 0.004, n=2), 0.04)
    C.extend(S.patch(lip, 'front', offset=0.0020, depth=0.005, res=0.0, mat='Trim', smooth=False))
    xs = [-0.70 + 1.40 * k / 28 for k in range(29)]
    front = []
    for x in xs:
        p = S.snap('front', x, 0.372)
        front.append((x, (p.y if p is not None else 2.30) + 0.017 - 0.010 * (abs(x) / 0.70) ** 2))
    prof = front + [(0.62, 2.12), (-0.62, 2.12)]
    prof = list(reversed(prof)) if ck.poly_area(prof) < 0 else prof
    C.extend(ck.sweep_axis('z', [0.334, 0.350], prof, 'Carbon'))
    # bumper-to-wing split line from the lamp tip down to the arch
    R.extend(S.line([(2.150, 0.722), (2.060, 0.664), (1.930, 0.628), (1.760, 0.604)], 'right', step=0.02))

    # ================= headlamps: slim swept blades from the nose corners back along the wing tops
    hl_spec = [('front', 0.392, 0.640), ('front', 0.410, 0.660), ('front', 0.520, 0.670), ('front', 0.630, 0.681),
               ('right', 2.270, 0.722), ('right', 2.185, 0.748), ('right', 2.105, 0.764), ('right', 2.120, 0.748),
               ('right', 2.215, 0.712), ('right', 2.300, 0.668), ('front', 0.650, 0.628), ('front', 0.520, 0.616),
               ('front', 0.410, 0.618)]
    housing, inner, frame, p2 = lamp(S, hl_spec, 'Trim', 'Chrome', inset=0.005, res=0.016)   # reflector bowl
    R.extend(housing, inner)
    drl = snap_pts(S, [('front', 0.420, 0.656), ('front', 0.52, 0.664), ('front', 0.620, 0.674),
                       ('right', 2.270, 0.715), ('right', 2.190, 0.740), ('right', 2.130, 0.753)])
    LH.extend(S.line3d(drl, width=0.0065, offset=0.0062, mat='HeadlightLens', step=0.012))
    proj_centers = []
    for (x, z) in ((0.468, 0.638), (0.566, 0.643)):
        loc, nor = S.hit(F, x, z)
        c = loc + nor * 0.0058
        LH.extend(ck.disc(c, nor, 0.0115, 'HeadlightLens', n=16))
        R.extend(ck.disc(c - nor * 0.0010, nor, 0.0115, 'Chrome', n=16, ring_mat='Chrome', ring_w=0.004))
        proj_centers.append(c)
    hc = (proj_centers[0] + proj_centers[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))

    # ================= hood: shut line, cowl, wipers
    R.extend(S.line3d(hood_line(), step=0.025))
    for (x0, x1, y0, y1, px) in ((-0.64, -0.08, Y_COWL - 0.030, Y_COWL - 0.060, -0.30),
                                 (-0.03, 0.50, Y_COWL - 0.036, Y_COWL - 0.064, 0.22)):
        a0 = S.snap('top', x0, y0) + Vector((0, 0, 0.012))
        a1 = S.snap('top', x1, y1) + Vector((0, 0, 0.012))
        C.extend(ck.box_between(a0, a1, 0.015, 0.010, 'Trim'))
        pivot = S.snap('top', px, Y_COWL + 0.028) + Vector((0, 0, 0.010))
        mid = (a0 + a1) / 2 + Vector((0, 0, 0.007))
        C.extend(ck.box_between(pivot, mid, 0.011, 0.007, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.015, 0.015, 0.009), 'Trim', nu=8, nv=5))

    # ================= side: wing vent with chrome strakes, shut lines, handle, mirror, DLO chrome, sill
    vent = D(ck.fillet_poly([(1.092, 0.548), (1.168, 0.668), (0.905, 0.662), (0.818, 0.606), (0.900, 0.556)],
                            [0.012, 0.012, 0.012, 0.020, 0.012], n=3), 0.02)
    R.extend(S.patch(vent, 'right', offset=0.0010, depth=0.004, res=0.014, mat='Grille', smooth=False))
    R.extend(S.rim(vent, 'right', width=0.008, offset=0.0050, depth=0.005, mat='Chrome', smooth=False))
    for (z0, y_end) in ((0.588, 1.108), (0.627, 1.135)):
        R.extend(S.line(D([(0.848, z0 + 0.004), (y_end, z0 - 0.002)], 0.02, closed=False), 'right', width=0.0085,
                        offset=0.0045, mat='Chrome', smooth=False, step=0.02))
    R.extend(S.line([(0.470, 0.292), (0.478, 0.55), (0.472, 0.76), (0.452, 0.852)], 'right', step=0.02))   # door front
    R.extend(S.line([(-0.858, 0.292), (-0.866, 0.55), (-0.876, 0.76), (-0.890, 0.872)], 'right', step=0.02))  # door rear
    R.extend(S.patch(D(ck.rrect_pts(-0.640, 0.790, 0.170, 0.034, 0.015, n=3), 0.02), 'right', offset=0.0010,
                     depth=0.004, res=0.0, mat='Trim', smooth=False))
    R.extend(S.patch(D(ck.rrect_pts(-0.640, 0.792, 0.150, 0.016, 0.007, n=3), 0.02), 'right', offset=0.0052,
                     depth=0.006, res=0.0, mat='Chrome', smooth=False))
    # mirror on the door top at the sail: body-colour cap, black base/arm, mirror glass facing back
    mc = Vector((0.992, 0.330, 0.952))
    ry = 0.058

    def flat_back(p):
        if p.y < -ry * 0.25:
            p.y = -ry * 0.25 - (p.y + ry * 0.25) * 0.08
        return p
    mirror = ck.ellipsoid(mc, (0.098, ry, 0.047), 'Paint', nu=18, nv=9, exp=3.0, deform=flat_back)
    for fi in range(len(mirror.f)):
        if mirror.face_center(fi).z < mc.z - 0.026:
            mirror.m[fi] = 'Trim'
    R.extend(mirror)
    glass_pts = ck.superellipse_pts(0.0, 0.0, 0.078, 0.038, e=2.6, n=20)
    mg = ck.Part()
    cen = mg.vert(mc + Vector((0, -ry * 0.25 - 0.003, 0)))
    ring = [mg.vert(mc + Vector((p.x, -ry * 0.25 - 0.003, p.y))) for p in glass_pts]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    base = S.snap('right', 0.335, 0.885)
    R.extend(ck.box_between(base + Vector((-0.012, 0.0, 0.006)), mc + Vector((-0.070, 0.004, -0.016)), 0.046, 0.018,
                            'Trim'))
    # chrome window surround
    R.extend(S.line3d(dlo_line(), width=0.011, offset=0.0016, mat='Chrome', step=0.05))
    # slim gloss-black sill blade between the arches
    ys = [-1.035, -1.010, -0.94, -0.40, 0.20, 0.80, 0.990, 1.025]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        e = min(y - ys[0], ys[-1] - y)
        k = 0.30 if e < 0.01 else (0.75 if e < 0.05 else 1.0)
        profs.append([(ws - 0.030, zs + 0.004), (ws + 0.001 * k, zs + 0.006), (ws + 0.011 * k, zs - 0.010),
                      (ws + 0.013 * k, zs - 0.044 * k), (ws + 0.006 * k, zs - 0.054 * k), (ws - 0.030, zs - 0.050)])
    R.extend(ck.sweep_axis('y', ys, profs, 'Trim'))
    fuel = ck.rrect_pts(-1.020, 0.790, 0.105, 0.095, 0.024, n=3)
    C.extend(S.line(fuel, 'right', closed=True, smooth=False))                                       # right side only

    # ================= rear: slim wrap-around tail lamps, lid lines, plate, valance, diffuser, quad exhausts
    tl_spec = [('rear', 0.300, 0.862), ('rear', 0.318, 0.884), ('rear', 0.460, 0.896), ('rear', 0.590, 0.904),
               ('right', -2.375, 0.906), ('right', -2.310, 0.902), ('right', -2.250, 0.898), ('right', -2.262, 0.884),
               ('right', -2.330, 0.876), ('rear', 0.620, 0.862), ('rear', 0.470, 0.852), ('rear', 0.330, 0.848)]
    housing, inner, frame, p2 = lamp(S, tl_spec, 'Trim', 'TaillightLens', inset=0.005, res=0.016)
    R.extend(housing)
    LT.extend(inner)
    brake = snap_pts(S, [('rear', 0.340, 0.872), ('rear', 0.470, 0.879), ('rear', 0.590, 0.885),
                         ('right', -2.370, 0.889), ('right', -2.300, 0.888)])
    LB.extend(S.line3d(brake, width=0.010, offset=0.0060, mat='BrakeLens', step=0.012))
    # lid: side lines along the deck, line across the face between the lamps, lip edge accent
    R.extend(S.line3d([BODY.point(y, 5.30) for y in (Y_RW + 0.035, -2.06, -2.20, -2.30, -2.36)], step=0.025))
    C.extend(S.line(D([(-0.31, 0.842), (0.31, 0.842)], 0.05, closed=False), 'rear', step=0.025, smooth=False))
    # number-plate recess on the lid face
    plate = D(ck.rrect_pts(0.0, 0.708, 0.525, 0.115, 0.012, n=2), 0.05)
    C.extend(S.patch(plate, 'rear', offset=0.0012, depth=0.004, res=0.0, mat='Grille', smooth=False))
    C.extend(S.rim(plate, 'rear', width=0.010, offset=0.0050, depth=0.005, mat='Trim', smooth=False))
    # bumper split line from the rear arch round the corner, lower rear valance (black), reverse lamps
    R.extend(S.line([(-1.790, 0.585), (-1.950, 0.598), (-2.120, 0.606), (-2.280, 0.610), (-2.350, 0.612)], 'right',
                    step=0.025))
    C.extend(S.line([(-0.74, 0.612), (-0.62, 0.614), (-0.30, 0.615), (0.0, 0.615), (0.30, 0.615), (0.62, 0.614),
                     (0.74, 0.612)], 'rear', step=0.03))
    valance = D(ck.fillet_poly([(-0.600, 0.508), (0.600, 0.508), (0.640, 0.530), (0.625, 0.566), (-0.625, 0.566),
                                (-0.640, 0.530)], [0.0, 0.0, 0.015, 0.012, 0.012, 0.015], n=3), 0.05)
    C.extend(S.patch(valance, 'rear', offset=0.0025, depth=0.006, res=0.0, mat='Trim', smooth=False))
    for sx in (1, -1):
        LR.extend(S.patch(ck.rrect_pts(sx * 0.300, 0.538, 0.110, 0.016, 0.006, n=2), 'rear', offset=0.0055, depth=0.004,
                          res=0.0, mat='ReverseLens', smooth=False))
        LTC.extend(S.patch(ck.rrect_pts(sx * 0.540, 0.538, 0.090, 0.014, 0.006, n=2), 'rear', offset=0.0055,
                           depth=0.004, res=0.0, mat='TaillightLens', smooth=False))
    # diffuser fins under the upswept tail
    for x in (-0.30, -0.15, 0.0, 0.15, 0.30):
        ysf = [-2.410, -2.36, -2.26, -2.12, -2.00]
        profs = []
        for y in ysf:
            zb = BODY.params_at(max(y, -2.405))['zb']
            top = zb + 0.025
            bot = zb - (0.050 if y < -2.30 else (0.040 if y < -2.15 else 0.012))
            profs.append([(x - 0.004, bot), (x + 0.004, bot), (x + 0.004, top), (x - 0.004, top)])
        C.extend(ck.sweep_axis('y', ysf, profs, 'Carbon'))
    # quad exhaust tips (two per side) emerging from the diffuser
    tips = []
    for sx in (1, -1):
        for x in (0.440, 0.565):
            p1 = Vector((sx * x, TAIL_Y - 0.004, 0.452))
            p0 = Vector((sx * x, -2.200, 0.452))
            C.extend(ck.tube(p0, p1, 0.040, 0.034, 'Chrome', 'Trim', n=20, inner_depth=0.06))
            tips.append(p1)
        C.extend(ck.tube(Vector((sx * 0.42, -1.85, 0.215)), Vector((sx * 0.50, -2.20, 0.440)), 0.034, 0.030,
                         'Underbody', 'Underbody', n=12))
    car.socket('Socket_Exhaust', (tips[0] + tips[1]) / 2)
    car.socket('Socket_Exhaust2', (tips[2] + tips[3]) / 2)
    # third brake light on the roof just above the rear window
    LBC.extend(S.patch(ck.rrect_pts(0.0, RW_TOP + 0.020, 0.34, 0.013, 0.006, n=2), 'top', offset=0.0025, depth=0.004,
                       res=0.0, mat='BrakeLens', smooth=False))

    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x(), LTC)
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR)


def _x_to(normal):
    """Rotation matrix taking +X onto `normal`."""
    return Vector((1.0, 0.0, 0.0)).rotation_difference(Vector(normal).normalized()).to_matrix().to_4x4()


def bezel(center, normal, r, mat='Chrome', h=0.010, w=0.007, segs=24):
    """Round bright bezel (ring) standing on `center` around radius r, facing `normal`."""
    prof = [(-0.004, r + w), (h * 0.85, r + w * 0.80), (h, r + w * 0.45), (h * 0.85, r + w * 0.12), (-0.004, r)]
    return ck.revolve(prof, segs, mat).transformed(Matrix.Translation(Vector(center)) @ _x_to(normal))


def recolor(part, mapping):
    part.m = [mapping.get(m, m) for m in part.m]
    return part


def interior(car):
    I = ck.Part()
    # ---- dashboard (profile in (y, z) swept across X): dark top, walnut fascia band, tan leather lower dash
    dash = [(0.445, 0.858), (0.320, 0.890), (0.200, 0.898), (0.125, 0.890), (0.092, 0.872), (0.080, 0.850),
            (0.076, 0.812), (0.082, 0.770), (0.098, 0.725), (0.140, 0.655), (0.210, 0.585), (0.320, 0.505),
            (0.430, 0.480), (0.445, 0.640)]
    dmats = ['InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorDark', 'Interior', 'InteriorWood',
             'InteriorWood', 'Interior', 'Interior', 'Interior', 'InteriorDark', 'InteriorDark', 'InteriorDark',
             'InteriorDark']
    xs = [-0.800, -0.786, -0.60, -0.25, 0.0, 0.25, 0.60, 0.786, 0.800]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < 0.79 else 0.012
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # bright metal strip along the top of the walnut fascia
    I.extend(ck.box_between((-0.775, 0.0838, 0.861), (0.775, 0.0838, 0.861), 0.004, 0.005, 'Chrome', up=(0, 0, 1)))
    # driver's binnacle: two big dials with bright bezels under a leather visor
    xb = [HUB.x - 0.180, HUB.x - 0.170, HUB.x + 0.170, HUB.x + 0.180]
    visor = [(0.140, 0.900), (0.062, 0.922), (0.040, 0.917), (0.046, 0.905), (0.100, 0.893)]
    I.extend(ck.sweep_axis('x', xb, [[(y + (0.006 if k in (0, 3) else 0.0), z - (0.006 if k in (0, 3) else 0.0))
                                      for (y, z) in visor] for k in range(4)], 'InteriorDark'))
    I.extend(ck.box_between((HUB.x - 0.165, 0.074, 0.838), (HUB.x + 0.165, 0.074, 0.838), 0.006, 0.112,
                            'InteriorDark', up=(0, 0, 1)))
    for (dx, nt, r) in ((-0.078, 9, 0.052), (0.078, 11, 0.052)):
        c = Vector((HUB.x + dx, 0.069, 0.840))
        n = EYE - c
        I.extend(ck.gauge(c, n, r, n_ticks=nt))
        I.extend(bezel(c - n.normalized() * 0.002, n, r, h=0.008, w=0.006, segs=24))
    # centre stack: round analogue clock on the walnut fascia, vents, small display, walnut panel
    clk = Vector((0.0, 0.073, 0.818))
    I.extend(ck.gauge(clk, (0, -1, 0.12), 0.038, n_ticks=12, arc=330.0, needle_deg=60.0))
    I.extend(bezel(clk + Vector((0, 0.002, 0)), (0, -1, 0.12), 0.038, h=0.008, w=0.007, segs=24))
    for x in (-0.115, 0.115):
        I.extend(ck.box_between((x - 0.045, 0.080, 0.818), (x + 0.045, 0.080, 0.818), 0.028, 0.030, 'InteriorDark'))
        I.extend(ck.box_between((x - 0.043, 0.0655, 0.818), (x + 0.043, 0.0655, 0.818), 0.003, 0.004, 'Chrome'))
    for x in (-0.64, 0.64):
        I.extend(ck.disc((x, 0.0705, 0.818), (0, -1, 0), 0.030, 'InteriorDark', n=16, ring_mat='Chrome', ring_w=0.005))
    # small display under the clock and a walnut centre-stack panel down to the console
    I.extend(ck.box_between((-0.085, 0.0815, 0.762), (0.085, 0.0815, 0.762), 0.006, 0.054, 'InteriorDark',
                            up=(0, 0, 1)))
    scr = ck.Part()
    for (x0, x1, z0, z1, off, m) in ((-0.074, 0.074, 0.740, 0.784, 0.0, 'InteriorDark'),
                                     (-0.064, -0.010, 0.772, 0.775, 0.0012, 'Gauge'),
                                     (-0.064, -0.030, 0.760, 0.763, 0.0012, 'Gauge'),
                                     (0.006, 0.064, 0.750, 0.775, 0.0012, 'Gauge')):
        q = [scr.vert(Vector((x, 0.0775 - off, z))) for (x, z) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
        scr.face(q, m)
    scr.orient(0, ref=Vector((0, 0.3, 0.76)))
    I.extend(scr)
    I.extend(ck.box_between((0.0, 0.093, 0.728), (0.0, 0.196, 0.500), 0.26, 0.014, 'InteriorWood'))
    # steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.17, 0.064, 0.070, 'InteriorDark'))
    # centre console: wide tunnel from the dash to the rear seats, walnut top, metal gate shifter
    cys = [0.36, 0.22, 0.05, -0.25, -0.55, -0.80]
    tops = [0.540, 0.510, 0.500, 0.520, 0.540, 0.520]
    profs = [[(-0.125, 0.16), (0.125, 0.16), (0.130, t - 0.035), (0.110, t), (-0.110, t), (-0.130, t - 0.035)]
             for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'InteriorWood', 'Interior',
                                             'InteriorDark']))
    I.extend(ck.box_between((0.0, 0.040, 0.505), (0.0, -0.035, 0.508), 0.006, 0.006, 'Chrome', up=(0, 0, 1)))
    I.extend(ck.box_between((0.0, 0.002, 0.500), (0.0, -0.010, 0.640), 0.012, 0.012, 'Chrome'))          # shifter
    I.extend(ck.ellipsoid((0.0, -0.012, 0.652), (0.022, 0.022, 0.024), 'InteriorWood', nu=12, nv=8))
    I.extend(ck.ellipsoid((0.0, 0.002, 0.506), (0.045, 0.055, 0.010), 'InteriorDark', nu=12, nv=6))       # gaiter
    I.extend(ck.box_between((0.0, -0.40, 0.548), (0.0, -0.70, 0.548), 0.17, 0.040, 'Interior'))          # armrest
    # seats: two luxurious front buckets + two small rear seats (tan leather, darker brown side panels)
    cmap = {'InteriorDark': 'InteriorAccent'}
    for x in (-0.380, 0.380):
        I.extend(recolor(ck.bucket_seat(x, 0.060, -0.430, 0.270, width=0.54, recline=21.0, back_h=0.80,
                                        bolster=0.060, headrest_w=0.26), cmap))
    for x in (-0.300, 0.300):
        I.extend(recolor(ck.bucket_seat(x, -0.930, -1.230, 0.272, width=0.42, recline=30.0, back_h=0.52,
                                        bolster=0.045, headrest_w=0.21), cmap))
    # luggage shelf under the fastback glass
    I.extend(ck.box_between((0.0, -1.560, 0.842), (0.0, -1.880, 0.842), 1.08, 0.016, 'InteriorDark'))
    # door cards: tan armrest, walnut capping with metal pull, speaker; mirrored
    door = ck.Part()
    ays = [0.40, 0.37, -0.78, -0.82]
    door.extend(ck.sweep_axis('y', ays, [(0.838, 0.640), (0.856, 0.598), (0.892, 0.596), (0.892, 0.666), (0.844, 0.666)],
                              'Interior'))
    door.extend(ck.box_between((DOOR_X - 0.004, 0.38, 0.755), (DOOR_X - 0.004, -0.80, 0.755), 0.030, 0.010,
                               'InteriorWood', up=(1, 0, 0)))
    door.extend(ck.box_between((0.866, 0.10, 0.720), (0.866, -0.06, 0.720), 0.018, 0.016, 'Chrome'))
    door.extend(ck.disc((0.898, 0.20, 0.42), (-1, 0, 0), 0.060, 'InteriorDark', n=16, ring_mat='Chrome', ring_w=0.004))
    I.extend(door, door.mirrored_x())
    # pedals (metal)
    for x, w in ((-0.47, 0.055), (-0.37, 0.080), (-0.27, 0.055)):
        I.extend(ck.box_between((x, 0.390, 0.215), (x, 0.355, 0.320), w, 0.012, 'Chrome'))
    # sun visors + rear-view mirror
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.13, -0.300, 1.203), (s * 0.44, -0.300, 1.203), 0.12, 0.012, 'Interior'))
    I.extend(ck.box_between((-0.10, -0.150, 1.150), (0.10, -0.150, 1.150), 0.022, 0.050, 'InteriorDark'))
    I.extend(ck.box_between((-0.094, -0.1615, 1.150), (0.094, -0.1615, 1.150), 0.002, 0.042, 'Chrome'))
    I.extend(ck.box_between((0.0, -0.160, 1.172), (0.0, -0.200, 1.220), 0.016, 0.016, 'InteriorDark'))
    car.add('Interior', I)
    # steering wheel (separate object, origin at the hub, local +Y = column toward the dash):
    # dark leather rim, three bright metal spokes, round hub
    car.add('SteeringWheel', ck.steering_wheel_part(R=SW_R, tube_r=(0.0135, 0.0165), segs=40, flat_bottom=False,
                                                    hub_r=0.054, rim_mat='InteriorDark', spoke_mat='Chrome',
                                                    hub_mat='InteriorDark', marker=False, spoke_thick=0.008,
                                                    dish=0.036,
                                                    spokes=((0.0, 0.042), (180.0, 0.042), (270.0, 0.036))),
            ck.disc((0.0, -0.0135, 0.0), (0, -1, 0), 0.028, 'Chrome', n=20, ring_mat='InteriorDark', ring_w=0.004),
            location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W_F, rim_d_in=20, spokes=5, style='single', segs=48,
                  spoke_w=(0.068, -0.030), spoke_thick=0.026, spoke_dish=0.044, hub_r=0.066, nuts=5,
                  disc_r=0.190, caliper_angle=150.0, caliper_span=48.0, grooves=[-0.042, 0.042], groove_w=0.012,
                  rear=dict(W=WHEEL_W_R, grooves=[-0.052, 0.052], disc_r=0.182, caliper_span=42.0))


def build():
    paint = (0.0137, 0.0467, 0.0242)          # #1F3D2B dark British-style green (linear)
    mats = ck.default_materials(paint=paint, paint_metallic=0.55, paint_rough=0.30, paint_coat=0.9,
                                rim=(0.70, 0.70, 0.72), rim_metallic=1.0, rim_rough=0.16,
                                caliper=(0.30, 0.018, 0.024),
                                interior=(0.360, 0.170, 0.072), interior_dark=(0.020, 0.015, 0.012))
    mats['Paint']['coat_rough'] = 0.03
    mats['Interior'] = dict(base=(0.360, 0.170, 0.072), roughness=0.55)       # tan leather
    mats['Glass'] = dict(base=(0.010, 0.014, 0.014), roughness=0.03, alpha=0.30, double_sided=True)
    mats['InteriorWood'] = dict(base=(0.11, 0.040, 0.014), roughness=0.28, coat=0.9, coat_rough=0.04)   # walnut
    mats['InteriorAccent'] = dict(base=(0.140, 0.055, 0.020), roughness=0.60)                             # brown hide
    car = ck.CarAssembly(CAR_ID, CAR_NAME, mats)
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Glass', shell.glass)
    car.add('Interior', shell.inner)
    ck.add_wheels(car, WHEEL_SPEC, axles=dict(front=(YF, TRACK_F / 2), rear=(YR, TRACK_R / 2)))
    if STAGE != 'body':
        body_details(car, shell.surface)
        interior(car)
        car.socket('Socket_CamHood', (0.0, 0.52, 1.005))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.06, 0.45))
    car.finalize()
    car.info['lip_sharp_edges'] = sharpen_arch_lips(car)
    return car, shell


def sharpen_arch_lips(car, min_deg=8.0):
    """Mark the edge where the side panel meets the bevelled arch lip as sharp (no dark band above the wheel)."""
    me = car.objects['Body'].data
    co = [v.co for v in me.vertices]
    efaces = {}
    for p in me.polygons:
        for ek in p.edge_keys:
            efaces.setdefault(ek, []).append(p.index)
    n = 0
    for e in me.edges:
        m = (co[e.vertices[0]] + co[e.vertices[1]]) / 2
        for A in ARCHES:
            if abs(m.x) < A['x_in'] + 0.08:
                continue
            d = math.hypot(m.y - A['y'], m.z - A['z'])
            if A['r'] - 0.006 < d < A['r'] + 0.018:
                fs = efaces.get(e.key, [])
                if len(fs) == 2:
                    n0, n1 = me.polygons[fs[0]].normal, me.polygons[fs[1]].normal
                    side0, side1 = abs(n0.x) > 0.97, abs(n1.x) > 0.97
                    if side0 != side1 and n0.angle(n1) > math.radians(min_deg):
                        e.use_edge_sharp = True
                        n += 1
                break
    me.update()
    return n


RENDER_PATH = os.path.join(PROJECT, 'docs', 'blender_cars', CAR_ID + '.png')
GLB_PATH = os.path.join(PROJECT, 'assets', 'imported', 'cars', CAR_ID + '.glb')
JSON_PATH = os.path.join(PROJECT, 'assets', 'imported', 'cars', CAR_ID + '.json')


def interior_in_wells(car):
    """Count Interior/SteeringWheel vertices that sit inside a wheel-well cavity (visible from outside)."""
    n = 0
    for nm in ('Interior', 'SteeringWheel'):
        ob = car.objects[nm]
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            for a in ARCHES:
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
    SHELL_YS = car.shell.ys
    body = car.objects['Body']
    M = body.matrix_world
    bv = [M @ v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in bv), min(v.y for v in bv), min(v.z for v in bv)))
    mx = Vector((max(v.x for v in bv), max(v.y for v in bv), max(v.z for v in bv)))
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.92 and abs(v.y - 0.33) > 0.15)   # mirrors excluded
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
    roof = max(BODY.params_at(y)['zc'] for y in SHELL_YS)
    return {
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'front-engine grand tourer (2+2 coupe)', 'drivetrain': 'RWD',
        'engine': 'front V12', 'doors': 2, 'seats': 4, 'source_blend': 'Opus55ForzaUltracodeEffort.blend',
        'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(mx.y - mn.y, 4), 'length_body_shell': round(BODY.nose['y'] - BODY.tail['y'], 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(roof, 4), 'height_overall': round(all_mx.z, 4),
        'ground_clearance': round(BODY.params_at(0.0)['zb'], 4), 'ground_clearance_min': round(mn.z, 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'rim_diameter_in': 20,
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
        'default_paint': {'hex': '#1F3D2B', 'linear_rgb': [0.0137, 0.0467, 0.0242], 'finish': 'metallic'},
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
    if STAGE != 'body':
        print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W_R), 'interior verts in wheel wells:', interior_in_wells(CAR),
              'interior leaks:', interior_leaks(CAR))
    if RENDER:
        hidden = isolate(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.6, 6.3, 1.65), target=(0.0, 0.05, 0.55),
                                           lens=50.0, world_strength=0.8, sun_energy=3.4, exposure=0.0))
        finally:
            if not globals().get('KEEP_ISOLATED', False):
                isolate(False)
    elif globals().get('KEEP_ISOLATED', False):
        isolate(True)
    if EXPORT:
        RES, INFO, DATA = export_all(CAR)
        print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
        print('materials', INFO['materials'])
