"""Aurelia Saloon - everyday mid-size 4-door sedan (three-box), FWD, front engine (car #2 of Sunward Roads).

Rebuilds Cars/Car_aurelia_sedan from scratch with tools/blender/car_kit.py, then (optionally) renders the
QA hero image, exports assets/imported/cars/aurelia_sedan.glb + .json and saves nothing by itself (the
caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\aurelia_sedan.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool).

Spec: L 4.75, W 1.82, H 1.45, wheelbase 2.78, track 1.57 / 1.56, wheel R 0.325 (16" rims), width 0.205.
Original design (no real brand / model): upright friendly face with a wide chrome-framed grille, horizontal
lamp clusters, chrome DLO surround, 4 doors, short boot deck, 10-spoke silver alloys, slate-blue metallic.
"""
import sys
import os
import math
import importlib

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender'))
import car_kit as ck  # noqa: E402
importlib.reload(ck)
from mathutils import Vector  # noqa: E402

CAR_ID = 'aurelia_sedan'
CAR_NAME = 'Aurelia Saloon'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.78
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.39)
TRACK_F, TRACK_R = 1.57, 1.56
WHEEL_R, WHEEL_W = 0.325, 0.205
ARCH_R, ARCH_Z = 0.356, 0.332                  # ~3 cm visible gap above the tyre
NOSE_Y, TAIL_Y = 2.34, -2.41                   # overall length 4.75

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs),
# K3 waist / widest (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr),
# K8 roof crown (zc). On the boot deck and bonnet K5..K8 lie on the panel surface.
Y_DECK = -1.76           # rear window base / boot deck crease
Y_RHEAD = -1.17          # rear roof header (soft)
Y_HEADER = 0.22          # windscreen header
Y_COWL = 1.02            # windscreen base / bonnet rear edge
S = [
    # ---- boot: tight deck edge + rounded plan corners, closed by a nearly flat tail cap
    dict(y=-2.385, zb=0.300, wb=0.46, zs=0.338, ws=0.758, zw=0.600, ww=0.815, zh=0.928, wh=0.780,
         zg=0.992, wg=0.700, zr=1.013, wr=0.540, zc=1.022, ks={6: 0.15}),
    dict(y=-2.365, zb=0.285, wb=0.49, zs=0.325, ws=0.782, zw=0.598, ww=0.840, zh=0.944, wh=0.803,
         zg=1.010, wg=0.722, zr=1.032, wr=0.560, zc=1.042),
    dict(y=-2.320, zb=0.265, wb=0.52, zs=0.310, ws=0.812, zw=0.595, ww=0.864, zh=0.958, wh=0.828,
         zg=1.024, wg=0.742, zr=1.046, wr=0.575, zc=1.056),
    dict(y=-2.200, zb=0.235, wb=0.56, zs=0.290, ws=0.845, zw=0.592, ww=0.889, zh=0.966, wh=0.851,
         zg=1.030, wg=0.762, zr=1.053, wr=0.590, zc=1.063, ks={6: 0.3}),
    dict(y=-1.990, zb=0.200, wb=0.60, zs=0.275, ws=0.862, zw=0.588, ww=0.904, zh=0.968, wh=0.862,
         zg=1.032, wg=0.776, zr=1.057, wr=0.604, zc=1.068),
    # ---- deck / rear window crease
    dict(y=Y_DECK, zb=0.170, wb=0.62, zs=0.268, ws=0.870, zw=0.582, ww=0.910, zh=0.966, wh=0.868,
         zg=1.030, wg=0.784, zr=1.060, wr=0.615, zc=1.072, sharp=dict(zc=1.0, zr=0.7, wr=0.5), ks={6: 0.4}),
    # ---- rear window (C-pillar sails on band 5)
    dict(y=-1.470, zb=0.160, zs=0.262, ws=0.872, zw=0.575, ww=0.910, zh=0.945, wh=0.873,
         zg=1.006, wg=0.796, zr=1.240, wr=0.630, zc=1.268),
    dict(y=Y_RHEAD, zb=0.152, wb=0.62, zs=0.258, ws=0.872, zw=0.568, ww=0.908, zh=0.935, wh=0.875,
         zg=0.992, wg=0.806, zr=1.350, wr=0.645, zc=1.404),
    # ---- roof / cabin
    dict(y=-0.700, zb=0.150, zs=0.255, ws=0.870, zw=0.562, ww=0.906, zh=0.926, wh=0.875, zg=0.978,
         wg=0.815, zr=1.382, wr=0.658, zc=1.440),
    dict(y=-0.250, zw=0.556, ww=0.905, zh=0.921, wh=0.875, zg=0.970, wg=0.818, zr=1.390, wr=0.664, zc=1.450),
    dict(y=Y_HEADER, zw=0.553, zh=0.920, wh=0.874, zg=0.964, wg=0.816, zr=1.370, wr=0.664, zc=1.432,
         sharp=dict(zc=0.5, zr=0.5, wr=0.3)),
    dict(y=0.620, zw=0.550, ww=0.905, zh=0.923, wh=0.873, zg=0.960, wg=0.812, zr=1.180, wr=0.702, zc=1.225),
    dict(y=Y_COWL, zw=0.546, ww=0.905, zh=0.930, wh=0.872, zg=0.956, wg=0.806, zr=0.972, wr=0.746,
         zc=0.985, sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- bonnet / front wings
    dict(y=YF, zb=0.170, wb=0.60, zs=0.272, ws=0.865, zw=0.542, ww=0.908, zh=0.918, wh=0.872,
         zg=0.940, wg=0.790, zr=0.955, wr=0.600, zc=0.968, bulge=0.008, ks={7: 0.45}),
    dict(y=1.850, zb=0.200, wb=0.58, zs=0.282, ws=0.848, zw=0.536, ww=0.894, zh=0.880, wh=0.862,
         zg=0.902, wg=0.772, zr=0.918, wr=0.552, zc=0.932, bulge=0.006),
    dict(y=2.120, zb=0.228, wb=0.55, zs=0.290, ws=0.818, zw=0.530, ww=0.874, zh=0.850, wh=0.843,
         zg=0.868, wg=0.752, zr=0.882, wr=0.520, zc=0.894, bulge=0.004),
    dict(y=2.220, zb=0.240, wb=0.53, zs=0.292, ws=0.792, zw=0.524, ww=0.851, zh=0.838, wh=0.819,
         zg=0.855, wg=0.730, zr=0.869, wr=0.500, zc=0.880, bulge=0.002),
    dict(y=2.275, zb=0.250, wb=0.50, zs=0.296, ws=0.764, zw=0.518, ww=0.822, zh=0.825, wh=0.789,
         zg=0.842, wg=0.702, zr=0.858, wr=0.480, zc=0.868, bulge=0.0),
    dict(y=2.300, zb=0.262, wb=0.47, zs=0.302, ws=0.736, zw=0.514, ww=0.792, zh=0.808, wh=0.759,
         zg=0.825, wg=0.674, zr=0.838, wr=0.460, zc=0.846),
]

# C-pillar: the side-glass rear edge leans forward going up (belt at y=-1.37, roof rail at y=-1.11)
WARP_Y = -1.24
WARP = dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.37, -1.11), margin=0.28)
RW_TOP = -1.27           # base y of the rear-window top edge (lands at ~-1.15 in band 7 via the warp)
Y_MIRROR = 0.82          # front door glass front edge / mirror sail
Y_BPIL = (-0.165, -0.075)
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),       # windscreen
    dict(bands=(5, 5), y=(WARP_Y, Y_MIRROR), role='glass'),       # door glass (front + rear)
    dict(bands=(5, 5), y=(Y_MIRROR, Y_COWL), role='trim'),        # mirror sail (black)
    dict(bands=(5, 5), y=Y_BPIL, role='trim'),                    # B-pillar (black)
    dict(bands=(7, 7), y=(Y_DECK + 0.035, RW_TOP), role='glass'), # rear window
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.055), role='trim'),  # scuttle / cowl panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[3, 3, 5, 5, 2, 6, 2, 7],
    key_sharp=(0, 0.7, 0.5, 0.6, 0.85, 0.38, 0.42, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.52, tilt=4.0, k_edge=2.4, k_face=2.8, rings=8),
    tail=dict(y=TAIL_Y, z=0.62, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8),
    step=0.055,
    rail=0.05,
    warps=[WARP],
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.53), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.585)]
INNER = dict(y=(-1.800, 1.060), d=0.035,
             tubs=[(YR, ARCH_Z, ARCH_R + 0.03, 0.57), (YF, ARCH_Z, ARCH_R + 0.03, 0.51)])


