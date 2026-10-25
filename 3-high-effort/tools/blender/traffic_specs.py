"""Civilian traffic vehicles (simpler than the garage cars: no detailed interior)."""

CITY = dict(
    name="TRF_City", file="traffic_city", lite=True, L=3.55, W=1.64, wb=2.36, fo=0.62, wheel_r=0.29, wheel_w=0.185,
    ride=0.14, nose_z=0.82, nose_drop=0.12, front_lift=0.14, cowl_y=0.86, cowl_z=1.02, roof_front_y=0.3, roof_z=1.53,
    roof_rear_y=-1.0, deck_y=-1.45, deck_z=1.12, tail_z=1.02, belt_r=1.02, belt_f=0.92,
    trunk_keys=[(-1.25, 1.38)], glass_rear_y=-0.95, glass_front_y=0.7, doors=4, b_pillar_y=-0.2, tumble=0.84,
    nose_taper=0.82, tail_taper=0.93,
    headlight=dict(w=0.26, h=0.14, x=0.52, z=0.84, wrap=0.45, up=0.2, shape="ellipse"),
    taillight=dict(w=0.12, h=0.2, x=0.68, z=1.04, wrap=0.6),
    grille=dict(w=0.45, h=0.07, z=0.7), intake=dict(w=0.9, h=0.1, dz=0.12),
    exhaust=[(0.4, 0.04)], exhaust_dual=False, spoilers=[], rim_style="steel", rim_color=(0.7, 0.7, 0.72),
    paint=(0.9, 0.85, 0.3), seat_y=-0.3,
)

VAN = dict(
    name="TRF_Van", file="traffic_van", lite=True, L=5.1, W=1.96, wb=3.2, fo=0.9, wheel_r=0.34, wheel_w=0.215,
    ride=0.18, nose_z=1.05, nose_drop=0.08, front_lift=0.16, cowl_y=1.32, cowl_z=1.26, roof_front_y=0.85, roof_z=2.35,
    roof_rear_y=-2.35, deck_y=-2.47, deck_z=2.25, tail_z=1.95, tail_drop=0.02, belt_r=1.25, belt_f=1.2,
    hood_keys=[(2.2, 1.12)], glass_rear_y=0.5, glass_front_y=1.15, doors=2, tumble=0.95, roof_crown=0.04,
    hood_crown=0.04, deck_round=0.95, shoulder=0.98, nose_taper=0.9, tail_taper=0.98, rear_glass=False,
    headlight=dict(w=0.3, h=0.16, x=0.66, z=1.02, wrap=0.4, up=0.1, shape="rect"),
    taillight=dict(w=0.12, h=0.4, x=0.88, z=1.2, wrap=0.5),
    grille=dict(w=0.9, h=0.18, z=0.88, slats=3), intake=dict(w=1.3, h=0.12, dz=0.14),
    exhaust=[(0.5, 0.05)], exhaust_dual=False, spoilers=[], rim_style="steel", rim_color=(0.6, 0.6, 0.62),
    paint=(0.93, 0.93, 0.95), seat_y=0.6,
)

LORRY = dict(
    name="TRF_Lorry", file="traffic_lorry", lite=True, L=7.2, W=2.3, wb=4.2, fo=1.25, wheel_r=0.48, wheel_w=0.3,
    ride=0.3, rim_ratio=0.58, tread_groove=0.02,
    nose_z=1.6, nose_drop=0.06, front_lift=0.2, cowl_y=2.95, cowl_z=1.8, roof_front_y=2.7, roof_z=2.95,
    roof_rear_y=1.62, deck_y=1.47, deck_z=1.28, tail_z=1.22, tail_drop=0.02, belt_r=1.25, belt_f=1.75,
    belt_keys=[(-3.85, 1.2), (1.4, 1.22), (1.6, 1.72), (3.35, 1.72)],
    glass_rear_y=1.72, glass_front_y=2.85, doors=2, tumble=0.95, roof_crown=0.04, hood_crown=0.03, deck_round=0.96,
    shoulder=0.985, nose_taper=0.94, tail_taper=0.98, rear_glass=False, mirrors=True, cabin_closed=False,
    headlight=dict(w=0.32, h=0.18, x=0.82, z=1.45, wrap=0.3, up=0.0, shape="rect"),
    taillight=dict(w=0.2, h=0.12, x=0.95, z=1.05, wrap=0.3),
    grille=dict(w=1.3, h=0.4, z=1.6, slats=4), intake=dict(w=1.6, h=0.15, dz=0.25),
    extras=["cargo_box"], box=(2.38, 5.0, 2.55, -1.25, 1.32), paint2=(0.88, 0.88, 0.86),
    exhaust=[(0.9, 0.1)], exhaust_dual=False, spoilers=[], rim_style="steel", rim_color=(0.75, 0.75, 0.76),
    paint=(0.12, 0.35, 0.6), seat_y=2.2,
)

