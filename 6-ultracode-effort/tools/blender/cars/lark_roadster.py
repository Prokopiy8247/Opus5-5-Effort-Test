"""Lark Roadster - late-1950s-flavoured open two-seat roadster, front engine, RWD (car #10 of Sunward Roads).

Rebuilds Cars/Car_lark_roadster from scratch with tools/blender/car_kit.py, then (optionally) renders the QA hero
image and exports assets/imported/cars/lark_roadster.glb + .json (the caller saves the master .blend).

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\lark_roadster.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Globals that may be pre-set in the exec() dict: STAGE ('body' | 'full'), EXPORT (bool), RENDER (bool),
KEEP_ISOLATED (bool: leave the other cars hidden after the run, for looking).

Spec: L 3.90 (bumper to bumper), W 1.55, H 1.20 (top of the windscreen frame; body sides ~0.85), wheelbase 2.30,
track 1.30 / 1.28, wheel R 0.33 (15" chrome wire wheels, tall thin 165-wide tyres with whitewall sidewalls).
Original design (no real brand / model): flowing pontoon front fenders standing proud of a low bonnet, their crowns
running back into the door tops (dipped cockpit sides) and on into rounded rear fenders; small oval chrome grille,
round headlamps in raised pods on the fender tops, thin chrome blade bumpers with overriders, low chrome-framed
windscreen (the only glass), open cockpit with a padded rim, folded soft-top bundle behind the seats, small round tail
lamps on the fender ends. Interior: two cream leather seats, painted dash with round chrome-ringed gauges, large thin
2-spoke steering wheel with a horn ring. Default paint pastel mint #9FD8C4.
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

CAR_ID = 'lark_roadster'
CAR_NAME = 'Lark Roadster'
STAGE = globals().get('STAGE', 'full')
EXPORT = globals().get('EXPORT', False)
RENDER = globals().get('RENDER', False)

# ---------------------------------------------------------------- dimensions (metres)
WHEELBASE = 2.30
YF, YR = WHEELBASE / 2, -WHEELBASE / 2         # axle Y positions (+-1.15)
TRACK_F, TRACK_R = 1.30, 1.28
WHEEL_R, WHEEL_W = 0.33, 0.165
RIM_IN = 15
ARCH_R, ARCH_Z = 0.362, 0.337                  # ~3 cm visible gap above the tyre
NOSE_Y, TAIL_Y = 1.888, -1.965                 # body cap poles; the chrome blade bumpers add ~4 cm each end


def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


PAINT_HEX = '#9FD8C4'
PAINT_LIN = tuple(round(srgb_to_lin(int(PAINT_HEX[i:i + 2], 16)), 4) for i in (1, 3, 5))

# ---------------------------------------------------------------- body stations (rear -> front)
# Half-section key points (x, z): K0 floor centre, K1 floor edge (wb, zb), K2 sill (ws, zs), K3 waist / widest
# (ww, zw), K4 shoulder (wh, zh), K5 FENDER CROWN on the fender stations / cockpit edge (door top) on the cockpit
# stations (wg, zg), K6 fender-to-bonnet VALLEY (bonnet / boot-lid shut line) (wr, zr), K8 bonnet / deck centre (zc).
# The fender crowns stand 6-12 cm above the bonnet and run back through the dipped door tops into the rear fenders.
KEYS = ('zb', 'wb', 'zs', 'ws', 'zw', 'ww', 'zh', 'wh', 'zg', 'wg', 'zr', 'wr', 'zc')


def st(y, vals, **kw):
    d = dict(zip(KEYS, vals))
    d['y'] = y
    d.update(kw)
    return d


#            zb    wb    zs    ws     zw    ww     zh    wh     zg     wg     zr     wr    zc
S = [
    # ---- rounded tail: rear fender ends + sloping boot lid
    st(-1.936, (0.398, 0.285, 0.450, 0.512, 0.592, 0.596, 0.694, 0.572, 0.738, 0.456, 0.722, 0.315, 0.729), ks={6: 0.0}),
    st(-1.918, (0.385, 0.300, 0.440, 0.530, 0.590, 0.615, 0.700, 0.590, 0.748, 0.470, 0.728, 0.325, 0.735), ks={6: 0.0}),
    st(-1.892, (0.355, 0.340, 0.415, 0.575, 0.585, 0.665, 0.715, 0.637, 0.775, 0.505, 0.745, 0.350, 0.752), ks={6: 0.1}),
    st(-1.840, (0.310, 0.38, 0.380, 0.635, 0.575, 0.725, 0.735, 0.700, 0.825, 0.555, 0.775, 0.390, 0.782), ks={6: 0.3}),
    st(-1.680, (0.270, 0.42, 0.340, 0.680, 0.565, 0.762, 0.745, 0.738, 0.858, 0.585, 0.795, 0.410, 0.806)),
    # ---- rounded rear fender (haunch) over the rear wheel
    st(-1.150, (0.230, 0.46, 0.310, 0.700, 0.555, 0.775, 0.750, 0.750, 0.875, 0.600, 0.805, 0.430, 0.818), ks={3: 0.2}),
    st(-0.850, (0.210, 0.48, 0.285, 0.708, 0.480, 0.772, 0.755, 0.746, 0.862, 0.615, 0.812, 0.430, 0.822), ks={3: 0.5}),
    # ---- open cockpit (bands 5..7 'open'): K5 = cockpit edge on the dipped door top; K3 = the fender sweep
    # crease that runs down across the door
    st(-0.550, (0.190, 0.50, 0.250, 0.715, 0.410, 0.768, 0.745, 0.740, 0.808, 0.662, 0.815, 0.430, 0.820), ks={3: 0.75}),
    st(-0.200, (0.190, 0.50, 0.250, 0.715, 0.450, 0.768, 0.745, 0.740, 0.792, 0.668, 0.815, 0.430, 0.820), ks={3: 0.75}),
    st(0.150, (0.190, 0.50, 0.250, 0.715, 0.520, 0.769, 0.755, 0.742, 0.800, 0.665, 0.835, 0.430, 0.845), ks={3: 0.7}),
    st(0.300, (0.195, 0.49, 0.255, 0.715, 0.555, 0.771, 0.770, 0.745, 0.825, 0.660, 0.855, 0.430, 0.862), ks={3: 0.6}),
    # ---- scuttle / windscreen base
    st(0.450, (0.200, 0.48, 0.260, 0.712, 0.580, 0.772, 0.785, 0.748, 0.860, 0.630, 0.875, 0.430, 0.885), ks={3: 0.5}),
    st(0.620, (0.210, 0.47, 0.270, 0.708, 0.600, 0.773, 0.775, 0.750, 0.866, 0.615, 0.855, 0.430, 0.870), ks={3: 0.45}),
    # ---- low bonnet between the tall pontoon front fenders
    st(0.900, (0.230, 0.45, 0.290, 0.700, 0.600, 0.775, 0.765, 0.752, 0.862, 0.600, 0.792, 0.430, 0.818), ks={3: 0.4}),
    st(1.150, (0.250, 0.44, 0.310, 0.695, 0.600, 0.775, 0.760, 0.752, 0.860, 0.598, 0.762, 0.430, 0.788), ks={3: 0.35}),
    st(1.400, (0.270, 0.43, 0.325, 0.688, 0.595, 0.770, 0.755, 0.745, 0.855, 0.592, 0.731, 0.420, 0.756)),
    st(1.600, (0.300, 0.40, 0.345, 0.668, 0.590, 0.752, 0.745, 0.726, 0.845, 0.580, 0.705, 0.400, 0.730)),
    st(1.720, (0.330, 0.36, 0.370, 0.622, 0.585, 0.705, 0.735, 0.680, 0.815, 0.555, 0.683, 0.380, 0.705), ks={6: 0.30}),
    st(1.800, (0.370, 0.32, 0.400, 0.555, 0.580, 0.640, 0.700, 0.615, 0.765, 0.510, 0.668, 0.350, 0.684), ks={6: 0.10}),
    # fascia: the last two rings are nearly parallel so the cap starts flat (no fold / V crease in the face)
    st(1.835, (0.395, 0.28, 0.425, 0.495, 0.578, 0.578, 0.675, 0.552, 0.722, 0.458, 0.662, 0.310, 0.673), ks={6: 0.0}),
    st(1.858, (0.408, 0.262, 0.435, 0.470, 0.577, 0.560, 0.667, 0.534, 0.710, 0.440, 0.659, 0.298, 0.669), ks={6: 0.0}),
]

Y_CK_F = 0.300           # cockpit opening front edge (dash top)
Y_CK_R = -0.740          # base y of the cockpit rear edge (bent into a U by WARP_CK)
WARP_CK = dict(y=Y_CK_R, t=(5.0, 6.0, 7.0, 8.0), y_t=(-0.600, -0.700, -0.760, -0.780), margin=0.22)
RULES = [
    dict(bands=(5, 7), y=(Y_CK_R, Y_CK_F), role='open'),     # open cockpit
]

BODY = ck.LoftBody(
    stations=S,
    band_segments=[2, 2, 4, 5, 4, 4, 2, 6],
    key_sharp=(0, 0.6, 0.45, 0.25, 0.20, 0.0, 0.45, 0.0, 0),
    rules=RULES,
    default_roles={0: 'under'},
    nose=dict(y=NOSE_Y, z=0.55, tilt=0.0, k_edge=2.2, k_face=2.6, rings=8),
    tail=dict(y=TAIL_Y, z=0.57, tilt=0.0, k_edge=2.2, k_face=2.6, rings=8),
    step=0.04,
    rail=0.05,
    warps=[WARP_CK],
)

ARCHES = [dict(y=YF, z=ARCH_Z, r=ARCH_R, x_in=0.40), dict(y=YR, z=ARCH_Z, r=ARCH_R, x_in=0.46)]
INNER = dict(y=(-0.770, 0.660), d=0.035,
             tubs=[(YR, ARCH_Z, ARCH_R + 0.03, 0.445), (YF, ARCH_Z, ARCH_R + 0.03, 0.385)])

EYE = Vector((-0.320, -0.430, 1.075))        # driver eye point (LHD, driver on the left = -X)
HUB = Vector((-0.320, 0.070, 0.800))         # steering wheel hub
COLUMN_TILT = 30.0                           # deg, column descends toward the dash
SW_R = 0.200                                 # large thin 2-spoke wheel


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


def snap_pts(S_, spec):
    out = []
    for view, a, b in spec:
        p = S_.snap(view, a, b)
        if p is None:
            raise RuntimeError('snap miss %s %s %s' % (view, a, b))
        out.append(p)
    return out


# =====================================================================================
# wire wheels with whitewall tyres
# =====================================================================================
def _x_to(normal):
    """Rotation matrix taking +X onto `normal`."""
    return Vector((1.0, 0.0, 0.0)).rotation_difference(Vector(normal).normalized()).to_matrix().to_4x4()


def spoke(p0, p1, r, mat='Rim'):
    """Thin 4-sided wire spoke (open ends, 8 tris)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = (p1 - p0).normalized()
    u = d.cross(Vector((1.0, 0.0, 0.0)))
    if u.length < 1e-3:
        u = d.cross(Vector((0.0, 0.0, 1.0)))
    u.normalize()
    w = d.cross(u)
    part = ck.Part()
    rows = []
    for c in (p0, p1):
        rows.append([part.vert(c + (u * math.cos(a) + w * math.sin(a)) * r)
                     for a in (0.25 * math.pi, 0.75 * math.pi, 1.25 * math.pi, 1.75 * math.pi)])
    for k in range(4):
        k2 = (k + 1) % 4
        part.face((rows[0][k], rows[0][k2], rows[1][k2], rows[1][k]), mat)
    part.orient(0, ref_fn=lambda c: p0 + d * (c - p0).dot(d))
    return part