EYE = Vector((-0.375, -0.20, 1.180))         # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.375, 0.27, 0.880))          # steering wheel hub
COLUMN_TILT = 23.0                           # deg, column descends toward the dash
SW_R = 0.188                                 # steering wheel radius


def isolate(on=True):
    """Hide the other cars (view-layer exclude only, no datablock change) while looking / rendering."""
    import bpy
    lc_cars = None
    root = bpy.context.view_layer.layer_collection.children.get('SUNWARD_GODOT')
    if root is not None:
        lc_cars = root.children.get('Cars')
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
    """Wrap-around lamp: housing patch + inset inner patch. Returns (housing, inner, frame)."""
    pts = snap_pts(S, spec)
    housing, frame = S.patch3d(pts, offset=house_off, depth=0.006, res=res, mat=house_mat, sub=4)
    O, U, V, D = frame
    pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in pts]
    inner2d = ck.offset_poly(ck.cr_resample(pts2d, True, 4), -inset)
    inner = S.patch(inner2d, frame, offset=inner_off, depth=0.004, res=res * 0.9, mat=inner_mat, smooth=False)
    return housing, inner, frame


def dlo_loop():
    """Closed 3D outline just outside the side window opening (chrome DLO surround)."""
    pts = []
    n = 44
    y_c0, y_c1 = WARP['y_t']
    for k in range(n + 1):                                   # belt line, front -> rear
        y = ck.lerp(1.000, y_c0 - 0.012, k / n)
        pts.append(BODY.point(y, 4.93))
    for k in range(1, 9):                                    # C-pillar edge, belt -> roof rail
        t = 4.93 + (6.12 - 4.93) * k / 8
        u = ck.clamp(t - 5.0, 0.0, 1.0)
        y = ck.lerp(y_c0, y_c1, u) - 0.012
        pts.append(BODY.point(y, t))
    m = 60
    for k in range(1, m + 1):                                # roof rail + A-pillar, rear -> front
        y = ck.lerp(y_c1 - 0.012, 1.000, k / m)
        pts.append(BODY.point(y, 6.12))
    return pts