BUS = dict(
    name="TRF_Coach", file="traffic_coach", lite=True, L=11.0, W=2.5, wb=6.0, fo=2.3, wheel_r=0.5, wheel_w=0.3,
    ride=0.35, rim_ratio=0.58, tread_groove=0.02,
    nose_z=1.42, nose_drop=0.05, front_lift=0.1, cowl_y=5.12, cowl_z=1.42, roof_front_y=4.95, roof_z=3.3,
    roof_rear_y=-5.45, deck_y=-5.6, deck_z=3.1, tail_z=2.9, tail_drop=0.04, belt_r=1.5, belt_f=1.42,
    glass_rear_y=-5.0, glass_front_y=4.85, doors=2, tumble=0.97, roof_crown=0.07, hood_crown=0.02, deck_round=0.97,
    shoulder=0.99, nose_taper=0.95, tail_taper=0.97, rear_glass=True, ws_inset=0.02,
    pillars=[(-3.75, -3.6), (-2.25, -2.1), (-0.75, -0.6), (0.75, 0.9), (2.25, 2.4), (3.75, 3.9)],
    headlight=dict(w=0.36, h=0.14, x=0.9, z=0.85, wrap=0.2, up=0.0, shape="rect"),
    taillight=dict(w=0.16, h=0.36, x=1.05, z=1.0, wrap=0.3),
    grille=dict(w=1.4, h=0.2, z=0.6, slats=3), intake=dict(w=0.0, h=0.0),
    exhaust=[(0.9, 0.05)], exhaust_dual=False, spoilers=[], rim_style="steel", rim_color=(0.8, 0.8, 0.82),
    paint=(0.95, 0.6, 0.12), seat_y=4.2, black_sill=True,
)

FARM_PICKUP = dict(
    name="TRF_FarmPickup", file="traffic_pickup", lite=True, L=4.95, W=1.86, wb=3.0, fo=0.82, wheel_r=0.36,
    wheel_w=0.235, ride=0.24, rim_ratio=0.6,
    nose_z=1.08, nose_drop=0.1, front_lift=0.14, cowl_y=0.95, cowl_z=1.24, roof_front_y=0.45, roof_z=1.78,
    roof_rear_y=-0.32, deck_y=-0.48, deck_z=1.16, tail_z=1.12, tail_drop=0.02, belt_r=1.14, belt_f=1.12,
    hood_keys=[(1.9, 1.15)], trunk_keys=[(-1.5, 1.16)],
    glass_rear_y=-0.25, glass_front_y=0.78, doors=2, tumble=0.88, roof_crown=0.05, deck_round=0.94,
    nose_taper=0.9, tail_taper=0.97, flare_f=0.05, flare_r=0.05, black_sill=False,
    open_regions=[(-2.4, -0.62, (8, 9, 10))],
    headlight=dict(w=0.18, h=0.18, x=0.64, z=1.0, wrap=0.2, up=0.0, shape="ellipse"),
    taillight=dict(w=0.1, h=0.2, x=0.82, z=0.98, wrap=0.5),
    grille=dict(w=0.85, h=0.24, z=0.88, chrome=True, slats=3), intake=dict(w=0.0, h=0.0),
    extras=["bed", "chrome_bumpers"], bumper_z=0.25,
    exhaust=[(0.6, 0.05)], exhaust_dual=False, spoilers=[], rim_style="steel", rim_color=(0.9, 0.9, 0.9),
    paint=(0.25, 0.42, 0.3), seat_y=0.0,
)

TRACTOR = dict(name="TRF_Tractor", file="traffic_tractor", paint=(0.15, 0.5, 0.18), rim_color=(0.9, 0.78, 0.12))

TRAFFIC = [CITY, VAN, LORRY, BUS, FARM_PICKUP]
