"""Sunward Roads buildings kit - part 1: houses, farm buildings, commercial, church, harbour buildings.

Exec'd into the namespace of tools/blender/props/buildings_kit.py (uses its helpers and `register`).
All dimensions in metres; Blender +Y is the front (door side); origin at the base centre on the ground.
"""

MATS.update({
    'BK_Cladding_Teal': dict(c=(96, 138, 146), r=0.5, m=0.3),
    'BK_Skylight': dict(c=(214, 222, 220), r=0.3),
    'BK_Concrete_Stave': dict(c=(196, 178, 150), r=0.88),
})


def gutter_at(span, eave, ridge, oh_e, side=1):
    """(across, z) of the gutter centre of gable_roof()'s slab on `side`."""
    sl = (ridge - eave) / (span / 2.0)
    A = (side * (span / 2 + oh_e), eave - oh_e * sl)
    B = (0.0, ridge)
    L, d, n = slab_frame(A, B)
    q = Vector(B) - d * (L + 0.105) + n * (-0.08)
    return q.x, q.y


def slab_point(A, B, u, h):
    L, d, n = slab_frame(A, B)
    q = Vector(B) - d * u + n * h
    return q.x, q.y, L


def bracket(pb, x, y0, y1, z0, z1, mat='BK_Wood_Dark', th=0.08, ny=1):
    """Triangular timber bracket in the YZ plane at world x: from the wall (y0) at z0..z1 out to y1 at z1."""
    F = Frame((x, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0))
    fprism(pb, F, [(y0, z0), (y0, z1), (y1, z1)], -th / 2, th / 2, mat, fcol=flat(0.9))


def bracket_x(pb, y, x0, x1, z0, z1, mat='BK_Wood_Dark', th=0.08):
    """Triangular bracket in the XZ plane at world y: from the wall (x0) at z0..z1 out to x1 at z1."""
    F = Frame((0.0, y, 0.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0))
    fprism(pb, F, [(x0, z0), (x0, z1), (x1, z1)], -th / 2, th / 2, mat, fcol=flat(0.9))


def braced_leaf(pb, F, x0, x1, z0, z1, leaf, trim, t=0.0, bw=0.16, xb=True, k=0.85):
    """Barn-style door leaf: board leaf + trim frame + X (or Z) brace, on frame F starting at t."""
    fbox(pb, F, x0, x1, z0, z1, t - 0.06, t + 0.04, leaf, fcol=flat(k))
    for (a0, a1, b0, b1) in ((x0, x1, z0, z0 + bw), (x0, x1, z1 - bw, z1), (x0, x0 + bw, z0, z1), (x1 - bw, x1, z0, z1)):
        fbox(pb, F, a0, a1, b0, b1, t + 0.03, t + 0.08, trim, fcol=flat(0.96))
    c = [(x0 + bw / 2, z0 + bw / 2), (x1 - bw / 2, z1 - bw / 2)]
    d = [(x1 - bw / 2, z0 + bw / 2), (x0 + bw / 2, z1 - bw / 2)]
    for (pa, pb_) in ([c, d] if xb else [c]):
        beam(pb, F.p(pa[0], pa[1], t + 0.055), F.p(pb_[0], pb_[1], t + 0.055), bw * 0.9, 0.05, trim,
             up=tuple(F.N), fcol=flat(0.96))


def gooseneck_lamp(pb, F, x, z, reach=0.6):
    """Wall lamp: arm out from the wall and a conical shade with a warm lens underneath."""
    a = F.p(x, z, 0.0)
    b = F.p(x, z + 0.25, reach * 0.6)
    c = F.p(x, z + 0.18, reach)
    tube(pb, [a - F.N * 0.02, b, c], [0.03, 0.03, 0.03], 'BK_Metal_Dark', sides=5, smooth=False)
    cyl(pb, (c.x, c.y, 0), 0.08, c.z - 0.05, c.z + 0.04, 'BK_Metal_Dark', sides=8, r1=0.05)
    cyl(pb, (c.x, c.y, 0), 0.22, c.z - 0.16, c.z - 0.04, 'BK_Metal_Dark', sides=10, r1=0.08)
    cyl(pb, (c.x, c.y, 0), 0.19, c.z - 0.17, c.z - 0.13, 'BK_LampWarm', sides=10)


# ====================================================================================================== houses
@register('House_Cottage_A')
def house_cottage_a():
    """1.5 storey plaster cottage: terracotta tiles, wall dormer, external stone chimney, shutters + flower boxes."""
    pb = PB('House_Cottage_A', 101)
    R = pb.R
    W, D = 9.0, 6.4
    z0, eave, ridge = 0.45, 3.7, 7.1
    oh_e, oh_g = 0.5, 0.28
    foundation(pb, -W / 2 - 0.12, W / 2 + 0.12, -D / 2 - 0.12, D / 2 + 0.12, top=z0)
    house_body(pb, 0, 0, 'X', D, W, z0, eave - 0.02, ridge - 0.02, 'BK_Plaster_Cream')
    quoins(pb, -W / 2, W / 2, -D / 2, D / 2, z0, eave - 0.06, 'BK_Stone_Light')
    gable_roof(pb, 0, 0, 'X', D, W, eave, ridge, oh_e=oh_e, oh_g=oh_g, mat='BK_Roof_Tile', barge='BK_Wood_Dark',
               gutter='BK_Metal_Dark', course=0.34, seg=1.3, seed=11)
    # wall dormer above the door (front flush with the front wall)
    house_body(pb, 0, 1.9, 'Y', 2.2, 2.6, 3.45, 5.08, 6.13, 'BK_Plaster_Cream')
    gable_roof(pb, 0, 1.9, 'Y', 2.2, 2.6, 5.1, 6.15, oh_e=0.2, oh_g=0.25, t=0.12, mat='BK_Roof_Tile',
               barge='BK_Wood_Dark', gutter=None, course=0.3, seg=0.9, seed=12)
    Ff = FY(D / 2, 1)
    window(pb, Ff, 0.0, 4.02, 0.9, 0.82, cols=2, rows=1, sill='BK_Trim_White')
    # front
    door(pb, Ff, 0.0, z0, 1.0, 2.1, leaf='BK_Paint_Green', frame='BK_Trim_White', ground=0.0)
    box2(pb, (-0.85, D / 2, 2.74), (0.85, D / 2 + 0.62, 2.86), 'BK_Wood_Dark', fcol=flat(0.9))
    for x in (-0.72, 0.72):
        bracket(pb, x, D / 2, D / 2 + 0.5, 2.3, 2.74)
    for x in (-2.6, 2.6):
        window(pb, Ff, x, 1.25, 1.1, 1.3, shutters='BK_Paint_Green', flower=('BK_Blossom_Red', 'BK_Blossom_Pink'))
    # gables: +X has the external chimney in the middle
    Fe = FX(W / 2, 1)
    window(pb, Fe, -1.7, 1.3, 1.0, 1.2)
    window(pb, Fe, 1.45, 4.25, 0.75, 0.85, cols=1, rows=2)
    Fw = FX(-W / 2, -1)
    for y in (-1.4, 1.4):
        window(pb, Fw, y, 1.3, 1.0, 1.2)
    window(pb, Fw, 0.0, 4.3, 0.8, 0.9, cols=2, rows=2)
    # external stone chimney on the +X gable
    box2(pb, (W / 2 - 0.1, -0.56, -0.4), (W / 2 + 0.68, 0.56, 4.3), 'BK_Stone_Wall', fcol=vary(R, 0.8, 1.0, 0.0))
    hexa(pb, [V(W / 2 - 0.1, -0.56, 4.3), V(W / 2 + 0.68, -0.56, 4.3), V(W / 2 + 0.68, 0.56, 4.3),
              V(W / 2 - 0.1, 0.56, 4.3), V(W / 2 - 0.1, -0.4, 4.85), V(W / 2 + 0.5, -0.4, 4.85),
              V(W / 2 + 0.5, 0.4, 4.85), V(W / 2 - 0.1, 0.4, 4.85)], 'BK_Stone_Light', fcol=flat(0.9))
    chimney(pb, W / 2 + 0.2, 0.0, 4.8, 8.15, sx=0.6, sy=0.8, mat='BK_Stone_Wall', cap='BK_Stone_Light', pots=2)
    # back
    Fb = FY(-D / 2, -1)
    for x in (-2.4, 2.4):
        window(pb, Fb, x, 1.3, 1.0, 1.2)
    window(pb, Fb, 0.0, 1.75, 0.55, 0.75, cols=1, rows=1)
    # downpipes at the front corners
    ga, gz = gutter_at(D, eave, ridge, oh_e, 1)
    for x in (-W / 2 + 0.25, W / 2 - 0.25):
        downpipe(pb, (x, ga, gz), ((x, D / 2, gz), (0, 1, 0)))
    ga, gz = gutter_at(D, eave, ridge, oh_e, -1)
    downpipe(pb, (-W / 2 + 0.25, ga, gz), ((-W / 2 + 0.25, -D / 2, gz), (0, -1, 0)))
    return pb


