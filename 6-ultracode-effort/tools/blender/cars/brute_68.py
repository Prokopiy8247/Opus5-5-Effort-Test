"""Brute 68 - classic late-1960s-style muscle car, 2-door fastback, front V8, RWD (car #3 of Sunward Roads).

Rebuilds Cars/Car_brute_68 from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero
image and exports assets/imported/cars/brute_68.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\brute_68.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking).

Spec: L 4.95, W 1.90, H 1.33, wheelbase 2.80, track 1.55 / 1.55, wheel R 0.34 (15" rims, tall tyres),
tyre width 0.235 front / 0.255 rear. Original design (no real brand / model): very long hood with a raised
power bulge and a forward-facing scoop, fastback roof with a small ducktail, coke-bottle rear hips,
full-width chrome blade bumpers, quad round headlamps recessed in a dark full-width grille, full-width
tail-lamp panel, twin exhaust tips under the rear bumper, polished 5-slot mags. Deep gloss red #9E1B1B.
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
from mathutils.bvhtree import BVHTree  # noqa: E402

CAR_ID = 'brute_68'
CAR_NAME = 'Brute 68'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.80
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.40)
TRACK_F, TRACK_R = 1.55, 1.55
WHEEL_R = 0.34
WHEEL_W_F, WHEEL_W_R = 0.235, 0.255
ARCH_R, ARCH_Z = 0.372, 0.347                  # ~3 cm visible gap above the tyre
NOSE_Y, TAIL_Y = 2.322, -2.515                 # body cap poles; chrome bumpers add ~5 cm each end

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs),
# K3 waist / widest (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr),
# K8 roof crown (zc). On the deck and the hood K5..K8 lie on the panel surface.
Y_RW = -1.72             # rear window base / deck crease
Y_HEADER = 0.17          # windscreen header
Y_COWL = 0.72            # windscreen base / hood rear edge
S = [
    # ---- tail: ducktail lip on the last ring, flat tail panel closed by the cap
    dict(y=-2.490, zb=0.248, wb=0.46, zs=0.290, ws=0.800, zw=0.640, ww=0.872, zh=0.946, wh=0.850,
         zg=0.984, wg=0.770, zr=1.020, wr=0.540, zc=1.030, ks={6: 0.15}),
    dict(y=-2.465, zb=0.240, wb=0.50, zs=0.284, ws=0.836, zw=0.641, ww=0.900, zh=0.944, wh=0.878,
         zg=0.982, wg=0.790, zr=1.016, wr=0.560, zc=1.025),
    dict(y=-2.400, zb=0.236, wb=0.54, zs=0.284, ws=0.872, zw=0.643, ww=0.928, zh=0.938, wh=0.906,
         zg=0.970, wg=0.805, zr=0.998, wr=0.575, zc=1.005, ks={6: 0.3}),
    dict(y=-2.250, zb=0.220, wb=0.58, zs=0.276, ws=0.895, zw=0.646, ww=0.940, zh=0.934, wh=0.924,
         zg=0.961, wg=0.815, zr=0.984, wr=0.590, zc=0.990),
    dict(y=-2.000, zb=0.195, wb=0.61, zs=0.270, ws=0.905, zw=0.651, ww=0.946, zh=0.934, wh=0.930,
         zg=0.964, wg=0.822, zr=0.996, wr=0.600, zc=1.004),
    # ---- rear window base (deck crease), fastback sail panels on band 5
    dict(y=Y_RW, zb=0.180, wb=0.62, zs=0.268, ws=0.908, zw=0.655, ww=0.948, zh=0.934, wh=0.934,
         zg=0.966, wg=0.830, zr=1.030, wr=0.610, zc=1.042, sharp=dict(zc=0.8, zr=0.6), ks={6: 0.35}),
    dict(y=-1.400, zb=0.168, zs=0.266, ws=0.908, zw=0.652, ww=0.948, zh=0.932, wh=0.932,
         zg=0.962, wg=0.835, zr=1.112, wr=0.625, zc=1.128),
    dict(y=-1.050, zb=0.162, zs=0.265, ws=0.904, zw=0.628, ww=0.940, zh=0.918, wh=0.924,
         zg=0.944, wg=0.836, zr=1.185, wr=0.640, zc=1.212),
    dict(y=-0.620, zb=0.160, wb=0.62, zs=0.264, ws=0.893, zw=0.598, ww=0.925, zh=0.880, wh=0.906,
         zg=0.912, wg=0.834, zr=1.252, wr=0.658, zc=1.296),
    # ---- roof / cabin (pillarless hardtop)
    dict(y=-0.250, zw=0.591, ww=0.916, zh=0.866, wh=0.898, zg=0.900, wg=0.832, zr=1.272, wr=0.668, zc=1.330),
    dict(y=Y_HEADER, zw=0.590, ww=0.917, zh=0.866, wh=0.899, zg=0.900, wg=0.832, zr=1.268, wr=0.672, zc=1.322,
         sharp=dict(zc=0.5, zr=0.5, wr=0.3)),
    dict(y=0.445, zw=0.590, ww=0.921, zh=0.872, wh=0.902, zg=0.910, wg=0.826, zr=1.112, wr=0.718, zc=1.146),
    dict(y=Y_COWL, zw=0.590, ww=0.925, zh=0.878, wh=0.905, zg=0.920, wg=0.816, zr=0.948, wr=0.760, zc=0.962,
         sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- long hood / front wings
    dict(y=1.050, zb=0.168, wb=0.60, zs=0.270, ws=0.893, zw=0.590, ww=0.930, zh=0.880, wh=0.912,
         zg=0.912, wg=0.800, zr=0.932, wr=0.600, zc=0.944),
    dict(y=YF, zb=0.175, wb=0.60, zs=0.275, ws=0.890, zw=0.588, ww=0.933, zh=0.874, wh=0.917,
         zg=0.902, wg=0.792, zr=0.921, wr=0.585, zc=0.932),
    dict(y=1.850, zb=0.200, wb=0.58, zs=0.282, ws=0.880, zw=0.582, ww=0.931, zh=0.860, wh=0.912,
         zg=0.884, wg=0.782, zr=0.902, wr=0.560, zc=0.911),
    dict(y=2.120, zb=0.228, wb=0.55, zs=0.292, ws=0.862, zw=0.576, ww=0.922, zh=0.848, wh=0.902,
         zg=0.868, wg=0.772, zr=0.884, wr=0.540, zc=0.892),
    dict(y=2.220, zb=0.238, wb=0.52, zs=0.296, ws=0.840, zw=0.573, ww=0.904, zh=0.843, wh=0.884,
         zg=0.862, wg=0.760, zr=0.876, wr=0.525, zc=0.884),
    dict(y=2.268, zb=0.244, wb=0.50, zs=0.300, ws=0.815, zw=0.571, ww=0.884, zh=0.839, wh=0.863,
         zg=0.857, wg=0.745, zr=0.870, wr=0.510, zc=0.878),
    dict(y=2.292, zb=0.250, wb=0.47, zs=0.304, ws=0.790, zw=0.569, ww=0.860, zh=0.835, wh=0.840,
         zg=0.852, wg=0.725, zr=0.864, wr=0.495, zc=0.872),
]

# Quarter window: its rear edge leans forward going up, following the fastback (belt y=-1.12, rail y=-0.70)
WARP_Y = -0.98
WARP = dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.12, -0.70), margin=0.46)
RW_TOP = -0.78           # base y of the rear-window top edge (lands at ~-0.62 in band 7 via the warp)
Y_SAIL = 0.66            # door glass front edge / mirror sail
Y_SPLIT = (-0.432, -0.410)   # pillarless split between door glass and quarter glass (chrome)
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),       # windscreen
    dict(bands=(5, 5), y=(WARP_Y, Y_SAIL), role='glass'),         # door + quarter glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),          # mirror sail (black)
    dict(bands=(5, 5), y=Y_SPLIT, role='chrome'),                 # hardtop glass split
    dict(bands=(7, 7), y=(Y_RW + 0.03, RW_TOP), role='glass'),    # fastback rear window
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.06), role='trim'),   # cowl vent panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[2, 2, 5, 5, 2, 6, 2, 7],
    key_sharp=(0, 0.7, 0.5, 0.78, 0.88, 0.40, 0.42, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.55, tilt=2.0, k_edge=2.4, k_face=2.8, rings=8),
    tail=dict(y=TAIL_Y, z=0.64, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8),
    step=0.058,
    rail=0.05,
    warps=[WARP],
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.56), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.60)]
INNER = dict(y=(-1.700, 0.780), d=0.035,
             tubs=[(YR, ARCH_Z, ARCH_R + 0.03, 0.585), (YF, ARCH_Z, ARCH_R + 0.03, 0.545)])

EYE = Vector((-0.380, -0.300, 1.120))        # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.380, 0.235, 0.880))         # steering wheel hub
COLUMN_TILT = 24.0                           # deg, column descends toward the dash
SW_R = 0.195                                 # thin-rim wood wheel radius


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


def _x_to(normal):
    """Rotation matrix taking +X onto `normal`."""
    return Vector((1.0, 0.0, 0.0)).rotation_difference(Vector(normal).normalized()).to_matrix().to_4x4()


def dome_lens(center, normal, r, h, mat, segs=24):
    """Shallow spherical-cap lens standing on `center`, bulging along `normal`."""
    prof = [(0.0, r), (h * 0.45, r * 0.86), (h * 0.80, r * 0.56), (h, 0.0)]
    p = ck.revolve(prof, segs, mat)
    return p.transformed(Matrix.Translation(Vector(center)) @ _x_to(normal))


def bezel(center, normal, r, mat='Chrome', h=0.014, w=0.014, segs=24):
    """Round chrome lamp bezel (ring) standing on `center` around radius r."""
    prof = [(-0.006, r + w), (h * 0.85, r + w * 0.80), (h, r + w * 0.45), (h * 0.85, r + w * 0.12),
            (-0.006, r)]
    p = ck.revolve(prof, segs, mat)
    return p.transformed(Matrix.Translation(Vector(center)) @ _x_to(normal))


def blade_bumper(S, z, center_y, ahead, a_lim, height=0.112, depth=0.058, n=46, end_taper=6):
    """Full-width chrome blade bumper wrapping round the body corners at height z (centre of the blade)."""
    pts = S.outline_at_z(z, center=(0.0, center_y), a0=-a_lim, a1=a_lim, n=n, ahead=ahead)
    path = [p for (p, nrm) in pts]
    nors = [nrm for (p, nrm) in pts]
    hh = height / 2
    base = [(-0.020, -hh + 0.006), (0.006, -hh), (depth * 0.55, -hh + 0.004), (depth * 0.88, -hh * 0.62),
            (depth, -hh * 0.12), (depth * 0.97, hh * 0.30), (depth * 0.86, hh * 0.72), (depth * 0.55, hh),
            (0.006, hh - 0.002), (-0.020, hh - 0.008)]
    profs = []
    m = len(path)
    for i in range(m):
        e = min(i, m - 1 - i)
        k = 1.0 if e >= end_taper else 0.04 + 0.96 * math.sin(0.5 * math.pi * e / end_taper) ** 0.7
        kz = 1.0 if e >= end_taper else 0.70 + 0.30 * k
        profs.append([(u * k if u > 0 else u, v * kz) for (u, v) in base])
    return ck.sweep_path(path, profs, 'Chrome', normals=nors), pts


def hood_bulge_fn(co, d):
    h = 0.044 * ck.smoothstep(2.10, 1.66, co.y) * (0.78 + 0.22 * ck.smoothstep(0.80, 1.10, co.y))
    return h * ck.smoothstep(0.0, 0.085, d)


BULGE = ck.fillet_poly([(-0.285, 0.805), (0.285, 0.805), (0.255, 2.09), (-0.255, 2.09)], [0.05, 0.05, 0.14, 0.14], n=5)


def hood_scoop(bvh, y0=1.16, y1=1.62, w=0.205, h=0.074, lip=0.014, throat=0.11):
    """Forward-facing scoop sitting on the power bulge: painted shell, lip and a dark throat."""
    def ztop(x, y):
        loc, nor, idx, dist = bvh.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)), 5.0)
        return loc.z if loc is not None else None

    def prof(y, hk, wk=1.0):
        ww = w * wk
        pts = [(-ww, -0.016), (ww, -0.016), (ww, 0.50 * hk), (0.975 * ww, 0.82 * hk), (0.90 * ww, 0.97 * hk),
               (0.62 * ww, 1.02 * hk), (0.0, 1.035 * hk), (-0.62 * ww, 1.02 * hk), (-0.90 * ww, 0.97 * hk),
               (-0.975 * ww, 0.82 * hk), (-ww, 0.50 * hk)]
        out = []
        for (x, dz) in pts:
            zt = ztop(x, y)
            out.append((x, (zt if zt is not None else 1.0) + dz))
        return out
    ys = [y0 + (y1 - y0) * k / 10 for k in range(11)]
    profs = []
    for y in ys:
        f = ck.smoothstep(y0, y1 - 0.06, y)
        profs.append(prof(y, max(h * f, 0.004), 0.90 + 0.10 * f))
    part = ck.sweep_axis('y', ys, profs, 'Paint', cap0=True, cap1=False)
    # mouth: lip ring + dark throat going back into the scoop
    outer = profs[-1]
    zb = [ztop(x, y1) for (x, _) in outer]
    inner = []
    for (x, z), zt in zip(outer, zb):
        dz = z - zt
        xi = x * (w - lip) / w
        zi = zt + 0.006 + max(dz + 0.016, 0.0) * (h - lip - 0.006) / (h * 1.035 + 0.016)
        inner.append((xi, zi))
    m = len(outer)
    P = ck.Part()
    o_idx = [P.vert((x, y1, z)) for (x, z) in outer]
    i_idx = [P.vert((x, y1, z)) for (x, z) in inner]
    b_idx = [P.vert((x, y1 - throat, z - 0.012)) for (x, z) in inner]
    for k in range(m):
        k2 = (k + 1) % m
        P.face((o_idx[k], o_idx[k2], i_idx[k2], i_idx[k]), 'Paint')
        if P.face_normal(len(P.f) - 1).y < 0:
            P.f[-1] = tuple(reversed(P.f[-1]))
    s = len(P.f)
    cen = sum((Vector((x, y1 - throat / 2, z)) for (x, z) in inner), Vector()) / m
    for k in range(m):
        k2 = (k + 1) % m
        P.face((i_idx[k], i_idx[k2], b_idx[k2], b_idx[k]), 'Grille')
    P.orient(s, ref_fn=lambda c: Vector((cen.x, c.y, cen.z)), inward=True)
    P.face(list(b_idx), 'Grille')
    if P.face_normal(len(P.f) - 1).y < 0:
        P.f[-1] = tuple(reversed(P.f[-1]))
    part.extend(P)
    return part


def _mirror_pts(pts):
    return [Vector((-p.x, p.y, p.z)) for p in pts]


def window_chrome_loops():
    """Chrome reveal mouldings around the windscreen and the fastback rear window (closed loops)."""
    loops = []
    for (y_a, y_b) in ((Y_COWL + 0.004, Y_HEADER - 0.004),
                       (Y_RW + 0.03 - 0.004, BODY.warp_y(RW_TOP, 7.0) + 0.004)):
        side = [BODY.point(ck.lerp(y_a, y_b, k / 14), 7.0, 1) for k in range(15)]        # a -> b, right
        top = [BODY.point(y_b, 7.0 + k / 8.0, 1) for k in range(9)]                       # right edge -> centre
        bot = [BODY.point(y_a, 7.0 + k / 8.0, 1) for k in range(9)]
        top_full = top + list(reversed(_mirror_pts(top[:-1])))                             # right -> left
        bot_full = bot + list(reversed(_mirror_pts(bot[:-1])))                             # right -> left
        left_side = list(reversed(_mirror_pts(side)))                                     # b -> a, left
        loop = side + top_full[1:] + left_side[1:] + list(reversed(bot_full))[1:-1]
        loops.append(loop)
    return loops


def dlo_line():
    """Right-side DLO chrome: belt line from the sail to the quarter-glass rear edge, up that slanted edge,
    along the roof rail (drip moulding) and down the A-pillar to the cowl."""
    pts = []
    y_c0, y_c1 = WARP['y_t']
    for k in range(41):
        pts.append(BODY.point(ck.lerp(Y_COWL - 0.02, y_c0 - 0.012, k / 40), 4.95))
    for k in range(1, 9):
        t = 4.95 + (6.08 - 4.95) * k / 8
        u = ck.clamp(t - 5.0, 0.0, 1.0)
        pts.append(BODY.point(ck.lerp(y_c0, y_c1, u) - 0.012, t))
    for k in range(1, 41):
        pts.append(BODY.point(ck.lerp(y_c1 - 0.012, Y_HEADER, k / 40), 6.08))
    for k in range(1, 17):
        pts.append(BODY.point(ck.lerp(Y_HEADER, Y_COWL - 0.004, k / 16), 6.08))
    return pts


def body_details(car, S):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LTC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    F = S.frame('front')
    B = S.frame('rear')

    # ================= front: full-width dark grille, quad round lamps, chrome surround
    D = ck.densify
    grille = D(ck.fillet_poly([(-0.800, 0.492), (0.800, 0.492), (0.812, 0.772), (-0.812, 0.772)], 0.030, n=4), 0.08)
    C.extend(S.patch(grille, 'front', offset=0.002, depth=0.005, res=0.05, mat='Grille', smooth=False, walls=False))
    C.extend(S.rim(grille, 'front', width=0.020, offset=0.013, depth=0.006, mat='Chrome', smooth=False))
    # centre section: horizontal bars + a few vertical dividers (dark), thin chrome centre bar
    for k in range(8):
        z = 0.520 + k * 0.0315
        C.extend(S.patch(D(ck.rrect_pts(0.0, z, 0.80, 0.007, 0.003, n=1), 0.10), 'front', offset=0.0065, depth=0.005,
                         res=0.0, mat='Trim', smooth=False))
    for x in (-0.30, -0.15, 0.0, 0.15, 0.30):
        C.extend(S.patch(D(ck.rrect_pts(x, 0.632, 0.007, 0.250, 0.003, n=1), 0.07), 'front', offset=0.0080, depth=0.005,
                         res=0.0, mat='Trim', smooth=False))
    C.extend(S.patch(D(ck.rrect_pts(0.0, 0.632, 1.52, 0.010, 0.004, n=1), 0.10), 'front', offset=0.0100, depth=0.006,
                     res=0.0, mat='Chrome', smooth=False))
    lamp_c = []
    for x in (0.525, 0.705):
        loc, nor = S.hit(F, x, 0.632)
        R.extend(ck.disc(loc + nor * 0.0035, nor, 0.083, 'Grille', n=24))                  # dark bucket
        R.extend(bezel(loc + nor * 0.003, nor, 0.073, h=0.016, w=0.013))
        LH.extend(dome_lens(loc + nor * 0.0045, nor, 0.0735, 0.014, 'HeadlightLens'))
        lamp_c.append(loc + nor * 0.012)
    hc = (lamp_c[0] + lamp_c[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))
    # hood leading-edge brow overhanging the grille (casts a shadow line over the grille)
    pts = S.outline_at_z(0.792, center=(0.0, 1.97), a0=-71.0, a1=71.0, n=30, ahead=1)
    brow = [(-0.012, 0.016), (0.004, 0.018), (0.016, 0.014), (0.022, 0.004), (0.020, -0.008), (0.010, -0.016),
            (-0.012, -0.018)]
    profs = []
    for i in range(len(pts)):
        e = min(i, len(pts) - 1 - i)
        k = 1.0 if e >= 5 else 0.05 + 0.95 * math.sin(0.5 * math.pi * e / 5) ** 0.8
        profs.append([(u * k if u > 0 else u, v) for (u, v) in brow])
    C.extend(ck.sweep_path([p for (p, nrm) in pts], profs, 'Paint', normals=[nrm for (p, nrm) in pts]))
    # hood front shut line across the face
    C.extend(S.line([(-0.84, 0.826), (-0.5, 0.822), (0.0, 0.820), (0.5, 0.822), (0.84, 0.826)], 'front', step=0.03))
    # front chrome blade bumper (wraps round to the wheel arches)
    bump_f, _ = blade_bumper(S, 0.405, 1.97, 1, 88.0, height=0.112, depth=0.058, n=36)
    C.extend(bump_f)
    # parking lamps in the valance under the bumper
    pk = D(ck.rrect_pts(0.56, 0.300, 0.180, 0.042, 0.010, n=2), 0.03)
    R.extend(S.rim(pk, 'front', width=0.008, offset=0.006, depth=0.005, mat='Chrome', smooth=False))
    LH.extend(S.patch(pk, 'front', offset=0.0035, depth=0.004, res=0.0, mat='HeadlightLens', smooth=False))
    # lower valance lip (dark)
    C.extend(S.patch(D(ck.fillet_poly([(-0.70, 0.250), (0.70, 0.250), (0.74, 0.268), (-0.74, 0.268)], 0.006, n=2), 0.10),
                     'front', offset=0.0018, depth=0.004, res=0.03, mat='Trim', smooth=False))

    # ================= hood: power bulge + scoop, shut lines, pins, cowl, wipers
    bulge = S.patch(ck.densify(BULGE, 0.045), 'top', offset=0.0015, depth=0.006, res=0.044, mat='Paint', smooth=False,
                    bulge_fn=hood_bulge_fn)
    C.extend(bulge)
    bvh = BVHTree.FromPolygons([v.copy() for v in bulge.v], [list(f) for f in bulge.f])
    C.extend(hood_scoop(bvh))
    hood_edge = [BODY.point(y, 5.0) for y in (Y_COWL + 0.06, 1.05, 1.40, 1.80, 2.10, 2.22, 2.27)]
    R.extend(S.line3d(hood_edge, step=0.03))
    p = S.snap('top', 0.42, 2.12)
    R.extend(ck.ellipsoid(p + Vector((0, 0, 0.002)), (0.014, 0.014, 0.006), 'Chrome', nu=12, nv=6))
    R.extend(ck.box_between(p + Vector((-0.004, -0.02, 0.006)), p + Vector((-0.004, 0.03, 0.006)), 0.004, 0.004,
                            'Chrome'))
    for (x0, x1, y0, y1, px) in ((-0.70, -0.10, Y_COWL + 0.060, Y_COWL + 0.030, -0.34),
                                 (-0.05, 0.55, Y_COWL + 0.052, Y_COWL + 0.026, 0.25)):
        a0 = S.snap('top', x0, y0) + Vector((0, 0, 0.012))
        a1 = S.snap('top', x1, y1) + Vector((0, 0, 0.012))
        C.extend(ck.box_between(a0, a1, 0.014, 0.010, 'Chrome'))
        pivot = S.snap('top', px, Y_COWL + 0.10) + Vector((0, 0, 0.010))
        mid = (a0 + a1) / 2 + Vector((0, 0, 0.006))
        C.extend(ck.box_between(pivot, mid, 0.010, 0.007, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.014, 0.014, 0.009), 'Trim', nu=10, nv=6))
    # cowl vent slats
    for k in range(12):
        x = -0.55 + k * 0.10
        a = S.snap('top', x, Y_COWL + 0.008)
        b = S.snap('top', x, Y_COWL + 0.052)
        if a is not None and b is not None:
            C.extend(ck.box_between(a + Vector((0, 0, 0.004)), b + Vector((0, 0, 0.004)), 0.006, 0.004, 'Grille'))

    # ================= windows: chrome reveal mouldings, side DLO
    for lp in window_chrome_loops():
        C.extend(S.line3d(lp, width=0.016, offset=0.0018, mat='Chrome', step=0.045, closed=True))
    R.extend(S.line3d(dlo_line(), width=0.013, offset=0.0018, mat='Chrome', step=0.045))

    # ================= side: shut lines, handle, mirror, quarter vents, sill chrome, markers, antenna
    R.extend(S.line([(0.865, 0.30), (0.872, 0.60), (0.868, 0.872)], 'right', step=0.02))            # door front
    R.extend(S.line([(-0.440, 0.30), (-0.440, 0.60), (-0.445, 0.872)], 'right', step=0.02))         # door rear
    R.extend(S.line([(0.865, 0.30), (0.30, 0.296), (-0.440, 0.296)], 'right', step=0.03))           # door bottom
    R.extend(S.patch(D(ck.rrect_pts(-0.300, 0.828, 0.150, 0.034, 0.012, n=3), 0.02), 'right', offset=0.0012, depth=0.004,
                     res=0.0, mat='Trim', smooth=False))
    R.extend(S.patch(D(ck.rrect_pts(-0.300, 0.832, 0.140, 0.020, 0.009, n=3), 0.02), 'right', offset=0.0065, depth=0.006,
                     res=0.0, mat='Chrome', smooth=False))
    loc, nor = S.hit(S.frame('right'), -0.215, 0.832)
    R.extend(ck.disc(loc + nor * 0.007, nor, 0.010, 'Chrome', n=12))
    # chrome bullet mirror on the door, ahead of the glass
    mb = S.snap('top', 0.86, 0.58)
    base = mb + Vector((0.0, 0.0, 0.004))
    head = Vector((0.958, 0.575, mb.z + 0.075))
    R.extend(ck.ellipsoid(base + Vector((0.0, 0.0, 0.006)), (0.030, 0.045, 0.012), 'Chrome', nu=12, nv=6))
    R.extend(ck.box_between(base + Vector((0.010, 0.0, 0.010)), head + Vector((-0.020, 0.0, -0.010)), 0.016, 0.014,
                            'Chrome'))

    def bullet(q):
        if q.y < 0:
            q.y *= 0.35
        return q
    R.extend(ck.ellipsoid(head, (0.045, 0.060, 0.040), 'Chrome', nu=16, nv=10, deform=bullet))
    R.extend(ck.disc(head + Vector((0.0, -0.022, 0.0)), (0, -1, 0), 0.036, 'Trim', n=16))
    # non-functional quarter vent ahead of the rear wheel: dark slot + chrome strakes
    vent = D(ck.fillet_poly([(-0.640, 0.640), (-0.940, 0.660), (-0.960, 0.748), (-0.680, 0.744)], 0.012, n=3), 0.025)
    R.extend(S.patch(vent, 'right', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    R.extend(S.rim(vent, 'right', width=0.010, offset=0.006, depth=0.005, mat='Chrome', smooth=False))
    for z in (0.670, 0.694, 0.718):
        R.extend(S.line(D([(-0.66, z - 0.002), (-0.94, z + 0.004)], 0.025, closed=False), 'right', width=0.006,
                        offset=0.004, mat='Chrome', smooth=False, step=0.02))
    # sill chrome moulding between the arches
    R.extend(S.line([(1.00, 0.330), (0.40, 0.322), (-0.40, 0.322), (-1.00, 0.330)], 'right', width=0.012,
                    offset=0.0022, mat='Chrome', step=0.03))
    # side marker lamps (rear red, front clear)
    for (y, z, lst, m) in ((-2.20, 0.660, LT, 'TaillightLens'), (2.08, 0.640, LH, 'HeadlightLens')):
        mk = D(ck.rrect_pts(y, z, 0.080, 0.030, 0.008, n=2), 0.02)
        R.extend(S.rim(mk, 'right', width=0.006, offset=0.004, depth=0.004, mat='Chrome', smooth=False))
        lst.extend(S.patch(mk, 'right', offset=0.0028, depth=0.003, res=0.0, mat=m, smooth=False))
    # antenna on the right front wing (not mirrored)
    ap = S.snap('top', 0.84, 1.78)
    C.extend(ck.ellipsoid(ap + Vector((0, 0, 0.002)), (0.012, 0.012, 0.006), 'Chrome', nu=10, nv=6))
    C.extend(ck.box_between(ap, ap + Vector((0.0, -0.05, 0.50)), 0.0035, 0.0035, 'Chrome'))

    # ================= rear: deck lid, full-width tail panel, bumper, plate, exhausts
    deck_side = [BODY.point(y, 5.0) for y in (Y_RW + 0.07, -2.00, -2.25, -2.40, -2.455)]
    R.extend(S.line3d(deck_side, step=0.03))
    C.extend(S.line([(-0.80, Y_RW + 0.07), (-0.40, Y_RW + 0.07), (0.0, Y_RW + 0.07), (0.40, Y_RW + 0.07),
                     (0.80, Y_RW + 0.07)], 'top', step=0.025))
    C.extend(S.line([(-0.80, 0.905), (-0.40, 0.902), (0.0, 0.901), (0.40, 0.902), (0.80, 0.905)], 'rear', step=0.025))
    tail = D(ck.fillet_poly([(-0.800, 0.632), (0.800, 0.632), (0.806, 0.860), (-0.806, 0.860)], 0.022, n=4), 0.08)
    C.extend(S.patch(tail, 'rear', offset=0.002, depth=0.005, res=0.05, mat='Grille', smooth=False, walls=False))
    C.extend(S.rim(tail, 'rear', width=0.016, offset=0.011, depth=0.006, mat='Chrome', smooth=False))
    cells = [(0.215, 0.395), (0.410, 0.590), (0.605, 0.785)]
    for ci, (x0, x1) in enumerate(cells):
        cell = D(ck.fillet_poly([(x0, 0.652), (x1, 0.652), (x1, 0.840), (x0, 0.840)], 0.010, n=2), 0.05)
        LT.extend(S.patch(cell, 'rear', offset=0.0055, depth=0.004, res=0.0, mat='TaillightLens', smooth=False))
        xm = (x0 + x1) / 2
        if ci > 0:
            LB.extend(S.patch(D(ck.rrect_pts(xm, 0.746, x1 - x0 - 0.050, 0.120, 0.012, n=2), 0.05), 'rear', offset=0.0075,
                              depth=0.004, res=0.0, mat='BrakeLens', smooth=False))
        else:
            LR.extend(S.patch(ck.rrect_pts(xm, 0.746, 0.080, 0.070, 0.010, n=2), 'rear', offset=0.0075,
                              depth=0.004, res=0.0, mat='ReverseLens', smooth=False))
        R.extend(S.patch(D(ck.rrect_pts(x0 - 0.0075, 0.746, 0.009, 0.200, 0.003, n=1), 0.07), 'rear', offset=0.009,
                         depth=0.006, res=0.0, mat='Chrome', smooth=False))
    # centre: chrome fuel filler cap
    loc, nor = S.hit(B, 0.0, 0.746)
    C.extend(ck.disc(loc + nor * 0.009, nor, 0.052, 'Chrome', n=24, ring_mat='Chrome', ring_w=0.006))
    C.extend(ck.disc(loc + nor * 0.011, nor, 0.030, 'Trim', n=20))
    # rear chrome blade bumper
    bump_r, _ = blade_bumper(S, 0.512, -2.18, -1, 86.0, height=0.110, depth=0.052, n=36)
    C.extend(bump_r)
    # number-plate recess (US size) in the valance under the bumper
    plate = D(ck.rrect_pts(0.0, 0.372, 0.330, 0.150, 0.010, n=2), 0.05)
    C.extend(S.patch(plate, 'rear', offset=0.0015, depth=0.004, res=0.025, mat='Grille', smooth=False))
    C.extend(S.rim(plate, 'rear', width=0.012, offset=0.0055, depth=0.005, mat='Trim', smooth=False))
    # twin exhaust tips under the bumper
    tips = []
    for x in (0.56, -0.56):
        p0 = Vector((x, -2.30, 0.300))
        p1 = Vector((x, -2.560, 0.300))
        C.extend(ck.tube(p0, p1, 0.040, 0.033, 'Chrome', 'Trim', n=22, inner_depth=0.06))
        C.extend(ck.tube(Vector((x * 0.85, -1.85, 0.215)), p0 + Vector((0, 0.02, 0)), 0.028, 0.024, 'Underbody',
                         'Underbody', n=12))
        tips.append(p1)
    car.socket('Socket_Exhaust', tips[0])
    car.socket('Socket_Exhaust2', tips[1])

    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x(), LTC)
    car.add('Lights_Brake', LB, LB.mirrored_x())
    car.add('Lights_Reverse', LR, LR.mirrored_x())


def interior(car):
    I = ck.Part()
    # ---- dashboard (profile in (y, z) swept across X): padded top, flat face, wood strip
    dash = [(0.98, 0.900), (0.80, 0.938), (0.64, 0.950), (0.565, 0.944), (0.538, 0.920), (0.530, 0.880),
            (0.527, 0.845), (0.530, 0.800), (0.545, 0.770), (0.60, 0.70), (0.70, 0.60), (0.84, 0.52),
            (0.94, 0.62), (0.98, 0.72)]
    dmats = ['InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorWood',
             'InteriorDark', 'InteriorDark', 'Interior', 'Interior', 'InteriorDark', 'InteriorDark', 'InteriorDark',
             'InteriorDark']
    xs = [-0.785, -0.77, -0.55, -0.2, 0.0, 0.2, 0.55, 0.77, 0.785]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < 0.78 else 0.01
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # driver's binnacle: two big dials with chrome rings, small visor above
    xb = [HUB.x - 0.175, HUB.x - 0.165, HUB.x + 0.165, HUB.x + 0.175]
    visor = [(0.560, 0.944), (0.505, 0.962), (0.470, 0.958), (0.474, 0.948), (0.530, 0.936)]
    I.extend(ck.sweep_axis('x', xb, [[(y + (0.006 if k in (0, 3) else 0.0), z - (0.006 if k in (0, 3) else 0.0))
                                      for (y, z) in visor] for k in range(4)], 'InteriorDark'))
    for (dx, nt, r) in ((-0.078, 9, 0.058), (0.078, 11, 0.058)):
        c = Vector((HUB.x + dx, 0.522, 0.876))
        I.extend(ck.gauge(c, EYE - c, r, n_ticks=nt))
        I.extend(bezel(c - (EYE - c).normalized() * 0.002, EYE - c, r, mat='Chrome', h=0.010, w=0.007, segs=24))
    # centre dash: three small gauges, radio, glovebox
    for dx in (-0.075, 0.0, 0.075):
        c = Vector((dx, 0.528, 0.900))
        I.extend(ck.gauge(c, (0, -1, 0.15), 0.026, n_ticks=7))
        I.extend(bezel(c + Vector((0, 0.002, 0)), (0, -1, 0.15), 0.026, mat='Chrome', h=0.006, w=0.004, segs=16))
    I.extend(ck.box_between((0.0, 0.535, 0.815), (0.0, 0.520, 0.815), 0.20, 0.050, 'InteriorDark'))
    I.extend(ck.box_between((-0.07, 0.518, 0.815), (0.07, 0.518, 0.815), 0.012, 0.016, 'Chrome'))
    for x in (-0.085, 0.085):
        I.extend(ck.disc((x, 0.517, 0.815), (0, -1, 0), 0.012, 'Chrome', n=12))
    I.extend(ck.box_between((0.30, 0.523, 0.845), (0.62, 0.523, 0.845), 0.006, 0.090, 'InteriorDark', up=(0, 0, 1)))
    I.extend(ck.box_between((0.45, 0.519, 0.858), (0.49, 0.519, 0.858), 0.010, 0.012, 'Chrome'))
    # steering column
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.36, 0.060, 0.065, 'InteriorDark'))
    # centre console with 4-speed shifter
    cys = [0.53, 0.46, 0.30, 0.05, -0.20, -0.42]
    tops = [0.62, 0.56, 0.47, 0.47, 0.50, 0.50]
    profs = [[(-0.105, 0.19), (0.105, 0.19), (0.11, t - 0.03), (0.09, t), (-0.09, t), (-0.11, t - 0.03)] for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'InteriorDark', 'Interior',
                                             'InteriorDark']))
    I.extend(ck.box_between((0.0, 0.40, 0.535), (0.0, 0.12, 0.475), 0.13, 0.008, 'InteriorWood'))
    I.extend(ck.box_between((0.0, 0.18, 0.47), (0.0, 0.13, 0.70), 0.012, 0.012, 'Chrome'))     # shifter
    I.extend(ck.ellipsoid((0.0, 0.128, 0.712), (0.022, 0.022, 0.022), 'InteriorWood', nu=12, nv=8))
    I.extend(ck.ellipsoid((0.0, 0.17, 0.478), (0.040, 0.050, 0.014), 'InteriorDark', nu=12, nv=6))  # boot
    # seats: two front buckets + rear bench (low backrest under the fastback)
    for x in (-0.380, 0.380):
        I.extend(ck.bucket_seat(x, 0.20, -0.30, 0.285, width=0.53, recline=20.0, back_h=0.80, bolster=0.040,
                                headrest_w=0.25))
    I.extend(ck.bucket_seat(0.0, -0.72, -1.16, 0.275, width=1.12, recline=27.0, back_h=0.56, bolster=0.05, bench=True))
    # rear luggage deck under the fastback glass
    I.extend(ck.box_between((0.0, -1.38, 0.86), (0.0, -1.68, 0.86), 1.22, 0.016, 'InteriorDark'))
    # door cards: armrest, chrome strip, window crank, speaker; mirrored
    door = ck.Part()
    ays = [0.62, 0.59, -0.30, -0.34]
    door.extend(ck.sweep_axis('y', ays, [(0.792, 0.640), (0.815, 0.600), (0.872, 0.598), (0.872, 0.668), (0.800, 0.668)],
                              'InteriorDark'))
    door.extend(ck.box_between((0.866, 0.60, 0.780), (0.866, -0.36, 0.780), 0.010, 0.022, 'Chrome', up=(1, 0, 0)))
    door.extend(ck.box_between((0.865, 0.40, 0.735), (0.865, 0.30, 0.735), 0.020, 0.020, 'Chrome'))
    door.extend(ck.disc((0.866, -0.05, 0.700), (-1, 0, 0), 0.026, 'Chrome', n=12))
    door.extend(ck.box_between((0.862, -0.05, 0.700), (0.852, -0.05, 0.640), 0.010, 0.010, 'Chrome'))
    door.extend(ck.ellipsoid((0.848, -0.05, 0.634), (0.010, 0.022, 0.010), 'InteriorDark', nu=10, nv=6))
    door.extend(ck.disc((0.874, 0.40, 0.42), (-1, 0, 0), 0.065, 'InteriorDark', n=16))
    I.extend(door, door.mirrored_x())
    # pedals
    for x, w in ((-0.49, 0.06), (-0.38, 0.09), (-0.27, 0.06)):
        I.extend(ck.box_between((x, 0.80, 0.24), (x, 0.76, 0.34), w, 0.012, 'InteriorDark'))
    # sun visors + rear-view mirror
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.15, 0.06, 1.262), (s * 0.50, 0.06, 1.262), 0.16, 0.014, 'Interior'))
    I.extend(ck.box_between((-0.105, 0.195, 1.236), (0.105, 0.195, 1.236), 0.022, 0.048, 'InteriorDark'))
    I.extend(ck.box_between((-0.099, 0.1835, 1.236), (0.099, 0.1835, 1.236), 0.002, 0.040, 'Chrome'))
    I.extend(ck.box_between((0.0, 0.205, 1.255), (0.0, 0.215, 1.292), 0.016, 0.016, 'Chrome'))
    car.add('Interior', I)
    # thin-rim wood steering wheel, 3 polished spokes (separate object, origin at the hub)
    car.add('SteeringWheel', ck.steering_wheel_part(R=SW_R, tube_r=(0.0105, 0.0125), segs=44, flat_bottom=False,
                                                    hub_r=0.050, rim_mat='InteriorWood', spoke_mat='Chrome',
                                                    hub_mat='InteriorDark', marker=False, spoke_thick=0.006,
                                                    dish=0.045,
                                                    spokes=((0.0, 0.040), (180.0, 0.040), (270.0, 0.034))),
            ck.disc((0.0, -0.0135, 0.0), (0, -1, 0), 0.030, 'Chrome', n=20, ring_mat='InteriorDark', ring_w=0.004),
            location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W_F, rim_d_in=15, spokes=5, style='slot', segs=44, tyre='tall',
                  grooves=[-0.042, 0.042], groove_w=0.012, spoke_thick=0.018, spoke_dish=0.044, hub_r=0.060,
                  nuts=5, disc_r=0.140, caliper_angle=150.0, caliper_span=40.0, face_segs=44,
                  slot_r=(0.080, 0.172), slot_w=(0.036, 0.064), slot_wall_mat='BrakeDisc', barrel_mat='BrakeDisc',
                  rear=dict(W=WHEEL_W_R, grooves=[-0.048, 0.048], disc_r=0.135, caliper_span=36.0))


def build():
    paint = (0.3419, 0.0110, 0.0110)          # #9E1B1B deep red (linear)
    mats = ck.default_materials(paint=paint, paint_metallic=0.0, paint_rough=0.22, paint_coat=0.9,
                                rim=(0.72, 0.72, 0.74), rim_metallic=1.0, rim_rough=0.20,
                                caliper=(0.30, 0.30, 0.31),
                                interior=(0.055, 0.052, 0.050), interior_dark=(0.014, 0.014, 0.015))
    mats['Interior'] = dict(base=(0.055, 0.052, 0.050), roughness=0.55)
    mats['BrakeDisc'] = dict(base=(0.17, 0.17, 0.18), metallic=1.0, roughness=0.50)
    mats['TaillightLens'] = dict(base=(0.26, 0.006, 0.007), roughness=0.12, emission=(1.0, 0.025, 0.02), strength=0.45)
    mats['BrakeLens'] = dict(base=(0.36, 0.010, 0.010), roughness=0.10, emission=(1.0, 0.03, 0.02), strength=0.30)
    mats['Glass'] = dict(base=(0.010, 0.014, 0.016), roughness=0.03, alpha=0.30, double_sided=True)
    mats['InteriorWood'] = dict(base=(0.16, 0.062, 0.020), roughness=0.30, coat=0.8, coat_rough=0.05)
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
        car.socket('Socket_CamHood', (0.0, 0.86, 1.13))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.08, 0.50))
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


def measure(car, tris):
    G = ck.to_godot
    SHELL_YS = car.shell.ys
    body = car.objects['Body']
    M = body.matrix_world
    bv = [M @ v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in bv), min(v.y for v in bv), min(v.z for v in bv)))
    mx = Vector((max(v.x for v in bv), max(v.y for v in bv), max(v.z for v in bv)))
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.95 and abs(v.y - 0.58) > 0.12)   # mirrors excluded
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
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'classic muscle car (fastback)', 'drivetrain': 'RWD',
        'engine': 'front V8', 'doors': 2, 'seats': 4, 'source_blend': 'Opus55ForzaUltracodeEffort.blend',
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
        'rim_diameter_in': 15,
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
        'default_paint': {'hex': '#9E1B1B', 'linear_rgb': [0.3419, 0.011, 0.011], 'finish': 'gloss',
                          'note': 'stripes are added by the game shader'},
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
        print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W_R), 'interior verts in wheel wells:', interior_in_wells(CAR))
    if RENDER:
        hidden = isolate(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.4, 6.6, 1.35), target=(0.0, 0.0, 0.58),
                                           lens=50.0, world_strength=0.7, sun_energy=3.6))
        finally:
            if not globals().get('KEEP_ISOLATED', False):
                isolate(False)
    if EXPORT:
        RES, INFO, DATA = export_all(CAR)
        print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
        print('materials', INFO['materials'])
