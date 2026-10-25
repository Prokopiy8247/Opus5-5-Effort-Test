"""Kestrel R4 - compact hot hatch, 3-door, FWD, front engine (car #1 of Sunward Roads).

Rebuilds Cars/Car_kestrel_r4 from scratch with tools/blender/car_kit.py, then (optionally) renders the
QA hero image, exports assets/imported/cars/kestrel_r4.glb + .json and saves the master .blend.

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\kestrel_r4.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking).

Spec: L 4.05, W 1.78 (body), H 1.44, wheelbase 2.55, track 1.53 / 1.52, wheel R 0.315 (18", 225 tyres).
Rework (review fixes): hot-hatch silhouette (roof falls toward a raked rear glass under the spoiler,
rising belt into a thick C-pillar, wide rear haunches, gloss-black roof), recessed honeycomb mouth,
slot grille, corner intakes and plate recess (boolean pockets), a splitter that stays ahead of the front
tyres at full lock, sculpted bucket seats, a rounded rear-view mirror and the Kestrel sport wheel.
"""
import sys
import os
import math
import importlib

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender'))
import car_kit as ck  # noqa: E402
importlib.reload(ck)
from mathutils import Vector, Matrix, geometry  # noqa: E402

CAR_ID = 'kestrel_r4'
CAR_NAME = 'Kestrel R4'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.55
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions
TRACK_F, TRACK_R = 1.53, 1.52
WHEEL_R, WHEEL_W = 0.315, 0.225
ARCH_R, ARCH_Z = 0.346, 0.322

# ---------------------------------------------------------------- body stations (rear -> front)
# Hot-hatch side view: roof crown peaks over the B-pillar (1.44) and falls toward a 35-deg rear glass
# under the roof spoiler; rising belt line that kicks up into a thick forward-leaning C-pillar; wide
# rear haunches (shoulder 3 cm wider than the doors) and front wings; short, plan-tapered nose.
NOSE_Y, TAIL_Y = 2.072, -1.985
Y_HEADER = 0.130          # windscreen header
Y_COWL = 1.020            # windscreen base / bonnet rear edge
Y_ROOF_END = -1.620       # roof end = rear glass top (spoiler base)
Y_RW_BASE = -1.865        # rear glass base (tailgate crease)
S = [
    # ---- tail (rear face = cap) and tailgate top
    dict(y=-1.940, zb=0.285, wb=0.48, zs=0.330, ws=0.742, zw=0.560, ww=0.770, zh=0.842, wh=0.752,
         zg=0.902, wg=0.690, zr=0.926, wr=0.520, zc=0.936, ks={4: 0.3, 6: 0.15}),
    dict(y=-1.905, zb=0.262, wb=0.52, zs=0.312, ws=0.790, zw=0.565, ww=0.812, zh=0.858, wh=0.795,
         zg=0.928, wg=0.725, zr=0.956, wr=0.545, zc=0.966, ks={4: 0.45}),
    dict(y=Y_RW_BASE, zb=0.240, wb=0.55, zs=0.300, ws=0.812, zw=0.575, ww=0.838, zh=0.876, wh=0.822,
         zg=0.952, wg=0.748, zr=0.990, wr=0.540, zc=1.000, sharp=dict(zc=0.5, zr=0.4), ks={4: 0.7, 6: 0.2}),
    # ---- raked rear glass (36 deg from vertical), C-pillars leaning in (tumblehome)
    dict(y=-1.780, zb=0.205, wb=0.59, zs=0.285, ws=0.828, zw=0.585, ww=0.862, zh=0.900, wh=0.850,
         zg=0.995, wg=0.765, zr=1.100, wr=0.556, zc=1.112, ks={4: 0.85}),
    dict(y=-1.700, zb=0.180, wb=0.61, zs=0.275, ws=0.834, zw=0.592, ww=0.876, zh=0.915, wh=0.864,
         zg=1.030, wg=0.772, zr=1.212, wr=0.566, zc=1.225),
    dict(y=Y_ROOF_END, zb=0.165, wb=0.62, zs=0.268, ws=0.836, zw=0.597, ww=0.884, zh=0.925, wh=0.871,
         zg=1.050, wg=0.775, zr=1.318, wr=0.576, zc=1.335, sharp=dict(zc=0.7, zr=0.5), ks={6: 0.3}),
    # ---- rear haunch (widest point of the car, wide shoulder), belt kicks up into the C-pillar
    dict(y=-1.450, zb=0.150, zs=0.262, ws=0.838, zw=0.600, ww=0.889, zh=0.930, wh=0.874,
         zg=1.058, wg=0.776, zr=1.336, wr=0.594, zc=1.368),
    dict(y=-1.275, zb=0.140, zs=0.255, ws=0.838, zw=0.600, ww=0.890, zh=0.932, wh=0.874,
         zg=1.056, wg=0.778, zr=1.352, wr=0.610, zc=1.392),
    dict(y=-1.000, zb=0.135, zs=0.246, ws=0.828, zw=0.585, ww=0.878, zh=0.930, wh=0.860,
         zg=1.036, wg=0.784, zr=1.368, wr=0.632, zc=1.418),
    # ---- doors (pulled in between the haunch and the wing); K3 = crisp lower door crease rising rearward
    dict(y=-0.700, zs=0.240, ws=0.800, zw=0.525, ww=0.857, zh=0.925, wh=0.840,
         zg=1.014, wg=0.790, zr=1.376, wr=0.650, zc=1.436, ks={3: 0.85}),
    dict(y=-0.350, zs=0.238, ws=0.794, zw=0.502, ww=0.855, zh=0.920, wh=0.836,
         zg=1.002, wg=0.793, zr=1.378, wr=0.660, zc=1.442, ks={3: 0.92}),
    dict(y=Y_HEADER, zs=0.238, ws=0.796, zw=0.495, ww=0.857, zh=0.912, wh=0.837, zg=0.990, wg=0.796, zr=1.355,
         wr=0.668, zc=1.418, sharp=dict(zc=0.5, zr=0.5, wr=0.3), ks={3: 0.92}),
    dict(y=0.580, zs=0.240, ws=0.804, zw=0.500, ww=0.862, zh=0.905, wh=0.843, zg=0.978, wg=0.799, zr=1.165,
         wr=0.708, zc=1.205, ks={3: 0.85}),
    dict(y=Y_COWL, zs=0.245, ws=0.816, zw=0.525, ww=0.869, zh=0.898, wh=0.851, zg=0.962, wg=0.800, zr=0.975,
         wr=0.752, zc=0.988, sharp=dict(zc=1.0, zr=1.0, wr=1.0), ks={3: 0.6}),
    # ---- bonnet between crisp wing crowns; two crisp power lines (K6 slightly raised) converging
    #      toward the slot grille; falls toward a lower nose
    dict(y=1.110, zb=0.145, wb=0.61, zs=0.250, ws=0.822, zw=0.545, ww=0.874, zh=0.892, wh=0.856,
         zg=0.954, wg=0.798, zr=0.977, wr=0.700, zc=0.977, ks={5: 0.55, 6: 0.5}),
    dict(y=1.275, zb=0.150, wb=0.60, zs=0.256, ws=0.824, zw=0.556, ww=0.880, zh=0.880, wh=0.860,
         zg=0.940, wg=0.792, zr=0.960, wr=0.640, zc=0.955, ks={5: 0.6, 6: 0.7}),
    dict(y=1.500, zb=0.160, wb=0.59, zs=0.260, ws=0.820, zw=0.550, ww=0.877, zh=0.848, wh=0.856,
         zg=0.900, wg=0.785, zr=0.916, wr=0.590, zc=0.911),
    dict(y=1.700, zb=0.172, wb=0.58, zs=0.262, ws=0.808, zw=0.540, ww=0.866, zh=0.812, wh=0.845,
         zg=0.856, wg=0.772, zr=0.868, wr=0.550, zc=0.863),
    # ---- plan-tapered nose
    dict(y=1.860, zb=0.188, wb=0.56, zs=0.263, ws=0.786, zw=0.525, ww=0.841, zh=0.776, wh=0.815,
         zg=0.810, wg=0.742, zr=0.821, wr=0.515, zc=0.817, ks={5: 0.5, 6: 0.6}),
    dict(y=1.960, zb=0.202, wb=0.52, zs=0.265, ws=0.740, zw=0.510, ww=0.793, zh=0.746, wh=0.765,
         zg=0.771, wg=0.695, zr=0.779, wr=0.490, zc=0.776, ks={6: 0.45}),
    dict(y=2.020, zb=0.214, wb=0.47, zs=0.268, ws=0.674, zw=0.500, ww=0.723, zh=0.724, wh=0.696,
         zg=0.745, wg=0.628, zr=0.750, wr=0.470, zc=0.749, ks={4: 0.5, 5: 0.3, 6: 0.3}),
]