def wire_wheel(R=WHEEL_R, W=WHEEL_W, rim_d_in=RIM_IN, segs=40, rim_segs=32, n_spokes=20, lace=24.0,
               disc_r=0.132, caliper_angle=150.0, caliper_span=40.0, ww=(0.226, 0.270)):
    """Chrome wire wheel (two laced spoke layers, splined hub, 2-eared knock-off spinner) + tall whitewall tyre,
    brake disc and caliper. RIGHT side frame of ck.build_wheel: axle at the origin, spin axis X, outer face +X,
    tyre contact at z = -R. Returns (wheel_part, caliper_part)."""
    rr = rim_d_in * 0.0254 / 2.0                 # bead seat radius 0.1905
    hw = W / 2.0
    lip_x = hw - 0.018
    # ---- tyre: coarse inner sidewall, outer sidewall with rows on the whitewall edges, 2 tread grooves
    inner = [(-lip_x + 0.004, rr + 0.004), (-hw + 0.004, 0.225), (-hw, 0.262), (-hw + 0.006, 0.300),
             (-hw + 0.020, R - 0.008), (-hw + 0.038, R)]
    g, gw = 0.0055, 0.004
    tread = []
    for gx in (-0.015, 0.015):
        tread += [(gx - gw, R), (gx - gw + 0.001, R - g), (gx + gw - 0.001, R - g), (gx + gw, R)]
    outer = [(hw - 0.038, R), (hw - 0.020, R - 0.008), (hw - 0.0045, 0.299), (hw - 0.0005, 0.282),
             (hw - 0.0015, ww[1]), (hw, 0.248), (hw - 0.002, ww[0]), (hw - 0.007, 0.209), (lip_x - 0.004, rr + 0.004)]
    prof = inner + tread + outer
    mats = []
    for k in range(len(prof) - 1):
        a0, r0 = prof[k]
        a1, r1 = prof[k + 1]
        white = a0 > 0.03 and a1 > 0.03 and ww[0] - 1e-4 <= min(r0, r1) and max(r0, r1) <= ww[1] + 1e-4
        mats.append('Whitewall' if white else 'Rubber')
    wheel = ck.revolve(prof, segs, mats)
    # ---- chrome rim with a drop-centre well (spokes end in the well)
    well = rr - 0.036
    rim_prof = [(lip_x + 0.007, rr + 0.011), (lip_x + 0.006, rr - 0.004), (lip_x - 0.010, rr - 0.009),
                (0.018, rr - 0.012), (0.010, well), (-0.030, well), (-0.038, rr - 0.012), (-lip_x, rr + 0.004)]
    wheel.extend(ck.revolve(rim_prof, rim_segs, 'Rim'))
    # ---- hub shell: inner flange, barrel, outer flange, splined nose
    hub = ck.revolve([(-0.050, 0.0), (-0.050, 0.044), (-0.046, 0.068), (-0.036, 0.068), (-0.030, 0.046),
                      (0.026, 0.040), (0.030, 0.056), (0.038, 0.056), (0.042, 0.040), (0.060, 0.036),
                      (0.062, 0.0)], 20, 'Rim')
    wheel.extend(hub)
    # ---- laced spokes: outer layer (outer flange -> inboard side of the well) and inner layer (inner flange ->
    # outboard side of the well); consecutive spokes lean +-lace degrees so they cross like a real wire wheel
    dl = math.radians(lace)
    for layer, (xh, rh, xr, phase) in enumerate(((0.034, 0.052, -0.022, 0.0), (-0.041, 0.064, 0.004, 0.5))):
        for k in range(n_spokes):
            a = 2 * math.pi * (k + phase) / n_spokes
            s = 1 if k % 2 == 0 else -1
            b = a + s * dl
            p0 = Vector((xh, rh * math.cos(a), rh * math.sin(a)))
            p1 = Vector((xr, (well + 0.003) * math.cos(b), (well + 0.003) * math.sin(b)))
            wheel.extend(spoke(p0, p1, 0.0021))
    # ---- 2-eared knock-off spinner
    boss = ck.revolve([(0.056, 0.0), (0.056, 0.036), (0.066, 0.036), (0.073, 0.031), (0.079, 0.020),
                       (0.081, 0.0)], 16, 'Rim')
    wheel.extend(boss)
    for ang in (90.0, 270.0):
        rs = [0.022, 0.050, 0.080, 0.090]
        profs = []
        for r in rs:
            f = (r - rs[0]) / (rs[-1] - rs[0])
            w2 = (0.034 - 0.012 * f) / 2
            x0, x1 = 0.058, 0.0765 - 0.008 * f
            if r == rs[-1]:
                w2 *= 0.8
                x1 -= 0.003
            profs.append([(x0, -w2), (x0, w2), (x1 - 0.002, w2 * 0.92), (x1, 0.0), (x1 - 0.002, -w2 * 0.92)])
        ear = ck.sweep_axis('z', rs, profs, 'Rim')
        wheel.extend(ear.transformed(Matrix.Rotation(math.radians(ang - 90.0), 4, 'X')))
    # ---- brake disc + hat (inboard of the spoke cone)
    dx0, dx1 = -0.090, -0.068
    dprof = [(dx0, disc_r - 0.058), (dx0, disc_r), (dx1, disc_r), (dx1, disc_r - 0.058), (dx0, disc_r - 0.058)]
    disc_p = ck.revolve(list(reversed(dprof)), 28, 'BrakeDisc')
    disc_p.orient(0, ref_fn=lambda c: Vector((0.5 * (dx0 + dx1), 0, 0)) + ck._unit(Vector((0, c.y, c.z))) * (disc_r - 0.029))
    wheel.extend(disc_p)
    hat = ck.revolve([(dx1, disc_r - 0.058), (dx1 + 0.004, 0.064), (-0.050, 0.050)], 20, 'BrakeDisc')
    hat.orient(0, ref=Vector((0, 0, 0)))
    wheel.extend(hat)
    # ---- caliper (does not spin), outboard edge 1.5 cm inside the spoke cone
    ca = math.radians(caliper_angle)
    span = math.radians(caliper_span) / 2
    cal_prof = [(-0.108, disc_r - 0.046), (-0.108, disc_r + 0.016), (-0.050, disc_r + 0.016),
                (-0.050, disc_r - 0.046), (-0.108, disc_r - 0.046)]
    cal = ck.revolve(list(reversed(cal_prof)), 8, 'Caliper', theta0=ca - span, theta1=ca + span, caps=True)
    cal.orient(0, ref_fn=lambda c: Vector((-0.079, 0, 0)) + ck._unit(Vector((0, c.y, c.z))) * (disc_r - 0.015))
    return wheel, cal


