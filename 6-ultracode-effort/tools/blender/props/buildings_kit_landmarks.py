"""Sunward Roads buildings kit - part 2: pier, fishing boat, lighthouse, castle ruins, wind turbine (tower + separate
rotor), desert water tower, festival stage + tent, viewpoint deck.

Exec'd into the namespace of tools/blender/props/buildings_kit.py (uses its helpers and `register`).
"""

MATS.update({
    'BK_Stone_Castle': dict(c=(150, 146, 136), r=0.95),
})


# ------------------------------------------------------------------------------------------------------ helpers
def block_column(pb, quad, segs, nb_lo, nb_hi, zs, mat, R, base_k=0, inner_from=None, tint_fn=None):
    """One column of coursed masonry. quad = 4 plan corners (outer-left, outer-right, inner-right, inner-left),
    segs = list of (k0, k1) course-index ranges that exist (zs = course heights), nb_lo / nb_hi = sets of course
    indices present in the neighbour on the left (OL-IL side) / right (OR-IR side) side (exposed sides get faces).
    inner_from: skip inner faces below this course index (hidden below a floor)."""
    OL, OR, IR, IL = [Vector((p[0], p[1], 0.0)) for p in quad]
    C = (OL + OR + IR + IL) / 4
    own = set()
    for k0, k1 in segs:
        own |= set(range(k0, k1))
    if not own:
        return
    ks = sorted(own)
    levels = sorted(set([k for k in ks] + [k + 1 for k in ks]))
    vid = {}
    verts = []
    for k in levels:
        for nm, p in (('OL', OL), ('OR', OR), ('IR', IR), ('IL', IL)):
            vid[(nm, k)] = len(verts)
            verts.append(Vector((p.x, p.y, zs[k])))
    faces, hints, cols = [], [], []

    def add(f, h, kk):
        faces.append(tuple(vid[x] for x in f))
        hints.append(h)
        c = R.uniform(0.8, 1.06)
        if tint_fn:
            c = tint_fn(c, kk)
        cols.append(kcol(c))
    out_n = ((OL + OR) / 2 - C).normalized()
    in_n = ((IL + IR) / 2 - C).normalized()
    l_n = ((OL + IL) / 2 - C).normalized()
    r_n = ((OR + IR) / 2 - C).normalized()
    for k in ks:
        add([('OL', k), ('OR', k), ('OR', k + 1), ('OL', k + 1)], out_n, k)
        if inner_from is None or k >= inner_from:
            add([('IR', k), ('IL', k), ('IL', k + 1), ('IR', k + 1)], in_n, k)
        if k not in nb_lo:
            add([('IL', k), ('OL', k), ('OL', k + 1), ('IL', k + 1)], l_n, k)
        if k not in nb_hi:
            add([('OR', k), ('IR', k), ('IR', k + 1), ('OR', k + 1)], r_n, k)
        if k + 1 not in own:
            add([('OL', k + 1), ('OR', k + 1), ('IR', k + 1), ('IL', k + 1)], Vector((0, 0, 1)), k)
        if k - 1 not in own and k > base_k:
            add([('OL', k), ('IL', k), ('IR', k), ('OR', k)], Vector((0, 0, -1)), k)
    pb.add(verts, faces, mat, fcols=cols, hint=hints)


def course_set(segs):
    s = set()
    for k0, k1 in segs:
        s |= set(range(k0, k1))
    return s


def sheet(pb, rings, mat, hint_fn, side_mat=None, fcol=None, smooth=False):
    """Open surface between consecutive rings (same vertex count, closed loops); orientation from hint_fn."""
    n = len(rings[0])
    verts = [Vector(p) for r in rings for p in r]
    faces, mats = [], []
    for i in range(len(rings) - 1):
        for j in range(n):
            j1 = (j + 1) % n
            faces.append((i * n + j, i * n + j1, (i + 1) * n + j1, (i + 1) * n + j))
            mats.append(side_mat(i, j) if side_mat else mat)
    return pb.add(verts, faces, mats, hint=hint_fn, fcol=fcol, smooth=smooth)


def square_ring(h, z, per_side=4, cx=0.0, cy=0.0):
    pts = []
    corners = [(-h, -h), (h, -h), (h, h), (-h, h)]
    for s in range(4):
        a, b = corners[s], corners[(s + 1) % 4]
        for k in range(per_side):
            t = k / per_side
            pts.append(V(cx + a[0] + (b[0] - a[0]) * t, cy + a[1] + (b[1] - a[1]) * t, z))
    return pts


# ====================================================================================================== waterfront
@register('Pier_Section')
def pier_section():
    """10 m timber pier section (runs along Y, tiles end to end), deck surface at Z 0 = origin."""
    pb = PB('Pier_Section', 501)
    R = pb.R
    L, Wp = 10.0, 3.0
    n = 46
    pw = L / n
    for i in range(n):
        y0 = -L / 2 + i * pw + 0.011
        y1 = y0 + pw - 0.022
        box2(pb, (-Wp / 2 + R.uniform(0.0, 0.03), y0, -0.065), (Wp / 2 - R.uniform(0.0, 0.03), y1, R.uniform(-0.008, 0.0)),
             'BK_Deck_Wood', fcol=kcol(R.uniform(0.72, 1.0)))
    for x in (-1.2, 0.0, 1.2):
        box2(pb, (x - 0.08, -L / 2, -0.3), (x + 0.08, L / 2, -0.06), 'BK_Wood_Dark', fcol=flat(0.75))
    for x in (-Wp / 2 + 0.02, Wp / 2 - 0.02):
        box2(pb, (x - 0.07, -L / 2, -0.32), (x + 0.07, L / 2, -0.06), 'BK_Wood_Dark', fcol=flat(0.7))
    for y in (-2.5, 2.5):
        box2(pb, (-1.78, y - 0.12, -0.56), (1.78, y + 0.12, -0.3), 'BK_Wood_Dark', fcol=flat(0.72))
        for x in (-1.6, 1.6):
            cyl(pb, (x, y), 0.16, -7.0, -0.33, 'BK_Wood_Dark', sides=8,
                fcol=lambda c, nn: kcol(0.55 if c.z < -1.4 else 0.78))
        for yo in (-0.2, 0.2):
            for (a, b) in (((-1.6, -0.75), (1.6, -2.9)), ((1.6, -0.75), (-1.6, -2.9))):
                beam(pb, (a[0], y + yo, a[1]), (b[0], y + yo, b[1]), 0.18, 0.06, 'BK_Wood_Dark', up=(0, 1, 0),
                     fcol=flat(0.7))
    # kerbs, bollards, cleats
    for x0, x1 in ((-Wp / 2, -Wp / 2 + 0.16), (Wp / 2 - 0.16, Wp / 2)):
        box2(pb, (x0, -L / 2, -0.01), (x1, L / 2, 0.15), 'BK_Wood_Mid', fcol=flat(0.85))
    for y in (-2.5, 2.5):
        cyl(pb, (1.15, y), 0.14, -0.02, 0.42, 'BK_Metal_Dark', sides=8, r1=0.12)
        cyl(pb, (1.15, y), 0.2, 0.42, 0.52, 'BK_Metal_Dark', sides=8, r1=0.17)
        box2(pb, (-1.25, y - 0.05, -0.01), (-1.15, y + 0.05, 0.12), 'BK_Metal_Dark')
        box2(pb, (-1.25, y - 0.22, 0.1), (-1.15, y + 0.22, 0.15), 'BK_Metal_Dark')
    # ladder down the +X side
    for y in (-0.22, 0.22):
        tube(pb, [V(Wp / 2 + 0.06, y, -2.6), V(Wp / 2 + 0.06, y, 0.0), V(Wp / 2 - 0.05, y, 0.75)], [0.035] * 3,
             'BK_Metal_Galv', sides=6, smooth=False)
    for k in range(8):
        z = -2.4 + k * 0.3
        tube(pb, [V(Wp / 2 + 0.06, -0.22, z), V(Wp / 2 + 0.06, 0.22, z)], [0.022, 0.022], 'BK_Metal_Galv', sides=5,
             smooth=False)
    # lamp post at one end (one per section -> every 10 m when tiled)
    tube(pb, [V(-1.2, -4.4, 0.1), V(-1.2, -4.4, 3.3)], [0.06, 0.05], 'BK_Metal_Dark', sides=8, smooth=False)
    box2(pb, (-1.32, -4.52, -0.01), (-1.08, -4.28, 0.12), 'BK_Metal_Dark')
    cyl(pb, (-1.2, -4.4), 0.17, 3.3, 3.75, 'BK_LampWarm', sides=8, r1=0.2)
    cyl(pb, (-1.2, -4.4), 0.26, 3.75, 3.9, 'BK_Metal_Dark', sides=8, r1=0.05)
    return pb