@register('House_Cottage_B')
def house_cottage_b():
    """Two storey stone cottage: slate roof, gable chimneys, lean-to porch and a whitewashed lean-to extension."""
    pb = PB('House_Cottage_B', 102)
    R = pb.R
    W, D = 9.8, 7.0
    z0, eave, ridge = 0.3, 5.7, 8.8
    oh_e, oh_g = 0.35, 0.18
    foundation(pb, -W / 2 - 0.1, W / 2 + 0.1, -D / 2 - 0.1, D / 2 + 0.1, top=z0)
    wall_set(pb, -W / 2, W / 2, -D / 2, D / 2, z0, eave, ridge, 'X', 'BK_Stone_Wall', 'stone', course=0.4,
             blk=(0.45, 0.95))
    gable_roof(pb, 0, 0, 'X', D, W, eave, ridge, oh_e=oh_e, oh_g=oh_g, mat='BK_Roof_Slate', barge='BK_Wood_Dark',
               gutter='BK_Metal_Dark', course=0.3, step=0.025, seg=0.95, vary_amp=0.15, seed=21)
    for x in (-W / 2 + 0.45, W / 2 - 0.45):
        chimney(pb, x, 0.0, ridge - 1.0, ridge + 1.25, sx=0.9, sy=0.72, mat='BK_Stone_Wall', cap='BK_Stone_Light',
                pots=2)
    Ff = FY(D / 2, 1)
    for x in (-3.5, 1.4, 3.5):
        window(pb, Ff, x, 1.0, 1.0, 1.25, lintel='BK_Stone_Light', frame='BK_Trim_White')
    for x, w in ((-3.5, 0.95), (-1.3, 0.75), (1.4, 0.95), (3.5, 0.95)):
        window(pb, Ff, x, 3.65, w, 1.1, lintel='BK_Stone_Light', frame='BK_Trim_White')
    door(pb, Ff, -1.3, z0, 1.0, 2.1, leaf='BK_Paint_Red', frame='BK_Wood_Dark', ground=0.0)
    # lean-to porch over the door
    roof_slab(pb, 0.0, 0.0, 'X', (D / 2 + 1.45, 2.78), (D / 2 - 0.02, 3.22), -2.55, -0.05, t=0.1, mat='BK_Roof_Slate',
              under='BK_Wood_Dark', course=0.28, step=0.022, seg=0.9, barge='BK_Wood_Dark', fascia='BK_Wood_Dark',
              seed=22)
    for x in (-2.4, -0.2):
        box2(pb, (x - 0.07, D / 2 + 1.18, 0.0), (x + 0.07, D / 2 + 1.32, 2.72), 'BK_Wood_Dark', fcol=flat(0.9))
        box2(pb, (x - 0.15, D / 2 + 1.1, -0.1), (x + 0.15, D / 2 + 1.4, 0.06), 'BK_Stone_Dark', fcol=flat(0.9))
    beam(pb, (-2.5, D / 2 + 1.25, 2.72), (-0.1, D / 2 + 1.25, 2.72), 0.14, 0.14, 'BK_Wood_Dark', fcol=flat(0.85))
    # gables
    Fe = FX(W / 2, 1)
    window(pb, Fe, 1.2, 1.0, 0.95, 1.2, lintel='BK_Stone_Light')
    window(pb, Fe, -1.1, 3.65, 0.9, 1.1, lintel='BK_Stone_Light')
    window(pb, Fe, 0.0, 6.2, 0.6, 0.7, cols=1, rows=1)
    Fw = FX(-W / 2, -1)
    window(pb, Fw, 0.4, 4.5, 0.8, 0.9, lintel='BK_Stone_Light')
    # back
    Fb = FY(-D / 2, -1)
    for x in (-2.4, 1.0):
        window(pb, Fb, x, 1.0, 1.0, 1.2, lintel='BK_Stone_Light')
    for x in (-2.4, 2.4):
        window(pb, Fb, x, 3.65, 0.9, 1.1, lintel='BK_Stone_Light')
    door(pb, Fb, 3.2, z0, 0.9, 2.0, leaf='BK_Wood_Dark', frame='BK_Wood_Dark', ground=0.0, panels=1)
    # whitewashed lean-to extension on the -X side
    x0, x1, y0, y1 = -W / 2 - 3.0, -W / 2 + 0.05, -3.2, 1.2
    foundation(pb, x0 - 0.08, x1, y0 - 0.08, y1 + 0.08, top=z0)
    extrude(pb, [(x0, z0), (x1, z0), (x1, 4.25), (x0, 2.75)], lambda u, v, d: V(u, d, v), y0, y1, 'BK_Plaster_White',
            vfn=lambda co: kcol(grime(co.z, z0, 2.0, 0.8)))
    sl2 = (4.25 - 2.75) / (x1 - x0)
    roof_slab(pb, 0.0, 0.0, 'Y', (x0 - 0.3, 2.75 - 0.3 * sl2), (x1 - 0.05, 4.25 - 0.05 * sl2), y0 - 0.15, y1 + 0.15,
              t=0.12, mat='BK_Roof_Slate', under='BK_Wood_Dark', course=0.3, step=0.025, seg=0.9,
              barge='BK_Wood_Dark', fascia='BK_Wood_Dark', gutter='BK_Metal_Dark', seed=23)
    window(pb, FY(y1, 1), -W / 2 - 1.5, 1.05, 0.9, 1.0, cols=2, rows=2)
    door(pb, FX(x0, -1), -1.4, z0, 0.9, 1.95, leaf='BK_Paint_Green', frame='BK_Trim_White', ground=0.0, panels=1)
    ga, gz = gutter_at(D, eave, ridge, oh_e, 1)
    downpipe(pb, (W / 2 - 0.25, ga, gz), ((W / 2 - 0.25, D / 2, gz), (0, 1, 0)))
    return pb


@register('House_Townhouse')
def house_townhouse():
    """Narrow three storey village house, gable to the street: rusticated ground floor, string courses, shutters,
    Juliet balconies, slate roof."""
    pb = PB('House_Townhouse', 103)
    R = pb.R
    W, D = 6.2, 9.4
    z0, eave, ridge = 0.6, 9.8, 13.3
    f1, f2 = 3.6, 6.7
    foundation(pb, -W / 2 - 0.1, W / 2 + 0.1, -D / 2 - 0.1, D / 2 + 0.1, top=z0)
    house_body(pb, 0, 0, 'Y', W, D, z0, eave - 0.02, ridge - 0.02, 'BK_Plaster_Ochre')
    # rusticated stone ground floor (slightly proud)
    for F, c, h in ((FY(D / 2, 1), 0.0, W / 2 + 0.03), (FY(-D / 2, -1), 0.0, W / 2 + 0.03),
                    (FX(W / 2, 1), 0.0, D / 2 + 0.03), (FX(-W / 2, -1), 0.0, D / 2 + 0.03)):
        grid_face(pb, F, c, [(z0, h), (f1 - 0.1, h)], 'BK_Stone_Light', 'stone', course=0.42, blk=(0.8, 1.3), t=0.03,
                  lo=0.86, hi=1.04)
    for z in (f1, f2):
        box2(pb, (-W / 2 - 0.07, -D / 2 - 0.07, z - 0.09), (W / 2 + 0.07, D / 2 + 0.07, z + 0.09), 'BK_Trim_White',
             fcol=flat(0.95))
    gable_roof(pb, 0, 0, 'Y', W, D, eave, ridge, oh_e=0.32, oh_g=0.35, mat='BK_Roof_Slate', barge='BK_Trim_White',
               fascia='BK_Trim_White', gutter='BK_Metal_Dark', course=0.3, step=0.025, seg=1.0, vary_amp=0.14,
               seed=31)
    chimney(pb, 0.0, -3.1, ridge - 1.4, ridge + 1.0, sx=0.72, sy=1.0, mat='BK_Brick', pots=2)
    Ff = FY(D / 2, 1)
    Fg = FY(D / 2 + 0.03, 1)      # ground floor openings sit on the proud rustication
    door(pb, Fg, -1.5, z0, 1.1, 2.4, leaf='BK_Paint_Blue', frame='BK_Trim_White', ground=0.0, panels=2)
    window(pb, Fg, 1.2, 1.25, 1.5, 1.7, cols=3, rows=2, frame='BK_Trim_White', depth=0.11)
    for x in (-1.45, 1.45):
        window(pb, Ff, x, f1 + 0.5, 1.0, 1.75, shutters='BK_Paint_Green', lintel='BK_Trim_White', rows=3)
        # Juliet balcony
        box2(pb, (x - 0.72, D / 2, f1 + 0.3), (x + 0.72, D / 2 + 0.38, f1 + 0.4), 'BK_Stone_Light', fcol=flat(0.9))
        beam(pb, (x - 0.68, D / 2 + 0.34, f1 + 1.25), (x + 0.68, D / 2 + 0.34, f1 + 1.25), 0.04, 0.04,
             'BK_Metal_Dark')
        for k in range(7):
            xx = x - 0.66 + 1.32 * k / 6
            box2(pb, (xx - 0.012, D / 2 + 0.32, f1 + 0.4), (xx + 0.012, D / 2 + 0.36, f1 + 1.25), 'BK_Metal_Dark')
        for xx in (x - 0.68, x + 0.68):
            beam(pb, (xx, D / 2, f1 + 1.25), (xx, D / 2 + 0.34, f1 + 1.25), 0.04, 0.04, 'BK_Metal_Dark')
        window(pb, Ff, x, f2 + 0.5, 0.95, 1.5, shutters='BK_Paint_Green', lintel='BK_Trim_White', rows=3)
    window(pb, Ff, 0.0, 10.4, 0.8, 0.95, cols=2, rows=2)
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for z in (f1 + 0.55, f2 + 0.55):
            for y in (-2.6, 1.8):
                window(pb, Fs, y, z, 0.9, 1.45, lintel='BK_Trim_White')
        window(pb, FX(sgn * (W / 2 + 0.03), sgn), -2.6, 1.3, 0.9, 1.3)
    Fb = FY(-D / 2, -1)
    window(pb, FY(-D / 2 - 0.03, -1), 0.0, 1.3, 0.9, 1.3)
    for z in (f1 + 0.55, f2 + 0.55):
        for x in (-1.4, 1.4):
            window(pb, Fb, x, z, 0.9, 1.4, lintel='BK_Trim_White')
    ga, gz = gutter_at(W, eave, ridge, 0.32, 1)
    for sgn in (1, -1):
        downpipe(pb, (sgn * ga, D / 2 - 0.3, gz), ((sgn * W / 2, D / 2 - 0.3, gz), (sgn, 0, 0)))
    return pb


@register('Farmhouse')
def farmhouse():
    """Two storey farmhouse: white plaster, terracotta roof, two ridge chimneys, green shutters, front veranda."""
    pb = PB('Farmhouse', 104)
    R = pb.R
    W, D = 13.6, 8.6
    z0, eave, ridge = 0.45, 6.3, 10.0
    oh_e = 0.5
    foundation(pb, -W / 2 - 0.12, W / 2 + 0.12, -D / 2 - 0.12, D / 2 + 0.12, top=z0)
    house_body(pb, 0, 0, 'X', D, W, z0, eave - 0.02, ridge - 0.02, 'BK_Plaster_White')
    gable_roof(pb, 0, 0, 'X', D, W, eave, ridge, oh_e=oh_e, oh_g=0.35, mat='BK_Roof_Tile', barge='BK_Wood_Dark',
               gutter='BK_Metal_Dark', course=0.38, seg=1.55, seed=41)
    for x in (-3.4, 3.4):
        chimney(pb, x, 0.0, ridge - 1.2, ridge + 1.3, sx=0.8, sy=0.65, mat='BK_Brick', pots=2)
    Ff = FY(D / 2, 1)
    for x in (-5.4, -2.8, 2.8, 5.4):
        window(pb, Ff, x, 1.15, 1.1, 1.4, shutters='BK_Paint_Green')
    for x in (-5.4, -2.8, 0.0, 2.8, 5.4):
        window(pb, Ff, x, 3.95, 1.0, 1.3, shutters='BK_Paint_Green')
    door(pb, Ff, 0.0, z0, 1.2, 2.25, leaf='BK_Paint_Green', frame='BK_Trim_White', ground=z0, glass_top=True)
    # veranda: deck, posts, railing, lean-to roof
    yv = D / 2 + 2.3
    box2(pb, (-4.75, D / 2 - 0.05, -0.6), (4.75, yv + 0.12, z0), 'BK_Deck_Wood', fcol=vary(R, 0.85, 0.95))
    for k in range(2):
        box2(pb, (-0.9, yv + 0.12, -0.3), (0.9, yv + 0.45 + 0.32 * k, z0 - 0.16 - 0.15 * k), 'BK_Deck_Wood',
             fcol=flat(0.82))
    for x in (-4.6, -1.45, 1.45, 4.6):
        box2(pb, (x - 0.09, yv - 0.09, z0), (x + 0.09, yv + 0.09, 3.06), 'BK_Trim_White', fcol=flat(0.95))
    beam(pb, (-4.75, yv, 3.08), (4.75, yv, 3.08), 0.18, 0.16, 'BK_Trim_White', fcol=flat(0.92))
    for xa, xb in ((-4.6, -1.45), (1.45, 4.6)):
        railing(pb, [(xa, yv), (xb, yv)], z0, h=0.9, post_mat='BK_Trim_White', rail_mat='BK_Trim_White',
                post_every=4.0, bal=0.16, bal_w=0.045)
    for xs in (-4.6, 4.6):
        railing(pb, [(xs, D / 2 + 0.1), (xs, yv)], z0, h=0.9, post_mat='BK_Trim_White', rail_mat='BK_Trim_White',
                post_every=3.0, bal=0.16, bal_w=0.045)
    roof_slab(pb, 0.0, 0.0, 'X', (yv + 0.3, 3.08), (D / 2 - 0.02, 3.5), -4.95, 4.95, t=0.12, mat='BK_Roof_Tile',
              under='BK_Wood_Light', course=0.36, seg=1.5, barge='BK_Trim_White', fascia='BK_Trim_White',
              gutter='BK_Metal_Dark', seed=42)
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for y in (-1.8, 1.8):
            window(pb, Fs, y, 1.15, 1.0, 1.3)
            window(pb, Fs, y, 3.95, 1.0, 1.3)
        window(pb, Fs, 0.0, 7.0, 0.8, 0.9)
    Fb = FY(-D / 2, -1)
    for x in (-4.6, -1.5, 1.5, 4.6):
        window(pb, Fb, x, 3.95, 1.0, 1.3)
    for x in (-4.6, -1.5, 4.6):
        window(pb, Fb, x, 1.15, 1.0, 1.3)
    door(pb, Fb, 1.5, z0, 1.0, 2.1, leaf='BK_Wood_Mid', frame='BK_Trim_White', ground=0.0, panels=2)
    ga, gz = gutter_at(D, eave, ridge, oh_e, 1)
    for x in (-W / 2 + 0.25, W / 2 - 0.25):
        downpipe(pb, (x, ga, gz), ((x, D / 2, gz), (0, 1, 0)), z_bottom=z0)
    return pb