WARP_Y = -1.250           # side glass rear edge (base y): leans forward from the belt to the roof rail
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),        # windscreen
    dict(bands=(5, 5), y=(WARP_Y, 0.800), role='glass'),           # door + rear quarter glass
    dict(bands=(5, 5), y=(0.800, Y_COWL), role='trim'),            # mirror sail
    dict(bands=(5, 5), y=(-0.470, -0.400), role='trim'),           # B-pillar (black)
    dict(bands=(6, 7), y=(Y_RW_BASE, Y_ROOF_END), role='glass'),   # rear glass (wraps over the rails)
    dict(bands=(6, 7), y=(Y_ROOF_END, Y_HEADER), role='carbon'),   # gloss-black contrast roof
    dict(bands=(6, 6), y=(Y_HEADER, Y_COWL), role='carbon'),       # gloss-black A-pillars
    dict(bands=(6, 7), y=(Y_COWL, Y_COWL + 0.055), role='trim'),   # scuttle / cowl panel
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[3, 3, 5, 5, 2, 6, 2, 7],
    key_sharp=(0, 0.7, 0.5, 0.55, 0.85, 0.35, 0.4, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.46, tilt=9.0, k_edge=1.3, k_face=2.5, rings=8),
    tail=dict(y=TAIL_Y, z=0.60, tilt=4.0, k_edge=1.2, k_face=2.4, rings=8),
    step=0.054,
    rail=0.05,
    warps=[dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.390, -1.090), margin=0.22)],   # forward-leaning C-pillar
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.50), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.56)]
INNER = dict(y=(-1.915, 1.060), d=0.035, dy_ramp=(-1.70, -1.82),
             tubs=[(YR, ARCH_Z, ARCH_R + 0.03, 0.54), (YF, ARCH_Z, ARCH_R + 0.03, 0.48)])


EYE = Vector((-0.37, -0.23, 1.185))          # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.37, 0.24, 0.84))            # steering wheel hub
COLUMN_TILT = 22.0                           # deg, column descends toward the dash


def snap_pts(S, spec):
    out = []
    for view, a, b in spec:
        p = S.snap(view, a, b)
        if p is None:
            raise RuntimeError('snap miss %s %s %s' % (view, a, b))
        out.append(p)
    return out


# ---------------------------------------------------------------- recessed openings (boolean pockets)
# Outlines in view coordinates: 'front' = (x, z) seen from ahead, 'rear' = (x, z) seen from behind.
MOUTH = ck.fillet_poly([(-0.400, 0.252), (0.400, 0.252), (0.458, 0.278), (0.436, 0.405), (0.335, 0.462),
                        (-0.335, 0.462), (-0.436, 0.405), (-0.458, 0.278)], 0.022, n=3)      # lower grille
SLOT_Z = 0.650
SLOT = ck.rrect_pts(0.0, SLOT_Z, 0.720, 0.030, 0.0145, n=3)                                 # upper slot grille
INTAKE_R = ck.fillet_poly([(0.532, 0.292), (0.668, 0.282), (0.692, 0.316), (0.682, 0.425), (0.645, 0.452),
                           (0.580, 0.452), (0.546, 0.418)], 0.012, n=3)                      # corner intake
CURTAIN_R = ck.rrect_pts(0.688, 0.530, 0.022, 0.105, 0.0105, n=3)                           # corner air curtain
PLATE = ck.rrect_pts(0.0, 0.655, 0.530, 0.118, 0.014, n=3)                                  # rear plate recess


def pocket(Sx, outline, view, depth, wall_mat='Trim', back_mat='Grille', res=0.035, max_len=0.02, out=0.20):
    """Closed prism cutter for LoftBody.build(cutters=...): the outline (view coords) is projected onto the
    uncut shell; the pocket floor lies `depth` metres deeper along the view direction (it follows the
    curvature of the panel), the walls run parallel to the view direction. Returns a closed Part."""
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


def liner_relief(arch, side, r=0.358, x_out=0.838, a0=22.0, a1=158.0, segs=28):
    """Upper wheel-well liner relief (inboard of the arch lip): room for the steered front tyre with 3 cm
    of bump travel. A pie-slice sector about the axle line, only above ~0.45 m so the body skin is untouched."""
    prof = [(arch['x_in'] + 0.02, 0.0), (arch['x_in'] + 0.02, r), (x_out, r), (x_out, 0.0)]
    p = ck.revolve(prof, segs, 'Underbody', theta0=math.radians(a0), theta1=math.radians(a1), caps=True)
    p = p.translated((0, arch['y'], arch['z']))
    return p if side > 0 else p.mirrored_x()