def add_wire_wheels(car):
    wheel, cal = wire_wheel()
    out = {}
    for axle, key, y, ht in (('front', 'F', YF, TRACK_F / 2), ('rear', 'R', YR, TRACK_R / 2)):
        for side, sk in ((1, 'R'), (-1, 'L')):
            w = wheel if side > 0 else wheel.mirrored_x()
            c = cal if side > 0 else cal.mirrored_x()
            loc = Vector((side * ht, y, WHEEL_R))
            car.add('Wheel_%s%s' % (key, sk), w, location=loc, mats=['Rubber', 'Rim', 'BrakeDisc', 'Whitewall'])
            car.add('Caliper_%s%s' % (key, sk), c, location=loc)
            out['%s%s' % (key, sk)] = loc
    car.info['wheels'] = out
    return out


# =====================================================================================
# build
# =====================================================================================
def make_materials():
    mats = ck.default_materials(paint=PAINT_LIN, paint_metallic=0.0, paint_rough=0.30, paint_coat=0.7,
                                rim=(0.86, 0.86, 0.88), rim_metallic=1.0, rim_rough=0.10,
                                caliper=(0.20, 0.20, 0.21),
                                interior=(0.70, 0.60, 0.43), interior_dark=(0.040, 0.028, 0.020))
    mats['Interior'] = dict(base=(0.70, 0.60, 0.43), roughness=0.50)            # cream leather
    mats['InteriorDark'] = dict(base=(0.040, 0.028, 0.020), roughness=0.85)     # dark brown carpet / roll
    mats['Gauge'] = dict(base=(0.72, 0.66, 0.52), roughness=0.35, emission=(1.0, 0.90, 0.72), strength=0.35)
    mats['Chrome'] = dict(base=(0.88, 0.88, 0.90), metallic=1.0, roughness=0.08)
    mats['Trim'] = dict(base=(0.020, 0.020, 0.022), roughness=0.45)
    mats['Rubber'] = dict(base=(0.020, 0.020, 0.022), roughness=0.90)
    mats['Whitewall'] = dict(base=(0.80, 0.79, 0.74), roughness=0.75)
    mats['BrakeDisc'] = dict(base=(0.16, 0.16, 0.17), metallic=1.0, roughness=0.50)
    mats['Glass'] = dict(base=(0.012, 0.016, 0.018), roughness=0.03, alpha=0.30, double_sided=True)
    mats['HeadlightLens'] = dict(base=(0.92, 0.93, 0.95), roughness=0.05, emission=(1.0, 0.96, 0.86), strength=1.2)
    mats['TaillightLens'] = dict(base=(0.30, 0.008, 0.010), roughness=0.10, emission=(1.0, 0.04, 0.03), strength=0.5)
    mats['BrakeLens'] = dict(base=(0.42, 0.012, 0.012), roughness=0.10, emission=(1.0, 0.03, 0.02), strength=0.3)
    return mats


def build():
    car = ck.CarAssembly(CAR_ID, CAR_NAME, make_materials())
    shell = BODY.build(car, arches=ARCHES, inner=INNER, glass_inset=0.006)
    car.shell = shell
    car.add('Body', shell.bm)
    car.add('Interior', shell.inner)
    if STAGE != 'body':
        body_details(car, shell.surface)
        windscreen(car, shell.surface)
        interior(car)
        car.socket('Socket_CamHood', (0.0, 0.66, 1.00))
        car.socket('Socket_CamCockpit', EYE)
        car.socket('Socket_CamBumper', (0.0, NOSE_Y + 0.09, 0.46))
    add_wire_wheels(car)
    car.finalize()
    car.info['lip_sharp_edges'] = sharpen_arch_lips(car)
    return car, shell


# =====================================================================================
# exterior details
# =====================================================================================
def dome_lens(center, normal, r, h, mat, segs=24):
    """Shallow spherical-cap lens standing on `center`, bulging along `normal`."""
    prof = [(0.0, r), (h * 0.45, r * 0.86), (h * 0.80, r * 0.56), (h, 0.0)]
    return ck.revolve(prof, segs, mat).transformed(Matrix.Translation(Vector(center)) @ _x_to(normal))


def bezel(center, normal, r, mat='Chrome', h=0.014, w=0.014, segs=24):
    """Round chrome lamp bezel (ring) standing on `center` around radius r."""
    prof = [(-0.006, r + w), (h * 0.85, r + w * 0.80), (h, r + w * 0.45), (h * 0.85, r + w * 0.12), (-0.006, r)]
    return ck.revolve(prof, segs, mat).transformed(Matrix.Translation(Vector(center)) @ _x_to(normal))


def lamp_pod(c_front, length=0.345, r=0.099, segs=24):
    """Headlamp nacelle (Paint) along +Y ending at c_front: a tapered body of revolution whose rear half sinks into
    the fender crown, so the lamp stands on top of the fender. Front face is a dark lamp bucket (Trim)."""
    prof = [(0.0, 0.0), (0.02, 0.030), (0.08, 0.062), (0.16, 0.084), (0.24, 0.095), (0.30, r), (length - 0.010, r),
            (length, r - 0.005), (length, 0.0)]
    p = ck.revolve(prof, segs, ['Paint'] * 7 + ['Trim'])
    M = Matrix.Translation(Vector(c_front) - Vector((0.0, length, 0.0))) @ Matrix.Rotation(math.radians(90.0), 4, 'Z')
    return p.transformed(M)