@register('House_Chalet')
def house_chalet():
    """Alpine chalet: stone ground floor, timber upper floor, wide shingle roof with purlin ends, balconies with
    board balustrades and red geraniums."""
    pb = PB('House_Chalet', 105)
    R = pb.R
    W, D = 10.4, 11.0
    z0, f1, eave, ridge = 0.4, 3.3, 6.0, 8.6
    oh_e, oh_g = 1.3, 1.7
    foundation(pb, -W / 2 - 0.1, W / 2 + 0.1, -D / 2 - 0.1, D / 2 + 0.1, top=z0)
    for F, c, h in ((FY(D / 2, 1), 0.0, W / 2), (FY(-D / 2, -1), 0.0, W / 2), (FX(W / 2, 1), 0.0, D / 2),
                    (FX(-W / 2, -1), 0.0, D / 2)):
        grid_face(pb, F, c, [(z0, h), (f1, h)], 'BK_Stone_Grey', 'stone', course=0.42, blk=(0.5, 1.0))
    for F, c, h in ((FX(W / 2, 1), 0.0, D / 2), (FX(-W / 2, -1), 0.0, D / 2)):
        grid_face(pb, F, c, [(f1, h), (eave, h)], 'BK_Timber_Chalet', 'hboard', course=0.27, alt=0.86)
    for F in (FY(D / 2, 1), FY(-D / 2, -1)):
        grid_face(pb, F, 0.0, gable_shape(f1, eave, ridge, W / 2), 'BK_Timber_Chalet', 'hboard', course=0.27, alt=0.86)
    box2(pb, (-W / 2 - 0.09, -D / 2 - 0.09, f1 - 0.1), (W / 2 + 0.09, D / 2 + 0.09, f1 + 0.12), 'BK_Timber_Chalet',
         fcol=flat(0.7))
    gable_roof(pb, 0, 0, 'Y', W, D, eave, ridge, oh_e=oh_e, oh_g=oh_g, t=0.18, mat='BK_Roof_Shingle',
               under='BK_Timber_Chalet', barge='BK_Timber_Chalet', gutter='BK_Metal_Dark', course=0.36, step=0.03,
               seg=1.45, vary_amp=0.12, seed=51)
    sl = (ridge - eave) / (W / 2)
    for x in (-5.2, -2.6, 0.0, 2.6, 5.2):
        zu = ridge - abs(x) * sl
        beam(pb, (x, -D / 2 - oh_g + 0.05, zu - 0.13), (x, D / 2 + oh_g - 0.05, zu - 0.13), 0.2, 0.24,
             'BK_Timber_Chalet', fcol=flat(0.75))
    for sgn in (1, -1):
        for y in (-4.7, -1.7, 1.7, 4.7):
            beam(pb, (sgn * (W / 2 - 0.05), y, 4.9), (sgn * (W / 2 + 1.0), y, eave - 1.0 * sl - 0.12), 0.14, 0.14,
                 'BK_Timber_Chalet', fcol=flat(0.75))
    chimney(pb, 2.6, -2.6, eave + 0.6, ridge + 0.85, sx=0.8, sy=0.8, mat='BK_Stone_Grey', cap='BK_Stone_Dark',
            pots=1, pot_mat='BK_Metal_Dark')
    # front: ground floor
    Ff = FY(D / 2, 1)
    door(pb, Ff, 0.0, z0, 1.1, 2.15, leaf='BK_Timber_Chalet', frame='BK_Wood_Dark', ground=0.0, panels=3)
    for x in (-3.0, 3.0):
        window(pb, Ff, x, 1.3, 1.0, 1.15, shutters='BK_Paint_Green', sill='BK_Stone_Light')
    # main balcony
    yb = D / 2 + 1.4
    box2(pb, (-W / 2 - 0.4, D / 2 - 0.05, f1 - 0.1), (W / 2 + 0.4, yb, f1 + 0.08), 'BK_Timber_Chalet', fcol=flat(0.8))
    for x in (-4.4, -1.5, 1.5, 4.4):
        bracket(pb, x, D / 2, yb - 0.15, 2.35, f1 - 0.1, mat='BK_Timber_Chalet', th=0.14)
    railing(pb, [(-W / 2 - 0.32, D / 2 + 0.02), (-W / 2 - 0.32, yb - 0.06), (W / 2 + 0.32, yb - 0.06),
                 (W / 2 + 0.32, D / 2 + 0.02)], f1 + 0.08, h=1.0, post_mat='BK_Timber_Chalet',
            rail_mat='BK_Timber_Chalet', bal_mat='BK_Wood_Light', post_every=3.6, bal=0.19, bal_w=0.12,
            rail_w=0.12)
    Fr = FY(yb, 1)
    for x in (-4.1, -2.4, -0.8, 0.8, 2.4, 4.1):
        flower_box(pb, Fr, x, f1 + 1.06, 1.15, ('BK_Blossom_Red', 'BK_Blossom_Red', 'BK_Blossom_Pink'))
    # upper floor
    door(pb, Ff, 0.0, f1 + 0.08, 1.4, 2.1, leaf='BK_Timber_Chalet', frame='BK_Wood_Dark', ground=f1 + 0.08,
         glass_top=True, double=True)
    for x in (-3.0, 3.0):
        window(pb, Ff, x, f1 + 0.7, 1.0, 1.2, shutters='BK_Paint_Green', sill='BK_Wood_Dark', frame='BK_Trim_White')
    # attic balcony in the gable
    ya = D / 2 + 0.95
    box2(pb, (-1.9, D / 2 - 0.05, eave - 0.08), (1.9, ya, eave + 0.06), 'BK_Timber_Chalet', fcol=flat(0.8))
    for x in (-1.5, 1.5):
        bracket(pb, x, D / 2, ya - 0.1, eave - 0.75, eave - 0.08, mat='BK_Timber_Chalet', th=0.12)
    railing(pb, [(-1.84, D / 2 + 0.02), (-1.84, ya - 0.06), (1.84, ya - 0.06), (1.84, D / 2 + 0.02)], eave + 0.06,
            h=0.95, post_mat='BK_Timber_Chalet', rail_mat='BK_Timber_Chalet', bal_mat='BK_Wood_Light', post_every=2.0,
            bal=0.19, bal_w=0.12, rail_w=0.12)
    door(pb, Ff, 0.0, eave + 0.06, 1.15, 1.75, leaf='BK_Timber_Chalet', frame='BK_Wood_Dark', ground=eave + 0.06,
         glass_top=True, double=True)
    # sides
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for y in (-2.5, 2.5):
            window(pb, Fs, y, 1.3, 1.0, 1.1, sill='BK_Stone_Light')
        for y in (-3.4, 0.0, 3.4):
            window(pb, Fs, y, f1 + 0.7, 0.95, 1.15, sill='BK_Wood_Dark')
    Fb = FY(-D / 2, -1)
    window(pb, Fb, -2.6, 1.3, 1.0, 1.1, sill='BK_Stone_Light')
    door(pb, Fb, 2.6, z0, 1.0, 2.05, leaf='BK_Timber_Chalet', frame='BK_Wood_Dark', ground=0.0, panels=2)
    for x in (-2.6, 2.6):
        window(pb, Fb, x, f1 + 0.7, 1.0, 1.15, sill='BK_Wood_Dark')
    window(pb, Fb, 0.0, eave + 0.3, 0.9, 1.0, sill='BK_Wood_Dark')
    return pb


