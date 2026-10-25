"""hatch_small - tiny 5-door city hatch (Sunward Roads traffic vehicle #1).

Rebuilds SUNWARD_GODOT/Traffic/Traffic_hatch_small with the kit's LoftBody (like the player cars, but with a much
lighter grid) and optionally renders docs/blender_props/traffic_hatch_small.png and exports
assets/imported/traffic/hatch_small.glb + .json. Run like van_delivery.py (globals EXPORT, RENDER, KEEP_SOLO).

Spec: L 3.60, W 1.65, H 1.50, wheelbase 2.35, track 1.43, wheels R 0.29 (14" steel wheels with slotted silver
covers, 165 tyres). Original design: short rounded bonnet, long 59 deg windscreen, tall flat roof, upright tailgate
with a 27 deg rear glass, big DLO with black B-pillars and thick body-colour C-pillars, rounded nose with
wrap-around lamps and a slim upper grille, vertical tail lamps beside the tailgate, black sills, five doors.
Default paint light blue #8EC3E6. The cabin tub (inner shell) is part of Body so the merged traffic LOD stays opaque.
"""
import sys
import os
import math
import importlib

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender'))
sys.path.insert(0, os.path.join(PROJECT, 'tools', 'blender', 'traffic'))
import car_kit as ck  # noqa: E402
importlib.reload(ck)
import traffic_common as tc  # noqa: E402
importlib.reload(tc)
from mathutils import Vector  # noqa: E402

CAR_ID = 'hatch_small'
CAR_NAME = 'City Hatch'
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
KEEP_SOLO = globals().get('KEEP_SOLO', False)

