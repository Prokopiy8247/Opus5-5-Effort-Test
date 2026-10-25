"""pickup_work - older single-cab work pickup with a flatbed (Sunward Roads traffic vehicle #6).

Rebuilds SUNWARD_GODOT/Traffic/Traffic_pickup_work with tools/blender/car_kit.py (ProfileBody) and optionally renders
docs/blender_props/traffic_pickup_work.png and exports assets/imported/traffic/pickup_work.glb + .json.
Run like van_delivery.py (globals EXPORT, RENDER, KEEP_SOLO).

Spec: L 5.20, W 1.90 (over the fender flares), H 1.80, wheelbase 3.20, track 1.60, wheels R 0.38 (16" white steel
disc wheels). Original design, deliberately unlike the player's Hauler 2500 (modern crew cab, chrome, dark paint):
boxy 1980s-style single cab with slab sides and small edge radii, flat bonnet with separate panel seams, upright
36 deg windscreen, door quarter-light, grey steel bumpers and grille surround with rectangular lamps, amber roof
beacon, square mirrors on arms; behind the cab a steel-framed flatbed with a wooden deck, tubular side / rear rails
on stake posts, a headache rack, black mudguards over the rear wheels, step bumper with tow hitch. White (Paint)
with grey steel trim. Interior: 3-seat bench, dash with two dials, thin two-spoke wheel.
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

CAR_ID = 'pickup_work'
CAR_NAME = 'Work Pickup'
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
KEEP_SOLO = globals().get('KEEP_SOLO', False)

# ---------------------------------------------------------------------------------------------------- dimensions
WHEELBASE = 3.20
YF, YR = WHEELBASE / 2, -WHEELBASE / 2
TRACK = 1.60
WHEEL_R, WHEEL_W = 0.380, 0.235
ARCH_R, ARCH_Z = 0.415, 0.388
HW = 0.930                        # cab / bonnet half width (flares -> 1.90)
Y_FRONT, Y_REAR = 2.480, -2.615   # bumper faces (L 5.20 incl. the tow ball at -2.72)
Z_BOT, Z_ROOF = 0.560, 1.800
Y_CAB_R = 0.100
COWL = (1.300, 1.190)
HEADER = (0.840, 1.790)
WS_A, WS_B = (1.2617, 1.240), (0.9013, 1.710)         # windscreen glass (marks on the screen line)
RW_A, RW_B = (Y_CAB_R, 1.650), (Y_CAB_R, 1.300)       # cab rear window (top -> bottom, CCW)
PROFILE = [
    (Y_CAB_R, Z_BOT, 0.06),           # cab rear bottom
    (2.380, Z_BOT, 0.06),             # front bottom (behind the bumper)
    (2.420, 1.100, 0.06),             # grille top / bonnet front edge
    (COWL[0], COWL[1], 0.04),         # cowl (concave)
    (HEADER[0], HEADER[1], 0.10),     # windscreen header
    (Y_CAB_R, Z_ROOF, 0.08),          # roof rear edge
]
BODY = ck.ProfileBody(PROFILE, HW, edge_r=0.045, edge_segs=3, step=0.25, arc_step=0.025, flat_x=[0.55, 0.80],
                      marks=[WS_A, WS_B, RW_A, RW_B])
ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.62, segs=48)]
DOOR_WIN = [(0.240, 1.220), (1.130, 1.220), (0.800, 1.690), (0.240, 1.690)]
LINING = dict(d=0.030, y=(0.000, 1.300), z=(0.740, 2.5))
DECK = dict(y0=-2.570, y1=0.020, hw=0.945, z0=0.980, z1=1.040)
RAIL_Z = 1.330

EYE = Vector((-0.420, 0.420, 1.560))
HUB = Vector((-0.420, 0.880, 1.150))
COLUMN_TILT = 26.0
SW_R = 0.200
PAINT_HEX, PAINT_LIN = '#EFEFEA', (0.863, 0.863, 0.823)

WHEEL_SPEC = dict(R=WHEEL_R, W=WHEEL_W, rim_d_in=16, spokes=6, style='disc', segs=28, rim_segs=28, face_segs=28,
                  tyre='tall', spoke_thick=0.020, spoke_dish=0.030, hub_r=0.070, nuts=0, brake=False,
                  disc=dict(hole_r=0.026, ring_f=0.58), grooves=[-0.050, 0.050], groove_w=0.014, disc_r=0.16,
                  caliper_angle=150.0, caliper_span=40.0)


def make_materials():
    m = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.0, paint_rough=0.38, paint_coat=0.2,
                             rim=(0.70, 0.70, 0.68), rim_metallic=0.15, rim_rough=0.40, caliper=(0.08, 0.08, 0.085),
                             interior=(0.16, 0.15, 0.13), interior_dark=(0.030, 0.029, 0.028))
    m['Trim'] = dict(base=(0.30, 0.31, 0.32), metallic=0.35, roughness=0.45)    # grey painted steel
    m['Chrome'] = dict(base=(0.75, 0.76, 0.78), metallic=1.0, roughness=0.2)
    m['Steel'] = dict(base=(0.12, 0.12, 0.125), metallic=0.5, roughness=0.5)
    m['Wood'] = dict(base=(0.26, 0.15, 0.075), roughness=0.82)
    m['Plastic'] = dict(base=(0.022, 0.022, 0.024), roughness=0.62)
    m['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.35)
    m['Plate'] = dict(base=(0.78, 0.78, 0.76), roughness=0.45)
    m['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.04, alpha=0.30, double_sided=True)
    return m


def mat_fn(c, n, where):
    if where == 'band' and n.z < -0.7:
        return 'Underbody'
    return 'Paint'


def D(pts, L=0.03):
    return ck.densify(pts, L)


def L(S, pts, view, closed=False, width=0.004, mat='Plastic'):
    pts = list(pts) + ([pts[0]] if closed else [])
    return S.line(pts, view, width=width, offset=0.0008, mat=mat, step=0.001, smooth=False)


# ---------------------------------------------------------------------------------------------------- build
def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials(), group='Traffic')
    sh = BODY.build(car, arches=ARCHES, side_holes=[dict(pts=DOOR_WIN, role='glass', fillet=0.03, fillet_n=2)],
                    band_holes=[dict(a=WS_A, b=WS_B, x=(-0.80, 0.80), role='glass'),
                                dict(a=RW_A, b=RW_B, x=(-0.55, 0.55), role='glass')],
                    lining=LINING, mat_fn=mat_fn, reveal_mat='Plastic', reveal_depth=0.03)
    car.shell = sh
    S = sh.surface
    car.add('Body', sh.part, sh.reveals, sh.lining)
    car.add('Glass', sh.glass)
    B, LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    front(car, S, B, LH)
    cab_details(car, S, B)
    flatbed(car, B, LT, LB, LR)
    chassis(car, B)
    car.info['width_body'] = 2 * max(abs(v.x) for v in sh.part.v + B.v)
    car.info['length_body'] = max(v.y for v in sh.part.v + B.v) - min(v.y for v in sh.part.v + B.v)
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
    car.socket('Socket_CamHood', (0.0, 1.55, 1.42))
    car.socket('Socket_CamCockpit', EYE)
    car.socket('Socket_CamBumper', (0.0, Y_FRONT + 0.10, 0.55))
    car.finalize()
    return car


def front(car, S, B, LH):
    # grey steel bumper with a slight wrap, blank plate, black lower valance
    plan = ck.rrect_pts(0.0, Y_FRONT - 0.055, 2 * 0.950, 0.110, 0.035, n=2)
    B.extend(ck.sweep_axis('z', [0.420, 0.430, 0.610, 0.620],
                           [ck.offset_poly(plan, -0.008), plan, plan, ck.offset_poly(plan, -0.008)], 'Trim'))
    B.extend(ck.abox((-0.260, Y_FRONT - 0.002, 0.460), (0.260, Y_FRONT + 0.004, 0.570), 'Plate'))
    B.extend(ck.abox((-0.800, 2.340, 0.360), (0.800, 2.400, 0.430), 'Plastic'))
    # grille: grey surround, black mesh, three bars, rectangular headlamps + amber indicators inside
    sur = D(ck.fillet_poly([(-0.880, 0.660), (0.880, 0.660), (0.880, 1.070), (-0.880, 1.070)], 0.02, n=2), 0.10)
    B.extend(S.patch(sur, 'front', offset=0.004, depth=0.006, res=0.0, mat='Trim', smooth=False))
    mesh = D(ck.fillet_poly([(-0.540, 0.700), (0.540, 0.700), (0.540, 1.030), (-0.540, 1.030)], 0.01, n=1), 0.10)
    B.extend(S.patch(mesh, 'front', offset=0.008, depth=0.006, res=0.0, mat='Grille', smooth=False))
    for z in (0.780, 0.865, 0.950):
        bar = D(ck.rrect_pts(0.0, z, 1.060, 0.024, 0.008, n=1), 0.10)
        B.extend(S.patch(bar, 'front', offset=0.014, depth=0.010, res=0.0, mat='Trim', smooth=False))
    for sx in (1, -1):
        lamp = [(sx * x, z) for (x, z) in D(ck.rrect_pts(0.700, 0.935, 0.240, 0.140, 0.012, n=2), 0.06)]
        LH.extend(S.patch(lamp, 'front', offset=0.010, depth=0.008, res=0.0, mat='HeadlightLens', smooth=False))
        ind = [(sx * x, z) for (x, z) in D(ck.rrect_pts(0.700, 0.745, 0.240, 0.060, 0.008, n=1), 0.06)]
        B.extend(S.patch(ind, 'front', offset=0.010, depth=0.008, res=0.0, mat='Amber', smooth=False))
    hc = S.snap('front', 0.700, 0.935)
    car.socket('Socket_HeadlightR', hc + Vector((0, 0.012, 0)))
    car.socket('Socket_HeadlightL', (-hc.x, hc.y + 0.012, hc.z))
    # bonnet panel seams (sides + front edge), wipers
    for sx in (1, -1):
        B.extend(L(S, [(sx * 0.840, 1.330), (sx * 0.840, 2.390)], 'top'))
    B.extend(L(S, [(-0.840, 2.390), (0.840, 2.390)], 'top'))
    for x0, x1 in ((-0.70, -0.08), (0.08, 0.70)):
        a = S.snap('front', x0, 1.265) + Vector((0, 0.012, 0.008))
        b = S.snap('front', x1, 1.300) + Vector((0, 0.012, 0.008))
        B.extend(ck.box_between(a, b, 0.014, 0.010, 'Plastic'))


def cab_details(car, S, B):
    for sx, view in ((1, 'right'), (-1, 'left')):
        door = [(0.160, 1.745), (0.160, 0.600), (1.180, 0.600), (1.180, 1.210), (0.840, 1.745)]
        B.extend(L(S, door, view, closed=True))
        B.extend(L(S, [(1.000, 1.220), (1.000, 1.450)], view, width=0.030))             # quarter-light divider
        B.extend(ck.abox((sx * (HW - 0.004), 0.250, 1.140), (sx * (HW + 0.014), 0.400, 1.170), 'Chrome'))
        # fender side marker (amber) ahead of the arch, grey arch flare
        B.extend(S.patch(D(ck.rrect_pts(2.200, 0.820, 0.090, 0.040, 0.008, n=1), 0.03), view, offset=0.003,
                         depth=0.005, res=0.0, mat='Amber', smooth=False))
        fl = ck.arch_flare(YF, ARCH_Z, ARCH_R - 0.003, ARCH_R + 0.045, HW + 0.020, HW, a0=3.0, a1=177.0, segs=18,
                           mat='Trim')
        B.extend(fl if sx > 0 else fl.mirrored_x())
        # rocker / step strip below the door
        B.extend(ck.rbox('y', 0.140, 1.150, (sx * (HW + 0.006), 0.610), 0.022, 0.060, 0.008, 'Trim'))
    # fuel filler (left rear of the cab)
    B.extend(L(S, ck.rrect_pts(0.230, 0.880, 0.120, 0.120, 0.015, n=1), 'left', closed=True))
    # roof beacon (work truck): grey base + amber lens
    B.extend(ck.rbox('x', -0.260, 0.260, (0.420, Z_ROOF + 0.010), 0.180, 0.030, 0.010, 'Trim', n=1))
    B.extend(ck.rbox('x', -0.230, 0.230, (0.420, Z_ROOF + 0.050), 0.130, 0.060, 0.025, 'Amber', n=2))


def mirrors(B):
    for sx in (1, -1):
        a = Vector((sx * (HW - 0.010), 1.120, 1.240))
        b = Vector((sx * (HW + 0.130), 1.080, 1.330))
        B.extend(ck.rod(a, b, 0.012, 'Trim', n=6))
        B.extend(ck.rod(Vector((sx * (HW - 0.010), 1.000, 1.420)), b + Vector((0, -0.005, 0.090)), 0.010, 'Trim',
                        n=6))
        B.extend(ck.rbox('z', 1.300, 1.500, (sx * (HW + 0.150), 1.090), 0.140, 0.040, 0.012, 'Trim', n=1))
        B.extend(ck.abox((sx * (HW + 0.085), 1.068, 1.310), (sx * (HW + 0.215), 1.070, 1.490), 'Chrome'))


def flatbed(car, B, LT, LB, LR):
    y0, y1, hw, z0, z1 = DECK['y0'], DECK['y1'], DECK['hw'], DECK['z0'], DECK['z1']
    # steel deck frame (perimeter channel) + wooden boards
    B.extend(ck.abox((-hw, y0, z0 - 0.080), (hw, y0 + 0.060, z1 + 0.020), 'Steel'))
    B.extend(ck.abox((-hw, y1 - 0.060, z0 - 0.080), (hw, y1, z1 + 0.020), 'Steel'))
    for sx in (1, -1):
        B.extend(ck.abox((sx * (hw - 0.060), y0, z0 - 0.080), (sx * hw, y1, z1 + 0.020), 'Steel'))
    n_boards = 9
    bw = (2 * (hw - 0.06)) / n_boards
    for k in range(n_boards):
        xa = -(hw - 0.06) + k * bw + 0.004
        B.extend(ck.abox((xa, y0 + 0.06, z1 - 0.030), (xa + bw - 0.008, y1 - 0.06, z1), 'Wood'))
    B.extend(ck.abox((-(hw - 0.06), y0 + 0.06, z0), (hw - 0.06, y1 - 0.06, z1 - 0.030), 'Steel'))
    for yy in (-2.250, -1.700, -1.100, -0.500):                     # cross bearers under the deck
        B.extend(ck.abox((-hw + 0.02, yy - 0.030, z0 - 0.110), (hw - 0.02, yy + 0.030, z0), 'Steel'))
    # stake posts + tubular rails (sides and tailgate end), headache rack behind the cab
    posts_y = [y0 + 0.06, -1.940, -1.300, -0.650, y1 - 0.06]
    for sx in (1, -1):
        for yy in posts_y:
            B.extend(ck.abox((sx * (hw - 0.045), yy - 0.022, z1), (sx * (hw - 0.005), yy + 0.022, RAIL_Z + 0.02),
                             'Steel'))
        B.extend(ck.rod((sx * (hw - 0.025), y0 + 0.04, RAIL_Z), (sx * (hw - 0.025), y1 - 0.04, RAIL_Z), 0.022, 'Steel',
                        n=8))
        B.extend(ck.rod((sx * (hw - 0.025), y0 + 0.04, (z1 + RAIL_Z) / 2), (sx * (hw - 0.025), y1 - 0.04,
                                                                             (z1 + RAIL_Z) / 2), 0.016, 'Steel', n=8))
    B.extend(ck.rod((-(hw - 0.025), y0 + 0.04, RAIL_Z), ((hw - 0.025), y0 + 0.04, RAIL_Z), 0.022, 'Steel', n=8))
    for xx in (-0.30, 0.30):
        B.extend(ck.abox((xx - 0.022, y0 + 0.02, z1), (xx + 0.022, y0 + 0.064, RAIL_Z), 'Steel'))
    rack = [Vector((-(hw - 0.05), y1 - 0.03, z1)), Vector((-(hw - 0.05), y1 - 0.03, 1.700)),
            Vector((-(hw - 0.15), y1 - 0.03, 1.780)), Vector(((hw - 0.15), y1 - 0.03, 1.780)),
            Vector(((hw - 0.05), y1 - 0.03, 1.700)), Vector(((hw - 0.05), y1 - 0.03, z1))]
    B.extend(ck.rod_path(rack, 0.024, 'Steel', n=8))
    for xx in (-0.45, -0.15, 0.15, 0.45):
        B.extend(ck.rod((xx, y1 - 0.03, z1), (xx, y1 - 0.03, 1.775), 0.012, 'Steel', n=6))
    B.extend(ck.rod((-(hw - 0.05), y1 - 0.03, 1.450), ((hw - 0.05), y1 - 0.03, 1.450), 0.014, 'Steel', n=6))
    # rear mudguards under the deck + stays, step bumper, hitch, tail lamps under the deck corners
    for sx in (1, -1):
        p = ck.revolve([(0.660, 0.420), (0.950, 0.420), (0.950, 0.436), (0.660, 0.436)], 18, 'Plastic',
                       theta0=math.radians(18), theta1=math.radians(162), caps=True)
        p.extend(ck.revolve([(0.660, 0.436), (0.660, 0.420)], 18, 'Plastic', theta0=math.radians(18),
                            theta1=math.radians(162)))
        p.orient(0, ref_fn=lambda c: Vector((0.805, 0.428 * c.y / max(math.hypot(c.y, c.z), 1e-6),
                                             0.428 * c.z / max(math.hypot(c.y, c.z), 1e-6))))
        p = p.translated((0, YR, WHEEL_R))
        B.extend(p if sx > 0 else p.mirrored_x())
        B.extend(ck.abox((sx * 0.780, YR - 0.020, WHEEL_R + 0.430), (sx * 0.820, YR + 0.020, z0 - 0.110), 'Steel'))
    plan = ck.rrect_pts(0.0, Y_REAR + 0.060, 2 * 0.930, 0.120, 0.030, n=2)
    B.extend(ck.sweep_axis('z', [0.500, 0.510, 0.690, 0.700],
                           [ck.offset_poly(plan, -0.006), plan, plan, ck.offset_poly(plan, -0.006)], 'Trim'))
    B.extend(ck.abox((-0.300, Y_REAR - 0.004, 0.700), (0.300, Y_REAR + 0.110, 0.712), 'Steel'))  # step plate
    B.extend(ck.abox((-0.040, Y_REAR - 0.100, 0.520), (0.040, Y_REAR + 0.020, 0.580), 'Steel'))   # hitch tongue
    B.extend(ck.ellipsoid((0.0, Y_REAR - 0.080, 0.605), (0.025, 0.025, 0.025), 'Chrome', nu=10, nv=6))
    B.extend(ck.abox((-0.260, Y_REAR - 0.006, 0.570), (0.260, Y_REAR, 0.680), 'Plate'))
    for sx in (1, -1):
        B.extend(ck.abox((sx * 0.640, y0 - 0.020, 0.800), (sx * 0.930, y0 + 0.040, 0.940), 'Plastic'))
        LT.extend(ck.abox((sx * 0.800, y0 - 0.026, 0.880), (sx * 0.920, y0 - 0.020, 0.930), 'TaillightLens'))
        LB.extend(ck.abox((sx * 0.800, y0 - 0.026, 0.815), (sx * 0.920, y0 - 0.020, 0.875), 'BrakeLens'))
        LR.extend(ck.abox((sx * 0.650, y0 - 0.026, 0.815), (sx * 0.790, y0 - 0.020, 0.875), 'ReverseLens'))
        B.extend(ck.abox((sx * 0.650, y0 - 0.026, 0.880), (sx * 0.790, y0 - 0.020, 0.930), 'Amber'))


def chassis(car, B):
    for sx in (1, -1):
        B.extend(ck.abox((sx * 0.380, Y_REAR + 0.10, 0.560), (sx * 0.460, 2.250, 0.760), 'Steel'))
        B.extend(ck.abox((sx * 0.400, YR - 0.70, 0.470), (sx * 0.460, YR + 0.70, 0.562), 'Steel'))     # leaf springs
        B.extend(ck.abox((sx * 0.400, YR - 0.07, 0.425), (sx * 0.460, YR + 0.07, 0.472), 'Steel'))     # spring seat
    B.extend(ck.rod((-0.62, YR, WHEEL_R), (0.62, YR, WHEEL_R), 0.055, 'Steel', n=10))
    B.extend(ck.ellipsoid((0.0, YR, WHEEL_R), (0.15, 0.16, 0.15), 'Steel', nu=10, nv=6))
    B.extend(ck.rod((0.0, YR + 0.15, WHEEL_R + 0.01), (0.0, 0.40, 0.520), 0.035, 'Steel', n=8))       # prop shaft
    B.extend(ck.rod((-0.62, YF, WHEEL_R), (0.62, YF, WHEEL_R), 0.045, 'Steel', n=8))
    for sx in (1, -1):                                                                                # front springs
        B.extend(ck.abox((sx * 0.380, YF - 0.20, WHEEL_R + 0.03), (sx * 0.460, YF + 0.20, 0.565), 'Steel'))
    B.extend(ck.rbox('y', -1.000, -0.300, (-0.620, 0.660), 0.300, 0.220, 0.050, 'Steel'))            # fuel tank
    B.extend(ck.rod((0.300, 0.200, 0.470), (0.520, -2.050, 0.430), 0.030, 'Steel', n=8))              # exhaust
    for t in (0.15, 0.55, 0.85):                                                                       # hangers
        p = Vector((0.300, 0.200, 0.470)).lerp(Vector((0.520, -2.050, 0.430)), t)
        B.extend(ck.rod(p, Vector((0.400, p.y, 0.565)), 0.008, 'Steel', n=6))
    B.extend(ck.tube((0.520, -2.050, 0.430), (0.560, -2.420, 0.420), 0.034, 0.028, 'Steel', 'Underbody', n=10))
    car.socket('Socket_Exhaust', (0.562, -2.425, 0.420))
    B.extend(ck.abox((-0.880, 0.040, 0.560), (0.880, 0.100, 0.620), 'Underbody'))                    # cab sill


def interior(car):
    I = ck.Part()
    zf = LINING['z'][0]
    I.extend(ck.rbox('y', 0.300, 0.820, (0.0, 1.000), 1.620, 0.130, 0.040, 'Interior', n=2))         # bench seat
    I.extend(ck.abox((-0.78, 0.360, zf), (0.78, 0.760, 0.940), 'InteriorDark'))
    M = ck.Matrix.Translation((0.0, 0.330, 1.020)) @ ck.Matrix.Rotation(math.radians(14.0), 4, 'X')
    I.extend(ck.rbox('z', 0.0, 0.600, (0.0, 0.0), 1.600, 0.110, 0.040, 'Interior', n=2).transformed(M))
    prof = [(1.290, zf + 0.01), (1.290, 1.170), (1.120, 1.240), (1.000, 1.240), (0.960, 1.170), (1.000, 0.900),
            (1.120, zf + 0.01)]
    I.extend(ck.sweep_axis('x', [-0.880, 0.880], [prof, prof], 'InteriorDark'))
    for x in (-0.500, -0.340):
        I.extend(ck.gauge((x, 0.972, 1.130), (0.0, -1.0, 0.15), 0.050))
    I.extend(ck.rod((0.050, 1.000, zf + 0.02), (0.090, 0.820, 1.080), 0.010, 'InteriorDark', n=8))  # floor shifter
    I.extend(ck.ellipsoid((0.092, 0.815, 1.090), (0.026, 0.026, 0.030), 'Interior', nu=10, nv=6))
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.06, HUB + col * 0.18, 0.060, 0.070, 'InteriorDark'))
    car.add('Interior', I)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.012, 0.014), segs=24, flat_bottom=False, hub_r=0.050,
                                spokes=((0.0, 0.035), (180.0, 0.035)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


META = dict(cls='work pickup (single cab, steel-framed flatbed with side rails)', drivetrain='RWD',
            engine='front, 4.1 petrol I6', doors=2, seats=3, sw_radius=SW_R, eye=EYE, paint_hex=PAINT_HEX,
            paint_lin=PAINT_LIN, finish='gloss', height_roof=Z_ROOF, rim_diameter_in_front=16,
            rim_diameter_in_rear=16, tyre_width_nominal=WHEEL_W,
            livery='Paint = white (repaintable); Trim = grey painted steel (bumpers, grille surround, flares)',
            cargo={'deck_height': DECK['z1'], 'deck_length': round(DECK['y1'] - DECK['y0'], 3),
                   'deck_width': 2 * DECK['hw'], 'rail_height': RAIL_Z},
            notes='Cab lining is part of Body so the merged traffic LOD stays opaque. Distinct from the player '
                  'Hauler 2500: single cab, boxy older style, flatbed, steel wheels, no chrome grille.')


if __name__ == '__main__':
    CAR = build()
    tc.finish_body(CAR)
    META['width_body'] = CAR.info['width_body']
    META['length_body'] = CAR.info['length_body']
    print('tris', ck.tri_counts(CAR))
    print('qa', tc.qa(CAR, WHEEL_R, WHEEL_W))
    if RENDER:
        print('render', tc.render_hero(CAR, os.path.join(tc.DOC_DIR, 'traffic_%s.png' % CAR_ID),
                                       cam_loc=(6.4, 7.4, 2.0), target=(0.0, -0.15, 0.95), lens=50.0,
                                       world_strength=0.9, sun_energy=3.8, exposure=-0.6, sun_rot=(0.80, 0.0, 2.30)))
    if EXPORT:
        RES, VER, DATA = tc.export(CAR, META)
        print('export', RES, VER)
        print('dims L %.3f W %.3f H %.3f wb %.3f' % (DATA['length'], DATA['width'], DATA['height_overall'],
                                                    DATA['wheelbase']))
    if KEEP_SOLO:
        tc.solo(CAR_ID)
