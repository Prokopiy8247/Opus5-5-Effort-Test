"""Ridgeback SX - rugged 5-door off-road SUV, AWD, tall suspension (car #8 of Sunward Roads).

Rebuilds Cars/Car_ridgeback_sx from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero image
and exports assets/imported/cars/ridgeback_sx.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\ridgeback_sx.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking), DEBUG (bool).

Spec: L 4.70 overall (bull bar -> spare wheel; shell 4.29), W 1.95 over the fender flares, H 1.85 without the roof
rack, wheelbase 2.85, track 1.65 / 1.65, wheel R 0.40 (17" matte-black 6-spoke steel-look rims, 265-wide all-terrain
tyres with raised tread blocks), ground clearance 0.28 (diff housings; body floor at 0.46). Original design (no real
brand / model): upright two-box body with slab sides, a crisp shoulder crease and a flat hood between flat-topped
wings, near-vertical windscreen, flat roof with a tubular roof basket, big glasshouse with a black B-pillar and body-
coloured C/D pillars, chunky bolt-on plastic flares, black rocker cladding, side steps, exposed door hinges, a
snorkel up the right A-pillar, square black grille with body-coloured slats and two round halo headlamps, black
bumpers with a steel bull bar and an aluminium skid plate, side-hinged tailgate carrying the spare wheel, vertical
corner tail lamps, rear ladder, visible frame rails / solid axles / diff housings underneath.
Interior: 2 front seats + 3-seat rear bench (5 seats), upright two-tone dash with a binnacle, chunky 4-spoke wheel,
centre console with gear and transfer levers, passenger grab handle, door cards, cargo floor.
Default paint olive / khaki #6B6B3A, matte-ish.
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

CAR_ID = 'ridgeback_sx'
CAR_NAME = 'Ridgeback SX'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
DEBUG = globals().get('DEBUG', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.85
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.425)
TRACK_F, TRACK_R = 1.65, 1.65
WHEEL_R, WHEEL_W = 0.400, 0.265
ARCH_R, ARCH_Z = 0.433, 0.407                  # ~3.3 cm gap at the sides, ~4 cm above the tyre
FLARE_X = 0.975                                # flare outer face -> 1.95 m overall width
NOSE_Y, TAIL_Y = 2.190, -2.098                 # cap poles -> shell length 4.29

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs), K3 waist / widest
# (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr), K8 crown (zc).
# Hood stations: K5 = hood shut line on the flat wing top, K6 = a point on the hood, K8 = hood centre.
# Tail: the roof folds down over the last 6 cm into the near-vertical rear glass / tailgate (band 7); the cap below
# is the lower tailgate.
CAB = dict(zb=0.460, wb=0.620, zs=0.520, ws=0.885, zw=0.800, ww=0.915, zh=1.175, wh=0.905, zg=1.225, wg=0.862,
           zr=1.795, wr=0.812, zc=1.850)


def cab(**kw):
    d = dict(CAB)
    d.update(kw)
    return d


Y_HEADER = 0.800         # windscreen header
Y_COWL = 1.000           # windscreen base
Y_SAIL = 0.905           # door glass front edge (black mirror sail ahead of it)
Y_BPIL = (-0.100, -0.035)  # black B-pillar
Y_CPIL = (-1.060, -0.925)  # body-coloured C-pillar
Y_QTR = -1.960           # rear quarter glass rear edge (body-coloured D-pillar behind it)
Y_ROOF_END = -2.025      # roof rear edge (fold starts)

S = [
    # ---- tail: roof folds into the rear glass, plan-view corner rounding, departure-angle rise
    dict(y=-2.080, zb=0.500, wb=0.560, zs=0.550, ws=0.842, zw=0.800, ww=0.872, zh=1.168, wh=0.862, zg=1.212,
         wg=0.822, zr=1.236, wr=0.770, zc=1.245, rail=0.130),
    dict(y=-2.065, zb=0.497, wb=0.575, zs=0.548, ws=0.863, zw=0.800, ww=0.893, zh=1.172, wh=0.883, zg=1.220,
         wg=0.843, zr=1.400, wr=0.795, zc=1.420, rail=0.150),
    dict(y=-2.045, zb=0.493, wb=0.590, zs=0.545, ws=0.876, zw=0.800, ww=0.906, zh=1.175, wh=0.896, zg=1.224,
         wg=0.855, zr=1.700, wr=0.806, zc=1.740, rail=0.165),
    dict(y=Y_ROOF_END, zb=0.490, wb=0.600, zs=0.542, ws=0.882, zw=0.800, ww=0.912, zh=1.175, wh=0.902, zg=1.225,
         wg=0.860, zr=1.795, wr=0.811, zc=1.850, rail=0.070, sharp=dict(zc=0.7, zr=0.7)),
    # ---- cabin: slab sides, flat roof
    cab(y=-1.900, zb=0.470, wb=0.610, zs=0.528),
    cab(y=YR),
    cab(y=-0.400),
    cab(y=0.400),
    cab(y=Y_HEADER, sharp=dict(zc=0.6, zr=0.6, wr=0.3)),
    # ---- near-vertical windscreen (17 deg from vertical) down to the cowl
    cab(y=Y_COWL, zg=1.222, wg=0.860, zr=1.228, wr=0.835, zc=1.222, sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- flat hood between flat-topped wings, square nose
    cab(y=1.100, zh=1.180, zg=1.205, wg=0.800, zr=1.200, wr=0.640, zc=1.200),
    cab(y=YF, zh=1.178, zg=1.200, wg=0.800, zr=1.196, wr=0.560, zc=1.196),
    cab(y=1.900, zb=0.470, zs=0.525, zh=1.176, zg=1.196, wg=0.800, zr=1.192, wr=0.555, zc=1.192),
    dict(y=2.080, zb=0.495, wb=0.600, zs=0.540, ws=0.882, zw=0.800, ww=0.912, zh=1.172, wh=0.902, zg=1.192,
         wg=0.798, zr=1.188, wr=0.555, zc=1.188),
    dict(y=2.125, zb=0.505, wb=0.590, zs=0.545, ws=0.874, zw=0.800, ww=0.905, zh=1.168, wh=0.895, zg=1.187,
         wg=0.792, zr=1.183, wr=0.550, zc=1.183),
    dict(y=2.155, zb=0.512, wb=0.575, zs=0.550, ws=0.862, zw=0.800, ww=0.892, zh=1.160, wh=0.882, zg=1.178,
         wg=0.782, zr=1.175, wr=0.545, zc=1.175),
    dict(y=2.172, zb=0.520, wb=0.555, zs=0.555, ws=0.842, zw=0.800, ww=0.872, zh=1.146, wh=0.862, zg=1.163,
         wg=0.765, zr=1.160, wr=0.535, zc=1.160),
]

KEY_SHARP = (0, 0.7, 0.6, 0.35, 0.85, 0.55, 0.55, 0.0, 0)
NOSE = dict(y=NOSE_Y, z=0.840, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8)
TAIL = dict(y=TAIL_Y, z=0.870, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8)
BANDS = [3, 3, 3, 4, 2, 4, 2, 5]


def _rear_glass_range(z_top=1.775, z_bot=1.430):
    """Base-y range of the fold where the roof crown passes z_top .. z_bot (rear glass between them)."""
    tmp = ck.LoftBody(stations=S, band_segments=BANDS, key_sharp=KEY_SHARP, nose=NOSE, tail=TAIL)
    ys = [Y_ROOF_END - 0.0005 * k for k in range(0, 121)]
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
    dict(bands=(5, 5), y=(Y_QTR, Y_SAIL), role='glass'),           # door + rear quarter glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),           # mirror sail
    dict(bands=(5, 5), y=Y_BPIL, role='trim'),                     # B-pillar (black)
    dict(bands=(5, 5), y=Y_CPIL, role='paint'),                    # C-pillar (body colour)
    dict(bands=(7, 7), y=(YG0, YG1), role='glass'),                # rear glass in the tailgate
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
    step=0.065,
    rail=0.07,
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.660), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.660)]
INNER = dict(y=(-2.078, 0.990), d=0.035, dy_ramp=(-1.980, -2.078), center_z=1.15,   # tall cabin: orient faces
             tubs=[(YR, ARCH_Z, ARCH_R + 0.055, 0.640), (YF, ARCH_Z, ARCH_R + 0.055, 0.640)])  # toward mid-height
# (tub radius 5.5 cm beyond the arch: the coarse inner-shell transition then lies outside the liner radius)

EYE = Vector((-0.420, -0.150, 1.520))        # driver eye point (LHD, driver on the left = -X), high SUV seating
HUB = Vector((-0.420, 0.420, 1.160))         # steering wheel hub
COLUMN_TILT = 24.0                           # deg, column descends toward the dash
SW_R = 0.190                                 # steering wheel radius (chunky 4-spoke)
D_IN = INNER['d']
SEAT_Z = 0.660                               # front seat base (runners stay above the cabin floor at 0.495)
SEAT_Y = (0.400, -0.100)
SEAT_RECLINE, SEAT_BACK_H = 15.0, 0.840
BENCH_Y, BENCH_Z, BENCH_RECLINE, BENCH_BACK_H, BENCH_W = (-0.470, -0.930), 0.680, 20.0, 0.660, 1.300

SPARE = Vector((-0.040, 0.0, 1.010))         # spare wheel centre (y set from the tailgate face in rear_details)


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


def lathe_y(profile, segs, mats, center):
    """Revolve a profile [(a, r)] about the Y axis (a = position along +Y), placed at `center`."""
    p = ck.revolve(profile, segs, mats)
    M = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(90.0), 4, 'Z')
    return p.transformed(M)


def lathe_neg_y(profile, segs, mats, center):
    """Revolve a profile [(a, r)] about the Y axis with a measured along -Y (rear-facing lamps)."""
    p = ck.revolve(profile, segs, mats)
    M = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(-90.0), 4, 'Z')
    return p.transformed(M)


UNDER = (Vector((0, 0, 0)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))   # view from below: (x, y)


def under_z(S_, x, y, default=0.46):
    loc, nor = S_.hit(UNDER, x, y)
    return loc.z if loc is not None else default


def body_x(y, z):
    """x of the outer body side (right) at (y, z) from the analytic loft section."""
    h = BODY.half(y)
    best = None
    for a, b in zip(h[:-1], h[1:]):
        if (a.y - z) * (b.y - z) <= 0 and abs(b.y - a.y) > 1e-9 and max(a.x, b.x) > 0.3:
            t = (z - a.y) / (b.y - a.y)
            x = a.x + (b.x - a.x) * t
            best = x if best is None else max(best, x)
    return best if best is not None else 0.90


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


def frame_box(c, axis_u, axis_v, nrm, w, h, bar, depth, mat, back_mat=None, back_off=0.002):
    """Rectangular recess frame (4 bars) centred at c on a flat face with outward normal nrm (number plates)."""
    P = ck.Part()
    u, v, n = Vector(axis_u), Vector(axis_v), Vector(nrm)
    for (a, b, ww) in (((-w / 2, h / 2), (w / 2, h / 2), bar), ((-w / 2, -h / 2), (w / 2, -h / 2), bar)):
        p0 = c + u * a[0] + v * a[1] + n * (depth / 2)
        p1 = c + u * b[0] + v * b[1] + n * (depth / 2)
        P.extend(ck.box_between(p0 - u * bar / 2, p1 + u * bar / 2, ww, depth, mat, up=tuple(n)))
    for sx in (-1, 1):
        p0 = c + u * (sx * w / 2) + v * (-h / 2) + n * (depth / 2)
        p1 = c + u * (sx * w / 2) + v * (h / 2) + n * (depth / 2)
        P.extend(ck.box_between(p0, p1, bar, depth, mat, up=tuple(n)))
    if back_mat:
        q = ck.Part()
        cc = c + n * back_off
        ids = [q.vert(cc + u * (sx * w / 2) + v * (sy * h / 2)) for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        q.face(ids, back_mat)
        if q.face_normal(0).dot(n) < 0:
            q.f[0] = tuple(reversed(q.f[0]))
        P.extend(q)
    return P


# =====================================================================================================
# exterior details
# =====================================================================================================
def front_details(car, S_, R, C, LH):
    D = ck.densify
    yF = S_.snap('front', 0.0, 0.60).y
    # ---- square black grille panel with a body-coloured surround and vertical body-coloured slats
    gr = D(ck.fillet_poly([(-0.790, 0.785), (0.790, 0.785), (0.790, 1.095), (-0.790, 1.095)], 0.035, n=3), 0.06)
    C.extend(S_.patch(gr, 'front', offset=0.0015, depth=0.005, res=0.07, mat='Grille', smooth=False))
    C.extend(S_.rim(gr, 'front', width=0.016, offset=0.009, depth=0.006, mat='Paint', smooth=False))
    for k in range(9):
        x = -0.420 + 0.105 * k
        yy = S_.snap('front', x, 0.94).y
        C.extend(ck.box_between((x, yy + 0.010, 0.805), (x, yy + 0.010, 1.075), 0.026, 0.020, 'Paint'))
    # thin horizontal bar through the slats
    yy = S_.snap('front', 0.0, 0.94).y
    C.extend(ck.box_between((-0.455, yy + 0.006, 0.940), (0.455, yy + 0.006, 0.940), 0.010, 0.014, 'Trim'))
    # ---- round halo headlamps at the grille ends (chrome bezel, domed lens, projector ring)
    cs = []
    for sx in (1,):
        x, z = 0.635 * sx, 0.940
        yl = S_.snap('front', x, z).y + 0.002
        R.extend(lathe_y([(0.000, 0.122), (0.010, 0.121), (0.018, 0.113), (0.016, 0.100), (0.004, 0.097)], 32,
                         'Chrome', (x, yl, z)))
        R.extend(lathe_y([(0.002, 0.100), (0.002, 0.0)], 32, 'Grille', (x, yl, z)))      # dark back plate
        LH.extend(lathe_y([(0.006, 0.0985), (0.016, 0.092), (0.026, 0.068), (0.031, 0.035), (0.032, 0.0)], 32,
                          'HeadlightLens', (x, yl, z)))
        R.extend(ck.torus((x, yl + 0.0285, z), (0, 1, 0), 0.060, 0.0042, 'Chrome', nu=20, nv=4))
        cs.append(Vector((x, yl + 0.02, z)))
    hc = cs[0]
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))
    # ---- amber indicators below the lamps
    ind = D(ck.fillet_poly([(0.555, 0.722), (0.715, 0.722), (0.715, 0.752), (0.555, 0.752)], 0.008, n=2), 0.03)
    R.extend(S_.patch(ck.offset_poly(ind, 0.006), 'front', offset=0.002, depth=0.005, res=0.0, mat='Trim', smooth=False))
    R.extend(S_.patch(ind, 'front', offset=0.0045, depth=0.004, res=0.0, mat='Amber', smooth=False))
    # ---- hood shut line across the nose
    C.extend(S_.line(D([(-0.765, 1.128), (0.765, 1.128)], 0.02, closed=False), 'front', offset=0.0015, smooth=False,
                     step=0.025))

    # ---- chunky black bumper wrapping round the corners (its face follows the body's rounded corner + 7.5 cm)
    def wrap(x):
        p = S_.snap('front', math.copysign(min(abs(x), 0.890), x), 0.620)
        py = yF if p is None else max(p.y, yF - 0.060)          # never follow a ray that slipped past the nose
        yb_ = min(yF, py) + 0.075
        return yF + 0.075 - yb_ + 0.030 * ck.smoothstep(0.850, 0.905, abs(x)) ** 2
    xs = [-0.905, -0.897, -0.880, -0.850, -0.800, -0.700, -0.450, 0.0, 0.450, 0.700, 0.800, 0.850, 0.880, 0.897,
          0.905]
    profs = []
    for x in xs:
        yb = yF + 0.075 - wrap(x)
        e = 0.010 if abs(x) > 0.9 else 0.0
        profs.append([(yb - 0.140, 0.455 + e), (yb - 0.012 - e, 0.455 + e), (yb - e, 0.472), (yb + 0.002 - e, 0.683),
                      (yb - 0.010 - e, 0.700 - e), (yb - 0.140, 0.700 - e)])
    C.extend(ck.sweep_axis('x', xs, profs, 'Plastic'))
    yb0 = yF + 0.075
    # fog lamps in the bumper corners
    for sx in (1,):
        x = 0.690 * sx
        yfl = yF + 0.075 - wrap(x) + 0.002
        R.extend(lathe_y([(0.0, 0.050), (0.006, 0.049), (0.008, 0.041), (0.002, 0.039)], 20, 'Chrome', (x, yfl, 0.585)))
        LH.extend(lathe_y([(0.003, 0.040), (0.008, 0.034), (0.010, 0.0)], 20, 'HeadlightLens', (x, yfl, 0.585)))
    # number plate recess
    C.extend(frame_box(Vector((0.0, yb0 + 0.002, 0.578)), (1, 0, 0), (0, 0, 1), (0, 1, 0), 0.520, 0.115, 0.012,
                       0.007, 'Trim', back_mat='Grille'))
    # red tow hooks under the bumper
    for sx in (-1, 1):
        C.extend(ck.torus((sx * 0.360, yb0 - 0.010, 0.448), (1, 0, 0), 0.030, 0.008, 'TowStrap', nu=12, nv=5))

    # ---- steel bull bar: outer hoop, two inner uprights, a low cross bar, mounting tabs
    yB = yb0 + 0.026
    rb = 0.024
    hoop = [(-0.470, yB, 0.475), (-0.470, yB, 0.900), (-0.462, yB - 0.003, 0.965), (-0.420, yB - 0.006, 1.010),
            (-0.330, yB - 0.008, 1.025), (0.330, yB - 0.008, 1.025), (0.420, yB - 0.006, 1.010),
            (0.462, yB - 0.003, 0.965), (0.470, yB, 0.900), (0.470, yB, 0.475)]
    C.extend(ck.rod_path(ck.cr_resample(hoop, closed=False, sub=3), rb, 'Steel', n=8))
    for sx in (-1, 1):
        C.extend(ck.rod((sx * 0.290, yB, 0.475), (sx * 0.290, yB - 0.008, 1.020), rb * 0.85, 'Steel', n=8))
        for z in (0.520, 0.650):
            C.extend(ck.box_between((sx * 0.470, yB, z), (sx * 0.470, yb0 - 0.030, z), 0.040, 0.050, 'Steel'))
    C.extend(ck.rod((-0.470, yB, 0.745), (0.470, yB, 0.745), rb * 0.8, 'Steel', n=8))

    # ---- aluminium skid plate from the bumper lip back under the engine, bolts
    xs = [-0.540, -0.530, -0.300, 0.0, 0.300, 0.530, 0.540]
    top = [(yb0 - 0.010, 0.462), (yb0 - 0.050, 0.425), (yF - 0.080, 0.385), (1.900, 0.368), (1.700, 0.368)]
    profs = []
    for x in xs:
        sc = 0.006 if abs(x) > 0.535 else 0.0
        bot = [(y, z - 0.010) for (y, z) in top]
        profs.append([(y, z - sc) for (y, z) in top] + [(y, z + sc) for (y, z) in reversed(bot)])
    C.extend(ck.sweep_axis('x', xs, profs, 'Alu'))
    for x in (-0.38, 0.38):
        for y in (1.80, 2.06):
            C.extend(ck.disc((x, y, 0.3565 if y < 1.9 else 0.3695), (0, 0, -1), 0.010, 'Steel', n=8))
    return yF


def hood_details(S_, R, C):
    D = ck.densify
    # ---- hood shut lines along the flat wing tops
    edge = [BODY.point(y, 5.0, 1) for y in (Y_COWL + 0.06, 1.25, 1.50, 1.75, 1.95, 2.10, 2.150)]
    R.extend(S_.line3d(edge, step=0.04))
    # ---- two louvred intakes on the hood
    for sx in (1,):
        vent = D(ck.fillet_poly([(0.300, 1.400), (0.500, 1.400), (0.500, 1.720), (0.300, 1.720)], 0.025, n=3), 0.03)
        R.extend(S_.patch(vent, 'top', offset=0.0015, depth=0.006, res=0.06, mat='Grille', smooth=False))
        R.extend(S_.rim(vent, 'top', width=0.014, offset=0.007, depth=0.006, mat='Plastic', smooth=False))
        for k in range(5):
            yv = 1.435 + k * 0.062
            pts = [(0.312 + 0.044 * j, yv) for j in range(5)]
            sp = [S_.snap('top', a, b) for (a, b) in pts]
            R.extend(ck.sweep_path([p + Vector((0, 0, 0.001)) for p in sp],
                                   [(-0.009, -0.002), (0.009, -0.002), (0.014, 0.009), (0.000, 0.009)], 'Plastic',
                                   up=(0, 0, 1)))
    # ---- washer jets
    for sx in (-1, 1):
        p = S_.snap('top', sx * 0.25, Y_COWL + 0.12)
        C.extend(ck.ellipsoid(p + Vector((0, 0, 0.004)), (0.010, 0.016, 0.007), 'Trim', nu=8, nv=5))
    # ---- wipers parked at the base of the (near-vertical) windscreen, resting on the glass
    F = S_.frame('front')
    for (x0, x1, px) in ((-0.70, -0.08, -0.36), (-0.02, 0.62, 0.30)):
        l0, n0 = S_.hit(F, x0, 1.262)
        l1, n1 = S_.hit(F, x1, 1.262)
        a0, a1 = l0 + n0 * 0.010, l1 + n1 * 0.010
        C.extend(ck.box_between(a0, a1, 0.012, 0.014, 'Trim', up=tuple(n0)))
        pivot = S_.snap('top', px, Y_COWL + 0.030) + Vector((0, 0, 0.010))
        mid = (a0 + a1) / 2 + n0 * 0.006
        C.extend(ck.box_between(pivot, mid, 0.012, 0.008, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.016, 0.016, 0.010), 'Trim', nu=10, nv=6))


def snorkel(R):
    """Raised air intake: tube from the right front wing up the A-pillar, ram head above the roof line."""
    pts = [Vector((body_x(1.225, 0.975) + 0.020, 1.225, 0.975)),
           Vector((body_x(1.205, 1.085) + 0.030, 1.205, 1.085)),
           Vector((0.938, 1.178, 1.180)),
           Vector((0.915, 1.140, 1.250))]
    for y in (1.020, 0.960, 0.900, 0.850, 0.815):
        p = BODY.point(y, 6.45, 1)
        pts.append(Vector((p.x + 0.052, p.y + 0.026, p.z)))
    top = pts[-1] + Vector((0.0, 0.004, 0.060))
    pts.append(top)
    path = ck.cr_resample(pts, closed=False, sub=2)
    R.extend(ck.rod_path(path, 0.040, 'Plastic', n=10))
    # foot plate where the tube meets the wing
    p = pts[0]
    R.extend(ck.box_between(p + Vector((-0.022, 0.0, -0.06)), p + Vector((-0.022, 0.0, 0.06)), 0.010, 0.11, 'Plastic',
                            up=(1, 0, 0)))
    # ram head facing forward
    hc = top + Vector((0.0, 0.050, 0.025))
    head = ck.ellipsoid(hc, (0.058, 0.105, 0.058), 'Plastic', nu=16, nv=8, exp=3.2,
                        deform=lambda q: Vector((q.x, q.y if q.y < 0 else q.y * 0.6, q.z)))
    R.extend(head)
    front = hc + Vector((0.0, 0.105 * 0.6 + 0.001, 0.0))
    R.extend(ck.disc(front, (0, 1, 0), 0.040, 'Grille', n=16, ring_mat='Trim', ring_w=0.006))
    for z in (-0.016, 0.0, 0.016):
        R.extend(ck.box_between(front + Vector((-0.036, 0.003, z)), front + Vector((0.036, 0.003, z)), 0.004, 0.004,
                                'Trim'))


def side_details(car, S_, R, C):
    D = ck.densify
    # ---- chunky plastic flares over both arches
    for ya in (YF, YR):
        R.extend(ck.arch_flare(ya, ARCH_Z, ARCH_R + 0.001, ARCH_R + 0.110, FLARE_X, body_x, a0=15.0, a1=165.0,
                               segs=30, mat='Plastic'))
    # ---- black rocker cladding between the arches
    clad = D(ck.fillet_poly([(-0.900, 0.528), (0.900, 0.528), (0.900, 0.640), (-0.900, 0.640)], 0.012, n=2), 0.08)
    R.extend(S_.patch(clad, 'right', offset=0.0030, depth=0.006, res=0.08, mat='Plastic', smooth=False))
    # ---- side steps: steel beam on three brackets, aluminium tread plate
    xs0, zs0 = 0.905, 0.410
    R.extend(ck.box_between((xs0, -0.880, zs0), (xs0, 0.880, zs0), 0.120, 0.036, 'Steel'))
    R.extend(ck.box_between((xs0, -0.860, zs0 + 0.020), (xs0, 0.860, zs0 + 0.020), 0.104, 0.006, 'Alu'))
    for y in (-0.860, -0.020, 0.840):
        for x in (xs0 - 0.040, xs0 + 0.040):
            R.extend(ck.box_between((x, y, zs0 + 0.019), (x, y + 0.020, zs0 + 0.019), 0.010, 0.004, 'Plastic'))
    for y in (-0.700, 0.0, 0.700):
        R.extend(ck.box_between((0.660, y, 0.455), (xs0 - 0.030, y, zs0 - 0.004), 0.050, 0.030, 'Steel'))
    # ---- door shut lines, handles, exposed hinges
    for (y, z0, z1) in ((0.888, 0.645, 1.190), (-0.065, 0.645, 1.190), (-0.925, 0.665, 1.190)):
        R.extend(S_.line([(y, z0), (y + 0.002, 0.90), (y + 0.004, z1)], 'right', step=0.03))
    for yc in (0.090, -0.800):
        R.extend(S_.patch(D(ck.rrect_pts(yc, 1.088, 0.140, 0.030, 0.011, n=3), 0.02), 'right', offset=0.0055,
                          depth=0.006, res=0.0, mat='Trim', smooth=False))
        R.extend(S_.patch(D(ck.rrect_pts(yc + 0.045, 1.088, 0.030, 0.016, 0.006, n=2), 0.02), 'right', offset=0.0075,
                          depth=0.003, res=0.0, mat='Chrome', smooth=False))
    for (yh, zs) in ((0.862, (0.760, 1.050)), (-0.092, (0.760, 1.050))):
        for z in zs:
            loc, nor = S_.hit(S_.frame('right'), yh, z)
            R.extend(ck.box_between(loc + Vector((0.002, 0.016, 0.0)), loc + Vector((0.002, -0.034, 0.0)), 0.044,
                                    0.012, 'Steel', up=(1, 0, 0)))                               # hinge leaf
            R.extend(ck.rod(loc + Vector((0.010, 0.018, -0.026)), loc + Vector((0.010, 0.018, 0.026)), 0.0075,
                            'Steel', n=8))                                                       # knuckle / pin
    # ---- side marker / indicator on the front wing behind the arch
    loc, nor = S_.hit(S_.frame('right'), 2.000, 1.000)
    R.extend(ck.disc(loc + nor * 0.003, nor, 0.022, 'Amber', n=14, ring_mat='Trim', ring_w=0.005))
    # ---- big square mirrors on arms from the door top
    mc = Vector((1.025, 0.800, 1.335))
    ry = 0.036

    def flat_back(q):
        if q.y < -0.6 * ry:
            q.y = -0.6 * ry
        return q
    head = ck.ellipsoid(mc, (0.085, ry, 0.095), 'Plastic', nu=16, nv=8, exp=4.0, deform=flat_back)
    R.extend(head)
    mg = ck.Part()
    gp = ck.superellipse_pts(0.0, 0.0, 0.074, 0.083, e=4.0, n=20)
    cen = mg.vert(mc + Vector((0, -0.6 * ry - 0.0012, 0)))
    ring = [mg.vert(mc + Vector((p.x, -0.6 * ry - 0.0012, p.y))) for p in gp]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    base = S_.snap('right', 0.850, 1.205)
    R.extend(ck.box_between(base + Vector((-0.012, 0.0, 0.0)), mc + Vector((-0.060, 0.000, -0.030)), 0.030, 0.026,
                            'Plastic'))
    R.extend(ck.box_between(base + Vector((-0.012, 0.0, 0.030)), mc + Vector((-0.060, 0.000, 0.040)), 0.020, 0.016,
                            'Plastic'))
    R.extend(ck.box_between(base + Vector((-0.020, -0.025, -0.010)), base + Vector((-0.020, 0.040, -0.010)), 0.040,
                            0.050, 'Plastic', up=(1, 0, 0)))
    # ---- fuel filler (right rear quarter only)
    C.extend(S_.line(D(ck.rrect_pts(-1.620, 1.040, 0.130, 0.110, 0.018, n=3), 0.02), 'right', closed=True,
                     smooth=False, step=0.012))
    loc, nor = S_.hit(S_.frame('right'), -1.565, 1.040)
    C.extend(ck.box_between(loc + nor * 0.003, loc + nor * 0.003 + Vector((0, -0.020, 0)), 0.010, 0.040, 'Trim',
                            up=(1, 0, 0)))
    # ---- drip rails along the roof edges (body colour)
    rail = [BODY.point(y, 6.22, 1) for y in (Y_ROOF_END + 0.02, -1.60, -1.0, -0.40, 0.20, 0.60, Y_HEADER - 0.01)]
    R.extend(S_.line3d(rail, width=0.008, offset=0.0035, mat='Paint', step=0.08))


def rear_details(car, S_, R, C, LT, LB, LR, LBC):
    D = ck.densify
    yR = S_.snap('rear', 0.0, 0.80).y
    # ---- vertical corner tail lamps: brake / tail / indicator / reverse sections
    house = D(ck.fillet_poly([(0.700, 0.695), (0.868, 0.695), (0.868, 1.140), (0.700, 1.140)], 0.018, n=2), 0.03)
    R.extend(S_.patch(house, 'rear', offset=0.002, depth=0.006, res=0.025, mat='Trim', smooth=False))
    secs = [(1.030, 1.122, 'BrakeLens', LB), (0.902, 1.022, 'TaillightLens', LT), (0.800, 0.894, 'Amber', R),
            (0.712, 0.792, 'ReverseLens', LR)]
    for (z0, z1, mat, tgt) in secs:
        sec = D(ck.fillet_poly([(0.713, z0), (0.855, z0), (0.855, z1), (0.713, z1)], 0.008, n=2), 0.025)
        tgt.extend(S_.patch(sec, 'rear', offset=0.0050, depth=0.004, res=0.02, mat=mat, smooth=False))
    # ---- tailgate shut line (side-hinged door between the lamps, up to the roof edge), handle, hinges
    gate = [(-0.688, 0.605), (-0.688, 1.200), (-0.688, 1.802), (0.0, 1.806), (0.688, 1.802), (0.688, 1.200),
            (0.688, 0.605), (0.0, 0.605)]
    C.extend(S_.line(D(gate, 0.03), 'rear', closed=True, smooth=False, step=0.045, offset=0.0012))
    C.extend(S_.patch(D(ck.rrect_pts(-0.600, 1.090, 0.050, 0.120, 0.012, n=3), 0.02), 'rear', offset=0.0055,
                      depth=0.006, res=0.0, mat='Trim', smooth=False))
    for z in (0.760, 1.560):
        loc, nor = S_.hit(S_.frame('rear'), 0.672, z)
        C.extend(ck.box_between(loc + Vector((-0.020, -0.006, 0)), loc + Vector((0.030, -0.006, 0)), 0.060, 0.016,
                                'Steel', up=(0, -1, 0)))
    # ---- spare wheel on the tailgate (part of Body): kit wheel without the brake disc
    sp_wheel, _ = ck.build_wheel(**dict(WHEEL_SPEC, segs=24, rim_segs=24, blocks=dict(n=16, h=0.013)))
    keep = ck.Part()
    keep.v = [v.copy() for v in sp_wheel.v]          # shared vertices kept (smooth shading); unused ones are dropped
    for f, m in zip(sp_wheel.f, sp_wheel.m):
        c = sum((sp_wheel.v[i] for i in f), Vector()) / len(f)
        if m == 'BrakeDisc' and c.x < 0.07:
            continue
        keep.f.append(tuple(f))
        keep.m.append(m)
    y_face = S_.snap('rear', SPARE.x, SPARE.z).y
    SPARE.y = y_face - 0.024 - WHEEL_W / 2
    M = Matrix.Translation(SPARE) @ Matrix.Rotation(math.radians(-90.0), 4, 'Z')      # rim face (+X) -> -Y
    C.extend(keep.transformed(M))
    C.extend(ck.box_between((SPARE.x, y_face + 0.010, SPARE.z), (SPARE.x, SPARE.y + 0.040, SPARE.z), 0.110, 0.110,
                            'Steel'))
    for sz in (-1, 1):
        C.extend(ck.box_between((SPARE.x - 0.25, y_face - 0.004, SPARE.z + sz * 0.18),
                                (SPARE.x + 0.25, y_face - 0.004, SPARE.z + sz * 0.18), 0.040, 0.012, 'Steel',
                                up=(0, -1, 0)))
    # ---- rear ladder on the right half of the tailgate, hooking over onto the roof rack
    for x in (0.445, 0.625):
        lad = []
        for z in (0.680, 1.000, 1.400, 1.700):
            lad.append(Vector((x, S_.snap('rear', x, z).y - 0.055, z)))
        lad.append(Vector((x, lad[-1].y + 0.012, 1.880)))
        lad.append(Vector((x, Y_ROOF_END + 0.040, 1.935)))
        lad.append(Vector((x, -1.888, 1.945)))
        C.extend(ck.rod_path(ck.cr_resample(lad, closed=False, sub=2), 0.014, 'Steel', n=8))
        for z in (0.760, 1.560):
            yy = S_.snap('rear', x, z).y
            C.extend(ck.rod((x, yy + 0.005, z), (x, yy - 0.055, z), 0.010, 'Steel', n=8))
    for z in (0.760, 0.960, 1.160, 1.360, 1.560):
        yy = S_.snap('rear', 0.535, z).y - 0.055
        C.extend(ck.rod((0.445, yy, z), (0.625, yy, z), 0.010, 'Steel', n=8))
    # ---- third brake lamp at the top of the tailgate (on the roof-edge fold)
    loc, nor = S_.hit(S_.frame('rear'), 0.0, 1.812)
    C.extend(ck.box_between((-0.150, loc.y - 0.004, 1.812), (0.150, loc.y - 0.004, 1.812), 0.018, 0.028, 'Trim'))
    LBC.extend(ck.box_between((-0.135, loc.y - 0.0135, 1.812), (0.135, loc.y - 0.0135, 1.812), 0.002, 0.016,
                              'BrakeLens'))

    # ---- black rear bumper with step pad, plate recess, reflectors, tow hitch
    def wrap(x):
        p = S_.snap('rear', math.copysign(min(abs(x), 0.860), x), 0.640)
        py = yR if p is None else min(p.y, yR + 0.060)          # never follow a ray that slipped past the tail
        yb_ = max(yR, py) - 0.115
        return yb_ - (yR - 0.115) + 0.030 * ck.smoothstep(0.850, 0.905, abs(x)) ** 2
    xs = [-0.905, -0.897, -0.880, -0.850, -0.800, -0.700, -0.450, 0.0, 0.450, 0.700, 0.800, 0.850, 0.880, 0.897,
          0.905]
    profs = []
    for x in xs:
        yb = yR - 0.115 + wrap(x)
        e = 0.010 if abs(x) > 0.9 else 0.0
        profs.append([(yb + 0.140, 0.450 + e), (yb + 0.012 + e, 0.450 + e), (yb + e, 0.466), (yb - 0.002 + e, 0.572),
                      (yb + 0.010 + e, 0.588 - e), (yb + 0.140, 0.588 - e)])
    C.extend(ck.sweep_axis('x', xs, profs, 'Plastic'))
    ybb = yR - 0.115
    C.extend(ck.box_between((-0.300, ybb + 0.060, 0.5905), (0.300, ybb + 0.060, 0.5905), 0.090, 0.006, 'Alu'))
    C.extend(frame_box(Vector((0.0, ybb - 0.002, 0.519)), (1, 0, 0), (0, 0, 1), (0, -1, 0), 0.500, 0.105, 0.010,
                       0.006, 'Trim', back_mat='Grille'))
    for sx in (-1, 1):
        x = sx * 0.700
        yy = yR - 0.115 + wrap(x) - 0.003
        LT.extend(ck.box_between((x - 0.055, yy, 0.520), (x + 0.055, yy, 0.520), 0.003, 0.028, 'TaillightLens'))
    C.extend(ck.box_between((0.0, ybb + 0.10, 0.430), (0.0, ybb - 0.075, 0.430), 0.070, 0.070, 'Steel'))
    C.extend(ck.box_between((0.0, ybb - 0.060, 0.430), (0.0, ybb - 0.120, 0.430), 0.050, 0.050, 'Steel'))
    C.extend(ck.torus((0.0, ybb - 0.130, 0.430), (1, 0, 0), 0.024, 0.008, 'Steel', nu=14, nv=6))
    # ---- exhaust (right, under the bumper)
    p1 = Vector((0.560, ybb + 0.025, 0.400))
    C.extend(ck.tube(Vector((0.560, -1.80, 0.405)), p1, 0.036, 0.030, 'Chrome', 'Trim', n=20, inner_depth=0.06))
    car.socket('Socket_Exhaust', p1)
    # ---- rear mud flaps
    R.extend(ck.box_between((0.800, -1.935, 0.300), (0.800, -1.935, 0.515), 0.230, 0.010, 'Plastic', up=(0, 1, 0)))
    return yR


def roof_rack(S_, C):
    """Tubular roof basket: perimeter rails top and bottom, uprights, cross bars, feet on the roof drip rails."""
    r, mat = 0.016, 'Steel'
    y0, y1, xw = -1.900, 0.640, 0.730
    z_lo, z_hi = 1.945, 2.020
    corner = [(-xw, y0), (xw, y0), (xw, y1), (-xw, y1)]
    loop = ck.fillet_poly(corner, 0.10, n=4)
    C.extend(ck.rod_path([Vector((p.x, p.y, z_lo)) for p in loop], r, mat, n=8, closed=True))
    loop2 = ck.fillet_poly([(-xw + 0.015, y0 + 0.015), (xw - 0.015, y0 + 0.015), (xw - 0.015, y1 - 0.015),
                            (-xw + 0.015, y1 - 0.015)], 0.09, n=4)
    C.extend(ck.rod_path([Vector((p.x, p.y, z_hi)) for p in loop2], r * 0.9, mat, n=8, closed=True))
    # uprights between the rails
    for sx in (-1, 1):
        for y in (-1.700, -1.250, -0.800, -0.350, 0.100, 0.500):
            C.extend(ck.rod((sx * (xw - 0.006), y, z_lo), (sx * (xw - 0.015), y, z_hi), r * 0.7, mat, n=6, caps=False))
    for x in (-0.40, 0.0, 0.40):
        for (y, d) in ((y0, 0.006), (y1, -0.006)):
            C.extend(ck.rod((x, y + d, z_lo), (x, y + d * 2.5, z_hi), r * 0.7, mat, n=6, caps=False))
    # cross bars (slats)
    for y in (-1.700, -1.400, -1.100, -0.800, -0.500, -0.200, 0.100, 0.400):
        C.extend(ck.rod((-xw + 0.010, y, z_lo), (xw - 0.010, y, z_lo), r * 0.75, mat, n=6, caps=False))
    # feet: from the drip rail at the roof edge up to the lower rail
    for sx in (-1, 1):
        for y in (-1.780, -1.000, -0.200, 0.520):
            p = BODY.point(y, 6.22, sx)
            foot = p + Vector((sx * 0.004, 0.0, 0.006))
            C.extend(ck.box_between(foot + Vector((0, -0.040, 0)), foot + Vector((0, 0.040, 0)), 0.040, 0.014, 'Plastic'))
            C.extend(ck.rod(foot + Vector((0, 0, 0.004)), (sx * (xw - 0.004), y, z_lo), 0.012, mat, n=8))


def underbody(S_, C):
    """Ladder frame rails, solid axles with diff housings (ground clearance 0.28), propshafts, transfer case, tank,
    exhaust pipe - visible from low angles under the high body."""
    for sx in (-1, 1):
        C.extend(ck.box_between((sx * 0.470, -2.000, 0.420), (sx * 0.470, 2.050, 0.420), 0.075, 0.090, 'Underbody'))
    for (ya, xd) in ((YF, 0.070), (YR, 0.0)):
        C.extend(ck.rod((-0.800, ya, WHEEL_R), (0.800, ya, WHEEL_R), 0.042, 'Underbody', n=8))
        C.extend(ck.ellipsoid((xd, ya, 0.407), (0.130, 0.140, 0.127), 'Steel', nu=12, nv=7))
        # coil springs / shock mounts (simple towers between axle and frame)
        for sx in (-1, 1):
            C.extend(ck.rod((sx * 0.560, ya - 0.10, WHEEL_R + 0.03), (sx * 0.540, ya - 0.10, 0.470), 0.050, 'Steel',
                            n=8))
    C.extend(ck.box_between((0.0, 0.080, 0.430), (0.0, 0.600, 0.430), 0.250, 0.090, 'Underbody'))
    C.extend(ck.rod((0.0, YR + 0.140, 0.415), (0.0, 0.080, 0.430), 0.030, 'Steel', n=8))
    C.extend(ck.rod((0.070, YF - 0.140, 0.415), (0.040, 0.600, 0.430), 0.030, 'Steel', n=8))
    C.extend(ck.box_between((-0.050, -1.050, 0.420), (-0.050, -0.450, 0.420), 0.600, 0.075, 'Underbody'))
    ex = [Vector((0.300, 0.700, 0.430)), Vector((0.360, 0.500, 0.412)), Vector((0.360, -0.900, 0.412)),
          Vector((0.560, -1.050, 0.412)), Vector((0.560, -1.250, 0.470)), Vector((0.560, -1.600, 0.470)),
          Vector((0.560, -1.800, 0.405))]
    C.extend(ck.rod_path(ck.cr_resample(ex, closed=False, sub=2), 0.028, 'Steel', n=8))
    C.extend(ck.ellipsoid((0.360, -0.350, 0.410), (0.075, 0.220, 0.050), 'Steel', nu=12, nv=6))


def body_details(car, S_):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre / one-sided parts (not mirrored)
    LH, LT, LB, LR, LBC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    SN = ck.Part()     # right-only snorkel
    front_details(car, S_, R, C, LH)
    hood_details(S_, R, C)
    side_details(car, S_, R, C)
    rear_details(car, S_, R, C, LT, LB, LR, LBC)
    roof_rack(S_, C)
    underbody(S_, C)
    snorkel(SN)
    # whip antenna on the left wing
    base = S_.snap('top', -0.850, 1.900)
    C.extend(ck.ellipsoid(base + Vector((0, 0, 0.008)), (0.016, 0.016, 0.014), 'Trim', nu=10, nv=6))
    C.extend(ck.rod(base + Vector((0, 0, 0.012)), base + Vector((-0.010, -0.180, 0.780)), 0.0028, 'Trim', n=6))
    if DEBUG:
        print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris(), 'snorkel =', SN.tris())
    car.add('Body', R, R.mirrored_x(), C, SN)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x())
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR, LR.mirrored_x())


# =====================================================================================================
# interior
# =====================================================================================================
def interior(car):
    I = ck.Part()
    xa = min(inner_x(y, z) for y in (0.66, 0.80, 0.95) for z in (0.85, 1.00, 1.15, 1.25)) - 0.012
    # ---- upright two-tone dashboard (profile (y, z) swept across X)
    dash = [(0.985, 1.150), (0.955, 1.205), (0.860, 1.238), (0.700, 1.248), (0.668, 1.240), (0.652, 1.222),
            (0.620, 1.095), (0.622, 0.985), (0.640, 0.905), (0.700, 0.845), (0.850, 0.805), (0.985, 0.830)]
    dmats = ['InteriorDark'] * 5 + ['InteriorDark', 'Interior', 'Interior'] + ['InteriorDark'] * 4
    xs = [-xa, -xa + 0.012, -0.55, -0.2, 0.0, 0.2, 0.55, xa - 0.012, xa]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < xa - 0.006 else 0.010
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # firewall plate facing the windscreen (closes the sliver between the dash top and the screen base)
    fw = ck.Part()
    ids = [fw.vert((sx * xa, 0.9875, z)) for (sx, z) in ((-1, 0.80), (1, 0.80), (1, 1.215), (-1, 1.215))]
    fw.face(ids, 'InteriorDark')
    if fw.face_normal(0).y < 0:
        fw.f[0] = tuple(reversed(fw.f[0]))
    I.extend(fw)
    # ---- driver binnacle over two big dials and a centre display
    hood = [(0.680, 1.238), (0.655, 1.290), (0.590, 1.302), (0.566, 1.292), (0.562, 1.276), (0.592, 1.280),
            (0.640, 1.262)]
    I.extend(ck.sweep_axis('x', [-0.640, -0.628, -0.212, -0.200],
                           [[(y, z - (0.01 if k in (0, 3) else 0)) for (y, z) in hood] for k in range(4)],
                           'InteriorDark'))
    fn = Vector((0.0, -0.127, 0.032)).normalized()          # upper dash face normal (face leans back 14 deg)
    face = [(0.640, 0.905), (0.622, 0.985), (0.620, 1.095), (0.652, 1.222)]

    def face_pt(x, z):
        for (ya, za), (yb, zb) in zip(face[:-1], face[1:]):
            if za <= z <= zb:
                return Vector((x, ya + (yb - ya) * (z - za) / (zb - za), z))
        return Vector((x, face[-1][0], z))
    for (x, z, r, nt) in ((-0.515, 1.163, 0.056, 11), (-0.325, 1.163, 0.056, 11)):
        c = face_pt(x, z) + fn * 0.003
        I.extend(ck.gauge(c, fn, r, n_ticks=nt))
    c = face_pt(-0.420, 1.165) + fn * 0.0025
    scr = ck.Part()
    up = fn.cross(Vector((1, 0, 0)))
    if up.z < 0:
        up = -up
    q = [scr.vert(c + Vector((1, 0, 0)) * u + up * v) for (u, v) in ((-0.034, -0.030), (0.034, -0.030),
                                                                      (0.034, 0.030), (-0.034, 0.030))]
    scr.face(q, 'Gauge')
    if scr.face_normal(0).dot(fn) < 0:
        scr.f[0] = tuple(reversed(scr.f[0]))
    I.extend(scr)
    # ---- centre stack: screen, vents, switch row
    cst = face_pt(0.0, 1.150) + fn * 0.002
    I.extend(ck.box_between(cst + Vector((-0.150, 0.004, 0)), cst + Vector((0.150, 0.004, 0)), 0.150, 0.012,
                            'InteriorDark', up=tuple(fn)))
    scr = ck.Part()
    c = cst + fn * 0.0075
    q = [scr.vert(c + Vector((1, 0, 0)) * u + up * v) for (u, v) in ((-0.110, -0.050), (0.110, -0.050),
                                                                      (0.110, 0.050), (-0.110, 0.050))]
    scr.face(q, 'Gauge')
    if scr.face_normal(0).dot(fn) < 0:
        scr.f[0] = tuple(reversed(scr.f[0]))
    I.extend(scr)
    for x in (-0.700, -0.140, 0.140, 0.700):
        p = face_pt(x, 1.050) + fn * 0.002
        I.extend(ck.box_between(p + Vector((-0.050, 0, 0)), p + Vector((0.050, 0, 0)), 0.045, 0.020, 'Trim',
                                up=tuple(fn)))
        for k in range(3):
            I.extend(ck.box_between(p + Vector((-0.045, 0, -0.012 + 0.012 * k)) + fn * 0.010,
                                    p + Vector((0.045, 0, -0.012 + 0.012 * k)) + fn * 0.010, 0.004, 0.004, 'Alu'))
    for k in range(5):
        p = Vector((-0.100 + 0.050 * k, 0.632, 0.990))
        I.extend(ck.box_between(p, p + Vector((0, -0.016, 0)), 0.022, 0.014, 'Gauge' if k == 2 else 'Trim'))
    # passenger grab handle across the dash
    gh = [Vector((0.300, 0.668, 1.240)), Vector((0.330, 0.612, 1.282)), Vector((0.650, 0.612, 1.282)),
          Vector((0.680, 0.668, 1.240))]
    I.extend(ck.rod_path(ck.cr_resample(gh, closed=False, sub=3), 0.013, 'InteriorDark', n=8))
    # ---- steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.26, 0.075, 0.085, 'InteriorDark'))
    # ---- centre console, gear selector, transfer-case lever, armrest
    cys = [0.640, 0.560, 0.380, 0.150, -0.050, -0.420]
    tops = [0.980, 0.900, 0.850, 0.840, 0.900, 0.905]
    profs = [[(-0.125, 0.500), (0.125, 0.500), (0.130, t - 0.03), (0.105, t), (-0.105, t), (-0.130, t - 0.03)]
             for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'InteriorDark', 'Interior',
                                             'InteriorDark', 'InteriorDark']))
    I.extend(ck.box_between((0.0, -0.060, 0.912), (0.0, -0.400, 0.912), 0.200, 0.030, 'Interior'))
    I.extend(ck.rod((-0.030, 0.300, 0.850), (-0.030, 0.270, 0.950), 0.009, 'Alu', n=8))
    I.extend(ck.ellipsoid((-0.030, 0.265, 0.965), (0.024, 0.030, 0.030), 'InteriorDark', nu=10, nv=8))
    I.extend(ck.rod((0.055, 0.180, 0.845), (0.060, 0.150, 0.925), 0.007, 'Alu', n=8))
    I.extend(ck.ellipsoid((0.060, 0.147, 0.935), (0.016, 0.016, 0.018), 'Trim', nu=8, nv=6))
    # ---- 2 front seats + 3-seat rear bench with headrests (5 seats)
    for x in (-0.420, 0.420):
        I.extend(ck.bucket_seat(x, SEAT_Y[0], SEAT_Y[1], SEAT_Z, width=0.540, recline=SEAT_RECLINE,
                                back_h=SEAT_BACK_H, bolster=0.070, headrest_w=0.27))
    I.extend(ck.bucket_seat(0.0, BENCH_Y[0], BENCH_Y[1], BENCH_Z, width=BENCH_W, recline=BENCH_RECLINE,
                            back_h=BENCH_BACK_H, bolster=0.050, bench=True))
    I.extend(ck.box_between((0.0, BENCH_Y[0] - 0.030, (BENCH_Z + 0.500) / 2), (0.0, BENCH_Y[1] + 0.040,
                                                                               (BENCH_Z + 0.500) / 2),
                            BENCH_W - 0.06, BENCH_Z - 0.500, 'InteriorDark'))
    Mb = Matrix.Translation((0.0, BENCH_Y[1] - 0.05, BENCH_Z + 0.05)) @ Matrix.Rotation(math.radians(BENCH_RECLINE),
                                                                                        4, 'X')
    for x in (-0.440, 0.0, 0.440):
        hc = Mb @ Vector((x, 0.050, BENCH_BACK_H + 0.100))
        I.extend(ck.ellipsoid(hc, (0.125, 0.048, 0.080), 'Interior', nu=12, nv=6, exp=3.0))
        for dx in (-0.055, 0.055):
            I.extend(ck.rod(Mb @ Vector((x + dx, 0.050, BENCH_BACK_H - 0.020)), hc + Vector((dx, 0, -0.050)), 0.006,
                            'Alu', n=6))
    # ---- door cards: armrests, pulls, speakers (4 doors)
    door = ck.Part()
    for (ya, yb) in ((0.800, 0.020), (-0.140, -0.860)):
        xd = min(inner_x(y, z) for y in (ya, (ya + yb) / 2, yb) for z in (0.80, 0.90)) - 0.004
        door.extend(ck.sweep_axis('y', [ya, ya - 0.020, yb + 0.020, yb],
                                  [(xd, 0.830), (xd - 0.070, 0.845), (xd - 0.075, 0.885), (xd - 0.060, 0.900),
                                   (xd, 0.905)], 'InteriorDark'))
        door.extend(ck.box_between((xd - 0.020, ya - 0.200, 0.980), (xd - 0.020, ya - 0.380, 0.980), 0.020, 0.025,
                                   'Alu'))
        door.extend(ck.disc((xd - 0.004, (ya + yb) / 2 + 0.10, 0.650), (-1, 0, 0), 0.070, 'Trim', n=16,
                            ring_mat='Alu', ring_w=0.006))
        door.extend(ck.box_between((xd - 0.006, ya - 0.10, 1.150), (xd - 0.006, yb + 0.10, 1.150), 0.012, 0.030,
                                   'Interior'))
    I.extend(door, door.mirrored_x())
    # ---- pedals, footrest, sun visors, rear-view mirror, cargo mat
    for x, w in ((-0.400, 0.090), (-0.280, 0.050)):
        I.extend(ck.box_between((x, 0.900, 0.570), (x, 0.860, 0.690), w, 0.014, 'Alu'))
    I.extend(ck.box_between((-0.620, 0.920, 0.520), (-0.620, 0.800, 0.600), 0.070, 0.012, 'Alu'))
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.120, 0.715, 1.775), (s * 0.540, 0.715, 1.775), 0.160, 0.018, 'Interior'))
    I.extend(ck.box_between((-0.120, 0.720, 1.705), (0.120, 0.720, 1.705), 0.030, 0.065, 'InteriorDark'))
    I.extend(ck.box_between((0.0, 0.740, 1.745), (0.0, 0.760, 1.800), 0.022, 0.022, 'InteriorDark'))
    zf = BODY.params_at(-1.500)['zb'] + D_IN
    I.extend(ck.box_between((0.0, -1.020, zf + 0.004), (0.0, -1.980, zf + 0.004), 1.180, 0.008, 'InteriorDark'))
    for x in (-0.50, 0.50):
        for y in (-1.10, -1.90):
            I.extend(ck.torus((x, y, zf + 0.012), (0, 0, 1), 0.020, 0.004, 'Alu', nu=10, nv=4))
    car.add('Interior', I)
    # ---- chunky 4-spoke steering wheel (separate object, origin at the hub)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.020, 0.024), segs=36, flat_bottom=False, hub_r=0.066, dish=0.035,
                                spoke_thick=0.018, spokes=((10.0, 0.050), (170.0, 0.050), (235.0, 0.042),
                                                           (305.0, 0.042)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=17, spokes=6, style='single', segs=36, rim_segs=36,
                  spoke_w=(0.078, 0.022), spoke_thick=0.022, spoke_dish=0.026, hub_r=0.072, nuts=6,
                  tyre='tall', blocks=dict(n=26, h=0.013),
                  disc_r=0.165, caliper_angle=150.0, caliper_span=48.0)


def build():
    paint = (0.147, 0.147, 0.042)             # #6B6B3A (sRGB) -> linear
    mats = ck.default_materials(paint=paint, paint_metallic=0.0, paint_rough=0.55, paint_coat=0.08,
                                rim=(0.022, 0.022, 0.024), rim_metallic=0.25, rim_rough=0.62,
                                caliper=(0.42, 0.035, 0.025),
                                interior=(0.200, 0.135, 0.080), interior_dark=(0.016, 0.016, 0.018))
    mats['Glass'] = dict(base=(0.008, 0.010, 0.011), roughness=0.03, alpha=0.35, double_sided=True)
    mats['Plastic'] = dict(base=(0.026, 0.026, 0.028), roughness=0.78)
    mats['Steel'] = dict(base=(0.060, 0.060, 0.064), metallic=0.65, roughness=0.48)
    mats['Alu'] = dict(base=(0.60, 0.61, 0.63), metallic=1.0, roughness=0.36)
    mats['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.25)
    mats['TowStrap'] = dict(base=(0.70, 0.05, 0.02), roughness=0.60)
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
        car.socket('Socket_CamHood', (0.0, 1.150, 1.420))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.170, 0.640))
    car.finalize()
    return car, shell


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
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.85)     # over the flares (mirrors / snorkel excluded)
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
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'off-road SUV (5-door, tall suspension)', 'drivetrain': 'AWD',
        'engine': 'front, turbo straight-six', 'doors': 5, 'seats': 5,
        'source_blend': 'Opus55ForzaUltracodeEffort.blend', 'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(mx.y - mn.y, 4),
        'length_shell': round(BODY.nose['y'] - BODY.tail['y'], 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(roof, 4), 'height_overall': round(all_mx.z, 4),
        'height_note': 'height = roof without the rack; height_overall includes the roof rack / antenna',
        'ground_clearance': round(mn.z, 4), 'body_floor_height': round(BODY.params_at(0.0)['zb'], 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'rim_diameter_in_front': 17, 'rim_diameter_in_rear': 17,
        'wheels': {k: G(v) for k, v in wheels.items()},
        'sockets': sockets,
        'steering_wheel': {'position': G(sw.matrix_world.translation),
                           'column_axis': G(sw.matrix_world.to_3x3() @ Vector((0, 1, 0))), 'radius': SW_R,
                           'spin_axis_local_godot': [0.0, 0.0, -1.0],
                           'note': 'Blender local +Y (column toward dash) becomes node-local -Z after the +Y-up glTF export'},
        'wheel_spin_axis_local_godot': [1.0, 0.0, 0.0],
        'eye_point': G(EYE),
        'spare_wheel_center': G(SPARE),
        'body_aabb': {'min': [round(mn.x, 4), round(mn.z, 4), round(-mx.y, 4)],
                      'max': [round(mx.x, 4), round(mx.z, 4), round(-mn.y, 4)]},
        'car_aabb': {'min': [round(all_mn.x, 4), round(all_mn.z, 4), round(-all_mx.y, 4)],
                     'max': [round(all_mx.x, 4), round(all_mx.z, 4), round(-all_mn.y, 4)]},
        'tris': tris,
        'materials': mats,
        'default_paint': {'hex': '#6B6B3A', 'linear_rgb': [0.147, 0.147, 0.042], 'finish': 'matte'},
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
    print('rear glass y range', YG0, YG1)
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
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.6, 6.6, 1.85), target=(0.0, 0.10, 0.92),
                                           lens=50.0, world_strength=0.85, sun_energy=3.6, exposure=-0.15,
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