def cutters(S0):
    """Recessed grille mouth, slot grille, corner intakes (front), the number-plate recess (rear) and the
    front wheel-well liner reliefs."""
    out = [pocket(S0, MOUTH, 'front', 0.045),
           pocket(S0, SLOT, 'front', 0.016),
           pocket(S0, INTAKE_R, 'front', 0.028),
           pocket(S0, [(-x, z) for (x, z) in INTAKE_R], 'front', 0.028),
           pocket(S0, CURTAIN_R, 'front', 0.018, res=0.0, max_len=0.012),
           pocket(S0, [(-x, z) for (x, z) in CURTAIN_R], 'front', 0.018, res=0.0, max_len=0.012),
           pocket(S0, PLATE, 'rear', 0.009, wall_mat='Paint', back_mat='Paint', res=0.04)]
    out += [liner_relief(ARCHES[0], 1), liner_relief(ARCHES[0], -1)]
    return out


def splitter(S):
    """Carbon splitter blade under the front bumper, following the bumper plan outline at z = 0.236.
    It ends at y >= 1.78 (the front tyres reach y = 1.58 at full lock), so it never touches the wheels."""
    samples = S.outline_at_z(0.236, center=(0.0, 1.50), a0=-74.0, a1=74.0, n=40, ahead=1)
    keep = sorted([(p, n) for (p, n) in samples if p.y > 1.80], key=lambda s: s[0].x)
    front = [Vector((p.x + n.x * 0.026, p.y + n.y * 0.026)) for (p, n) in keep]
    inner = [Vector((p.x - n.x * 0.012, p.y - n.y * 0.012)) for (p, n) in keep]
    back = [Vector((p.x - n.x * 0.105, max(p.y - n.y * 0.105, 1.78))) for (p, n) in keep]
    blade = front + list(reversed(back))
    if ck.poly_area(blade) < 0:
        blade.reverse()
    part = ck.Part()
    part.extend(ck.sweep_axis('z', [0.166, 0.170, 0.181, 0.185],
                              [ck.offset_poly(blade, -0.003), blade, blade, ck.offset_poly(blade, -0.002)], 'Carbon'))
    web = inner + list(reversed(back))
    if ck.poly_area(web) < 0:
        web.reverse()
    part.extend(ck.sweep_axis('z', [0.184, 0.228], [web, web], 'Trim'))     # lower lip web up into the bumper
    return part


def headlamps(car, S, R, LH):
    hl_spec = [('front', 0.385, 0.618), ('front', 0.385, 0.690), ('front', 0.550, 0.716), ('front', 0.690, 0.728),
               ('right', 1.950, 0.738), ('right', 1.860, 0.752), ('right', 1.780, 0.752), ('right', 1.845, 0.728),
               ('right', 1.935, 0.685), ('front', 0.705, 0.632), ('front', 0.560, 0.606)]
    hl = snap_pts(S, hl_spec)
    housing, frame = S.patch3d(hl, offset=0.002, depth=0.006, res=0.02, mat='Trim', sub=4)
    R.extend(housing)
    O, U, V, D = frame
    pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in hl]
    inner2d = ck.offset_poly(ck.cr_resample(pts2d, True, 4), -0.006)
    R.extend(S.patch(inner2d, frame, offset=0.0032, depth=0.004, res=0.018, mat='Grille', smooth=False))
    drl = snap_pts(S, [('front', 0.410, 0.677), ('front', 0.550, 0.700), ('front', 0.660, 0.712),
                       ('right', 1.960, 0.722), ('right', 1.885, 0.733)])
    LH.extend(S.line3d(drl, width=0.008, offset=0.0070, mat='HeadlightLens'))
    centers = []
    for (x, z) in ((0.478, 0.647), (0.594, 0.659)):
        loc, nor = S.hit(S.frame('front'), x, z)
        c = loc + nor * 0.0058
        LH.extend(ck.disc(c, nor, 0.022, 'HeadlightLens', n=20))
        R.extend(ck.disc(c - nor * 0.0012, nor, 0.022, 'Chrome', n=20, ring_mat='Chrome', ring_w=0.006))
        centers.append(c)
    hc = (centers[0] + centers[1]) / 2
    car.socket('Socket_HeadlightR', hc)
    car.socket('Socket_HeadlightL', (-hc.x, hc.y, hc.z))


def taillamps(S, R, LT, LB, LR):
    tl_spec = [('rear', 0.345, 0.842), ('rear', 0.360, 0.902), ('rear', 0.600, 0.928), ('right', -1.905, 0.888),
               ('right', -1.800, 0.884), ('right', -1.742, 0.870), ('right', -1.790, 0.838), ('right', -1.900, 0.815),
               ('rear', 0.712, 0.792), ('rear', 0.540, 0.806)]
    tl = snap_pts(S, tl_spec)
    housing, frame = S.patch3d(tl, offset=0.002, depth=0.006, res=0.02, mat='Trim', sub=4)
    R.extend(housing)
    O, U, V, D = frame
    pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in tl]
    inner2d = ck.offset_poly(ck.cr_resample(pts2d, True, 4), -0.005)
    LT.extend(S.patch(inner2d, frame, offset=0.004, depth=0.004, res=0.016, mat='TaillightLens', smooth=False))
    brake = snap_pts(S, [('rear', 0.385, 0.884), ('rear', 0.600, 0.908), ('right', -1.900, 0.868),
                         ('right', -1.790, 0.864)])
    LB.extend(S.line3d(brake, width=0.012, offset=0.0058, mat='BrakeLens', step=0.02))
    LR.extend(S.patch(ck.rrect_pts(0.455, 0.836, 0.080, 0.022, 0.008, n=2), 'rear', offset=0.0058, depth=0.003,
                      res=0.0, mat='ReverseLens', smooth=False))