@register('Boat_Fishing')
def boat_fishing():
    """7 m inshore fishing boat (bow +Y), origin at the waterline: lofted hull with boot top and antifouling,
    wheelhouse, mast with lights, stern gantry with net drum, fish boxes, fenders, life ring."""
    pb = PB('Boat_Fishing', 502)
    R = pb.R
    ys = [-3.5, -3.1, -2.3, -1.3, -0.1, 1.1, 2.1, 2.8, 3.25, 3.5]
    hw = [1.0, 1.1, 1.18, 1.2, 1.19, 1.1, 0.88, 0.58, 0.28, 0.06]
    gs = [0.98, 0.95, 0.92, 0.91, 0.93, 0.99, 1.08, 1.18, 1.27, 1.34]
    ks = [-0.3, -0.52, -0.62, -0.66, -0.66, -0.62, -0.5, -0.25, 0.2, 0.75]
    rings = []
    for y, h, g, k in zip(ys, hw, gs, ks):
        bt = min(0.07, h * 0.5)
        z1 = max(0.5, k + 0.1)
        z2 = max(0.08, k + 0.08)
        z3 = max(0.0, k + 0.06)
        z4 = max(k * 0.55, k + 0.03)
        right = [(h, g), (h * 0.998, g - 0.13), (h * 0.995, z1), (h * 0.965, z2), (h * 0.95, z3), (h * 0.72, z4),
                 (0.06, k)]
        left = [(-x, z) for x, z in reversed(right)]
        deck = [(-(h - bt), g), (-(h - bt), g - 0.4), ((h - bt), g - 0.4), ((h - bt), g)]
        rings.append([V(x, y, z) for x, z in right + left + deck])
    # edge materials: 0 white strake, 1-2 hull, 3 boot top, 4-6 antifouling (incl. keel), mirrored, then deck parts
    em = (['BK_Hull_White', 'BK_Hull_Blue', 'BK_Hull_Blue', 'BK_Hull_White', 'BK_Antifouling', 'BK_Antifouling',
           'BK_Antifouling', 'BK_Antifouling', 'BK_Antifouling', 'BK_Antifouling', 'BK_Hull_White', 'BK_Hull_Blue',
           'BK_Hull_Blue', 'BK_Hull_White', 'BK_Wood_Mid', 'BK_Hull_White', 'BK_Deck_Wood', 'BK_Hull_White',
           'BK_Wood_Mid'])
    loft(pb, rings, 'BK_Hull_Blue', side_mat=lambda i, j: em[j], cap_mats=('BK_Hull_Blue', 'BK_Hull_Blue'),
         fcol=lambda c, n: kcol(0.82 if n.z > 0.6 else 0.95))

    def hw_at(y):
        for i in range(len(ys) - 1):
            if ys[i] <= y <= ys[i + 1]:
                t = (y - ys[i]) / (ys[i + 1] - ys[i])
                return lerp(hw[i], hw[i + 1], t), lerp(gs[i], gs[i + 1], t)
        return hw[-1], gs[-1]
    dz = 0.5
    # wheelhouse
    wy0, wy1 = -1.3, 0.4
    box2(pb, (-0.85, wy0, dz), (0.85, wy1, 2.45), 'BK_Hull_White', fcol=vary(R, 0.92, 0.98))
    window(pb, FY(wy1, 1), 0.0, 1.6, 1.4, 0.6, frame='BK_Hull_White', cols=3, rows=1, sill=None, fw=0.05, depth=0.05)
    for sgn in (1, -1):
        window(pb, FX(sgn * 0.85, sgn), -0.55, 1.65, 0.9, 0.5, frame='BK_Hull_White', cols=2, rows=1, sill=None,
               fw=0.05, depth=0.05)
    door(pb, FY(wy0, -1), 0.25, dz + 0.02, 0.6, 1.6, leaf='BK_Hull_Blue', frame='BK_Hull_White', ground=dz + 0.02,
         panels=1, fw=0.05, depth=0.05, knob='BK_Metal_Dark', step_w=0.7)
    box2(pb, (-0.97, wy0 - 0.12, 2.45), (0.97, wy1 + 0.18, 2.57), 'BK_Hull_Blue', fcol=flat(0.95))
    ring = [V(-0.45 + 0.24 * math.cos(TAU * k / 10), wy0 - 0.055, 1.55 + 0.24 * math.sin(TAU * k / 10)) for k in range(10)]
    tube(pb, ring, 0.05, 'BK_Buoy_Orange', sides=5, smooth=True, closed=True)
    # mast, yard, radar, lights
    tube(pb, [V(0.0, -0.6, 2.56), V(0.0, -0.6, 4.6)], [0.055, 0.04], 'BK_Hull_White', sides=6, smooth=False)
    beam(pb, (-0.6, -0.6, 4.0), (0.6, -0.6, 4.0), 0.05, 0.05, 'BK_Hull_White')
    cyl(pb, (0.0, -0.1), 0.06, 2.56, 2.72, 'BK_Metal_Dark', sides=6)
    box2(pb, (-0.42, -0.16, 2.72), (0.42, -0.04, 2.8), 'BK_Black')
    box2(pb, (-0.05, -0.65, 4.6), (0.05, -0.55, 4.72), 'BK_LampWarm')
    box2(pb, (-0.97, -0.2, 2.57), (-0.85, -0.05, 2.7), 'BK_Beacon_Red')
    box2(pb, (0.85, -0.2, 2.57), (0.97, -0.05, 2.7), 'BK_Nav_Green')
    # stern gantry with net drum
    for x in (-0.95, 0.95):
        beam(pb, (x, -3.05, dz - 0.05), (x * 0.92, -3.05, 2.7), 0.1, 0.1, 'BK_Metal_Galv')
        beam(pb, (x * 0.92, -3.05, 2.6), (x * 0.9, -1.95, dz), 0.06, 0.06, 'BK_Metal_Galv')
    beam(pb, (-0.92, -3.05, 2.65), (0.92, -3.05, 2.65), 0.1, 0.1, 'BK_Metal_Galv')
    tube(pb, [V(0.0, -3.05, 2.6), V(0.0, -2.55, 1.15)], [0.012, 0.012], 'BK_Rope', sides=4, smooth=False)
    tube(pb, [V(-0.62, -2.55, 0.85), V(0.62, -2.55, 0.85)], [0.3, 0.3], 'BK_Paint_Green', sides=10, smooth=True)
    for x in (-0.66, 0.66):
        tube(pb, [V(x - 0.03, -2.55, 0.85), V(x + 0.03, -2.55, 0.85)], [0.38, 0.38], 'BK_Metal_Dark', sides=10,
             smooth=False)
        box2(pb, (x - 0.04 + (0.08 if x > 0 else -0.08), -2.65, dz), (x + 0.04 + (0.08 if x > 0 else -0.08), -2.45, 0.86),
             'BK_Metal_Dark')
    # fish boxes on the aft deck, bitts on the foredeck
    for j, (x, y) in enumerate(((0.5, -1.75), (0.5, -1.75), (-0.45, -1.8))):
        z = dz + (0.26 if j == 1 else 0.0)
        box2(pb, (x - 0.3, y - 0.2, z), (x + 0.3, y + 0.2, z + 0.25), 'BK_Paint_Blue' if j != 1 else 'BK_Paint_Orange',
             fcol=lambda c, n: kcol(0.7 if n.z > 0.5 else 0.95))
    for x in (-0.25, 0.25):
        cyl(pb, (x, 2.0), 0.07, 0.6, 0.95, 'BK_Metal_Dark', sides=6)
    # fenders on both sides
    for sgn in (1, -1):
        for y in (-1.6, 0.9):
            h, g = hw_at(y)
            x = sgn * (h * 0.998 + 0.12)
            cyl(pb, (x, y), 0.12, 0.35, 0.78, 'BK_Buoy_Orange', sides=8, smooth=True)
            tube(pb, [V(x, y, 0.78), V(sgn * (h - 0.03), y, g + 0.02)], [0.012, 0.012], 'BK_Rope', sides=4,
                 smooth=False)
    return pb