def blade(S_, z, center_y, ahead, a_lim, gap=0.007, height=0.056, depth=0.026, n=34, end_taper=5):
    """Thin chrome blade bumper standing `gap` off the body plan outline at height z (wraps round the corners)."""
    pts = S_.outline_at_z(z, center=(0.0, center_y), a0=-a_lim, a1=a_lim, n=n, ahead=ahead)
    path = [p + nrm * gap for (p, nrm) in pts]
    nors = [nrm for (p, nrm) in pts]
    hh = height / 2
    base = [(-0.004, -hh + 0.005), (0.004, -hh), (depth * 0.6, -hh + 0.003), (depth * 0.92, -hh * 0.55), (depth, 0.0),
            (depth * 0.92, hh * 0.55), (depth * 0.6, hh - 0.003), (0.004, hh), (-0.004, hh - 0.005)]
    profs = []
    m = len(path)
    for i in range(m):
        e = min(i, m - 1 - i)
        k = 1.0 if e >= end_taper else 0.10 + 0.90 * math.sin(0.5 * math.pi * e / end_taper) ** 0.7
        kz = 1.0 if e >= end_taper else 0.55 + 0.45 * k
        profs.append([(u * k if u > 0 else u, v * kz) for (u, v) in base])
    return ck.sweep_path(path, profs, 'Chrome', normals=nors), pts


GRILLE_Z, GRILLE_A, GRILLE_B = 0.540, 0.205, 0.100     # small oval grille: centre height, semi-axes
HL = Vector((0.560, 1.845, 0.790))                     # right headlamp lens centre (front of the fender pod)


def front_details(car, S_, R, C, LH):
    F = S_.frame('front')
    # ---- small oval grille: dark mouth, fat chrome surround, vertical chrome bars + centre bar
    n = 48
    oval = [Vector((GRILLE_A * math.cos(2 * math.pi * k / n), GRILLE_Z + GRILLE_B * math.sin(2 * math.pi * k / n)))
            for k in range(n)]
    C.extend(S_.patch(oval, 'front', offset=0.0025, depth=0.006, res=0.03, mat='Grille', smooth=False, walls=False))
    ring = []
    for p in oval:
        loc, nor = S_.hit(F, p.x, p.y)
        ring.append(loc + nor * 0.008)
    C.extend(ck.rod_path(ring, 0.013, 'Chrome', n=10, closed=True))
    for k in range(9):
        x = -0.16 + 0.04 * k
        h = GRILLE_B * math.sqrt(max(0.0, 1.0 - (x / GRILLE_A) ** 2)) - 0.004
        pts = []
        for z in (GRILLE_Z - h, GRILLE_Z, GRILLE_Z + h):
            loc, nor = S_.hit(F, x, z)
            pts.append(loc + nor * 0.009)
        C.extend(ck.rod_path(pts, 0.0042, 'Chrome', n=6))
    pts = []
    for k in range(9):
        loc, nor = S_.hit(F, -0.196 + 0.392 * k / 8, GRILLE_Z)
        pts.append(loc + nor * 0.0115)
    C.extend(ck.rod_path(pts, 0.0065, 'Chrome', n=8))
    # ---- headlamps in raised pods on the fender tops
    R.extend(lamp_pod(HL))
    nf = Vector((0.0, 1.0, 0.0))
    R.extend(bezel(HL, nf, 0.080, h=0.016, w=0.015, segs=28))
    LH.extend(dome_lens(HL + nf * 0.002, nf, 0.080, 0.018, 'HeadlightLens', segs=28))
    car.socket('Socket_HeadlightR', HL + nf * 0.010)
    car.socket('Socket_HeadlightL', (-HL.x, HL.y + 0.010, HL.z))
    # ---- small round parking lamps in the fascia corners
    loc, nor = S_.hit(F, 0.452, 0.500)
    R.extend(bezel(loc + nor * 0.002, nor, 0.026, h=0.008, w=0.007, segs=16))
    LH.extend(dome_lens(loc + nor * 0.003, nor, 0.026, 0.010, 'HeadlightLens', segs=16))
    # ---- thin chrome blade bumper + overriders + brackets
    bump, _ = blade(S_, 0.420, 1.55, 1, 76.0)
    C.extend(bump)
    for x in (0.300, -0.300):
        loc, nor = S_.hit(F, x, 0.420)
        front = loc + nor * 0.033                      # blade front face
        C.extend(ck.ellipsoid(front + nor * (0.005 - 0.019) + Vector((0.0, 0.0, 0.040)), (0.021, 0.019, 0.078), 'Chrome',
                              nu=14, nv=10))
        C.extend(ck.box_between(loc - nor * 0.010, loc + nor * 0.016, 0.050, 0.026, 'Trim'))
    # ---- bonnet: shut lines along the fender valleys, rear edge at the scuttle, front edge over the fascia,
    # chrome centre strip
    valley = [BODY.point(y, 6.0) for y in (0.66, 0.80, 1.00, 1.20, 1.40, 1.56, 1.68, 1.76, 1.81, 1.835)]
    R.extend(S_.line3d(valley, step=0.03))
    C.extend(S_.line([(-0.432, 0.660), (-0.2, 0.660), (0.0, 0.660), (0.2, 0.660), (0.432, 0.660)], 'top', step=0.03))
    C.extend(S_.line([(-0.300, 0.651), (-0.15, 0.655), (0.0, 0.656), (0.15, 0.655), (0.300, 0.651)], 'front',
                     step=0.025))
    strip = [BODY.point(0.70 + (1.832 - 0.70) * k / 16, 8.0) for k in range(17)]
    C.extend(S_.line3d(strip, width=0.012, offset=0.0018, mat='Chrome', step=0.03))


def side_details(car, S_, R, C):
    # ---- door shut lines (front, rear, bottom) running up over the rolled door top to the cockpit edge
    for y in (0.312, -0.505):
        R.extend(S_.line([(y, 0.268), (y + 0.002, 0.45), (y + 0.004, 0.62), (y + 0.006, 0.735)], 'right', step=0.02))
        R.extend(S_.line3d([BODY.point(y + 0.006, t) for t in (3.95, 4.25, 4.55, 4.80, 4.985)], step=0.012))
    R.extend(S_.line([(0.312, 0.268), (0.0, 0.262), (-0.505, 0.262)], 'right', step=0.03))
    # ---- chrome door handle (dark recess behind it)
    R.extend(S_.patch(ck.densify(ck.rrect_pts(-0.400, 0.712, 0.100, 0.024, 0.010, n=3), 0.015), 'right',
                      offset=0.0012, depth=0.004, res=0.0, mat='Trim', smooth=False))
    R.extend(S_.patch(ck.densify(ck.rrect_pts(-0.400, 0.714, 0.088, 0.013, 0.006, n=3), 0.015), 'right',
                      offset=0.0070, depth=0.008, res=0.0, mat='Chrome', smooth=False))
    # ---- chrome sweep spear on the fender crease, from behind the front wheel down across the door
    spear = [BODY.point(0.840 - k * (0.840 + 0.560) / 30, 3.0) for k in range(31)]     # ends where the crease is lowest
    R.extend(S_.line3d(spear, width=0.011, offset=0.0016, mat='Chrome', step=0.03))
    # ---- louvred vent in the front fender behind the wheel
    vent = ck.densify(ck.fillet_poly([(0.470, 0.430), (0.700, 0.452), (0.700, 0.517), (0.470, 0.495)], 0.012, n=3), 0.02)
    R.extend(S_.patch(vent, 'right', offset=0.0015, depth=0.004, res=0.0, mat='Grille', smooth=False))
    R.extend(S_.rim(vent, 'right', width=0.008, offset=0.005, depth=0.004, mat='Chrome', smooth=False))
    for k in range(3):
        z0 = 0.447 + 0.0215 * k
        R.extend(S_.line(ck.densify([(0.482, z0), (0.688, z0 + 0.0195)], 0.02, closed=False), 'right', width=0.0055,
                         offset=0.004, mat='Chrome', smooth=False, step=0.02))
    # ---- round chrome wing mirrors on the front fender crowns
    base = S_.snap('top', 0.600, 0.980)
    R.extend(ck.ellipsoid(base + Vector((0.0, 0.0, 0.003)), (0.020, 0.030, 0.010), 'Chrome', nu=12, nv=6))
    head = base + Vector((0.030, -0.012, 0.125))
    R.extend(ck.rod_path([base + Vector((0.0, 0.0, 0.006)), base + Vector((0.010, -0.002, 0.070)),
                          head + Vector((-0.006, 0.006, -0.036))], 0.0055, 'Chrome', n=8))
    ry = 0.022

    def flat_back(p):
        if p.y < -ry * 0.3:
            p.y = -ry * 0.3 - (p.y + ry * 0.3) * 0.08
        return p
    R.extend(ck.ellipsoid(head, (0.046, ry, 0.042), 'Chrome', nu=18, nv=8, deform=flat_back))
    R.extend(ck.disc(head + Vector((0.0, -ry * 0.3 - 0.0012, 0.0)), (0, -1, 0), 0.040, 'Chrome', n=18))


