"""bus_coach - regional coach (Sunward Roads traffic vehicle #4).

Rebuilds SUNWARD_GODOT/Traffic/Traffic_bus_coach with tools/blender/car_kit.py (ProfileBody) and optionally renders
docs/blender_props/traffic_bus_coach.png and exports assets/imported/traffic/bus_coach.glb + .json.
Run like van_delivery.py (globals EXPORT, RENDER, KEEP_SOLO).

Spec: L 11.50, W 2.50, H 3.30 (roof pod; roof 3.22), wheelbase 6.20, wheels R 0.50 (22.5" polished wheels with ten
hand holes), front track 2.06, rear dual tyres (1.84 between the dual centres). Original design: raked one-piece
front with a big two-part windscreen (destination sign behind the upper glass), wrap-around black window band with
seven passenger bays per side, driver window (left), front door and middle door (right / kerb side), luggage bay
doors between the axles, engine hatch and tall lamp clusters at the rear, "rabbit-ear" mirrors, roof A/C pod.
Livery as two paint regions: Paint = teal skirt + pinstripe (repainted by the game), Trim = cream upper body
(fixed); 'Seal' = black window band / reveals. Passenger saloon lining (floor, walls, ceiling) is part of Body so the
merged traffic LOD stays opaque; Interior holds the driver area and 22 double seats.
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

CAR_ID = 'bus_coach'
CAR_NAME = 'Coach'
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
KEEP_SOLO = globals().get('KEEP_SOLO', False)

# ---------------------------------------------------------------------------------------------------- dimensions
WHEELBASE = 6.20
YF, YR = WHEELBASE / 2, -WHEELBASE / 2
WHEEL_R = 0.500
W_FRONT, W_DUAL, DUAL_GAP = 0.290, 0.265, 0.035
TRACK_F, TRACK_R = 2.06, 1.84
HW = 1.250
Z_ROOF = 3.220
Z_FLOOR = 1.220
LIVERY_Z = 1.400                  # teal skirt below, cream above
BAND = (1.580, 2.760)             # black window band
PIN = (2.860, 2.920)              # teal pinstripe above the window band
WS_A, WS_B = (5.52696, 1.300), (5.41872, 2.550)      # lower windscreen (marks on the front face line)
US_A, US_B = (5.41270, 2.620), (5.39706, 2.800)      # upper screen (destination sign)
RW_A, RW_B = (-5.87969, 2.800), (-5.91484, 2.050)    # rear window (CCW: top -> bottom)
PROFILE = [
    (-5.900, 0.420, 0.18),        # rear bottom
    (5.440, 0.340, 0.22),         # front bottom
    (5.540, 1.150, 0.60),         # front knee (bumper zone leans forward, glass leans back 5 deg)
    (5.360, Z_ROOF, 0.42),        # front roof edge
    (-5.860, Z_ROOF, 0.32),       # rear roof edge
    (-5.950, 1.300, 0.50),        # rear knee
]


def edge_r(y, z):
    return 0.130 + 0.050 * ck.smoothstep(5.10, 5.35, y)


BODY = ck.ProfileBody(PROFILE, HW, edge_r=edge_r, edge_segs=3, step=0.40, arc_step=0.04, flat_x=[0.85, 1.03],
                      splits=[('z', LIVERY_Z), ('z', BAND[0]), ('z', BAND[1]), ('z', PIN[0]), ('z', PIN[1])],
                      marks=[WS_A, WS_B, US_A, US_B, RW_A, RW_B])
ARCHES = [dict(y=YF, z=0.505, r=0.555, x_in=0.80, segs=40), dict(y=YR, z=0.505, r=0.555, x_in=0.58, segs=40)]
LINING = dict(d=0.040, z=(Z_FLOOR, 3.60), mats=dict(roof='Interior', wall='Interior', floor='InteriorDark',
                                                    fill='InteriorDark'))
BAY_Z = (1.620, 2.720)
BAYS = []
_y = -5.350
for _k in range(7):
    BAYS.append((_y, _y + 1.2786))
    _y += 1.2786 + 0.100
MID_DOOR = BAYS[4]                 # right side: the 5th bay is the middle door (0.16 .. 1.44)
FRONT_DOOR = (4.320, 5.150)

EYE = Vector((-0.720, 4.620, 2.420))
HUB = Vector((-0.720, 5.020, 1.960))
COLUMN_TILT = 55.0
SW_R = 0.245
PAINT_HEX, PAINT_LIN = '#1E7F86', (0.0129, 0.212, 0.238)
CREAM_LIN = (0.863, 0.791, 0.578)

WHEEL_BASE_SPEC = dict(R=WHEEL_R, rim_d_in=22.5, spokes=10, style='disc', segs=24, rim_segs=24, face_segs=24,
                       tyre='default', spoke_thick=0.024, spoke_dish=0.040, hub_r=0.115, nuts=0,
                       disc=dict(hole_r=0.034, ring_f=0.56), grooves=[-0.060, 0.060], groove_w=0.016, brake=False, disc_r=0.22,
                       caliper_angle=150.0, caliper_span=34.0)


def make_materials():
    m = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.0, paint_rough=0.28, paint_coat=0.5,
                             rim=(0.78, 0.79, 0.80), rim_metallic=1.0, rim_rough=0.22, caliper=(0.08, 0.08, 0.085),
                             interior=(0.11, 0.12, 0.14), interior_dark=(0.025, 0.026, 0.03))
    m['Trim'] = dict(base=CREAM_LIN, roughness=0.30, coat=0.4)            # cream livery (second paint region)
    m['Seal'] = dict(base=(0.012, 0.012, 0.014), roughness=0.35)           # black window band, seals
    m['Plastic'] = dict(base=(0.022, 0.022, 0.024), roughness=0.62)
    m['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.3)
    m['Plate'] = dict(base=(0.78, 0.78, 0.76), roughness=0.45)
    m['Sign'] = dict(base=(0.02, 0.015, 0.0), roughness=0.4, emission=(1.0, 0.55, 0.08), strength=1.2)
    m['Steel'] = dict(base=(0.045, 0.045, 0.048), metallic=0.5, roughness=0.55)
    m['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.04, alpha=0.34, double_sided=True)
    return m


def mat_fn(c, n, where):
    if where == 'band' and n.z < -0.7:
        return 'Underbody'
    if BAND[0] < c.z < BAND[1]:
        return 'Seal'
    if c.z < LIVERY_Z:
        return 'Paint'
    if PIN[0] < c.z < PIN[1] and c.y < 5.20 and (where == 'side' or abs(n.x) > 0.3 or c.y < -5.5):
        return 'Paint'
    return 'Trim'


def D(pts, L=0.03):
    return ck.densify(pts, L)


def L(S, pts, view, closed=False, width=0.007, mat='Seal'):
    pts = list(pts) + ([pts[0]] if closed else [])
    return S.line(pts, view, width=width, offset=0.0009, mat=mat, step=0.001, smooth=False)


def side_holes():
    holes = []
    for k, (y0, y1) in enumerate(BAYS):
        pts = [(y0, BAY_Z[0]), (y1, BAY_Z[0]), (y1, BAY_Z[1]), (y0, BAY_Z[1])]
        holes.append(dict(pts=pts, role='glass', fillet=0.05, fillet_n=2, side=-1 if k == 4 else 0, max_len=0.7))
    y0, y1 = MID_DOOR
    holes.append(dict(pts=[(y0, 1.420), (y1, 1.420), (y1, 2.720), (y0, 2.720)], role='glass', fillet=0.04,
                      fillet_n=2, side=1, max_len=0.7))
    y0, y1 = FRONT_DOOR
    holes.append(dict(pts=[(y0, 1.420), (y1, 1.420), (y1 - 0.035, 2.720), (y0, 2.720)], role='glass', fillet=0.04,
                      fillet_n=2, side=1, max_len=0.7))
    holes.append(dict(pts=[(y0, 1.480), (y1, 1.480), (y1 - 0.035, 2.720), (y0, 2.720)], role='glass', fillet=0.04,
                      fillet_n=2, side=-1, max_len=0.7))
    return holes


# ---------------------------------------------------------------------------------------------------- build
def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials(), group='Traffic')
    sh = BODY.build(car, arches=ARCHES, side_holes=side_holes(),
                    band_holes=[dict(a=WS_A, b=WS_B, x=(-1.03, 1.03), role='glass'),
                                dict(a=US_A, b=US_B, x=(-1.03, 1.03), role='glass'),
                                dict(a=RW_A, b=RW_B, x=(-0.85, 0.85), role='glass')],
                    lining=LINING, mat_fn=mat_fn, reveal_mat='Seal', reveal_depth=0.04)
    car.shell = sh
    S = sh.surface
    car.add('Body', sh.part, sh.reveals, sh.lining)
    car.add('Glass', sh.glass)
    B, LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    front(car, S, B, LH)
    t0 = B.tris()
    sides(car, S, B)
    t1 = B.tris()
    rear(car, S, B, LT, LB, LR)
    t2 = B.tris()
    roof_and_under(car, B)
    t3 = B.tris()
    car.info['width_body'] = 2 * max(abs(v.x) for v in sh.part.v + B.v)
    car.info['length_body'] = max(v.y for v in sh.part.v + B.v) - min(v.y for v in sh.part.v + B.v)
    mirrors(B)
    print('details: front %d sides %d rear %d roof/under %d mirrors %d' % (t0, t1 - t0, t2 - t1, t3 - t2, B.tris() - t3))
    car.add('Body', B)
    print('parts: shell %d reveals %d lining %d details %d glass %d' % (sh.part.tris(), sh.reveals.tris(),
                                                                         sh.lining.tris(), B.tris(), sh.glass.tris()))
    car.add('Lights_Head', LH)
    car.add('Lights_Tail', LT)
    car.add('Lights_Brake', LB)
    car.add('Lights_Reverse', LR)
    interior(car)
    wf, cf = ck.build_wheel(**dict(WHEEL_BASE_SPEC, W=W_FRONT))
    ck.add_axle(car, 'F', wf, cf, YF, TRACK_F / 2, WHEEL_R)
    wr, cr = ck.build_wheel(**dict(WHEEL_BASE_SPEC, W=W_DUAL))
    off = (W_DUAL + DUAL_GAP) / 2
    rr = 22.5 * 0.0254 / 2
    dual = ck.Part().extend(wr.translated((off, 0, 0)), ck.keep_outer_faces(wr, rr - 0.03).translated((-off, 0, 0)))
    ck.add_axle(car, 'R', dual, cr.translated((-off, 0, 0)), YR, TRACK_R / 2, WHEEL_R)
    car.socket('Socket_CamHood', (0.0, 5.00, 3.00))
    car.socket('Socket_CamCockpit', EYE)
    car.socket('Socket_CamBumper', (0.0, 5.68, 0.60))
    car.finalize()
    return car


def front(car, S, B, LH):
    plan = ck.rrect_pts(0.0, 5.470, 2 * HW - 0.012, 0.170, 0.080, n=3)
    B.extend(ck.sweep_axis('z', [0.300, 0.320, 0.600, 0.620],
                           [ck.offset_poly(plan, -0.015), plan, plan, ck.offset_poly(plan, -0.015)], 'Paint'))
    strip = ck.rrect_pts(0.0, 5.470, 2 * HW, 0.182, 0.086, n=3)
    B.extend(ck.sweep_axis('z', [0.430, 0.480], [strip, strip], 'Seal'))
    B.extend(ck.abox((-0.270, 5.553, 0.330), (0.270, 5.559, 0.425), 'Plate'))
    # grille + slats, headlamps wrapping round the corners, indicators
    g = D(ck.fillet_poly([(-0.620, 0.700), (0.620, 0.700), (0.620, 0.990), (-0.620, 0.990)], 0.04, n=2), 0.12)
    B.extend(S.patch(g, 'front', offset=0.004, depth=0.008, res=0.0, mat='Grille', smooth=False))
    for z in (0.770, 0.845, 0.920):
        sl = D(ck.rrect_pts(0.0, z, 1.180, 0.022, 0.009, n=1), 0.12)
        B.extend(S.patch(sl, 'front', offset=0.011, depth=0.010, res=0.0, mat='Seal', smooth=False))
    for sx in (1, -1):
        lamp = [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.700, 0.720), (HW - 0.020, 0.720), (HW - 0.012, 0.860),
                                                             (HW - 0.030, 0.930), (0.700, 0.930)], 0.03, n=2), 0.05)]
        LH.extend(S.patch(lamp, 'front', offset=0.006, depth=0.008, res=0.06, mat='HeadlightLens', smooth=False))
        B.extend(S.rim(lamp, 'front', width=0.014, offset=0.007, depth=0.006, mat='Seal', smooth=False))
        ind = [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.720, 0.960), (HW - 0.040, 0.960), (HW - 0.040, 1.000),
                                                            (0.720, 1.000)], 0.012, n=2), 0.06)]
        B.extend(S.patch(ind, 'front', offset=0.005, depth=0.006, res=0.0, mat='Amber', smooth=False))
    hc = S.snap('front', 0.980, 0.825)
    car.socket('Socket_HeadlightR', hc + Vector((0, 0.01, 0)))
    car.socket('Socket_HeadlightL', (-hc.x, hc.y + 0.01, hc.z))
    # destination sign (emissive) behind the upper screen
    B.extend(ck.abox((-0.880, 5.300, 2.645), (0.880, 5.330, 2.780), 'Sign'))
    for x0, x1 in ((-0.90, -0.06), (0.06, 0.90)):                    # long wipers at the screen base
        a = S.snap('front', x0, 1.360) + Vector((0, 0.020, 0))
        b = S.snap('front', x1, 1.430) + Vector((0, 0.020, 0))
        B.extend(ck.box_between(a, b, 0.018, 0.012, 'Plastic'))


def sides(car, S, B):
    for sx, view in ((1, 'right'), (-1, 'left')):
        # luggage bay doors between the axles (shut lines + handles)
        bays = [(-2.40, -0.85), (-0.75, 0.80), (0.90, 2.40)] if sx < 0 else [(-2.40, -1.20), (-1.10, 0.06),
                                                                            (1.54, 2.40)]
        for (y0, y1) in bays:
            B.extend(L(S, [(y0, 0.420), (y1, 0.420), (y1, 1.180), (y0, 1.180)], view, closed=True, width=0.006))
            B.extend(ck.abox((sx * (HW - 0.004), (y0 + y1) / 2 - 0.10, 1.090), (sx * (HW + 0.004), (y0 + y1) / 2 + 0.10,
                                                                                  1.120), 'Plastic'))
        # side marker lamps along the skirt, rear engine-bay vent
        for yy in (4.6, 2.6, 0.0, -2.6, -4.5):
            B.extend(ck.abox((sx * (HW - 0.002), yy - 0.035, 0.520), (sx * (HW + 0.004), yy + 0.035, 0.555), 'Amber'))
        v = D(ck.fillet_poly([(-5.20, 0.700), (-4.20, 0.700), (-4.20, 1.150), (-5.20, 1.150)], 0.03, n=2), 0.08)
        B.extend(S.patch(v, view, offset=0.003, depth=0.006, res=0.0, mat='Grille', smooth=False))
        for z in (0.78, 0.86, 0.94, 1.02, 1.10):
            B.extend(ck.abox((sx * (HW - 0.002), -5.18, z - 0.012), (sx * (HW + 0.004), -4.22, z + 0.012), 'Paint'))
    # doors (right / kerb side): leaf outlines, leaf split, rubber edges, handles
    for (y0, y1) in (FRONT_DOOR, MID_DOOR):
        door = [(y0 - 0.020, 0.400), (y1 + 0.020, 0.400), (y1 + 0.020, 2.760), (y0 - 0.020, 2.760)]
        B.extend(L(S, door, 'right', closed=True, width=0.016))
        ym = (y0 + y1) / 2
        B.extend(L(S, [(ym, 0.400), (ym, 2.760)], 'right', width=0.026))
        B.extend(L(S, [(y0 + 0.02, 1.380), (y1 - 0.02, 1.380)], 'right', width=0.012))
        B.extend(ck.abox((HW - 0.004, ym - 0.15, 1.150), (HW + 0.004, ym - 0.03, 1.175), 'Plastic'))
    # driver window sliding pane line (left)
    B.extend(L(S, [(4.720, 1.480), (4.720, 2.720)], 'left', width=0.012))


def mirrors(B):
    for sx in (1, -1):
        path = [Vector((sx * 1.080, 5.200, 3.120)), Vector((sx * 1.250, 5.480, 3.060)),
                Vector((sx * 1.340, 5.680, 2.880)), Vector((sx * 1.360, 5.700, 2.700))]
        B.extend(ck.rod_path(ck.cr_resample(path, closed=False, sub=3), 0.022, 'Plastic', n=8))
        B.extend(ck.rbox('z', 2.300, 2.720, (sx * 1.360, 5.700), 0.200, 0.080, 0.035, 'Plastic'))
        B.extend(ck.abox((sx * 1.270, 5.656, 2.320), (sx * 1.450, 5.660, 2.700), 'Chrome'))


def rear(car, S, B, LT, LB, LR):
    plan = ck.rrect_pts(0.0, -5.880, 2 * HW - 0.004, 0.150, 0.070, n=3)
    B.extend(ck.sweep_axis('z', [0.340, 0.360, 0.620, 0.640],
                           [ck.offset_poly(plan, -0.012), plan, plan, ck.offset_poly(plan, -0.012)], 'Paint'))
    B.extend(ck.abox((-0.270, -5.962, 0.400), (0.270, -5.956, 0.510), 'Plate'))
    # engine hatch: shut line, vent grilles, handle
    B.extend(L(S, [(-0.950, 0.720), (0.950, 0.720), (0.950, 1.900), (-0.950, 1.900)], 'rear', closed=True))
    for z0 in (1.05, 1.40):
        g = D(ck.fillet_poly([(-0.700, z0), (0.700, z0), (0.700, z0 + 0.22), (-0.700, z0 + 0.22)], 0.02, n=2), 0.12)
        B.extend(S.patch(g, 'rear', offset=0.004, depth=0.008, res=0.0, mat='Grille', smooth=False))
    B.extend(ck.abox((-0.12, -5.946, 0.830), (0.12, -5.930, 0.860), 'Plastic'))
    # tall lamp clusters at the rear corners
    for sx in (1, -1):
        def seg(z0, z1):
            return [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.990, z0), (HW - 0.014, z0), (HW - 0.014, z1),
                                                                (0.990, z1)], 0.010, n=2), 0.05)]
        LT.extend(S.patch(seg(1.300, 1.560), 'rear', offset=0.006, depth=0.007, res=0.07, mat='TaillightLens',
                          smooth=False))
        B.extend(S.patch(seg(1.160, 1.300), 'rear', offset=0.006, depth=0.007, res=0.07, mat='Amber', smooth=False))
        LB.extend(S.patch(seg(0.960, 1.160), 'rear', offset=0.006, depth=0.007, res=0.07, mat='BrakeLens',
                          smooth=False))
        LR.extend(S.patch(seg(0.780, 0.960), 'rear', offset=0.006, depth=0.007, res=0.07, mat='ReverseLens',
                          smooth=False))
        B.extend(S.rim(seg(0.780, 1.560), 'rear', width=0.012, offset=0.007, depth=0.006, mat='Seal', smooth=False))
    hb = D(ck.rrect_pts(0.0, 3.020, 0.600, 0.050, 0.012, n=2), 0.04)
    LB.extend(S.patch(hb, 'rear', offset=0.006, depth=0.007, res=0.0, mat='BrakeLens', smooth=False))
    B.extend(S.rim(hb, 'rear', width=0.010, offset=0.007, depth=0.005, mat='Seal', smooth=False))


def roof_and_under(car, B):
    # roof A/C pod (cream) and two escape hatches
    B.extend(ck.rbox('y', -2.700, -0.500, (0.0, Z_ROOF), 1.500, 0.160, 0.060, 'Trim', n=2))
    for yy in (2.4, -3.6):
        B.extend(ck.rbox('y', yy - 0.35, yy + 0.35, (0.0, Z_ROOF + 0.005), 0.700, 0.050, 0.020, 'Seal', n=1))
    # running gear: front beam axle, rear axle + diff, engine / gearbox block, exhaust
    B.extend(ck.abox((-0.950, YF - 0.060, 0.420), (0.950, YF + 0.060, 0.540), 'Steel'))
    B.extend(ck.rod((-0.62, YR, WHEEL_R), (0.62, YR, WHEEL_R), 0.080, 'Steel', n=10))
    B.extend(ck.ellipsoid((0.0, YR, WHEEL_R), (0.22, 0.26, 0.22), 'Steel', nu=12, nv=8))
    B.extend(ck.abox((-0.600, -5.500, 0.380), (0.600, -3.900, 0.420), 'Underbody'))
    B.extend(ck.rod((-0.800, -5.300, 0.400), (-0.860, -5.880, 0.360), 0.045, 'Steel', n=10))
    B.extend(ck.tube((-0.860, -5.870, 0.360), (-0.862, -5.960, 0.355), 0.050, 0.042, 'Steel', 'Underbody', n=12))
    car.socket('Socket_Exhaust', (-0.862, -5.965, 0.355))


def double_seat(xc, yf, yb, zf, w=0.900):
    """Coach double seat: cushion, tall reclined backrest, leg frame (~70 tris)."""
    p = ck.Part()
    zc = zf + 0.420
    p.extend(ck.rbox('y', yb, yf, (xc, zc), w, 0.110, 0.030, 'Interior', n=1))
    M = Matrix.Translation((0.0, yb + 0.05, zc)) @ Matrix.Rotation(math.radians(12.0), 4, 'X')
    p.extend(ck.rbox('z', 0.0, 0.820, (xc, 0.0), w - 0.02, 0.100, 0.035, 'Interior', n=1).transformed(M))
    p.extend(ck.abox((xc - w / 2 + 0.06, yb + 0.12, zf), (xc + w / 2 - 0.06, yb + 0.16, zc - 0.05), 'InteriorDark'))
    return p


def interior(car):
    I = ck.Part()
    zf = Z_FLOOR
    # driver area: seat on a pedestal, dash, column shroud
    I.extend(ck.simple_seat(-0.720, 4.820, 4.330, zf + 0.380, width=0.54, back_h=0.70, recline=12.0))
    I.extend(ck.abox((-0.92, 4.380, zf), (-0.52, 4.760, zf + 0.385), 'InteriorDark'))
    prof = [(5.470, zf + 0.01), (5.470, 1.520), (5.250, 1.700), (5.080, 1.700), (5.030, 1.600), (5.120, zf + 0.01)]
    I.extend(ck.sweep_axis('x', [-1.180, 0.250], [prof, prof], 'InteriorDark'))
    for x in (-0.800, -0.640):
        I.extend(ck.gauge((x, 5.045, 1.640), (0.0, -1.0, 0.25), 0.060))
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.08, HUB + col * 0.32, 0.080, 0.090, 'InteriorDark'))
    # 22 double seats (2 + 2 with an aisle), none at the middle door well
    for k in range(12):
        yf = 3.900 - k * 0.790
        yb = yf - 0.480
        for sx in (1, -1):
            if sx > 0 and MID_DOOR[0] - 0.55 < yf < MID_DOOR[1] + 0.35:
                continue
            I.extend(double_seat(sx * 0.705, yf, yb, zf))
    # luggage racks along the window tops
    for sx in (1, -1):
        I.extend(ck.rbox('y', -5.400, 4.200, (sx * 1.030, 2.880), 0.300, 0.050, 0.020, 'InteriorDark', n=1))
        I.extend(ck.rbox('y', -5.400, 4.200, (sx * 0.890, 2.840), 0.030, 0.090, 0.012, 'InteriorDark', n=1))
    car.add('Interior', I)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.017, 0.020), segs=20, flat_bottom=False, hub_r=0.075,
                                spokes=((0.0, 0.055), (180.0, 0.055), (270.0, 0.050)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


META = dict(cls='regional coach (2 axles, dual rear tyres, front + middle door)', drivetrain='RWD',
            engine='rear, 10.5 turbo-diesel I6', doors=2, seats=45, sw_radius=SW_R, eye=EYE,
            paint_hex=PAINT_HEX, paint_lin=PAINT_LIN, finish='gloss', height_roof=Z_ROOF,
            rim_diameter_in_front=22.5, rim_diameter_in_rear=22.5, tyre_width_nominal=W_FRONT,
            wheel_width_note='rear wheel objects hold dual tyres (2 x 0.265 + 0.035 gap)',
            livery='Paint = teal skirt + pinstripe (repaintable); Trim = cream upper body (fixed); Seal = black '
                   'window band', cargo={'floor_height': Z_FLOOR, 'luggage_bays': 'between the axles, both sides'},
            notes='Passenger saloon lining is part of Body so the merged traffic LOD stays opaque; Interior = driver '
                  'area, 22 double seats, luggage racks. height = roof 3.22, height_overall = A/C pod 3.30.')


if __name__ == '__main__':
    CAR = build()
    tc.finish_body(CAR)
    META['width_body'] = CAR.info['width_body']
    META['length_body'] = CAR.info['length_body']
    print('tris', ck.tri_counts(CAR))
    print('qa', tc.qa(CAR, WHEEL_R, W_FRONT))
    if RENDER:
        print('render', tc.render_hero(CAR, os.path.join(tc.DOC_DIR, 'traffic_%s.png' % CAR_ID),
                                       cam_loc=(12.6, 15.8, 3.6), target=(0.0, -0.6, 1.55), lens=50.0,
                                       world_strength=0.9, sun_energy=3.8, exposure=-0.5, sun_rot=(0.80, 0.0, 2.30)))
    if EXPORT:
        RES, VER, DATA = tc.export(CAR, META)
        print('export', RES, VER)
        print('dims L %.3f W %.3f H %.3f wb %.3f' % (DATA['length'], DATA['width'], DATA['height_overall'],
                                                    DATA['wheelbase']))
    if KEEP_SOLO:
        tc.solo(CAR_ID)
