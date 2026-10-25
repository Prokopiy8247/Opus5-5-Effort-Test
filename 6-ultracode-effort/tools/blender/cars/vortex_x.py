"""Vortex X - mid-engine hypercar-flavoured supercar, 2 seats, AWD (car #6 of Sunward Roads).

Rebuilds Cars/Car_vortex_x from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero
image and exports assets/imported/cars/vortex_x.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\vortex_x.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking).

Spec: L 4.60, W 2.04, H 1.12, wheelbase 2.70, track 1.70 / 1.65, wheel R 0.345 / 0.36 (20" / 21" rims), tyre
width 0.265 / 0.335. Original design (no real brand / model): low wedge, very short front overhang with a deep
carbon splitter and three lower intakes, tall front wing crowns with thin LED headlamp blades, cab-forward black
"bubble" canopy (wrap-around windscreen, black A-pillars and carbon roof), big side intakes scooped into the doors
ahead of the wide rear haunches, body-colour buttresses either side of a small engine glass and a louvred engine
deck, fixed carbon rear wing on two pylons, full-width tail bar, big carbon diffuser with a central exhaust pair,
centre-lock 10-spoke satin-black rims. Metallic orange #E8590C, black alcantara interior with orange accents.
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

CAR_ID = 'vortex_x'
CAR_NAME = 'Vortex X'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
DEBUG = globals().get('DEBUG', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.70
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.35)
TRACK_F, TRACK_R = 1.70, 1.65
WHEEL_R_F, WHEEL_R_R = 0.345, 0.360
WHEEL_W_F, WHEEL_W_R = 0.265, 0.335
ARCH_R_F, ARCH_Z_F = 0.372, 0.352              # ~3 cm visible gap above the tyre
ARCH_R_R, ARCH_Z_R = 0.387, 0.367
NOSE_Y, TAIL_Y = 2.212, -2.388                 # cap poles -> overall length 4.60

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs),
# K3 waist / widest (ww, zw), K4 shoulder (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr), K8 crown (zc).
# Behind the cabin K5 = haunch top, K6 = buttress top (higher than the deck centre K8: sunken engine deck).
# On the hood K5 = front-wing crown, K6 = valley inboard of the wing, K8 = hood centre (well below the crowns).
Y_ENG1 = -1.220          # engine glass rear edge (louvred deck behind it)
Y_ROOF = -0.820          # roof rear edge / engine glass front edge
Y_HEADER = -0.100        # windscreen header
Y_COWL = 0.800           # windscreen base
Y_SAIL = 0.620           # side glass front edge (black sail ahead of it)
S = [
    # ---- tail: flat rear face; the raised engine cover between the lower haunch pods fades into a smooth tail edge
    dict(y=-2.365, zb=0.335, wb=0.48, zs=0.370, ws=0.850, zw=0.570, ww=0.890, zh=0.765, wh=0.860,
         zg=0.815, wg=0.770, zr=0.838, wr=0.640, zc=0.918, rail=0.05, bulge=0.0,
         ks={4: 0.85, 5: 0.4, 6: 0.0, 7: 0.25}),
    dict(y=-2.330, zb=0.315, wb=0.52, zs=0.355, ws=0.890, zw=0.565, ww=0.930, zh=0.775, wh=0.895,
         zg=0.826, wg=0.800, zr=0.834, wr=0.650, zc=0.922, bulge=0.014),
    dict(y=-2.250, zb=0.270, wb=0.56, zs=0.320, ws=0.925, zw=0.555, ww=0.968, zh=0.780, wh=0.930,
         zg=0.835, wg=0.830, zr=0.829, wr=0.665, zc=0.925, bulge=0.034, ks={7: 0.6}),
    dict(y=-2.100, zb=0.210, wb=0.60, zs=0.270, ws=0.955, zw=0.545, ww=1.000, zh=0.790, wh=0.958,
         zg=0.848, wg=0.852, zr=0.832, wr=0.680, zc=0.935, bulge=0.052, ks={7: 0.85}),
    dict(y=-1.850, zb=0.150, wb=0.63, zs=0.230, ws=0.970, zw=0.530, ww=1.015, zh=0.800, wh=0.975,
         zg=0.865, wg=0.865, zr=0.846, wr=0.692, zc=0.952),
    dict(y=-1.600, zb=0.125, wb=0.65, zs=0.215, ws=0.975, zw=0.520, ww=1.020, zh=0.806, wh=0.980,
         zg=0.878, wg=0.870, zr=0.858, wr=0.700, zc=0.968),
    dict(y=YR, zb=0.115, wb=0.66, zs=0.210, ws=0.975, zw=0.510, ww=1.020, zh=0.808, wh=0.980,
         zg=0.884, wg=0.870, zr=0.866, wr=0.702, zc=0.983, bulge=0.068),
    dict(y=Y_ENG1, zw=0.500, ww=1.015, zh=0.802, wh=0.972, zg=0.880, wg=0.866, zr=0.872, wr=0.700, zc=0.993,
         bulge=0.064),
    # ---- haunch leading edge (crisp) / side intake scoop (upper side pulled in under the beltline lip)
    dict(y=-1.050, zb=0.110, zs=0.205, ws=0.965, zw=0.480, ww=1.000, zh=0.790, wh=0.940, zg=0.866, wg=0.858,
         zr=0.895, wr=0.690, zc=1.013, rail=0.05, bulge=0.050, sharp=dict(wh=0.8, zh=0.4),
         ks={4: 0.85}),
    dict(y=-0.920, zw=0.455, ww=0.962, zh=0.745, wh=0.815, zg=0.848, wg=0.850, zr=0.940, wr=0.665, zc=1.033,
         bulge=0.022, ks={4: 0.35}),
    dict(y=Y_ROOF, zw=0.450, ww=0.956, zh=0.735, wh=0.835, zg=0.835, wg=0.855, zr=0.995, wr=0.645, zc=1.055,
         bulge=0.0),
    # ---- cabin: black bubble canopy (low beltline, strong tumblehome, domed roof); door scoop deepens rearward
    dict(y=-0.700, zs=0.200, ws=0.945, zw=0.445, ww=0.955, zh=0.725, wh=0.860, zg=0.820, wg=0.860,
         zr=1.025, wr=0.638, zc=1.085, ks={4: 0.5}),
    dict(y=-0.400, zw=0.440, ww=0.958, zh=0.712, wh=0.905, zg=0.800, wg=0.870, zr=1.045, wr=0.640, zc=1.120),
    dict(y=Y_HEADER, zw=0.440, ww=0.968, zh=0.705, wh=0.935, zg=0.795, wg=0.875, zr=1.030, wr=0.690, zc=1.100,
         sharp=dict(zc=0.5, zr=0.5, wr=0.3), ks={4: 0.85}),
    dict(y=0.350, zw=0.450, ww=0.975, zh=0.700, wh=0.945, zg=0.790, wg=0.880, zr=0.905, wr=0.770, zc=0.950),
    dict(y=Y_COWL, zb=0.110, wb=0.66, zs=0.205, ws=0.950, zw=0.460, ww=0.985, zh=0.700, wh=0.955,
         zg=0.775, wg=0.890, zr=0.790, wr=0.835, zc=0.785, sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- front: tall wing crowns either side of a low hood, very short overhang, arrow-shaped plan
    dict(y=0.900, zw=0.465, ww=0.990, zh=0.725, wh=0.966, zg=0.790, wg=0.896, zr=0.752, wr=0.700, zc=0.763,
         rail=0.05),
    dict(y=1.000, zb=0.110, zs=0.205, ws=0.955, zw=0.470, ww=0.995, zh=0.745, wh=0.975, zg=0.800, wg=0.900,
         zr=0.725, wr=0.640, zc=0.738, rail=0.05, ks={5: 0.55, 7: 0.30}),
    dict(y=YF, zb=0.110, wb=0.64, zs=0.210, ws=0.955, zw=0.480, ww=1.005, zh=0.775, wh=0.985, zg=0.815,
         wg=0.895, zr=0.695, wr=0.600, zc=0.685),
    dict(y=1.650, zb=0.115, wb=0.62, zs=0.215, ws=0.945, zw=0.465, ww=0.995, zh=0.765, wh=0.975, zg=0.780,
         wg=0.880, zr=0.655, wr=0.570, zc=0.630),
    dict(y=1.850, zb=0.120, wb=0.58, zs=0.220, ws=0.910, zw=0.450, ww=0.968, zh=0.705, wh=0.950, zg=0.720,
         wg=0.858, zr=0.600, wr=0.540, zc=0.575),
    dict(y=1.980, zb=0.125, wb=0.53, zs=0.222, ws=0.855, zw=0.440, ww=0.915, zh=0.655, wh=0.895, zg=0.670,
         wg=0.815, zr=0.560, wr=0.505, zc=0.535),
    dict(y=2.070, zb=0.130, wb=0.47, zs=0.225, ws=0.775, zw=0.430, ww=0.830, zh=0.605, wh=0.815, zg=0.615,
         wg=0.745, zr=0.518, wr=0.460, zc=0.498),
    dict(y=2.130, zb=0.135, wb=0.40, zs=0.228, ws=0.665, zw=0.420, ww=0.715, zh=0.555, wh=0.705, zg=0.565,
         wg=0.650, zr=0.480, wr=0.405, zc=0.460),
    dict(y=2.175, zb=0.145, wb=0.32, zs=0.232, ws=0.520, zw=0.410, ww=0.565, zh=0.495, wh=0.555, zg=0.505,
         wg=0.515, zr=0.442, wr=0.335, zc=0.426),
    dict(y=2.200, zb=0.160, wb=0.24, zs=0.240, ws=0.385, zw=0.400, ww=0.420, zh=0.445, wh=0.415, zg=0.455,
         wg=0.380, zr=0.412, wr=0.260, zc=0.398),
]

# side glass: its rear edge leans forward going up, following the canopy (belt y=-0.76, rail y=-0.44)
WARP_Y = -0.600
WARP = dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-0.760, -0.440), margin=0.20)
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),       # wrap-around windscreen
    dict(bands=(6, 6), y=(Y_ROOF, Y_COWL), role='trim'),          # black A-pillars + roof rails
    dict(bands=(7, 7), y=(Y_ROOF, Y_HEADER), role='carbon'),      # carbon roof
    dict(bands=(5, 5), y=(Y_ROOF, WARP_Y), role='trim'),          # black C-pillar (canopy reads as one bubble)
    dict(bands=(5, 5), y=(WARP_Y, Y_SAIL), role='glass'),         # side glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),          # mirror sail
    dict(bands=(7, 7), y=(Y_ENG1, Y_ROOF), role='glass'),         # small engine glass between the buttresses
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.045), role='trim'),  # cowl panel
    dict(bands=(0, 1), y=(-2.400, -1.800), role='carbon'),        # diffuser ramp (carbon underside)
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[2, 2, 5, 5, 3, 5, 2, 7],
    key_sharp=(0, 0.7, 0.5, 0.55, 0.85, 0.45, 0.45, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.310, tilt=4.0, k_edge=1.8, k_face=2.6, rings=8),
    tail=dict(y=TAIL_Y, z=0.630, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8),
    step=0.05,
    rail=0.05,
    warps=[WARP],
)

ARCHES = [dict(y=YF, z=ARCH_Z_F, r=ARCH_R_F, x_in=0.660), dict(y=YR, z=ARCH_Z_R, r=ARCH_R_R, x_in=0.620)]
INNER = dict(y=(-1.280, Y_COWL + 0.040), d=0.035,
             tubs=[(YR, ARCH_Z_R, ARCH_R_R + 0.03, 0.605)])


EYE = Vector((-0.360, -0.460, 0.975))        # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.360, -0.060, 0.720))        # steering wheel hub
COLUMN_TILT = 20.0                           # deg, column descends toward the dash
SW_R = 0.165                                 # steering wheel radius
Y_BULK = -0.800                              # cabin / engine-bay bulkhead
D_IN = INNER['d']


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
    """Lamp: housing patch + inset inner patch. Returns (housing, inner, frame, pts2d)."""
    pts = snap_pts(S, spec)
    housing, frame = S.patch3d(pts, offset=house_off, depth=0.006, res=res, mat=house_mat, sub=4)
    O, U, V, D = frame
    pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in pts]
    inner = S.patch(ck.offset_poly(ck.cr_resample(pts2d, True, 4), -inset), frame, offset=inner_off, depth=0.004,
                    res=res * 0.9, mat=inner_mat, smooth=False)
    return housing, inner, frame, pts2d


def surface_path(S, view, pts2d, lift=0.0):
    """Snap 2D points (view coords) to the shell, raised `lift` along the surface normal."""
    fr = S.frame(view)
    out = []
    for a, b in pts2d:
        loc, nor = S.hit(fr, a, b)
        if loc is not None:
            out.append((loc + nor * lift, nor))
    return out


def blade(S, view, pts2d, prof, mat, lift=0.0):
    """Thin profile (u, v) swept along a surface-snapped path (louvres, strakes)."""
    sp = surface_path(S, view, pts2d, lift)
    return ck.sweep_path([p for p, n in sp], prof, mat, up=(0, 0, 1))


def airfoil(chord, thick, camber=-0.045, p=0.42, n=9):
    """Cambered NACA-style section in (s, h): s 0..chord from the leading edge, negative camber (downforce).
    Returns a closed loop: trailing edge -> upper surface -> leading edge -> lower surface."""
    up, lo = [], []
    for k in range(n + 1):
        u = 0.5 * (1 - math.cos(math.pi * k / n))
        yt = 5 * thick * (0.2969 * math.sqrt(u) - 0.1260 * u - 0.3516 * u ** 2 + 0.2843 * u ** 3 - 0.1036 * u ** 4)
        yc = camber / p ** 2 * (2 * p * u - u * u) if u < p else camber / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * u - u * u)
        up.append((u * chord, (yc + yt) * chord))
        lo.append((u * chord, (yc - yt) * chord))
    return list(reversed(up)) + lo[1:-1]


def hood_line():
    """Right half of the front-lid shut line: along the valley inboard of the wing crown, then across the nose."""
    pts = [BODY.point(y, 6.0) for y in (Y_COWL + 0.065, 1.00, 1.20, YF, 1.55, 1.75, 1.92, 2.02)]
    for k in range(1, 9):
        u = k / 8.0
        pts.append(BODY.point(2.02 + 0.09 * (u ** 1.3), 6.0 + 2.0 * u))
    return pts


def body_details(car, S):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LBC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    D = ck.densify
    B = S.frame('rear')
    _t = [0]

    def tick(label):
        n = R.tris() * 2 + C.tris()
        if DEBUG:
            print('  %-14s %6d tris' % (label, n - _t[0]))
        _t[0] = n

    # ================= front: three lower intakes, black chin, deep carbon splitter with fences
    mouth = D(ck.fillet_poly([(-0.355, 0.180), (0.355, 0.180), (0.400, 0.255), (0.345, 0.335), (-0.345, 0.335),
                              (-0.400, 0.255)], [0.02, 0.02, 0.025, 0.02, 0.02, 0.025], n=4), 0.04)
    C.extend(S.honeycomb(mouth, 'front', cell=0.060, wall=0.0065, base_offset=0.0025, height=0.008, margin=0.004,
                         smooth=False, res=0.040))
    C.extend(S.rim(mouth, 'front', width=0.012, offset=0.010, depth=0.007, mat='Trim', smooth=False))
    side_in = D(ck.fillet_poly([(0.470, 0.180), (0.735, 0.180), (0.775, 0.250), (0.735, 0.392), (0.520, 0.352),
                                (0.448, 0.262)], [0.015, 0.02, 0.03, 0.02, 0.02, 0.015], n=3), 0.03)
    R.extend(S.patch(side_in, 'front', offset=0.0025, depth=0.006, res=0.03, mat='Grille', smooth=False))
    R.extend(S.rim(side_in, 'front', width=0.011, offset=0.0095, depth=0.007, mat='Trim', smooth=False))
    for x0 in (0.548, 0.618, 0.688):
        R.extend(S.line(D([(x0, 0.192), (x0 + 0.010, 0.360)], 0.02, closed=False), 'front', width=0.008, offset=0.008,
                        mat='Trim', smooth=False, step=0.02))
    chin = D(ck.fillet_poly([(-0.70, 0.160), (0.70, 0.160), (0.74, 0.178), (-0.74, 0.178)], 0.004, n=2), 0.04)
    C.extend(S.patch(chin, 'front', offset=0.002, depth=0.005, res=0.0, mat='Trim', smooth=False))
    xs = [-0.74 + 1.48 * k / 32 for k in range(33)]
    front = []
    for x in xs:
        p = S.snap('front', x, 0.175)
        front.append((x, (p.y if p is not None else 1.90) + 0.022 + 0.018 * max(0.0, 1.0 - abs(x) / 0.6)))
    prof = front + [(0.66, 1.80), (-0.66, 1.80)]
    prof = list(reversed(prof)) if ck.poly_area(prof) < 0 else prof
    C.extend(ck.sweep_axis('z', [0.094, 0.112], prof, 'Carbon'))
    for sx in (1, -1):
        yf = S.snap('front', 0.47, 0.175).y
        C.extend(ck.box_between((sx * 0.47, yf - 0.05, 0.138), (sx * 0.47, yf + 0.030, 0.138), 0.008, 0.052, 'Carbon'))
    tick('front')
    # ================= thin LED headlamp blades on the wing fronts
    hl_spec = [('front', 0.418, 0.441), ('front', 0.52, 0.461), ('front', 0.63, 0.490), ('front', 0.74, 0.525),
               ('front', 0.832, 0.556), ('front', 0.842, 0.582), ('front', 0.74, 0.556), ('front', 0.63, 0.521),
               ('front', 0.52, 0.490), ('front', 0.418, 0.467)]
    housing, inner, frame, p2 = lamp(S, hl_spec, 'Trim', 'HeadlightLens', inset=0.0045, res=0.015)
    R.extend(housing)
    LH.extend(inner)
    hc = sum((v for v in inner.v), Vector()) / max(1, len(inner.v))
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))

    tick('headlamps')
    # ================= front lid: shut line, central heat-extractor vent; louvres on the wing crowns
    R.extend(S.line3d(hood_line(), step=0.06))
    vent = D(ck.fillet_poly([(-0.25, 1.60), (0.25, 1.60), (0.19, 1.86), (-0.19, 1.86)], 0.025, n=3), 0.03)
    C.extend(S.patch(vent, 'top', offset=0.0015, depth=0.005, res=0.045, mat='Grille', smooth=False))
    C.extend(S.rim(vent, 'top', width=0.012, offset=0.006, depth=0.005, mat='Trim', smooth=False))
    for k in range(5):
        yv = 1.640 + k * 0.045
        hw = 0.250 - 0.24 * (yv - 1.60) - 0.020
        C.extend(blade(S, 'top', [(-hw + (2 * hw) * j / 4, yv) for j in range(5)],
                       [(-0.006, -0.002), (0.006, -0.002), (0.011, 0.009), (0.000, 0.009)], 'Carbon'))
    wl = D(ck.fillet_poly([(0.738, 1.020), (0.872, 1.030), (0.880, 1.240), (0.748, 1.250)], 0.012, n=2), 0.03)
    R.extend(S.patch(wl, 'top', offset=0.0015, depth=0.005, res=0.035, mat='Grille', smooth=False))
    R.extend(S.rim(wl, 'top', width=0.008, offset=0.005, depth=0.004, mat='Trim', smooth=False))
    for k in range(5):
        yv = 1.056 + k * 0.042
        R.extend(blade(S, 'top', [(0.752 + 0.12 * j / 4, yv) for j in range(5)],
                       [(-0.005, -0.002), (0.005, -0.002), (0.009, 0.007), (0.000, 0.007)], 'Paint'))
    tick('hood+louvres')
    # single centre wiper parked at the base of the windscreen
    a0 = S.snap('top', -0.56, Y_COWL - 0.050) + Vector((0, 0, 0.012))
    a1 = S.snap('top', 0.34, Y_COWL - 0.068) + Vector((0, 0, 0.012))
    C.extend(ck.box_between(a0, a1, 0.015, 0.009, 'Trim'))
    pivot = S.snap('top', 0.02, Y_COWL + 0.028) + Vector((0, 0, 0.010))
    C.extend(ck.box_between(pivot, (a0 + a1) / 2 + Vector((0, 0, 0.007)), 0.011, 0.007, 'Trim'))
    C.extend(ck.ellipsoid(pivot, (0.016, 0.016, 0.009), 'Trim', nu=10, nv=6))

    tick('wiper')
    # ================= side: carbon skirts, door shut lines, flush handle, side intake, mirrors
    ys = [-0.945, -0.925, -0.86, -0.40, 0.0, 0.40, 0.86, 0.935, 0.955]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        k = 0.35 if abs(y) > 0.94 else (0.8 if abs(y) > 0.92 else 1.0)
        profs.append([(ws - 0.030, zs + 0.034), (ws + 0.004 * k, zs + 0.031), (ws + 0.014 * k, zs + 0.002),
                      (ws + 0.034 * k, zs - 0.062 * k), (ws + 0.030 * k, zs - 0.077 * k), (ws - 0.030, zs - 0.073)])
    R.extend(ck.sweep_axis('y', ys, profs, 'Carbon'))
    R.extend(S.line([(0.885, 0.245), (0.892, 0.45), (0.878, 0.62), (0.845, 0.735), (0.805, 0.772)], 'right', step=0.03))
    R.extend(S.line([(-0.690, 0.240), (-0.700, 0.45), (-0.716, 0.62), (-0.748, 0.800)], 'right', step=0.03))
    R.extend(S.patch(D(ck.rrect_pts(-0.470, 0.742, 0.145, 0.026, 0.011, n=3), 0.02), 'right', offset=0.0012,
                     depth=0.004, res=0.0, mat='Trim', smooth=False))
    tick('skirt+lines')
    sid = D(ck.fillet_poly([(-0.790, 0.540), (-0.975, 0.540), (-1.030, 0.640), (-1.046, 0.790), (-0.900, 0.818),
                            (-0.775, 0.750)], [0.03, 0.025, 0.03, 0.03, 0.04, 0.03], n=3), 0.03)
    R.extend(S.patch(sid, 'right', offset=0.002, depth=0.008, res=0.032, mat='Grille', smooth=False))
    R.extend(S.rim(sid, 'right', width=0.010, offset=0.007, depth=0.006, mat='Trim', smooth=False))
    for z, y1 in ((0.630, -1.012), (0.715, -1.036)):
        R.extend(blade(S, 'right', [(-0.790 + (y1 + 0.790) * j / 6, z + 0.004 * j / 6) for j in range(7)],
                       [(-0.004, -0.004), (0.004, -0.004), (0.006, 0.014), (-0.002, 0.014)], 'Carbon', lift=0.004))
    tick('side intake')
    mc = Vector((1.030, 0.600, 0.878))
    ry = 0.052

    def flat_back(p):
        if p.y < -ry * 0.25:
            p.y = -ry * 0.25 - (p.y + ry * 0.25) * 0.08
        return p
    mirror = ck.ellipsoid(mc, (0.088, ry, 0.043), 'Paint', nu=14, nv=8, exp=3.0, deform=flat_back)
    for fi in range(len(mirror.f)):
        if mirror.face_center(fi).z < mc.z - 0.022:
            mirror.m[fi] = 'Carbon'
    R.extend(mirror)
    glass_pts = ck.superellipse_pts(0.0, 0.0, 0.072, 0.034, e=2.6, n=20)
    mg = ck.Part()
    cen = mg.vert(mc + Vector((0, -ry * 0.25 - 0.003, 0)))
    ring = [mg.vert(mc + Vector((p.x, -ry * 0.25 - 0.003, p.y))) for p in glass_pts]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    base = S.snap('right', 0.665, 0.772)
    R.extend(ck.box_between(base + Vector((-0.012, 0.0, 0.004)), mc + Vector((-0.058, 0.006, -0.014)), 0.034, 0.014,
                            'Carbon'))
    # brake-cooling outlet behind the rear wheel (dark slot with a black frame)
    rv = D(ck.fillet_poly([(-1.865, 0.405), (-1.925, 0.420), (-1.935, 0.640), (-1.880, 0.655)], 0.012, n=2), 0.03)
    R.extend(S.patch(rv, 'right', offset=0.0015, depth=0.005, res=0.0, mat='Grille', smooth=False))
    R.extend(S.rim(rv, 'right', width=0.008, offset=0.005, depth=0.005, mat='Trim', smooth=False))
    fuel = ck.rrect_pts(0.815, -1.600, 0.105, 0.085, 0.022, n=3)
    C.extend(S.line(fuel, 'top', closed=True, smooth=False))                                   # right side only

    tick('mirror+fuel')
    # ================= rear: full-width tail bar, mesh outlets, plate recess, diffuser, central exhaust pair
    bar = D(ck.fillet_poly([(-0.860, 0.743), (0.860, 0.743), (0.872, 0.755), (0.860, 0.767), (-0.860, 0.767),
                            (-0.872, 0.755)], 0.004, n=2), 0.04)
    C.extend(S.patch(ck.offset_poly(bar, 0.008), 'rear', offset=0.0020, depth=0.005, res=0.0, mat='Trim', smooth=False))
    LT.extend(S.patch(bar, 'rear', offset=0.0042, depth=0.004, res=0.0, mat='TaillightLens', smooth=False))
    brake = D(ck.fillet_poly([(0.600, 0.745), (0.858, 0.745), (0.869, 0.755), (0.858, 0.765), (0.600, 0.765)],
                             0.003, n=2), 0.03)
    LB.extend(S.patch(brake, 'rear', offset=0.0058, depth=0.003, res=0.0, mat='BrakeLens', smooth=False))
    for x in (0.12, 0.24, 0.36, 0.48):
        R.extend(S.patch(ck.rrect_pts(x, 0.755, 0.004, 0.026, 0.0015, n=1), 'rear', offset=0.0060, depth=0.003,
                         res=0.0, mat='Trim', smooth=False))
    tick('tail bar')
    outlet = D(ck.fillet_poly([(0.315, 0.452), (0.800, 0.452), (0.835, 0.530), (0.805, 0.688), (0.345, 0.688),
                               (0.315, 0.610)], [0.02, 0.025, 0.03, 0.03, 0.02, 0.02], n=3), 0.05)
    R.extend(S.honeycomb(outlet, 'rear', cell=0.074, wall=0.0080, base_offset=0.002, height=0.009, margin=0.004,
                         smooth=False, res=0.0))
    R.extend(S.rim(outlet, 'rear', width=0.012, offset=0.011, depth=0.006, mat='Trim', smooth=False))
    tick('outlets')
    plate = D(ck.rrect_pts(0.0, 0.572, 0.520, 0.118, 0.012, n=2), 0.05)
    C.extend(S.patch(plate, 'rear', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    C.extend(S.rim(plate, 'rear', width=0.011, offset=0.0060, depth=0.005, mat='Trim', smooth=False))
    dl = D(ck.fillet_poly([(-0.845, 0.350), (0.845, 0.350), (0.872, 0.395), (0.845, 0.430), (-0.845, 0.430),
                           (-0.872, 0.395)], 0.010, n=2), 0.05)
    C.extend(S.patch(dl, 'rear', offset=0.003, depth=0.006, res=0.05, mat='Carbon', smooth=False, walls=False))
    for x in (0.18, 0.40, 0.62):
        ysf = [-2.398, -2.30, -2.15, -1.98, -1.82]
        profs = []
        for y in ysf:
            zb = BODY.params_at(max(y, -2.365))['zb']
            top = zb + 0.018
            bot = 0.130 + (-1.82 - y) * 0.070
            profs.append([(x - 0.004, bot), (x + 0.004, bot), (x + 0.004, top), (x - 0.004, top)])
        R.extend(ck.sweep_axis('y', ysf, profs, 'Carbon'))
    for sx in (1, -1):
        LR.extend(S.patch(ck.rrect_pts(sx * 0.560, 0.390, 0.100, 0.020, 0.008, n=2), 'rear', offset=0.0068, depth=0.004,
                          res=0.0, mat='ReverseLens', smooth=False))
    tips = []
    for x in (0.098, -0.098):
        loc, nor = S.hit(B, x, 0.392)
        sur = D(ck.superellipse_pts(x, 0.392, 0.064, 0.050, e=3.0, n=24), 0.02)
        C.extend(S.patch(sur, 'rear', offset=0.0065, depth=0.006, res=0.03, mat='Grille', smooth=False))
        p0 = Vector((x, loc.y + 0.10, 0.392))
        p1 = Vector((x, loc.y - 0.012, 0.392))
        C.extend(ck.tube(p0, p1, 0.046, 0.039, 'Chrome', 'Trim', n=20, inner_depth=0.06))
        tips.append(p1)
    tick('plate+diffuser')
    car.socket('Socket_Exhaust', tips[0])
    car.socket('Socket_Exhaust2', tips[1])

    # ================= louvred engine deck behind the engine glass
    lv = D(ck.fillet_poly([(-0.455, -2.000), (0.455, -2.000), (0.500, -1.320), (-0.500, -1.320)], 0.03, n=3), 0.05)
    C.extend(S.patch(lv, 'top', offset=0.0015, depth=0.006, res=0.090, mat='Grille', smooth=False, walls=False))
    C.extend(S.rim(lv, 'top', width=0.012, offset=0.007, depth=0.006, mat='Trim', smooth=False))
    for k in range(12):
        yv = -1.368 - k * 0.0548
        hw = 0.495 - 0.045 * (-1.32 - yv) / 0.68 - 0.022
        C.extend(blade(S, 'top', [(-hw + 2 * hw * j / 6, yv) for j in range(7)],
                       [(-0.007, -0.002), (0.007, -0.002), (0.013, 0.011), (-0.001, 0.011)], 'Paint'))

    tick('deck louvres')
    # ================= fixed carbon rear wing on two pylons (+ third brake lamp on the trailing edge)
    Y_LE, Z_LE, CHORD, AOA = -1.975, 1.030, 0.300, math.radians(7.0)
    foil = airfoil(CHORD, 0.11)
    xs = [-0.865, -0.80, -0.55, -0.25, 0.0, 0.25, 0.55, 0.80, 0.865]
    profs = []
    for x in xs:
        dz = 0.010 * (abs(x) / 0.865) ** 2
        profs.append([(Y_LE - s * math.cos(AOA), Z_LE + dz + s * math.sin(AOA) + h * math.cos(AOA)) for (s, h) in foil])
    C.extend(ck.sweep_axis('x', xs, profs, 'Carbon'))
    y_te = Y_LE - CHORD * math.cos(AOA)
    z_te = Z_LE + CHORD * math.sin(AOA)
    C.extend(ck.box_between((-0.86, y_te + 0.004, z_te + 0.011), (0.86, y_te + 0.004, z_te + 0.011), 0.004, 0.018,
                            'Carbon'))                                                             # gurney flap
    LBC.extend(ck.box_between((-0.20, y_te - 0.0005, z_te + 0.005), (0.20, y_te - 0.0005, z_te + 0.005), 0.003, 0.008,
                              'BrakeLens'))
    plate_p = [(-1.935, 0.985), (-2.325, 0.985), (-2.345, 1.120), (-2.150, 1.112), (-1.950, 1.060)]
    for sx in (1, -1):
        xa, xb = sorted((sx * 0.865, sx * 0.877))
        C.extend(ck.sweep_axis('x', [xa, xb], plate_p, 'Carbon'))
    for sx in (1, -1):
        x = sx * 0.320
        zdeck = S.snap('top', x, -2.10).z
        pr0 = [(x - 0.006, -2.020), (x + 0.006, -2.020), (x + 0.007, -2.085), (x + 0.005, -2.150), (x - 0.005, -2.150),
               (x - 0.007, -2.085)]
        pr1 = [(px, py - 0.035) for (px, py) in pr0]
        C.extend(ck.sweep_axis('z', [zdeck - 0.012, Z_LE + 0.012], [pr0, pr1], 'Carbon'))

    tick('wing')
    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT)
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR)


def engine_bay(car):
    """Louvred body-colour engine cover, carbon base and chrome strut brace seen through the engine glass."""
    E = ck.Part()
    E.extend(ck.box_between((0.0, Y_BULK - 0.030, 0.800), (0.0, -1.265, 0.800), 1.24, 0.020, 'Grille'))
    for k in range(8):
        y = -0.885 - k * 0.042
        E.extend(ck.box_between((-0.400, y, 0.832), (0.400, y, 0.832), 0.024, 0.050, 'Paint', up=(0, -0.35, 1.0)))
    for sx in (1, -1):
        E.extend(ck.box_between((sx * 0.500, -0.850, 0.835), (sx * 0.500, -1.230, 0.835), 0.130, 0.060, 'Carbon'))
        E.extend(ck.box_between((sx * 0.120, -0.850, 0.812), (sx * 0.120, -1.230, 0.812), 0.012, 0.022, 'Chrome'))
    E.extend(ck.box_between((-0.58, -1.205, 0.885), (0.58, -1.205, 0.885), 0.022, 0.022, 'Chrome'))
    for sx in (1, -1):
        E.extend(ck.ellipsoid((sx * 0.58, -1.205, 0.885), (0.020, 0.020, 0.020), 'Chrome', nu=10, nv=6))
    car.add('Body', E)


def accent(part, src='Interior', dst='InteriorAccent'):
    part.m = [dst if m == src else m for m in part.m]
    return part


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


def harness(x, y_back=-0.320, z_base=0.262, recline=24.0, back_h=0.74):
    """Orange 4-point harness on a kit bucket seat (same backrest transform as ck.bucket_seat)."""
    Mb = Matrix.Translation((x, y_back - 0.05, z_base + 0.05)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    nrm = (Mb.to_3x3() @ Vector((0, 1, 0))).normalized()
    H = ck.Part()
    for dx in (-0.072, 0.072):
        t0 = 0.11 - 0.02 * (0.55 / back_h) + 0.006
        t1 = 0.11 - 0.02 * (0.08 / back_h) + 0.006
        a = Mb @ Vector((dx, t0, 0.55))
        b = Mb @ Vector((dx * 0.55, t1, 0.08))
        H.extend(ck.box_between(a, b, 0.042, 0.004, 'InteriorAccent', up=tuple(nrm)))
    ym = y_back + 0.14
    zc = z_base + 0.115
    H.extend(ck.box_between((x - 0.20, ym, zc), (x + 0.20, ym, zc), 0.042, 0.004, 'InteriorAccent'))
    H.extend(ck.box_between((x, ym + 0.01, zc + 0.004), (x, ym - 0.01, zc + 0.004), 0.050, 0.010, 'Interior'))
    return H


def interior(car):
    I = ck.Part()
    # ---- low slim dashboard (profile (y, z) swept across X)
    dash = [(0.780, 0.722), (0.600, 0.768), (0.420, 0.790), (0.280, 0.795), (0.200, 0.787), (0.168, 0.768),
            (0.158, 0.735), (0.166, 0.690), (0.200, 0.640), (0.280, 0.582), (0.420, 0.522), (0.600, 0.472),
            (0.780, 0.560)]
    dmats = ['InteriorDark'] * 5 + ['InteriorAccent'] + ['InteriorDark'] + ['Interior'] * 3 + ['InteriorDark'] * 3
    xs = [-0.700, -0.688, -0.55, -0.2, 0.0, 0.2, 0.55, 0.688, 0.700]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < 0.69 else 0.012
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # ---- driver display pod: slim housing, digital screen, central rev dial, facing the eye
    c = Vector((HUB.x, 0.205, 0.822))
    n = (EYE - c).normalized()
    side = Vector((1, 0, 0))
    vdir = n.cross(side).normalized()
    if vdir.z < 0:
        vdir = -vdir
    I.extend(ck.box_between(c + Vector((-0.150, 0, 0)) - n * 0.012, c + Vector((0.150, 0, 0)) - n * 0.012, 0.024, 0.090,
                            'InteriorDark', up=tuple(vdir)))
    scr = ck.Part()
    quads = [(-0.140, 0.140, -0.040, 0.040, 'InteriorDark', 0.0012)]
    for sgn in (-1, 1):                               # digital read-outs: thin lit bars either side of the dial
        for k, ln in enumerate((0.060, 0.045, 0.052, 0.030)):
            u0 = sgn * 0.062 if sgn > 0 else -0.062 - ln
            v0 = -0.024 + k * 0.014
            quads.append((u0, u0 + ln, v0, v0 + 0.0045, 'Gauge', 0.0022))
    for (u0, u1, v0, v1, m, off) in quads:
        q = [scr.vert(c + side * u + vdir * v + n * off) for (u, v) in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
        scr.face(q, m)
    scr.orient(0, ref=c - n * 0.05)
    I.extend(scr)
    I.extend(ck.gauge(c + n * 0.0025, n, 0.034, n_ticks=11))
    # ---- steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.26, 0.068, 0.076, 'InteriorDark'))
    # ---- high centre tunnel with gear buttons and a starter button
    cys = [0.640, 0.500, 0.320, 0.050, -0.250, -0.550, -0.740]
    tops = [0.690, 0.620, 0.520, 0.455, 0.470, 0.505, 0.505]
    profs = [[(-0.115, 0.150), (0.115, 0.150), (0.120, t - 0.03), (0.095, t), (-0.095, t), (-0.120, t - 0.03)]
             for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'InteriorDark', 'Interior',
                                             'InteriorDark']))
    for k, x in enumerate((-0.050, 0.0, 0.050)):
        I.extend(ck.box_between((x, 0.300, 0.536), (x, 0.262, 0.528), 0.030, 0.012, 'Gauge' if k == 1 else 'Interior'))
    I.extend(ck.box_between((0.0, 0.420, 0.585), (0.0, 0.405, 0.592), 0.034, 0.016, 'InteriorAccent'))
    # ---- two racing buckets (orange alcantara centres)
    for x in (-0.360, 0.360):
        I.extend(ck.bucket_seat(x, 0.160, -0.320, 0.262, width=0.50, recline=24.0, back_h=0.74, bolster=0.10,
                                headrest_w=0.25))
        I.extend(harness(x))
    # ---- door cards: armrest pad, orange pull strap, speaker
    door = ck.Part()
    ays = [0.520, 0.480, -0.300, -0.340]
    xa = min(inner_x(y, 0.640) for y in (0.5, 0.2, -0.1, -0.34)) - 0.006
    door.extend(ck.sweep_axis('y', ays, [(xa - 0.050, 0.605), (xa - 0.032, 0.575), (xa, 0.572), (xa, 0.634),
                                         (xa - 0.044, 0.634)], 'InteriorDark'))
    xs_ = inner_x(0.10, 0.70) - 0.008
    door.extend(ck.box_between((xs_, 0.35, 0.700), (xs_, -0.15, 0.700), 0.008, 0.020, 'InteriorAccent', up=(1, 0, 0)))
    door.extend(ck.disc((inner_x(0.35, 0.42) - 0.006, 0.35, 0.42), (-1, 0, 0), 0.055, 'InteriorDark', n=16))
    I.extend(door, door.mirrored_x())
    # ---- pedals, footrest
    for x, w in ((-0.465, 0.050), (-0.375, 0.075), (-0.285, 0.050)):
        I.extend(ck.box_between((x, 0.680, 0.210), (x, 0.640, 0.320), w, 0.012, 'InteriorDark'))
    I.extend(ck.box_between((-0.58, 0.690, 0.200), (-0.58, 0.640, 0.290), 0.070, 0.012, 'Interior'))
    # ---- rear-view mirror at the header
    I.extend(ck.box_between((-0.095, Y_HEADER + 0.030, 1.030), (0.095, Y_HEADER + 0.030, 1.030), 0.020, 0.045,
                            'InteriorDark'))
    I.extend(ck.box_between((0.0, Y_HEADER + 0.020, 1.050), (0.0, Y_HEADER - 0.010, 1.070), 0.016, 0.016,
                            'InteriorDark'))
    # ---- bulkhead behind the seats (separates the cabin from the engine bay)
    ring = BODY.ring_at(Y_BULK, d=D_IN + 0.006)
    bh = ck.Part()
    idx = [bh.vert(p) for p in ring]
    bh.face(idx, 'InteriorDark')
    if bh.face_normal(0).y < 0:
        bh.f[0] = tuple(reversed(bh.f[0]))
    I.extend(bh)
    car.add('Interior', I)
    # ---- flat-top / flat-bottom yoke-ish racing wheel with paddles (separate object, origin at the hub)
    sw = ck.steering_wheel_part(R=SW_R, flat_bottom=True, flat_top=0.80, hub_r=0.054,
                                spokes=((0.0, 0.050), (180.0, 0.050), (270.0, 0.030)), marker=True)
    for sx in (1, -1):
        sw.extend(ck.box_between((sx * 0.080, 0.040, 0.028), (sx * 0.160, 0.040, 0.048), 0.036, 0.005, 'Interior',
                                 up=(0, 1, 0)))
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R_F, W=WHEEL_W_F, rim_d_in=20, spokes=10, style='single', segs=48, rim_segs=40,
                  spoke_w=(0.034, 0.004), spoke_thick=0.028, spoke_dish=0.034, hub_r=0.078, nuts=0,
                  center_lock=dict(r=0.040, h=0.026, sides=6), disc_r=0.198, caliper_angle=150.0, caliper_span=50.0,
                  grooves=[-0.052, 0.052], groove_w=0.012,
                  rear=dict(R=WHEEL_R_R, W=WHEEL_W_R, rim_d_in=21, disc_r=0.205, caliper_span=46.0,
                            grooves=[-0.066, 0.066], groove_w=0.014))


def build():
    paint = (0.807, 0.100, 0.0036)             # #E8590C (sRGB) -> linear
    mats = ck.default_materials(paint=paint, paint_metallic=0.55, paint_rough=0.24, paint_coat=0.8,
                                rim=(0.030, 0.030, 0.032), rim_metallic=0.55, rim_rough=0.48,
                                caliper=(0.85, 0.55, 0.01),
                                interior=(0.045, 0.045, 0.048), interior_dark=(0.012, 0.012, 0.014))
    mats['Paint']['coat_rough'] = 0.05
    mats['Carbon'] = dict(base=(0.009, 0.009, 0.011), metallic=0.0, roughness=0.52, coat=0.10, coat_rough=0.20)
    mats['BrakeDisc'] = dict(base=(0.20, 0.20, 0.21), metallic=1.0, roughness=0.45)
    mats['Glass'] = dict(base=(0.010, 0.012, 0.016), roughness=0.03, alpha=0.30, double_sided=True)
    mats['InteriorAccent'] = dict(base=(0.60, 0.075, 0.006), roughness=0.60)
    car = ck.CarAssembly(CAR_ID, CAR_NAME, mats)
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Glass', shell.glass)
    car.add('Interior', shell.inner)
    if STAGE != 'body':
        body_details(car, shell.surface)
        engine_bay(car)
        interior(car)
        ck.add_wheels(car, WHEEL_SPEC, axles=dict(front=(YF, TRACK_F / 2), rear=(YR, TRACK_R / 2)))
        car.socket('Socket_CamHood', (0.0, 0.900, 0.880))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.050, 0.360))
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
    width_body = 2 * max(abs(v.x) for v in bv if not (abs(v.y - 0.60) < 0.12 and v.z > 0.76))   # mirrors excluded
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
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'mid-engine supercar (hypercar-flavoured)', 'drivetrain': 'AWD',
        'engine': 'mid', 'doors': 2, 'seats': 2, 'source_blend': 'Opus55ForzaUltracodeEffort.blend',
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
        'rim_diameter_in_front': 20, 'rim_diameter_in_rear': 21,
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
        'default_paint': {'hex': '#E8590C', 'linear_rgb': [0.807, 0.100, 0.0036], 'finish': 'metallic'},
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
        print('qa', ck.qa_checks(CAR, WHEEL_R_R, WHEEL_W_R), 'interior verts in wheel wells:', interior_in_wells(CAR),
              'interior leaks:', interior_leaks(CAR))
    if RENDER:
        hidden = isolate(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.4, 5.9, 1.75), target=(0.0, 0.0, 0.50),
                                           lens=50.0, world_strength=0.8, sun_energy=3.2, exposure=-0.35))
        finally:
            if not globals().get('KEEP_ISOLATED', False):
                isolate(False)
    elif globals().get('KEEP_ISOLATED', False):
        isolate(True)
    if EXPORT:
        RES, INFO, DATA = export_all(CAR)
        print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
        print('materials', INFO['materials'])