@register('Lighthouse')
def lighthouse():
    """25 m lighthouse: tapered round tower, white with red bands, gallery on corbels with railing, polygonal
    lantern room glazed with the emissive "LampLens" material (centred at 0.86 x total height), domed roof."""
    pb = PB('Lighthouse', 503)
    R = pb.R
    z0, zt, r0, r1 = 0.8, 20.2, 3.1, 2.15

    def rr(z):
        return r0 + (r1 - r0) * (z - z0) / (zt - z0)
    cyl(pb, (0, 0), 4.2, -2.5, 0.6, 'BK_Stone_Dark', sides=8, phase=PI / 8, fcol=vary(R, 0.82, 0.9))
    cyl(pb, (0, 0), 3.65, 0.55, 0.85, 'BK_Stone_Light', sides=16, fcol=flat(0.9))
    bands = [z0, 4.6, 7.8, 11.0, 14.2, 17.4, zt]
    rings = [ring_pts((0, 0), rr(z), z, 16) for z in bands]
    loft(pb, rings, 'BK_Lighthouse_White', side_mat=lambda i, j: 'BK_Lighthouse_White' if i % 2 == 0 else
         'BK_Lighthouse_Red', cap0=True, cap1=True, smooth=True, fcol=lambda c, n: kcol(grime(c.z, 0.8, 3.0, 0.88)))
    for (zb, ang) in ((5.6, 70.0), (9.6, 200.0), (13.4, 300.0), (16.8, 110.0)):
        a = math.radians(ang)
        F = FR(0, 0, a, rr(zb) + 0.006)
        window(pb, F, 0.0, zb, 0.5, 0.85, frame='BK_Lighthouse_White', cols=1, rows=2, sill='BK_Stone_Light', fw=0.07,
               depth=0.08)
    Fd = FR(0, 0, PI / 2, rr(0.85) + 0.012)
    door(pb, Fd, 0.0, 0.85, 1.1, 2.2, leaf='BK_Lighthouse_Red', frame='BK_Stone_Light', ground=0.0, panels=2)
    yd = rr(3.3)
    gable_roof(pb, 0.0, yd + 0.3, 'Y', 1.7, 0.95, 3.3, 3.75, oh_e=0.1, oh_g=0.08, t=0.08, mat='BK_Lighthouse_Red',
               under='BK_Lighthouse_White', barge='BK_Lighthouse_White', gutter=None, course=0.18, seg=0.5, seed=531)
    house_body(pb, 0.0, yd + 0.3, 'Y', 1.7, 0.95, 3.12, 3.28, 3.73, 'BK_Lighthouse_White')
    for x in (-0.7, 0.7):
        bracket(pb, x, yd - 0.1, yd + 0.7, 2.7, 3.14, mat='BK_Lighthouse_White', th=0.1)
    # gallery
    cyl(pb, (0, 0), 3.2, zt, zt + 0.25, 'BK_Metal_Dark', sides=16, fcol=flat(0.9))
    for k in range(16):
        a = TAU * (k + 0.5) / 16
        c, s = math.cos(a), math.sin(a)
        t = Vector((-s, c, 0.0)) * 0.08
        pi_ = Vector((c, s, 0)) * (rr(zt - 0.8) - 0.05)
        po = Vector((c, s, 0)) * 3.0
        hexa(pb, [pi_ - t + V(0, 0, zt - 0.8), po - t + V(0, 0, zt - 0.02), po + t + V(0, 0, zt - 0.02),
                  pi_ + t + V(0, 0, zt - 0.8), pi_ - t + V(0, 0, zt + 0.01), po - t + V(0, 0, zt + 0.01),
                  po + t + V(0, 0, zt + 0.01), pi_ + t + V(0, 0, zt + 0.01)], 'BK_Lighthouse_White', fcol=flat(0.9))
        pp = Vector((c, s, 0)) * 3.1
        box2(pb, (pp.x - 0.03, pp.y - 0.03, zt + 0.24), (pp.x + 0.03, pp.y + 0.03, zt + 1.3), 'BK_Metal_Dark')
    for z in (zt + 0.8, zt + 1.3):
        tube(pb, ring_pts((0, 0), 3.1, z, 16), 0.035, 'BK_Metal_Dark', sides=4, smooth=False, closed=True)
    # watch room, lantern, roof
    cyl(pb, (0, 0), 1.85, zt + 0.25, zt + 1.0, 'BK_Lighthouse_Red', sides=16, fcol=flat(0.92))
    zl0, zl1 = zt + 1.0, zt + 3.3
    cyl(pb, (0, 0), 1.65, zl0, zl1, 'LampLens_Lighthouse', sides=10, phase=PI / 10)
    for k in range(10):
        a = PI / 10 + TAU * k / 10
        p = Vector((math.cos(a), math.sin(a), 0)) * 1.66
        box2(pb, (p.x - 0.04, p.y - 0.04, zl0), (p.x + 0.04, p.y + 0.04, zl1), 'BK_Metal_Dark')
    tube(pb, ring_pts((0, 0), 1.62, (zl0 + zl1) / 2, 10, phase=PI / 10), 0.03, 'BK_Metal_Dark', sides=4, smooth=False,
         closed=True)
    prof = [(1.95, zl1 - 0.05), (1.95, zl1 + 0.1), (1.6, zl1 + 0.5), (1.0, zl1 + 1.05), (0.4, zl1 + 1.35),
            (0.12, zl1 + 1.42)]
    loft(pb, [ring_pts((0, 0), r, z, 16) for r, z in prof], 'BK_Lighthouse_Red', cap0=True, cap1=True, smooth=True,
         cap_mats=('BK_Metal_Dark', 'BK_Lighthouse_Red'))
    sphere(pb, (0, 0, zl1 + 1.62), 0.26, 'BK_Metal_Dark', seg=8, rings=5)
    tube(pb, [V(0, 0, zl1 + 1.8), V(0, 0, 26.0)], [0.03, 0.02], 'BK_Metal_Dark', sides=5)
    return pb


# ====================================================================================================== castle
@register('Castle_Ruin_Wall')
def castle_ruin_wall():
    """20 m ruined curtain wall (along X, outer face +Y): coursed stone columns with broken, stepped tops, intact
    crenellated stretches at both ends, a breach in the middle, arrow slits, battered base, rubble and ivy."""
    pb = PB('Castle_Ruin_Wall', 601)
    R = pb.R
    c = 0.5
    base = -2.5
    zs = [base + c * k for k in range(40)]
    y0, y1 = -1.2, 1.2
    xs = [-10.0]
    while xs[-1] < 10.0 - 0.5:
        xs.append(min(10.0, xs[-1] + R.uniform(0.55, 0.95)))
    if xs[-1] < 10.0:
        xs[-1] = 10.0

    def hprof(x):
        if x < -6.6:
            return 7.0
        if x < -2.2:
            return lerp(6.5, 4.0, (x + 6.6) / 4.4)
        if x < 2.6:
            return 1.6 + 1.2 * abs(x - 0.2) / 2.4
        if x < 6.6:
            return lerp(4.0, 6.5, (x - 2.6) / 4.0)
        return 7.0
    kwalk = int(round((7.0 - base) / c))
    tops = []
    for i in range(len(xs) - 1):
        xm = (xs[i] + xs[i + 1]) / 2
        k = int(round((hprof(xm) - base) / c))
        if -6.6 < xm < 6.6:
            k += R.choice((-2, -1, 0, 0, 1, 2))
        k = min(k, kwalk)
        tops.append(k)
    tops[-1] = kwalk + 3       # stub of a former tower junction at the +X end
    segs = [[(0, t)] for t in tops]

    def tint(cc, kk):
        return cc * grime(zs[kk], 0.0, 1.5, 0.8)
    for i in range(len(tops)):
        lo = course_set(segs[i - 1]) if i > 0 else set()
        hi = course_set(segs[i + 1]) if i + 1 < len(tops) else set()
        block_column(pb, [(xs[i], y1), (xs[i + 1], y1), (xs[i + 1], y0), (xs[i], y0)], segs[i], lo, hi, zs,
                     'BK_Stone_Castle', R, tint_fn=tint)
    # parapet with merlons on the intact stretches (outer side)
    for xa, xb in ((-10.0, -6.6), (6.6, xs[-2])):
        px = [xa]
        while px[-1] < xb - 0.3:
            px.append(min(xb, px[-1] + (0.9 if len(px) % 2 == 1 else 0.6)))
        ptops = []
        for j in range(len(px) - 1):
            ptops.append(kwalk + (3 if j % 2 == 0 else 1))
        psegs = [[(kwalk, t)] for t in ptops]
        for j in range(len(ptops)):
            lo = course_set(psegs[j - 1]) if j > 0 else set()
            hi = course_set(psegs[j + 1]) if j + 1 < len(ptops) else set()
            block_column(pb, [(px[j], y1), (px[j + 1], y1), (px[j + 1], 0.55), (px[j], 0.55)], psegs[j], lo, hi, zs,
                         'BK_Stone_Castle', R, base_k=kwalk + 1, tint_fn=tint)
    # battered base on both faces
    for sgn in (1, -1):
        prof = [(sgn * 1.2, -0.6), (sgn * 1.75, -0.6), (sgn * 1.2, 1.0)]
        extrude(pb, prof, lambda u, v, d: V(d, u, v), -10.0, 10.0, 'BK_Stone_Castle',
                fcol=lambda cc, n: kcol(0.78 if n.z > 0.2 else 0.84))
    # arrow slits
    Ff = FY(y1, 1)
    for x in (-8.6, -7.2, 7.4, 8.8):
        fbox(pb, Ff, x - 0.08, x + 0.08, 3.4, 4.6, -0.02, 0.012, 'BK_Shadow')
        fbox(pb, Ff, x - 0.2, x + 0.2, 4.6, 4.75, -0.02, 0.05, 'BK_Stone_Light', fcol=flat(0.8))
    # rubble at the breach and along the foot
    for k in range(16):
        side = 1 if k % 2 == 0 else -1
        x = R.uniform(-3.0, 3.4) if k < 12 else R.uniform(-9.0, 9.0)
        y = side * R.uniform(1.8, 3.6)
        s = (R.uniform(0.45, 0.9), R.uniform(0.35, 0.7), R.uniform(0.28, 0.5))
        if k % 3 == 0:
            blob(pb, (x, y, s[2] * 0.25), (s[0] * 0.6, s[1] * 0.6, s[2] * 0.6), 'BK_Stone_Castle', sub=0, amp=0.25,
                 fcol=lambda cc, n: kcol(R.uniform(0.75, 0.95)))
        else:
            stone_block(pb, (x, y, s[2] * 0.3), s, 'BK_Stone_Castle', R, rot=R.uniform(0, PI), tilt=R.uniform(-0.25, 0.25))
    # loose blocks lying on the broken steps
    for i in range(len(tops)):
        xm = (xs[i] + xs[i + 1]) / 2
        if -6.4 < xm < 6.4 and R.random() < 0.35:
            sz = (R.uniform(0.35, 0.55), R.uniform(0.5, 0.9), R.uniform(0.22, 0.32))
            stone_block(pb, (xm + R.uniform(-0.1, 0.1), R.uniform(-0.5, 0.5), zs[tops[i]] + sz[2] * 0.35), sz,
                        'BK_Stone_Castle', R, rot=R.uniform(-0.3, 0.3), tilt=R.uniform(-0.12, 0.12))
    # ivy: flat clusters climbing the outer face
    for (x, z0_, w, hgt) in ((-5.0, 0.6, 1.6, 3.4), (4.6, 0.6, 1.2, 2.6), (-9.2, 0.8, 1.0, 2.8)):
        for k in range(9):
            t = k / 8
            cx = x + R.uniform(-w / 2, w / 2) * (1.0 - 0.5 * t)
            cz = z0_ + hgt * t + R.uniform(-0.15, 0.15)
            r = R.uniform(0.28, 0.45) * (1.0 - 0.35 * t)
            blob(pb, (cx, y1 + 0.025, cz), (r, 0.07, r * 1.1), 'BK_Ivy', sub=0, amp=0.35, freq=2.2, squash=0.0,
                 fcol=lambda cc, n: kcol(R.uniform(0.62, 0.9)))
    return pb