# ---------------------------------------------------------------------------------------------------- dimensions
WHEELBASE = 2.35
YF, YR = WHEELBASE / 2, -WHEELBASE / 2
TRACK = 1.43
WHEEL_R, WHEEL_W = 0.290, 0.165
ARCH_R, ARCH_Z = 0.320, 0.297
NOSE_Y, TAIL_Y = 1.802, -1.796
Y_HEADER = 0.200          # windscreen header
Y_COWL = 1.020            # windscreen base
Y_ROOF_END = -1.500       # rear glass top (roof falls slightly toward it)
Y_RW_BASE = -1.700        # rear glass base (tailgate crease)
S = [
    # ---- tail (cap) and tailgate
    dict(y=-1.770, zb=0.320, wb=0.44, zs=0.360, ws=0.690, zw=0.560, ww=0.745, zh=0.880, wh=0.725, zg=0.925,
         wg=0.672, zr=0.938, wr=0.515, zc=0.948, ks={4: 0.3, 6: 0.15}),
    dict(y=-1.742, zb=0.292, wb=0.48, zs=0.336, ws=0.738, zw=0.565, ww=0.782, zh=0.895, wh=0.765, zg=0.950,
         wg=0.705, zr=0.976, wr=0.542, zc=0.986, ks={4: 0.45}),
    dict(y=Y_RW_BASE, zb=0.270, wb=0.51, zs=0.320, ws=0.760, zw=0.570, ww=0.802, zh=0.905, wh=0.785, zg=0.968,
         wg=0.726, zr=1.018, wr=0.556, zc=1.028, sharp=dict(zc=0.5, zr=0.4), ks={4: 0.6, 6: 0.2}),
    # ---- rear glass raked ~27 deg, thick body-colour C-pillars leaning in
    dict(y=-1.600, zb=0.232, wb=0.53, zs=0.300, ws=0.772, zw=0.560, ww=0.815, zh=0.900, wh=0.798, zg=0.968,
         wg=0.742, zr=1.220, wr=0.598, zc=1.240),
    dict(y=Y_ROOF_END, zb=0.205, wb=0.54, zs=0.292, ws=0.776, zw=0.548, ww=0.820, zh=0.892, wh=0.804, zg=0.960,
         wg=0.750, zr=1.385, wr=0.626, zc=1.410, sharp=dict(zc=0.7, zr=0.5), ks={6: 0.3}),
    # ---- cabin (tall flat roof, tumblehome, gentle waist)
    dict(y=-1.300, zb=0.180, zs=0.280, ws=0.778, zw=0.535, ww=0.825, zh=0.880, wh=0.808, zg=0.945, wg=0.760,
         zr=1.402, wr=0.640, zc=1.442),
    dict(y=-0.900, zb=0.172, zs=0.272, ws=0.778, zw=0.528, ww=0.825, zh=0.873, wh=0.808, zg=0.935, wg=0.763,
         zr=1.416, wr=0.646, zc=1.478),
    dict(y=-0.400, zb=0.166, zs=0.266, ws=0.778, zw=0.520, ww=0.825, zh=0.866, wh=0.808, zg=0.926, wg=0.765,
         zr=1.420, wr=0.652, zc=1.500, ks={3: 0.6}),
    dict(y=Y_HEADER, zs=0.266, ws=0.778, zw=0.520, ww=0.825, zh=0.860, wh=0.808, zg=0.918, wg=0.768, zr=1.400,
         wr=0.662, zc=1.476, sharp=dict(zc=0.5, zr=0.5, wr=0.3), ks={3: 0.6}),
    dict(y=0.620, zs=0.268, ws=0.780, zw=0.522, ww=0.825, zh=0.852, wh=0.808, zg=0.905, wg=0.772, zr=1.192,
         wr=0.702, zc=1.238),
    dict(y=Y_COWL, zs=0.272, ws=0.780, zw=0.525, ww=0.825, zh=0.846, wh=0.810, zg=0.890, wg=0.775, zr=0.968,
         wr=0.746, zc=0.986, sharp=dict(zc=1.0, zr=1.0, wr=1.0), ks={3: 0.5}),
    # ---- short rounded bonnet falling to a rounded nose
    dict(y=1.100, zb=0.180, wb=0.56, zs=0.275, ws=0.782, zw=0.528, ww=0.825, zh=0.840, wh=0.810, zg=0.880,
         wg=0.770, zr=0.962, wr=0.690, zc=0.962, ks={5: 0.4, 6: 0.4}),
    dict(y=1.300, zb=0.190, wb=0.55, zs=0.278, ws=0.780, zw=0.530, ww=0.822, zh=0.822, wh=0.805, zg=0.860,
         wg=0.758, zr=0.928, wr=0.640, zc=0.926),
    dict(y=1.500, zb=0.200, wb=0.54, zs=0.282, ws=0.768, zw=0.525, ww=0.810, zh=0.797, wh=0.790, zg=0.833,
         wg=0.738, zr=0.884, wr=0.588, zc=0.879),
    dict(y=1.640, zb=0.212, wb=0.52, zs=0.286, ws=0.742, zw=0.515, ww=0.786, zh=0.772, wh=0.762, zg=0.801,
         wg=0.702, zr=0.840, wr=0.544, zc=0.836, ks={5: 0.4, 6: 0.5}),
    dict(y=1.725, zb=0.225, wb=0.49, zs=0.290, ws=0.698, zw=0.505, ww=0.742, zh=0.748, wh=0.718, zg=0.771,
         wg=0.654, zr=0.801, wr=0.505, zc=0.798, ks={6: 0.45}),
    dict(y=1.770, zb=0.236, wb=0.44, zs=0.293, ws=0.640, zw=0.495, ww=0.680, zh=0.728, wh=0.654, zg=0.748,
         wg=0.594, zr=0.772, wr=0.480, zc=0.770, ks={4: 0.5, 5: 0.3, 6: 0.3}),
]
WARP_Y = -1.050           # rear door glass rear edge (base y): leans forward toward the roof
RULES = [
    dict(bands=(7, 7), y=(Y_HEADER, Y_COWL), role='glass'),        # windscreen
    dict(bands=(5, 5), y=(WARP_Y, 0.860), role='glass'),           # front + rear door glass
    dict(bands=(5, 5), y=(0.860, Y_COWL), role='trim'),            # mirror sail
    dict(bands=(5, 5), y=(-0.090, -0.010), role='trim'),           # B-pillar (black)
    dict(bands=(6, 7), y=(Y_RW_BASE, Y_ROOF_END), role='glass'),   # rear glass (wraps over the rails)
]
BODY = ck.LoftBody(
    stations=S,
    band_segments=[2, 2, 2, 3, 1, 3, 2, 4],
    key_sharp=(0, 0.7, 0.5, 0.45, 0.80, 0.35, 0.4, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.46, tilt=8.0, k_edge=1.3, k_face=2.5, rings=6),
    tail=dict(y=TAIL_Y, z=0.62, tilt=3.0, k_edge=1.2, k_face=2.4, rings=6),
    step=0.090,
    rail=0.05,
    warps=[dict(y=WARP_Y, t=(5.0, 6.0), y_t=(-1.110, -0.975), margin=0.16)],
)
ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.50, segs=48), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.52, segs=48)]
INNER = dict(y=(-1.700, 1.030), d=0.032, dy_ramp=(-1.560, -1.680),
             tubs=[(YR, ARCH_Z, ARCH_R + 0.07, 0.470), (YF, ARCH_Z, ARCH_R + 0.07, 0.450)])