@register('House_Adobe')
def house_adobe():
    """Flat-roof desert adobe house: battered rounded walls with parapets, stepped upper block, vigas, a portal on
    posts with zapatas, canales, a ladder and a kiva chimney."""
    pb = PB('House_Adobe', 106)
    R = pb.R
    W, D = 9.0, 7.4

    def adobe_block(cx, cy, w, d, zb, ztop, zroof, wall=0.32, batter=0.12, ground=0.0, rad=0.4):
        def ring(ww, dd, z, r):
            return [V(cx + x, cy + y, z) for x, y in rrect2(ww, dd, r, seg=2)]
        rings = [ring(w + 0.12, d + 0.12, zb, rad + 0.06)]
        if zb < ground:
            rings += [ring(w + 0.12, d + 0.12, ground + 0.22, rad + 0.06), ring(w, d, ground + 0.22, rad),
                      ring(w - 0.03, d - 0.03, ground + 0.9, rad)]
        rings += [ring(w - batter, d - batter, ztop, rad * 0.9),
                  ring(w - batter - 2 * wall, d - batter - 2 * wall, ztop, max(0.08, rad * 0.9 - wall)),
                  ring(w - batter - 2 * wall, d - batter - 2 * wall, zroof, max(0.08, rad * 0.9 - wall))]

        def vf(co):
            k = 0.82 if co.z < ground + 0.85 else 1.0
            if co.z > ztop - 0.01:
                k = 1.06
            return kcol(k * (0.97 + 0.03 * hrand(round(co.x, 1), round(co.y, 1))))
        loft(pb, rings, 'BK_Adobe', vfn=vf)

    adobe_block(0.0, 0.0, W, D, -2.5, 3.95, 3.55)
    # raised rounded parapet corners and a front step in the parapet
    for (x, y) in ((-W / 2 + 0.5, -D / 2 + 0.5), (W / 2 - 0.5, -D / 2 + 0.5), (W / 2 - 0.5, D / 2 - 0.5),
                   (-W / 2 + 0.5, D / 2 - 0.5)):
        rings = [[V(x + px, y + py, 3.7) for px, py in rrect2(0.95, 0.95, 0.25, seg=2)],
                 [V(x + px, y + py, 4.2) for px, py in rrect2(0.9, 0.9, 0.25, seg=2)],
                 [V(x + px, y + py, 4.3) for px, py in rrect2(0.7, 0.7, 0.2, seg=2)]]
        loft(pb, rings, 'BK_Adobe', fcol=flat(1.04))
    rings = [[V(px, D / 2 - 0.22 + py, 3.75) for px, py in rrect2(2.6, 0.36, 0.12, seg=1)],
             [V(px, D / 2 - 0.22 + py, 4.15) for px, py in rrect2(2.5, 0.34, 0.12, seg=1)]]
    loft(pb, rings, 'BK_Adobe', fcol=flat(1.04))
    # upper block (set back, rear left)
    ux, uy, uw, ud = -1.9, -1.2, 4.4, 4.0
    adobe_block(ux, uy, uw, ud, 3.4, 6.85, 6.45, ground=3.55)
    # vigas
    for x in (-3.6, -2.4, -1.2, 0.0, 1.2, 2.4, 3.6):
        for sgn in (1, -1):
            ln = R.uniform(0.45, 0.65)
            tube(pb, [V(x, sgn * (D / 2 - 0.5), 3.25), V(x, sgn * (D / 2 + ln), 3.25 - 0.02)], [0.11, 0.1],
                 'BK_Wood_Mid', sides=7, smooth=False, vfn=lambda i, j, p: kcol(0.8 + 0.1 * i))
    for x in (-3.5, -2.7, -1.9, -1.1, -0.3):
        tube(pb, [V(x, uy + ud / 2 - 0.5, 6.55), V(x, uy + ud / 2 + R.uniform(0.4, 0.55), 6.53)], [0.1, 0.09],
             'BK_Wood_Mid', sides=7, smooth=False, vfn=lambda i, j, p: kcol(0.8 + 0.1 * i))
    # canales
    for sgn in (1, -1):
        Fs = FX(sgn * (W / 2 - 0.12), sgn)
        fbox(pb, Fs, 1.0 - 0.13, 1.0 + 0.13, 3.5, 3.66, -0.3, 0.6, 'BK_Wood_Mid', fcol=flat(0.85))
    # portal on posts
    px0, px1, py1 = -0.9, 3.7, D / 2 + 2.2
    box2(pb, (px0 - 0.25, D / 2 - 0.3, 2.78), (px1 + 0.25, py1 + 0.2, 2.98), 'BK_Adobe', fcol=flat(0.95))
    beam(pb, (px0 - 0.3, py1, 2.66), (px1 + 0.3, py1, 2.66), 0.24, 0.24, 'BK_Wood_Mid', fcol=flat(0.85))
    for x in (px0, (px0 + px1) / 2, px1):
        cyl(pb, (x, py1, 0), 0.12, -0.3, 2.48, 'BK_Wood_Mid', sides=8, fcol=flat(0.85))
        box2(pb, (x - 0.42, py1 - 0.11, 2.42), (x + 0.42, py1 + 0.11, 2.55), 'BK_Wood_Mid', fcol=flat(0.8))
    for k in range(6):
        x = px0 + (px1 - px0) * k / 5
        tube(pb, [V(x, D / 2 - 0.3, 2.72), V(x, py1 + 0.45, 2.72)], [0.08, 0.08], 'BK_Wood_Mid', sides=6,
             smooth=False, vfn=lambda i, j, p: kcol(0.85))
    # openings (deep-set, turquoise trim, timber lintels)
    # (walls are battered: the frames sit just in front of the wall surface at window height)
    door(pb, FY(D / 2 + 0.02, 1), 1.4, 0.22, 1.0, 2.1, leaf='BK_Paint_Turquoise', frame='BK_Wood_Mid', ground=0.0,
         panels=2)
    Ff = FY(D / 2 - 0.015, 1)
    for x in (-2.9, 2.95):
        window(pb, Ff, x, 1.15, 0.9, 1.0, frame='BK_Paint_Turquoise', lintel='BK_Wood_Mid', sill='BK_Adobe',
               depth=0.07)
    for sgn in (1, -1):
        Fs = FX(sgn * (W / 2 - 0.015), sgn)
        window(pb, Fs, 0.6, 1.15, 0.85, 0.95, frame='BK_Paint_Turquoise', lintel='BK_Wood_Mid', sill='BK_Adobe',
               depth=0.07)
    Fb = FY(-D / 2 + 0.015, -1)
    for x in (-2.2, 2.4):
        window(pb, Fb, x, 1.15, 0.85, 0.95, frame='BK_Paint_Turquoise', lintel='BK_Wood_Mid', sill='BK_Adobe',
               depth=0.07)
    window(pb, FY(uy + ud / 2 - 0.015, 1), ux, 4.6, 0.8, 0.8, frame='BK_Paint_Turquoise', lintel='BK_Wood_Mid',
           sill='BK_Adobe', depth=0.07)
    window(pb, FX(ux - uw / 2 + 0.015, -1), uy, 4.6, 0.75, 0.8, frame='BK_Paint_Turquoise', lintel='BK_Wood_Mid',
           sill='BK_Adobe', depth=0.07)
    door(pb, FX(ux + uw / 2 + 0.02, 1), uy + 0.6, 3.55, 0.85, 1.9, leaf='BK_Paint_Turquoise', frame='BK_Wood_Mid',
         ground=3.55, panels=1)
    # ladder against the front parapet
    for x in (-3.85, -3.35):
        tube(pb, [V(x, D / 2 + 1.0, -0.1), V(x, D / 2 + 0.05, 4.65)], [0.05, 0.045], 'BK_Wood_Weathered', sides=6,
             smooth=False)
    for k in range(12):
        t = (k + 1) / 13.5
        p = V(-3.6, D / 2 + 1.0 - 0.95 * t, -0.1 + 4.75 * t)
        tube(pb, [p - V(0.27, 0, 0), p + V(0.27, 0, 0)], [0.03, 0.03], 'BK_Wood_Weathered', sides=5, smooth=False)
    # kiva chimney
    rings = [ring_pts((3.0, -2.2), 0.42, 3.4, 8), ring_pts((3.0, -2.2), 0.36, 4.5, 8),
             ring_pts((3.0, -2.2), 0.45, 4.75, 8), ring_pts((3.0, -2.2), 0.4, 4.95, 8)]
    loft(pb, rings, 'BK_Adobe', fcol=flat(1.0))
    cyl(pb, (3.0, -2.2), 0.26, 4.6, 4.97, 'BK_Shadow', sides=8)
    return pb


# ====================================================================================================== farm
@register('Barn_Red')
def barn_red():
    """Big red gambrel barn: vertical board siding, white trim, X-braced sliding doors, hayloft door with hay hood,
    ribbed metal roof and a ridge cupola."""
    pb = PB('Barn_Red', 201)
    R = pb.R
    W, D = 14.0, 24.0
    z0, eave, zk, ridge, xk = 0.45, 6.0, 9.6, 11.6, 4.5
    oh = 0.5
    foundation(pb, -W / 2 - 0.12, W / 2 + 0.12, -D / 2 - 0.12, D / 2 + 0.12, top=z0, mat='BK_Concrete', k=0.85)
    gsh = [(z0, W / 2), (eave, W / 2), (zk, xk), (ridge, 0.0)]
    wall_set(pb, -W / 2, W / 2, -D / 2, D / 2, z0, eave, ridge, 'Y', 'BK_Barn_Red', 'vboard', gshape=gsh, board=0.36,
             alt=0.9)
    s1 = (zk - eave) / (W / 2 - xk)
    slabs = []
    for side in (1, -1):
        A = (side * (W / 2 + oh), eave - oh * s1)
        K = (side * xk, zk)
        T = (0.0, ridge)
        slabs.append(roof_slab(pb, 0.0, 0.0, 'Y', A, K, -D / 2 - oh, D / 2 + oh, t=0.12, style='metal',
                               mat='BK_Roof_Metal', under='BK_Wood_Mid', rib=0.5, barge='BK_Trim_White',
                               fascia='BK_Trim_White', gutter='BK_Metal_Dark', seed=200 + side))
        roof_slab(pb, 0.0, 0.0, 'Y', K, T, -D / 2 - oh, D / 2 + oh, t=0.12, style='metal', mat='BK_Roof_Metal',
                  under='BK_Wood_Mid', rib=0.5, barge='BK_Trim_White', seed=210 + side)
        # knuckle trim
        ridge_cap(pb, 0.0, 0.0, 'Y', side * xk + side * 0.06, zk + 0.12, -D / 2 - oh - 0.05, D / 2 + oh + 0.05, 0.12,
                  'BK_Roof_Metal')
    ridge_cap(pb, 0.0, 0.0, 'Y', 0.0, ridge + 0.1, -D / 2 - oh - 0.05, D / 2 + oh + 0.05, 0.14, 'BK_Roof_Metal')
    # corner trim boards
    for (x, y) in ((-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)):
        box2(pb, (x - 0.14, y - 0.14, z0), (x + 0.14, y + 0.14, eave + 0.05), 'BK_Trim_White', fcol=flat(0.95))
    # front gable: sliding doors, track, hayloft, hay hood
    Ff = FY(D / 2, 1)
    for (xa, xb) in ((-2.45, 0.0), (0.0, 2.45)):
        braced_leaf(pb, Ff, xa + 0.02, xb - 0.02, z0 + 0.02, z0 + 4.4, 'BK_Barn_Red', 'BK_Trim_White', t=0.06)
    fbox(pb, Ff, -5.2, 5.2, z0 + 4.45, z0 + 4.65, -0.02, 0.2, 'BK_Metal_Dark', fcol=flat(0.9))
    fbox(pb, Ff, -2.7, 2.7, z0 - 0.05, z0 + 0.03, -0.02, 0.25, 'BK_Metal_Dark', fcol=flat(0.8))
    braced_leaf(pb, Ff, -0.95, 0.95, 7.0, 8.9, 'BK_Barn_Red', 'BK_Trim_White', t=0.03)
    fbox(pb, Ff, -1.1, 1.1, 6.86, 7.0, -0.02, 0.2, 'BK_Trim_White', fcol=flat(0.92))
    gable_roof(pb, 0.0, D / 2 + 0.55, 'Y', 1.7, 1.5, 10.3, 10.9, oh_e=0.1, oh_g=0.08, t=0.08, style='metal',
               mat='BK_Roof_Metal', under='BK_Wood_Mid', barge='BK_Trim_White', gutter=None, rib=0.3, seed=220)
    house_body(pb, 0.0, D / 2 + 0.55, 'Y', 1.7, 1.5, 9.9, 10.28, 10.88, 'BK_Barn_Red')
    beam(pb, (0, D / 2 - 0.1, 9.75), (0, D / 2 + 1.55, 9.75), 0.16, 0.2, 'BK_Wood_Mid', fcol=flat(0.85))
    tube(pb, [V(0.0, D / 2 + 1.35, 9.65), V(0.0, D / 2 + 1.35, 9.45)], [0.05, 0.05], 'BK_Metal_Dark', sides=6)
    cyl(pb, (0.0, D / 2 + 1.35), 0.12, 9.25, 9.45, 'BK_Metal_Dark', sides=8)
    # side windows + person door
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for y in (-8.0, -3.0, 3.0, 8.0):
            window(pb, Fs, y, 3.5, 0.9, 0.9, sill='BK_Trim_White', frame='BK_Trim_White', fw=0.1)
    door(pb, FX(W / 2, 1), 5.6, z0, 1.0, 2.1, leaf='BK_Barn_Red', frame='BK_Trim_White', ground=0.0, panels=1)
    # back gable door
    Fb = FY(-D / 2, -1)
    braced_leaf(pb, Fb, -2.0, 2.0, z0 + 0.02, z0 + 4.0, 'BK_Barn_Red', 'BK_Trim_White', t=0.06)
    window(pb, Fb, 0.0, 7.4, 1.1, 1.1, sill='BK_Trim_White', frame='BK_Trim_White', fw=0.1)
    # cupola
    box2(pb, (-0.85, -0.85, ridge - 0.6), (0.85, 0.85, ridge + 1.15), 'BK_Barn_Red', fcol=flat(0.95))
    for F in (FY(0.85, 1), FY(-0.85, -1), FX(0.85, 1), FX(-0.85, -1)):
        fbox(pb, F, -0.62, 0.62, ridge + 0.3, ridge + 1.0, -0.02, 0.03, 'BK_Shadow')
        for k in range(4):
            zz = ridge + 0.36 + k * 0.17
            fbox(pb, F, -0.62, 0.62, zz, zz + 0.05, 0.0, 0.06, 'BK_Trim_White', fcol=flat(0.9))
        fbox(pb, F, -0.85, 0.85, ridge + 1.0, ridge + 1.15, -0.01, 0.05, 'BK_Trim_White', fcol=flat(0.95))
    rings = [[V(x, y, ridge + 1.15) for x, y in ((-1.1, -1.1), (1.1, -1.1), (1.1, 1.1), (-1.1, 1.1))],
             [V(x, y, ridge + 1.3) for x, y in ((-1.05, -1.05), (1.05, -1.05), (1.05, 1.05), (-1.05, 1.05))],
             [V(x, y, ridge + 2.05) for x, y in ((-0.06, -0.06), (0.06, -0.06), (0.06, 0.06), (-0.06, 0.06))]]
    loft(pb, rings, 'BK_Roof_Metal', fcol=flat(0.9))
    tube(pb, [V(0, 0, ridge + 1.95), V(0, 0, ridge + 2.85)], [0.03, 0.025], 'BK_Metal_Dark', sides=5)
    box2(pb, (-0.45, -0.02, ridge + 2.55), (0.45, 0.02, ridge + 2.6), 'BK_Metal_Dark')
    hexa(pb, [V(0.45, -0.02, 2.5 + ridge), V(0.62, -0.02, 2.575 + ridge), V(0.62, 0.02, 2.575 + ridge),
              V(0.45, 0.02, 2.5 + ridge), V(0.45, -0.02, 2.65 + ridge), V(0.62, -0.02, 2.6 + ridge),
              V(0.62, 0.02, 2.6 + ridge), V(0.45, 0.02, 2.65 + ridge)], 'BK_Metal_Dark')
    box2(pb, (-0.5, -0.12, ridge + 2.5), (-0.4, 0.12, ridge + 2.65), 'BK_Metal_Dark')
    return pb