@register('Castle_Ruin_Tower')
def castle_ruin_tower():
    """15 m ruined round tower: 24 coursed stone sectors, partly collapsed back, crenellated remains, gate passage,
    a window opening, battered skirt, earthen floor and rubble."""
    pb = PB('Castle_Ruin_Tower', 602)
    R = pb.R
    c, base = 0.5, -2.5
    zs = [base + c * k for k in range(45)]
    Ro, Ri, N = 4.4, 3.0, 24
    k0 = int(round((0.0 - base) / c))          # ground course index
    ktop = int(round((13.5 - base) / c))
    tops = []
    for i in range(N):
        a = math.degrees(TAU * (i + 0.5) / N)
        t = ktop
        if 195.0 < a < 300.0:                    # collapsed back-left
            depth = math.sin(math.radians((a - 195.0) / 105.0 * 180.0))
            t = int(round(ktop - depth * 14 + R.choice((-1, 0, 1))))
        elif 175.0 < a < 320.0:
            t = ktop - R.choice((2, 3, 4))
        else:
            t = ktop + (3 if i % 2 == 0 else 0) + R.choice((0, 0, -1))
        tops.append(t)
    segs = []
    kd = int(round((3.0 - base) / c))           # gate lintel
    for i in range(N):
        a = math.degrees(TAU * (i + 0.5) / N)
        if 75.0 < a < 105.0:                     # gate passage at the front (+Y)
            segs.append([(0, k0), (kd, tops[i])])
        elif 165.0 < a < 180.0:                  # window opening (-X side)
            kw0, kw1 = int(round((8.0 - base) / c)), int(round((9.5 - base) / c))
            segs.append([(0, kw0), (kw1, tops[i])])
        else:
            segs.append([(0, tops[i])])

    def tint(cc, kk):
        return cc * grime(zs[kk], 0.0, 1.5, 0.8)
    for i in range(N):
        a0, a1 = TAU * i / N, TAU * (i + 1) / N
        quad = [(Ro * math.cos(a0), Ro * math.sin(a0)), (Ro * math.cos(a1), Ro * math.sin(a1)),
                (Ri * math.cos(a1), Ri * math.sin(a1)), (Ri * math.cos(a0), Ri * math.sin(a0))]
        lo = course_set(segs[(i - 1) % N])
        hi = course_set(segs[(i + 1) % N])
        block_column(pb, quad, segs[i], lo, hi, zs, 'BK_Stone_Castle', R, inner_from=k0, tint_fn=tint)
    # battered skirt (not across the gate)
    for i in range(N):
        a = math.degrees(TAU * (i + 0.5) / N)
        if 75.0 < a < 105.0:
            continue
        a0, a1 = TAU * i / N, TAU * (i + 1) / N
        pts = []
        for (r, z) in ((5.0, -2.5), (5.0, 0.0), (Ro - 0.02, 1.6)):
            pts.append([V(r * math.cos(a0), r * math.sin(a0), z), V(r * math.cos(a1), r * math.sin(a1), z)])
        vs = [pts[0][0], pts[0][1], pts[1][1], pts[1][0], pts[2][1], pts[2][0]]
        pb.add(vs, [(0, 1, 2, 3), (3, 2, 4, 5)], 'BK_Stone_Castle', fcol=lambda cc, n: kcol(0.8 if n.z > 0.2 else 0.86),
               hint=lambda cc: Vector((cc.x, cc.y, 0.6)))
    # floor, slits, rubble, ivy
    cyl(pb, (0, 0), Ri + 0.02, -0.4, 0.12, 'BK_Earth', sides=16, fcol=flat(0.85))
    for ang, z in ((30.0, 5.5), (140.0, 4.0), (330.0, 6.5), (60.0, 10.5)):
        a = math.radians(ang)
        F = FR(0, 0, a, Ro * math.cos(PI / N) + 0.005)
        fbox(pb, F, -0.08, 0.08, z, z + 1.1, -0.02, 0.012, 'BK_Shadow')
    for k in range(16):
        a = math.radians(R.uniform(190.0, 310.0)) if k < 11 else R.uniform(0, TAU)
        r = R.uniform(4.9, 7.2) if k < 13 else R.uniform(0.5, 2.2)
        x, y = r * math.cos(a), r * math.sin(a)
        zb = 0.0 if r > 3.0 else 0.12
        s = (R.uniform(0.45, 0.95), R.uniform(0.35, 0.75), R.uniform(0.28, 0.55))
        if k % 3 == 0:
            blob(pb, (x, y, zb + s[2] * 0.25), (s[0] * 0.6, s[1] * 0.6, s[2] * 0.6), 'BK_Stone_Castle', sub=0,
                 amp=0.25, fcol=lambda cc, n: kcol(R.uniform(0.75, 0.95)))
        else:
            stone_block(pb, (x, y, zb + s[2] * 0.3), s, 'BK_Stone_Castle', R, rot=R.uniform(0, PI),
                        tilt=R.uniform(-0.25, 0.25))
    for ang, z in ((14.0, 2.4), (24.0, 3.6), (19.0, 5.0), (118.0, 1.6), (112.0, 2.7)):
        a = math.radians(ang)
        p = Vector((math.cos(a), math.sin(a), 0)) * (Ro - 0.3)
        blob(pb, (p.x, p.y, z), (0.62, 0.62, 0.8), 'BK_Ivy', sub=1, amp=0.3, freq=1.8, squash=0.0,
             fcol=lambda cc, n: kcol(R.uniform(0.8, 1.05)))
    return pb


# ====================================================================================================== wind turbine
TURBINE = dict(hub_z=70.4, nose_y=4.4, top_z=72.5)