def body_details(car, S):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LTC, LBC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()

    # ---------------- front: wide chrome-framed grille with horizontal chrome bars
    grille = ck.fillet_poly([(-0.395, 0.556), (0.395, 0.556), (0.438, 0.690), (0.442, 0.778), (-0.442, 0.778),
                             (-0.438, 0.690)], [0.035, 0.035, 0.0, 0.022, 0.022, 0.0], n=5)
    C.extend(S.patch(grille, 'front', offset=0.002, depth=0.005, res=0.035, mat='Grille', smooth=False))
    C.extend(S.rim(grille, 'front', width=0.022, offset=0.010, depth=0.006, mat='Chrome', smooth=False))
    for z, w in ((0.612, 0.805), (0.667, 0.835), (0.722, 0.848)):
        bar = ck.rrect_pts(0.0, z, w, 0.013, 0.0055, n=2)
        C.extend(S.patch(bar, 'front', offset=0.0068, depth=0.006, res=0.0, mat='Chrome', smooth=False))
    # bonnet front shut line (across the top of the face) and bumper-to-wing split lines
    C.extend(S.line([(-0.74, 0.838), (-0.40, 0.835), (0.0, 0.834), (0.40, 0.835), (0.74, 0.838)], 'front'))
    R.extend(S.line([(2.20, 0.688), (2.06, 0.668), (1.90, 0.640), (1.76, 0.610), (1.67, 0.597)], 'right'))
    hood_edge = [BODY.point(y, 5.0) for y in (1.045, 1.30, 1.60, 1.90, 2.10, 2.22, 2.27)]
    R.extend(S.line3d(hood_edge))
    # front number-plate recess
    plate_f = ck.rrect_pts(0.0, 0.462, 0.52, 0.112, 0.012, n=2)
    C.extend(S.patch(plate_f, 'front', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    C.extend(S.rim(plate_f, 'front', width=0.011, offset=0.0055, depth=0.005, mat='Trim', smooth=False))
    # lower intake + bar, lower lip
    intake = [(-0.46, 0.302), (0.46, 0.302), (0.53, 0.322), (0.505, 0.384), (-0.505, 0.384), (-0.53, 0.322)]
    C.extend(S.patch(intake, 'front', offset=0.0015, depth=0.004, res=0.035, mat='Grille', corners=(0, 1, 2, 3, 4, 5), sub=3))
    C.extend(S.rim(intake, 'front', width=0.012, offset=0.006, depth=0.005, mat='Trim', corners=(0, 1, 2, 3, 4, 5), sub=3))
    C.extend(S.patch(ck.rrect_pts(0.0, 0.343, 0.92, 0.012, 0.005, n=2), 'front', offset=0.005, depth=0.004,
                     res=0.0, mat='Trim', smooth=False))
    lip = ck.fillet_poly([(-0.74, 0.268), (0.74, 0.268), (0.775, 0.282), (0.755, 0.293), (-0.755, 0.293),
                          (-0.775, 0.282)], 0.006, n=3)
    C.extend(S.patch(lip, 'front', offset=0.002, depth=0.005, res=0.03, mat='Trim', smooth=False))
    # fog lamps (unlit reflectors) in black pods
    fog = ck.rrect_pts(0.655, 0.358, 0.125, 0.066, 0.030, n=3)
    R.extend(S.patch(fog, 'front', offset=0.003, depth=0.005, res=0.0, mat='Trim', smooth=False))
    loc, nor = S.hit(S.frame('front'), 0.655, 0.358)
    R.extend(ck.disc(loc + nor * 0.0045, nor, 0.022, 'Chrome', n=16, ring_mat='Trim', ring_w=0.004))

    # ---------------- headlamps: horizontal clusters wrapping onto the wings
    hl_spec = [('front', 0.448, 0.672), ('front', 0.444, 0.786), ('front', 0.60, 0.806), ('front', 0.735, 0.808),
               ('right', 2.215, 0.812), ('right', 2.105, 0.800), ('right', 2.090, 0.752), ('right', 2.200, 0.703),
               ('front', 0.745, 0.668), ('front', 0.60, 0.662)]
    housing, inner, frame = lamp(S, hl_spec, 'Trim', 'Chrome', inset=0.007)
    R.extend(housing, inner)
    proj_centers = []
    for (x, z) in ((0.522, 0.738), (0.648, 0.744)):
        loc, nor = S.hit(S.frame('front'), x, z)
        c = loc + nor * 0.0068
        LH.extend(ck.disc(c, nor, 0.032, 'HeadlightLens', n=20))
        R.extend(ck.disc(c - nor * 0.0012, nor, 0.032, 'Chrome', n=20, ring_mat='Trim', ring_w=0.005))
        proj_centers.append(c)
    drl = snap_pts(S, [('front', 0.47, 0.688), ('front', 0.60, 0.682), ('front', 0.735, 0.686),
                       ('right', 2.20, 0.718), ('right', 2.12, 0.748)])
    LH.extend(S.line3d(drl, width=0.010, offset=0.0062, mat='HeadlightLens'))
    hc = (proj_centers[0] + proj_centers[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))

    # ---------------- side: DLO chrome, shut lines, handles, mirror, sill trim, fuel flap
    R.extend(S.line3d(dlo_loop(), width=0.012, offset=0.0016, mat='Chrome', step=0.03, closed=True))
    R.extend(S.line([(0.925, 0.285), (0.928, 0.60), (0.950, 0.84), (0.990, 0.945)], 'right'))      # front door, front
    R.extend(S.line([(-0.120, 0.282), (-0.120, 0.60), (-0.120, 0.968)], 'right'))                    # B-pillar shut
    R.extend(S.line([(-1.364, 0.990), (-1.330, 0.870), (-1.270, 0.760), (-1.190, 0.680), (-1.085, 0.590),
                     (-1.015, 0.470), (-0.992, 0.335), (-0.990, 0.282)], 'right'))                    # rear door, rear
    R.extend(S.line([(-2.330, 0.702), (-2.200, 0.700), (-1.950, 0.662), (-1.800, 0.622), (-1.665, 0.596)], 'right'))
    for yc in (0.070, -1.170):                                                                      # door handles
        R.extend(S.patch(ck.rrect_pts(yc, 0.884, 0.175, 0.046, 0.020, n=3), 'right', offset=0.0015, depth=0.004,
                         res=0.0, mat='Trim', smooth=False))
        R.extend(S.patch(ck.rrect_pts(yc, 0.888, 0.150, 0.026, 0.012, n=3), 'right', offset=0.0072, depth=0.007,
                         res=0.0, mat='Chrome', smooth=False))
    # mirror: body-colour cap, black base + arm, chrome-look glass facing back
    mc = Vector((0.978, 0.880, 1.046))
    ry = 0.064

    def flat_back(p):
        if p.y < -ry * 0.25:
            p.y = -ry * 0.25 - (p.y + ry * 0.25) * 0.08
        return p
    mirror = ck.ellipsoid(mc, (0.105, ry, 0.058), 'Paint', nu=20, nv=10, exp=3.0, deform=flat_back)
    for fi in range(len(mirror.f)):
        if mirror.face_center(fi).z < mc.z - 0.030:
            mirror.m[fi] = 'Trim'
    R.extend(mirror)
    glass_pts = ck.superellipse_pts(0.0, 0.0, 0.085, 0.048, e=2.6, n=20)
    mg = ck.Part()
    cen = mg.vert(mc + Vector((0, -ry * 0.25 - 0.003, 0)))
    ring = [mg.vert(mc + Vector((p.x, -ry * 0.25 - 0.003, p.y))) for p in glass_pts]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    R.extend(ck.box_between((0.800, 0.905, 0.985), (0.900, 0.890, 1.024), 0.050, 0.024, 'Trim'))
    # black sill extension between the arches
    ys = [-0.985, -0.965, -0.90, -0.40, 0.0, 0.40, 0.90, 0.975, 0.995]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        k = 0.35 if abs(abs(y) - 0.99) < 0.012 else (0.8 if abs(abs(y) - 0.97) < 0.012 else 1.0)
        profs.append([(ws - 0.030, zs + 0.036), (ws + 0.004 * k, zs + 0.034), (ws + 0.013 * k, zs + 0.004),
                      (ws + 0.011 * k, zs - 0.046 * k), (ws - 0.004, zs - 0.058 * k), (ws - 0.030, zs - 0.048)])
    R.extend(ck.sweep_axis('y', ys, profs, 'Trim'))
    fuel = ck.rrect_pts(-1.640, 0.850, 0.115, 0.105, 0.028, n=3)
    C.extend(S.line(fuel, 'right', closed=True, smooth=False))                                       # right side only

    # ---------------- windscreen wipers + scuttle
    for (x0, x1, y0, y1, px) in ((-0.66, -0.08, 0.978, 0.948, -0.31), (-0.03, 0.52, 0.970, 0.942, 0.23)):
        a0 = S.snap('top', x0, y0) + Vector((0, 0, 0.013))
        a1 = S.snap('top', x1, y1) + Vector((0, 0, 0.013))
        C.extend(ck.box_between(a0, a1, 0.016, 0.011, 'Trim'))
        pivot = S.snap('top', px, 1.045) + Vector((0, 0, 0.012))
        mid = (a0 + a1) / 2 + Vector((0, 0, 0.008))
        C.extend(ck.box_between(pivot, mid, 0.012, 0.008, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.016, 0.016, 0.010), 'Trim', nu=10, nv=6))

    # ---------------- roof: antenna, third brake light at the rear-window top
    C.extend(ck.ellipsoid((0.0, -0.93, S.snap('top', 0.0, -0.93).z + 0.010), (0.020, 0.070, 0.036), 'Trim', nu=12, nv=8,
                          deform=lambda p: Vector((p.x * (1.0 - 0.6 * max(0.0, p.z) / 0.036), p.y - 0.6 * max(0.0, p.z), max(p.z, -0.004)))))
    LBC.extend(S.patch(ck.rrect_pts(0.0, -1.118, 0.30, 0.020, 0.008, n=2), 'top', offset=0.003, depth=0.004,
                       res=0.0, mat='BrakeLens', smooth=False))

    # ---------------- rear: tail lamps, boot lid, garnish, plate, bumper, valance, exhaust
    tl_spec = [('rear', 0.470, 0.800), ('rear', 0.470, 0.946), ('rear', 0.62, 0.954), ('rear', 0.742, 0.952),
               ('right', -2.300, 0.952), ('right', -2.222, 0.944), ('right', -2.205, 0.890), ('right', -2.240, 0.836),
               ('right', -2.310, 0.802), ('rear', 0.730, 0.796), ('rear', 0.600, 0.796)]
    housing, inner, frame = lamp(S, tl_spec, 'Trim', 'TaillightLens', inset=0.0055, inner_off=0.004, res=0.018)
    R.extend(housing)
    LT.extend(inner)
    brake = snap_pts(S, [('rear', 0.492, 0.922), ('rear', 0.62, 0.929), ('rear', 0.735, 0.928), ('right', -2.300, 0.926),
                         ('right', -2.232, 0.918)])
    LB.extend(S.line3d(brake, width=0.016, offset=0.0058, mat='BrakeLens'))
    for zz in (0.872, 0.840):                                       # dark louvre lines across the lens
        lv = snap_pts(S, [('rear', 0.488, zz), ('rear', 0.62, zz + 0.004), ('rear', 0.735, zz + 0.002),
                          ('right', -2.300, zz), ('right', -2.226, zz - 0.004)])
        R.extend(S.line3d(lv, width=0.005, offset=0.0052, mat='Trim'))
    LR.extend(S.patch(ck.rrect_pts(0.545, 0.8195, 0.075, 0.022, 0.007, n=2), 'rear', offset=0.0058, depth=0.003,
                      res=0.0, mat='ReverseLens', smooth=False))
    # boot lid shut line (rear face, right half) + deck sides + deck front edge
    R.extend(S.line([(0.0, 0.700), (0.40, 0.700), (0.452, 0.712), (0.456, 0.80), (0.458, 0.944), (0.480, 0.962),
                     (0.70, 0.963), (0.728, 0.975), (0.733, 1.020)], 'rear'))
    R.extend(S.line3d([BODY.point(y, 5.0) for y in (-1.80, -2.00, -2.20, -2.30, -2.345)]))
    C.extend(S.line([(-0.70, -1.795), (-0.35, -1.797), (0.0, -1.798), (0.35, -1.797), (0.70, -1.795)], 'top'))
    # rear bumper top line (outside the lid) and lower valance
    R.extend(S.line([(0.456, 0.700), (0.62, 0.700), (0.76, 0.702), (0.80, 0.703)], 'rear'))
    C.extend(S.patch(ck.rrect_pts(0.0, 0.893, 0.86, 0.022, 0.009, n=2), 'rear', offset=0.0045, depth=0.004,
                     res=0.0, mat='Chrome', smooth=False))                                        # chrome garnish
    plate = ck.rrect_pts(0.0, 0.784, 0.52, 0.112, 0.012, n=2)
    C.extend(S.patch(plate, 'rear', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    C.extend(S.rim(plate, 'rear', width=0.011, offset=0.0055, depth=0.005, mat='Trim', smooth=False))
    valance = ck.fillet_poly([(-0.70, 0.302), (0.70, 0.302), (0.765, 0.335), (0.745, 0.398), (-0.745, 0.398),
                              (-0.765, 0.335)], 0.02, n=4)
    C.extend(S.patch(valance, 'rear', offset=0.002, depth=0.005, res=0.04, mat='Trim', smooth=False))
    LTC.extend(S.patch(ck.rrect_pts(0.69, 0.452, 0.10, 0.024, 0.010, n=2), 'rear', offset=0.003, depth=0.004,
                       res=0.0, mat='TaillightLens', smooth=False))                               # reflectors
    LTC.extend(S.patch(ck.rrect_pts(-0.69, 0.452, 0.10, 0.024, 0.010, n=2), 'rear', offset=0.003, depth=0.004,
                       res=0.0, mat='TaillightLens', smooth=False))
    # single exhaust (left), tail pipe + silencer under the boot floor
    tip0 = Vector((-0.50, -2.235, 0.258))
    tip1 = Vector((-0.50, -2.418, 0.258))
    C.extend(ck.tube(tip0, tip1, 0.034, 0.028, 'Chrome', 'Trim', n=22, inner_depth=0.06))
    C.extend(ck.tube(Vector((-0.42, -1.86, 0.196)), tip0 + Vector((0, 0.02, 0)), 0.024, 0.020, 'Underbody', 'Underbody', n=12))
    C.extend(ck.ellipsoid((-0.30, -1.98, 0.205), (0.20, 0.13, 0.048), 'Underbody', nu=16, nv=8, exp=2.6))
    car.socket('Socket_Exhaust', tip1)

    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x(), LTC)
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR, LR.mirrored_x())


def interior(car):
    I = ck.Part()
    # ---- dashboard (profile in (y, z), swept across X); wood-look strip across the face
    dash = [(1.02, 0.925), (0.82, 0.962), (0.64, 0.972), (0.555, 0.960), (0.522, 0.930), (0.515, 0.895),
            (0.512, 0.862), (0.52, 0.80), (0.56, 0.70), (0.64, 0.60), (0.72, 0.52), (0.84, 0.48), (0.94, 0.62),
            (1.02, 0.72)]
    dmats = ['InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorDark', 'Interior', 'InteriorWood',
             'InteriorDark', 'Interior', 'Interior', 'Interior', 'InteriorDark', 'InteriorDark', 'InteriorDark',
             'InteriorDark']
    xs = [-0.755, -0.74, -0.55, -0.2, 0.0, 0.2, 0.55, 0.74, 0.755]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < 0.75 else 0.01
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # instrument cluster on the dash face, seen through the upper half of the steering wheel:
    # dark cluster panel (interrupts the wood strip), two dials, short visor above
    xb = [HUB.x - 0.20, HUB.x - 0.19, HUB.x + 0.19, HUB.x + 0.20]
    I.extend(ck.box_between((HUB.x - 0.19, 0.511, 0.882), (HUB.x + 0.19, 0.511, 0.882), 0.006, 0.124, 'InteriorDark',
                            up=(0, 0, 1)))
    visor = [(0.524, 0.948), (0.476, 0.963), (0.438, 0.957), (0.441, 0.945), (0.500, 0.939)]
    I.extend(ck.sweep_axis('x', xb, [[(y + (0.006 if k in (0, 3) else 0.0), z - (0.006 if k in (0, 3) else 0.0))
                                      for (y, z) in visor] for k in range(4)], 'InteriorDark'))
    for (dx, nt) in ((-0.080, 9), (0.080, 11)):
        c = Vector((HUB.x + dx, 0.505, 0.878))
        I.extend(ck.gauge(c, EYE - c, 0.052, n_ticks=nt))
    # centre stack: screen + climate panel, vents
    I.extend(ck.box_between((0.0, 0.545, 0.80), (0.0, 0.528, 0.955), 0.24, 0.016, 'InteriorDark', up=(0, 1, 0)))
    scr = ck.Part()
    for (x0, x1, z0, z1, m) in ((-0.095, 0.095, 0.878, 0.942, 'InteriorDark'), (-0.080, 0.030, 0.925, 0.931, 'Gauge'),
                                (-0.080, -0.010, 0.900, 0.904, 'Gauge'), (0.040, 0.080, 0.890, 0.930, 'Gauge'),
                                (-0.09, -0.01, 0.825, 0.845, 'InteriorDark'), (0.01, 0.09, 0.825, 0.845, 'InteriorDark'),
                                (-0.07, -0.03, 0.833, 0.837, 'Gauge'), (0.03, 0.07, 0.833, 0.837, 'Gauge')):
        off = 0.0015 if m == 'InteriorDark' else 0.0025
        yb = lambda z: 0.5265 - 0.11 * (z - 0.80) - off
        q = [scr.vert(Vector((x, yb(z), z))) for (x, z) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
        scr.face(q, m)
    scr.orient(0, ref=Vector((0, 0.7, 0.9)))
    I.extend(scr)
    for x in (-0.64, -0.12, 0.12, 0.64):
        I.extend(ck.box_between((x - 0.06, 0.508, 0.958), (x + 0.06, 0.508, 0.958), 0.03, 0.040, 'InteriorDark'))
    # steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.30, 0.075, 0.085, 'InteriorDark'))
    # centre console (armrest box at the back), automatic selector, wood inlay
    cys = [0.60, 0.50, 0.30, 0.05, -0.12, -0.20, -0.42]
    tops = [0.66, 0.58, 0.52, 0.52, 0.53, 0.60, 0.60]
    profs = [[(-0.10, 0.18), (0.10, 0.18), (0.105, t - 0.03), (0.085, t), (-0.085, t), (-0.105, t - 0.03)] for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'InteriorDark', 'Interior',
                                             'InteriorDark']))
    I.extend(ck.box_between((0.0, 0.40, 0.522), (0.0, 0.08, 0.522), 0.12, 0.008, 'InteriorWood'))
    I.extend(ck.box_between((0.0, 0.20, 0.52), (0.0, 0.18, 0.60), 0.022, 0.022, 'InteriorDark'))
    I.extend(ck.ellipsoid((0.0, 0.178, 0.615), (0.024, 0.034, 0.030), 'Interior', nu=12, nv=8))
    # seats: two front seats + rear bench with three headrests
    for x in (-0.375, 0.375):
        I.extend(ck.bucket_seat(x, 0.25, -0.24, 0.30, width=0.52, recline=17.0, back_h=0.84, bolster=0.045))
    I.extend(ck.bucket_seat(0.0, -0.64, -1.10, 0.29, width=1.12, recline=25.0, back_h=0.60, bolster=0.05, bench=True))
    rec = math.radians(25.0)
    for x in (-0.38, 0.0, 0.38):
        top = Vector((x, -1.15 - 0.60 * math.sin(rec), 0.34 + 0.60 * math.cos(rec)))
        I.extend(ck.ellipsoid(top + Vector((0, -0.01, 0.075)), (0.115 if x else 0.10, 0.050, 0.075), 'Interior', nu=12, nv=8, exp=3.0))
        I.extend(ck.box_between(top + Vector((0, 0, -0.02)), top + Vector((0, -0.01, 0.03)), 0.06, 0.012, 'InteriorDark'))
    # parcel shelf
    I.extend(ck.box_between((0.0, -1.43, 1.000), (0.0, -1.77, 1.000), 1.38, 0.018, 'InteriorDark'))
    # door cards: armrests, wood strips, speakers (front + rear doors), mirrored
    door = ck.Part()
    for (y0, y1) in ((0.58, -0.08), (-0.20, -0.98)):
        ays = [y0, y0 - 0.03, y1 + 0.04, y1]
        door.extend(ck.sweep_axis('y', ays, [(0.765, 0.650), (0.790, 0.610), (0.852, 0.606), (0.852, 0.676),
                                             (0.773, 0.676)], 'InteriorDark'))
        door.extend(ck.box_between((0.842, y0 - 0.04, 0.800), (0.842, y1 + 0.05, 0.800), 0.010, 0.030, 'InteriorWood',
                                   up=(1, 0, 0)))
        door.extend(ck.disc((0.842, (y0 + y1) / 2 + 0.06, 0.40), (-1, 0, 0), 0.060, 'InteriorDark', n=16))
    door.extend(ck.box_between((0.835, 0.50, 0.81), (0.835, 0.40, 0.81), 0.03, 0.022, 'Interior'))
    I.extend(door, door.mirrored_x())
    # pedals
    for x, w in ((-0.47, 0.06), (-0.36, 0.09)):
        I.extend(ck.box_between((x, 0.82, 0.22), (x, 0.78, 0.33), w, 0.012, 'InteriorDark'))
    # sun visors + rear-view mirror
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.15, 0.10, 1.368), (s * 0.50, 0.10, 1.368), 0.17, 0.016, 'Interior'))
    I.extend(ck.box_between((-0.12, 0.24, 1.320), (0.12, 0.24, 1.320), 0.03, 0.065, 'InteriorDark'))
    I.extend(ck.box_between((0.0, 0.255, 1.345), (0.0, 0.265, 1.400), 0.02, 0.02, 'InteriorDark'))
    car.add('Interior', I)
    # steering wheel (separate object, origin at the hub, local +Y = column toward the dash): round, 4 spokes
    car.add('SteeringWheel', ck.steering_wheel_part(R=SW_R, flat_bottom=False, hub_r=0.062,
                                                    spokes=((-12.0, 0.046), (192.0, 0.046), (250.0, 0.034), (290.0, 0.034))),
            location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=16, spokes=10, style='single', segs=48,
                  spoke_w=(0.032, 0.007), spoke_thick=0.020, spoke_dish=0.030, hub_r=0.066, nuts=5,
                  disc_r=0.150, caliper_angle=150.0, caliper_span=40.0,
                  rear=dict(disc_r=0.140, caliper_span=36.0))