@register('Silo')
def silo():
    """12 m concrete stave silo with steel hoops, galvanised dome, front chute and a filler pipe."""
    pb = PB('Silo', 202)
    R = pb.R
    R0, H, sides = 2.6, 10.2, 20
    cyl(pb, (0, 0), 3.1, -1.0, 0.25, 'BK_Concrete', sides=8, fcol=vary(R, 0.85, 0.92), phase=PI / 8)
    # stave rows and proud hoop bands
    zs = [0.2]
    hoop_idx = set()
    while zs[-1] < H - 0.5:
        z = min(H, zs[-1] + 0.78)
        zs.append(z)
        if z < H - 0.2:
            hoop_idx.add(len(zs) - 1)
            zs.append(z + 0.07)
    if zs[-1] < H:
        zs.append(H)
    hoops = [zs[i] for i in sorted(hoop_idx)]
    rings, radii = [], []
    RH = R0 + 0.035
    for i, z in enumerate(zs):
        if i in hoop_idx:
            rings += [ring_pts((0, 0), R0, z, sides), ring_pts((0, 0), RH, z, sides)]
            radii += [R0, RH]
        elif (i - 1) in hoop_idx:
            rings += [ring_pts((0, 0), RH, z, sides), ring_pts((0, 0), R0, z, sides)]
            radii += [RH, R0]
        else:
            rings.append(ring_pts((0, 0), R0, z, sides))
            radii.append(R0)
    stave_k = {}

    def side_mat(i, j):
        return 'BK_Metal_Dark' if max(radii[i], radii[i + 1]) > R0 + 0.01 else 'BK_Concrete_Stave'

    def fc(c, n):
        a = math.atan2(c.y, c.x)
        key = (int((a + PI) / TAU * sides), round(c.z, 1))
        if key not in stave_k:
            stave_k[key] = R.uniform(0.86, 1.04)
        return kcol(stave_k[key] * grime(c.z, 0.0, 2.0, 0.82))
    loft(pb, rings, 'BK_Concrete_Stave', side_mat=side_mat, cap0=False, cap1=False, fcol=fc)
    # dome
    prof = [(R0, H), (R0 + 0.1, H), (R0 + 0.1, H + 0.14), (R0 - 0.15, H + 0.55), (R0 * 0.74, H + 1.0),
            (R0 * 0.45, H + 1.38), (0.52, H + 1.6)]
    rings = [ring_pts((0, 0), r, z, sides) for r, z in prof]
    loft(pb, rings, 'BK_Metal_Galv', cap0=False, cap1=True,
         fcol=lambda c, n: kcol(0.9 + 0.1 * (int((math.atan2(c.y, c.x) + PI) / TAU * sides) % 2)))
    cyl(pb, (0, 0), 0.5, H + 1.58, H + 1.7, 'BK_Metal_Galv', sides=10, r1=0.42)
    cyl(pb, (0, 0), 0.22, H + 1.7, H + 1.8, 'BK_Metal_Dark', sides=8, r1=0.16)
    # chute on the front
    zc1 = H + 0.5
    mids = [z for z in hoops if z < zc1]
    extrude(pb, [(-0.38, R0 - 0.3), (0.38, R0 - 0.3), (0.38, R0 + 0.55), (-0.38, R0 + 0.55)],
            lambda u, v, d: V(u, v, d), 0.2, zc1, 'BK_Metal_Galv', mids=mids,
            fcol=lambda c, n: kcol(0.82 if n.z > 0.5 else (0.95 if int(c.z / 0.85) % 2 else 0.88)))
    hexa(pb, [V(-0.42, R0 - 0.5, zc1), V(0.42, R0 - 0.5, zc1), V(0.42, R0 + 0.6, zc1), V(-0.42, R0 + 0.6, zc1),
              V(-0.42, R0 - 0.5, zc1 + 0.85), V(0.42, R0 - 0.5, zc1 + 0.85), V(0.42, R0 - 0.1, zc1 + 0.85),
              V(-0.42, R0 - 0.1, zc1 + 0.85)], 'BK_Metal_Galv', fcol=flat(0.9))
    fbox(pb, FY(R0 + 0.55, 1), -0.3, 0.3, 0.3, 2.2, -0.02, 0.03, 'BK_Metal_Dark')
    # filler pipe with wall brackets
    a = math.radians(215.0)
    ca, sa = math.cos(a), math.sin(a)
    Rp = R0 + 0.32
    pts = [V(Rp * ca, Rp * sa, 0.2), V(Rp * ca, Rp * sa, H + 0.25), V((R0 - 0.2) * ca, (R0 - 0.2) * sa, H + 0.9),
           V(1.2 * ca, 1.2 * sa, H + 1.42), V(0.55 * ca, 0.55 * sa, H + 1.62)]
    tube(pb, pts, [0.14] * len(pts), 'BK_Metal_Galv', sides=8, smooth=True)
    for z in (1.5, 4.0, 6.5, 9.0):
        beam(pb, (R0 * ca * 0.99, R0 * sa * 0.99, z), (Rp * ca, Rp * sa, z), 0.08, 0.08, 'BK_Metal_Dark')
    return pb


@register('Shed_Small')
def shed_small():
    """Small timber garden shed: board walls, shingle roof, ledged-and-braced door, small window."""
    pb = PB('Shed_Small', 203)
    R = pb.R
    W, D = 3.6, 2.6
    z0, eave, ridge = 0.15, 2.15, 2.78
    box2(pb, (-W / 2 - 0.12, -D / 2 - 0.12, -0.6), (W / 2 + 0.12, D / 2 + 0.12, z0), 'BK_Concrete',
         fcol=vary(R, 0.82, 0.9))
    wall_set(pb, -W / 2, W / 2, -D / 2, D / 2, z0, eave, ridge, 'X', 'BK_Wood_Mid', 'vboard', board=0.15, alt=0.88)
    for (x, y) in ((-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)):
        box2(pb, (x - 0.05, y - 0.05, z0), (x + 0.05, y + 0.05, eave), 'BK_Wood_Dark', fcol=flat(0.9))
    gable_roof(pb, 0, 0, 'X', D, W, eave, ridge, oh_e=0.25, oh_g=0.2, t=0.08, mat='BK_Roof_Shingle',
               under='BK_Wood_Dark', barge='BK_Wood_Dark', gutter=None, course=0.22, step=0.02, seg=0.6,
               vary_amp=0.15, seed=231)
    Ff = FY(D / 2, 1)
    x0, x1, zt = -1.15, -0.25, z0 + 1.88
    fbox(pb, Ff, x0 - 0.06, x1 + 0.06, z0, zt + 0.06, -0.03, 0.05, 'BK_Wood_Dark', fcol=flat(0.9))
    fbox(pb, Ff, x0, x1, z0 + 0.02, zt, 0.02, 0.08, 'BK_Wood_Mid', fcol=flat(0.82))
    for zz in (z0 + 0.25, z0 + 0.95, zt - 0.25):
        fbox(pb, Ff, x0 + 0.04, x1 - 0.04, zz - 0.07, zz + 0.07, 0.07, 0.11, 'BK_Wood_Mid', fcol=flat(0.92))
    for za, zb in ((z0 + 0.25, z0 + 0.95), (z0 + 0.95, zt - 0.25)):
        beam(pb, Ff.p(x1 - 0.1, za, 0.09), Ff.p(x0 + 0.1, zb, 0.09), 0.12, 0.04, 'BK_Wood_Mid', up=(0, 1, 0),
             fcol=flat(0.92))
    for zz in (z0 + 0.25, zt - 0.25):
        fbox(pb, Ff, x0 - 0.05, x0 + 0.3, zz - 0.03, zz + 0.03, 0.1, 0.13, 'BK_Black')
    fbox(pb, Ff, x1 - 0.12, x1 - 0.06, z0 + 0.95, z0 + 1.05, 0.1, 0.16, 'BK_Black')
    window(pb, Ff, 0.85, 1.1, 0.7, 0.55, frame='BK_Wood_Dark', cols=2, rows=1, sill='BK_Wood_Dark', fw=0.06)
    window(pb, FX(W / 2, 1), 0.0, 1.15, 0.55, 0.5, frame='BK_Wood_Dark', cols=1, rows=1, sill='BK_Wood_Dark', fw=0.06)
    # water butt at the back corner
    cyl(pb, (-W / 2 + 0.45, -D / 2 - 0.42), 0.32, -0.05, 0.95, 'BK_Paint_Green', sides=10, fcol=flat(0.85))
    cyl(pb, (-W / 2 + 0.45, -D / 2 - 0.42), 0.34, 0.95, 1.0, 'BK_Paint_Green', sides=10, fcol=flat(0.7))
    return pb