@register('Wind_Turbine_Tower')
def wind_turbine_tower():
    """70 m tubular tower + nacelle (origin at the tower base on its axis). The nacelle nose is the most +Y point
    (y = 4.4) and the aviation light the highest (z = 72.5), so Godot's hub = (0, maxY + 0.6, maxZ - 2.1)
    = (0, 5.0, 70.4) matches Wind_Turbine_Rotor's origin."""
    pb = PB('Wind_Turbine_Tower', 701)
    R = pb.R
    zt, rb, rt = 68.45, 2.15, 1.35

    def rr(z):
        return rb + (rt - rb) * (z - 0.25) / (zt - 0.25)
    cyl(pb, (0, 0), 3.4, -1.5, 0.25, 'BK_Concrete', sides=8, phase=PI / 8, fcol=vary(R, 0.82, 0.9))
    cyl(pb, (0, 0), rb + 0.12, 0.2, 0.55, 'BK_Turbine_White', sides=24, fcol=flat(0.85))
    joints = [0.25, 23.0, 46.0, zt]
    for za, zb in zip(joints[:-1], joints[1:]):
        rings = [ring_pts((0, 0), rr(z), z, 24) for z in (za, zb)]
        loft(pb, rings, 'BK_Turbine_White', cap0=False, cap1=False, smooth=True,
             fcol=lambda c, n: kcol(grime(c.z, 0.0, 3.0, 0.88)))
    for z in joints[1:-1]:
        cyl(pb, (0, 0), rr(z) + 0.05, z - 0.07, z + 0.07, 'BK_Turbine_White', sides=24, fcol=flat(0.88))
    cyl(pb, (0, 0), rt + 0.12, zt - 0.1, 68.75, 'BK_Metal_Dark', sides=24, fcol=flat(0.9))
    # door, platform, stairs
    Fd = FR(0, 0, PI / 2, rr(1.2) + 0.01)
    fbox(pb, Fd, -0.5, 0.5, 1.15, 3.25, -0.04, 0.03, 'BK_Metal_Galv', fcol=flat(0.92))
    ring_frame(pb, Fd, rect2(-0.58, 1.07, 0.58, 3.33), rect2(-0.5, 1.15, 0.5, 3.25), -0.03, 0.07, 'BK_Metal_Dark')
    box2(pb, (-0.9, 1.9, 1.0), (0.9, 3.2, 1.1), 'BK_Metal_Galv', fcol=flat(0.85))
    for x in (-0.8, 0.8):
        box2(pb, (x - 0.04, 3.06, 0.25), (x + 0.04, 3.14, 1.0), 'BK_Metal_Galv')
    for k in range(4):
        x0 = 0.9 + k * 0.32
        ztop = 1.0 - (k + 1) * 0.19
        box2(pb, (x0, 2.05, ztop - 0.05), (x0 + 0.32, 3.05, ztop), 'BK_Metal_Galv', fcol=flat(0.85))
        box2(pb, (x0 + 0.25, 2.05, 0.2), (x0 + 0.32, 2.12, ztop), 'BK_Metal_Galv')
    tube(pb, [V(-0.85, 3.12, 1.1), V(-0.85, 3.12, 2.1), V(0.85, 3.12, 2.1), V(0.85, 3.12, 1.1)], [0.025] * 4,
         'BK_Metal_Galv', sides=5, smooth=False)
    tube(pb, [V(0.88, 3.08, 2.1), V(2.15, 3.08, 1.1), V(2.15, 3.08, 0.3)], [0.025] * 3, 'BK_Metal_Galv', sides=5,
         smooth=False)
    # transformer kiosk
    box2(pb, (-4.6, -2.0, -0.3), (-2.6, -0.6, 0.12), 'BK_Concrete', fcol=flat(0.85))
    box2(pb, (-4.5, -1.9, 0.12), (-2.7, -0.7, 2.3), 'BK_Paint_Green', fcol=vary(R, 0.85, 0.92, 0.0))
    box2(pb, (-4.6, -2.0, 2.3), (-2.6, -0.6, 2.42), 'BK_Metal_Dark', fcol=flat(0.9))
    fbox(pb, FX(-2.7, 1), -1.6, -1.0, 0.2, 2.05, -0.02, 0.02, 'BK_Metal_Dark')
    # nacelle (rounded body lofted along Y)
    zc = TURBINE['hub_z']
    st = [(-5.6, 2.5, 2.7, 0.6), (-5.2, 3.2, 3.3, 0.7), (2.6, 3.5, 3.4, 0.75), (3.8, 3.3, 3.2, 0.75),
          (TURBINE['nose_y'], 2.9, 2.9, 0.7)]
    rings = [[V(x, y, zc + z) for x, z in rrect2(w, h, r, seg=2)] for (y, w, h, r) in st]
    loft(pb, rings, 'BK_Turbine_White', cap0=True, cap1=True,
         fcol=lambda c, n: kcol(0.8 if n.z < -0.6 else (0.95 if n.y < -0.9 else 1.0)))
    for sgn in (1, -1):
        F = FX(sgn * 1.615, sgn)          # nacelle side surface at y = -4.6..-2.8 lies at |x| = 1.61..1.64
        fbox(pb, F, -4.6, -2.8, zc - 0.6, zc + 0.6, -0.06, 0.035, 'BK_Metal_Dark')
        for k in range(5):
            zz = zc - 0.5 + k * 0.25
            fbox(pb, F, -4.55, -2.85, zz, zz + 0.06, 0.02, 0.06, 'BK_Metal_Galv')
    box2(pb, (-0.6, -2.6, zc + 1.6), (0.6, -1.4, zc + 1.8), 'BK_Metal_Galv', fcol=flat(0.9))
    for x in (-0.5, 0.5):
        tube(pb, [V(x, -4.9, zc + 1.6), V(x, -4.9, TURBINE['top_z'] - 0.1)], [0.03, 0.03], 'BK_Metal_Dark', sides=5)
    box2(pb, (-0.58, -4.97, TURBINE['top_z'] - 0.12), (0.58, -4.83, TURBINE['top_z'] - 0.08), 'BK_Metal_Dark')
    box2(pb, (0.42, -4.98, TURBINE['top_z'] - 0.1), (0.58, -4.82, TURBINE['top_z']), 'BK_Beacon_Red')
    box2(pb, (-0.58, -4.98, TURBINE['top_z'] - 0.1), (-0.42, -4.82, TURBINE['top_z'] - 0.01), 'BK_Beacon_Red')
    pb.info['hub_expected'] = (0.0, TURBINE['nose_y'] + 0.6, TURBINE['top_z'] - 2.1)
    return pb


@register('Wind_Turbine_Rotor')
def wind_turbine_rotor():
    """Rotor (separate object): spinner + 3 twisted airfoil blades of 35 m radius in the XZ plane; origin at the
    hub centre, rotation axis Blender Y (Godot Z), front (nose) +Y. Blade tips carry red marking bands."""
    pb = PB('Wind_Turbine_Rotor', 702)
    R = pb.R
    prof = [(-0.6, 1.5), (-0.1, 1.72), (0.8, 1.66), (1.7, 1.25), (2.4, 0.6), (2.75, 0.1)]
    rings = [[V(r * math.cos(TAU * k / 16), y, r * math.sin(TAU * k / 16)) for k in range(16)] for y, r in prof]
    loft(pb, rings, 'BK_Turbine_White', cap0=True, cap1=True, smooth=True)
    foil = [(1.0, 0.0), (0.65, 0.045), (0.4, 0.07), (0.2, 0.075), (0.08, 0.06), (0.02, 0.035), (0.0, 0.0),
            (0.02, -0.02), (0.08, -0.035), (0.2, -0.04), (0.4, -0.035), (0.65, -0.02)]
    circ = []
    for i in range(12):
        th = TAU * i / 12
        circ.append((0.5 + 0.5 * math.cos(th), 0.5 * math.sin(th)))
    secs = [(1.0, 1.5, 1.0, 0.0), (2.2, 1.8, 0.85, 2.0), (4.0, 2.9, 0.45, 12.0), (6.5, 3.2, 0.3, 10.0),
            (10.0, 2.9, 0.22, 7.5), (15.0, 2.4, 0.18, 5.0), (20.0, 1.95, 0.15, 3.5), (25.0, 1.5, 0.13, 2.0),
            (29.0, 1.15, 0.12, 1.0), (31.8, 0.95, 0.12, 0.5), (32.0, 0.94, 0.12, 0.5), (33.4, 0.78, 0.12, 0.2),
            (33.6, 0.75, 0.12, 0.2), (34.6, 0.55, 0.12, 0.0), (35.0, 0.25, 0.12, 0.0)]
    cone = math.tan(math.radians(2.5))
    Y = Vector((0.0, 1.0, 0.0))
    for b in range(3):
        ang = PI / 2 + TAU * b / 3
        er = Vector((math.cos(ang), 0.0, math.sin(ang)))
        et = Y.cross(er).normalized()
        brings = []
        for (rho, chord, tr, tw) in secs:
            twr = math.radians(tw)
            le = (-et * math.cos(twr) + Y * math.sin(twr)).normalized()
            tn = -(le.cross(er)).normalized()
            blend = max(0.0, min(1.0, (tr - 0.3) / 0.7))
            pivot = er * rho + Y * (rho * cone + 0.15)
            ring = []
            for (fx, fy), (cx_, cy_) in zip(foil, circ):
                ax = lerp(fx, cx_, blend)
                ay = lerp(fy * tr / 0.115, cy_, blend)
                ring.append(pivot + le * (0.3 - ax) * chord + tn * ay * chord)
            brings.append(ring)
        red = {i for i, s in enumerate(secs) if 31.9 < s[0] < 33.5 or s[0] > 34.5}
        loft(pb, brings, 'BK_Turbine_White', side_mat=lambda i, j, red=red: 'BK_Lighthouse_Red' if (i in red)
             else 'BK_Turbine_White', cap_mats=('BK_Turbine_White', 'BK_Lighthouse_Red'), smooth=True)
    return pb