def softtop_bundle(S_, C):
    """Folded black soft-top lying on the deck behind the seats (Trim), with two straps."""
    xe = 0.465
    xs = [-xe, -xe + 0.006, -xe + 0.020, -xe + 0.045, -xe + 0.085, -0.200, 0.0, 0.200, xe - 0.085, xe - 0.045,
          xe - 0.020, xe - 0.006, xe]
    yc, ry, rz = -0.880, 0.084, 0.041
    profs = []
    for x in xs:
        zd = S_.snap('top', ck.clamp(x, -0.45, 0.45), yc).z
        e = xe - abs(x)
        k = 0.30 + 0.70 * math.sqrt(max(0.0, 1.0 - (1.0 - min(e, 0.085) / 0.085) ** 2))
        prof = []
        for j in range(14):
            a = 2 * math.pi * j / 14
            prof.append((yc + ry * k * math.cos(a), zd + 0.031 * k + rz * k * math.sin(a) * (1.0 if math.sin(a) > 0 else 0.8)))
        profs.append(prof)
    C.extend(ck.sweep_axis('x', xs, profs, 'Trim'))
    for x in (-0.26, 0.26):
        zd = S_.snap('top', x, yc).z
        loop = [Vector((x, yc + (ry + 0.004) * math.cos(2 * math.pi * j / 16),
                        zd + 0.031 + (rz + 0.004) * math.sin(2 * math.pi * j / 16) *
                        (1.0 if math.sin(2 * math.pi * j / 16) > 0 else 0.8))) for j in range(16)]
        C.extend(ck.rod_path(loop, 0.006, 'Trim', n=4, closed=True))


def rear_details(car, S_, R, C, LT, LB, LR):
    B = S_.frame('rear')
    # ---- small round tail lamps on the rear fender ends: tail ring + raised brake centre
    loc, nor = S_.hit(B, 0.505, 0.655)
    R.extend(bezel(loc + nor * 0.002, nor, 0.046, h=0.012, w=0.011, segs=24))
    LT.extend(dome_lens(loc + nor * 0.003, nor, 0.046, 0.012, 'TaillightLens', segs=24))
    LB.extend(dome_lens(loc + nor * 0.003, nor, 0.024, 0.019, 'BrakeLens', segs=16))
    # ---- small round reversing lamps
    loc, nor = S_.hit(B, 0.360, 0.525)
    R.extend(bezel(loc + nor * 0.002, nor, 0.020, h=0.007, w=0.006, segs=16))
    LR.extend(dome_lens(loc + nor * 0.003, nor, 0.020, 0.008, 'ReverseLens', segs=16))
    # ---- number-plate recess + chrome plate-lamp hood
    plate = ck.densify(ck.rrect_pts(0.0, 0.565, 0.300, 0.140, 0.010, n=2), 0.04)
    C.extend(S_.patch(plate, 'rear', offset=0.0015, depth=0.004, res=0.025, mat='Grille', smooth=False))
    C.extend(S_.rim(plate, 'rear', width=0.010, offset=0.005, depth=0.004, mat='Chrome', smooth=False))
    loc, nor = S_.hit(B, 0.0, 0.652)
    C.extend(ck.ellipsoid(loc + nor * 0.002, (0.060, 0.016, 0.013), 'Chrome', nu=14, nv=6))
    # ---- boot lid shut line on the deck, chrome boot handle, chrome filler cap on the right rear fender
    boot = ck.densify(ck.fillet_poly([(-0.380, -1.020), (0.380, -1.020), (0.380, -1.860), (-0.380, -1.860)], 0.07, n=4),
                      0.03)
    C.extend(S_.line(boot, 'top', closed=True, smooth=False, step=0.02))
    loc, nor = S_.hit(B, 0.0, 0.700)
    C.extend(ck.box_between(loc + Vector((-0.045, 0, 0)) + nor * 0.012, loc + Vector((0.045, 0, 0)) + nor * 0.012, 0.012,
                            0.012, 'Chrome'))
    for x in (-0.040, 0.040):
        C.extend(ck.box_between(loc + Vector((x, 0, 0)) - nor * 0.004, loc + Vector((x, 0, 0)) + nor * 0.012, 0.010, 0.010,
                                'Chrome'))
    loc, nor = S_.hit(S_.frame('top'), 0.585, -1.420)
    C.extend(dome_lens(loc - nor * 0.004, nor, 0.044, 0.016, 'Chrome', segs=20))
    # ---- rear blade bumper + overriders + brackets
    bump, _ = blade(S_, 0.460, -1.55, -1, 74.0)
    C.extend(bump)
    for x in (0.320, -0.320):
        loc, nor = S_.hit(B, x, 0.460)
        front = loc + nor * 0.033
        C.extend(ck.ellipsoid(front + nor * (0.005 - 0.019) + Vector((0.0, 0.0, 0.030)), (0.021, 0.019, 0.075), 'Chrome',
                              nu=14, nv=10))
        C.extend(ck.box_between(loc - nor * 0.010, loc + nor * 0.016, 0.050, 0.026, 'Trim'))
    # ---- single exhaust (right rear, under the bumper) + pipe along the floor
    p0 = Vector((0.360, -1.870, 0.245))                 # chrome tip only; the pipe under the car is dark
    p1 = Vector((0.360, -1.985, 0.245))
    C.extend(ck.tube(p0, p1, 0.025, 0.020, 'Chrome', 'Trim', n=18, inner_depth=0.05))
    C.extend(ck.rod_path([Vector((0.200, -0.300, 0.170)), Vector((0.320, -1.150, 0.180)), Vector((0.360, -1.600, 0.215)),
                          p0 + Vector((0.0, 0.030, 0.0))], 0.020, 'Underbody', n=10))
    car.socket('Socket_Exhaust', p1)


def body_details(car, S_):
    """Exterior details, all conforming to the shell. Right side built, then mirrored."""
    R = ck.Part()      # right-side parts (mirrored)
    C = ck.Part()      # centre / one-off parts (not mirrored)
    LH, LT, LB, LR = ck.Part(), ck.Part(), ck.Part(), ck.Part()
    front_details(car, S_, R, C, LH)
    side_details(car, S_, R, C)
    rear_details(car, S_, R, C, LT, LB, LR)
    softtop_bundle(S_, C)
    print('detail tris: right x2 =', 2 * R.tris(), 'centre =', C.tris())
    car.add('Body', R, R.mirrored_x(), C)
    car.add('Lights_Head', LH, LH.mirrored_x())
    car.add('Lights_Tail', LT, LT.mirrored_x())
    car.add('Lights_Brake', LB, LB.mirrored_x())
    car.add('Lights_Reverse', LR, LR.mirrored_x())


# =====================================================================================
# windscreen: low, plan-curved, raked; the pane is the only glass, framed by a chrome tube
# =====================================================================================
WS_Y0, WS_K, WS_RAKE = 0.470, 0.160, math.radians(30.0)   # base y at the centre, plan sweep y -= k x^2, rake
WS_TUBE = 0.011                                          # chrome frame tube radius
WS_TOP = 1.200 - WS_TUBE                                 # frame centre line at the top -> top of frame 1.20
WS_HW0, WS_HW1, WS_VREF = 0.625, 0.585, 0.330            # half width at the base / top, nominal slant height


def ws_map(S_):
    """(x, v) -> 3D on the windscreen surface; v in [0, WS_VREF] is the nominal slant height."""
    cache = {}

    def zb(x):
        key = round(x, 4)
        if key not in cache:
            p = S_.snap('top', x, WS_Y0 - WS_K * x * x)
            cache[key] = p.z + WS_TUBE + 0.001
        return cache[key]

    def f(x, v):
        z0 = zb(x)
        s = (WS_TOP - z0) / math.cos(WS_RAKE)          # true slant height at this x
        w = s * v / WS_VREF
        return Vector((x, WS_Y0 - WS_K * x * x - w * math.sin(WS_RAKE), z0 + w * math.cos(WS_RAKE)))
    return f