# ====================================================================================================== commercial
@register('Gas_Station')
def gas_station():
    """Roadside fuel station: 18 x 10 m canopy on six columns with emissive light panels underneath (front), flat
    forecourt at Z 0 for the separate Fuel_Pump props, small shop with a glazed front behind."""
    pb = PB('Gas_Station', 301)
    R = pb.R
    cy0, cy1 = 0.6, 10.6          # canopy y range (front = cy1)
    sy0, sy1 = -11.4, -3.4        # shop y range
    # forecourt slab with 2 m panels (subtle variation) and the shop apron
    box2(pb, (-9.0, sy1, -3.0), (9.0, cy1, 0.0), 'BK_Concrete', fcol=flat(0.85))
    xs = [-9.0 + 2.0 * i for i in range(10)]
    ys = [sy1 + (cy1 - sy1) * j / 7 for j in range(8)]
    vs, fs, fc = [], [], []
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            b = len(vs)
            vs += [V(xs[i], ys[j], 0.03), V(xs[i + 1], ys[j], 0.03), V(xs[i + 1], ys[j + 1], 0.03),
                   V(xs[i], ys[j + 1], 0.03)]
            fs.append((b, b + 1, b + 2, b + 3))
            fc.append(kcol(R.uniform(0.86, 0.97)))
    pb.add(vs, fs, 'BK_Concrete', fcols=fc, hint=(0, 0, 1))
    box2(pb, (-8.6, sy1 - 0.05, 0.0), (8.6, sy1 + 1.3, 0.17), 'BK_Concrete', fcol=flat(0.97))
    # canopy
    box2(pb, (-9.0, cy0, 5.0), (9.0, cy1, 5.95), 'BK_Render_White', fcol=lambda c, n: kcol(0.8 if n.z < -0.5 else 0.97))
    box2(pb, (-9.04, cy0 - 0.04, 5.28), (9.04, cy1 + 0.04, 5.62), 'BK_Paint_Orange', fcol=flat(0.97))
    box2(pb, (-9.05, cy0 - 0.05, 5.68), (9.05, cy1 + 0.05, 5.78), 'BK_Paint_Teal', fcol=flat(0.97))
    for x in (-6.0, -2.0, 2.0, 6.0):
        for y in (3.4, 7.8):
            box2(pb, (x - 1.2, y - 0.45, 4.97), (x + 1.2, y + 0.45, 5.02), 'BK_LightPanel')
    for x in (-7.4, 0.0, 7.4):
        for y in (2.46, 7.74):
            box2(pb, (x - 0.25, y - 0.25, 0.0), (x + 0.25, y + 0.25, 5.0), 'BK_Render_White', fcol=flat(0.95))
            box2(pb, (x - 0.27, y - 0.27, 0.15), (x + 0.27, y + 0.27, 0.95), 'BK_Metal_Dark', fcol=flat(0.9))
            box2(pb, (x - 0.45, y - 0.45, -0.05), (x + 0.45, y + 0.45, 0.18), 'BK_Paint_Yellow', fcol=flat(0.9))
    # shop
    box2(pb, (-7.0, sy0, -2.0), (7.0, sy1, 4.2), 'BK_Render_White',
         fcol=lambda c, n: kcol(0.95 * (grime(c.z, 0.0, 1.0, 0.85) if abs(n.z) < 0.5 else 1.0)))
    box2(pb, (-7.12, sy0 - 0.12, 4.2), (7.12, sy1 + 0.12, 4.5), 'BK_Render_White', fcol=flat(0.98))
    box2(pb, (-7.08, sy0 - 0.08, 3.35), (7.08, sy1 + 0.08, 4.05), 'BK_Paint_Orange', fcol=flat(0.97))
    box2(pb, (-7.09, sy0 - 0.09, 3.22), (7.09, sy1 + 0.09, 3.3), 'BK_Paint_Teal', fcol=flat(0.97))
    Ff = FY(sy1, 1)
    window(pb, Ff, -3.5, 0.45, 5.6, 2.45, frame='BK_Metal_Dark', cols=4, rows=1, sill=None, fw=0.08, depth=0.08)
    window(pb, Ff, 3.5, 0.45, 2.2, 2.45, frame='BK_Metal_Dark', cols=2, rows=1, sill=None, fw=0.08, depth=0.08)
    # glazed double door
    fbox(pb, Ff, 0.0, 1.8, 0.17, 2.55, -0.08, 0.01, 'Window', fcol=flat(0.95))
    ring_frame(pb, Ff, rect2(-0.08, 0.17, 1.88, 2.63), rect2(0.0, 0.17, 1.8, 2.55), -0.04, 0.08, 'BK_Metal_Dark')
    fbox(pb, Ff, 0.88, 0.92, 0.17, 2.55, -0.03, 0.06, 'BK_Metal_Dark')
    for x in (0.5, 1.3):
        fbox(pb, Ff, x - 0.3, x + 0.3, 1.0, 1.05, 0.04, 0.1, 'BK_Chrome')
    fbox(pb, Ff, 5.0, 6.6, 1.6, 2.4, -0.02, 0.03, 'BK_Metal_Dark')
    for k in range(5):
        fbox(pb, Ff, 5.05, 6.55, 1.68 + k * 0.14, 1.72 + k * 0.14, 0.02, 0.05, 'BK_Metal_Galv')
    door(pb, FX(7.0, 1), -6.0, 0.17, 1.0, 2.1, leaf='BK_Metal_Galv', frame='BK_Metal_Dark', ground=0.0, panels=1,
         knob='BK_Metal_Dark')
    window(pb, FY(sy0, -1), 3.0, 1.7, 0.8, 0.6, frame='BK_Metal_Dark', cols=1, rows=1, sill=None)
    # canopy trims, shop door canopy, wall lamps, ice chest, gas-bottle cage
    box2(pb, (-9.06, cy0 - 0.06, 5.9), (9.06, cy1 + 0.06, 6.02), 'BK_Metal_Dark', fcol=flat(0.9))
    box2(pb, (-9.03, cy0 - 0.03, 4.94), (9.03, cy1 + 0.03, 5.02), 'BK_Metal_Galv', fcol=flat(0.95))
    box2(pb, (-0.6, sy1, 2.85), (2.4, sy1 + 1.1, 3.0), 'BK_Metal_Galv', fcol=flat(0.92))
    for x in (-0.45, 2.25):
        beam(pb, (x, sy1, 3.3), (x, sy1 + 1.05, 3.0), 0.05, 0.05, 'BK_Metal_Dark')
    for x in (-5.0, 4.0):
        gooseneck_lamp(pb, Ff, x, 3.0, 0.45)
    box2(pb, (-6.6, sy1 + 0.15, 0.17), (-5.2, sy1 + 0.95, 1.15), 'BK_Render_White', fcol=flat(0.97))
    box2(pb, (-6.62, sy1 + 0.13, 0.75), (-5.18, sy1 + 0.97, 0.95), 'BK_Paint_Blue', fcol=flat(0.95))
    cx0, cx1, cyb0, cyb1 = 7.15, 8.35, -9.0, -7.2
    box2(pb, (cx0 - 0.05, cyb0 - 0.05, -0.1), (cx1 + 0.05, cyb1 + 0.05, 0.12), 'BK_Concrete', fcol=flat(0.85))
    for (x, y) in ((cx0, cyb0), (cx1, cyb0), (cx1, cyb1), (cx0, cyb1)):
        box2(pb, (x - 0.03, y - 0.03, 0.12), (x + 0.03, y + 0.03, 1.6), 'BK_Metal_Galv')
    box2(pb, (cx0 - 0.05, cyb0 - 0.05, 1.6), (cx1 + 0.05, cyb1 + 0.05, 1.66), 'BK_Metal_Galv', fcol=flat(0.9))
    for x in (cx0 + 0.3, cx1 - 0.3):
        for k in range(3):
            y = cyb0 + 0.35 + k * 0.55
            cyl(pb, (x, y), 0.17, 0.12, 1.15, 'BK_Paint_Red' if (k + int(x)) % 2 else 'BK_Paint_Yellow', sides=8,
                fcol=flat(0.92))
            cyl(pb, (x, y), 0.09, 1.15, 1.28, 'BK_Metal_Galv', sides=6)
    for z in (0.5, 1.05):
        for (a, b) in (((cx0, cyb0), (cx1, cyb0)), ((cx1, cyb0), (cx1, cyb1)), ((cx0, cyb1), (cx1, cyb1))):
            beam(pb, (a[0], a[1], z), (b[0], b[1], z), 0.03, 0.03, 'BK_Metal_Galv')
    # roof plant
    for x in (-3.5, 2.0):
        box2(pb, (x - 0.65, -8.5, 4.2), (x + 0.65, -7.6, 5.0), 'BK_Metal_Galv', fcol=flat(0.9))
        cyl(pb, (x, -8.05), 0.32, 5.0, 5.04, 'BK_Metal_Dark', sides=10)
    tube(pb, [V(5.5, -9.5, 4.2), V(5.5, -9.5, 5.3)], [0.08, 0.08], 'BK_Metal_Galv', sides=8)
    return pb


@register('Diner')
def diner():
    """Retro roadside diner: streamlined stainless body with rounded ends, red bands, a continuous window band,
    entrance vestibule and a rooftop sign board with neon tubes (no lettering)."""
    pb = PB('Diner', 302)
    R = pb.R
    L, Wd = 8.6, 6.6
    plan = stadium2(L, Wd, seg=8, n_straight=20)
    bands = [-1.8, 0.72, 0.92, 2.55, 2.75, 3.7]
    bmat = ['BK_Brick', 'BK_Paint_Red', 'Window', 'BK_Paint_Red', 'BK_Steel_Brushed']

    def band_of(z):
        for i in range(len(bands) - 1):
            if bands[i] - 1e-4 <= z <= bands[i + 1] + 1e-4:
                return i
        return 0

    def fc(c, n):
        if abs(n.z) > 0.5:
            return kcol(0.9)
        i = band_of(c.z)
        if bmat[i] == 'BK_Steel_Brushed':
            idx = int(round((math.atan2(c.y, c.x * 0.6) + PI) * 9.0))
            return kcol(0.86 + 0.14 * (idx % 2))
        if bmat[i] == 'BK_Brick':
            return kcol(R.uniform(0.82, 0.98) * grime(c.z, -0.3, 0.8, 0.85))
        return kcol(0.97)
    extrude(pb, plan, lambda u, v, d: V(u, v, d), bands[0], bands[-1], 'BK_Steel_Brushed', mids=bands[1:-1],
            side_mat=lambda i, j: bmat[i], cap_mats=('BK_Brick', 'BK_Render_White'), fcol=fc)
    # mullions in the window band
    n = len(plan)
    for k in range(0, n, 2):
        x, y = plan[k]
        x0, y0 = plan[k - 1]
        x1, y1 = plan[(k + 1) % n]
        t = Vector((x1 - x0, y1 - y0, 0.0)).normalized()
        N = Vector((t.y, -t.x, 0.0))
        if N.dot(Vector((x, y, 0.0))) < 0:
            N = -N
        F = Frame((x, y, 0.0), N, t)
        fbox(pb, F, -0.035, 0.035, bands[2], bands[3], -0.02, 0.04, 'BK_Chrome', fcol=flat(0.95))
    # roof slab with red edge band and overhang
    roof_plan = stadium2(L, Wd + 0.8, seg=8, n_straight=4)
    extrude(pb, roof_plan, lambda u, v, d: V(u, v, d), 3.68, 3.98, 'BK_Render_White', fcol=lambda c, nn: kcol(
        0.78 if nn.z < -0.5 else 0.97))
    band_plan = stadium2(L, Wd + 0.86, seg=8, n_straight=4)
    extrude(pb, band_plan, lambda u, v, d: V(u, v, d), 3.76, 3.9, 'BK_Paint_Red', fcol=flat(0.97))
    # entrance vestibule
    yv0, yv1 = Wd / 2 - 0.6, Wd / 2 + 1.3
    box2(pb, (-1.35, yv0, -1.0), (1.35, yv1, 3.25), 'BK_Steel_Brushed',
         fcol=lambda c, nn: kcol(0.9 + 0.1 * (int(round(c.x * 4.0)) % 2) if abs(nn.z) < 0.5 else 0.9))
    box2(pb, (-1.37, yv0, 0.72), (1.37, yv1 + 0.02, 0.92), 'BK_Paint_Red', fcol=flat(0.97))
    box2(pb, (-1.45, yv0, 3.25), (1.45, yv1 + 0.1, 3.45), 'BK_Render_White', fcol=flat(0.95))
    box2(pb, (-1.65, yv1, 2.95), (1.65, yv1 + 0.85, 3.08), 'BK_Paint_Red', fcol=flat(0.95))
    for x in (-1.45, 1.45):
        beam(pb, (x, yv1, 2.55), (x, yv1 + 0.8, 2.95), 0.05, 0.05, 'BK_Chrome')
    Fv = FY(yv1, 1)
    fbox(pb, Fv, -0.75, 0.75, 0.3, 2.6, -0.08, 0.01, 'Window', fcol=flat(0.95))
    ring_frame(pb, Fv, rect2(-0.83, 0.3, 0.83, 2.68), rect2(-0.75, 0.3, 0.75, 2.6), -0.04, 0.08, 'BK_Paint_Red')
    fbox(pb, Fv, -0.02, 0.02, 0.3, 2.6, -0.03, 0.06, 'BK_Chrome')
    for x in (-0.35, 0.35):
        fbox(pb, Fv, x - 0.2, x + 0.2, 1.3, 1.35, 0.04, 0.1, 'BK_Chrome')
    for k in range(2):
        fbox(pb, Fv, -1.1 - 0.15 * k, 1.1 + 0.15 * k, -0.4, 0.3 - 0.15 * k, -0.05, 0.4 + 0.32 * k, 'BK_Concrete',
             fcol=flat(0.9))
    for sgn in (1, -1):
        Fs = FX(sgn * 1.35, sgn)
        fbox(pb, Fs, yv0 + 0.9, yv1 - 0.3, 0.92, 2.55, -0.06, 0.01, 'Window', fcol=flat(0.95))
    # rooftop sign board on posts
    for x in (-2.4, 2.4):
        box2(pb, (x - 0.1, -0.1, 3.9), (x + 0.1, 0.1, 5.05), 'BK_Metal_Dark', fcol=flat(0.9))
    box2(pb, (-3.72, -0.15, 4.95), (3.72, 0.15, 6.98), 'BK_Paint_Red', fcol=flat(0.95))
    box2(pb, (-3.55, -0.18, 5.08), (3.55, 0.18, 6.85), 'BK_Paint_Cream', fcol=flat(0.97))
    zc = 5.965
    for sgn in (1, -1):
        y = sgn * (0.18 + 0.035)
        border = [V(x, y, z + zc) for x, z in rrect2(6.7, 1.45, 0.3, seg=2)]
        tube(pb, border, 0.035, 'BK_Neon_Pink', sides=5, smooth=False, closed=True)
    yf = 0.18 + 0.035
    tube(pb, [V(-1.9, yf, zc - 0.05), V(3.0, yf, zc - 0.05)], 0.04, 'BK_Neon_Cyan', sides=5, smooth=False)
    tube(pb, [V(-1.9, yf, zc + 0.3), V(2.2, yf, zc + 0.3)], 0.03, 'BK_Neon_Cyan', sides=5, smooth=False)
    tube(pb, [V(-1.9, yf, zc - 0.4), V(2.6, yf, zc - 0.4)], 0.03, 'BK_Neon_Cyan', sides=5, smooth=False)
    star = []
    for k in range(10):
        a = PI / 2 + PI * k / 5
        rr = 0.5 if k % 2 == 0 else 0.22
        star.append(V(-2.75 + rr * math.cos(a), yf, zc + rr * math.sin(a)))
    tube(pb, star, 0.03, 'BK_Neon_Pink', sides=5, smooth=False, closed=True)
    tube(pb, [V(3.0, yf, zc - 0.05), V(2.75, yf, zc + 0.2)], 0.04, 'BK_Neon_Cyan', sides=5, smooth=False)
    tube(pb, [V(3.0, yf, zc - 0.05), V(2.75, yf, zc - 0.3)], 0.04, 'BK_Neon_Cyan', sides=5, smooth=False)
    # roof plant + kitchen stack
    box2(pb, (4.0, -2.2, 3.98), (5.4, -0.9, 4.75), 'BK_Metal_Galv', fcol=flat(0.9))
    cyl(pb, (4.7, -1.55), 0.4, 4.75, 4.79, 'BK_Metal_Dark', sides=10)
    cyl(pb, (-5.2, -1.6), 0.2, 3.95, 5.0, 'BK_Chrome', sides=8)
    cyl(pb, (-5.2, -1.6), 0.32, 5.0, 5.2, 'BK_Chrome', sides=8, r1=0.12)
    return pb