def build():
    paint = (0.0467, 0.1022, 0.2159)          # #3D5A80 slate blue (linear)
    mats = ck.default_materials(paint=paint, paint_metallic=0.55, paint_rough=0.30, paint_coat=0.8,
                                rim=(0.62, 0.63, 0.65), rim_metallic=0.9, rim_rough=0.26,
                                caliper=(0.26, 0.26, 0.27),
                                interior=(0.105, 0.098, 0.092), interior_dark=(0.020, 0.020, 0.022))
    mats['Glass'] = dict(base=(0.012, 0.018, 0.024), roughness=0.03, alpha=0.34, double_sided=True)
    mats['InteriorWood'] = dict(base=(0.105, 0.042, 0.016), roughness=0.32, coat=0.7, coat_rough=0.05)
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
        car.socket('Socket_CamHood', (0.0, 1.12, 1.085))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.04, 0.50))
    car.finalize()
    car.info['lip_sharp_edges'] = sharpen_arch_lips(car)
    return car, shell


def sharpen_arch_lips(car, min_deg=8.0):
    """Mark the edge where the side panel meets the bevelled arch lip as sharp, so the lip's normals do not
    darken the panel above the wheel (visible as a dark band in the clear coat)."""
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
                        e.use_edge_sharp = True       # panel <-> lip boundary only (lip itself stays smooth)
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


