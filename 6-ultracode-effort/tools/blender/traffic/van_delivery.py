"""van_delivery - panel delivery van (Sunward Roads traffic vehicle #2).

Rebuilds SUNWARD_GODOT/Traffic/Traffic_van_delivery from scratch with tools/blender/car_kit.py (ProfileBody) and
optionally renders docs/blender_props/traffic_van_delivery.png and exports assets/imported/traffic/van_delivery.glb
+ .json (the caller saves the master .blend: traffic_common STEP='save').

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\traffic\\van_delivery.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: EXPORT (bool), RENDER (bool), KEEP_SOLO (bool: leave the other
car / traffic collections excluded for `look`; run traffic_common STEP='restore' afterwards).

Spec: L 5.00 (bumper to bumper), W 2.00 (body), H 2.40, wheelbase 3.20, track 1.72, wheels R 0.33 (16" steel,
215 tyres). Original design: short sloping bonnet, 37 deg windscreen, tall box with rounded roof edges, two cab
doors, a sliding side door on the right (kerb) side, twin rear doors with tinted windows, black plastic bumpers,
side mouldings and arch flares, vertical rear lamp clusters, big two-arm mirrors. White with an orange belt stripe
(Paint = white, repainted by the game; 'Stripe' keeps its colour). Simple cab interior (2 seats, dash, wheel);
the cab lining (inner skin + bulkhead) is part of Body so the merged traffic LOD stays opaque behind the glass.
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

CAR_ID = 'van_delivery'
CAR_NAME = 'Delivery Van'
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
KEEP_SOLO = globals().get('KEEP_SOLO', False)

# ---------------------------------------------------------------------------------------------------- dimensions
WHEELBASE = 3.20
YF, YR = WHEELBASE / 2, -WHEELBASE / 2
TRACK = 1.72
WHEEL_R, WHEEL_W = 0.330, 0.215
ARCH_R, ARCH_Z = 0.372, 0.338
HW = 0.982                        # body half width (1.964 m; 2.00 m over the arch flares)
Y_REAR, Z_BOT, Z_ROOF = -2.455, 0.360, 2.390
COWL = (1.660, 1.300)
HEADER = (0.850, Z_ROOF)
WS_BASE = (1.6154, 1.360)         # windscreen glass base / top (marks on the straight windscreen line)
WS_TOP = (1.0209, 2.160)
RW_TOP, RW_BOT = (Y_REAR, 2.150), (Y_REAR, 1.560)
STRIPE = (0.950, 1.120)
STRIPE_Y1 = 2.050                 # front end of the stripe (clean vertical cut ahead of the front arch)
PROFILE = [
    (Y_REAR, Z_BOT + 0.02, 0.09),     # rear bottom
    (2.400, Z_BOT, 0.09),             # front bottom (behind the bumper)
    (2.475, 0.880, 0.14),             # nose: lower fascia top
    (2.340, 1.100, 0.10),             # bonnet front edge
    (COWL[0], COWL[1], 0.06),         # cowl (concave)
    (HEADER[0], HEADER[1], 0.28),     # windscreen header
    (Y_REAR, Z_ROOF, 0.15),           # rear roof corner
]


def edge_r(y, z):
    return 0.060 + 0.050 * ck.smoothstep(1.85, 2.30, z)


BODY = ck.ProfileBody(PROFILE, HW, edge_r=edge_r, edge_segs=3, step=0.30, arc_step=0.03, flat_x=[0.07, 0.84],
                      splits=[('z', STRIPE[0]), ('z', STRIPE[1]), ('y', STRIPE_Y1)], marks=[WS_BASE, WS_TOP, RW_TOP, RW_BOT])
ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.62), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.62)]
DOOR_WIN = [(0.550, 1.400), (1.410, 1.400), (0.830, 2.180), (0.550, 2.180)]
LINING = dict(d=0.035, y=(0.420, 1.660), z=(0.750, 3.0))

EYE = Vector((-0.480, 0.700, 1.960))
HUB = Vector((-0.480, 1.190, 1.500))
COLUMN_TILT = 34.0
SW_R = 0.190
SEAT_Y = (1.060, 0.620)
SEAT_Z = 1.100
PAINT_HEX, PAINT_LIN = '#ECEDEA', (0.838, 0.846, 0.823)

WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=16, spokes=8, style='slot', segs=28, rim_segs=28, face_segs=28,
                  tyre='tall', spoke_thick=0.020, spoke_dish=0.030, hub_r=0.062, nuts=0,
                  grooves=[-0.045, 0.045], groove_w=0.014, brake=False, disc_r=0.150, caliper_angle=150.0, caliper_span=40.0)


def make_materials():
    m = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.0, paint_rough=0.34, paint_coat=0.35,
                             rim=(0.20, 0.205, 0.215), rim_metallic=0.55, rim_rough=0.42, caliper=(0.08, 0.08, 0.085),
                             interior=(0.085, 0.087, 0.092), interior_dark=(0.020, 0.020, 0.022))
    m['Trim'] = dict(base=(0.022, 0.022, 0.024), roughness=0.62)
    m['Stripe'] = dict(base=(0.807, 0.162, 0.010), roughness=0.34, coat=0.3)
    m['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.3)
    m['Plate'] = dict(base=(0.78, 0.78, 0.76), roughness=0.45)
    m['Steel'] = dict(base=(0.20, 0.20, 0.21), metallic=0.8, roughness=0.45)
    m['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.04, alpha=0.32, double_sided=True)
    return m


def mat_fn(c, n, where):
    if where == 'band' and n.z < -0.7:
        return 'Underbody'
    if STRIPE[0] < c.z < STRIPE[1] and c.y < STRIPE_Y1 and (where == 'side' or abs(n.x) > 0.3 or c.y < -2.2):
        return 'Stripe'
    return 'Paint'


def D(pts, L=0.03):
    return ck.densify(pts, L)


def L(S, pts, view, closed=False, width=0.005):
    """Shut line through the given corner points only (flat panels need no extra samples)."""
    pts = list(pts) + ([pts[0]] if closed else [])
    return S.line(pts, view, width=width, offset=0.0009, mat='Trim', step=0.001, smooth=False)


# ---------------------------------------------------------------------------------------------------- build
def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials(), group='Traffic')
    sh = BODY.build(car, arches=ARCHES, side_holes=[dict(pts=DOOR_WIN, role='glass', fillet=0.05)],
                    band_holes=[dict(a=WS_BASE, b=WS_TOP, x=(-0.84, 0.84), role='glass'),
                                dict(a=RW_TOP, b=RW_BOT, x=(0.07, 0.84), role='black'),
                                dict(a=RW_TOP, b=RW_BOT, x=(-0.84, -0.07), role='black')],
                    lining=LINING, mat_fn=mat_fn, reveal_mat='Trim')
    car.shell = sh
    S = sh.surface
    car.add('Body', sh.part, sh.reveals, sh.lining)
    car.add('Glass', sh.glass)
    B, LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    front(car, S, B, LH)
    sides(car, S, B)
    rear(car, S, B, LT, LB, LR)
    car.info['width_body'] = 2 * max(abs(v.x) for v in sh.part.v + B.v)     # before the mirrors are added
    mirrors(B)
    car.add('Body', B)
    print('parts: shell %d reveals %d lining %d details %d glass %d' % (sh.part.tris(), sh.reveals.tris(),
                                                                         sh.lining.tris(), B.tris(), sh.glass.tris()))
    car.add('Lights_Head', LH)
    car.add('Lights_Tail', LT)
    car.add('Lights_Brake', LB)
    car.add('Lights_Reverse', LR)
    interior(car)
    wheel, cal = ck.build_wheel(**WHEEL_SPEC)
    ck.add_axle(car, 'F', wheel, cal, YF, TRACK / 2, WHEEL_R)
    ck.add_axle(car, 'R', wheel, cal, YR, TRACK / 2, WHEEL_R)
    car.socket('Socket_CamHood', (0.0, 1.85, 1.62))
    car.socket('Socket_CamCockpit', EYE)
    car.socket('Socket_CamBumper', (0.0, 2.62, 0.55))
    car.finalize()
    return car


def front(car, S, B, LH):
    # wrap-around black bumper (plan rounded rectangle, bevelled top / bottom)
    plan = ck.rrect_pts(0.0, 2.365, 2 * HW + 0.036, 0.270, 0.130, n=4)
    B.extend(ck.sweep_axis('z', [0.280, 0.300, 0.600, 0.630],
                           [ck.offset_poly(plan, -0.018), plan, plan, ck.offset_poly(plan, -0.022)], 'Trim'))
    B.extend(ck.abox((-0.60, 2.485, 0.318), (0.60, 2.502, 0.345), 'Grille'))          # lower air slot
    B.extend(ck.abox((-0.265, 2.500, 0.405), (0.265, 2.506, 0.515), 'Plate'))         # blank number plate
    B.extend(ck.abox((-0.275, 2.497, 0.398), (0.275, 2.502, 0.522), 'Trim'))
    for sx in (1, -1):                                                                  # fog lamps
        B.extend(ck.disc((sx * 0.78, 2.4545, 0.470), (0, 1, 0), 0.045, 'Grille', n=14, ring_mat='Trim', ring_w=0.012))
    # grille (black) with three slats, between the headlamps
    g = D(ck.fillet_poly([(-0.470, 0.660), (0.470, 0.660), (0.490, 0.965), (-0.490, 0.965)], 0.03, n=3), 0.04)
    B.extend(S.patch(g, 'front', offset=0.004, depth=0.008, res=0.05, mat='Grille', smooth=False))
    for z in (0.745, 0.825, 0.905):
        sl = D(ck.rrect_pts(0.0, z, 0.900, 0.020, 0.008, n=2), 0.04)
        B.extend(S.patch(sl, 'front', offset=0.010, depth=0.010, res=0.0, mat='Trim', smooth=False))
    # bonnet shut line + emblem-free badge plate
    B.extend(L(S, [(-0.90, 1.035), (0.90, 1.035)], 'front'))
    # headlamps wrapping round the nose corners, dark housing frame, amber indicator below
    for sx in (1, -1):
        lamp = [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.530, 0.880), (HW - 0.055, 0.850), (HW - 0.006, 0.900),
                                                             (HW - 0.012, 1.040), (0.580, 1.050)], 0.035, n=3), 0.03)]
        LH.extend(S.patch(lamp, 'front', offset=0.006, depth=0.008, res=0.03, mat='HeadlightLens', smooth=False))
        B.extend(S.rim(lamp, 'front', width=0.012, offset=0.007, depth=0.006, mat='Trim', smooth=False))
        ind = [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.62, 0.800), (0.92, 0.790), (0.95, 0.835),
                                                            (0.64, 0.840)], 0.012, n=2), 0.03)]
        B.extend(S.patch(ind, 'front', offset=0.005, depth=0.006, res=0.0, mat='Amber', smooth=False))
    hc = S.snap('front', 0.760, 0.955)
    car.socket('Socket_HeadlightR', hc + Vector((0, 0.01, 0)))
    car.socket('Socket_HeadlightL', (-hc.x, hc.y + 0.01, hc.z))
    # wipers on the windscreen base
    for x0, x1 in ((-0.78, -0.10), (0.02, 0.70)):
        a = S.snap('front', x0, 1.415) + Vector((0, 0.012, 0.010))
        b = S.snap('front', x1, 1.470) + Vector((0, 0.012, 0.010))
        B.extend(ck.box_between(a, b, 0.016, 0.010, 'Trim'))
        B.extend(ck.box_between(a + Vector((0, 0.03, -0.04)), a, 0.020, 0.016, 'Trim'))


def sides(car, S, B):
    for sx, view in ((1, 'right'), (-1, 'left')):
        # cab door shut line: B-pillar edge, bottom, front edge over the arch, A-pillar, roof edge
        door = [(0.500, 2.215), (0.500, 0.440), (1.150, 0.440), (1.158, 0.499), (1.240, 0.640), (1.365, 0.745),
                (1.478, 0.792), (1.560, 0.810), (1.545, 1.290), (0.854, 2.215)]
        B.extend(L(S, door, view, closed=True))
        B.extend(ck.abox((sx * (HW - 0.005), 0.600, 1.255), (sx * (HW + 0.016), 0.760, 1.290), 'Trim'))  # handle
        # side rubbing strips (black) between / behind the arches
        for (y0, y1) in ((-1.165, 1.165), (-2.380, -2.010), (2.010, 2.260)):
            B.extend(ck.rbox('y', y0, y1, (sx * (HW + 0.004), 0.560), 0.020, 0.110, 0.006, 'Trim'))
        # black plastic arch flares
        for a in ARCHES:
            fl = ck.arch_flare(a['y'], a['z'], a['r'] - 0.003, a['r'] + 0.058, HW + 0.018, HW, a0=4.0, a1=176.0, segs=20,
                               mat='Trim')
            B.extend(fl if sx > 0 else fl.mirrored_x())
        # side marker (amber) behind the front arch
        mk = D(ck.rrect_pts(1.880, 0.700, 0.070, 0.030, 0.010, n=2), 0.02)
        B.extend(S.patch(mk, view, offset=0.003, depth=0.005, res=0.0, mat='Amber', smooth=False))
    # sliding door (right / kerb side): shut lines, rail cover, handle, step
    sd = [(0.440, 2.215), (0.440, 0.440), (-0.700, 0.440), (-0.700, 2.215)]
    B.extend(L(S, sd, 'right', closed=True))
    B.extend(ck.rbox('y', -2.300, -0.720, (HW + 0.006, 1.470), 0.022, 0.050, 0.008, 'Trim'))
    B.extend(ck.abox((HW - 0.005, -0.660, 1.240), (HW + 0.016, -0.500, 1.275), 'Trim'))
    B.extend(ck.abox((HW - 0.200, -0.680, 0.330), (HW - 0.008, 0.420, 0.380), 'Trim'))
    # fuel flap (left)
    B.extend(L(S, ck.rrect_pts(-1.120, 0.880, 0.150, 0.110, 0.02, n=1), 'left', closed=True, width=0.004))


def mirrors(B):
    for sx in (1, -1):
        B.extend(ck.rod((sx * (HW - 0.01), 1.460, 1.440), (sx * (HW + 0.08), 1.380, 1.480), 0.016, 'Trim', n=8))
        B.extend(ck.rod((sx * (HW - 0.01), 1.240, 1.720), (sx * (HW + 0.08), 1.335, 1.745), 0.014, 'Trim', n=8))
        B.extend(ck.rbox('z', 1.430, 1.820, (sx * (HW + 0.145), 1.360), 0.150, 0.070, 0.028, 'Trim'))
        B.extend(ck.abox((sx * (HW + 0.078), 1.322, 1.455), (sx * (HW + 0.212), 1.326, 1.795), 'Chrome'))
        B.extend(ck.rbox('y', 1.400, 1.530, (sx * HW, 1.440), 0.040, 0.060, 0.018, 'Trim'))     # mirror foot


def rear(car, S, B, LT, LB, LR):
    plan = ck.rrect_pts(0.0, -2.395, 2 * HW + 0.036, 0.210, 0.090, n=4)
    B.extend(ck.sweep_axis('z', [0.300, 0.320, 0.530, 0.555],
                           [ck.offset_poly(plan, -0.016), plan, plan, ck.offset_poly(plan, -0.020)], 'Trim'))
    B.extend(ck.abox((-0.46, -2.490, 0.550), (0.46, -2.320, 0.566), 'Grille'))           # step pad
    # twin rear doors: centre + outer shut lines, handle, hinges, plate
    B.extend(L(S, [(0.0, 0.600), (0.0, 2.270)], 'rear', width=0.006))
    rd = [(-0.880, 0.600), (0.880, 0.600), (0.880, 2.270), (-0.880, 2.270)]
    B.extend(L(S, rd, 'rear', closed=True))
    B.extend(ck.abox((0.060, -2.478, 1.230), (0.200, -2.455, 1.268), 'Trim'))
    for sx in (1, -1):
        for z in (0.760, 1.450, 2.080):
            B.extend(ck.abox((sx * 0.845, -2.472, z), (sx * 0.905, -2.452, z + 0.07), 'Trim'))
    pl = D(ck.rrect_pts(0.0, 0.700, 0.520, 0.110, 0.008, n=2), 0.03)
    B.extend(S.patch(pl, 'rear', offset=0.004, depth=0.005, res=0.0, mat='Plate', smooth=False))
    B.extend(S.rim(pl, 'rear', width=0.008, offset=0.005, depth=0.004, mat='Trim', smooth=False))
    # vertical rear lamp clusters on the corner pillars (tail / indicator / brake / reverse), dark housing
    for sx in (1, -1):
        def seg(z0, z1):
            return [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.892, z0), (HW - 0.007, z0), (HW - 0.007, z1), (0.892, z1)],
                                                                0.008, n=2), 0.025)]
        LT.extend(S.patch(seg(1.080, 1.300), 'rear', offset=0.006, depth=0.007, res=0.03, mat='TaillightLens',
                          smooth=False))
        B.extend(S.patch(seg(0.950, 1.080), 'rear', offset=0.006, depth=0.007, res=0.03, mat='Amber', smooth=False))
        LB.extend(S.patch(seg(0.790, 0.950), 'rear', offset=0.006, depth=0.007, res=0.03, mat='BrakeLens',
                          smooth=False))
        LR.extend(S.patch(seg(0.640, 0.790), 'rear', offset=0.006, depth=0.007, res=0.03, mat='ReverseLens',
                          smooth=False))
        B.extend(S.rim(seg(0.640, 1.300), 'rear', width=0.010, offset=0.007, depth=0.006, mat='Trim', smooth=False))
    hb = D(ck.rrect_pts(0.0, 2.300, 0.300, 0.040, 0.010, n=2), 0.03)                     # high-mounted brake lamp
    LB.extend(S.patch(hb, 'rear', offset=0.006, depth=0.007, res=0.0, mat='BrakeLens', smooth=False))
    B.extend(S.rim(hb, 'rear', width=0.008, offset=0.007, depth=0.005, mat='Trim', smooth=False))
    # exhaust under the right rear corner
    B.extend(ck.rod((0.560, -1.800, 0.332), (0.600, -2.380, 0.318), 0.030, 'Steel', n=10))
    B.extend(ck.tube((0.600, -2.370, 0.318), (0.602, -2.455, 0.316), 0.034, 0.028, 'Steel', 'Underbody', n=12))
    car.socket('Socket_Exhaust', (0.602, -2.460, 0.316))
    # floor pan / chassis shadows: spare wheel carrier under the rear
    B.extend(ck.abox((-0.42, -2.30, 0.230), (0.42, -1.95, 0.360), 'Underbody'))


def interior(car):
    I = ck.Part()
    zf = LINING['z'][0]
    for x in (-0.480, 0.480):
        I.extend(ck.simple_seat(x, SEAT_Y[0], SEAT_Y[1], SEAT_Z, width=0.50, back_h=0.62, recline=13.0))
        I.extend(ck.abox((x - 0.20, SEAT_Y[1] + 0.05, zf), (x + 0.20, SEAT_Y[0] - 0.08, SEAT_Z + 0.01), 'InteriorDark'))
    # dash: extruded side profile across the cab
    prof = [(1.640, zf + 0.01), (1.640, 1.245), (1.500, 1.375), (1.330, 1.400), (1.270, 1.330), (1.300, 1.060),
            (1.430, zf + 0.01)]
    I.extend(ck.sweep_axis('x', [-0.925, 0.925], [prof, prof], 'InteriorDark'))
    I.extend(ck.abox((-0.700, 1.300, 1.392), (0.150, 1.420, 1.415), 'Interior'))          # dash top pad
    for x in (-0.555, -0.405):
        I.extend(ck.gauge((x, 1.292, 1.300), (0.0, -1.0, 0.22), 0.055))
    I.extend(ck.abox((-0.08, 1.285, 1.140), (0.08, 1.300, 1.260), 'Gauge'))                # radio / screen
    I.extend(ck.rod((0.0, 1.300, 1.020), (0.0, 1.170, 1.160), 0.010, 'InteriorDark', n=8))  # gear lever
    I.extend(ck.ellipsoid((0.0, 1.165, 1.170), (0.025, 0.025, 0.030), 'Interior', nu=10, nv=6))
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.07, HUB + col * 0.20, 0.070, 0.080, 'InteriorDark'))
    for x in (-0.420, -0.300):
        I.extend(ck.box_between((x, 1.360, zf + 0.10), (x, 1.300, zf + 0.20), 0.080, 0.014, 'InteriorDark'))
    car.add('Interior', I)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.016, 0.019), segs=24, flat_bottom=False, hub_r=0.060,
                                spokes=((0.0, 0.05), (180.0, 0.05), (270.0, 0.045)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


META = dict(cls='panel delivery van', drivetrain='RWD', engine='front, 2.2 turbo-diesel I4', doors=4, seats=2,
            sw_radius=SW_R, eye=EYE, paint_hex=PAINT_HEX, paint_lin=PAINT_LIN, finish='gloss',
            height_roof=Z_ROOF, rim_diameter_in_front=16, rim_diameter_in_rear=16, tyre_width_nominal=WHEEL_W,
            livery='Paint (white, repaintable) + Stripe (orange belt stripe, fixed colour)',
            cargo={'floor_height': 0.56, 'inner_length_approx': 2.80, 'side_door': 'sliding, right (kerb) side',
                   'rear_doors': 'twin hinged'},
            notes='Cab lining (inner skin + bulkhead) is part of Body so the merged traffic LOD stays opaque.')


if __name__ == '__main__':
    CAR = build()
    tc.finish_body(CAR)
    META['width_body'] = CAR.info['width_body']
    print('tris', ck.tri_counts(CAR))
    print('qa', tc.qa(CAR, WHEEL_R, WHEEL_W))
    if RENDER:
        print('render', tc.render_hero(CAR, os.path.join(tc.DOC_DIR, 'traffic_%s.png' % CAR_ID),
                                       cam_loc=(6.6, 7.6, 2.4), target=(0.0, -0.1, 1.15), lens=50.0,
                                       world_strength=0.9, sun_energy=3.8, exposure=-0.6, sun_rot=(0.80, 0.0, 2.30)))
    if EXPORT:
        RES, VER, DATA = tc.export(CAR, META)
        print('export', RES, VER)
        print('dims L %.3f W %.3f H %.3f wb %.3f' % (DATA['length'], DATA['width'], DATA['height_overall'],
                                                    DATA['wheelbase']))
    if KEEP_SOLO:
        tc.solo(CAR_ID)