@register('Church')
def church():
    """Small stone village church: nave with slate roof, round-arched windows and buttresses, polygonal apse at the
    back, front tower (~20 m) with belfry openings, clock faces, a slate spire and a weathervane."""
    pb = PB('Church', 303)
    R = pb.R
    W, D = 9.2, 16.0
    z0, eave, ridge = 0.35, 6.4, 10.8
    foundation(pb, -W / 2 - 0.15, W / 2 + 0.15, -D / 2 - 0.15, D / 2 + 0.15, top=z0)
    wall_set(pb, -W / 2, W / 2, -D / 2, D / 2, z0, eave, ridge, 'Y', 'BK_Stone_Grey', 'stone', course=0.62,
             blk=(0.75, 1.45))
    gable_roof(pb, 0, 0, 'Y', W, D, eave, ridge, oh_e=0.35, oh_g=0.22, mat='BK_Roof_Slate', barge='BK_Stone_Light',
               fascia='BK_Stone_Light', gutter='BK_Metal_Dark', course=0.4, step=0.028, seg=2.3, vary_amp=0.15,
               seed=331)
    # nave windows + buttresses
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for y in (-5.0, -1.0, 3.0):
            window(pb, Fs, y, 2.3, 1.1, 2.9, frame='BK_Stone_Light', cols=2, rows=3, arch=True, sill='BK_Stone_Light',
                   fw=0.14, depth=0.12, seg=6)
        for y in (-7.0, -3.0, 1.0, 5.0):
            x0 = sgn * (W / 2 - 0.1)
            x1 = sgn * (W / 2 + 0.75)
            xa, xb = min(x0, x1), max(x0, x1)
            box2(pb, (xa, y - 0.4, -0.3), (xb, y + 0.4, 3.4), 'BK_Stone_Light', fcol=vary(R, 0.85, 0.95, 0.0))
            xo, xm = sgn * (W / 2 + 0.75), sgn * (W / 2 + 0.42)
            hexa(pb, [V(x0, y - 0.4, 3.4), V(xo, y - 0.4, 3.4), V(xo, y + 0.4, 3.4), V(x0, y + 0.4, 3.4),
                      V(x0, y - 0.36, 4.1), V(xm, y - 0.36, 4.1), V(xm, y + 0.36, 4.1), V(x0, y + 0.36, 4.1)],
                 'BK_Stone_Light', fcol=flat(0.9))
            hexa(pb, [V(x0, y - 0.36, 4.1), V(xm, y - 0.36, 4.1), V(xm, y + 0.36, 4.1), V(x0, y + 0.36, 4.1),
                      V(x0, y - 0.36, 5.6), V(xm, y - 0.36, 5.3), V(xm, y + 0.36, 5.3), V(x0, y + 0.36, 5.6)],
                 'BK_Stone_Light', fcol=flat(0.88))
    # apse (half octagon at the back; the front half is hidden inside the nave)
    ac, ar, ae = (0.0, -D / 2 + 0.05), 3.6, 5.3
    cyl(pb, ac, ar + 0.15, -2.5, z0, 'BK_Stone_Dark', sides=8, phase=PI / 8, fcol=flat(0.9))
    pts8 = [(ac[0] + ar * math.cos(PI / 8 + TAU * k / 8), ac[1] + ar * math.sin(PI / 8 + TAU * k / 8)) for k in range(8)]
    for k in range(8):
        (xa, ya), (xb, yb) = pts8[k], pts8[(k + 1) % 8]
        mx, my = (xa + xb) / 2, (ya + yb) / 2
        if my > ac[1] + 0.5:
            continue
        t = Vector((xb - xa, yb - ya, 0.0))
        half = t.length / 2
        t.normalize()
        N = Vector((t.y, -t.x, 0.0))
        if N.dot(Vector((mx - ac[0], my - ac[1], 0.0))) < 0:
            N = -N
        F = Frame((mx, my, 0.0), N, t)
        grid_face(pb, F, 0.0, [(z0, half), (ae, half)], 'BK_Stone_Grey', 'stone', course=0.55, blk=(0.6, 1.2))
        if abs(N.x) < 0.95:
            window(pb, F, 0.0, 2.3, 0.7, 1.8, frame='BK_Stone_Light', cols=1, rows=2, arch=True, sill='BK_Stone_Light',
                   fw=0.12, depth=0.1, seg=6)
    cyl(pb, ac, ar + 0.4, ae - 0.32, ae + 3.0, 'BK_Roof_Slate', sides=8, r1=0.05, phase=PI / 8,
        fcol=lambda c, n: kcol(0.75 if n.z < -0.5 else R.uniform(0.92, 1.05)))
    # tower
    tx0, tx1, ty0, ty1 = -2.3, 2.3, D / 2, D / 2 + 4.6
    tz1 = 14.0
    foundation(pb, tx0 - 0.15, tx1 + 0.15, ty0 - 0.1, ty1 + 0.15, top=z0)
    tc = (ty0 + ty1) / 2
    for F, c, h in ((FY(ty1, 1), 0.0, 2.3), (FY(ty0, -1), 0.0, 2.3), (FX(tx1, 1), tc, 2.3), (FX(tx0, -1), tc, 2.3)):
        grid_face(pb, F, c, [(z0, h), (tz1, h)], 'BK_Stone_Grey', 'stone', course=0.66, blk=(0.75, 1.4))
    for z, p in ((9.0, 0.07), (tz1 - 0.15, 0.14)):
        box2(pb, (tx0 - p, ty0 - p, z - 0.12), (tx1 + p, ty1 + p, z + 0.12), 'BK_Stone_Light', fcol=flat(0.92))
    for F, c in ((FY(ty1, 1), 0.0), (FY(ty0, -1), 0.0), (FX(tx1, 1), tc), (FX(tx0, -1), tc)):
        for dx in (-0.6, 0.6):
            inner = arch2(c + dx, 11.3, 0.62, 1.8, 4)
            outer = arch2(c + dx, 11.3 - 0.12, 0.86, 2.04, 4)
            fprism(pb, F, inner, -0.06, 0.005, 'BK_Shadow')
            ring_frame(pb, F, outer, inner, -0.04, 0.09, 'BK_Stone_Light', fcol=flat(0.92))
            for k in range(3):
                zz = 11.5 + k * 0.4
                fbox(pb, F, c + dx - 0.31, c + dx + 0.31, zz, zz + 0.06, -0.03, 0.04, 'BK_Wood_Dark')
        if F.N.y > -0.5:
            cp = (c, 10.05)
            fprism(pb, F, circle2(0.58, 12, cx=cp[0], cy=cp[1]), -0.02, 0.05, 'BK_Paint_Cream', fcol=flat(0.97))
            ring_frame(pb, F, circle2(0.68, 12, cx=cp[0], cy=cp[1]), circle2(0.58, 12, cx=cp[0], cy=cp[1]), -0.02,
                       0.08, 'BK_Stone_Light', fcol=flat(0.9))
            fbox(pb, F, cp[0] - 0.025, cp[0] + 0.025, cp[1], cp[1] + 0.45, 0.05, 0.07, 'BK_Black')
            beam(pb, F.p(cp[0], cp[1], 0.075), F.p(cp[0] + 0.3, cp[1] - 0.12, 0.075), 0.04, 0.02, 'BK_Black',
                 up=tuple(F.N))
    Ft = FY(ty1, 1)
    door(pb, Ft, 0.0, z0, 1.5, 3.0, leaf='BK_Wood_Dark', frame='BK_Stone_Light', arch=True, fw=0.24, double=True,
         ground=0.0, panels=2, knob='BK_Metal_Dark', seg=8, step_w=2.6)
    window(pb, Ft, 0.0, 5.4, 0.6, 1.4, frame='BK_Stone_Light', cols=1, rows=2, arch=True, sill='BK_Stone_Light',
           fw=0.12, seg=6)
    for F, c in ((FX(tx1, 1), tc), (FX(tx0, -1), tc)):
        fprism(pb, F, arch2(c, 6.2, 0.22, 1.1, 4), -0.04, 0.01, 'BK_Shadow')
    # spire (bell-cast square pyramid) + finial + weathervane
    sq = lambda h, z: [V(x, tc + y, z) for x, y in ((-h, -h), (h, -h), (h, h), (-h, h))]
    loft(pb, [sq(2.6, tz1 - 0.05), sq(2.62, tz1 + 0.12), sq(2.2, tz1 + 0.75), sq(0.06, 20.4)], 'BK_Roof_Slate',
         cap_mats=('BK_Stone_Dark', 'BK_Roof_Slate'), fcol=lambda c, n: kcol(0.8 if n.z < -0.5 else R.uniform(0.92, 1.04)))
    sphere(pb, (0, tc, 20.45), 0.16, 'BK_Brass', seg=8, rings=5)
    tube(pb, [V(0, tc, 20.35), V(0, tc, 21.6)], [0.035, 0.03], 'BK_Metal_Dark', sides=5)
    box2(pb, (-0.55, tc - 0.015, 21.18), (0.45, tc + 0.015, 21.24), 'BK_Metal_Dark')
    hexa(pb, [V(0.45, tc - 0.015, 21.1), V(0.68, tc - 0.015, 21.21), V(0.68, tc + 0.015, 21.21),
              V(0.45, tc + 0.015, 21.1), V(0.45, tc - 0.015, 21.32), V(0.68, tc - 0.015, 21.21 + 0.001),
              V(0.68, tc + 0.015, 21.211), V(0.45, tc + 0.015, 21.32)], 'BK_Metal_Dark')
    box2(pb, (-0.62, tc - 0.12, 21.13), (-0.5, tc + 0.12, 21.29), 'BK_Metal_Dark')
    return pb