def measure(car, tris):
    G = ck.to_godot
    SHELL_YS = car.shell.ys
    body = car.objects['Body']
    M = body.matrix_world
    bv = [M @ v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in bv), min(v.y for v in bv), min(v.z for v in bv)))
    mx = Vector((max(v.x for v in bv), max(v.y for v in bv), max(v.z for v in bv)))
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.95)        # mirrors excluded
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
    mats = sorted({m.name for o in car.objects.values() if o.type == 'MESH' for m in o.data.materials})
    return {
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'mid-size sedan', 'drivetrain': 'FWD', 'engine': 'front',
        'doors': 4, 'seats': 5, 'source_blend': 'Opus55ForzaUltracodeEffort.blend', 'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(BODY.nose['y'] - BODY.tail['y'], 4), 'length_overall': round(mx.y - mn.y, 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(max(BODY.params_at(y)['zc'] for y in SHELL_YS), 4), 'height_overall': round(all_mx.z, 4),
        'ground_clearance': round(BODY.params_at(0.0)['zb'], 4), 'ground_clearance_min': round(mn.z, 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'rim_diameter_in': 16,
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
        'default_paint': {'hex': '#3D5A80', 'linear_rgb': [0.0467, 0.1022, 0.2159], 'finish': 'metallic'},
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
        print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W), 'interior verts in wheel wells:', interior_in_wells(CAR))
    if RENDER:
        hidden = isolate(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.6, 6.2, 1.55), target=(0.0, 0.10, 0.60), lens=50.0))
        finally:
            if not globals().get('KEEP_ISOLATED', False):
                isolate(False)
    if EXPORT:
        RES, INFO, DATA = export_all(CAR)
        print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
        print('materials', INFO['materials'])
