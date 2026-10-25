"""lorry_box - rigid box lorry, cab-over (Sunward Roads traffic vehicle #3).

Rebuilds SUNWARD_GODOT/Traffic/Traffic_lorry_box with tools/blender/car_kit.py and optionally renders
docs/blender_props/traffic_lorry_box.png and exports assets/imported/traffic/lorry_box.glb + .json.
Run like van_delivery.py (globals EXPORT, RENDER, KEEP_SOLO).

Spec: L 7.80 (front bumper -> rear underrun bar), W 2.45 (box; cab 2.30), H 3.40 (box roof), wheelbase 4.60,
wheels R 0.48 (19.5" steel disc wheels with hand holes and wheel nuts), front track 2.00, rear dual tyres
(track 1.80 between the dual centres). Original design: flat-fronted day cab (ProfileBody) with a big one-piece
windscreen, sun visor, roof air deflector, entry steps ahead of the front wheel, black plastic mudguards over every
axle; separate white box body (part of Body) with aluminium corner posts, rails, side seams, twin rear doors with
four lock rods, side guards, fuel tank, battery box, air tanks, exhaust silencer, ladder frame and axles below.
Paint = cab colour (repainted by the game); 'Panel' = white box (fixed). Rear wheels are dual tyres inside the
standard Wheel_RL / Wheel_RR objects (physics uses the four standard wheels).
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

CAR_ID = 'lorry_box'
CAR_NAME = 'Box Lorry'
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)
KEEP_SOLO = globals().get('KEEP_SOLO', False)

# ---------------------------------------------------------------------------------------------------- dimensions
WHEELBASE = 4.60
YF, YR = WHEELBASE / 2, -WHEELBASE / 2
WHEEL_R = 0.480
W_FRONT, W_DUAL, DUAL_GAP = 0.270, 0.250, 0.035
TRACK_F, TRACK_R = 2.00, 1.80
HW_CAB, HW_BOX = 1.150, 1.225
Y_FRONT, Y_REAR = 3.550, -4.250           # bumper face / underrun bar face (L 7.80)
Y_CAB_R, Y_CAB_F = 1.550, 3.480
Y_BOX_F, Y_BOX_R = 1.450, -4.200
Z_CAB_FLOOR, Z_CAB_ROOF = 1.050, 2.950
Z_BOX0, Z_BOX1 = 1.150, 3.400
Z_RAIL0, Z_RAIL1 = 0.720, 0.970
WS_A, WS_B = (3.4717, 1.880), (3.3944, 2.620)
CAB_PROFILE = [
    (Y_CAB_R, Z_CAB_FLOOR, 0.10),     # cab rear bottom (cab floor level, above the front wheel)
    (2.880, Z_CAB_FLOOR, 0.06),       # concave: lower front quarter steps down ahead of the front wheel
    (2.880, 0.560, 0.10),
    (3.440, 0.560, 0.18),             # front bottom corner
    (Y_CAB_F, 1.800, 0.50),           # front face: vertical below, leaning back 6 deg above
    (3.360, Z_CAB_ROOF, 0.32),        # roof front edge
    (Y_CAB_R, Z_CAB_ROOF, 0.12),      # roof rear edge
]


def cab_r(y, z):
    return 0.080 + 0.070 * ck.smoothstep(3.20, 3.40, y)


CAB = ck.ProfileBody(CAB_PROFILE, HW_CAB, edge_r=cab_r, edge_segs=3, step=0.30, arc_step=0.035, flat_x=[0.96],
                     marks=[WS_A, WS_B])
DOOR_WIN = [(2.120, 1.860), (3.170, 1.860), (3.170, 2.620), (2.120, 2.620)]
LINING = dict(d=0.035, z=(1.100, 3.20))

EYE = Vector((-0.600, 2.080, 2.360))
HUB = Vector((-0.600, 2.900, 1.780))
COLUMN_TILT = 52.0
SW_R = 0.235
PAINT_HEX, PAINT_LIN = '#B3261E', (0.451, 0.019, 0.013)

WHEEL_BASE_SPEC = dict(R=WHEEL_R, rim_d_in=19.5, spokes=8, style='slot', segs=24, rim_segs=24, face_segs=24,
                       tyre='tall', spoke_thick=0.024, spoke_dish=0.045, hub_r=0.105, nuts=0,
                       grooves=[-0.055, 0.055], groove_w=0.016, brake=False, disc_r=0.20, caliper_angle=150.0,
                       caliper_span=36.0)


def make_materials():
    m = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.0, paint_rough=0.30, paint_coat=0.45,
                             rim=(0.55, 0.56, 0.58), rim_metallic=0.6, rim_rough=0.35, caliper=(0.08, 0.08, 0.085),
                             interior=(0.10, 0.10, 0.105), interior_dark=(0.022, 0.022, 0.024))
    m['Trim'] = dict(base=(0.022, 0.022, 0.024), roughness=0.62)
    m['Panel'] = dict(base=(0.80, 0.81, 0.80), roughness=0.40)
    m['Alu'] = dict(base=(0.62, 0.63, 0.65), metallic=1.0, roughness=0.38)
    m['Steel'] = dict(base=(0.045, 0.045, 0.048), metallic=0.5, roughness=0.55)
    m['Amber'] = dict(base=(0.60, 0.25, 0.02), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.3)
    m['Plate'] = dict(base=(0.78, 0.78, 0.76), roughness=0.45)
    m['Glass'] = dict(base=(0.010, 0.013, 0.016), roughness=0.04, alpha=0.32, double_sided=True)
    return m


def cab_mat(c, n, where):
    if where == 'band' and n.z < -0.7:
        return 'Underbody'
    if c.z < 1.0 and c.y > 3.2 and where == 'band':
        return 'Trim'                     # black lower front panel (behind the bumper / steps)
    return 'Paint'


def D(pts, L=0.03):
    return ck.densify(pts, L)


def L(S, pts, view, closed=False, width=0.006):
    pts = list(pts) + ([pts[0]] if closed else [])
    return S.line(pts, view, width=width, offset=0.0009, mat='Trim', step=0.001, smooth=False)


def mudguard(yc, zc, r_in, r_out, x0, x1, a0, a1, segs=16, mat='Trim'):
    """Curved mudguard band around a wheel (RIGHT side): annular sector r_in..r_out, x0..x1, angles a0..a1 (deg,
    0 = +Y forward, 90 = up) about the axle (yc, zc)."""
    t0, t1 = math.radians(a0), math.radians(a1)
    p = ck.revolve([(x0, r_in), (x1, r_in), (x1, r_out), (x0, r_out)], segs, mat, theta0=t0, theta1=t1, caps=True)
    p.extend(ck.revolve([(x0, r_out), (x0, r_in)], segs, mat, theta0=t0, theta1=t1))
    rm, xm = (r_in + r_out) / 2, (x0 + x1) / 2
    dd = math.radians(3.0)

    def ref(c):
        a = ck.clamp(math.atan2(c.z, c.y), t0 + dd, t1 - dd)
        return Vector((xm, rm * math.cos(a), rm * math.sin(a)))
    p.orient(0, ref_fn=ref)
    return p.translated((0, yc, zc))


def wheel_with_nuts(W):
    spec = dict(WHEEL_BASE_SPEC, W=W)
    wheel, cal = ck.build_wheel(**spec)
    lip_x = W / 2 - 0.012
    r0, r1 = 0.055, 19.5 * 0.0254 / 2 - 0.006
    xf = lambda r: lip_x - 0.040 + spec['spoke_dish'] * ck.smoothstep(r0, r1, r)
    for k in range(8):
        a = math.pi / 2 + 2 * math.pi * (k + 0.5) / 8
        c = Vector((xf(0.140) - 0.002, 0.140 * math.cos(a), 0.140 * math.sin(a)))
        nut = ck.revolve([(0.0, 0.0), (0.0, 0.016), (0.020, 0.015), (0.024, 0.0)], 6, 'BrakeDisc')
        wheel.extend(nut.translated(c))
    return wheel, cal, spec


# ---------------------------------------------------------------------------------------------------- build
def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials(), group='Traffic')
    sh = CAB.build(car, arches=(), side_holes=[dict(pts=DOOR_WIN, role='glass', fillet=0.06)],
                   band_holes=[dict(a=WS_A, b=WS_B, x=(-0.96, 0.96), role='glass')],
                   lining=LINING, mat_fn=cab_mat, reveal_mat='Trim')
    car.shell = sh
    S = sh.surface
    car.add('Body', sh.part, sh.reveals, sh.lining)
    car.add('Glass', sh.glass)
    B, LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part(), ck.Part()
    cab_front(car, S, B, LH)
    cab_sides(car, S, B)
    box_body(B, LT)
    chassis(car, B)
    rear(car, B, LT, LB, LR)
    car.info['width_body'] = 2 * max(abs(v.x) for v in sh.part.v + B.v)
    mirrors(B)
    car.add('Body', B)
    print('parts: shell %d reveals %d lining %d details %d glass %d' % (sh.part.tris(), sh.reveals.tris(),
                                                                         sh.lining.tris(), B.tris(), sh.glass.tris()))
    car.add('Lights_Head', LH)
    car.add('Lights_Tail', LT)
    car.add('Lights_Brake', LB)
    car.add('Lights_Reverse', LR)
    interior(car)
    wf, cf, _ = wheel_with_nuts(W_FRONT)
    ck.add_axle(car, 'F', wf, cf, YF, TRACK_F / 2, WHEEL_R)
    wr, cr, spec_r = wheel_with_nuts(W_DUAL)
    off = (W_DUAL + DUAL_GAP) / 2
    rr = 19.5 * 0.0254 / 2
    dual = ck.Part().extend(wr.translated((off, 0, 0)), ck.keep_outer_faces(wr, rr - 0.03).translated((-off, 0, 0)))
    ck.add_axle(car, 'R', dual, cr.translated((-off, 0, 0)), YR, TRACK_R / 2, WHEEL_R)
    car.socket('Socket_CamHood', (0.0, 3.20, 2.60))
    car.socket('Socket_CamCockpit', EYE)
    car.socket('Socket_CamBumper', (0.0, Y_FRONT + 0.10, 0.80))
    car.finalize()
    return car


def cab_front(car, S, B, LH):
    # bumper (grey plastic, wraps the corners) with a blank plate and fog lamps
    plan = ck.rrect_pts(0.0, 3.470, 2 * HW_CAB + 0.02, 0.160, 0.070, n=3)
    B.extend(ck.sweep_axis('z', [0.400, 0.420, 0.680, 0.700],
                           [ck.offset_poly(plan, -0.015), plan, plan, ck.offset_poly(plan, -0.015)], 'Trim'))
    B.extend(ck.abox((-0.270, 3.542, 0.480), (0.270, 3.549, 0.600), 'Plate'))
    for sx in (1, -1):
        B.extend(ck.disc((sx * 0.86, 3.546, 0.550), (0, 1, 0), 0.055, 'Grille', n=14, ring_mat='Alu', ring_w=0.010))
    # grille panel with slats
    g = D(ck.fillet_poly([(-0.600, 1.240), (0.600, 1.240), (0.600, 1.720), (-0.600, 1.720)], 0.05, n=3), 0.05)
    B.extend(S.patch(g, 'front', offset=0.004, depth=0.008, res=0.0, mat='Grille', smooth=False))
    for z in (1.320, 1.420, 1.520, 1.620):
        sl = D(ck.rrect_pts(0.0, z, 1.140, 0.030, 0.012, n=2), 0.05)
        B.extend(S.patch(sl, 'front', offset=0.012, depth=0.012, res=0.0, mat='Paint', smooth=False))
    B.extend(S.patch(D(ck.rrect_pts(0.0, 1.800, 0.500, 0.050, 0.018, n=2), 0.05), 'front', offset=0.006,
                     depth=0.006, res=0.0, mat='Alu', smooth=False))                       # blank badge bar
    # headlamps (lower corners, wrapping round), indicators, dark housings
    for sx in (1, -1):
        lamp = [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.640, 0.980), (1.090, 0.980), (1.110, 1.170),
                                                             (0.640, 1.170)], 0.03, n=2), 0.03)]
        LH.extend(S.patch(lamp, 'front', offset=0.006, depth=0.008, res=0.04, mat='HeadlightLens', smooth=False))
        B.extend(S.rim(lamp, 'front', width=0.016, offset=0.007, depth=0.006, mat='Trim', smooth=False))
        ind = [(sx * x, z) for (x, z) in D(ck.fillet_poly([(0.660, 1.190), (1.060, 1.190), (1.060, 1.225),
                                                            (0.660, 1.225)], 0.012, n=2), 0.03)]
        B.extend(S.patch(ind, 'front', offset=0.005, depth=0.006, res=0.0, mat='Amber', smooth=False))
    hc = S.snap('front', 0.860, 1.075)
    car.socket('Socket_HeadlightR', hc + Vector((0, 0.01, 0)))
    car.socket('Socket_HeadlightL', (-hc.x, hc.y + 0.01, hc.z))
    # sun visor over the windscreen, wipers
    B.extend(ck.sweep_axis('x', [-1.02, 1.02], [[(3.330, 2.660), (3.520, 2.690), (3.520, 2.720), (3.320, 2.735)]] * 2,
                           'Trim'))
    for x0, x1 in ((-0.86, -0.10), (0.06, 0.82)):
        a = S.snap('front', x0, 1.930) + Vector((0, 0.020, 0))
        b = S.snap('front', x1, 2.000) + Vector((0, 0.020, 0))
        B.extend(ck.box_between(a, b, 0.018, 0.012, 'Trim'))
    # roof air deflector
    prof = [(1.600, Z_CAB_ROOF - 0.01), (2.700, Z_CAB_ROOF - 0.01), (2.450, 3.020), (2.150, 3.140), (1.850, 3.250),
            (1.620, 3.310), (1.600, 3.310)]
    B.extend(ck.sweep_axis('x', [-1.040, 1.040], [prof, prof], 'Paint'))


def cab_sides(car, S, B):
    for sx, view in ((1, 'right'), (-1, 'left')):
        door = [(2.020, 2.840), (2.020, 1.090), (2.840, 1.090), (2.900, 0.620), (3.270, 0.620), (3.270, 2.840)]
        B.extend(L(S, door, view, closed=True))
        B.extend(ck.abox((sx * (HW_CAB - 0.005), 2.150, 1.700), (sx * (HW_CAB + 0.018), 2.330, 1.740), 'Trim'))
        # entry steps (recessed black treads) ahead of the front wheel, grab handle
        for z in (0.640, 0.860):
            B.extend(ck.abox((sx * (HW_CAB - 0.16), 2.930, z), (sx * (HW_CAB + 0.010), 3.240, z + 0.040), 'Grille'))
        B.extend(ck.rod((sx * (HW_CAB + 0.03), 3.300, 1.200), (sx * (HW_CAB + 0.03), 3.300, 2.200), 0.016, 'Alu',
                        n=8))
        for z in (1.200, 2.200):
            B.extend(ck.rod((sx * (HW_CAB - 0.01), 3.300, z), (sx * (HW_CAB + 0.03), 3.300, z), 0.012, 'Alu', n=6))
        # side repeater
        B.extend(S.patch(D(ck.rrect_pts(2.700, 1.250, 0.090, 0.040, 0.012, n=2), 0.02), view, offset=0.003,
                         depth=0.005, res=0.0, mat='Amber', smooth=False))
        # front mudguard + mud flap
        mg = mudguard(YF, WHEEL_R, 0.530, 0.555, 0.850, 1.150, 40.0, 168.0, segs=16)
        B.extend(mg if sx > 0 else mg.mirrored_x())
        B.extend(ck.abox((sx * 0.86, 1.740, 0.250), (sx * 1.14, 1.755, 0.600), 'Trim'))


def mirrors(B):
    for sx in (1, -1):
        base = Vector((sx * (HW_CAB - 0.02), 3.250, 2.700))
        tip = Vector((sx * (HW_CAB + 0.230), 3.300, 2.620))
        B.extend(ck.rod(base, tip, 0.020, 'Trim', n=8))
        B.extend(ck.rod(Vector((sx * (HW_CAB - 0.02), 3.250, 1.700)), tip + Vector((0, 0, -0.62)), 0.018, 'Trim', n=8))
        B.extend(ck.rbox('z', 2.080, 2.620, (sx * (HW_CAB + 0.250), 3.300), 0.200, 0.070, 0.030, 'Trim'))
        B.extend(ck.abox((sx * (HW_CAB + 0.162), 3.262, 2.100), (sx * (HW_CAB + 0.338), 3.266, 2.600), 'Chrome'))
        B.extend(ck.rbox('z', 1.880, 2.040, (sx * (HW_CAB + 0.250), 3.300), 0.200, 0.070, 0.030, 'Trim'))
        B.extend(ck.abox((sx * (HW_CAB + 0.162), 3.262, 1.895), (sx * (HW_CAB + 0.338), 3.266, 2.025), 'Chrome'))
        B.extend(ck.rod(tip + Vector((0, 0, -0.62)), tip, 0.018, 'Trim', n=8))


def box_body(B, LT):
    hw, y0, y1, z0, z1 = HW_BOX, Y_BOX_R, Y_BOX_F, Z_BOX0, Z_BOX1
    B.extend(ck.rbox('y', y0, y1, (0.0, (z0 + z1) / 2), 2 * hw, z1 - z0, 0.035, 'Panel', n=2))
    B.extend(ck.abox((-hw + 0.02, y0 + 0.02, z0 - 0.015), (hw - 0.02, y1 - 0.02, z0 + 0.001), 'Underbody'))
    # corner posts, top / bottom rails
    for sx in (1, -1):
        for yy in (y0 + 0.030, y1 - 0.030):
            B.extend(ck.rbox('z', z0, z1, (sx * (hw - 0.031), yy), 0.062, 0.070, 0.010, 'Alu'))
        B.extend(ck.rbox('y', y0 + 0.02, y1 - 0.02, (sx * (hw - 0.017), z1 - 0.038), 0.036, 0.076, 0.010, 'Alu'))
        B.extend(ck.rbox('y', y0 + 0.02, y1 - 0.02, (sx * (hw - 0.015), z0 + 0.075), 0.032, 0.160, 0.010, 'Alu'))
        for k in range(1, 6):                                   # side panel seams
            yy = y1 - k * (y1 - y0) / 6.0
            B.extend(ck.abox((sx * (hw - 0.004), yy - 0.018, z0 + 0.155), (sx * (hw + 0.002), yy + 0.018, z1 - 0.072),
                             'Alu'))
        for yy in (0.95, -0.55, -2.05, -3.55):                  # amber side markers on the bottom rail
            B.extend(ck.abox((sx * (hw - 0.002), yy - 0.040, z0 + 0.060), (sx * (hw + 0.002), yy + 0.040, z0 + 0.095),
                             'Amber'))
        # top corner marker lamps: red at the rear (tail circuit), white/amber at the front
        LT.extend(ck.abox((sx * (hw - 0.120), y0 - 0.012, z1 - 0.090), (sx * (hw - 0.040), y0 - 0.002, z1 - 0.050),
                          'TaillightLens'))
        B.extend(ck.abox((sx * (hw - 0.120), y1 + 0.002, z1 - 0.090), (sx * (hw - 0.040), y1 + 0.012, z1 - 0.050),
                         'Amber'))
    for yy, sgn in ((y0 + 0.030, -1), (y1 - 0.030, 1)):
        B.extend(ck.rbox('x', -hw + 0.02, hw - 0.02, (yy, z1 - 0.038), 0.070, 0.076, 0.010, 'Alu'))
        B.extend(ck.rbox('x', -hw + 0.02, hw - 0.02, (yy, z0 + 0.075), 0.070, 0.160, 0.010, 'Alu'))
    # rear doors: split line, lock rods with handles, hinges
    yr = y0 - 0.006
    B.extend(ck.abox((-0.008, yr - 0.004, z0 + 0.15), (0.008, yr + 0.002, z1 - 0.07), 'Trim'))
    for x in (-0.880, -0.320, 0.320, 0.880):
        B.extend(ck.rod((x, yr - 0.030, z0 + 0.170), (x, yr - 0.030, z1 - 0.100), 0.014, 'Alu', n=8))
        for z in (z0 + 0.170, z1 - 0.100, 1.980):
            B.extend(ck.abox((x - 0.035, yr - 0.040, z - 0.020), (x + 0.035, yr, z + 0.020), 'Alu'))
        B.extend(ck.box_between((x, yr - 0.034, 1.780), (x + (0.20 if x < 0 else -0.20), yr - 0.034, 1.700), 0.020,
                                0.024, 'Alu'))
    for sx in (1, -1):
        for z in (1.500, 2.200, 2.900):
            B.extend(ck.abox((sx * 1.080, yr - 0.030, z - 0.060), (sx * 1.200, yr + 0.002, z + 0.060), 'Steel'))


def chassis(car, B):
    for sx in (1, -1):
        B.extend(ck.abox((sx * 0.380, -4.100, Z_RAIL0), (sx * 0.470, 3.300, Z_RAIL1), 'Steel'))       # frame rails
        B.extend(ck.abox((sx * 0.400, Y_BOX_R + 0.05, Z_RAIL1), (sx * 0.500, Y_BOX_F - 0.05, Z_BOX0 - 0.012),
                         'Steel'))                                                                     # box subframe
        for yy in (1.750, 3.050):                                                                     # cab mounts
            B.extend(ck.abox((sx * 0.360, yy - 0.06, Z_RAIL1), (sx * 0.490, yy + 0.06, Z_CAB_FLOOR + 0.01), 'Trim'))
        B.extend(ck.abox((sx * 0.400, YF - 0.60, 0.495), (sx * 0.470, YF + 0.60, 0.600), 'Steel'))     # leaf springs
        B.extend(ck.abox((sx * 0.400, YF - 0.60, 0.600), (sx * 0.470, YF - 0.52, Z_RAIL0), 'Steel'))   # shackles
        B.extend(ck.abox((sx * 0.400, YF + 0.52, 0.600), (sx * 0.470, YF + 0.60, Z_RAIL0), 'Steel'))
        B.extend(ck.abox((sx * 0.400, YR - 0.70, 0.560), (sx * 0.470, YR + 0.70, 0.660), 'Steel'))
        # side guards between the axles
        for z in (0.560, 0.800):
            B.extend(ck.rbox('y', YR + 0.58, YF - 0.66, (sx * (HW_BOX - 0.060), z), 0.030, 0.090, 0.010, 'Alu'))
        for yy in (YR + 0.70, -0.30, YF - 0.80):
            B.extend(ck.abox((sx * 0.470, yy - 0.025, 0.540), (sx * (HW_BOX - 0.075), yy + 0.025, 0.580), 'Steel'))
            B.extend(ck.abox((sx * (HW_BOX - 0.090), yy - 0.025, 0.540), (sx * (HW_BOX - 0.075), yy + 0.025,
                                                                          Z_BOX0 - 0.01), 'Steel'))
        # rear mudguards over the duals + mud flaps
        mg = mudguard(YR, WHEEL_R, 0.530, 0.555, 0.610, 1.190, 15.0, 165.0, segs=18)
        B.extend(mg if sx > 0 else mg.mirrored_x())
        B.extend(ck.abox((sx * 0.620, YR - 0.575, 0.240), (sx * 1.180, YR - 0.560, 0.720), 'Trim'))
        B.extend(ck.abox((sx * 0.470, YR - 0.580, 0.700), (sx * 1.180, YR - 0.555, 0.740), 'Steel'))   # flap hanger
        B.extend(ck.abox((sx * 0.880, YR - 0.040, 1.030), (sx * 0.920, YR + 0.040, Z_BOX0), 'Steel'))   # guard stay
    for yy in (3.100, 1.800, 0.300, -1.200, -3.000, -4.050):
        B.extend(ck.abox((-0.380, yy - 0.040, 0.770), (0.380, yy + 0.040, 0.920), 'Steel'))
    for k in range(10):                                                                               # box cross sills
        yy = Y_BOX_R + 0.25 + k * (Y_BOX_F - Y_BOX_R - 0.5) / 9
        B.extend(ck.abox((-HW_BOX + 0.04, yy - 0.035, Z_BOX0 - 0.060), (HW_BOX - 0.04, yy + 0.035, Z_BOX0 - 0.012),
                         'Steel'))
    # axles
    B.extend(ck.abox((-0.900, YF - 0.050, 0.400), (0.900, YF + 0.050, 0.500), 'Steel'))
    B.extend(ck.rod((-0.62, YR, WHEEL_R), (0.62, YR, WHEEL_R), 0.075, 'Steel', n=10))
    B.extend(ck.ellipsoid((0.0, YR, WHEEL_R), (0.20, 0.24, 0.20), 'Steel', nu=12, nv=8))
    B.extend(ck.rod((0.0, YR + 0.20, WHEEL_R + 0.02), (0.0, 1.20, 0.680), 0.045, 'Steel', n=8))        # prop shaft
    # fuel tank (left), battery box + air tanks (right), exhaust silencer (right)
    B.extend(ck.rbox('y', -0.950, 0.550, (-0.860, 0.760), 0.420, 0.460, 0.120, 'Alu', n=3))
    for yy in (-0.70, 0.30):
        B.extend(ck.rbox('y', yy - 0.025, yy + 0.025, (-0.860, 0.760), 0.440, 0.480, 0.125, 'Steel', n=3))
    B.extend(ck.rod((-0.860, 0.560, 1.000), (-0.860, 0.560, 1.050), 0.050, 'Trim', n=10))
    B.extend(ck.rbox('y', -0.300, 0.450, (0.860, 0.820), 0.400, 0.360, 0.030, 'Trim'))
    B.extend(ck.rod((0.680, 0.700, 0.780), (0.680, 1.500, 0.780), 0.110, 'Steel', n=12))
    B.extend(ck.rod((0.680, -1.500, 0.690), (0.680, -0.500, 0.690), 0.150, 'Steel', n=14))
    B.extend(ck.rod((0.680, -1.500, 0.690), (0.900, -1.640, 0.560), 0.045, 'Steel', n=10))
    # brackets tying the tank / boxes / tanks / silencer to the frame rails
    for (x0, x1, yy, z) in ((-0.660, -0.470, -0.70, 0.870), (-0.660, -0.470, 0.30, 0.870),
                            (0.470, 0.680, -0.10, 0.900), (0.470, 0.660, 1.10, 0.850), (0.470, 0.560, -1.00, 0.800),
                            (0.470, 0.560, -1.35, 0.800)):
        B.extend(ck.abox((x0, yy - 0.030, z - 0.030), (x1, yy + 0.030, z + 0.030), 'Steel'))
    B.extend(ck.tube((0.900, -1.640, 0.560), (1.020, -1.716, 0.484), 0.048, 0.040, 'Steel', 'Underbody', n=12))
    car.socket('Socket_Exhaust', (1.025, -1.719, 0.481))


def rear(car, B, LT, LB, LR):
    # underrun bar + supports, rear light bar
    B.extend(ck.rbox('x', -1.120, 1.120, (Y_REAR + 0.050, 0.520), 0.100, 0.140, 0.020, 'Trim'))
    for sx in (1, -1):
        B.extend(ck.abox((sx * 0.380, Y_REAR + 0.08, 0.500), (sx * 0.470, -4.050, Z_RAIL1), 'Steel'))
    B.extend(ck.abox((-1.150, -4.200, 0.720), (1.150, -4.090, 0.940), 'Trim'))
    B.extend(ck.abox((-0.260, -4.208, 0.760), (0.260, -4.200, 0.870), 'Plate'))
    for sx in (1, -1):
        def lens(x0, x1, z0, z1, mat, part):
            part.extend(ck.abox((sx * x0, -4.210, z0), (sx * x1, -4.198, z1), mat))
        lens(0.960, 1.120, 0.760, 0.900, 'Amber', B)
        lens(0.780, 0.950, 0.835, 0.900, 'TaillightLens', LT)
        lens(0.780, 0.950, 0.760, 0.828, 'BrakeLens', LB)
        lens(0.640, 0.770, 0.760, 0.900, 'ReverseLens', LR)
        B.extend(ck.abox((sx * 0.300, -4.212, 0.790), (sx * 0.360, -4.200, 0.830), 'TaillightLens'))   # reflector


def interior(car):
    I = ck.Part()
    zf = LINING['z'][0]
    for x in (-0.600, 0.600):
        I.extend(ck.simple_seat(x, 2.350, 1.880, 1.500, width=0.52, back_h=0.68, recline=12.0))
        I.extend(ck.abox((x - 0.20, 1.930, zf), (x + 0.20, 2.280, 1.505), 'InteriorDark'))
    I.extend(ck.rbox('y', 1.700, 3.050, (0.0, zf + 0.20), 0.640, 0.400, 0.08, 'Interior', n=2))      # engine hump
    prof = [(3.420, zf + 0.01), (3.420, 1.820), (3.150, 1.880), (2.990, 1.860), (2.960, 1.650), (3.080, zf + 0.01)]
    I.extend(ck.sweep_axis('x', [-1.090, 1.090], [prof, prof], 'InteriorDark'))
    for x in (-0.680, -0.520):
        I.extend(ck.gauge((x, 2.962, 1.760), (0.0, -1.0, 0.10), 0.060))
    I.extend(ck.abox((-0.10, 2.958, 1.560), (0.10, 2.970, 1.700), 'Gauge'))
    I.extend(ck.rod((-0.20, 2.900, 1.500), (-0.24, 2.750, 1.650), 0.012, 'InteriorDark', n=8))       # gear lever
    I.extend(ck.ellipsoid((-0.245, 2.745, 1.665), (0.028, 0.028, 0.034), 'Interior', nu=10, nv=6))
    col = Vector((0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.box_between(HUB + col * 0.08, HUB + col * 0.30, 0.080, 0.090, 'InteriorDark'))
    I.extend(ck.abox((-1.090, 1.620, zf), (1.090, 1.700, 2.300), 'InteriorDark'))                   # rear wall trim
    car.add('Interior', I)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.018, 0.021), segs=28, flat_bottom=False, hub_r=0.075,
                                spokes=((0.0, 0.055), (180.0, 0.055), (270.0, 0.050)), marker=False)
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0))


META = dict(cls='rigid box lorry (cab-over day cab, 2 axles, dual rear tyres)', drivetrain='RWD',
            engine='front under cab, 6.7 turbo-diesel I6', doors=2, seats=2, sw_radius=SW_R, eye=EYE,
            paint_hex=PAINT_HEX, paint_lin=PAINT_LIN, finish='gloss', height_roof=Z_BOX1,
            rim_diameter_in_front=19.5, rim_diameter_in_rear=19.5, tyre_width_nominal=W_FRONT,
            wheel_width_note='rear wheel objects hold dual tyres (2 x 0.25 + 0.035 gap)',
            livery='Paint = cab (repaintable); Panel = white box body (fixed); Alu frame',
            cargo={'box_floor_height': Z_BOX0, 'box_inner_length_approx': round(Y_BOX_F - Y_BOX_R - 0.1, 2),
                   'box_inner_width_approx': round(2 * HW_BOX - 0.1, 2), 'rear_doors': 'twin hinged, 4 lock rods'},
            notes='Cab lining is part of Body so the merged traffic LOD stays opaque; box body is part of Body.')


if __name__ == '__main__':
    CAR = build()
    tc.finish_body(CAR)
    META['width_body'] = CAR.info['width_body']
    print('tris', ck.tri_counts(CAR))
    print('qa', tc.qa(CAR, WHEEL_R, W_FRONT))
    if RENDER:
        print('render', tc.render_hero(CAR, os.path.join(tc.DOC_DIR, 'traffic_%s.png' % CAR_ID),
                                       cam_loc=(9.6, 11.4, 3.2), target=(0.0, -0.4, 1.55), lens=50.0,
                                       world_strength=0.9, sun_energy=3.8, exposure=-0.4, sun_rot=(0.80, 0.0, 2.30)))
    if EXPORT:
        RES, VER, DATA = tc.export(CAR, META)
        print('export', RES, VER)
        print('dims L %.3f W %.3f H %.3f wb %.3f' % (DATA['length'], DATA['width'], DATA['height_overall'],
                                                    DATA['wheelbase']))
    if KEEP_SOLO:
        tc.solo(CAR_ID)