# ====================================================================================================== harbour
@register('Harbour_Shed')
def harbour_shed():
    """Corrugated-metal harbour shed: concrete upstand, ribbed cladding and roof with skylight strips, roller door,
    personnel door, blank sign board, gooseneck lamps, fish crates."""
    pb = PB('Harbour_Shed', 401)
    R = pb.R
    W, D = 12.0, 20.0
    z0, zc, eave, ridge = 0.3, 1.0, 6.0, 8.2
    oh_e = 0.4
    foundation(pb, -W / 2 - 0.15, W / 2 + 0.15, -D / 2 - 0.15, D / 2 + 0.15, top=z0, mat='BK_Concrete', k=0.85)
    box2(pb, (-W / 2 - 0.03, -D / 2 - 0.03, z0), (W / 2 + 0.03, D / 2 + 0.03, zc), 'BK_Concrete',
         fcol=lambda c, n: kcol(0.85 if abs(n.z) < 0.5 else 0.9))
    gsh = [(zc, W / 2), (eave, W / 2), (ridge, 0.0)]
    wall_set(pb, -W / 2, W / 2, -D / 2, D / 2, zc, eave, ridge, 'Y', 'BK_Cladding_Teal', 'vboard', gshape=gsh,
             board=0.2, alt=0.86)
    gable_roof(pb, 0, 0, 'Y', W, D, eave, ridge, oh_e=oh_e, oh_g=0.3, t=0.1, style='metal', mat='BK_Roof_Metal',
               under='BK_Metal_Galv', barge='BK_Metal_Dark', fascia='BK_Metal_Dark', gutter='BK_Metal_Dark', rib=0.3,
               seed=411)
    sl = (ridge - eave) / (W / 2)
    for side in (1, -1):
        A, B = (side * (W / 2 + oh_e), eave - oh_e * sl), (0.0, ridge)
        for yc in (-6.0, 0.0, 6.0):
            pts = []
            for y in (yc - 0.9, yc + 0.9):
                for (u, h) in ((1.2, 0.09), (3.6, 0.09), (3.6, 0.13), (1.2, 0.13)):
                    a, z, _ = slab_point(A, B, u, h)
                    pts.append(V(a, y, z))
            hexa(pb, pts, 'BK_Skylight', fcol=flat(0.95))
    for (x, y) in ((-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)):
        box2(pb, (x - 0.09, y - 0.09, zc), (x + 0.09, y + 0.09, eave + 0.02), 'BK_Metal_Dark', fcol=flat(0.9))
    Ff = FY(D / 2, 1)
    # roller door with slats, guides and housing
    grid_face(pb, FY(D / 2 + 0.06, 1), -1.5, [(z0, 2.7), (5.0, 2.7)], 'BK_Metal_Galv', 'hboard', course=0.22, alt=0.84)
    for x in (-4.3, 1.3):
        fbox(pb, Ff, x - 0.08, x + 0.08, z0, 5.05, -0.02, 0.14, 'BK_Metal_Dark', fcol=flat(0.9))
    fbox(pb, Ff, -4.45, 1.45, 5.0, 5.55, -0.02, 0.45, 'BK_Metal_Galv', fcol=flat(0.88))
    fbox(pb, Ff, -4.4, 1.4, z0 - 0.04, z0 + 0.02, -0.02, 0.1, 'BK_Black')
    door(pb, Ff, 3.6, z0, 1.0, 2.1, leaf='BK_Paint_Blue', frame='BK_Metal_Dark', ground=0.0, panels=1,
         knob='BK_Metal_Dark')
    box2(pb, (2.9, D / 2, 2.6), (4.3, D / 2 + 0.9, 2.7), 'BK_Metal_Galv', fcol=flat(0.9))
    for x in (3.0, 4.2):
        beam(pb, (x, D / 2, 3.1), (x, D / 2 + 0.85, 2.7), 0.04, 0.04, 'BK_Metal_Dark')
    # blank sign board (border + field)
    fbox(pb, Ff, -3.7, 0.7, 5.72, 6.62, -0.02, 0.06, 'BK_Trim_White', fcol=flat(0.95))
    fbox(pb, Ff, -3.6, 0.6, 5.8, 6.54, 0.0, 0.09, 'BK_Paint_Blue', fcol=flat(0.95))
    gooseneck_lamp(pb, Ff, -1.5, 6.75, 0.65)
    gooseneck_lamp(pb, Ff, 3.6, 3.15, 0.55)
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for y in (-6.0, 0.0, 6.0):
            window(pb, Fs, y, 3.9, 2.4, 0.9, frame='BK_Metal_Dark', cols=3, rows=1, sill='BK_Metal_Dark', fw=0.07)
    door(pb, FY(-D / 2, -1), -2.0, z0, 1.0, 2.1, leaf='BK_Paint_Blue', frame='BK_Metal_Dark', ground=0.0, panels=1,
         knob='BK_Metal_Dark')
    ga, gz = gutter_at(W, eave, ridge, oh_e, 1)
    for sgn in (1, -1):
        downpipe(pb, (sgn * ga, D / 2 - 0.35, gz), ((sgn * W / 2, D / 2 - 0.35, gz), (sgn, 0, 0)))
    # fish crates
    cols = ['BK_Paint_Blue', 'BK_Paint_Orange', 'BK_Paint_Blue', 'BK_Paint_Yellow', 'BK_Paint_Orange',
            'BK_Paint_Blue']
    k = 0
    for (x, y, nz) in ((4.9, D / 2 + 0.75, 3), (5.6, D / 2 + 0.75, 2), (5.25, D / 2 + 1.3, 1)):
        for j in range(nz):
            box2(pb, (x - 0.3, y - 0.2, 0.0 + 0.3 * j), (x + 0.3, y + 0.2, 0.29 + 0.3 * j), cols[k % len(cols)],
                 fcol=lambda c, n: kcol(0.75 if n.z > 0.5 else 0.95))
            k += 1
    return pb


@register('Boathouse')
def boathouse():
    """Timber boathouse on piles (origin = floor level): falu-red shiplap, white trim, boat doors to the water side
    (-Y), land door + window at the front (+Y), lifebuoy."""
    pb = PB('Boathouse', 402)
    R = pb.R
    W, D = 7.0, 11.0
    z0, eave, ridge = 0.0, 3.4, 5.7
    for x in (-3.2, 0.0, 3.2):
        for y in (-5.1, -1.7, 1.7, 5.1):
            cyl(pb, (x, y), 0.18, -4.5, -0.3, 'BK_Wood_Dark', sides=8, fcol=flat(0.8))
    for y in (-5.1, -1.7, 1.7, 5.1):
        box2(pb, (-3.55, y - 0.12, -0.5), (3.55, y + 0.12, -0.25), 'BK_Wood_Dark', fcol=flat(0.75))
    box2(pb, (-3.85, -D / 2 - 0.35, -0.25), (3.85, D / 2 + 1.3, 0.0), 'BK_Deck_Wood',
         fcol=lambda c, n: kcol(0.9 if n.z > 0.5 else 0.72))
    for y in (D / 2 + 0.6, D / 2 + 1.3):
        cyl(pb, (-3.2, y), 0.16, -4.5, -0.25, 'BK_Wood_Dark', sides=8, fcol=flat(0.8))
        cyl(pb, (3.2, y), 0.16, -4.5, -0.25, 'BK_Wood_Dark', sides=8, fcol=flat(0.8))
    wall_set(pb, -W / 2, W / 2, -D / 2, D / 2, z0, eave, ridge, 'Y', 'BK_Falu_Red', 'hboard', course=0.24, alt=0.88)
    for (x, y) in ((-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)):
        box2(pb, (x - 0.08, y - 0.08, z0), (x + 0.08, y + 0.08, eave + 0.02), 'BK_Trim_White', fcol=flat(0.95))
    gable_roof(pb, 0, 0, 'Y', W, D, eave, ridge, oh_e=0.45, oh_g=0.4, t=0.12, mat='BK_Roof_Slate',
               barge='BK_Trim_White', fascia='BK_Trim_White', gutter=None, course=0.3, step=0.025, seg=1.0,
               vary_amp=0.14, seed=421)
    Fb = FY(-D / 2, -1)
    for (xa, xb) in ((-2.3, 0.0), (0.0, 2.3)):
        braced_leaf(pb, Fb, xa + 0.02, xb - 0.02, 0.02, 3.0, 'BK_Falu_Red', 'BK_Trim_White', t=0.06, k=0.8)
    fbox(pb, Fb, -2.5, 2.5, 3.0, 3.2, -0.02, 0.12, 'BK_Trim_White', fcol=flat(0.95))
    window(pb, Fb, 0.0, 3.9, 0.6, 0.6, cols=2, rows=2, sill='BK_Trim_White')
    Ff = FY(D / 2, 1)
    door(pb, Ff, 1.6, z0, 0.95, 2.05, leaf='BK_Paint_Green', frame='BK_Trim_White', ground=z0, panels=2)
    window(pb, Ff, -1.6, 1.05, 0.95, 0.95, cols=2, rows=2, sill='BK_Trim_White')
    window(pb, Ff, 0.0, 3.85, 0.6, 0.6, cols=2, rows=2, sill='BK_Trim_White')
    for sgn in (1, -1):
        Fs = FX(sgn * W / 2, sgn)
        for y in (-2.4, 2.4):
            window(pb, Fs, y, 1.3, 0.9, 0.8, cols=2, rows=2, sill='BK_Trim_White')
    # lifebuoy on the front wall
    ring = [V(-0.05 + 0.32 * math.cos(TAU * k / 12), D / 2 + 0.075, 2.25 + 0.32 * math.sin(TAU * k / 12))
            for k in range(12)]
    tube(pb, ring, 0.07, 'BK_Trim_White', sides=6, smooth=True, closed=True,
         side_mat=lambda i, j: 'BK_Paint_Red' if (i // 3) % 2 == 0 else 'BK_Trim_White')
    # cleats on the landing
    for x in (-3.4, 3.4):
        box2(pb, (x - 0.06, D / 2 + 0.9, 0.0), (x + 0.06, D / 2 + 1.0, 0.1), 'BK_Metal_Dark')
        box2(pb, (x - 0.06, D / 2 + 0.75, 0.1), (x + 0.06, D / 2 + 1.15, 0.15), 'BK_Metal_Dark')
    return pb
