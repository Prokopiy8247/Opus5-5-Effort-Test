"""Sora S2 - modern compact sports coupe, 2+2, front-mid engine, RWD (car #4 of Sunward Roads).

Rebuilds Cars/Car_sora_s2 from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero
image and exports assets/imported/cars/sora_s2.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\sora_s2.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking).

Spec: L 4.35, W 1.80, H 1.27, wheelbase 2.55, track 1.54 / 1.56, wheel R 0.32 (18" rims), tyre width
0.225 front / 0.245 rear. Original design (no real brand / model): long low hood, cabin set well back,
smooth fastback greenhouse with a carbon roof panel, one sharp shoulder crease from the headlamp to the tail,
slim LED headlamp blades, large lower intake with corner curtains, integrated ducktail spoiler, slim
full-width tail-lamp bar, dual exhaust tips at the corners of a carbon diffuser, 10 thin Y-split spokes in
gunmetal. Matte-ish pearl white #E8E8E4.

Review fixes (rework 1):
* third brake light: black housing + lens raised 3 / 5 mm off the carbon roof and following its crown (res > 0),
  shark-fin antenna moved forward so the two never overlap (was coplanar with the roof -> z-fighting);
* the cabin inner shell now continues under the deck to y = -2.05 (closed boot), so rays through the big rear
  window never reach the back of the rear bulkhead or the inside of the rear underbody (see-through gaps);
  the underbody exhaust pipes (open tubes) are gone and the tips are capped; window reveals get back faces;
* sculpted, smooth, outward-oriented sport seats (signed-volume check) replace the inside-out bucket_seat()
  parts; rounded rear-view mirror; parcel shelf clear of the rear seat backs;
* front wheel-well liner reliefs (r 0.358 inboard of the 0.348 arch lip) clear the front tyres at +-32 deg
  steer with 3 cm bump; the visible arch gap is unchanged;
* recessed (boolean pocket) lower intake with three blade fins and a centre divider, recessed corner air
  curtains with vanes instead of flat painted-on patches.
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

CAR_ID = 'sora_s2'
CAR_NAME = 'Sora S2'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.55
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.275)
TRACK_F, TRACK_R = 1.54, 1.56
WHEEL_R = 0.32
WHEEL_W_F, WHEEL_W_R = 0.225, 0.245
ARCH_R, ARCH_Z = 0.348, 0.327                  # ~3 cm visible gap above the tyre
NOSE_Y, TAIL_Y = 2.165, -2.185                 # cap poles -> overall length 4.35

# ---------------------------------------------------------------- body stations (rear -> front)
# Key points per half section (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs),
# K3 waist / widest (ww, zw), K4 shoulder crease (wh, zh), K5 glass base (wg, zg), K6 roof rail (wr, zr),
# K8 roof crown (zc). On the deck and the hood K5..K8 lie on the panel surface.
Y_RW = -1.680            # rear window base / deck crease
RW_TOP = -0.800          # rear window top edge (roof panel starts here)
Y_HEADER = -0.100        # windscreen header
Y_COWL = 0.620           # windscreen base / hood rear edge
S = [
    # ---- tail: integrated ducktail (deck sweeps up ~5 cm into a crisp lip), rounded plan corners
    dict(y=-2.155, zb=0.340, wb=0.40, zs=0.372, ws=0.680, zw=0.620, ww=0.748, zh=0.917, wh=0.708,
         zg=0.980, wg=0.640, zr=1.008, wr=0.470, zc=1.014, ks={6: 0.15}),
    dict(y=-2.125, zb=0.324, wb=0.46, zs=0.356, ws=0.742, zw=0.622, ww=0.806, zh=0.915, wh=0.770,
         zg=0.973, wg=0.692, zr=0.999, wr=0.515, zc=1.005),
    dict(y=-2.050, zb=0.294, wb=0.53, zs=0.330, ws=0.810, zw=0.626, ww=0.866, zh=0.908, wh=0.836,
         zg=0.958, wg=0.748, zr=0.977, wr=0.555, zc=0.983, ks={6: 0.3}),
    dict(y=-1.900, zb=0.240, wb=0.58, zs=0.296, ws=0.852, zw=0.630, ww=0.897, zh=0.900, wh=0.874,
         zg=0.944, wg=0.784, zr=0.958, wr=0.585, zc=0.964),
    # ---- deck crease / rear window base
    dict(y=Y_RW, zb=0.195, wb=0.60, zs=0.276, ws=0.862, zw=0.636, ww=0.906, zh=0.892, wh=0.888,
         zg=0.938, wg=0.796, zr=0.956, wr=0.598, zc=0.960, sharp=dict(zc=0.8, zr=0.6), ks={6: 0.35}),
    # ---- fastback rear window over the rear haunches (widest point of the car)
    dict(y=-1.300, zb=0.172, wb=0.62, zs=0.266, ws=0.860, zw=0.640, ww=0.906, zh=0.880, wh=0.882,
         zg=0.938, wg=0.795, zr=1.070, wr=0.612, zc=1.086),
    dict(y=-0.950, zb=0.162, zs=0.258, ws=0.846, zw=0.608, ww=0.893, zh=0.864, wh=0.872,
         zg=0.918, wg=0.796, zr=1.165, wr=0.622, zc=1.188),
    # ---- cabin (doors slightly narrower than the haunches and wings: coke-bottle plan)
    dict(y=-0.550, zb=0.152, wb=0.62, zs=0.252, ws=0.830, zw=0.578, ww=0.878, zh=0.848, wh=0.853,
         zg=0.898, wg=0.790, zr=1.222, wr=0.636, zc=1.258),
    dict(y=-0.250, ws=0.826, zw=0.566, ww=0.874, zh=0.840, wh=0.850, zg=0.889, wg=0.788, zr=1.230, wr=0.643,
         zc=1.270),
    dict(y=Y_HEADER, zw=0.560, ww=0.874, zh=0.836, wh=0.849, zg=0.886, wg=0.786, zr=1.222, wr=0.646, zc=1.262,
         sharp=dict(zc=0.5, zr=0.5, wr=0.3)),
    dict(y=0.280, ws=0.830, zw=0.550, ww=0.877, zh=0.826, wh=0.851, zg=0.877, wg=0.783, zr=1.068, wr=0.698,
         zc=1.098),
    dict(y=Y_COWL, zw=0.544, ww=0.881, zh=0.818, wh=0.857, zg=0.862, wg=0.783, zr=0.896, wr=0.756, zc=0.902,
         sharp=dict(zc=1.0, zr=1.0, wr=1.0)),
    # ---- long hood between raised front-wing crowns; raked, rounded nose
    dict(y=0.900, zb=0.155, wb=0.61, zs=0.255, ws=0.838, zw=0.538, ww=0.886, zh=0.814, wh=0.866,
         zg=0.846, wg=0.778, zr=0.856, wr=0.560, zc=0.862),
    dict(y=YF, zb=0.165, wb=0.60, zs=0.262, ws=0.838, zw=0.528, ww=0.893, zh=0.806, wh=0.872,
         zg=0.840, wg=0.770, zr=0.814, wr=0.520, zc=0.810, ks={5: 0.6}),
    dict(y=1.620, zb=0.183, wb=0.58, zs=0.270, ws=0.830, zw=0.516, ww=0.886, zh=0.778, wh=0.864,
         zg=0.808, wg=0.762, zr=0.780, wr=0.505, zc=0.774),
    dict(y=1.780, zb=0.195, wb=0.56, zs=0.277, ws=0.812, zw=0.508, ww=0.870, zh=0.758, wh=0.846,
         zg=0.782, wg=0.742, zr=0.754, wr=0.490, zc=0.748),
    dict(y=1.900, zb=0.207, wb=0.53, zs=0.284, ws=0.778, zw=0.498, ww=0.836, zh=0.734, wh=0.808,
         zg=0.750, wg=0.705, zr=0.731, wr=0.470, zc=0.726, ks={5: 0.4}),
    dict(y=1.990, zb=0.218, wb=0.49, zs=0.292, ws=0.728, zw=0.488, ww=0.780, zh=0.704, wh=0.752,
         zg=0.713, wg=0.655, zr=0.698, wr=0.445, zc=0.694),
    dict(y=2.060, zb=0.232, wb=0.43, zs=0.300, ws=0.655, zw=0.478, ww=0.700, zh=0.668, wh=0.672,
         zg=0.672, wg=0.585, zr=0.655, wr=0.405, zc=0.648),
    dict(y=2.110, zb=0.250, wb=0.36, zs=0.312, ws=0.555, zw=0.468, ww=0.592, zh=0.622, wh=0.566,
         zg=0.624, wg=0.495, zr=0.605, wr=0.350, zc=0.598),
    dict(y=2.140, zb=0.272, wb=0.27, zs=0.326, ws=0.425, zw=0.458, ww=0.455, zh=0.572, wh=0.432,
         zg=0.573, wg=0.378, zr=0.556, wr=0.270, zc=0.550),
    dict(y=2.152, zb=0.292, wb=0.20, zs=0.340, ws=0.320, zw=0.452, ww=0.345, zh=0.535, wh=0.326,
         zg=0.535, wg=0.285, zr=0.522, wr=0.205, zc=0.517),
]

# Quarter window: its rear edge leans forward going up, following the fastback (belt y=-1.30, rail y=-0.92)
WARP_Y = -1.110
WARP = dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.300, -0.920), margin=0.30)
Y_SAIL = 0.480           # door glass front edge / mirror sail
Y_QSPLIT = (-0.660, -0.636)   # door glass / quarter glass divider (black)
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),       # windscreen
    dict(bands=(5, 5), y=(WARP_Y, Y_SAIL), role='glass'),         # door + quarter glass
    dict(bands=(5, 5), y=(Y_SAIL, Y_COWL), role='trim'),          # mirror sail (black)
    dict(bands=(5, 5), y=Y_QSPLIT, role='trim'),                  # door / quarter divider
    dict(bands=(7, 7), y=(RW_TOP, Y_HEADER), role='carbon'),      # carbon roof panel
    dict(bands=(7, 7), y=(Y_RW + 0.030, RW_TOP), role='glass'),   # fastback rear window
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.050), role='trim'),  # cowl panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[3, 3, 5, 5, 2, 6, 2, 7],
    key_sharp=(0, 0.7, 0.5, 0.72, 0.9, 0.40, 0.42, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.42, tilt=8.0, k_edge=1.8, k_face=2.6, rings=8),
    tail=dict(y=TAIL_Y, z=0.66, tilt=0.0, k_edge=2.4, k_face=2.8, rings=8),
    step=0.05,
    rail=0.05,
    warps=[WARP],
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.50), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.56)]
# inner cabin shell: from the firewall back under the deck to a closed boot (y -2.05), so nothing behind the
# rear seats can be seen "from behind" through the fastback glass
# rear wheel tubs: generous radius (arch + 13 cm: the inner-shell rows are up to 0.17 m apart) and x limit (2.6 cm
# inboard of the well wall) so the coarse inner shell never lets the wheel-well liner poke into the cabin (it showed
# as back faces through the glass)
INNER = dict(y=(-2.050, 0.660), d=0.035,
             tubs=[(YR, ARCH_Z, ARCH_R + 0.13, 0.534)])

# ---------------------------------------------------------------- recessed openings (boolean pockets)
# Outlines in view coordinates: 'front' = (x, z) seen from ahead.
MOUTH = ck.fillet_poly([(-0.520, 0.296), (0.520, 0.296), (0.455, 0.468), (-0.455, 0.468)],
                       [0.050, 0.050, 0.060, 0.060], n=5)                         # large lower intake
MOUTH_DEPTH = 0.050
CURTAIN_R = ck.fillet_poly([(0.600, 0.302), (0.700, 0.296), (0.742, 0.452), (0.642, 0.462)], 0.018, n=3)
CURTAIN_DEPTH = 0.030
LINER_R = 0.356          # front wheel-well liner relief radius (arch lip stays at ARCH_R); the steered tyre needs
#                          0.352 at +-32 deg / 3 cm bump (x 0.72-0.82, 15-50 deg either side of the top)


def pocket(Sx, outline, view, depth, wall_mat='Trim', back_mat='Grille', res=0.035, max_len=0.02, out=0.20):
    """Closed prism cutter for LoftBody.build(cutters=...) (same construction as kestrel_r4.pocket): the
    outline (view coords) is projected onto the uncut shell; the pocket floor lies `depth` metres deeper along
    the view direction (it follows the panel curvature), the walls run parallel to the view direction."""
    from mathutils import geometry
    frame = Sx.frame(view)
    O, U, V, D = frame
    pts = ck.densify([Vector((p[0], p[1])) for p in outline], max_len)
    if ck.poly_area(pts) < 0:
        pts.reverse()
    nb = len(pts)
    verts2d = list(pts)
    if res > 0:
        xs = [p.x for p in pts]
        ys = [p.y for p in pts]
        gx = min(xs) + res * 0.5
        while gx < max(xs):
            gy = min(ys) + res * 0.5
            while gy < max(ys):
                g = Vector((gx, gy))
                if ck.point_in_poly(g, pts) and ck.dist_to_poly(g, pts) > res * 0.45:
                    verts2d.append(g)
                gy += res
            gx += res
    cdt = geometry.delaunay_2d_cdt(verts2d, [(k, (k + 1) % nb) for k in range(nb)], [list(range(nb))], 1, 1e-7)
    ov, of = cdt[0], cdt[2]
    part = ck.Part()
    back, front = [], []
    for co in ov:
        loc, nor = Sx.hit(frame, co.x, co.y)
        if loc is None:
            raise RuntimeError('pocket outline misses the shell at %s %s' % (view, tuple(co)))
        back.append(part.vert(loc + D * depth))
        front.append(part.vert(loc - D * out))
    ecount = {}
    for f in of:
        part.face([back[k] for k in f], back_mat)
        if part.face_normal(len(part.f) - 1).dot(D) < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
        part.face([front[k] for k in f], wall_mat)
        if part.face_normal(len(part.f) - 1).dot(D) > 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
        for k in range(len(f)):
            key = tuple(sorted((f[k], f[(k + 1) % len(f)])))
            ecount[key] = ecount.get(key, 0) + 1
    for (a, b), n in ecount.items():
        if n != 1:
            continue
        part.face((back[a], back[b], front[b], front[a]), wall_mat)
        e2 = ov[b] - ov[a]
        n2 = Vector((e2.y, -e2.x)).normalized()
        if ck.point_in_poly((ov[a] + ov[b]) / 2 + n2 * 1e-4, pts):
            n2 = -n2
        if part.face_normal(len(part.f) - 1).dot(U * n2.x + V * n2.y) < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def liner_relief(arch, side, r=LINER_R, x_out=0.862, a0=30.0, a1=150.0, segs=30):
    """Upper wheel-well liner relief inboard of the arch lip: a pie-slice sector about the axle line (radius r,
    from x_in + 2 cm to x_out, i.e. ~2 cm inside the body side at the arch top, lowest point ~0.47 m), giving the
    steered front tyre room for 3 cm of bump while the visible lip keeps the ARCH_R gap."""
    prof = [(arch['x_in'] + 0.02, 0.0), (arch['x_in'] + 0.02, r), (x_out, r), (x_out, 0.0)]
    p = ck.revolve(prof, segs, 'Underbody', theta0=math.radians(a0), theta1=math.radians(a1), caps=True)
    p = p.translated((0, arch['y'], arch['z']))
    return p if side > 0 else p.mirrored_x()


def cutters(S0):
    """Recessed lower intake + corner air curtains (front) and the front wheel-well liner reliefs."""
    return [pocket(S0, MOUTH, 'front', MOUTH_DEPTH, res=0.03),
            pocket(S0, CURTAIN_R, 'front', CURTAIN_DEPTH, res=0.0, max_len=0.012),
            pocket(S0, [(-x, z) for (x, z) in CURTAIN_R], 'front', CURTAIN_DEPTH, res=0.0, max_len=0.012),
            liner_relief(ARCHES[0], 1), liner_relief(ARCHES[0], -1)]


def puck(center, normal, pts2d, depth, mat, side_mat=None, u=None):
    """Flat face (fan) of a 2D outline centred at `center`, facing `normal`, plus a side band `depth` deep behind
    it: a thin glass / lens that stays solid from grazing angles with single-sided materials. pts2d in (u, w) where
    u = given horizontal axis (default normal x Z) and w = normal x u."""
    nrm = Vector(normal).normalized()
    c = Vector(center)
    uu = Vector(u).normalized() if u is not None else nrm.cross(Vector((0, 0, 1))).normalized()
    ww = nrm.cross(uu).normalized()
    if ww.z < 0:
        ww = -ww
    part = ck.Part()
    ci = part.vert(c)
    top = [part.vert(c + uu * p[0] + ww * p[1]) for p in pts2d]
    bot = [part.vert(c + uu * p[0] + ww * p[1] - nrm * depth) for p in pts2d]
    n = len(pts2d)
    for k in range(n):
        k2 = (k + 1) % n
        part.face((ci, top[k], top[k2]), mat)
        if part.face_normal(len(part.f) - 1).dot(nrm) < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
        part.face((top[k], bot[k], bot[k2], top[k2]), side_mat or mat)
        mid = (part.v[top[k]] + part.v[top[k2]]) / 2
        if part.face_normal(len(part.f) - 1).dot(mid - c) < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def closed_out(part):
    """Orient a closed Part outward: reverse every face if its signed volume is negative."""
    vol = 0.0
    for f in part.f:
        a = part.v[f[0]]
        for k in range(1, len(f) - 1):
            vol += a.dot(part.v[f[k]].cross(part.v[f[k + 1]]))
    if vol < 0:
        part.f = [tuple(reversed(f)) for f in part.f]
    return part

EYE = Vector((-0.370, -0.600, 1.095))        # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.370, -0.190, 0.815))        # steering wheel hub
COLUMN_TILT = 21.0                           # deg, column descends toward the dash
SW_R = 0.178                                 # steering wheel radius


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
    """Right half of the hood shut line: along the inboard side of the wing crown from the cowl, then across
    the nose to the centre line (the left half is the mirror)."""
    pts = [BODY.point(y, 5.12) for y in (Y_COWL + 0.055, 0.80, 1.05, YF, 1.50, 1.70, 1.85, 1.93)]
    for k in range(1, 9):
        u = k / 8.0
        pts.append(BODY.point(1.93 + 0.065 * (u ** 1.4), 5.12 + 2.88 * u))
    return pts


# blade sections (dy forward from the pocket floor, dz) - root sunk 4 mm into the floor, rounded nose, tipped down
FIN = [(-0.004, 0.0036), (0.014, 0.0012), (0.028, -0.0020), (0.036, -0.0048), (0.038, -0.0074), (0.034, -0.0094),
       (0.020, -0.0072), (0.004, -0.0042), (-0.004, -0.0036)]
VANE = [(-0.004, 0.0030), (0.012, 0.0008), (0.020, -0.0018), (0.022, -0.0040), (0.018, -0.0056), (0.006, -0.0038),
        (-0.004, -0.0030)]


def poly_span(pts, z):
    """x extent of a closed 2D outline (x, z) on the horizontal line at height z."""
    xs = []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        if (a[1] - z) * (b[1] - z) <= 0 and abs(b[1] - a[1]) > 1e-12:
            u = (z - a[1]) / (b[1] - a[1])
            xs.append(a[0] + (b[0] - a[0]) * u)
    return min(xs), max(xs)


def blade(S, outline, zf, prof, n=12, mat='Trim'):
    """Horizontal blade spanning a recessed opening at height zf: swept along X, every station sits on the pocket
    floor (ray hit through the opening), the end stations run 1 cm into the side walls."""
    F = S.frame('front')
    x0, x1 = poly_span(outline, zf)
    xa, xb = x0 + 0.004, x1 - 0.004
    xs = [xa + (xb - xa) * k / n for k in range(n + 1)]
    profs = []
    for x in xs:
        loc, nor = S.hit(F, x, zf)
        profs.append([(loc.y + dy, zf + dz) for (dy, dz) in prof])
    xs = [x0 - 0.010] + xs + [x1 + 0.010]
    profs = [profs[0]] + profs + [profs[-1]]
    return closed_out(ck.sweep_axis('x', xs, profs, mat))


def divider(S, x, outline, w=0.010, n=8):
    """Vertical centre divider of the lower intake (swept along Z on the pocket floor)."""
    F = S.frame('front')
    ys = [p[1] for p in outline]
    z0, z1 = min(ys), max(ys)
    zs = [z0 + 0.006 + (z1 - z0 - 0.012) * k / n for k in range(n + 1)]
    profs = []
    for z in zs:
        loc, nor = S.hit(F, x, z)
        yf = loc.y
        profs.append([(x - w / 2, yf - 0.004), (x + w / 2, yf - 0.004), (x + w / 2, yf + 0.030), (x + 0.3 * w, yf + 0.037),
                      (x - 0.3 * w, yf + 0.037), (x - w / 2, yf + 0.030)])
    zs = [z0 - 0.010] + zs + [z1 + 0.010]
    profs = [profs[0]] + profs + [profs[-1]]
    return closed_out(ck.sweep_axis('z', zs, profs, 'Trim'))


def body_details(car, S):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LTC, LBC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    D = ck.densify
    F = S.frame('front')
    B = S.frame('rear')

    # ================= front: recessed lower intake (boolean pocket, see cutters()) with blade fins and a centre
    # divider, recessed corner air curtains with vanes, a slim gloss lip around the mouth, carbon splitter
    for zf in (0.340, 0.384, 0.428):
        C.extend(blade(S, MOUTH, zf, FIN, n=12, mat='Trim'))
    C.extend(divider(S, 0.0, MOUTH))
    C.extend(S.rim(ck.offset_poly(D(MOUTH, 0.03), 0.002), 'front', width=0.008, offset=0.0028, depth=0.004,
                   mat='Trim', smooth=False))
    for zf in (0.352, 0.410):
        R.extend(blade(S, CURTAIN_R, zf, VANE, n=5, mat='Trim'))
    # carbon splitter following the plan outline of the nose just below the intake
    xs = [-0.80 + 1.60 * k / 32 for k in range(33)]
    front = []
    for x in xs:
        p = S.snap('front', x, 0.282)
        front.append((x, (p.y if p is not None else 1.80) + (0.030 - 0.022 * max(0.0, 1.0 - abs(x) / 0.45))))
    prof = front + [(0.72, 1.70), (-0.72, 1.70)]
    prof = list(reversed(prof)) if ck.poly_area(prof) < 0 else prof
    C.extend(ck.sweep_axis('z', [0.252, 0.268], prof, 'Carbon'))
    # bumper-to-wing split behind the lamp
    R.extend(S.line([(1.888, 0.660), (1.800, 0.604), (1.690, 0.566), (1.578, 0.530)], 'right', step=0.02))
    # hood shut line (both halves) and a pair of heat-extractor vents
    R.extend(S.line3d(hood_line(), step=0.025))
    vent = D(ck.fillet_poly([(0.215, 1.455), (0.395, 1.475), (0.395, 1.640), (0.235, 1.625)], 0.015, n=3), 0.025)
    R.extend(S.patch(vent, 'top', offset=0.0012, depth=0.004, res=0.0, mat='Grille', smooth=False))
    R.extend(S.rim(vent, 'top', width=0.008, offset=0.004, depth=0.004, mat='Trim', smooth=False))
    for k in range(5):
        yv = 1.488 + k * 0.032
        R.extend(S.line(D([(0.225, yv), (0.388, yv + 0.012)], 0.03, closed=False), 'top', width=0.006, offset=0.0035,
                        mat='Trim', smooth=False, step=0.028))

    # ================= headlamps: slim LED blades under the wing crowns, wrapping onto the wing
    hl_spec = [('front', 0.330, 0.616), ('front', 0.440, 0.634), ('front', 0.560, 0.648), ('front', 0.665, 0.657),
               ('right', 1.985, 0.668), ('right', 1.915, 0.677), ('right', 1.892, 0.666), ('right', 1.930, 0.648),
               ('right', 1.995, 0.628), ('front', 0.690, 0.606), ('front', 0.560, 0.598), ('front', 0.440, 0.593),
               ('front', 0.345, 0.592)]
    housing, inner, frame, p2 = lamp(S, hl_spec, 'Trim', 'Grille', inset=0.005)
    R.extend(housing, inner)
    # DRL strip 3 mm lower than before: its side walls used to share a plane with the inner lamp wall at the corner
    drl = snap_pts(S, [('front', 0.352, 0.608), ('front', 0.45, 0.624), ('front', 0.56, 0.637), ('front', 0.660, 0.645),
                       ('right', 1.985, 0.656), ('right', 1.925, 0.665)])
    LH.extend(S.line3d(drl, width=0.0065, offset=0.0062, mat='HeadlightLens', step=0.012))
    proj_centers = []
    for (x, z) in ((0.488, 0.613), (0.585, 0.621)):
        loc, nor = S.hit(F, x, z)
        c = loc + nor * 0.0060
        LH.extend(ck.disc(c, nor, 0.0125, 'HeadlightLens', n=16))
        R.extend(ck.disc(c - nor * 0.0010, nor, 0.0125, 'Chrome', n=16, ring_mat='Chrome', ring_w=0.004))
        proj_centers.append(c)
    hc = (proj_centers[0] + proj_centers[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))
    # slim gloss-black slot across the nose, linking the two lamp blades
    slot = D(ck.fillet_poly([(-0.338, 0.598), (0.338, 0.598), (0.338, 0.607), (-0.338, 0.607)], 0.003, n=2), 0.03)
    C.extend(S.patch(slot, 'front', offset=0.0030, depth=0.005, res=0.0, mat='Trim', smooth=False))

    # ================= side: door shut lines, flush handle, mirror, wing vent, carbon skirt, fuel flap
    R.extend(S.line([(0.604, 0.292), (0.612, 0.55), (0.617, 0.76), (0.606, 0.858)], 'right', step=0.02))   # door front
    R.extend(S.line([(-0.646, 0.292), (-0.653, 0.55), (-0.659, 0.76), (-0.661, 0.895)], 'right', step=0.02))  # door rear
    R.extend(S.patch(D(ck.rrect_pts(-0.440, 0.786, 0.165, 0.036, 0.016, n=3), 0.02), 'right', offset=0.0010,
                     depth=0.004, res=0.0, mat='Trim', smooth=False))
    R.extend(S.patch(D(ck.rrect_pts(-0.440, 0.788, 0.140, 0.018, 0.008, n=3), 0.02), 'right', offset=0.0050,
                     depth=0.006, res=0.0, mat='Paint', smooth=False))
    wvent = D(ck.fillet_poly([(0.735, 0.588), (0.925, 0.602), (0.948, 0.646), (0.762, 0.638)], 0.010, n=3), 0.02)
    R.extend(S.patch(wvent, 'right', offset=0.0012, depth=0.004, res=0.0, mat='Grille', smooth=False))
    R.extend(S.rim(wvent, 'right', width=0.008, offset=0.0050, depth=0.005, mat='Trim', smooth=False))
    for z in (0.607, 0.624):
        R.extend(S.line(D([(0.752, z), (0.935, z + 0.008)], 0.02, closed=False), 'right', width=0.0055, offset=0.0040,
                        mat='Trim', smooth=False, step=0.015))
    # mirror on the door, ahead of the glass: body-colour cap, black base/arm, mirror glass facing back
    mc = Vector((0.952, 0.468, 0.968))
    ry = 0.060

    def flat_back(p):
        # compress (do not fold) the rear half into a nearly flat back: keeps the face order -> no inside-out faces
        if p.y < -ry * 0.25:
            p.y = -ry * 0.25 + (p.y + ry * 0.25) * 0.08
        return p
    mirror = closed_out(ck.ellipsoid(mc, (0.100, ry, 0.048), 'Paint', nu=18, nv=9, exp=3.0, deform=flat_back))
    for fi in range(len(mirror.f)):
        if mirror.face_center(fi).z < mc.z - 0.024:
            mirror.m[fi] = 'Trim'
    R.extend(mirror)
    glass_pts = ck.superellipse_pts(0.0, 0.0, 0.080, 0.039, e=2.6, n=20)
    yg = -ry * 0.25 - 0.75 * ry * 0.08 - 0.002          # 2 mm proud of the flat back, with a 4 mm deep edge band
    R.extend(puck(mc + Vector((0, yg, 0)), (0, -1, 0), glass_pts, 0.004, 'Chrome', side_mat='Trim', u=(1, 0, 0)))
    base = S.snap('right', 0.500, 0.858)
    R.extend(ck.box_between(base + Vector((-0.012, 0.0, 0.004)), mc + Vector((-0.070, 0.004, -0.018)), 0.050, 0.020,
                            'Trim'))
    # carbon side skirt between the arches
    ys = [-0.915, -0.895, -0.82, -0.40, 0.0, 0.40, 0.82, 0.895, 0.915]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        k = 0.35 if abs(y) > 0.905 else (0.8 if abs(y) > 0.885 else 1.0)
        profs.append([(ws - 0.030, zs + 0.030), (ws + 0.004 * k, zs + 0.028), (ws + 0.011 * k, zs + 0.000),
                      (ws + 0.019 * k, zs - 0.050 * k), (ws + 0.015 * k, zs - 0.058 * k), (ws - 0.030, zs - 0.056)])
    R.extend(ck.sweep_axis('y', ys, profs, 'Carbon'))
    fuel = ck.rrect_pts(-1.070, 0.792, 0.105, 0.100, 0.026, n=3)
    C.extend(S.line(fuel, 'right', closed=True, smooth=False))                                       # right side only

    # ================= windscreen wipers + roof antenna + third brake light
    for (x0, x1, y0, y1, px) in ((-0.64, -0.08, Y_COWL - 0.040, Y_COWL - 0.068, -0.30),
                                 (-0.03, 0.50, Y_COWL - 0.046, Y_COWL - 0.072, 0.22)):
        a0 = S.snap('top', x0, y0) + Vector((0, 0, 0.012))
        a1 = S.snap('top', x1, y1) + Vector((0, 0, 0.012))
        C.extend(ck.box_between(a0, a1, 0.015, 0.010, 'Trim'))
        pivot = S.snap('top', px, Y_COWL + 0.030) + Vector((0, 0, 0.010))
        mid = (a0 + a1) / 2 + Vector((0, 0, 0.007))
        C.extend(ck.box_between(pivot, mid, 0.011, 0.007, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.015, 0.015, 0.009), 'Trim', nu=10, nv=6))
    # shark-fin antenna well ahead of the third brake light (they used to overlap)
    ap = S.snap('top', 0.0, RW_TOP + 0.200)
    C.extend(ck.ellipsoid((0.0, ap.y, ap.z + 0.010), (0.020, 0.072, 0.036), 'Trim', nu=12, nv=8,
                          deform=lambda p: Vector((p.x * (1.0 - 0.6 * max(0.0, p.z) / 0.036), p.y - 0.6 * max(0.0, p.z),
                                                   max(p.z, -0.004)))))
    # third brake light at the rear edge of the carbon roof: black housing 3 mm proud of the roof, lens 2.2 mm
    # above the housing; both conform to the roof crown (interior grid points) so nothing is coplanar
    yb = RW_TOP + 0.022
    C.extend(S.patch(D(ck.rrect_pts(0.0, yb, 0.330, 0.026, 0.010, n=3), 0.02), 'top', offset=0.0030, depth=0.004,
                     res=0.008, mat='Trim', smooth=False))
    LBC.extend(S.patch(D(ck.rrect_pts(0.0, yb, 0.306, 0.012, 0.0055, n=3), 0.02), 'top', offset=0.0052, depth=0.0035,
                       res=0.008, mat='BrakeLens', smooth=False))

    # ================= rear: full-width lamp bar under the ducktail, boot lid, plate, diffuser, exhausts
    bar = D(ck.fillet_poly([(-0.758, 0.866), (0.758, 0.866), (0.770, 0.889), (0.752, 0.903), (-0.752, 0.903),
                            (-0.770, 0.889)], [0.006, 0.006, 0.008, 0.006, 0.006, 0.008], n=3), 0.04)
    C.extend(S.patch(ck.offset_poly(bar, 0.006), 'rear', offset=0.0020, depth=0.005, res=0.0, mat='Trim', smooth=False))
    LT.extend(S.patch(bar, 'rear', offset=0.0042, depth=0.004, res=0.0, mat='TaillightLens', smooth=False))
    brake = D(ck.fillet_poly([(0.535, 0.872), (0.748, 0.872), (0.760, 0.888), (0.745, 0.897), (0.535, 0.897)],
                             0.004, n=2), 0.03)
    LB.extend(S.patch(brake, 'rear', offset=0.0058, depth=0.003, res=0.0, mat='BrakeLens', smooth=False))
    for x in (0.12, 0.24, 0.36, 0.48):                    # dark segment lines across the light bar (LED look)
        R.extend(S.patch(ck.rrect_pts(x, 0.8845, 0.004, 0.034, 0.0015, n=1), 'rear', offset=0.0060, depth=0.003,
                         res=0.0, mat='Trim', smooth=False))
    # boot lid: deck sides, rear face lower edge; bumper split from the rear arch around the corner
    R.extend(S.line3d([BODY.point(y, 5.0) for y in (Y_RW - 0.04, -1.85, -2.00, -2.10, -2.14)], step=0.025))
    R.extend(S.line([(0.640, 0.960), (0.640, 0.860), (0.636, 0.800), (0.600, 0.776), (0.300, 0.774), (0.0, 0.774)],
                    'rear', step=0.02))
    R.extend(S.line([(-1.556, 0.568), (-1.700, 0.598), (-1.900, 0.610), (-2.030, 0.612)], 'right', step=0.025))
    plate = D(ck.rrect_pts(0.0, 0.660, 0.525, 0.118, 0.012, n=2), 0.05)
    C.extend(S.patch(plate, 'rear', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    C.extend(S.rim(plate, 'rear', width=0.011, offset=0.0055, depth=0.005, mat='Trim', smooth=False))
    # black lower valance with carbon diffuser insert, fins, reflectors, centre reverse lamp
    valance = D(ck.fillet_poly([(-0.770, 0.340), (0.770, 0.340), (0.785, 0.380), (0.760, 0.478), (-0.760, 0.478),
                                (-0.785, 0.380)], [0.0, 0.0, 0.03, 0.02, 0.02, 0.03], n=4), 0.05)
    C.extend(S.patch(valance, 'rear', offset=0.0032, depth=0.006, res=0.024, mat='Trim', smooth=False))
    diff = D(ck.fillet_poly([(-0.470, 0.342), (0.470, 0.342), (0.445, 0.452), (-0.445, 0.452)], 0.015, n=3), 0.04)
    C.extend(S.patch(diff, 'rear', offset=0.0058, depth=0.007, res=0.030, mat='Carbon', smooth=False))
    for x in (-0.30, -0.12, 0.12, 0.30):
        ysf = [-2.190, -2.12, -1.98, -1.84]
        profs = []
        for y in ysf:
            zb = BODY.params_at(max(y, -2.155))['zb']
            top = zb + 0.030
            bot = zb - (0.036 if y < -2.15 else (0.030 if y < -2.0 else 0.012))
            profs.append([(x - 0.004, bot), (x + 0.004, bot), (x + 0.004, top), (x - 0.004, top)])
        C.extend(ck.sweep_axis('y', ysf, profs, 'Carbon'))
    for sx in (1, -1):
        LTC.extend(S.patch(ck.rrect_pts(sx * 0.690, 0.505, 0.090, 0.018, 0.008, n=2), 'rear', offset=0.0048, depth=0.005,
                           res=0.008, mat='TaillightLens', smooth=False))
    LR.extend(S.patch(ck.rrect_pts(0.0, 0.425, 0.120, 0.020, 0.008, n=2), 'rear', offset=0.0080, depth=0.005,
                      res=0.0, mat='ReverseLens', smooth=False))
    # dual exhaust tips at the corners, in dark surrounds set into the valance
    tips = []
    for x in (0.600, -0.600):
        loc, nor = S.hit(B, x, 0.405)
        sur = D(ck.superellipse_pts(x, 0.405, 0.066, 0.052, e=3.2, n=24), 0.02)
        C.extend(S.patch(sur, 'rear', offset=0.0065, depth=0.006, res=0.02, mat='Grille', smooth=False))
        p0 = Vector((x, loc.y + 0.08, 0.405))
        p1 = Vector((x, loc.y - 0.014, 0.405))
        C.extend(ck.tube(p0, p1, 0.044, 0.037, 'Chrome', 'Trim', n=24, inner_depth=0.06))
        C.extend(ck.disc(p0, (0.0, 1.0, 0.0), 0.044, 'Trim', n=24))       # closed back end (no open tube)
        tips.append(p1)
    car.socket('Socket_Exhaust', tips[0])
    car.socket('Socket_Exhaust2', tips[1])

    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LTC)
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR)


def accent(part, src='Interior', dst='InteriorAccent'):
    part.m = [dst if m == src else m for m in part.m]
    return part


def seat_section(hw, h, b, roll=0.026, r_bot=0.020, flat=0.38, crown=0.007, sub=3):
    """Closed, smooth (x, v) section of a seat cushion / backrest: base at v=0, centre insert top at v=h (slightly
    crowned), side bolsters rising by b with rounded tops; Catmull-Rom resampled (no facets)."""
    q = [(0.0, h + crown), (flat * hw, h), (0.55 * hw, h + 0.25 * b), (0.70 * hw, h + 0.78 * b),
         (0.84 * hw, h + b), (0.95 * hw, h + b - 0.42 * roll), (hw, h + b - roll)]
    top = ck.cr_resample([Vector(p) for p in q], closed=False, sub=sub, corners=(6,))   # only the top is subdivided
    half = top + [Vector((hw, r_bot)), Vector((hw - r_bot, 0.0)), Vector((0.0, 0.0))]
    return half + [Vector((-p.x, p.y)) for p in reversed(half[1:-1])]


def seat_mats(loop, hw, h, accent=True):
    """Material per section segment: centre insert 'Interior', red piping 'InteriorAccent', bolsters dark."""
    out = []
    n = len(loop)
    for k in range(n):
        a, b = loop[k], loop[(k + 1) % n]
        mx, my = abs(a.x + b.x) / 2 / hw, (a.y + b.y) / 2
        if my > h * 0.7 and mx < 0.46:
            out.append('Interior')
        elif accent and my > h * 0.7 and mx < 0.54:
            out.append('InteriorAccent')
        else:
            out.append('InteriorDark')
    return out


def sport_seat(x, y_front, y_back, z_base, width=0.52, recline=20.0, back_h=0.82, head=True, sub=2,
               runners=True, hw_top=0.135):
    """Sculpted sport bucket (front) / small rear bucket (head=False): smooth cushion with thigh bolsters, winged
    backrest with an integrated headrest, red piping, seat pan + runners. Every closed piece is oriented outward
    (signed volume), so the seat is solid with single-sided materials."""
    part = ck.Part()
    hw0 = width / 2
    L = y_front - y_back
    if head:
        ys = [y_front, y_front - 0.010, y_front - 0.030, y_front - 0.070, y_front - 0.15, (y_front + y_back) / 2,
              y_back + 0.14, y_back + 0.06, y_back + 0.02, y_back]
    else:
        ys = [y_front, y_front - 0.010, y_front - 0.030, y_front - 0.080, (y_front + y_back) / 2, y_back + 0.05,
              y_back]
    profs = []
    for k, yy in enumerate(ys):
        f = (y_front - yy) / L
        sc = (0.50, 0.84, 0.96)[k] if k < 3 else 1.0
        hw = hw0 * (0.92 if k == 0 else (0.97 if k == 1 else 1.0))
        b = (0.046 + 0.024 * math.sin(math.pi * min(1.0, f * 1.35))) * (hw0 / 0.26)
        sec = seat_section(hw, 0.082 * sc, b * sc, sub=sub)
        dz = 0.034 * (1 - f) ** 1.5
        profs.append([(x + p.x, z_base + dz + p.y) for p in sec])
    mats = seat_mats(seat_section(hw0, 0.082, 0.06, sub=sub), hw0, 0.082)
    part.extend(closed_out(ck.sweep_axis('y', ys, profs, mats, cap_mat='InteriorDark')))
    # backrest (built upright along Z, depth toward +Y, then reclined about X at its base)
    k_w = hw0 / 0.26
    if head:
        zs = [0.0, 0.025, 0.10, 0.22, 0.34, 0.45, 0.53, 0.585, 0.625, 0.66, 0.72, back_h - 0.05, back_h - 0.015, back_h]
    else:
        zs = [0.0, 0.025, 0.10, 0.22, 0.32, 0.40, back_h - 0.06, back_h - 0.02, back_h]
    profs = []
    for zz in zs:
        u = zz / back_h
        if head:
            if zz <= 0.34:
                s = ck.smoothstep(0.08, 0.34, zz)
                hw, b = (0.250 + 0.012 * s) * k_w, (0.090 + 0.022 * s) * k_w
            elif zz <= 0.625:
                s = ck.smoothstep(0.34, 0.625, zz)
                hw, b = ck.lerp(0.262 * k_w, hw_top + 0.010, s), ck.lerp(0.112 * k_w, 0.018, s)
            else:
                s = ck.smoothstep(0.625, back_h, zz)
                hw, b = hw_top + 0.010 * (1 - s), 0.018 - 0.006 * s
        else:
            s = ck.smoothstep(0.05, 0.30, zz)
            hw, b = (0.250 + 0.010 * s) * k_w, (0.060 + 0.020 * s) * k_w * (1.0 - 0.6 * ck.smoothstep(0.32, back_h, zz))
        t = 0.082 - 0.016 * u
        if zz == 0.0:
            hw, t = hw * 0.96, t * 0.9
        if zz == back_h:
            hw, t, b = hw * 0.80, t * 0.72, b * 0.5
        elif zz == zs[-2]:
            hw, t = hw * 0.95, t * 0.93
        sec = seat_section(hw, t, b, roll=0.028 if zz < 0.5 else 0.020, sub=sub)
        profs.append([(x + p.x, p.y) for p in sec])
    mats = seat_mats(seat_section(0.26 * k_w, 0.08, 0.10, sub=sub), 0.26 * k_w, 0.08)
    back = closed_out(ck.sweep_axis('z', zs, profs, mats, cap_mat='InteriorDark'))
    M = Matrix.Translation((0, y_back - 0.035, z_base + 0.055)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    part.extend(back.transformed(M))
    # seat pan + runners
    if runners:
        part.extend(closed_out(ck.box_between((x, y_front - 0.08, z_base - 0.045), (x, y_back + 0.05, z_base - 0.045),
                                              width * 0.70, 0.09, 'InteriorDark')))
        for sx in (-1, 1):
            part.extend(closed_out(ck.box_between((x + sx * 0.16 * k_w, y_front + 0.02, z_base - 0.095),
                                                  (x + sx * 0.16 * k_w, y_back - 0.02, z_base - 0.095), 0.032, 0.026,
                                                  'InteriorDark')))
    else:
        part.extend(closed_out(ck.box_between((x, y_front - 0.05, z_base - 0.040), (x, y_back + 0.03, z_base - 0.040),
                                              width * 0.86, 0.10, 'InteriorDark')))
    return part


def rv_mirror(mc=Vector((0.0, -0.040, 1.148)), mount=Vector((0.0, -0.074, 1.218))):
    """Interior rear-view mirror: rounded housing, chrome glass facing the driver, stalk up to a mount pad just
    under the windscreen glass at the header."""
    part = ck.Part()
    outline = ck.superellipse_pts(0.0, 0.0, 0.118, 0.033, e=3.4, n=28)
    stations = [(-0.019, 0.93), (-0.016, 1.0), (-0.004, 1.03), (0.009, 0.97), (0.020, 0.74)]
    profs = [[(mc.x + p.x * s, mc.z + p.y * s) for p in outline] for (dy, s) in stations]
    part.extend(closed_out(ck.sweep_axis('y', [mc.y + dy for (dy, s) in stations], profs, 'InteriorDark')))
    # mirror glass 1.5 mm proud of the housing end, with a 3 mm edge band (solid from grazing angles)
    part.extend(puck(mc + Vector((0, -0.0205, 0)), (0, -1, 0), [(p.x * 0.86, p.y * 0.76) for p in outline], 0.003,
                     'Chrome', side_mat='InteriorDark', u=(1, 0, 0)))
    part.extend(ck.rod(mc + Vector((0.0, 0.006, 0.024)), mount + Vector((0.0, 0.004, -0.006)), 0.0075, 'InteriorDark',
                       n=10))
    part.extend(closed_out(ck.ellipsoid(mount, (0.032, 0.026, 0.010), 'InteriorDark', nu=12, nv=6)))
    return part


def interior(car):
    I = ck.Part()
    # ---- dashboard (profile in (y, z) swept across X): low wide top, padded face, lower knee panel
    dash = [(0.660, 0.858), (0.460, 0.886), (0.300, 0.896), (0.200, 0.890), (0.150, 0.874), (0.128, 0.848),
            (0.122, 0.800), (0.128, 0.750), (0.150, 0.700), (0.210, 0.620), (0.300, 0.545), (0.430, 0.480),
            (0.560, 0.500), (0.660, 0.620)]
    dmats = ['InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorDark', 'InteriorAccent',
             'InteriorDark', 'Interior', 'Interior', 'Interior', 'InteriorDark', 'InteriorDark', 'InteriorDark',
             'InteriorDark']
    xs = [-0.735, -0.720, -0.55, -0.2, 0.0, 0.2, 0.55, 0.720, 0.735]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < 0.73 else 0.01
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # driver's binnacle: two dials + small centre display, visor above
    xb = [HUB.x - 0.175, HUB.x - 0.165, HUB.x + 0.165, HUB.x + 0.175]
    visor = [(0.210, 0.902), (0.098, 0.926), (0.066, 0.920), (0.070, 0.909), (0.140, 0.897)]
    I.extend(ck.sweep_axis('x', xb, [[(y + (0.006 if k in (0, 3) else 0.0), z - (0.006 if k in (0, 3) else 0.0))
                                      for (y, z) in visor] for k in range(4)], 'InteriorDark'))
    I.extend(ck.box_between((HUB.x - 0.160, 0.119, 0.836), (HUB.x + 0.160, 0.119, 0.836), 0.006, 0.124, 'InteriorDark',
                            up=(0, 0, 1)))
    for (dx, nt, r) in ((-0.080, 9, 0.050), (0.080, 11, 0.050)):
        c = Vector((HUB.x + dx, 0.114, 0.838))
        I.extend(ck.gauge(c, EYE - c, r, n_ticks=nt))
    scr = ck.Part()
    q = [scr.vert(Vector((HUB.x + x, 0.1145, z))) for (x, z) in ((-0.017, 0.822), (0.017, 0.822), (0.017, 0.856),
                                                                  (-0.017, 0.856))]
    scr.face(q, 'Gauge')
    scr.orient(0, ref=Vector((HUB.x, 0.2, 0.81)))
    I.extend(scr)
    # centre stack: floating screen, vents
    # floating centre screen, leaning back (faces the occupants and slightly up, so it is never seen from behind
    # through the windscreen), on a short stem into the dash top
    I.extend(closed_out(ck.box_between((0.0, 0.165, 0.905), (0.0, 0.180, 0.990), 0.230, 0.012, 'InteriorDark',
                                       up=(0, 1, 0))))
    I.extend(closed_out(ck.box_between((0.0, 0.180, 0.870), (0.0, 0.172, 0.915), 0.060, 0.014, 'InteriorDark',
                                       up=(0, 1, 0))))
    scr = ck.Part()
    for (x0, x1, z0, z1, off) in ((-0.105, 0.105, 0.912, 0.982, 0.0012), (-0.092, -0.010, 0.968, 0.972, 0.0022),
                                  (-0.092, -0.040, 0.952, 0.955, 0.0022), (0.010, 0.090, 0.925, 0.965, 0.0022),
                                  (-0.092, -0.020, 0.925, 0.928, 0.0022)):
        m = 'InteriorDark' if off < 0.002 else 'Gauge'
        q = [scr.vert(Vector((x, 0.165 + 0.1765 * (z - 0.905) - 0.0060 - off, z)))
             for (x, z) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
        scr.face(q, m)
    scr.orient(0, ref=Vector((0, 0.3, 0.95)))
    I.extend(scr)
    for x in (-0.60, -0.10, 0.10, 0.60):
        I.extend(ck.box_between((x - 0.050, 0.138, 0.768), (x + 0.050, 0.138, 0.768), 0.030, 0.034, 'InteriorDark'))
    # steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.30, 0.070, 0.080, 'InteriorDark'))
    # centre console: tall tunnel with a manual shifter, handbrake and armrest
    cys = [0.50, 0.38, 0.20, -0.05, -0.30, -0.42, -0.70]
    tops = [0.66, 0.56, 0.47, 0.46, 0.48, 0.54, 0.54]
    profs = [[(-0.105, 0.17), (0.105, 0.17), (0.110, t - 0.03), (0.090, t), (-0.090, t), (-0.110, t - 0.03)] for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'InteriorDark', 'Interior',
                                             'InteriorDark']))
    I.extend(ck.box_between((0.0, 0.10, 0.462), (0.0, 0.07, 0.640), 0.012, 0.012, 'Chrome'))            # shifter
    I.extend(ck.ellipsoid((0.0, 0.068, 0.655), (0.023, 0.023, 0.023), 'InteriorDark', nu=12, nv=8))
    I.extend(ck.ellipsoid((0.0, 0.10, 0.466), (0.042, 0.052, 0.012), 'InteriorDark', nu=12, nv=6))       # boot
    I.extend(ck.box_between((0.0, -0.18, 0.475), (0.0, -0.36, 0.530), 0.030, 0.026, 'InteriorDark'))     # handbrake
    # seats: two sculpted sport buckets with integrated headrests + two tiny rear buckets between the wheel tubs
    for x in (-0.370, 0.370):
        I.extend(sport_seat(x, -0.020, -0.500, 0.285, width=0.52, recline=20.0, back_h=0.82))
    for x in (-0.300, 0.300):
        I.extend(sport_seat(x, -0.985, -1.265, 0.300, width=0.40, recline=27.0, back_h=0.50, head=False,
                            runners=False))
    # parcel shelf behind the rear seat backs, under the fastback glass base (the boot below is closed by the
    # inner shell)
    I.extend(closed_out(ck.box_between((0.0, -1.545, 0.872), (0.0, -1.735, 0.872), 1.20, 0.016, 'InteriorDark')))
    # door cards: armrest, accent strip, pull handle, speaker; mirrored
    door = ck.Part()
    ays = [0.55, 0.52, -0.56, -0.60]
    door.extend(ck.sweep_axis('y', ays, [(0.785, 0.640), (0.805, 0.602), (0.850, 0.600), (0.850, 0.668), (0.792, 0.668)],
                              'InteriorDark'))
    door.extend(ck.box_between((0.846, 0.50, 0.745), (0.846, -0.50, 0.745), 0.010, 0.020, 'InteriorAccent',
                               up=(1, 0, 0)))
    door.extend(ck.box_between((0.835, 0.20, 0.705), (0.835, 0.06, 0.705), 0.024, 0.020, 'Interior'))
    door.extend(ck.disc((0.828, 0.36, 0.44), (-1, 0, 0), 0.055, 'InteriorDark', n=16))
    I.extend(door, door.mirrored_x())
    # pedals
    for x, w in ((-0.47, 0.055), (-0.37, 0.075), (-0.27, 0.055)):
        I.extend(ck.box_between((x, 0.56, 0.235), (x, 0.52, 0.335), w, 0.012, 'InteriorDark'))
    # sun visors + rear-view mirror
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.13, -0.120, 1.196), (s * 0.46, -0.120, 1.196), 0.13, 0.012, 'Interior'))
    # rounded rear-view mirror; its mount pad sits 2 mm under the windscreen glass (glass is inset 6 mm)
    ym = -0.074
    zg = BODY.point(ym + 0.034, 8.0).z - 0.006        # glass height at the front end of the mount pad (lowest)
    I.extend(rv_mirror(mc=Vector((0.0, -0.036, zg - 0.078)), mount=Vector((0.0, ym, zg - 0.012))))
    car.add('Interior', I)
    car.obj_specs['Interior']['sharp'] = 60.0
    # steering wheel (separate object, origin at the hub, local +Y = column toward the dash): 3 spokes, flat bottom
    car.add('SteeringWheel', ck.steering_wheel_part(R=SW_R, flat_bottom=True, hub_r=0.056,
                                                    spokes=((0.0, 0.046), (180.0, 0.046), (270.0, 0.036))),
            location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W_F, rim_d_in=18, spokes=10, style='split', segs=48, rim_segs=40,
                  spoke_thick=0.022, spoke_dish=0.030, hub_r=0.060, nuts=5, disc_r=0.172, caliper_angle=150.0,
                  caliper_span=46.0,
                  split=dict(split_f=0.40, stem_w=(0.030, 0.006), arm_w=(0.0135, 0.004), arm_gap=0.050),
                  rear=dict(W=WHEEL_W_R, disc_r=0.165, caliper_span=40.0))


def bead_seal(W, rim_d_in=18, segs=24):
    """Outboard bead seal (RIGHT-side wheel frame): a hidden rubber band from inside the tyre bead down under the
    rim flange curl. ck.build_wheel leaves the tyre bead edge open ~1 cm inboard of the flange, so steep views
    from above looked through that slot into the back faces of the barrel. Normals face outward (+x / +r)."""
    rr = rim_d_in * 0.0254 / 2.0
    lip_x = W / 2.0 - 0.012
    return ck.revolve([(lip_x - 0.011, rr + 0.010), (lip_x - 0.004, rr - 0.006)], segs, 'Rubber')


def build():
    paint = (0.807, 0.807, 0.776)             # #E8E8E4 pearl white (linear)
    mats = ck.default_materials(paint=paint, paint_metallic=0.0, paint_rough=0.34, paint_coat=0.45,
                                rim=(0.125, 0.130, 0.138), rim_metallic=1.0, rim_rough=0.30,
                                caliper=(0.62, 0.030, 0.018),
                                interior=(0.050, 0.050, 0.054), interior_dark=(0.013, 0.013, 0.015))
    mats['Paint']['coat_rough'] = 0.08
    mats['Carbon'] = dict(base=(0.009, 0.009, 0.011), metallic=0.0, roughness=0.48, coat=0.15, coat_rough=0.15)
    mats['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.03, alpha=0.30, double_sided=True)
    mats['InteriorAccent'] = dict(base=(0.30, 0.018, 0.016), roughness=0.62)
    car = ck.CarAssembly(CAR_ID, CAR_NAME, mats)
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006, cutters=cutters, frame_backs=0.0006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Glass', shell.glass)
    car.add('Interior', shell.inner)
    if STAGE != 'body':
        body_details(car, shell.surface)
        interior(car)
        ck.add_wheels(car, WHEEL_SPEC, axles=dict(front=(YF, TRACK_F / 2), rear=(YR, TRACK_R / 2)))
        for key, W in (('F', WHEEL_W_F), ('R', WHEEL_W_R)):
            seal = bead_seal(W)
            car.add('Wheel_%sR' % key, seal)
            car.add('Wheel_%sL' % key, seal.mirrored_x())
        car.socket('Socket_CamHood', (0.0, 0.80, 0.995))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.06, 0.46))
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
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.92 and abs(v.y - 0.47) > 0.13)   # mirrors excluded
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
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'compact sports coupe (2+2)', 'drivetrain': 'RWD',
        'engine': 'front-mid', 'doors': 2, 'seats': 4, 'source_blend': 'Opus55ForzaUltracodeEffort.blend',
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
        'rim_diameter_in': 18,
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
        'default_paint': {'hex': '#E8E8E4', 'linear_rgb': [0.807, 0.807, 0.776], 'finish': 'satin pearl'},
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
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.3, 6.0, 1.95), target=(0.0, 0.0, 0.52),
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