# ====================================================================================================== water tower
@register('Water_Tower')
def water_tower():
    """15 m desert water tower: splayed steel legs with struts and tension rods, timber deck with railing, banded
    wooden stave tank, conical metal roof, swing spout, inlet pipe and access ladder."""
    pb = PB('Water_Tower', 801)
    R = pb.R
    zd = 9.6
    leg = lambda sx, sy, z: V(sx * lerp(2.7, 2.05, z / zd), sy * lerp(2.7, 2.05, z / zd), z)
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in corners:
        box2(pb, (sx * 2.7 - 0.45, sy * 2.7 - 0.45, -1.0), (sx * 2.7 + 0.45, sy * 2.7 + 0.45, 0.35), 'BK_Concrete',
             fcol=vary(R, 0.82, 0.9))
        tube(pb, [leg(sx, sy, 0.3), leg(sx, sy, zd)], [0.17, 0.15], 'BK_Metal_Rust', sides=8, smooth=False,
             vfn=lambda i, j, p: kcol(0.9 + 0.1 * i))
    levels = [0.3, 3.4, 6.6, zd - 0.2]
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        for z in levels[1:]:
            tube(pb, [leg(ax, ay, z), leg(bx, by, z)], [0.08, 0.08], 'BK_Metal_Rust', sides=6, smooth=False)
        for za, zb in zip(levels[:-1], levels[1:]):
            tube(pb, [leg(ax, ay, za + 0.1), leg(bx, by, zb - 0.1)], [0.03, 0.03], 'BK_Metal_Dark', sides=4,
                 smooth=False)
            tube(pb, [leg(bx, by, za + 0.1), leg(ax, ay, zb - 0.1)], [0.03, 0.03], 'BK_Metal_Dark', sides=4,
                 smooth=False)
    for (a, b) in (((-2.4, -2.4), (2.4, 2.4)), ((2.4, -2.4), (-2.4, 2.4))):
        beam(pb, (a[0], a[1], zd + 0.1), (b[0], b[1], zd + 0.1), 0.3, 0.3, 'BK_Wood_Dark', fcol=flat(0.8))
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        beam(pb, (ax * 2.25, ay * 2.25, zd + 0.1), (bx * 2.25, by * 2.25, zd + 0.1), 0.25, 0.3, 'BK_Wood_Dark',
             fcol=flat(0.8))
    cyl(pb, (0, 0), 3.75, zd + 0.25, zd + 0.4, 'BK_Wood_Weathered', sides=16,
        fcol=lambda c, n: kcol(0.75 if n.z < -0.5 else R.uniform(0.85, 1.0)))
    for k in range(16):
        a = TAU * k / 16
        p = Vector((math.cos(a), math.sin(a), 0)) * 3.65
        box2(pb, (p.x - 0.04, p.y - 0.04, zd + 0.38), (p.x + 0.04, p.y + 0.04, zd + 1.42), 'BK_Metal_Dark')
    for z in (zd + 0.9, zd + 1.4):
        tube(pb, ring_pts((0, 0), 3.65, z, 16), 0.03, 'BK_Metal_Dark', sides=4, smooth=False, closed=True)
    # tank: wooden staves + proud steel hoops
    zt0, zt1, Rt = zd + 0.4, 13.5, 3.0
    hoops = [zt0 + 0.5, 11.2, 12.1, 12.95]
    zl = [zt0]
    radii = [Rt]
    for h in hoops:
        zl += [h - 0.05, h - 0.05, h + 0.05, h + 0.05]
        radii += [Rt, Rt + 0.035, Rt + 0.035, Rt]
    zl.append(zt1)
    radii.append(Rt)
    rings = [ring_pts((0, 0), r, z, 24) for r, z in zip(radii, zl)]
    loft(pb, rings, 'BK_Wood_Weathered', cap0=True, cap1=False,
         side_mat=lambda i, j: 'BK_Metal_Dark' if max(radii[i], radii[i + 1]) > Rt + 0.01 else 'BK_Wood_Weathered',
         fcol=lambda c, n: kcol((0.88 if int((math.atan2(c.y, c.x) + PI) / TAU * 24) % 2 else 1.0) *
                                R.uniform(0.9, 1.02)))
    roof = [(Rt, zt1), (3.32, zt1 - 0.02), (3.32, zt1 + 0.1), (0.14, 14.72)]
    loft(pb, [ring_pts((0, 0), r, z, 16) for r, z in roof], 'BK_Roof_Metal', cap0=True, cap1=True,
         fcol=lambda c, n: kcol(0.75 if n.z < -0.3 else 0.95))
    cyl(pb, (0, 0), 0.16, 14.7, 14.86, 'BK_Metal_Dark', sides=8)
    sphere(pb, (0, 0, 14.9), 0.11, 'BK_Metal_Dark', seg=8, rings=4)
    # swing spout with hinge, inlet pipe, ladder
    box2(pb, (2.9, -0.2, 11.1), (3.25, 0.2, 11.55), 'BK_Metal_Dark')
    tube(pb, [V(3.15, 0.0, 11.3), V(4.0, 0.0, 10.7), V(4.45, 0.0, 9.6)], [0.17, 0.17, 0.16], 'BK_Metal_Rust', sides=8,
         smooth=False)
    tube(pb, [V(4.0, 0.0, 10.8), V(4.0, 0.0, 12.6), V(3.25, 0.0, 13.0)], [0.012] * 3, 'BK_Metal_Dark', sides=4,
         smooth=False)
    cyl(pb, (0, 0), 0.22, -0.3, zd + 0.3, 'BK_Metal_Rust', sides=8)
    box2(pb, (-0.5, -0.5, -0.3), (0.5, 0.5, 0.15), 'BK_Concrete', fcol=flat(0.85))
    for x in (-0.25, 0.25):
        tube(pb, [V(x, -3.82, -0.1), V(x, -3.82, zd + 1.45)], [0.03, 0.03], 'BK_Metal_Dark', sides=5, smooth=False)
    for k in range(32):
        z = 0.25 + k * 0.33
        tube(pb, [V(-0.25, -3.82, z), V(0.25, -3.82, z)], [0.02, 0.02], 'BK_Metal_Dark', sides=4, smooth=False)
    for z in (3.4, 6.6):
        beam(pb, (0.0, -3.8, z), (0.0, -2.0, z), 0.06, 0.06, 'BK_Metal_Dark')
    box2(pb, (-0.35, -3.95, -0.3), (0.35, -3.65, 0.0), 'BK_Concrete', fcol=flat(0.85))
    return pb