EYE = Vector((-0.360, -0.150, 1.230))
HUB = Vector((-0.360, 0.330, 0.905))
COLUMN_TILT = 24.0
SW_R = 0.180
PAINT_HEX, PAINT_LIN = '#8EC3E6', (0.270, 0.546, 0.791)

WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=14, spokes=10, style='disc', segs=28, rim_segs=28, face_segs=28,
                  tyre='tall', spoke_thick=0.018, spoke_dish=0.026, hub_r=0.055, nuts=0, brake=False,
                  disc=dict(hole_r=0.016, ring_f=0.66, rings=3), grooves=[-0.030, 0.030], groove_w=0.010, disc_r=0.13, caliper_angle=150.0,
                  caliper_span=40.0)


def make_materials():
    m = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.25, paint_rough=0.30, paint_coat=0.6,
                             rim=(0.62, 0.63, 0.65), rim_metallic=0.5, rim_rough=0.35, caliper=(0.08, 0.08, 0.085),
                             interior=(0.10, 0.10, 0.11), interior_dark=(0.020, 0.020, 0.022))
    m['Trim'] = dict(base=(0.018, 0.018, 0.020), roughness=0.45)
    m['Plate'] = dict(base=(0.78, 0.78, 0.76), roughness=0.45)
    m['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.3)
    m['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.04, alpha=0.32, double_sided=True)
    return m


def D(pts, L=0.03):
    return ck.densify(pts, L)


def snap_pts(S_, spec):
    out = []
    for view, a, b in spec:
        p = S_.snap(view, a, b)
        if p is None:
            raise RuntimeError('snap miss %s %s %s' % (view, a, b))
        out.append(p)
    return out


# ---------------------------------------------------------------------------------------------------- build
def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials(), group='Traffic')
    sh = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006, frame_backs=0.0006)
    car.shell = sh
    S_ = sh.surface
    car.add('Body', sh.bm)
    car.add('Glass', sh.glass)
    car.add('Body', sh.inner)          # cabin tub in Body: the merged traffic LOD drops Interior
    R, C, LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    details(car, S_, R, C, LH, LT, LB, LR)
    car.info['width_body'] = 2 * max(abs(v.x) for v in R.v + C.v + [Vector((p['ww'], 0, 0)) for p in
                                                                       (BODY.params_at(y) for y in sh.ys)])
    mirrors(R)
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x())
    car.add('Lights_Brake', LB)
    car.add('Lights_Reverse', LR, LR.mirrored_x())
    interior(car)
    wheel, cal = ck.build_wheel(**WHEEL_SPEC)
    ck.add_axle(car, 'F', wheel, cal, YF, TRACK / 2, WHEEL_R)
    ck.add_axle(car, 'R', wheel, cal, YR, TRACK / 2, WHEEL_R)
    car.socket('Socket_CamHood', (0.0, 1.10, 1.08))
    car.socket('Socket_CamCockpit', EYE)
    car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.08, 0.45))
    car.finalize()
    return car


