"""Granite RS - 1990s-flavoured gravel rally car, 3-door coupe-hatch, AWD turbo (car #7 of Sunward Roads).

Rebuilds Cars/Car_granite_rally from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero
image and exports assets/imported/cars/granite_rally.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\granite_rally.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking), DEBUG (bool).

Spec: L 4.20, W 1.85 (blistered arches), H 1.40, wheelbase 2.55, track 1.58 / 1.58, wheel R 0.33 (15" gravel rims,
tall 215-wide tyres with zig-zag tread), ground clearance 0.20. Original design (no real brand / model): long, boxy
coupe-hatch with slab sides and a crisp shoulder crease, big blistered wheel arches front and rear, flat bonnet with a
big central outlet vent and bonnet pins, upright windscreen with a black sun strip, roof scoop, liftback rear glass
over a short deck carrying a huge two-element wing with tall end plates, square 90s headlamps, a four-lamp light pod on
the bumper, aluminium skid plate, tow loops, mud flaps behind every wheel, single big rear exhaust. White 6-spoke gravel
rims, gold calipers. Interior: two buckets with red harnesses, roll cage, rally dash, hydraulic handbrake, sequential
lever, spare wheel in the back, no rear seats. Default paint white #F4F4F0 (liveries come from the game shader).
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

CAR_ID = 'granite_rally'
CAR_NAME = 'Granite RS'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
DEBUG = globals().get('DEBUG', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.55
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.275)
TRACK_F, TRACK_R = 1.58, 1.58
WHEEL_R, WHEEL_W = 0.330, 0.215
ARCH_R, ARCH_Z = 0.360, 0.338                  # ~3 cm gap at the sides, ~3.8 cm above the tyre
NOSE_Y, TAIL_Y = 2.155, -2.045                 # cap poles -> body length 4.20

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs), K3 waist / widest
# (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr), K8 crown (zc).
# Hood / deck stations: K5 = shut line, K6 = a point on the panel, K8 = panel centre.
# The waist (ww) swells from 0.884 (doors) to 0.925 at both axles: blistered arches (1.85 m over the flares).
Y_DECK = -1.660          # liftback glass lower edge (short deck carrying the wing behind it)
Y_ROOF = -0.890          # roof rear edge / rear glass top
Y_HEADER = 0.250         # windscreen header
Y_COWL = 0.980           # windscreen base
Y_SAIL = 0.840           # door glass front edge (black mirror sail ahead of it)
Y_BPIL = (-0.460, -0.400)  # black B-pillar
S = [
    # ---- tail: square tail panel, short deck carrying the wing
    dict(y=-2.015, zb=0.330, wb=0.48, zs=0.370, ws=0.800, zw=0.570, ww=0.830, zh=0.912, wh=0.810, zg=0.962,
         wg=0.740, zr=0.980, wr=0.560, zc=0.986),
    dict(y=-2.000, zb=0.320, wb=0.52, zs=0.360, ws=0.830, zw=0.575, ww=0.858, zh=0.928, wh=0.838, zg=0.988,
         wg=0.765, zr=1.006, wr=0.585, zc=1.013),
    dict(y=-1.950, zb=0.300, wb=0.55, zs=0.350, ws=0.852, zw=0.580, ww=0.886, zh=0.938, wh=0.862, zg=1.002,
         wg=0.786, zr=1.023, wr=0.605, zc=1.031),
    dict(y=-1.850, zb=0.272, wb=0.58, zs=0.338, ws=0.872, zw=0.585, ww=0.906, zh=0.942, wh=0.876, zg=1.006,
         wg=0.800, zr=1.028, wr=0.620, zc=1.040),
    dict(y=Y_DECK, zb=0.240, wb=0.60, zs=0.322, ws=0.889, zw=0.590, ww=0.921, zh=0.942, wh=0.886, zg=1.006,
         wg=0.808, zr=1.030, wr=0.640, zc=1.045, sharp=dict(zc=0.6, zr=0.5)),
    # ---- liftback rear glass between the blistered rear arches
    dict(y=-1.500, zb=0.222, wb=0.61, zs=0.315, ws=0.893, zw=0.590, ww=0.924, zh=0.941, wh=0.888, zg=1.005,
         wg=0.812, zr=1.094, wr=0.652, zc=1.114),
    dict(y=YR, zb=0.205, wb=0.62, zs=0.305, ws=0.895, zw=0.590, ww=0.925, zh=0.940, wh=0.889, zg=1.002, wg=0.815,
         zr=1.178, wr=0.660, zc=1.212),
    dict(y=-1.050, zb=0.200, zs=0.300, ws=0.885, zw=0.590, ww=0.915, zh=0.938, wh=0.882, zg=0.998, wg=0.816,
         zr=1.272, wr=0.665, zc=1.309),
    dict(y=Y_ROOF, zs=0.300, ws=0.864, ww=0.897, zh=0.937, wh=0.868, zg=0.995, wg=0.816, zr=1.338, wr=0.668,
         zc=1.378, sharp=dict(zc=0.6, zr=0.5)),
    # ---- cabin: slab doors set in between the blisters (creased flare starts), flat roof
    dict(y=-0.760, ws=0.842, ww=0.866, wh=0.851, zg=0.991, zr=1.345, wr=0.670, zc=1.386,
         sharp=dict(ww=0.6, ws=0.6, wh=0.4)),
    dict(y=-0.300, ws=0.840, ww=0.864, zh=0.935, wh=0.849, zg=0.985, wg=0.815, zr=1.348, wr=0.672, zc=1.390),
    dict(y=Y_HEADER, zh=0.930, wh=0.849, zg=0.976, wg=0.815, zr=1.335, wr=0.674, zc=1.370,
         sharp=dict(zc=0.5, zr=0.5, wr=0.3)),
    dict(y=0.600, ws=0.841, ww=0.865, zh=0.925, wh=0.850, zg=0.968, wg=0.812, zr=1.165, wr=0.722, zc=1.195),
    dict(y=0.860, ws=0.845, ww=0.869, zh=0.920, wh=0.853, zg=0.953, wg=0.808, zr=1.025, wr=0.755, zc=1.027,
         sharp=dict(ww=0.6, ws=0.6, wh=0.4)),
    dict(y=Y_COWL, ws=0.868, ww=0.902, zh=0.915, wh=0.872, zg=0.945, wg=0.806, zr=0.960, wr=0.770, zc=0.950,
         sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- flat bonnet between blistered front wings, square nose
    dict(y=1.100, zs=0.302, ws=0.884, ww=0.917, zh=0.903, wh=0.883, zg=0.933, wg=0.800, zr=0.937, wr=0.610,
         zc=0.939),
    dict(y=YF, zb=0.205, wb=0.62, zs=0.305, ws=0.895, zw=0.585, ww=0.925, zh=0.897, wh=0.890, zg=0.926,
         wg=0.796, zr=0.929, wr=0.565, zc=0.931),
    dict(y=1.600, zb=0.218, wb=0.60, zs=0.308, ws=0.893, zw=0.578, ww=0.922, zh=0.885, wh=0.888, zg=0.910,
         wg=0.790, zr=0.913, wr=0.550, zc=0.915),
    dict(y=1.820, zb=0.234, wb=0.58, zs=0.312, ws=0.882, zw=0.570, ww=0.912, zh=0.872, wh=0.880, zg=0.893,
         wg=0.783, zr=0.897, wr=0.540, zc=0.899),
    dict(y=1.980, zb=0.252, wb=0.55, zs=0.316, ws=0.858, zw=0.556, ww=0.893, zh=0.856, wh=0.866, zg=0.874,
         wg=0.772, zr=0.879, wr=0.525, zc=0.882),
    dict(y=2.065, zb=0.268, wb=0.50, zs=0.322, ws=0.812, zw=0.540, ww=0.858, zh=0.822, wh=0.838, zg=0.850,
         wg=0.752, zr=0.857, wr=0.505, zc=0.861),
    dict(y=2.105, zb=0.278, wb=0.46, zs=0.326, ws=0.762, zw=0.522, ww=0.812, zh=0.778, wh=0.795, zg=0.818,
         wg=0.722, zr=0.830, wr=0.480, zc=0.835),
    dict(y=2.125, zb=0.285, wb=0.42, zs=0.330, ws=0.705, zw=0.500, ww=0.758, zh=0.735, wh=0.742, zg=0.776,
         wg=0.680, zr=0.795, wr=0.450, zc=0.800),
]

# quarter glass: its rear edge leans forward going up, parallel to the liftback (belt y=-1.15, rail y=-0.93)
WARP_Y = -1.050
WARP = dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.150, -0.930), margin=0.16)
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),        # windscreen
    dict(bands=(5, 5), y=(WARP_Y, Y_SAIL), role='glass'),          # door + quarter glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),           # mirror sail
    dict(bands=(5, 5), y=Y_BPIL, role='trim'),                     # B-pillar (black)
    dict(bands=(7, 7), y=(Y_DECK, Y_ROOF), role='glass'),          # liftback glass
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.050), role='trim'),   # scuttle / cowl panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[3, 3, 4, 5, 2, 5, 2, 6],
    key_sharp=(0, 0.7, 0.55, 0.35, 0.85, 0.5, 0.5, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.530, tilt=3.0, k_edge=2.4, k_face=2.8, rings=8),
    tail=dict(y=TAIL_Y, z=0.640, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8),
    step=0.05,
    rail=0.05,
    warps=[WARP],
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.585), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.640)]
INNER = dict(y=(-1.900, 1.000), d=0.035,
             tubs=[(YR, ARCH_Z, ARCH_R + 0.03, 0.625), (YF, ARCH_Z, ARCH_R + 0.03, 0.570)])

EYE = Vector((-0.370, -0.220, 1.170))        # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.370, 0.270, 0.860))         # steering wheel hub
COLUMN_TILT = 22.0                           # deg, column descends toward the dash
SW_R = 0.175                                 # steering wheel radius (deep-dish rally wheel)
D_IN = INNER['d']
SEAT_Z = 0.370                               # bucket seat base (runners stay above the floor)
SEAT_Y = (0.200, -0.300)
SEAT_RECLINE, SEAT_BACK_H = 14.0, 0.84
Y_HOOP = -0.600                              # roll-cage main hoop (behind the seats)


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


def lamp(S_, spec, house_mat, inner_mat, inset=0.006, house_off=0.002, inner_off=0.0034, res=0.02):
    """Lamp: housing patch + inset inner patch. Returns (housing, inner, frame, pts2d)."""
    pts = snap_pts(S_, spec)
    housing, frame = S_.patch3d(pts, offset=house_off, depth=0.006, res=res, mat=house_mat, sub=4)
    O, U, V, D = frame
    pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in pts]
    inner = S_.patch(ck.offset_poly(ck.cr_resample(pts2d, True, 4), -inset), frame, offset=inner_off, depth=0.004,
                     res=res * 0.9, mat=inner_mat, smooth=False)
    return housing, inner, frame, pts2d


def surface_path(S_, view, pts2d, lift=0.0):
    """Snap 2D points (view coords) to the shell, raised `lift` along the surface normal."""
    fr = S_.frame(view)
    out = []
    for a, b in pts2d:
        loc, nor = S_.hit(fr, a, b)
        if loc is not None:
            out.append((loc + nor * lift, nor))
    return out


def blade(S_, view, pts2d, prof, mat, lift=0.0):
    """Thin profile (u, v) swept along a surface-snapped path (louvres, strakes)."""
    sp = surface_path(S_, view, pts2d, lift)
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


UNDER = (Vector((0, 0, 0)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))   # view from below: (x, y)


def under_z(S_, x, y, default=0.20):
    loc, nor = S_.hit(UNDER, x, y)
    return loc.z if loc is not None else default


def lathe_y(profile, segs, mats, center):
    """Revolve a profile [(a, r)] about the Y axis (a = position along +Y), placed at `center`."""
    p = ck.revolve(profile, segs, mats)
    M = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(90.0), 4, 'Z')
    return p.transformed(M)


# =====================================================================================================
# exterior details
# =====================================================================================================
def front_details(car, S_, R, C, LH, LHC):
    D = ck.densify
    F = S_.frame('front')
    # ---- square 90s headlamps (slight wrap onto the corner), chrome reflector, two round lenses
    hl_spec = [('front', 0.452, 0.668), ('front', 0.452, 0.770), ('front', 0.600, 0.776), ('front', 0.700, 0.774),
               ('right', 2.092, 0.764), ('right', 2.092, 0.678), ('front', 0.700, 0.664), ('front', 0.600, 0.664)]
    housing, inner, frame, p2 = lamp(S_, hl_spec, 'Trim', 'Alu', inset=0.007, res=0.026)
    R.extend(housing, inner)
    cs = []
    for (x, z, r) in ((0.522, 0.719, 0.038), (0.638, 0.719, 0.034)):
        loc, nor = S_.hit(F, x, z)
        c = loc + nor * 0.0062
        LH.extend(ck.disc(c, nor, r, 'HeadlightLens', n=20))
        R.extend(ck.disc(c - nor * 0.0010, nor, r, 'Grille', n=20, ring_mat='Chrome', ring_w=0.006))
        cs.append(c)
    hc = (cs[0] + cs[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))
    # ---- upper grille between the headlamps (black, two slats)
    gr = D(ck.fillet_poly([(-0.420, 0.672), (0.420, 0.672), (0.420, 0.768), (-0.420, 0.768)], 0.012, n=2), 0.04)
    C.extend(S_.patch(gr, 'front', offset=0.0015, depth=0.005, res=0.03, mat='Grille', smooth=False))
    C.extend(S_.rim(gr, 'front', width=0.010, offset=0.006, depth=0.005, mat='Trim', smooth=False))
    for z in (0.708, 0.738):
        C.extend(S_.line(D([(-0.405, z), (0.405, z)], 0.04, closed=False), 'front', width=0.009, offset=0.0045,
                         mat='Trim', smooth=False, step=0.04))
    # ---- bonnet / fascia shut line, bumper split line
    C.extend(S_.line(D([(-0.70, 0.790), (0.70, 0.790)], 0.02, closed=False), 'front', offset=0.0015, smooth=False,
                     step=0.020))
    C.extend(S_.line(D([(-0.78, 0.652), (0.78, 0.652)], 0.02, closed=False), 'front', offset=0.0015, smooth=False,
                     step=0.020))
    R.extend(S_.line([(2.095, 0.651), (1.95, 0.648), (1.78, 0.645), (1.625, 0.643)], 'right', step=0.03))
    # ---- big intercooler mouth (honeycomb) and corner brake ducts
    mouth = D(ck.fillet_poly([(-0.400, 0.335), (0.400, 0.335), (0.430, 0.385), (0.430, 0.528), (-0.430, 0.528),
                              (-0.430, 0.385)], [0.02, 0.02, 0.02, 0.015, 0.015, 0.02], n=3), 0.04)
    C.extend(S_.honeycomb(mouth, 'front', cell=0.064, wall=0.0070, base_offset=0.0025, height=0.008, margin=0.004,
                          smooth=False, res=0.06))
    C.extend(S_.rim(mouth, 'front', width=0.012, offset=0.010, depth=0.007, mat='Trim', smooth=False))
    duct = D(ck.fillet_poly([(0.515, 0.362), (0.705, 0.362), (0.715, 0.500), (0.525, 0.500)], 0.025, n=3), 0.03)
    R.extend(S_.patch(duct, 'front', offset=0.0025, depth=0.006, res=0.03, mat='Grille', smooth=False))
    R.extend(S_.rim(duct, 'front', width=0.010, offset=0.0085, depth=0.006, mat='Trim', smooth=False))
    for z in (0.408, 0.454):
        R.extend(S_.line(D([(0.525, z), (0.712, z)], 0.03, closed=False), 'front', width=0.008, offset=0.007,
                         mat='Trim', smooth=False, step=0.03))
    lip = D(ck.fillet_poly([(-0.700, 0.306), (0.700, 0.306), (0.735, 0.322), (-0.735, 0.322)], 0.005, n=2), 0.04)
    C.extend(S_.patch(lip, 'front', offset=0.002, depth=0.005, res=0.0, mat='Trim', smooth=False))

    # ---- four-lamp rally light pod on the bumper (pod = Body / Trim, lenses = Lights_Head)
    face_y = S_.snap('front', 0.0, 0.62).y
    y0, y1 = 2.100, face_y + 0.068
    zc, hh, hw = 0.618, 0.090, 0.428
    prof = ck.rrect_pts(0.0, zc, 2 * hw, 2 * hh, 0.040, n=4)
    prof2 = ck.rrect_pts(0.0, zc, 2 * hw - 0.012, 2 * hh - 0.012, 0.034, n=4)
    pod = ck.sweep_axis('y', [y0, y1 - 0.006, y1], [[(p.x, p.y) for p in prof], [(p.x, p.y) for p in prof],
                                                    [(p.x, p.y) for p in prof2]], 'Trim')
    C.extend(pod)
    for x in (-0.315, -0.105, 0.105, 0.315):
        a0, a1 = y1 - 0.010, y1 + 0.032
        housing = [(a0, 0.081), (a1 - 0.007, 0.081), (a1, 0.076), (a1, 0.067), (a1 - 0.003, 0.064)]
        C.extend(lathe_y([(a - a0, r) for (a, r) in housing], 20, ['Trim', 'Trim', 'Chrome', 'Chrome'],
                         (x, a0, zc)))
        lens = [(a1 - 0.002, 0.065), (a1 + 0.004, 0.056), (a1 + 0.009, 0.034), (a1 + 0.011, 0.0)]
        LHC.extend(lathe_y([(a - a0, r) for (a, r) in lens], 20, 'HeadlightLens', (x, a0, zc)))
        C.extend(lathe_y([(a1 - 0.004 - a0, 0.064), (a1 - 0.004 - a0, 0.0)], 20, 'Alu', (x, a0, zc)))  # reflector
    # straps from the pod top to the bonnet leading edge
    for sx in (-1, 1):
        top = Vector((sx * 0.24, y1 - 0.030, zc + hh - 0.004))
        hood = S_.snap('top', sx * 0.24, 2.060) + Vector((0, 0, 0.001))
        C.extend(ck.box_between(top, hood, 0.034, 0.005, 'Trim'))
        C.extend(ck.disc(hood + Vector((0, 0, 0.003)), (0, 0, 1), 0.010, 'Alu', n=10))

    # ---- aluminium skid plate following the bumper underside, bolts
    ys = [1.02, 1.30, 1.60, 1.80, 1.92, 2.00, 2.06, 2.10, 2.125]
    xs = [-0.560, -0.548, -0.30, 0.0, 0.30, 0.548, 0.560]
    profs = []
    for x in xs:
        bot = []
        top = []
        for y in ys:
            zb = under_z(S_, max(min(x, 0.55), -0.55), y)
            zt = zb - 0.004
            th = 0.008
            bot.append((y, zt - th))
            top.append((y, zt))
        sc = 0.006 if abs(x) > 0.55 else 0.0
        prof = [(y, z + sc) for (y, z) in bot] + [(y, z - sc) for (y, z) in reversed(top)]
        profs.append(prof)
    C.extend(ck.sweep_axis('x', xs, profs, 'Alu'))
    for x in (-0.40, 0.40):
        for y in (1.20, 1.85):
            C.extend(ck.disc((x, y, under_z(S_, x, y) - 0.0125), (0, 0, -1), 0.009, 'Alu', n=8))
    # ---- front tow loop (right) under the bumper
    zt = under_z(S_, 0.480, 2.110)
    C.extend(ck.torus((0.480, 2.118, zt - 0.020), (1, 0, 0), 0.034, 0.0075, 'TowStrap', nu=16, nv=6))


def bonnet_details(S_, R, C):
    D = ck.densify
    # ---- big central outlet vent with black louvres
    vent = D(ck.fillet_poly([(-0.300, 1.300), (0.300, 1.300), (0.262, 1.760), (-0.262, 1.760)], 0.03, n=3), 0.03)
    C.extend(S_.patch(vent, 'top', offset=0.0015, depth=0.006, res=0.045, mat='Grille', smooth=False))
    C.extend(S_.rim(vent, 'top', width=0.018, offset=0.008, depth=0.006, mat='Trim', smooth=False))
    for k in range(8):
        yv = 1.335 + k * 0.056
        hw = 0.300 - 0.038 * (yv - 1.300) / 0.46 - 0.022
        C.extend(blade(S_, 'top', [(-hw + 2 * hw * j / 4, yv) for j in range(5)],
                       [(-0.007, -0.002), (0.007, -0.002), (0.012, 0.010), (0.000, 0.010)], 'Trim'))
    # ---- bonnet shut lines (along the wing tops and across the leading edge), bonnet pins
    edge = [BODY.point(y, 5.0, 1) for y in (Y_COWL + 0.06, 1.25, 1.50, 1.75, 1.95, 2.05)]
    R.extend(S_.line3d(edge, step=0.04))
    for sx in (-1, 1):
        p = S_.snap('top', sx * 0.540, 1.985)
        loc, nor = S_.nearest(p)
        C.extend(ck.disc(loc + nor * 0.0030, nor, 0.017, 'Alu', n=12, ring_mat='Trim', ring_w=0.006))
        C.extend(ck.box_between(loc + nor * 0.004, loc + nor * 0.004 + Vector((sx * 0.045, -0.020, 0.0)), 0.006,
                                0.004, 'Alu'))
    # ---- scuttle wipers (parked at the base of the screen)
    for (x0, x1, y0, y1, px) in ((-0.66, -0.10, 0.935, 0.905, -0.32), (-0.05, 0.50, 0.928, 0.900, 0.22)):
        a0 = S_.snap('top', x0, y0) + Vector((0, 0, 0.013))
        a1 = S_.snap('top', x1, y1) + Vector((0, 0, 0.013))
        C.extend(ck.box_between(a0, a1, 0.016, 0.011, 'Trim'))
        pivot = S_.snap('top', px, Y_COWL + 0.030) + Vector((0, 0, 0.012))
        mid = (a0 + a1) / 2 + Vector((0, 0, 0.008))
        C.extend(ck.box_between(pivot, mid, 0.012, 0.008, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.016, 0.016, 0.010), 'Trim', nu=10, nv=6))
    # ---- black sun strip across the top of the windscreen
    strip = D(ck.fillet_poly([(-0.585, 0.262), (0.585, 0.262), (0.590, 0.360), (-0.590, 0.360)], 0.01, n=2), 0.04)
    C.extend(S_.patch(strip, 'top', offset=-0.0046, depth=0.001, res=0.04, mat='Trim', smooth=False, walls=False))


def roof_details(S_, C, LBC):
    # ---- roof scoop (cabin air) on the front of the roof
    ys = [-0.230, -0.140, -0.020, 0.080, 0.150, 0.180]
    hs = [0.002, 0.012, 0.026, 0.038, 0.045, 0.046]
    ws = [0.090, 0.120, 0.145, 0.158, 0.160, 0.156]
    profs = []
    for y, h, w in zip(ys, hs, ws):
        pr = []
        for (u, v) in ((-1.0, -0.012), (1.0, -0.012), (1.0, 0.45), (0.86, 1.0), (-0.86, 1.0), (-1.0, 0.45)):
            x = u * w
            z0 = S_.snap('top', x, y).z
            pr.append((x, z0 + (v * h if v > 0 else v)))
        profs.append(pr)
    C.extend(ck.sweep_axis('y', ys, profs, 'Paint', cap_mat='Grille'))
    # black mesh in the scoop mouth (slightly behind the opening)
    y_m = ys[-1] - 0.012
    m = ck.Part()
    q = [m.vert((x, y_m, S_.snap('top', x, y_m).z + dz)) for (x, dz) in
         ((-0.130, 0.002), (0.130, 0.002), (0.130, 0.040), (-0.130, 0.040))]
    m.face(q, 'Grille')
    m.orient(0, ref=Vector((0, y_m - 0.1, 1.3)))
    C.extend(m)
    # ---- third brake lamp at the top of the liftback, short antenna
    zr = S_.snap('top', 0.0, Y_ROOF + 0.020).z
    C.extend(ck.box_between((-0.13, Y_ROOF + 0.025, zr + 0.010), (0.13, Y_ROOF + 0.025, zr + 0.010), 0.040, 0.022,
                            'Trim'))
    LBC.extend(ck.box_between((-0.115, Y_ROOF + 0.0045, zr + 0.011), (0.115, Y_ROOF + 0.0045, zr + 0.011), 0.002,
                              0.012, 'BrakeLens'))
    ya = -0.640
    za = S_.snap('top', 0.0, ya).z
    C.extend(ck.ellipsoid((0.0, ya, za + 0.004), (0.016, 0.030, 0.012), 'Trim', nu=10, nv=6))
    C.extend(ck.rod((0.0, ya - 0.004, za + 0.012), (0.0, ya - 0.070, za + 0.220), 0.0025, 'Trim', n=6))


def side_details(car, S_, R):
    D = ck.densify
    # ---- black side skirts between the arches
    ys = [-0.905, -0.885, -0.80, -0.40, 0.0, 0.40, 0.80, 0.885, 0.905]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        k = 0.35 if abs(y) > 0.9 else (0.8 if abs(y) > 0.88 else 1.0)
        profs.append([(ws - 0.030, zs + 0.050), (ws + 0.008 * k, zs + 0.046), (ws + 0.024 * k, zs + 0.004),
                      (ws + 0.022 * k, zs - 0.062 * k), (ws + 0.005, zs - 0.074 * k), (ws - 0.030, zs - 0.062)])
    R.extend(ck.sweep_axis('y', ys, profs, 'Trim'))
    # ---- door shut lines, handle, fuel filler
    R.extend(S_.line([(0.882, 0.315), (0.900, 0.620), (0.935, 0.960)], 'right', step=0.03))
    R.extend(S_.line([(-0.442, 0.315), (-0.447, 0.620), (-0.452, 0.975)], 'right', step=0.03))
    R.extend(S_.patch(D(ck.rrect_pts(-0.300, 0.884, 0.130, 0.030, 0.010, n=3), 0.02), 'right', offset=0.0040,
                      depth=0.005, res=0.0, mat='Trim', smooth=False))
    # front-wing / bumper join behind the front arch is the door line; rear bumper split line
    R.extend(S_.line([(-2.000, 0.566), (-1.850, 0.568), (-1.760, 0.571), (-1.672, 0.574)], 'right', step=0.03))
    # ---- 90s aero mirror on the black sail
    mc = Vector((0.955, 0.885, 1.035))
    ry = 0.058

    def flat_back(p):
        if p.y < -ry * 0.25:
            p.y = -ry * 0.25 - (p.y + ry * 0.25) * 0.08
        return p
    mirror = ck.ellipsoid(mc, (0.095, ry, 0.050), 'Paint', nu=16, nv=8, exp=3.0, deform=flat_back)
    for fi in range(len(mirror.f)):
        if mirror.face_center(fi).z < mc.z - 0.030:
            mirror.m[fi] = 'Trim'
    R.extend(mirror)
    glass_pts = ck.superellipse_pts(0.0, 0.0, 0.078, 0.040, e=2.6, n=20)
    mg = ck.Part()
    cen = mg.vert(mc + Vector((0, -ry * 0.25 - 0.003, 0)))
    ring = [mg.vert(mc + Vector((p.x, -ry * 0.25 - 0.003, p.y))) for p in glass_pts]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    base = S_.snap('right', 0.905, 0.995)
    R.extend(ck.box_between(base + Vector((-0.010, 0.0, 0.0)), mc + Vector((-0.060, 0.005, -0.012)), 0.040, 0.016,
                            'Trim'))
    # ---- over-fender seams: the blistered arches read as bolted-on wide-body flares
    for (ya, sgn) in ((YF, 1), (YR, -1)):
        rf = 0.462
        pts = []
        for k in range(29):
            a = math.radians(-2.0 + 184.0 * k / 28)
            z = ARCH_Z + rf * math.sin(a)
            y = ya + rf * math.cos(a)
            if z < 0.335 or (sgn > 0 and y < 0.900):      # the front flare ends at the door shut line
                continue
            pts.append((y, z))
        R.extend(S_.line(pts, 'right', width=0.0032, offset=0.0010, step=0.028))
    # ---- mud flaps behind every wheel
    for yw in (YF, YR):
        yfl = yw - 0.400
        R.extend(ck.box_between((0.790, yfl, 0.065), (0.790, yfl, 0.345), 0.210, 0.008, 'Grille', up=(0, 1, 0)))
        R.extend(ck.box_between((0.790, yfl - 0.005, 0.070), (0.790, yfl - 0.005, 0.110), 0.200, 0.004, 'Trim',
                                up=(0, 1, 0)))


def rear_details(car, S_, R, C, LT, LB, LR):
    D = ck.densify
    B = S_.frame('rear')
    # ---- tail lamps (horizontal 90s units) with brake and reverse sections, black centre garnish
    tlo = D(ck.fillet_poly([(0.400, 0.792), (0.796, 0.792), (0.800, 0.902), (0.400, 0.902)], 0.012, n=2), 0.03)
    R.extend(S_.patch(ck.offset_poly(tlo, 0.009), 'rear', offset=0.002, depth=0.006, res=0.02, mat='Trim',
                      smooth=False))
    LT.extend(S_.patch(tlo, 'rear', offset=0.0042, depth=0.004, res=0.02, mat='TaillightLens', smooth=False))
    brk = D(ck.fillet_poly([(0.530, 0.858), (0.786, 0.858), (0.788, 0.892), (0.530, 0.892)], 0.006, n=2), 0.03)
    LB.extend(S_.patch(brk, 'rear', offset=0.0060, depth=0.003, res=0.0, mat='BrakeLens', smooth=False))
    LR.extend(S_.patch(D(ck.rrect_pts(0.455, 0.847, 0.070, 0.074, 0.008, n=2), 0.02), 'rear', offset=0.0060,
                       depth=0.003, res=0.0, mat='ReverseLens', smooth=False))
    for x in (0.585, 0.665, 0.745):
        R.extend(S_.line(D([(x, 0.800), (x, 0.852)], 0.02, closed=False), 'rear', width=0.004, offset=0.0062,
                         mat='Trim', smooth=False, step=0.02))
    garnish = D(ck.fillet_poly([(-0.385, 0.800), (0.385, 0.800), (0.385, 0.894), (-0.385, 0.894)], 0.008, n=2), 0.04)
    C.extend(S_.patch(garnish, 'rear', offset=0.0025, depth=0.005, res=0.03, mat='Trim', smooth=False))
    # ---- hatch shut lines: around the liftback on the roof, along the deck, across the tail
    C.extend(S_.line(D([(-0.600, Y_ROOF + 0.016), (0.600, Y_ROOF + 0.016)], 0.05, closed=False), 'top', smooth=False,
                     step=0.03))
    hl = [BODY.point(y, 6.15, 1) for y in (Y_ROOF + 0.016, -1.10, -1.35, -1.60, -1.80, -1.96, -1.995)]
    R.extend(S_.line3d(hl, step=0.04))
    C.extend(S_.line(D([(-0.600, 0.948), (0.600, 0.948)], 0.02, closed=False), 'rear', offset=0.0015, smooth=False,
                     step=0.020))
    # ---- plate recess, bumper split, black lower valance, rear fog
    plate = D(ck.rrect_pts(0.0, 0.666, 0.520, 0.120, 0.012, n=2), 0.05)
    C.extend(S_.patch(plate, 'rear', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    C.extend(S_.rim(plate, 'rear', width=0.012, offset=0.0060, depth=0.005, mat='Trim', smooth=False))
    C.extend(S_.line(D([(-0.815, 0.566), (0.815, 0.566)], 0.02, closed=False), 'rear', offset=0.0015, smooth=False,
                     step=0.020))
    val = D(ck.fillet_poly([(-0.735, 0.362), (0.735, 0.362), (0.760, 0.400), (0.750, 0.452), (-0.750, 0.452),
                            (-0.760, 0.400)], 0.012, n=2), 0.025)
    C.extend(S_.patch(val, 'rear', offset=0.0025, depth=0.006, res=0.025, mat='Trim', smooth=False))
    LT.extend(S_.patch(D(ck.rrect_pts(-0.300, 0.408, 0.090, 0.030, 0.008, n=2), 0.02), 'rear', offset=0.0045,
                       depth=0.003, res=0.0, mat='TaillightLens', smooth=False))
    # ---- single big exhaust (right) through the valance, rear tow loop (left)
    x_ex, z_ex = 0.470, 0.392
    loc, nor = S_.hit(B, x_ex, z_ex)
    sur = D(ck.superellipse_pts(x_ex, z_ex, 0.070, 0.062, e=2.4, n=24), 0.02)
    C.extend(S_.patch(sur, 'rear', offset=0.0040, depth=0.006, res=0.03, mat='Grille', smooth=False))
    p0 = Vector((x_ex, loc.y + 0.14, z_ex + 0.008))
    p1 = Vector((x_ex, loc.y - 0.042, z_ex))
    C.extend(ck.tube(p0, p1, 0.052, 0.045, 'Chrome', 'Trim', n=24, inner_depth=0.07))
    car.socket('Socket_Exhaust', p1)
    zt = under_z(S_, -0.480, -1.995)
    C.extend(ck.torus((-0.480, -2.030, zt - 0.018), (1, 0, 0), 0.032, 0.0075, 'TowStrap', nu=16, nv=6))


def rear_wing(S_, C):
    """Huge two-element wing on tall end plates standing on the deck edges, plus two centre uprights."""
    Y_LE, Z_LE, CHORD, AOA = -1.700, 1.215, 0.300, math.radians(8.0)
    XT = 0.808
    xs = [-XT, -0.79, -0.55, -0.25, 0.0, 0.25, 0.55, 0.79, XT]
    foil = airfoil(CHORD, 0.12, camber=-0.05)
    profs = []
    for x in xs:
        dz = 0.006 * (abs(x) / XT) ** 2
        profs.append([(Y_LE - s * math.cos(AOA), Z_LE + dz + s * math.sin(AOA) + h * math.cos(AOA)) for (s, h) in foil])
    C.extend(ck.sweep_axis('x', xs, profs, 'Paint'))
    y_te = Y_LE - CHORD * math.cos(AOA)
    z_te = Z_LE + CHORD * math.sin(AOA)
    # upper flap (second element)
    Y2, Z2, CH2, A2 = y_te + 0.070, z_te + 0.036, 0.135, math.radians(28.0)
    foil2 = airfoil(CH2, 0.10, camber=-0.03)
    profs = []
    for x in xs:
        dz = 0.006 * (abs(x) / XT) ** 2
        profs.append([(Y2 - s * math.cos(A2), Z2 + dz + s * math.sin(A2) + h * math.cos(A2)) for (s, h) in foil2])
    C.extend(ck.sweep_axis('x', xs, profs, 'Paint'))
    y_te2 = Y2 - CH2 * math.cos(A2)
    z_te2 = Z2 + CH2 * math.sin(A2)
    C.extend(ck.box_between((-XT, y_te2 + 0.003, z_te2 + 0.008), (XT, y_te2 + 0.003, z_te2 + 0.008), 0.004, 0.014,
                            'Carbon'))                                                         # gurney
    # end plates: bottom edge follows the deck / shoulder, top above the flap
    ys_b = [-1.672, -1.740, -1.820, -1.900, -1.960, -1.990, -2.010]
    bot = [(y, S_.snap('top', 0.811, y).z - 0.014) for y in ys_b]
    top = [(-2.052, 1.190), (-2.062, z_te2 + 0.034), (-1.990, z_te2 + 0.050), (-1.860, 1.345), (-1.745, 1.290),
           (-1.672, 1.180)]
    plate = bot + top
    for sx in (1, -1):
        xa, xb = sorted((sx * XT, sx * (XT + 0.012)))
        C.extend(ck.sweep_axis('x', [xa, xb], plate, 'Carbon'))
    # centre uprights
    for sx in (1, -1):
        x = sx * 0.360
        zdeck = S_.snap('top', x, -1.850).z
        pr0 = [(x - 0.006, -1.770), (x + 0.006, -1.770), (x + 0.007, -1.830), (x + 0.005, -1.900),
               (x - 0.005, -1.900), (x - 0.007, -1.830)]
        C.extend(ck.sweep_axis('z', [zdeck - 0.012, Z_LE + 0.012], [pr0, pr0], 'Carbon'))


def body_details(car, S_):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LBC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    LHC = ck.Part()    # centre head lamps (light pod) - not mirrored
    front_details(car, S_, R, C, LH, LHC)
    bonnet_details(S_, R, C)
    roof_details(S_, C, LBC)
    side_details(car, S_, R)
    rear_details(car, S_, R, C, LT, LB, LR)
    rear_wing(S_, C)
    # fuel filler (right rear quarter only): quick-release cap
    loc, nor = S_.hit(S_.frame('right'), -1.640, 0.835)
    C.extend(ck.disc(loc + nor * 0.004, nor, 0.040, 'Alu', n=20, ring_mat='Trim', ring_w=0.008))
    C.extend(ck.box_between(loc + nor * 0.006 + Vector((0, 0.022, 0)), loc + nor * 0.006 + Vector((0, -0.022, 0)),
                            0.008, 0.006, 'Trim'))
    if DEBUG:
        print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    # main headlamp lenses: built on the right, mirrored; light-pod lenses are already full width
    car.add('Lights_Head', LH, LH.mirrored_x(), LHC)
    car.add('Lights_Tail', LT, LT.mirrored_x())
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR, LR.mirrored_x())


# =====================================================================================================
# interior
# =====================================================================================================
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


def sec_pt(y, t, inset, side=1):
    """Point on the loft section at y, parameter t (0..8), inset toward the cabin."""
    K, Sh = BODY.keys_at(y, inset)
    Tin, Tout = ck._section_tangents(K, Sh)
    p = ck._section_eval(K, Tin, Tout, t)
    return Vector((side * p.x, y, p.y))


def harness(x, y_back, z_base, recline, back_h, bar_y, bar_z):
    """Red 4-point harness on a kit bucket seat (same backrest transform as ck.bucket_seat); the shoulder
    straps run through the backrest slots back to the cage harness bar at (bar_y, bar_z)."""
    Mb = Matrix.Translation((x, y_back - 0.05, z_base + 0.05)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    nrm = (Mb.to_3x3() @ Vector((0, 1, 0))).normalized()
    H = ck.Part()
    for dx in (-0.072, 0.072):
        t0 = 0.11 - 0.02 * (0.56 / back_h) + 0.006
        t1 = 0.11 - 0.02 * (0.08 / back_h) + 0.006
        a = Mb @ Vector((dx, t0, 0.56))
        b = Mb @ Vector((dx * 0.55, t1, 0.08))
        H.extend(ck.box_between(a, b, 0.044, 0.004, 'InteriorAccent', up=tuple(nrm)))
        # shoulder straps: through the backrest slot back to the harness bar
        s = Mb @ Vector((dx, t0 - 0.004, 0.60))
        c = Vector((x + dx * 1.3, bar_y + 0.024, bar_z + 0.021))
        H.extend(ck.box_between(s, c, 0.044, 0.004, 'InteriorAccent', up=(0, 0, 1)))
    ym = y_back + 0.14
    zc = z_base + 0.118
    H.extend(ck.box_between((x - 0.20, ym, zc), (x + 0.20, ym, zc), 0.044, 0.004, 'InteriorAccent'))
    H.extend(ck.box_between((x, ym + 0.012, zc + 0.004), (x, ym - 0.012, zc + 0.004), 0.052, 0.010, 'Alu'))
    return H


def roll_cage(I):
    """Multi-point roll cage: main hoop, A-pillar hoop, roof bars, X door bars, diagonal, rear stays."""
    r, mat = 0.019, 'InteriorCage'
    ins = D_IN + 0.028
    # main hoop: sill -> B-pillar -> roof -> other side
    ts = [2.35, 3.0, 3.6, 4.2, 4.7, 5.2, 5.7, 6.2, 6.6, 7.0, 7.5, 8.0]
    right = [sec_pt(Y_HOOP, t, ins) for t in ts]
    hoop = right + [Vector((-p.x, p.y, p.z)) for p in reversed(right[:-1])]
    I.extend(ck.rod_path(hoop, r, mat, n=8))
    # A-pillar hoop: foot by the footwell -> up the door shut -> along the A-pillar -> across the header
    def a_leg(side):
        pts = [sec_pt(0.800, 2.35, ins, side), sec_pt(0.820, 3.6, ins, side), sec_pt(0.850, 4.6, ins, side),
               sec_pt(0.880, 5.4, ins, side)]
        for y in (0.780, 0.620, 0.460, 0.330):
            pts.append(sec_pt(y, 6.55, ins + 0.004, side))
        return pts
    hdr_y = Y_HEADER + 0.060
    head = [sec_pt(hdr_y, t, ins + 0.004) for t in (6.85, 7.4, 8.0)]
    head = head + [Vector((-p.x, p.y, p.z)) for p in reversed(head[:-1])]
    apath = a_leg(1) + head + list(reversed(a_leg(-1)))
    I.extend(ck.rod_path(apath, r, mat, n=8))
    # roof bars along the rails, X roof brace
    hp = {}
    for side in (1, -1):
        rb = [sec_pt(y, 6.75, ins + 0.004, side) for y in (hdr_y, 0.0, -0.30, Y_HOOP)]
        I.extend(ck.rod_path(rb, r * 0.9, mat, n=8))
        hp[side] = rb
    I.extend(ck.rod(hp[1][0], hp[-1][-1], r * 0.85, mat, n=8))
    I.extend(ck.rod(hp[-1][0], hp[1][-1], r * 0.85, mat, n=8))
    # X door bars
    for side in (1, -1):
        lo_h = sec_pt(Y_HOOP, 3.0, ins + 0.008, side)
        hi_h = sec_pt(Y_HOOP, 4.4, ins + 0.008, side)
        lo_a = sec_pt(0.800, 3.0, ins + 0.008, side)
        hi_a = sec_pt(0.830, 4.4, ins + 0.008, side)
        I.extend(ck.rod(lo_h, hi_a, r * 0.9, mat, n=8))
        I.extend(ck.rod(hi_h, lo_a, r * 0.9, mat, n=8))
    # main hoop diagonal + harness bar
    I.extend(ck.rod(sec_pt(Y_HOOP, 7.0, ins), sec_pt(Y_HOOP, 2.6, ins, -1), r * 0.9, mat, n=8))
    hb = [sec_pt(Y_HOOP, 4.85, ins), sec_pt(Y_HOOP, 4.85, ins, -1)]
    I.extend(ck.rod(hb[0] + Vector((0, -0.01, 0)), hb[1] + Vector((0, -0.01, 0)), r * 0.85, mat, n=8))
    # rear stays to the strut towers
    for side in (1, -1):
        top = sec_pt(Y_HOOP, 6.6, ins, side)
        foot = Vector((side * 0.540, -1.420, 0.680))
        I.extend(ck.rod(top, foot, r * 0.9, mat, n=8))
    return hb


def spare_wheel(y, z_floor):
    """Spare gravel wheel lying flat in the boot (seen through the liftback)."""
    Rw, hw, rr = 0.318, 0.100, 0.190
    tyre = [(-hw + 0.010, rr + 0.004), (-hw, rr + 0.04), (-hw + 0.004, Rw - 0.03), (-hw + 0.03, Rw), (hw - 0.03, Rw),
            (hw - 0.004, Rw - 0.03), (hw, rr + 0.04), (hw - 0.010, rr + 0.004)]
    p = ck.revolve(tyre, 24, 'Rubber')
    rim = ck.revolve([(hw - 0.006, rr + 0.004), (hw - 0.03, rr - 0.004), (hw - 0.045, 0.06), (hw - 0.04, 0.0)], 24,
                     'Rim')
    p.extend(rim)
    # lathe axis X -> Z (lying flat), centred above the floor
    M = Matrix.Translation((0.0, y, z_floor + hw + 0.004)) @ Matrix.Rotation(math.radians(-90.0), 4, 'Y')
    return p.transformed(M)


def interior(car):
    I = ck.Part()
    xa = min(inner_x(y, z) for y in (0.55, 0.75, 0.92) for z in (0.62, 0.80, 0.92)) - 0.012
    # ---- flat rally dashboard (profile (y, z) swept across X)
    dash = [(0.960, 0.905), (0.780, 0.948), (0.600, 0.960), (0.520, 0.952), (0.488, 0.928), (0.474, 0.866),
            (0.482, 0.786), (0.520, 0.696), (0.600, 0.606), (0.720, 0.526), (0.860, 0.476), (0.960, 0.600)]
    dmats = ['InteriorDark'] * 4 + ['Interior'] * 3 + ['InteriorDark'] * 5
    xs = [-xa, -xa + 0.012, -0.55, -0.2, 0.0, 0.2, 0.55, xa - 0.012, xa]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < xa - 0.006 else 0.010
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # ---- driver binnacle with a big centre tacho and two small dials
    hood = [(0.565, 0.958), (0.535, 0.993), (0.470, 0.998), (0.446, 0.988), (0.441, 0.973), (0.470, 0.976),
            (0.525, 0.965)]
    I.extend(ck.sweep_axis('x', [-0.545, -0.535, -0.205, -0.195],
                           [[(y, z - (0.01 if k in (0, 3) else 0)) for (y, z) in hood] for k in range(4)],
                           'InteriorDark'))
    for (x, z, r, nt) in ((-0.370, 0.915, 0.050, 11), (-0.478, 0.902, 0.032, 7), (-0.262, 0.902, 0.032, 7)):
        c = Vector((x, 0.479 + 0.06 * (0.93 - z) * 0.0, z))
        n = (EYE - c).normalized()
        I.extend(ck.gauge(c + n * 0.002, n, r, n_ticks=nt))
    # ---- centre switch panel + toggles, co-driver trip computer
    I.extend(ck.box_between((0.0, 0.500, 0.720), (0.0, 0.475, 0.900), 0.240, 0.014, 'InteriorDark', up=(0, 1, 0)))
    for row, z in enumerate((0.760, 0.810, 0.860)):
        for k in range(5):
            x = -0.08 + 0.04 * k
            m = 'Gauge' if (row == 0 and k in (1, 3)) else 'Interior'
            I.extend(ck.box_between((x, 0.470, z), (x, 0.452, z + 0.006), 0.012, 0.012, m))
    tc = Vector((0.380, 0.640, 0.985))
    I.extend(ck.box_between(tc + Vector((0, 0.03, -0.02)), tc + Vector((0, -0.03, 0.015)), 0.200, 0.060,
                            'InteriorDark'))
    scr = ck.Part()
    nrm = Vector((0.0, -0.75, 0.66)).normalized()
    side = Vector((1, 0, 0))
    up = nrm.cross(side)
    if up.z < 0:
        up = -up
    cc = tc + Vector((0, -0.032, 0.000)) + nrm * 0.002
    q = [scr.vert(cc + side * u + up * v) for (u, v) in ((-0.080, -0.018), (0.080, -0.018), (0.080, 0.018),
                                                          (-0.080, 0.018))]
    scr.face(q, 'Gauge')
    if scr.face_normal(0).dot(nrm) < 0:
        scr.f[0] = tuple(reversed(scr.f[0]))
    I.extend(scr)
    # ---- steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.26, 0.070, 0.080, 'InteriorDark'))
    # ---- transmission tunnel, sequential lever, hydraulic handbrake, fire extinguisher
    cys = [0.640, 0.500, 0.300, 0.050, -0.250, -0.560]
    tops = [0.640, 0.590, 0.530, 0.510, 0.520, 0.520]
    profs = [[(-0.105, 0.20), (0.105, 0.20), (0.110, t - 0.03), (0.085, t), (-0.085, t), (-0.110, t - 0.03)]
             for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'Interior', 'Interior',
                                             'InteriorDark']))
    I.extend(ck.box_between((0.0, 0.330, 0.540), (0.0, 0.230, 0.552), 0.090, 0.024, 'Alu'))
    I.extend(ck.rod((0.010, 0.290, 0.550), (-0.050, 0.235, 0.820), 0.008, 'Alu', n=8))
    I.extend(ck.ellipsoid((-0.052, 0.232, 0.835), (0.022, 0.022, 0.030), 'InteriorDark', nu=10, nv=8))
    I.extend(ck.box_between((0.020, 0.080, 0.515), (0.020, -0.050, 0.530), 0.050, 0.035, 'Alu'))
    I.extend(ck.rod((0.020, 0.040, 0.530), (-0.035, 0.110, 0.790), 0.010, 'InteriorCage', n=8))
    I.extend(ck.rod((-0.035, 0.110, 0.790), (-0.045, 0.125, 0.840), 0.016, 'InteriorDark', n=8))
    I.extend(ck.rod((0.0, -0.420, 0.565), (0.0, -0.160, 0.565), 0.044, 'InteriorAccent', n=12))
    I.extend(ck.box_between((0.0, -0.290, 0.505), (0.0, -0.290, 0.560), 0.100, 0.020, 'Alu'))
    # ---- roll cage first (the harness straps end on its harness bar)
    hb = roll_cage(I)
    # ---- two bucket seats with red harnesses
    for x in (-0.370, 0.370):
        I.extend(ck.bucket_seat(x, SEAT_Y[0], SEAT_Y[1], SEAT_Z, width=0.52, recline=SEAT_RECLINE,
                                back_h=SEAT_BACK_H, bolster=0.110, headrest_w=0.26))
        I.extend(harness(x, SEAT_Y[1], SEAT_Z, SEAT_RECLINE, SEAT_BACK_H, hb[0].y, hb[0].z))
    # ---- flat rally door cards with a red pull strap
    door = ck.Part()
    xd = min(inner_x(y, z) for y in (0.80, 0.4, 0.0, -0.38) for z in (0.42, 0.62, 0.86)) - 0.006
    door.extend(ck.box_between((xd, 0.820, 0.640), (xd, -0.380, 0.640), 0.008, 0.400, 'InteriorDark', up=(0, 0, 1)))
    door.extend(ck.box_between((xd - 0.006, 0.300, 0.760), (xd - 0.006, -0.100, 0.700), 0.030, 0.008,
                               'InteriorAccent', up=(1, 0, 0)))
    I.extend(door, door.mirrored_x())
    # ---- pedals, co-driver footrest, rear-view mirror
    for x, w in ((-0.465, 0.050), (-0.375, 0.075), (-0.285, 0.050)):
        I.extend(ck.box_between((x, 0.800, 0.260), (x, 0.760, 0.370), w, 0.012, 'Alu'))
    I.extend(ck.box_between((0.37, 0.830, 0.250), (0.37, 0.700, 0.330), 0.300, 0.012, 'Alu'))
    I.extend(ck.box_between((-0.095, Y_HEADER + 0.020, 1.255), (0.095, Y_HEADER + 0.020, 1.255), 0.018, 0.048,
                            'InteriorDark'))
    I.extend(ck.box_between((0.0, Y_HEADER + 0.012, 1.280), (0.0, Y_HEADER - 0.020, 1.310), 0.016, 0.016,
                            'InteriorDark'))
    # ---- rear strut brace, spare wheel
    I.extend(ck.rod((-0.540, -1.420, 0.680), (0.540, -1.420, 0.680), 0.016, 'InteriorCage', n=8))
    zf = BODY.params_at(-1.30)['zb'] + D_IN
    I.extend(spare_wheel(-1.300, zf))
    I.extend(ck.box_between((0.0, -0.98, zf + 0.212), (0.0, -1.62, zf + 0.212), 0.040, 0.006, 'InteriorAccent'))
    car.add('Interior', I)
    # ---- deep-dish three-spoke rally wheel (separate object, origin at the hub)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.017, 0.019), flat_bottom=False, hub_r=0.050, dish=0.045,
                                spokes=((0.0, 0.045), (180.0, 0.045), (270.0, 0.034)), marker=True)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=15, spokes=6, style='single', segs=44, rim_segs=36,
                  spoke_w=(0.058, 0.020), spoke_thick=0.026, spoke_dish=0.020, hub_r=0.062, nuts=6,
                  tyre='tall', grooves=[-0.050, 0.0, 0.050], groove_w=0.015, groove_depth=0.010,
                  zigzag=0.006, shoulder_zigzag=0.005,
                  disc_r=0.148, caliper_angle=150.0, caliper_span=46.0)


def build():
    paint = (0.905, 0.905, 0.871)             # #F4F4F0 (sRGB) -> linear
    mats = ck.default_materials(paint=paint, paint_metallic=0.0, paint_rough=0.30, paint_coat=0.5,
                                rim=(0.80, 0.80, 0.79), rim_metallic=0.0, rim_rough=0.32,
                                caliper=(0.70, 0.42, 0.04),
                                interior=(0.060, 0.060, 0.064), interior_dark=(0.014, 0.014, 0.016))
    mats['Glass'] = dict(base=(0.010, 0.012, 0.016), roughness=0.03, alpha=0.30, double_sided=True)
    mats['Alu'] = dict(base=(0.60, 0.61, 0.63), metallic=1.0, roughness=0.36)
    mats['TowStrap'] = dict(base=(0.70, 0.05, 0.02), roughness=0.60)
    mats['InteriorAccent'] = dict(base=(0.55, 0.025, 0.020), roughness=0.60)
    mats['InteriorCage'] = dict(base=(0.50, 0.50, 0.52), metallic=0.3, roughness=0.40)
    car = ck.CarAssembly(CAR_ID, CAR_NAME, mats)
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Glass', shell.glass)
    car.add('Interior', shell.inner)
    if STAGE != 'body':
        body_details(car, shell.surface)
        interior(car)
        ck.add_wheels(car, WHEEL_SPEC, axles=dict(front=(YF, TRACK_F / 2), rear=(YR, TRACK_R / 2)))
        car.socket('Socket_CamHood', (0.0, 1.060, 1.040))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.140, 0.440))
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
    width_body = 2 * max(abs(v.x) for v in bv if not (abs(v.y - 0.88) < 0.12 and v.z > 0.97))   # mirrors excluded
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
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'rally car (1990s-flavoured gravel coupe-hatch)', 'drivetrain': 'AWD',
        'engine': 'front, turbo', 'doors': 3, 'seats': 2, 'source_blend': 'Opus55ForzaUltracodeEffort.blend',
        'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(BODY.nose['y'] - BODY.tail['y'], 4),
        'length_overall': round(mx.y - mn.y, 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(roof, 4), 'height_overall': round(all_mx.z, 4),
        'ground_clearance': round(BODY.params_at(0.0)['zb'], 4), 'ground_clearance_min': round(mn.z, 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'rim_diameter_in_front': 15, 'rim_diameter_in_rear': 15,
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
        'default_paint': {'hex': '#F4F4F0', 'linear_rgb': [0.905, 0.905, 0.871], 'finish': 'gloss'},
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
        hidden = isolate(True)
        try:
            print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W), 'interior verts in wheel wells:', interior_in_wells(CAR),
                  'interior leaks:', interior_leaks(CAR))
        finally:
            isolate(False)
    if RENDER:
        hidden = isolate(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.0, 6.2, 1.45), target=(0.0, 0.10, 0.60),
                                           lens=50.0, world_strength=0.75, sun_energy=3.0, exposure=-0.85,
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