def windscreen(car, S_):
    f = ws_map(S_)
    outline = ck.fillet_poly([(-WS_HW0, 0.0), (WS_HW0, 0.0), (WS_HW1, WS_VREF), (-WS_HW1, WS_VREF)],
                             [0.015, 0.015, 0.070, 0.070], n=6)
    outline = ck.densify(outline, 0.05)
    # glass pane (CDT in the (x, v) parameter plane, mapped onto the curved raked surface)
    from mathutils import geometry
    pts = [Vector((p.x, p.y)) for p in outline]
    if ck.poly_area(pts) < 0:
        pts.reverse()
    nb = len(pts)
    verts = list(pts)
    gx = -WS_HW0 + 0.06
    while gx < WS_HW0:
        gv = 0.05
        while gv < WS_VREF:
            g = Vector((gx, gv))
            if ck.point_in_poly(g, pts) and ck.dist_to_poly(g, pts) > 0.03:
                verts.append(g)
            gv += 0.07
        gx += 0.08
    out = geometry.delaunay_2d_cdt(verts, [(k, (k + 1) % nb) for k in range(nb)], [list(range(nb))], 1, 1e-7)
    pane = ck.Part()
    vi = [pane.vert(f(co.x, co.y)) for co in out[0]]
    for fc in out[2]:
        pane.face([vi[i] for i in fc], 'Glass')
    pane.orient(0, ref=Vector((0.0, -1.5, 0.6)))                 # normals face forward / away from the cockpit
    car.add('Glass', pane)
    # chrome frame tube round the pane (sits on the scuttle at the bottom)
    ring = [f(p.x, p.y) for p in pts]
    W = ck.Part()
    W.extend(ck.rod_path(ring, WS_TUBE, 'Chrome', n=8, closed=True))
    # side stanchions into the scuttle + mounting feet
    for sx in (1, -1):
        a = f(sx * WS_HW0, 0.0)
        W.extend(ck.rod(a + Vector((0, 0, 0.004)), a + Vector((0.0, 0.020, -0.045)), 0.013, 'Chrome', n=10))
        W.extend(ck.ellipsoid(a + Vector((0.0, 0.010, -0.008)), (0.022, 0.030, 0.010), 'Chrome', nu=12, nv=6))
    # rear-view mirror on the top centre of the frame
    top = f(0.0, WS_VREF)
    head = top + Vector((0.0, -0.050, -0.068))
    W.extend(ck.rod(top + Vector((0, -0.004, -0.004)), head + Vector((0.0, 0.010, 0.020)), 0.0055, 'Chrome', n=8))
    W.extend(ck.ellipsoid(head, (0.082, 0.013, 0.030), 'Chrome', nu=18, nv=8, exp=2.6))
    W.extend(ck.ellipsoid(head + Vector((0.0, -0.004, 0.0)), (0.074, 0.010, 0.024), 'Trim', nu=18, nv=6, exp=2.6))
    # parked wipers on the scuttle ahead of the glass
    for (x0, x1) in ((-0.470, -0.080), (0.060, 0.450)):
        y0, y1 = WS_Y0 - WS_K * x0 * x0 + 0.040, WS_Y0 - WS_K * x1 * x1 + 0.022
        a0 = S_.snap('top', x0, y0) + Vector((0, 0, 0.010))
        a1 = S_.snap('top', x1, y1) + Vector((0, 0, 0.008))
        W.extend(ck.box_between(a0, a1, 0.010, 0.006, 'Chrome'))
        W.extend(ck.ellipsoid(a0 + Vector((0, 0, -0.002)), (0.012, 0.012, 0.008), 'Chrome', nu=10, nv=6))
    car.add('Body', W)
    car.info['ws_top'] = top


# =====================================================================================
# interior
# =====================================================================================
def vgauge(center, normal, r, n_ticks=9, arc=270.0, needle_deg=215.0):
    """Vintage round gauge: cream face (Gauge), dark ticks and needle, chrome bezel."""
    c = Vector(center)
    nrm = Vector(normal).normalized()
    u = ck._unit(Vector((0, 0, 1)).cross(nrm), Vector((1, 0, 0)))
    w = nrm.cross(u)
    part = ck.disc(c, nrm, r, 'Gauge', n=28)
    for k in range(n_ticks):
        a = math.radians(90 + arc / 2 - arc * k / (n_ticks - 1))
        d = u * math.cos(a) + w * math.sin(a)
        side = nrm.cross(d) * (0.0028 if k % 2 == 0 else 0.0018)
        p0 = c + d * r * (0.72 if k % 2 == 0 else 0.80) + nrm * 0.0012
        p1 = c + d * r * 0.93 + nrm * 0.0012
        t = ck.Part()
        q = [t.vert(p0 - side), t.vert(p1 - side), t.vert(p1 + side), t.vert(p0 + side)]
        t.face(q, 'InteriorDark')
        if t.face_normal(0).dot(nrm) < 0:
            t.f[0] = tuple(reversed(t.f[0]))
        part.extend(t)
    a = math.radians(needle_deg)
    d = u * math.cos(a) + w * math.sin(a)
    side = nrm.cross(d) * 0.0022
    t = ck.Part()
    q = [t.vert(c - d * 0.012 - side + nrm * 0.0025), t.vert(c + d * r * 0.86 + nrm * 0.0025),
         t.vert(c - d * 0.012 + side + nrm * 0.0025)]
    t.face(q, 'InteriorDark')
    if t.face_normal(0).dot(nrm) < 0:
        t.f[0] = tuple(reversed(t.f[0]))
    part.extend(t)
    part.extend(ck.disc(c + nrm * 0.003, nrm, 0.006, 'Chrome', n=10))
    part.extend(bezel(c - nrm * 0.001, nrm, r, mat='Chrome', h=0.008, w=0.007, segs=28))
    return part