def body_details(car, S):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre parts (not mirrored)
    LH, LT, LB, LR, LBC = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()

    # ---- front: honeycomb deep inside the recessed mouth and corner intakes, chrome bar in the slot grille
    C.extend(S.honeycomb(ck.offset_poly(MOUTH, -0.002), 'front', cell=0.044, wall=0.006, base=False,
                         base_offset=0.001, height=0.010, margin=0.002, smooth=False))
    R.extend(S.honeycomb(ck.offset_poly(INTAKE_R, -0.002), 'front', cell=0.036, wall=0.0055, base=False,
                         base_offset=0.001, height=0.008, margin=0.002, smooth=False))
    C.extend(S.line([(-0.345, SLOT_Z), (0.345, SLOT_Z)], 'front', width=0.0055, offset=0.003, mat='Chrome',
                    smooth=False, step=0.03))
    C.extend(splitter(S))
    # bonnet front shut line + bumper/wing seam
    C.extend(S.line([(-0.68, 0.764), (-0.4, 0.764), (0.0, 0.764), (0.4, 0.764), (0.68, 0.764)], 'front', step=0.02))
    R.extend(S.line([(1.975, 0.600), (1.860, 0.602), (1.700, 0.595), (1.580, 0.580), (1.545, 0.560)], 'right'))
    headlamps(car, S, R, LH)

    # ---- mirrors (body colour cap, black base, chrome glass)
    mc = Vector((0.945, 0.885, 1.045))
    ry = 0.062

    def flat_back(p):          # flatten the glass side monotonically (no folded, inside-out faces)
        if p.y < -ry * 0.25:
            p.y = -ry * 0.25 + (p.y + ry * 0.25) * 0.08
        return p
    mirror = ck.ellipsoid(mc, (0.100, ry, 0.052), 'Paint', nu=20, nv=10, exp=3.0, deform=flat_back)
    for fi in range(len(mirror.f)):
        if mirror.face_center(fi).z < mc.z - 0.026:
            mirror.m[fi] = 'Trim'
    R.extend(mirror)
    glass_pts = ck.superellipse_pts(0.0, 0.0, 0.080, 0.043, e=2.6, n=20)
    mg = ck.Part()
    gy = -ry * 0.25 - ry * 0.75 * 0.08 - 0.0015          # 1.5 mm behind the flattened back of the housing
    cen = mg.vert(mc + Vector((0, gy, 0)))
    ring = [mg.vert(mc + Vector((p.x, gy, p.y))) for p in glass_pts]
    for k in range(len(ring)):
        mg.face((cen, ring[(k + 1) % len(ring)], ring[k]), 'Chrome')
    mg.orient(0, ref=mc)
    R.extend(mg)
    mgb = mg.copy().translated((0, 0.0006, 0))          # reversed backing, so the glass never shows a back face
    mgb.f = [tuple(reversed(f)) for f in mgb.f]
    mgb.set_mat('Trim')
    R.extend(mgb)
    R.extend(ck.box_between((0.77, 0.905, 0.985), (0.875, 0.893, 1.03), 0.045, 0.022, 'Trim'))

    # ---- windscreen wipers (parked at the base of the screen)
    for (x0, x1, y0, y1, px) in ((-0.64, -0.08, 0.975, 0.945, -0.30), (-0.03, 0.50, 0.968, 0.940, 0.22)):
        a0 = S.snap('top', x0, y0) + Vector((0, 0, 0.013))
        a1 = S.snap('top', x1, y1) + Vector((0, 0, 0.013))
        C.extend(ck.box_between(a0, a1, 0.016, 0.011, 'Trim'))
        pivot = S.snap('top', px, 1.045) + Vector((0, 0, 0.012))
        mid = (a0 + a1) / 2 + Vector((0, 0, 0.008))
        C.extend(ck.box_between(pivot, mid, 0.012, 0.008, 'Trim'))
        C.extend(ck.ellipsoid(pivot, (0.016, 0.016, 0.010), 'Trim', nu=10, nv=6))

    # ---- side skirts (black), between the arches
    ys = [-0.905, -0.885, -0.80, -0.40, 0.0, 0.40, 0.80, 0.885, 0.905]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        k = 0.35 if abs(y) > 0.9 else (0.8 if abs(y) > 0.88 else 1.0)
        pr = [(ws - 0.030, zs + 0.050), (ws + 0.010 * k, zs + 0.046), (ws + 0.026 * k, zs + 0.004),
              (ws + 0.024 * k, zs - 0.060 * k), (ws + 0.006, zs - 0.072 * k), (ws - 0.030, zs - 0.060)]
        profs.append(pr)
    R.extend(ck.sweep_axis('y', ys, profs, 'Trim'))

    # ---- door handles, panel lines, fuel flap
    R.extend(S.patch(ck.rrect_pts(-0.215, 0.893, 0.15, 0.028, 0.012, n=3), 'right', offset=0.0055, depth=0.006,
                     res=0.0, mat='Trim', smooth=False))
    R.extend(S.line([(0.893, 0.29), (0.905, 0.62), (0.955, 0.94)], 'right', step=0.022))            # door front
    R.extend(S.line([(-0.44, 0.285), (-0.45, 0.62), (-0.47, 0.99)], 'right', step=0.022))           # door rear
    hood_edge = [BODY.point(y, 5.0, 1) for y in (1.05, 1.30, 1.55, 1.80, 1.955)]
    R.extend(S.line3d(hood_edge, step=0.025))
    fuel = ck.rrect_pts(-1.52, 0.835, 0.10, 0.10, 0.025, n=3)
    C.extend(S.line(fuel, 'right', closed=True, smooth=False))                              # right side only

    # ---- rear: tail lamps, tailgate + bumper lines, plate blank in the recess
    taillamps(S, R, LT, LB, LR)
    # gloss-black bar linking the tail lamps across the tailgate
    bar = ck.densify(ck.fillet_poly([(-0.338, 0.848), (0.338, 0.848), (0.338, 0.882), (-0.338, 0.882)], 0.01, n=2), 0.04)
    C.extend(S.patch(bar, 'rear', offset=0.002, depth=0.005, res=0.02, mat='Trim', smooth=False))
    tg = [(-0.330, 0.985), (-0.334, 0.800), (-0.331, 0.770), (-0.320, 0.753), (-0.300, 0.745), (0.300, 0.745),
          (0.320, 0.753), (0.331, 0.770), (0.334, 0.800), (0.330, 0.985)]
    C.extend(S.line(ck.densify(tg, 0.02, closed=False), 'rear', step=0.018, smooth=False))     # tailgate
    C.extend(S.line([(-0.72, 0.525), (-0.4, 0.519), (0.0, 0.517), (0.4, 0.519), (0.72, 0.525)], 'rear', step=0.025))
    R.extend(S.line([(-1.955, 0.525), (-1.82, 0.528), (-1.68, 0.540), (-1.60, 0.528), (-1.57, 0.51)], 'right',
                    step=0.022))
    C.extend(S.patch(ck.rrect_pts(0.0, 0.655, 0.505, 0.098, 0.010, n=2), 'rear', offset=0.0025, depth=0.003,
                     res=0.03, mat='Trim', smooth=False))

    # ---- roof spoiler (gloss black like the roof) following the roof crown + third brake light
    prof = [(-1.480, 0.006), (-1.580, 0.030), (-1.700, 0.040), (-1.790, 0.034), (-1.802, 0.014),
            (-1.745, -0.004), (-1.665, -0.016), (-1.600, -0.012)]
    xs = [-0.585, -0.575, -0.45, -0.25, 0.0, 0.25, 0.45, 0.575, 0.585]
    z0 = S.snap('top', 0.0, -1.56).z
    profs = []
    for x in xs:
        zx = S.snap('top', min(abs(x), 0.565) * (1 if x >= 0 else -1), -1.56).z
        sc = 0.75 if abs(x) >= 0.58 else 1.0
        profs.append([(y, zx + dz * sc) for (y, dz) in prof])
    C.extend(ck.sweep_axis('x', xs, profs, 'Carbon'))
    LBC.extend(ck.box_between((-0.14, -1.803, z0 + 0.024), (0.14, -1.803, z0 + 0.024), 0.008, 0.010, 'BrakeLens'))
    # shark-fin antenna
    C.extend(ck.ellipsoid((0.0, -1.30, S.snap('top', 0.0, -1.30).z + 0.012), (0.022, 0.075, 0.04), 'Carbon', nu=12, nv=8,
                          deform=lambda p: Vector((p.x * (1.0 - 0.6 * max(0.0, p.z) / 0.04), p.y - 0.6 * max(0.0, p.z), max(p.z, -0.004)))))

    # ---- rear valance, carbon diffuser with fins, twin centre exhausts
    valance = ck.densify([(-0.70, 0.300), (0.70, 0.300), (0.735, 0.33), (0.725, 0.405), (0.66, 0.418), (-0.66, 0.418),
                          (-0.725, 0.405), (-0.735, 0.33)], 0.05)
    C.extend(S.patch(valance, 'rear', offset=0.0025, depth=0.005, res=0.025, mat='Trim', smooth=False))
    diff = ck.densify([(-0.56, 0.305), (0.56, 0.305), (0.60, 0.322), (0.58, 0.398), (-0.58, 0.398), (-0.60, 0.322)], 0.05)
    C.extend(S.patch(diff, 'rear', offset=0.005, depth=0.006, res=0.025, mat='Carbon', smooth=False))
    for x in (-0.40, -0.20, 0.20, 0.40):
        ys = [-1.958, -1.90, -1.80, -1.66]
        profs = []
        for y in ys:
            zb = BODY.params_at(max(y, -1.93))['zb']
            top = zb + 0.03
            bot = max(0.17, zb - 0.06)
            profs.append([(x - 0.004, bot), (x + 0.004, bot), (x + 0.004, top), (x - 0.004, top)])
        C.extend(ck.sweep_axis('y', ys, profs, 'Carbon'))
    tips = []
    for x in (0.085, -0.085):
        p0 = Vector((x, -1.88, 0.248))
        p1 = Vector((x, -2.008, 0.248))
        C.extend(ck.tube(p0, p1, 0.043, 0.035, 'Chrome', 'Trim', n=22, inner_depth=0.06))
        tips.append(p1)
    car.socket('Socket_Exhaust', tips[0])
    car.socket('Socket_Exhaust2', tips[1])

    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x())
    car.add('Lights_Brake', LB, LB.mirrored_x(), LBC)
    car.add('Lights_Reverse', LR, LR.mirrored_x())
    return LB