def details(car, S_, R, C, LH, LT, LB, LR):
    # ---- front: wrap-around headlamps, slim upper grille, lower mouth, plate, bonnet + bumper seams
    hl = D(ck.fillet_poly([(0.330, 0.700), (0.640, 0.680), (0.740, 0.730), (0.700, 0.790), (0.380, 0.785)], 0.03,
                          n=2), 0.025)
    LH.extend(S_.patch(hl, 'front', offset=0.004, depth=0.006, res=0.025, mat='HeadlightLens', smooth=False))
    R.extend(S_.rim(hl, 'front', width=0.010, offset=0.005, depth=0.005, mat='Trim', smooth=False))
    ind = D(ck.fillet_poly([(0.600, 0.650), (0.720, 0.650), (0.735, 0.672), (0.610, 0.672)], 0.006, n=1), 0.02)
    R.extend(S_.patch(ind, 'front', offset=0.004, depth=0.005, res=0.0, mat='Amber', smooth=False))
    hc = S_.snap('front', 0.520, 0.742)
    car.socket('Socket_HeadlightR', hc + Vector((0, 0.010, 0)))
    car.socket('Socket_HeadlightL', (-hc.x, hc.y + 0.010, hc.z))
    gr = D(ck.fillet_poly([(-0.290, 0.712), (0.290, 0.712), (0.270, 0.760), (-0.270, 0.760)], 0.012, n=2), 0.03)
    C.extend(S_.patch(gr, 'front', offset=0.003, depth=0.005, res=0.02, mat='Grille', smooth=False))
    mouth = D(ck.fillet_poly([(-0.480, 0.330), (0.480, 0.330), (0.520, 0.380), (0.470, 0.470), (-0.470, 0.470),
                              (-0.520, 0.380)], 0.03, n=2), 0.03)
    C.extend(S_.patch(mouth, 'front', offset=0.003, depth=0.005, res=0.03, mat='Grille', smooth=False))
    for z in (0.375, 0.425):
        C.extend(S_.line([(-0.44, z), (0.44, z)], 'front', width=0.010, offset=0.0055, mat='Trim', step=0.04,
                         smooth=False))
    C.extend(S_.patch(D(ck.rrect_pts(0.0, 0.545, 0.500, 0.105, 0.008, n=2), 0.04), 'front', offset=0.004,
                      depth=0.004, res=0.03, mat='Plate', smooth=False))
    C.extend(S_.line([(-0.62, 0.805), (-0.3, 0.812), (0.0, 0.814), (0.3, 0.812), (0.62, 0.805)], 'front',
                     step=0.03))
    R.extend(S_.line([(1.760, 0.620), (1.650, 0.618), (1.540, 0.590), (1.490, 0.560)], 'right', step=0.025))
    hood_edge = [BODY.point(y, 5.0, 1) for y in (1.05, 1.25, 1.45, 1.65, 1.76)]
    R.extend(S_.line3d(hood_edge, step=0.04))
    # ---- sides: door shut lines, handles, black sills, fuel flap
    R.extend(S_.line([(1.000, 0.300), (1.002, 0.620), (1.000, 0.900)], 'right', step=0.04))       # front door front
    R.extend(S_.line([(-0.050, 0.290), (-0.050, 0.620), (-0.050, 0.930)], 'right', step=0.04))    # B line
    R.extend(S_.line([(-1.080, 0.940), (-1.075, 0.700), (-1.010, 0.640), (-0.960, 0.600), (-0.900, 0.540),
                      (-0.860, 0.490), (-0.830, 0.420), (-0.815, 0.320)], 'right', step=0.04, smooth=False))
    for yc in (0.560, -0.520):
        R.extend(S_.patch(ck.rrect_pts(yc, 0.870, 0.120, 0.024, 0.010, n=2), 'right', offset=0.0045, depth=0.005,
                          res=0.0, mat='Trim', smooth=False))
    ys = [-0.850, -0.830, -0.750, -0.300, 0.300, 0.780, 0.830, 0.850]
    profs = []
    for y in ys:
        p = BODY.params_at(y)
        ws, zs = p['ws'], p['zs']
        k = 0.4 if abs(y) > 0.84 else (0.8 if abs(y) > 0.82 else 1.0)
        profs.append([(ws - 0.030, zs + 0.050), (ws + 0.008 * k, zs + 0.045), (ws + 0.020 * k, zs + 0.004),
                      (ws + 0.018 * k, zs - 0.055 * k), (ws + 0.004, zs - 0.066 * k), (ws - 0.030, zs - 0.056)])
    R.extend(ck.sweep_axis('y', ys, profs, 'Trim'))
    C.extend(S_.line(ck.rrect_pts(-1.400, 0.800, 0.100, 0.100, 0.025, n=2), 'right', closed=True, smooth=False))
    # ---- rear: vertical tail lamps beside the tailgate, tailgate seam, plate, black valance, wiper, roof lip
    tl = D(ck.fillet_poly([(0.560, 0.770), (0.735, 0.760), (0.752, 0.830), (0.712, 0.935), (0.575, 0.945)], 0.02,
                          n=2), 0.025)
    LT.extend(S_.patch(tl, 'rear', offset=0.004, depth=0.006, res=0.025, mat='TaillightLens', smooth=False))
    R.extend(S_.rim(tl, 'rear', width=0.008, offset=0.005, depth=0.005, mat='Trim', smooth=False))
    LR.extend(S_.patch(D(ck.rrect_pts(0.640, 0.820, 0.090, 0.040, 0.010, n=2), 0.02), 'rear', offset=0.0068,
                       depth=0.004, res=0.0, mat='ReverseLens', smooth=False))
    for sx in (1, -1):
        LB.extend(S_.patch(D(ck.rrect_pts(sx * 0.640, 0.895, 0.110, 0.045, 0.012, n=2), 0.02), 'rear',
                           offset=0.0068, depth=0.004, res=0.0, mat='BrakeLens', smooth=False))
    tg = [(-0.540, 1.010), (-0.548, 0.760), (-0.540, 0.700), (-0.520, 0.680), (0.520, 0.680), (0.540, 0.700),
          (0.548, 0.760), (0.540, 1.010)]
    C.extend(S_.line(ck.densify(tg, 0.04, closed=False), 'rear', step=0.03, smooth=False))
    C.extend(S_.patch(D(ck.rrect_pts(0.0, 0.755, 0.500, 0.105, 0.008, n=2), 0.04), 'rear', offset=0.003,
                      depth=0.004, res=0.03, mat='Plate', smooth=False))
    valance = D([(-0.70, 0.300), (0.70, 0.300), (0.735, 0.33), (0.725, 0.430), (-0.725, 0.430), (-0.735, 0.33)],
                0.05)
    C.extend(S_.patch(valance, 'rear', offset=0.0025, depth=0.005, res=0.03, mat='Trim', smooth=False))
    a0 = S_.snap('rear', -0.050, 1.090) + Vector((0, -0.012, 0))
    a1 = S_.snap('rear', -0.420, 1.250) + Vector((0, -0.012, 0))
    C.extend(ck.box_between(a0, a1, 0.014, 0.010, 'Trim'))
    zt = S_.snap('top', 0.0, -1.580).z
    C.extend(ck.sweep_axis('x', [-0.56, -0.54, 0.54, 0.56],
                           [[(-1.545, zt - 0.005), (-1.640, zt - 0.010), (-1.655, zt + 0.004), (-1.560, zt + 0.018)]] * 4,
                           'Paint'))
    LB.extend(ck.box_between((-0.12, -1.649, zt + 0.004), (0.12, -1.649, zt + 0.004), 0.006, 0.010, 'BrakeLens'))
    zr = S_.snap('top', 0.0, -1.300).z
    C.extend(ck.ellipsoid((0.0, -1.320, zr + 0.008), (0.018, 0.060, 0.032), 'Trim', nu=10, nv=6,
                          deform=lambda p: Vector((p.x, p.y - 0.5 * max(0.0, p.z), max(p.z, -0.004)))))
    C.extend(ck.tube((-0.420, -1.560, 0.272), (-0.430, -1.770, 0.268), 0.024, 0.019, 'Chrome', 'Underbody', n=12))
    car.socket('Socket_Exhaust', (-0.430, -1.775, 0.268))
    # wipers at the base of the windscreen
    for (x0, x1, y0, y1) in ((-0.58, -0.06, 0.990, 0.960), (-0.02, 0.46, 0.985, 0.955)):
        b0 = S_.snap('top', x0, y0) + Vector((0, 0, 0.012))
        b1 = S_.snap('top', x1, y1) + Vector((0, 0, 0.012))
        C.extend(ck.box_between(b0, b1, 0.014, 0.010, 'Trim'))