# ====================================================================================================== festival
@register('Festival_Stage')
def festival_stage():
    """Open-air concert stage, 20 m wide (front +Y = audience): black deck with LED lip, four truss towers, truss
    roof grid under an arched membrane, LED backdrop, line arrays, subs, moving heads and par cans, back stairs."""
    pb = PB('Festival_Stage', 901)
    R = pb.R
    zd = 1.6
    box2(pb, (-10.0, -6.0, -1.5), (10.0, 6.0, zd - 0.06), 'BK_Fabric_Dark', fcol=lambda c, n: kcol(0.9))
    box2(pb, (-10.02, -6.02, zd - 0.06), (10.02, 6.02, zd), 'BK_Black', fcol=flat(0.9))
    box2(pb, (-10.0, 6.0, zd - 0.16), (10.0, 6.06, zd - 0.06), 'BK_LED_Gold')
    tx, ty, zr = 9.55, 5.55, 12.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            box2(pb, (sx * tx - 0.4, sy * ty - 0.4, zd), (sx * tx + 0.4, sy * ty + 0.4, zd + 0.08), 'BK_Metal_Dark')
            truss(pb, (sx * tx, sy * ty, zd + 0.08), (sx * tx, sy * ty, zr - 0.25), w=0.45, h=0.45, step=0.95,
                  faces=('L', 'R', 'B', 'T'))
            box2(pb, (sx * tx - 0.32, sy * ty - 0.32, zr - 0.3), (sx * tx + 0.32, sy * ty + 0.32, zr + 0.3),
                 'BK_Metal_Dark', fcol=flat(0.9))
    for y in (-ty, 0.0, ty):
        truss(pb, (-tx + 0.32, y, zr), (tx - 0.32, y, zr), w=0.45, h=0.45, step=0.95, faces=('L', 'R', 'B'))
    for x in (-tx, tx):
        truss(pb, (x, -ty + 0.32, zr), (x, ty - 0.32, zr), w=0.45, h=0.45, step=0.95, faces=('L', 'R', 'B'))
    for x in (-tx, tx):
        box2(pb, (x - 0.3, -0.3, zr - 0.28), (x + 0.3, 0.3, zr + 0.28), 'BK_Metal_Dark', fcol=flat(0.9))
    # arched roof membrane resting on the grid
    zt_ = zr + 0.255                       # top of the truss top chords

    def under(y):
        if abs(y) <= ty:
            return zt_ + 1.6 * (1.0 - (y / ty) ** 2)
        return zt_ - 0.3 * (abs(y) - ty) / 0.8
    ys_ = [-ty - 0.8] + [lerp(-ty, ty, k / 12) for k in range(13)] + [ty + 0.8]
    poly = [(y, under(y) + 0.14) for y in ys_] + [(y, under(y)) for y in reversed(ys_)]
    extrude(pb, poly, lambda u, v, d: V(d, u, v), -10.35, 10.35, 'BK_Fabric_Dark',
            fcol=lambda c, n: kcol(0.7 if n.z < -0.3 else 0.95))
    for x in (-tx, 0.0, tx):
        tube(pb, [V(x, y, under(y) - 0.06) for y in ys_[1:-1]], [0.06] * 13, 'BK_Alu', sides=6, smooth=False)
        tube(pb, [V(x, 0.0, zt_ - 0.02), V(x, 0.0, under(0.0) - 0.06)], [0.05, 0.05], 'BK_Alu', sides=6,
             smooth=False)
        for yy in (-ty * 0.5, ty * 0.5):
            tube(pb, [V(x, yy, zt_ - 0.02), V(x, yy, under(yy) - 0.06)], [0.04, 0.04], 'BK_Alu', sides=6,
                 smooth=False)
    # LED backdrop
    box2(pb, (-7.5, -5.65, zd), (7.5, -5.3, 9.9), 'BK_Black', fcol=flat(0.9))
    Fb = FY(-5.3, 1)
    for (z0, z1, m) in ((2.0, 4.6, 'BK_LED_Gold'), (4.6, 7.2, 'BK_LED_Magenta'), (7.2, 9.7, 'BK_LED_Violet')):
        for i in range(8):
            x0 = -7.3 + i * 1.825
            fbox(pb, Fb, x0 + 0.02, x0 + 1.805, z0 + 0.02, z1 - 0.02, -0.02, 0.03, m)
    # line arrays hanging from the front truss
    for sx in (-1, 1):
        x = sx * 8.25
        zb = zr - 0.225
        box2(pb, (x - 0.7, ty - 0.45, zb - 0.12), (x + 0.7, ty + 0.45, zb), 'BK_Metal_Dark')
        z = zb - 0.12
        for k in range(8):
            ang = math.radians(1.5 + k * 1.8)
            hgt = 0.36
            c = V(x, ty + 0.02 * k * k * 0.25, z - hgt / 2)
            box(pb, c, (1.25, 0.72, hgt), 'BK_Black', rot=rot_x(-ang), fcol=lambda cc, n: kcol(0.75 if n.y > 0.8 else 0.95))
            z -= hgt * math.cos(ang) - 0.004
        tube(pb, [V(x - 0.55, ty, zb - 0.12), V(x - 0.55, ty, z + 0.2)], [0.012, 0.012], 'BK_Metal_Dark', sides=4,
             smooth=False)
        for j in range(2):
            box2(pb, (x * 0.92 - 0.65, 6.25, 0.6 * j), (x * 0.92 + 0.65, 7.1, 0.6 * j + 0.58), 'BK_Black',
                 fcol=lambda cc, n: kcol(0.7 if n.y > 0.8 else 0.95))
    # moving heads under the front truss, par cans on the mid truss and the front towers
    zb = zr - 0.225
    yh = ty + 0.225                         # front bottom chord of the front truss
    for x in (-6.0, -3.6, -1.2, 1.2, 3.6, 6.0):
        box2(pb, (x - 0.06, yh - 0.06, zb - 0.1), (x + 0.06, yh + 0.06, zb + 0.02), 'BK_Metal_Dark')
        box2(pb, (x - 0.22, yh - 0.18, zb - 0.26), (x + 0.22, yh + 0.18, zb - 0.1), 'BK_Black')
        for dx in (-0.2, 0.2):
            box2(pb, (x + dx - 0.03, yh - 0.08, zb - 0.64), (x + dx + 0.03, yh + 0.08, zb - 0.26), 'BK_Black')
        tube(pb, [V(x - 0.17, yh - 0.02, zb - 0.59), V(x + 0.17, yh - 0.02, zb - 0.59)], [0.17, 0.17], 'BK_Black',
             sides=8, smooth=True)
        tube(pb, [V(x, yh + 0.05, zb - 0.59), V(x, yh + 0.2, zb - 0.66)], [0.11, 0.12], 'BK_Black', sides=8,
             smooth=False, cap_mat='BK_StageLens')
    for x in (-7.0, -4.2, -1.4, 1.4, 4.2, 7.0):
        box2(pb, (x - 0.05, 0.175, zb - 0.1), (x + 0.05, 0.275, zb + 0.02), 'BK_Metal_Dark')
        tube(pb, [V(x, 0.225, zb - 0.1), V(x, 0.4, zb - 0.45)], [0.13, 0.13], 'BK_Black', sides=8, smooth=False,
             cap_mat='BK_StageLens')
    for sx in (-1, 1):
        for z in (4.5, 6.5, 8.5):
            x = sx * (tx - 0.26)
            tube(pb, [V(x, ty + 0.05, z), V(x - sx * 0.3, ty + 0.15, z - 0.1)], [0.12, 0.12], 'BK_Black', sides=8,
                 smooth=False, cap_mat='BK_StageLens')
    # monitor wedges, drum riser, back stairs with handrail
    for x in (-4.5, -1.5, 1.5, 4.5):
        a = 0.5
        box(pb, (x, 5.3, zd + 0.275 * math.sin(a) + 0.16 * math.cos(a)), (0.7, 0.55, 0.32), 'BK_Black', rot=rot_x(a),
            fcol=lambda cc, n: kcol(0.7 if n.z > 0.5 else 0.92))
    box2(pb, (-2.0, -4.6, zd), (2.0, -2.6, zd + 0.42), 'BK_Fabric_Dark', fcol=flat(0.85))
    for k in range(8):
        zt_ = zd - (k + 1) * 0.2
        box2(pb, (6.4, -6.0 - (k + 1) * 0.28, -0.4), (7.7, -6.0 - k * 0.28, zt_ + 0.2), 'BK_Metal_Galv',
             fcol=flat(0.85))
    for x in (6.42, 7.68):
        tube(pb, [V(x, -6.0, zd + 1.0), V(x, -8.24, 0.95), V(x, -8.3, -0.05)], [0.025] * 3, 'BK_Metal_Galv', sides=5,
             smooth=False)
        tube(pb, [V(x, -6.0, zd), V(x, -6.0, zd + 1.0)], [0.025, 0.025], 'BK_Metal_Galv', sides=5, smooth=False)
    return pb