# ---------------------------------------------------------------- interior
def seat_section(hw, h, b, roll=0.028, r_bot=0.022, flat=0.40, crown=0.006, sub=3):
    """Closed, smooth (x, v) section of a seat cushion / backrest: base at v=0, centre insert top at v=h
    (slightly crowned), side bolsters rising by b with rounded tops. Catmull-Rom resampled (no facets)."""
    q = [(0.0, h + crown), (flat * hw, h), (0.56 * hw, h + 0.28 * b), (0.70 * hw, h + 0.80 * b),
         (0.84 * hw, h + b), (0.95 * hw, h + b - 0.40 * roll), (hw, h + b - roll),
         (hw, r_bot), (hw - r_bot, 0.0), (0.0, 0.0)]
    half = ck.cr_resample([Vector(p) for p in q], closed=False, sub=sub, corners=(6, 7, 9))
    return half + [Vector((-p.x, p.y)) for p in reversed(half[1:-1])]


def seat_mats(loop, hw, h, accent=True):
    """Material per section segment: centre insert 'Interior', yellow piping 'InteriorAccent', rest dark."""
    out = []
    n = len(loop)
    for k in range(n):
        a, b = loop[k], loop[(k + 1) % n]
        mx, my = abs(a.x + b.x) / 2 / hw, (a.y + b.y) / 2
        if my > h * 0.7 and mx < 0.47:
            out.append('Interior')
        elif accent and my > h * 0.7 and mx < 0.55:
            out.append('InteriorAccent')
        else:
            out.append('InteriorDark')
    return out