def mirrors(R):
    mc = Vector((0.880, 0.930, 1.000))
    head = ck.ellipsoid(mc, (0.075, 0.045, 0.048), 'Paint', nu=14, nv=8, exp=2.6)
    for fi in range(len(head.f)):
        if head.face_center(fi).y < mc.y - 0.020:
            head.m[fi] = 'Chrome'
    R.extend(head)
    R.extend(ck.box_between((0.770, 0.935, 0.960), (0.830, 0.930, 0.985), 0.040, 0.022, 'Trim'))


def interior(car):
    I = ck.Part()
    zf = BODY.params_at(0.0)['zb'] + INNER['d']
    for x in (-0.360, 0.360):
        I.extend(ck.simple_seat(x, 0.130, -0.360, zf + 0.240, width=0.48, back_h=0.62, recline=15.0))
        I.extend(ck.abox((x - 0.17, -0.300, zf), (x + 0.17, 0.080, zf + 0.245), 'InteriorDark'))
    I.extend(ck.simple_seat(0.0, -0.700, -1.130, zf + 0.250, width=1.20, back_h=0.56, recline=14.0, headrest=False))
    I.extend(ck.abox((-0.58, -1.080, zf), (0.58, -0.740, zf + 0.255), 'InteriorDark'))
    prof = [(0.980, zf + 0.06), (0.980, 0.860), (0.820, 0.955), (0.640, 0.960), (0.590, 0.900), (0.640, 0.640),
            (0.800, zf + 0.06)]
    I.extend(ck.sweep_axis('x', [-0.700, 0.700], [prof, prof], 'InteriorDark'))
    I.extend(ck.gauge((-0.360, 0.598, 0.880), (0.0, -1.0, 0.25), 0.055))
    I.extend(ck.abox((-0.08, 0.594, 0.760), (0.08, 0.606, 0.880), 'Gauge'))
    I.extend(ck.rbox('y', -0.150, 0.600, (0.0, zf + 0.10), 0.200, 0.200, 0.04, 'InteriorDark', n=1))
    I.extend(ck.rod((0.0, 0.420, zf + 0.20), (0.0, 0.380, zf + 0.36), 0.008, 'InteriorDark', n=8))
    I.extend(ck.ellipsoid((0.0, 0.378, zf + 0.375), (0.022, 0.022, 0.026), 'Interior', nu=10, nv=6))
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.06, HUB + col * 0.20, 0.060, 0.070, 'InteriorDark'))
    car.add('Interior', I)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.014, 0.017), segs=24, flat_bottom=False, hub_r=0.055,
                                spokes=((0.0, 0.045), (180.0, 0.045), (270.0, 0.040)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


META = dict(cls='city car (5-door hatchback)', drivetrain='FWD', engine='front, 1.0 petrol I3', doors=5, seats=4,
            sw_radius=SW_R, eye=EYE, paint_hex=PAINT_HEX, paint_lin=PAINT_LIN, finish='metallic', height_roof=1.500,
            rim_diameter_in_front=14, rim_diameter_in_rear=14, tyre_width_nominal=WHEEL_W,
            notes='Cabin tub (LoftBody inner shell) is part of Body so the merged traffic LOD stays opaque.')


if __name__ == '__main__':
    CAR = build()
    tc.finish_body(CAR)
    META['width_body'] = CAR.info['width_body']
    print('tris', ck.tri_counts(CAR))
    print('qa', tc.qa(CAR, WHEEL_R, WHEEL_W))
    if RENDER:
        print('render', tc.render_hero(CAR, os.path.join(tc.DOC_DIR, 'traffic_%s.png' % CAR_ID),
                                       cam_loc=(5.0, 5.6, 1.7), target=(0.0, 0.0, 0.70), lens=50.0,
                                       world_strength=0.9, sun_energy=3.8, exposure=-0.3, sun_rot=(0.80, 0.0, 2.30)))
    if EXPORT:
        RES, VER, DATA = tc.export(CAR, META)
        print('export', RES, VER)
        print('dims L %.3f W %.3f H %.3f wb %.3f' % (DATA['length'], DATA['width'], DATA['height_overall'],
                                                    DATA['wheelbase']))
    if KEEP_SOLO:
        tc.solo(CAR_ID)