def vintage_seat(x, y_front, y_back, z_base, width=0.46, back_h=0.56, recline=15.0, pleats=5):
    """Low-back 1950s seat in cream leather with rolled pleats (cushion + backrest), dark plinth."""
    part = ck.Part()
    hw = width / 2

    def prof(w2, h, rise, ripple, m=30):
        pts = [(-w2 + 0.022, 0.0), (w2 - 0.022, 0.0), (w2, 0.022), (w2, h - 0.018)]
        for k in range(m + 1):
            u = 1.0 - 2.0 * k / m
            xx = u * (w2 - 0.010)
            inner = abs(u) < 0.66
            rip = ripple * abs(math.sin(math.pi * pleats * (u + 0.66) / 1.32)) if inner else 0.0
            zz = h + rise * ck.smoothstep(0.62, 0.92, abs(u)) + rip - (0.012 * ck.smoothstep(0.92, 1.0, abs(u)))
            pts.append((xx, zz))
        pts += [(-w2, h - 0.018), (-w2, 0.022)]
        return pts
    # cushion along -Y
    L = y_front - y_back
    ys = [y_front, y_front - 0.025, y_front - 0.07, y_front - 0.5 * L, y_back + 0.03, y_back]
    profs = []
    for yy in ys:
        f = (y_front - yy) / L
        h = 0.115 + 0.020 * (1 - f)
        sc = 0.80 if yy == y_front else (0.95 if yy == ys[1] else 1.0)
        pr = prof(hw * (0.97 if yy == y_front else 1.0), h * sc, 0.030 * sc, 0.007 * sc)
        profs.append([(x + px, z_base + pz) for (px, pz) in pr])
    part.extend(ck.sweep_axis('y', ys, profs, 'Interior', cap0=True, cap1=True, cap_mat='Interior'))
    # backrest: built upright along Z (pleated face toward +Y), then reclined about X at its base
    zs = [0.0, 0.035, 0.20, 0.36, back_h - 0.10, back_h - 0.045, back_h - 0.012, back_h]
    wk = [0.97, 1.0, 1.0, 1.0, 0.97, 0.90, 0.80, 0.66]
    profs = []
    for zz, k in zip(zs, wk):
        t = 0.085
        pr = prof(hw * k, t * (0.85 if zz == back_h else 1.0), 0.026 * k, 0.006 if zz < back_h - 0.05 else 0.002)
        profs.append([(x + px, pz) for (px, pz) in pr])
    back = ck.sweep_axis('z', zs, profs, 'Interior', cap0=True, cap1=True, cap_mat='Interior')
    M = Matrix.Translation((0, y_back - 0.065, z_base + 0.045)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    part.extend(back.transformed(M))
    # dark plinth / runners under the cushion
    part.extend(ck.box_between((x, y_front - 0.06, z_base - 0.010), (x, y_back + 0.04, z_base - 0.010), width * 0.78, 0.030,
                               'InteriorDark'))
    return part


def cockpit_edge_loop():
    """3D points round the cockpit opening (K5 sides, warped U-shaped rear edge, straight front edge)."""
    ys_side = [Y_CK_F - (Y_CK_F - WARP_CK['y_t'][0]) * k / 24 for k in range(25)]       # 0.30 -> -0.60
    right = [BODY.point(y, 5.0) for y in ys_side]
    rear = [BODY.point(BODY.warp_y(Y_CK_R, 5.0 + 3.0 * k / 12), 5.0 + 3.0 * k / 12) for k in range(1, 13)]
    front = [BODY.point(Y_CK_F, 8.0 - 3.0 * k / 12) for k in range(12)]                   # centre -> right K5
    half = front + right + rear                          # centre front -> right side -> centre rear
    left = [Vector((-p.x, p.y, p.z)) for p in reversed(half[1:-1])]
    return half + left


def interior(car):
    I = ck.Part()
    # ---- dashboard: cream padded roll under the cockpit edge, painted face, dark lower lip
    dash = [(0.62, 0.795), (0.45, 0.803), (0.36, 0.804), (0.318, 0.798), (0.300, 0.786), (0.302, 0.772),
            (0.315, 0.762), (0.322, 0.745), (0.322, 0.605), (0.335, 0.580), (0.40, 0.560), (0.62, 0.552)]
    dm = ['InteriorDark', 'Interior', 'Interior', 'Interior', 'Interior', 'Interior', 'Paint', 'Paint', 'Paint',
          'InteriorDark', 'InteriorDark', 'InteriorDark']
    xs = [-0.715, -0.700, -0.620, -0.45, -0.15, 0.15, 0.45, 0.620, 0.700, 0.715]
    profs = []
    for xx in xs:
        sc = 0.0 if abs(xx) < 0.71 else 0.008
        cap = 0.81 if abs(xx) < 0.65 else 0.765          # ends tucked under the rolled door tops
        profs.append([(y + sc, min(z, cap) - sc) for (y, z) in dash])
    I.extend(ck.sweep_axis('x', xs, profs, dm))
    face_y = 0.322
    # big speedometer + rev counter in front of the driver, three small dials + clock in the centre
    for (dx, nt, r) in ((-0.085, 11, 0.056), (0.085, 9, 0.056)):
        c = Vector((HUB.x + dx, face_y - 0.010, 0.686))
        I.extend(vgauge(c, (0, -1, 0.12), r, n_ticks=nt))
    for (xx, r) in ((-0.075, 0.026), (0.0, 0.036), (0.075, 0.026)):
        c = Vector((xx, face_y - 0.006, 0.700))
        I.extend(vgauge(c, (0, -1, 0.10), r, n_ticks=7))
    # toggle switches + chrome knobs
    for k in range(4):
        xx = -0.090 + 0.060 * k
        I.extend(ck.ellipsoid((xx, face_y - 0.002, 0.636), (0.008, 0.004, 0.008), 'Chrome', nu=8, nv=4))
        I.extend(ck.rod((xx, face_y - 0.004, 0.636), (xx, face_y - 0.024, 0.644), 0.0022, 'Chrome', n=6))
    for xx in (-0.150, 0.150):
        I.extend(ck.ellipsoid((xx, face_y - 0.006, 0.636), (0.011, 0.008, 0.011), 'Interior', nu=10, nv=6))
    # glovebox lid outline + chrome push button (passenger side)
    gb = ck.rrect_pts(0.0, 0.0, 0.26, 0.11, 0.015, n=3)
    lid = ck.Part()
    gbz = 0.690
    ring = [Vector((0.38 + p.x, face_y - 0.0015, gbz + p.y)) for p in gb]
    lid.extend(ck.rod_path(ring, 0.0025, 'InteriorDark', n=4, closed=True))
    I.extend(lid)
    I.extend(ck.ellipsoid((0.38, face_y - 0.003, gbz + 0.035), (0.010, 0.004, 0.010), 'Chrome', nu=10, nv=4))
    # ---- steering column (from the hub down into the dash)
    col = Vector((0.0, math.cos(math.radians(COLUMN_TILT)), -math.sin(math.radians(COLUMN_TILT))))
    I.extend(ck.rod(HUB + col * 0.055, HUB + col * 0.40, 0.021, 'InteriorDark', n=12))
    # ---- transmission tunnel, gear lever with an ivory knob, handbrake
    tys = [0.640, 0.540, 0.300, 0.050, -0.250, -0.560]
    tops = [0.380, 0.372, 0.345, 0.318, 0.300, 0.290]
    tw = [0.120, 0.118, 0.110, 0.100, 0.092, 0.088]
    profs = [[(-w, 0.232), (w, 0.232), (w + 0.004, t - 0.035), (w * 0.72, t), (-w * 0.72, t), (-w - 0.004, t - 0.035)]
             for t, w in zip(tops, tw)]
    I.extend(ck.sweep_axis('y', tys, profs, 'InteriorDark'))
    I.extend(ck.ellipsoid((0.0, 0.180, 0.352), (0.045, 0.055, 0.016), 'InteriorDark', nu=12, nv=6))
    I.extend(ck.rod((0.0, 0.182, 0.350), (0.0, 0.112, 0.578), 0.0065, 'Chrome', n=8))
    I.extend(ck.ellipsoid((0.0, 0.108, 0.594), (0.021, 0.021, 0.021), 'Interior', nu=12, nv=8))
    I.extend(ck.rod((0.0, -0.200, 0.305), (0.0, -0.020, 0.365), 0.008, 'Chrome', n=8))
    I.extend(ck.rod((0.0, -0.020, 0.365), (0.0, 0.030, 0.372), 0.013, 'InteriorDark', n=8))
    # ---- pedals
    for xx, w in ((-0.415, 0.050), (-0.320, 0.070), (-0.225, 0.050)):
        I.extend(ck.box_between((xx, 0.585, 0.290), (xx, 0.548, 0.385), w, 0.012, 'InteriorDark'))
        I.extend(ck.rod((xx, 0.575, 0.385), (xx, 0.620, 0.520), 0.006, 'InteriorDark', n=6))
    # ---- two cream leather seats
    for xx in (-0.320, 0.320):
        I.extend(vintage_seat(xx, -0.060, -0.500, 0.240, width=0.500, back_h=0.560, recline=15.0))
    # ---- door cards: chrome strip + door pull, mirrored
    door = ck.Part()
    door.extend(ck.box_between((0.722, 0.270, 0.640), (0.722, -0.470, 0.640), 0.006, 0.010, 'Chrome', up=(1, 0, 0)))
    door.extend(ck.box_between((0.702, 0.150, 0.700), (0.702, 0.060, 0.700), 0.012, 0.018, 'Chrome'))
    door.extend(ck.box_between((0.722, -0.050, 0.520), (0.722, -0.350, 0.520), 0.004, 0.006, 'InteriorDark', up=(1, 0, 0)))
    I.extend(door, door.mirrored_x())
    # ---- padded leather roll round the cockpit opening (hides the reveal)
    loop = []
    for p in cockpit_edge_loop():
        inward = Vector((-p.x, 0.0, 0.0)).normalized() * 0.006 if abs(p.x) > 0.05 else Vector((0, 0, 0))
        if abs(p.y - Y_CK_F) < 1e-6:
            inward = Vector((0.0, -0.006, 0.0))
        loop.append(p + inward + Vector((0.0, 0.0, -0.002)))
    I.extend(ck.rod_path(loop, 0.016, 'InteriorDark', n=7, closed=True))
    car.add('Interior', I, mats=['Interior', 'InteriorDark', 'Gauge', 'Paint', 'Chrome'])
    # ---- large thin 2-spoke steering wheel with a chrome horn ring (separate object, origin at the hub)
    sw = ck.steering_wheel_part(R=SW_R, tube_r=(0.0085, 0.0100), segs=48, flat_bottom=False,
                                spokes=((-14.0, 0.020), (194.0, 0.020)), hub_r=0.040, rim_mat='Interior',
                                spoke_mat='Chrome', hub_mat='Chrome', marker=False, spoke_thick=0.005, dish=0.050)
    sw.extend(ck.torus((0.0, 0.026, 0.0), (0, 1, 0), 0.118, 0.0032, 'Chrome', nu=40, nv=6))
    sw.extend(ck.disc((0.0, -0.0135, 0.0), (0, -1, 0), 0.030, 'Interior', n=20, ring_mat='Chrome', ring_w=0.004))
    car.add('SteeringWheel', sw, location=HUB, rotation=(math.radians(-COLUMN_TILT), 0.0, 0.0),
            mats=['InteriorDark', 'Interior', 'Gauge', 'Chrome'])


# =====================================================================================
# QA helpers
# =====================================================================================
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
    """Interior vertices that poke out of the body below the cockpit edge: a ray straight down must hit the Body
    floor and rays to +-X must hit the Body (only tested below the door-top height, the cockpit is open above)."""
    import bpy
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    body = BVHTree.FromObject(car.objects['Body'], dg)
    bad = []
    for nm in ('Interior',):
        ob = car.objects[nm]
        M = ob.matrix_world
        for v in ob.data.vertices:
            p = M @ v.co
            down = body.ray_cast(p + Vector((0, 0, 0.0005)), Vector((0, 0, -1)), 2.0)[0]
            ok = down is not None
            if p.z < BODY.params_at(ck.clamp(p.y, -0.6, 0.3))['zg'] - 0.03:
                for sx in (1, -1):
                    if body.ray_cast(p, Vector((sx, 0, 0)), 2.0)[0] is None:
                        ok = False
            if not ok:
                bad.append(p)
    return len(bad), [tuple(round(c, 3) for c in p) for p in bad[:6]]


def hero_world(on, added=None):
    """Temporarily drive the QA world's background colour with a sky -> horizon -> ground gradient (by view
    direction) so chrome has something to reflect in the hero render; hero_world(False, added) removes the nodes
    again (the kit's render_hero only sets the flat background colour, which it keeps owning)."""
    import bpy
    world = bpy.data.worlds.get('QA_World') or bpy.data.worlds.new('QA_World')
    try:
        world.use_nodes = True
    except Exception:
        pass
    nt = world.node_tree
    if not on:
        for n in (added or []):
            if n.name in nt.nodes:
                nt.nodes.remove(n)
        return []
    bg = next((n for n in nt.nodes if n.type == 'BACKGROUND'), None)
    if bg is None:
        return []
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0])          # world: Generated = view direction
    nt.links.new(sep.outputs[2], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = 0.40, (0.16, 0.16, 0.17, 1.0)        # ground (dir.z = -0.2)
    el[1].position, el[1].color = 1.00, (0.42, 0.55, 0.75, 1.0)        # zenith
    e2 = el.new(0.50)
    e2.color = (0.90, 0.90, 0.88, 1.0)                                 # bright horizon band
    e3 = el.new(0.62)
    e3.color = (0.62, 0.70, 0.82, 1.0)                                 # sky
    mp = nt.nodes.new('ShaderNodeMapRange')                           # dir.z -1..1 -> 0..1
    mp.inputs['From Min'].default_value = -1.0
    mp.inputs['From Max'].default_value = 1.0
    nt.links.new(sep.outputs[2], mp.inputs['Value'])
    nt.links.new(mp.outputs['Result'], ramp.inputs[0])
    return [tc, sep, ramp, mp]


RENDER_PATH = os.path.join(PROJECT, 'docs', 'blender_cars', CAR_ID + '.png')
GLB_PATH = os.path.join(PROJECT, 'assets', 'imported', 'cars', CAR_ID + '.glb')
JSON_PATH = os.path.join(PROJECT, 'assets', 'imported', 'cars', CAR_ID + '.json')


def measure(car, tris):
    G = ck.to_godot
    body = car.objects['Body']
    M = body.matrix_world
    bv = [M @ v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in bv), min(v.y for v in bv), min(v.z for v in bv)))
    mx = Vector((max(v.x for v in bv), max(v.y for v in bv), max(v.z for v in bv)))
    width_body = 2 * max(abs(v.x) for v in bv if v.z < 0.95)          # wing mirror heads excluded
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
    glass = car.objects['Glass']
    gz = max((glass.matrix_world @ v.co).z for v in glass.data.vertices)
    return {
        'id': CAR_ID, 'name': CAR_NAME, 'class': 'vintage open two-seat roadster', 'drivetrain': 'RWD',
        'engine': 'front, inline-4', 'doors': 2, 'seats': 2, 'roof': 'open (folded soft-top bundle behind the seats)',
        'source_blend': 'Opus55ForzaUltracodeEffort.blend', 'collection': 'Cars/Car_' + CAR_ID,
        'coordinate_system': 'Godot: x right, y up, z = -BlenderY (car faces -z); metres; origin = ground, mid-axles',
        'length': round(mx.y - mn.y, 4), 'length_body_shell': round(NOSE_Y - TAIL_Y, 4),
        'width': round(width_body, 4), 'width_with_mirrors': round(mx.x - mn.x, 4),
        'height': round(all_mx.z, 4), 'height_windscreen_glass_top': round(gz, 4),
        'height_body_sides': round(BODY.params_at(0.0)['zg'], 4),          # dipped door top (cockpit edge)
        'height_fender_crowns': [round(BODY.params_at(YF)['zg'], 4), round(BODY.params_at(YR)['zg'], 4)],
        'height_scuttle': round(BODY.params_at(0.45)['zc'], 4),
        'ground_clearance': round(BODY.params_at(0.0)['zb'], 4), 'ground_clearance_min': round(mn.z, 4),
        'wheelbase': round(wheels['FL'].y - wheels['RL'].y, 4),
        'track_front': round(wheels['FR'].x - wheels['FL'].x, 4), 'track_rear': round(wheels['RR'].x - wheels['RL'].x, 4),
        'wheel_radius_front': round(rf, 4), 'wheel_radius_rear': round(rr, 4),
        'wheel_width_front': round(wf, 4), 'wheel_width_rear': round(wr, 4),
        'tyre_width_nominal': WHEEL_W,
        'wheel_width_note': 'measured over the whole wheel object incl. the knock-off spinner and brake disc; tyre 0.165',
        'rim_diameter_in': RIM_IN, 'rim_style': 'chrome wire wheel (40 laced spokes) with 2-eared knock-off spinner',
        'tyre_style': 'tall whitewall bias-ply look',
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
        'default_paint': {'hex': PAINT_HEX, 'linear_rgb': list(PAINT_LIN), 'finish': 'gloss pastel'},
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
        isolate(True)
        try:
            print('qa', ck.qa_checks(CAR, WHEEL_R, WHEEL_W), 'interior verts in wheel wells:', interior_in_wells(CAR),
                  'interior leaks:', interior_leaks(CAR))
        finally:
            isolate(False)
    if RENDER:
        isolate(True)
        added = hero_world(True)
        try:
            print('render', ck.render_hero(CAR, RENDER_PATH, cam_loc=(4.5, 5.2, 1.40), target=(0.0, 0.05, 0.52),
                                           lens=50.0, world_strength=0.9, sun_energy=3.6, exposure=-0.35))
        finally:
            hero_world(False, added)
            if not globals().get('KEEP_ISOLATED', False):
                isolate(False)
    if globals().get('KEEP_ISOLATED', False):
        isolate(True)
    if EXPORT:
        RES, INFO, DATA = export_all(CAR)
        print('export', RES, INFO['file_size'], [(n['name'], n['translation']) for n in INFO['nodes']])
        print('materials', INFO['materials'])
