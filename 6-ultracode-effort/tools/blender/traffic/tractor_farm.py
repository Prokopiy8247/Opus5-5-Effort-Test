"""tractor_farm - farm tractor with an open canopy cab (Sunward Roads traffic vehicle #5).

Rebuilds SUNWARD_GODOT/Traffic/Traffic_tractor_farm with tools/blender/car_kit.py and optionally renders
docs/blender_props/traffic_tractor_farm.png and exports assets/imported/traffic/tractor_farm.glb + .json.
Run like van_delivery.py (globals EXPORT, RENDER, KEEP_SOLO).

Spec: L 4.00 (front weights -> rear wheels), W 2.20 (over the rear tyres), H 2.80 (canopy beacon; roof 2.72),
wheelbase 2.40, BIG rear wheels R 0.80 (34" yellow rims, 0.42 wide lugged tyres, track 1.78) and small front wheels
R 0.45 (20", 0.30 wide, track 1.60); the four standard Wheel_* objects carry their own axle heights (0.80 / 0.45).
Original design: rounded engine bonnet (ProfileBody) with a tall grille, two grille headlamps, side vents and a yellow
side stripe; front weight carrier with suitcase weights; open four-post canopy (ROPS) with roof, front screen, work
lamps and an amber beacon; vertical exhaust stack with a rain cap and an air-intake stack; big rear mudguards with
the tail lamps; operator platform, suspension seat, flat steering wheel, levers; rear axle housing, three-point
linkage, PTO stub and drawbar. Paint = grass green (repainted by the game); yellow rims and canopy roof ('Stripe') are fixed colours.
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
from mathutils import Vector, Matrix  # noqa: E402

CAR_ID = 'tractor_farm'
CAR_NAME = 'Farm Tractor'
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
KEEP_SOLO = globals().get('KEEP_SOLO', False)

# ---------------------------------------------------------------------------------------------------- dimensions
WHEELBASE = 2.40
YF, YR = WHEELBASE / 2, -WHEELBASE / 2
RF, WF_, TRACK_F = 0.450, 0.300, 1.600
RR, WR_, TRACK_R = 0.800, 0.420, 1.780
HOOD_HW = 0.400
STRIPE = (1.420, 1.470)
HOOD_PROFILE = [
    (-0.350, 1.050, 0.10),        # rear bottom (under the dash)
    (1.950, 1.050, 0.10),         # front bottom (grille foot)
    (1.985, 1.470, 0.12),         # grille top
    (1.860, 1.560, 0.14),         # bonnet front edge
    (-0.350, 1.680, 0.10),        # bonnet rear (dash)
]
HOOD = ck.ProfileBody(HOOD_PROFILE, HOOD_HW, edge_r=0.090, edge_segs=3, step=0.25, arc_step=0.03,
                      splits=[('z', STRIPE[0]), ('z', STRIPE[1])])
Z_PLAT = 1.200
ROOF_Z = 2.720
POST_X = 0.600
POST_YF, POST_YR = -0.420, -1.820
FENDER = dict(r_in=0.860, r_out=0.890, x0=0.640, x1=1.100)

EYE = Vector((0.0, -1.120, 2.300))
HUB = Vector((0.0, -0.640, 1.980))
COLUMN_TILT = 40.0
SW_R = 0.200
PAINT_HEX, PAINT_LIN = '#4E9A2A', (0.076, 0.323, 0.023)          # grass green
YELLOW_LIN = (0.768, 0.445, 0.013)                               # #E3B21E sun yellow

LUGS_R = [dict(x=(-WR_ / 2 - 0.004, -0.020), phase=0.0, frac=0.30, skew=0.95, shoulder=-1, drop=0.070),
          dict(x=(0.020, WR_ / 2 + 0.004), phase=0.5, frac=0.30, skew=-0.95, shoulder=1, drop=0.070)]
LUGS_F = [dict(x=(-WF_ / 2 - 0.004, -0.015), phase=0.0, frac=0.32, skew=0.85, shoulder=-1, drop=0.045),
          dict(x=(0.015, WF_ / 2 + 0.004), phase=0.5, frac=0.32, skew=-0.85, shoulder=1, drop=0.045)]
REAR_SPEC = dict(R=RR, W=WR_, rim_d_in=34, spokes=8, style='disc', segs=32, rim_segs=32, face_segs=32,
                 tyre='tall', spoke_thick=0.030, spoke_dish=0.060, hub_r=0.140, nuts=0, brake=False,
                 disc=dict(hole_r=0.045, ring_f=0.55, rings=3), blocks=dict(n=20, h=0.050, rows=LUGS_R),
                 disc_r=0.20, caliper_angle=150.0, caliper_span=30.0)
FRONT_SPEC = dict(R=RF, W=WF_, rim_d_in=20, spokes=6, style='disc', segs=24, rim_segs=24, face_segs=24,
                  tyre='tall', spoke_thick=0.024, spoke_dish=0.040, hub_r=0.100, nuts=0, brake=False,
                  disc=dict(hole_r=0.030, ring_f=0.58, rings=2), blocks=dict(n=16, h=0.032, rows=LUGS_F),
                  disc_r=0.16, caliper_angle=150.0, caliper_span=30.0)


def make_materials():
    m = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.0, paint_rough=0.34, paint_coat=0.3,
                             rim=YELLOW_LIN, rim_metallic=0.1, rim_rough=0.40, caliper=(0.05, 0.05, 0.05),
                             interior=(0.05, 0.05, 0.055), interior_dark=(0.018, 0.018, 0.02))
    m['Rubber'] = dict(base=(0.020, 0.020, 0.022), roughness=0.92)
    m['Trim'] = dict(base=(0.020, 0.020, 0.022), roughness=0.55)
    m['Steel'] = dict(base=(0.050, 0.050, 0.052), metallic=0.5, roughness=0.55)
    m['Stripe'] = dict(base=YELLOW_LIN, roughness=0.35, coat=0.3)
    m['Alu'] = dict(base=(0.62, 0.63, 0.65), metallic=1.0, roughness=0.38)
    m['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.35)
    m['Plate'] = dict(base=(0.78, 0.78, 0.76), roughness=0.45)
    m['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.04, alpha=0.25, double_sided=True)
    return m


def hood_mat(c, n, where):
    if where == 'band' and n.z < -0.7:
        return 'Steel'
    if where == 'side' and STRIPE[0] < c.z < STRIPE[1]:
        return 'Trim'                    # dark band along the bonnet sides
    return 'Paint'


def D(pts, L=0.03):
    return ck.densify(pts, L)


def fender(sx):
    """Rear mudguard: curved top band + inner wall plate down to the platform + outer lip (RIGHT, mirrored)."""
    f = FENDER
    a0 = math.asin((Z_PLAT - RR) / f['r_out'])
    t0, t1 = a0, math.pi - a0
    p = ck.revolve([(f['x0'], f['r_in']), (f['x1'], f['r_in']), (f['x1'], f['r_out']), (f['x0'], f['r_out'])], 24,
                   'Paint', theta0=t0, theta1=t1, caps=True)
    p.extend(ck.revolve([(f['x0'], f['r_out']), (f['x0'], f['r_in'])], 24, 'Paint', theta0=t0, theta1=t1))
    lip = ck.revolve([(f['x1'] - 0.012, f['r_out']), (f['x1'], f['r_out']), (f['x1'], f['r_in'] - 0.045),
                      (f['x1'] - 0.012, f['r_in'] - 0.045)], 24, 'Paint', theta0=t0, theta1=t1, caps=True)
    p.extend(lip)
    rm = (f['r_in'] + f['r_out']) / 2

    def ref(c):
        a = ck.clamp(math.atan2(c.z, c.y), t0 + 0.05, t1 - 0.05)
        return Vector(((f['x0'] + f['x1']) / 2, rm * math.cos(a), rm * math.sin(a)))
    p.orient(0, ref_fn=ref)
    p = p.translated((0, YR, RR))
    # inner wall (x = x0) between the platform and the band
    pts = [(YR + f['r_in'] * math.cos(t0 + (t1 - t0) * k / 16), RR + f['r_in'] * math.sin(t0 + (t1 - t0) * k / 16))
           for k in range(17)]
    wall = ck.sweep_axis('x', [f['x0'], f['x0'] + 0.018], [pts, pts], 'Paint')
    p.extend(wall)
    return p if sx > 0 else p.mirrored_x()


# ---------------------------------------------------------------------------------------------------- build
def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials(), group='Traffic')
    sh = HOOD.build(car, arches=(), mat_fn=hood_mat)
    S = sh.surface
    car.add('Body', sh.part)
    B, G, LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    hood_details(car, S, B, LH)
    running_gear(car, B)
    platform_and_canopy(car, B, G, LH, LR)
    rear(car, B, LT, LB)
    car.add('Body', B)
    car.add('Glass', G)
    print('parts: hood %d details %d' % (sh.part.tris(), B.tris()))
    car.add('Lights_Head', LH)
    car.add('Lights_Tail', LT)
    car.add('Lights_Brake', LB)
    car.add('Lights_Reverse', LR)
    interior(car)
    wf, cf = ck.build_wheel(**FRONT_SPEC)
    ck.add_axle(car, 'F', wf, cf, YF, TRACK_F / 2, RF)
    wr, cr = ck.build_wheel(**REAR_SPEC)
    ck.add_axle(car, 'R', wr, cr, YR, TRACK_R / 2, RR)
    car.socket('Socket_CamHood', (0.0, 0.20, 2.10))
    car.socket('Socket_CamCockpit', EYE)
    car.socket('Socket_CamBumper', (0.0, 2.08, 0.80))
    car.finalize()
    return car


def hood_details(car, S, B, LH):
    # grille: black mesh with vertical bars, two headlamps in the upper corners
    g = D(ck.fillet_poly([(-0.300, 1.170), (0.300, 1.170), (0.300, 1.420), (-0.300, 1.420)], 0.03, n=2), 0.05)
    B.extend(S.patch(g, 'front', offset=0.004, depth=0.008, res=0.0, mat='Grille', smooth=False))
    for x in (-0.20, -0.10, 0.0, 0.10, 0.20):
        bar = D(ck.rrect_pts(x, 1.250, 0.018, 0.140, 0.006, n=1), 0.05)
        B.extend(S.patch(bar, 'front', offset=0.010, depth=0.008, res=0.0, mat='Trim', smooth=False))
    for sx in (1, -1):
        lamp = [(sx * x, z) for (x, z) in D(ck.rrect_pts(0.205, 1.360, 0.150, 0.075, 0.015, n=2), 0.04)]
        LH.extend(S.patch(lamp, 'front', offset=0.010, depth=0.008, res=0.0, mat='HeadlightLens', smooth=False))
        B.extend(S.rim(lamp, 'front', width=0.010, offset=0.011, depth=0.005, mat='Trim', smooth=False))
        # side vents on the bonnet sides
        for z in (1.180, 1.240, 1.300):
            v = D(ck.rrect_pts(1.450, z, 0.500, 0.030, 0.012, n=1), 0.06)
            B.extend(S.patch(v, 'right' if sx > 0 else 'left', offset=0.003, depth=0.006, res=0.0, mat='Grille',
                             smooth=False))
    hc = S.snap('front', 0.205, 1.360)
    car.socket('Socket_HeadlightR', hc + Vector((0, 0.012, 0)))
    car.socket('Socket_HeadlightL', (-hc.x, hc.y + 0.012, hc.z))
    # bonnet seam across the top behind the grille
    B.extend(S.line([(-0.30, 1.880), (0.30, 1.880)], 'top', width=0.004, offset=0.0008, mat='Trim', step=0.001,
                    smooth=False))
    # exhaust stack (right) with heat shield + rain cap, air-intake stack (left)
    x_e, y_e = 0.250, 1.300
    top = S.snap('top', x_e, y_e)
    B.extend(ck.rod((x_e, y_e, top.z - 0.02), (x_e, y_e, 2.550), 0.045, 'Steel', n=12))
    B.extend(ck.rod((x_e, y_e, 1.900), (x_e, y_e, 2.300), 0.060, 'Alu', n=12))
    B.extend(ck.box_between((x_e - 0.055, y_e, 2.580), (x_e + 0.055, y_e, 2.580), 0.11, 0.012, 'Steel'))
    B.extend(ck.box_between((x_e, y_e - 0.04, 2.555), (x_e, y_e - 0.04, 2.585), 0.010, 0.030, 'Steel'))
    car.socket('Socket_Exhaust', (x_e, y_e, 2.560))
    x_i = -0.250
    top = S.snap('top', x_i, y_e)
    B.extend(ck.rod((x_i, y_e, top.z - 0.02), (x_i, y_e, 2.100), 0.050, 'Trim', n=12))
    B.extend(ck.ellipsoid((x_i, y_e, 2.150), (0.090, 0.090, 0.070), 'Trim', nu=12, nv=6))


def running_gear(car, B):
    # engine block / sump under the bonnet, front axle + pivot, weight carrier with suitcase weights
    B.extend(ck.rbox('y', -0.300, 1.850, (0.0, 0.840), 0.560, 0.420, 0.06, 'Steel'))
    B.extend(ck.rbox('y', 0.300, 1.500, (0.0, 0.580), 0.420, 0.160, 0.04, 'Steel'))
    B.extend(ck.rbox('x', -0.680, 0.680, (YF, RF), 0.140, 0.140, 0.03, 'Steel'))
    B.extend(ck.rbox('y', YF - 0.25, YF + 0.25, (0.0, 0.540), 0.260, 0.200, 0.04, 'Steel'))
    B.extend(ck.rbox('y', 1.830, 1.940, (0.0, 0.820), 0.900, 0.420, 0.03, 'Steel'))                  # carrier
    for k in range(8):
        xk = -0.385 + k * 0.110
        B.extend(ck.rbox('x', xk - 0.045, xk + 0.045, (1.968, 0.820), 0.064, 0.380, 0.02, 'Paint'))
        B.extend(ck.abox((xk - 0.012, 1.995, 0.990), (xk + 0.012, 2.000, 1.030), 'Steel'))           # handles
    # rear axle housing / gearbox, axle tubes, final drives, fuel tank (left), battery box (right)
    B.extend(ck.rbox('y', -1.560, -0.320, (0.0, 0.860), 0.760, 0.560, 0.06, 'Steel'))
    for sx in (1, -1):
        B.extend(ck.rod((sx * 0.38, YR, RR), (sx * 0.62, YR, RR), 0.100, 'Steel', n=12))
        B.extend(ck.rod((sx * 0.56, YR, RR), (sx * 0.64, YR, RR), 0.165, 'Steel', n=14))
    B.extend(ck.rbox('y', -0.320, 0.300, (-0.480, 0.900), 0.240, 0.380, 0.08, 'Trim'))
    B.extend(ck.rod((-0.480, 0.000, 1.090), (-0.480, 0.000, 1.140), 0.040, 'Steel', n=10))
    B.extend(ck.rbox('y', -0.250, 0.200, (0.470, 0.920), 0.220, 0.300, 0.03, 'Trim'))
    for (x0, x1, yy) in ((-0.380, -0.270, -0.150), (-0.380, -0.270, 0.150), (0.270, 0.380, -0.100),
                         (0.270, 0.380, 0.100)):
        B.extend(ck.abox((x0, yy - 0.030, 0.860), (x1, yy + 0.030, 0.920), 'Steel'))   # tank / battery brackets


def platform_and_canopy(car, B, G, LH, LR):
    # operator platform + left access steps
    B.extend(ck.abox((-0.630, -1.820, Z_PLAT - 0.040), (0.630, -0.340, Z_PLAT), 'Trim'))
    for z in (0.560, 0.880):
        B.extend(ck.abox((-0.760, -0.360, z - 0.030), (-0.520, -0.120, z), 'Trim'))
    for yy in (-0.360, -0.120):
        B.extend(ck.abox((-0.770, yy - 0.015, 0.520), (-0.750, yy + 0.015, Z_PLAT), 'Trim'))
    B.extend(ck.rod((-0.640, -0.120, 1.250), (-0.640, -0.380, 2.050), 0.016, 'Trim', n=8))           # grab handle
    # rear mudguards (fenders)
    B.extend(fender(1), fender(-1))
    # four-post canopy (ROPS) + roof + front screen frame
    for sx in (1, -1):
        for yy, z0 in ((POST_YF, Z_PLAT), (POST_YR, Z_PLAT)):
            B.extend(ck.rbox('z', z0 - 0.02, ROOF_Z - 0.05, (sx * POST_X, yy), 0.070, 0.070, 0.015, 'Trim', n=1))
        B.extend(ck.rbox('y', POST_YR, POST_YF, (sx * POST_X, ROOF_Z - 0.080), 0.070, 0.060, 0.012, 'Trim', n=1))
    B.extend(ck.rbox('y', -2.000, -0.200, (0.0, ROOF_Z - 0.040), 1.720, 0.080, 0.035, 'Stripe', n=2))   # yellow roof
    B.extend(ck.rbox('y', -1.900, -0.300, (0.0, ROOF_Z - 0.085), 1.560, 0.012, 0.004, 'Trim', n=1))    # headliner
    for z in (1.760, 2.600):
        B.extend(ck.rod((-POST_X, POST_YF, z), (POST_X, POST_YF, z), 0.020, 'Trim', n=8))
    G.extend(ck.abox((-POST_X + 0.03, POST_YF - 0.006, 1.770), (POST_X - 0.03, POST_YF + 0.006, 2.590), 'Glass'))
    # mirrors on the front posts, wiper
    for sx in (1, -1):
        B.extend(ck.rod((sx * POST_X, POST_YF, 2.250), (sx * 0.920, POST_YF + 0.050, 2.300), 0.012, 'Trim', n=6))
        B.extend(ck.rbox('z', 2.200, 2.400, (sx * 0.950, POST_YF + 0.050), 0.120, 0.035, 0.012, 'Trim', n=1))
        B.extend(ck.abox((sx * 0.895, POST_YF + 0.030, 2.215), (sx * 1.005, POST_YF + 0.032, 2.385), 'Chrome'))
    B.extend(ck.box_between((-0.05, POST_YF + 0.020, 1.800), (-0.45, POST_YF + 0.020, 2.250), 0.014, 0.010, 'Trim'))
    # roof work lamps (front: Lights_Head, rear: Lights_Reverse) and amber beacon
    for sx in (1, -1):
        for yy, part, mat, sg in ((-0.240, LH, 'HeadlightLens', 1), (-1.960, LR, 'ReverseLens', -1)):
            B.extend(ck.abox((sx * 0.640, yy - 0.050, ROOF_Z - 0.170), (sx * 0.760, yy + 0.050, ROOF_Z - 0.080),
                             'Trim'))
            yl = yy + sg * 0.050
            part.extend(ck.abox((sx * 0.650, min(yl, yl + sg * 0.006), ROOF_Z - 0.160),
                                (sx * 0.750, max(yl, yl + sg * 0.006), ROOF_Z - 0.090), mat))
    B.extend(ck.rbox('z', ROOF_Z, ROOF_Z + 0.025, (0.0, -0.900), 0.120, 0.120, 0.04, 'Trim', n=2))
    B.extend(ck.rbox('z', ROOF_Z + 0.025, ROOF_Z + 0.080, (0.0, -0.900), 0.090, 0.090, 0.04, 'Amber', n=2))


def rear(car, B, LT, LB):
    # three-point linkage, lift arms, top link, PTO stub, drawbar
    for sx in (1, -1):
        B.extend(ck.rod((sx * 0.340, -1.400, 0.600), (sx * 0.420, -1.950, 0.480), 0.035, 'Steel', n=8))
        B.extend(ck.abox((sx * 0.410, -1.990, 0.440), (sx * 0.440, -1.920, 0.520), 'Steel'))
        B.extend(ck.box_between((sx * 0.300, -1.480, 1.180), (sx * 0.320, -1.860, 1.120), 0.050, 0.060, 'Steel'))
        B.extend(ck.rod((sx * 0.320, -1.840, 1.110), (sx * 0.380, -1.700, 0.580), 0.020, 'Steel', n=8))
    B.extend(ck.rod((0.0, -1.540, 1.140), (0.0, -1.900, 1.000), 0.030, 'Steel', n=8))
    B.extend(ck.rod((0.0, -1.540, 0.720), (0.0, -1.780, 0.720), 0.030, 'Alu', n=10))
    B.extend(ck.abox((-0.060, -1.960, 0.520), (0.060, -1.500, 0.590), 'Steel'))                    # drawbar
    # tail lamp housings at the back ends of the mudguards (tail / brake / amber)
    for sx in (1, -1):
        B.extend(ck.abox((sx * 0.820, -1.990, 1.205), (sx * 1.060, -1.920, 1.330), 'Trim'))
        LT.extend(ck.abox((sx * 0.900, -1.996, 1.275), (sx * 0.990, -1.990, 1.320), 'TaillightLens'))
        LB.extend(ck.abox((sx * 0.900, -1.996, 1.215), (sx * 0.990, -1.990, 1.270), 'BrakeLens'))
        B.extend(ck.abox((sx * 0.995, -1.996, 1.215), (sx * 1.050, -1.990, 1.320), 'Amber'))
        B.extend(ck.abox((sx * 0.830, -1.996, 1.215), (sx * 0.895, -1.990, 1.320), 'Amber'))
    B.extend(ck.abox((-0.820, -1.990, 1.200), (-0.600, -1.930, 1.350), 'Trim'))                   # plate bracket
    B.extend(ck.abox((-0.810, -1.996, 1.215), (-0.610, -1.990, 1.335), 'Plate'))


def interior(car):
    I = ck.Part()
    # suspension seat on a pedestal
    I.extend(ck.simple_seat(0.0, -1.000, -1.460, 1.500, width=0.50, back_h=0.50, recline=10.0, headrest=False))
    I.extend(ck.rbox('z', Z_PLAT, 1.500, (0.0, -1.250), 0.300, 0.300, 0.05, 'InteriorDark', n=1))
    for sx in (1, -1):                                                                          # armrests
        I.extend(ck.rbox('y', -1.380, -1.080, (sx * 0.265, 1.760), 0.060, 0.050, 0.02, 'InteriorDark', n=1))
        I.extend(ck.abox((sx * 0.250, -1.360, 1.600), (sx * 0.280, -1.320, 1.740), 'InteriorDark'))
    # dash pod on the bonnet rear + gauges, column
    I.extend(ck.rbox('y', -0.460, -0.300, (0.0, 1.760), 0.440, 0.220, 0.04, 'InteriorDark', n=2))
    for x in (-0.090, 0.090):
        I.extend(ck.gauge((x, -0.462, 1.790), (0.0, -1.0, 0.35), 0.050))
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.rod(HUB + col * 0.05, HUB + col * 0.36, 0.030, 'InteriorDark', n=10))
    # hydraulic / gear levers on the right console, pedals
    I.extend(ck.rbox('y', -1.300, -0.700, (0.430, 1.420), 0.160, 0.420, 0.03, 'InteriorDark', n=1))
    for k, (dy, h) in enumerate(((-0.95, 0.30), (-0.88, 0.26), (-0.81, 0.26), (-1.10, 0.34))):
        top = Vector((0.430 + (0.03 if k == 3 else 0.0), dy - 0.04, 1.630 + h))
        I.extend(ck.rod((0.430, dy, 1.630), top, 0.010, 'InteriorDark', n=6))
        I.extend(ck.ellipsoid(top, (0.022, 0.022, 0.026), 'Gauge' if k == 0 else 'Interior', nu=8, nv=5))
    for x in (-0.200, 0.200):
        I.extend(ck.box_between((x, -0.420, Z_PLAT + 0.05), (x, -0.380, Z_PLAT + 0.18), 0.080, 0.014, 'InteriorDark'))
        I.extend(ck.rod((x, -0.400, Z_PLAT - 0.01), (x, -0.400, Z_PLAT + 0.07), 0.010, 'InteriorDark', n=6))
    car.add('Interior', I)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.014, 0.016), segs=24, flat_bottom=False, hub_r=0.055,
                                spokes=((90.0, 0.035), (210.0, 0.035), (330.0, 0.035)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


META = dict(cls='farm tractor (open four-post canopy, rear-wheel drive)', drivetrain='RWD',
            engine='front, 4.4 turbo-diesel I4', doors=0, seats=1, sw_radius=SW_R, eye=EYE, paint_hex=PAINT_HEX,
            paint_lin=PAINT_LIN, finish='gloss', height_roof=ROOF_Z, rim_diameter_in_front=20,
            rim_diameter_in_rear=34, tyre_width_nominal=WR_,
            wheel_width_note='front 0.30 / rear 0.42 nominal; lugs add ~1 cm', ground_clearance=0.44,
            livery='Paint = green (repaintable); yellow rims (Rim) and yellow canopy roof (Stripe) are fixed',
            notes='Wheel_F* sit at z 0.45 (R 0.45), Wheel_R* at z 0.80 (R 0.80). Open canopy: Glass = front screen.')


if __name__ == '__main__':
    CAR = build()
    tc.finish_body(CAR)
    _ws = [v for k in ('Wheel_RL', 'Wheel_RR') for v in tc.world_verts(CAR.objects[k])]
    META['width_body'] = max(v.x for v in _ws) - min(v.x for v in _ws)        # over the rear tyres
    print('tris', ck.tri_counts(CAR))
    print('qa', tc.qa(CAR, RR, WR_))
    if RENDER:
        print('render', tc.render_hero(CAR, os.path.join(tc.DOC_DIR, 'traffic_%s.png' % CAR_ID),
                                       cam_loc=(6.0, 6.6, 2.5), target=(0.0, -0.1, 1.20), lens=50.0,
                                       world_strength=0.9, sun_energy=3.8, exposure=-0.3, sun_rot=(0.80, 0.0, 2.30)))
    if EXPORT:
        RES, VER, DATA = tc.export(CAR, META)
        print('export', RES, VER)
        print('dims L %.3f W %.3f H %.3f wb %.3f' % (DATA['length'], DATA['width'], DATA['height_overall'],
                                                    DATA['wheelbase']))
    if KEEP_SOLO:
        tc.solo(CAR_ID)