def sport_seat(x, y_front, y_back, z_base, width=0.52, recline=18.0, back_h=0.86):
    """Sculpted sport bucket seat: smooth cushion with thigh bolsters, tall winged backrest with an
    integrated headrest, yellow piping, seat pan + runners."""
    part = ck.Part()
    hw0 = width / 2
    L = y_front - y_back
    ys = [y_front, y_front - 0.012, y_front - 0.035, y_front - 0.08, y_front - 0.17, y_back + 0.17,
          y_back + 0.06, y_back + 0.02, y_back]
    profs = []
    for k, yy in enumerate(ys):
        f = (y_front - yy) / L
        sc = (0.55, 0.86, 0.97)[k] if k < 3 else 1.0
        hw = hw0 * (0.93 if k == 0 else (0.975 if k == 1 else 1.0))
        b = 0.050 + 0.022 * math.sin(math.pi * min(1.0, f * 1.4))
        sec = seat_section(hw, 0.085 * sc, b * sc, sub=2)
        dz = 0.035 * (1 - f) ** 1.5
        profs.append([(x + p.x, z_base + dz + p.y) for p in sec])
    mats = seat_mats(seat_section(hw0, 0.085, 0.06, sub=2), hw0, 0.085)
    part.extend(ck.sweep_axis('y', ys, profs, mats, cap_mat='InteriorDark'))
    # backrest (built upright along Z, depth toward +Y, then reclined about X at its base)
    zs = [0.0, 0.025, 0.10, 0.24, 0.38, 0.50, 0.57, 0.62, 0.66, 0.76, 0.83, back_h]
    profs = []
    for zz in zs:
        if zz <= 0.38:
            hw, b = 0.255 + 0.007 * ck.smoothstep(0.1, 0.38, zz), 0.100 + 0.015 * ck.smoothstep(0.1, 0.38, zz)
        elif zz <= 0.62:
            u = ck.smoothstep(0.38, 0.62, zz)
            hw, b = ck.lerp(0.262, 0.165, u), ck.lerp(0.115, 0.016, u)
        else:
            hw, b = 0.140 if zz < 0.80 else 0.132, 0.010
        t = 0.085 - 0.015 * zz / back_h
        if zz == 0.0:
            hw, t = hw * 0.96, t * 0.9
        if zz == back_h:
            hw, t, b = hw * 0.78, t * 0.75, b * 0.5
        elif zz == 0.83:
            hw, t = hw * 0.95, t * 0.95
        sec = seat_section(hw, t, b, roll=0.03 if zz < 0.6 else 0.02)
        profs.append([(x + p.x, p.y) for p in sec])
    mats = seat_mats(seat_section(0.26, 0.08, 0.10), 0.26, 0.08)
    back = ck.sweep_axis('z', zs, profs, mats, cap_mat='InteriorDark')
    M = Matrix.Translation((0, y_back - 0.04, z_base + 0.06)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    part.extend(back.transformed(M))
    # seat pan + runners
    part.extend(ck.box_between((x, y_front - 0.08, z_base - 0.05), (x, y_back + 0.04, z_base - 0.05),
                               width * 0.72, 0.10, 'InteriorDark'))
    for sx in (-1, 1):
        part.extend(ck.box_between((x + sx * 0.17, y_front + 0.02, z_base - 0.115), (x + sx * 0.17, y_back - 0.02, z_base - 0.115),
                                   0.035, 0.03, 'InteriorDark'))
    return part


def rear_bench(y_front, y_back, z_base, width=1.04, recline=24.0, back_h=0.60):
    part = ck.Part()
    hw0 = width / 2
    L = y_front - y_back
    ys = [y_front, y_front - 0.012, y_front - 0.035, y_front - 0.10, y_back + 0.08, y_back]
    profs = []
    for k, yy in enumerate(ys):
        sc = (0.6, 0.88, 0.97)[k] if k < 3 else 1.0
        sec = seat_section(hw0 * (0.97 if k == 0 else 1.0), 0.09 * sc, 0.03 * sc, flat=0.75, sub=2)
        dz = 0.02 * (1 - (y_front - yy) / L)
        profs.append([(p.x, z_base + dz + p.y) for p in sec])
    mats = seat_mats(seat_section(hw0, 0.09, 0.03, flat=0.75, sub=2), hw0, 0.09, accent=False)
    part.extend(ck.sweep_axis('y', ys, profs, mats, cap_mat='InteriorDark'))
    zs = [0.0, 0.03, 0.20, 0.42, back_h - 0.03, back_h]
    profs = []
    for zz in zs:
        hw = hw0 * (0.96 if zz in (0.0, back_h) else 1.0)
        t = 0.09 * (0.8 if zz == back_h else 1.0)
        sec = seat_section(hw, t, 0.035 * (1 - zz / back_h) + 0.008, flat=0.80, sub=2)
        profs.append([(p.x, p.y) for p in sec])
    mats = seat_mats(seat_section(hw0, 0.09, 0.035, flat=0.80, sub=2), hw0, 0.09, accent=False)
    back = ck.sweep_axis('z', zs, profs, mats, cap_mat='InteriorDark')
    M = Matrix.Translation((0, y_back - 0.04, z_base + 0.05)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    part.extend(back.transformed(M))
    # two outer headrests on the backrest top
    top = M @ Vector((0.0, 0.045, back_h + 0.07))
    for sx in (-1, 1):
        c = Vector((sx * 0.33, top.y, top.z))
        part.extend(ck.ellipsoid(c, (0.105, 0.045, 0.075), 'InteriorDark', nu=14, nv=7, exp=3.0))
    return part


def rv_mirror():
    """Interior rear-view mirror: rounded housing, chrome glass facing the driver, stalk to the screen top."""
    part = ck.Part()
    mc = Vector((0.0, 0.168, 1.318))
    outline = ck.superellipse_pts(0.0, 0.0, 0.122, 0.034, e=3.4, n=28)
    stations = [(-0.020, 0.94), (-0.017, 1.0), (-0.004, 1.03), (0.010, 0.97), (0.021, 0.74)]
    profs = [[(mc.x + p.x * s, mc.z + p.y * s) for p in outline] for (dy, s) in stations]
    house = ck.sweep_axis('y', [mc.y + dy for (dy, s) in stations], profs, 'InteriorDark')
    part.extend(house)
    glass = ck.Part()
    c = glass.vert(mc + Vector((0, -0.0215, 0)))
    ring = [glass.vert(mc + Vector((p.x * 0.88, -0.0215, p.y * 0.84))) for p in outline]
    for k in range(len(ring)):
        glass.face((c, ring[k], ring[(k + 1) % len(ring)]), 'Chrome')
    for fi in range(len(glass.f)):
        if glass.face_normal(fi).y > 0:
            glass.f[fi] = tuple(reversed(glass.f[fi]))
    part.extend(glass)
    part.extend(ck.rod((0.0, 0.188, 1.372), (0.0, 0.172, 1.345), 0.007, 'InteriorDark', n=10))
    part.extend(ck.ellipsoid((0.0, 0.192, 1.376), (0.030, 0.022, 0.009), 'InteriorDark', nu=12, nv=6))
    return part


def sport_wheel(R=0.180):
    """Kestrel sport steering wheel (local frame: hub at origin, rim in XZ, +Y = column toward the dash):
    D-shaped rim with thumb grips, perforated-leather grip zones, yellow 12 o'clock marker, two dished
    horizontal spokes with alloy inlays, a twin-bar lower spoke and a shield-shaped hub pad."""
    part = ck.Part()
    segs, ns = 48, 10
    rad, dep = 0.0135, 0.0175        # rim section semi-axes: radial / along the column

    def centre(a):
        c = Vector((R * math.cos(a), 0.0, R * math.sin(a)))
        if c.z < -R * 0.84:
            c.z = -R * 0.84 + (c.z + R * 0.84) * 0.2
        return c

    def grip(a):
        d = math.degrees(a) % 360.0
        return max(math.exp(-((d - 35.0) / 14.0) ** 2), math.exp(-((d - 145.0) / 14.0) ** 2))
    rows = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        c = centre(a)
        radial = ck._unit(Vector((c.x, 0, c.z)))
        th = 1.0 + 0.17 * grip(a)
        rows.append([part.vert(c + radial * (rad * th * math.cos(2 * math.pi * j / ns))
                               + Vector((0, 1, 0)) * (dep * th * math.sin(2 * math.pi * j / ns))) for j in range(ns)])
    for k in range(segs):
        k2 = (k + 1) % segs
        d = math.degrees(2 * math.pi * (k + 0.5) / segs) % 360.0
        if abs(d - 90.0) < 5.0:
            m = 'InteriorAccent'
        elif d < 62.0 or d > 298.0 or 118.0 < d < 242.0:
            m = 'Interior'
        else:
            m = 'InteriorDark'
        for j in range(ns):
            j2 = (j + 1) % ns
            part.face((rows[k][j], rows[k][j2], rows[k2][j2], rows[k2][j]), m)
    cents = [centre(2 * math.pi * k / segs) for k in range(segs)]
    part.orient(0, ref_fn=lambda q: min(cents, key=lambda p: (p - q).length))
    dish = 0.028
    # horizontal spokes: rounded sections lofted along X, dished toward the column at the hub
    for sx in (1, -1):
        xs = [0.050, 0.075, 0.105, 0.135, R - 0.006]
        profs = []
        for xx in xs:
            u = ck.smoothstep(0.05, R - 0.006, xx)
            w = 0.052 - 0.016 * u
            yc = dish * (1.0 - u) + 0.001
            zc = -0.010 * (1.0 - u)
            sec = ck.superellipse_pts(0.0, 0.0, 0.0075, w / 2, e=3.0, n=12)
            profs.append([(yc + p.x, zc + p.y) for p in sec])
        sp = ck.sweep_axis('x', [sx * xx for xx in xs], profs, 'InteriorDark')
        part.extend(sp)
        # alloy inlay on the driver side of the spoke
        part.extend(ck.box_between((sx * 0.062, dish * 0.82 - 0.0085, -0.008), (sx * 0.150, 0.0045 - 0.006, -0.002),
                                   0.012, 0.002, 'Chrome', up=(0, 1, 0)))
    # twin-bar lower spoke
    for sx in (1, -1):
        part.extend(ck.rod((sx * 0.020, dish, -0.040), (sx * 0.046, 0.003, -R * 0.84 + 0.004), 0.0075, 'InteriorDark', n=10))
    # shield-shaped hub pad
    outline = ck.superellipse_pts(0.0, 0.0, 0.066, 0.052, e=3.2, n=28)
    st = [(dish - 0.022, 0.90), (dish - 0.018, 0.98), (dish - 0.010, 1.0), (dish + 0.032, 0.92)]
    profs = [[(p.x * s, -0.006 + p.y * s - (0.010 * s if p.y < -0.03 else 0.0)) for p in outline] for (yy, s) in st]
    part.extend(ck.sweep_axis('y', [yy for (yy, s) in st], profs, 'InteriorDark'))
    part.extend(ck.box_between((-0.024, dish - 0.0232, 0.020), (0.024, dish - 0.0232, 0.020), 0.006, 0.002,
                               'Chrome', up=(0, 1, 0)))
    return part


def interior(car):
    I = ck.Part()
    # dashboard
    dash = [(1.02, 0.945), (0.80, 0.968), (0.60, 0.966), (0.515, 0.948), (0.48, 0.900), (0.47, 0.80),
            (0.50, 0.70), (0.58, 0.60), (0.66, 0.52), (0.80, 0.47), (0.92, 0.62), (1.02, 0.72)]
    dmats = ['InteriorDark'] * 4 + ['Interior'] * 3 + ['InteriorDark'] * 5
    xs = [-0.745, -0.73, -0.55, -0.2, 0.0, 0.2, 0.55, 0.73, 0.745]
    profs = []
    for x in xs:
        sc = 0.0 if abs(x) < 0.74 else 0.01
        profs.append([(y + sc, z - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dmats))
    # yellow accent strip across the dash face
    I.extend(ck.box_between((-0.70, 0.478, 0.842), (0.70, 0.478, 0.842), 0.010, 0.012, 'InteriorAccent'))
    # gauge binnacle
    hood = [(0.70, 0.962), (0.665, 1.018), (0.58, 1.033), (0.525, 1.025), (0.512, 1.003), (0.55, 1.006), (0.62, 0.988)]
    I.extend(ck.sweep_axis('x', [-0.57, -0.56, -0.18, -0.17], [[(y, z - (0.01 if k in (0, 3) else 0)) for (y, z) in hood]
                                                               for k in range(4)], 'InteriorDark'))
    for (x, nt) in ((-0.448, 9), (-0.292, 11)):
        c = Vector((x, 0.552, 0.982))
        I.extend(ck.gauge(c, EYE - c, 0.047, n_ticks=nt))
    # centre screen + vents
    I.extend(ck.box_between((0.0, 0.535, 0.955), (0.0, 0.515, 1.055), 0.225, 0.014, 'InteriorDark', up=(0, 1, 0)))
    scr = ck.Part()
    for (x0, x1, z0, z1) in ((-0.09, 0.09, 1.027, 1.037), (-0.09, -0.01, 0.982, 1.017), (0.01, 0.09, 0.982, 1.017),
                             (-0.09, 0.03, 0.972, 0.976)):
        yb = lambda z: 0.5281 - 0.2 * (z - 0.9536) - 0.0012      # 1.2 mm in front of the screen face
        q = [scr.vert(Vector((x, yb(z), z))) for (x, z) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
        scr.face(q, 'Gauge')
    scr.orient(0, ref=Vector((0, 0.6, 1.0)))
    I.extend(scr)
    for x in (-0.62, -0.14, 0.14, 0.62):
        I.extend(ck.box_between((x - 0.055, 0.485, 0.885), (x + 0.055, 0.485, 0.885), 0.03, 0.045, 'InteriorDark'))
    # steering column shroud
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.30, 0.075, 0.085, 'InteriorDark'))
    # centre console + gear lever
    cys = [0.62, 0.50, 0.30, 0.05, -0.20, -0.36]
    tops = [0.66, 0.60, 0.52, 0.50, 0.55, 0.54]
    profs = [[(-0.095, 0.17), (0.095, 0.17), (0.10, t - 0.03), (0.08, t), (-0.08, t), (-0.10, t - 0.03)] for t in tops]
    I.extend(ck.sweep_axis('y', cys, profs, ['InteriorDark', 'InteriorDark', 'Interior', 'Interior', 'Interior', 'InteriorDark']))
    I.extend(ck.box_between((0.0, 0.24, 0.50), (0.0, 0.215, 0.625), 0.014, 0.014, 'InteriorDark'))
    I.extend(ck.ellipsoid((0.0, 0.212, 0.635), (0.024, 0.024, 0.028), 'Interior', nu=12, nv=8))
    I.extend(ck.box_between((0.0, 0.0, 0.53), (0.0, -0.20, 0.57), 0.035, 0.03, 'InteriorDark'))   # handbrake
    # seats
    for x in (-0.37, 0.37):
        I.extend(sport_seat(x, 0.24, -0.24, 0.30, width=0.52, recline=18.0, back_h=0.86))
    I.extend(rear_bench(-0.62, -1.04, 0.28))
    # parcel shelf, door armrests, door handles, pedals, sun visors, rear-view mirror
    I.extend(ck.box_between((0.0, -1.36, 0.958), (0.0, -1.86, 0.958), 1.30, 0.016, 'InteriorDark'))
    door = ck.Part()
    ays = [-0.36, -0.33, 0.55, 0.60]
    door.extend(ck.sweep_axis('y', ays, [(0.745, 0.640), (0.770, 0.600), (0.835, 0.598), (0.835, 0.668), (0.752, 0.668)], 'InteriorDark'))
    door.extend(ck.box_between((0.80, 0.50, 0.80), (0.80, 0.60, 0.80), 0.03, 0.022, 'Interior'))
    door.extend(ck.disc((0.818, 0.55, 0.36), (-1, 0, 0), 0.06, 'InteriorDark', n=16))
    I.extend(door, door.mirrored_x())
    for x, w in ((-0.47, 0.05), (-0.37, 0.07), (-0.27, 0.045)):
        I.extend(ck.box_between((x, 0.80, 0.22), (x, 0.76, 0.33), w, 0.012, 'InteriorDark'))
    for s in (1, -1):
        I.extend(ck.box_between((s * 0.15, 0.03, 1.352), (s * 0.48, 0.03, 1.352), 0.17, 0.016, 'Interior'))
    I.extend(rv_mirror())
    car.add('Interior', I)
    car.obj_specs['Interior']['sharp'] = 60.0
    # steering wheel (separate object, origin at the hub, local +Y = column toward the dash)
    car.add('SteeringWheel', sport_wheel(R=0.180), location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))
    car.obj_specs['SteeringWheel']['sharp'] = 60.0


def make_materials():
    mats = ck.default_materials(paint=(0.888, 0.539, 0.0), paint_rough=0.26, paint_coat=0.6,
                                rim=(0.05, 0.05, 0.055), caliper=(0.60, 0.025, 0.02))
    mats['InteriorAccent'] = dict(base=(0.80, 0.48, 0.0), roughness=0.6)      # yellow piping / marker
    mats['Carbon'] = dict(base=(0.010, 0.010, 0.011), metallic=0.0, roughness=0.22, coat=0.5, coat_rough=0.05)  # gloss black
    return mats


def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials())
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006, cutters=cutters, frame_backs=0.0006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Glass', shell.glass)
    car.add('Interior', shell.inner)
    if STAGE != 'body':
        body_details(car, shell.surface)
        interior(car)
        ck.add_wheels(car, dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=18, spokes=5, style='double', segs=48,
                                disc_r=0.17, caliper_angle=150.0, rear=dict(disc_r=0.16, caliper_span=38.0)),
                      axles=dict(front=(YF, TRACK_F / 2), rear=(YR, TRACK_R / 2)))
        car.socket('Socket_CamHood', (0.0, 1.10, 1.075))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.04, 0.50))
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
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.92)        # mirrors excluded
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
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'compact hot hatch', 'drivetrain': 'FWD', 'engine': 'front',
        'doors': 3, 'source_blend': 'Opus55ForzaUltracodeEffort.blend', 'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(BODY.nose['y'] - BODY.tail['y'], 4), 'length_overall': round(mx.y - mn.y, 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(max(BODY.params_at(y)['zc'] for y in SHELL_YS), 4), 'height_overall': round(all_mx.z, 4),
        'ground_clearance': round(BODY.params_at(0.0)['zb'], 4), 'ground_clearance_min': round(mn.z, 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'wheels': {k: G(v) for k, v in wheels.items()},
        'sockets': sockets,
        'steering_wheel': {'position': G(sw.matrix_world.translation),
                           'column_axis': G(sw.matrix_world.to_3x3() @ Vector((0, 1, 0))), 'radius': 0.18,
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
        'default_paint': {'hex': '#F2C200', 'linear_rgb': [0.888, 0.539, 0.0], 'finish': 'gloss'},
    }


def export_all(car):
    tris = ck.tri_counts(car)
    res, info = ck.export_car(car, GLB_PATH)
    data = measure(car, tris)
    data['glb'] = {'path': 'res://assets/imported/cars/%s.glb' % CAR_ID, 'bytes': info['file_size'],
                   'nodes': [n['name'] for n in info['nodes']]}
    ck.write_car_json(car, JSON_PATH, data)
    return res, info, data


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


def front_wheel_clearance(car, steers=(-32, -20, 0, 20, 32), bumps=(0.0, 0.03)):
    """Body/wheel triangle overlaps with the front wheels steered and the suspension compressed
    (same test as tools/blender/review/inspect_steer_clearance.py); rear wheels at bump."""
    import bpy
    import bmesh
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()

    def bm_local(ob):
        oe = ob.evaluated_get(dg)
        me = oe.to_mesh()
        bm = bmesh.new()
        bm.from_mesh(me)
        oe.to_mesh_clear()
        return bm
    body = car.objects['Body']
    bb = bm_local(body)
    bb.transform(body.matrix_world)
    tb = BVHTree.FromBMesh(bb)
    bb.free()
    res = {}
    for w in ('FL', 'FR', 'RL', 'RR'):
        wo = car.objects['Wheel_' + w]
        base = bm_local(wo)
        for b in bumps:
            for s in (steers if w[0] == 'F' else (0,)):
                m = Matrix.Translation(wo.matrix_world.translation + Vector((0, 0, b))) @ Matrix.Rotation(math.radians(s), 4, 'Z')
                c = base.copy()
                c.transform(m)
                n = len(tb.overlap(BVHTree.FromBMesh(c)))
                c.free()
                if n:
                    res.setdefault(w, []).append((s, b, n))
        base.free()
    return res


if __name__ == '__main__':
    isolate(True)
    try:
        CAR, SHELL = build()
        print('tris', ck.tri_counts(CAR))
        if STAGE != 'body':
            print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W), 'interior verts in wheel wells:', interior_in_wells(CAR))
            print('interior leaks', interior_leaks(CAR))
            print('wheel/body contact (steer +-32, bump 3 cm):', front_wheel_clearance(CAR) or 'none')
        if RENDER:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(5.0, 6.1, 1.45), target=(0.0, 0.12, 0.60), lens=50.0,
                                           exposure=-0.2))
        if EXPORT:
            RES, INFO, DATA = export_all(CAR)
            print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
            print('materials', INFO['materials'])
    finally:
        if not globals().get('KEEP_ISOLATED', False):
            isolate(False)