@register('Festival_Tent')
def festival_tent():
    """Peaked festival marquee, 8 x 8 m: striped concave peak roof on aluminium poles, scalloped valance, closed
    walls with clear panels at the back and sides, open front with tied-back curtains, guy ropes, a bar counter."""
    pb = PB('Festival_Tent', 902)
    R = pb.R
    h, ze = 4.0, 2.6
    for (x, y) in ((-h, -h), (0, -h), (h, -h), (h, 0), (h, h), (0, h), (-h, h), (-h, 0)):
        tube(pb, [V(x, y, -0.05), V(x, y, ze + 0.05)], [0.05, 0.05], 'BK_Alu', sides=6, smooth=False)
        box2(pb, (x - 0.12, y - 0.12, -0.02), (x + 0.12, y + 0.12, 0.03), 'BK_Metal_Dark')
    tube(pb, [V(0, 0, -0.05), V(0, 0, 6.0)], [0.08, 0.06], 'BK_Alu', sides=6, smooth=False)
    prof = [(h + 0.06, ze - 0.02), (h + 0.06, ze), (2.7, 3.25), (1.6, 4.0), (0.75, 4.9), (0.22, 5.75), (0.05, 6.0)]
    outer = [square_ring(r, z, 4) for r, z in prof]
    inner = [square_ring(r - 0.04, z - 0.07, 4) for r, z in prof[1:]]
    stripe = lambda i, j: 'BK_Canvas_Red' if j % 2 == 0 else 'BK_Canvas_White'
    sheet(pb, outer, 'BK_Canvas_White', hint_fn=lambda c: Vector((c.x, c.y, 2.5)), side_mat=stripe,
          fcol=lambda c, n: kcol(0.97))
    sheet(pb, inner, 'BK_Canvas_White', hint_fn=lambda c: Vector((-c.x, -c.y, -2.5)), fcol=lambda c, n: kcol(0.8))
    sheet(pb, [outer[0], inner[0]], 'BK_Canvas_White', hint_fn=lambda c: Vector((0, 0, -1)), fcol=flat(0.85))
    tube(pb, [V(0, 0, 5.9), V(0, 0, 6.75)], [0.03, 0.02], 'BK_Alu', sides=5, smooth=False)
    fprism(pb, Frame((0, 0, 0), (0, 1, 0), (1, 0, 0)), [(0.02, 6.35), (0.6, 6.5), (0.02, 6.66)], -0.01, 0.01,
           'BK_Canvas_Red')
    # walls (back + sides), clear panels, valance
    walls = [(FY(-h, -1), 0.0), (FX(h, 1), 0.0), (FX(-h, -1), 0.0)]
    for F, c in walls:
        fbox(pb, F, c - h, c + h, 0.02, ze - 0.12, -0.03, 0.0, 'BK_Canvas_White', fcol=vary(R, 0.92, 0.98))
        for dx in (-1.9, 1.9):
            fbox(pb, F, c + dx - 0.7, c + dx + 0.7, 0.9, 1.9, 0.0, 0.01, 'BK_Tent_Window')
    for F in (FY(h + 0.07, 1), FY(-h - 0.07, -1), FX(h + 0.07, 1), FX(-h - 0.07, -1)):
        pts = [(-h - 0.07, ze + 0.02)]
        n = 8
        for i in range(n + 1):
            x = -h - 0.07 + (2 * h + 0.14) * i / n
            pts.append((x, ze - 0.28))
            if i < n:
                pts.append((x + (2 * h + 0.14) / n / 2, ze - 0.42))
        pts.append((h + 0.07, ze + 0.02))
        fprism(pb, F, pts, -0.03, 0.0, 'BK_Canvas_Red', fcol=flat(0.95))
    # tied-back curtains at the open front
    for x in (-h + 0.35, h - 0.35):
        tube(pb, [V(x, h - 0.05, 0.5), V(x * 0.98, h - 0.05, 1.4), V(x, h - 0.05, ze - 0.05)], [0.13, 0.17, 0.28],
             'BK_Canvas_White', sides=8, smooth=True)
        tube(pb, [V(x - 0.15, h - 0.05, 1.4), V(x + 0.15, h - 0.05, 1.4)], [0.025, 0.025], 'BK_Canvas_Red', sides=5)
    # guy ropes + pegs
    for (x, y) in ((-h, -h), (h, -h), (h, h), (-h, h), (0, -h), (h, 0), (0, h), (-h, 0)):
        d = Vector((x, y, 0.0)).normalized()
        g = V(x, y, ze) + d * 1.4
        g.z = 0.0
        tube(pb, [V(x, y, ze - 0.02) + d * 0.05, g + V(0, 0, 0.05)], [0.012, 0.012], 'BK_Rope', sides=4, smooth=False)
        box2(pb, (g.x - 0.03, g.y - 0.03, -0.15), (g.x + 0.03, g.y + 0.03, 0.08), 'BK_Metal_Dark')
    # bar counter at the back
    box2(pb, (-1.8, -h + 0.5, 0.0), (1.8, -h + 1.1, 1.0), 'BK_Wood_Light', fcol=vary(R, 0.85, 0.95))
    box2(pb, (-1.9, -h + 0.45, 1.0), (1.9, -h + 1.2, 1.06), 'BK_Wood_Dark', fcol=flat(0.9))
    return pb


@register('Viewpoint_Deck')
def viewpoint_deck():
    """Wooden viewing platform, 6 x 4 m (view side +Y, open access side -Y towards the road): posts reaching 4 m
    down the slope, bearers, joists, boards (deck top 0.42 m above the origin), railing with balusters, a coin
    binocular viewer and a blank information board."""
    pb = PB('Viewpoint_Deck', 903)
    R = pb.R
    W, D, zt = 6.0, 4.0, 0.42
    for x in (-2.8, 0.0, 2.8):
        for y in (-1.8, 1.8):
            box2(pb, (x - 0.1, y - 0.1, -4.0), (x + 0.1, y + 0.1, 0.07), 'BK_Wood_Dark', fcol=flat(0.75))
        beam(pb, (x, -1.7, -1.2), (x, 1.7, -2.6), 0.14, 0.08, 'BK_Wood_Dark', up=(1, 0, 0), fcol=flat(0.7))
    for y in (-1.8, 1.8):
        box2(pb, (-W / 2, y - 0.1, 0.06), (W / 2, y + 0.1, 0.26), 'BK_Wood_Dark', fcol=flat(0.8))
        for xa, xb in ((-2.8, 0.0), (0.0, 2.8)):
            beam(pb, (xa + 0.1, y, -1.0), (xb - 0.1, y, 0.0), 0.14, 0.08, 'BK_Wood_Dark', up=(0, 1, 0), fcol=flat(0.7))
    for k in range(11):
        x = -2.85 + 5.7 * k / 10
        box2(pb, (x - 0.04, -D / 2, 0.26), (x + 0.04, D / 2, 0.36), 'BK_Wood_Mid', fcol=flat(0.75))
    nb = 26
    for k in range(nb):
        y0 = -D / 2 + k * D / nb + 0.01
        box2(pb, (-W / 2, y0, 0.36), (W / 2, y0 + D / nb - 0.02, zt - R.uniform(0.0, 0.005)), 'BK_Deck_Wood',
             fcol=kcol(R.uniform(0.78, 1.0)))
    railing(pb, [(-W / 2 + 0.06, -D / 2 + 0.06), (-W / 2 + 0.06, D / 2 - 0.06), (W / 2 - 0.06, D / 2 - 0.06),
                 (W / 2 - 0.06, -D / 2 + 0.06)], zt, h=1.05, post_mat='BK_Wood_Dark', rail_mat='BK_Wood_Mid',
            bal_mat='BK_Wood_Mid', post_every=1.5, bal=0.17, bal_w=0.045, rail_w=0.13, rail_h=0.05)
    # binocular viewer
    box2(pb, (-0.18, 1.42, zt), (0.18, 1.78, zt + 0.04), 'BK_Metal_Dark')
    tube(pb, [V(0, 1.6, zt + 0.04), V(0, 1.6, zt + 1.05)], [0.07, 0.06], 'BK_Metal_Dark', sides=8, smooth=False)
    box2(pb, (-0.2, 1.48, zt + 1.05), (0.2, 1.75, zt + 1.3), 'BK_Paint_Teal', fcol=flat(0.95))
    for x in (-0.1, 0.1):
        tube(pb, [V(x, 1.75, zt + 1.2), V(x, 1.92, zt + 1.22)], [0.06, 0.07], 'BK_Paint_Teal', sides=8, smooth=False,
             cap_mat='BK_Black')
        tube(pb, [V(x, 1.48, zt + 1.2), V(x, 1.38, zt + 1.2)], [0.035, 0.035], 'BK_Black', sides=6, smooth=False)
    # information board (blank) at the access side
    for x in (2.0, 2.9):
        box2(pb, (x - 0.04, -1.75, zt), (x + 0.04, -1.67, zt + 1.05), 'BK_Wood_Dark')
    hexa(pb, [V(2.0, -1.7, zt + 0.95), V(2.9, -1.7, zt + 0.95), V(2.9, -1.5, zt + 1.5), V(2.0, -1.5, zt + 1.5),
              V(2.0, -1.76, zt + 0.97), V(2.9, -1.76, zt + 0.97), V(2.9, -1.56, zt + 1.52), V(2.0, -1.56, zt + 1.52)],
         'BK_Wood_Mid', fcol=flat(0.85))
    hexa(pb, [V(2.06, -1.68, zt + 1.0), V(2.84, -1.68, zt + 1.0), V(2.84, -1.5, zt + 1.46), V(2.06, -1.5, zt + 1.46),
              V(2.06, -1.71, zt + 1.0), V(2.84, -1.71, zt + 1.0), V(2.84, -1.53, zt + 1.46), V(2.06, -1.53, zt + 1.46)],
         'BK_Paint_Cream', fcol=flat(0.95))
    return pb
