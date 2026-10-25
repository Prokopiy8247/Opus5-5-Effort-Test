"""Specs for the ten original Velora Roads garage cars (Blender units = metres).

Longitudinal stations are measured along +Y from the middle of the wheelbase.
Every car is its own loft: proportions, rooflines and details differ per spec.
"""

KESTREL = dict(
    name="Kestrel_GTi", file="kestrel_gti", L=4.10, W=1.80, wb=2.60, fo=0.86, wheel_r=0.315, wheel_w=0.225, ride=0.14,
    nose_z=0.80, cowl_y=1.00, cowl_z=0.98, roof_front_y=0.22, roof_z=1.43, roof_rear_y=-1.12,
    deck_y=-1.86, deck_z=1.02, tail_z=0.95, belt_r=0.99, belt_f=0.86, front_lift=0.16,
    trunk_keys=[(-1.55, 1.30)], hood_keys=[(1.70, 0.90)],
    glass_rear_y=-1.05, glass_front_y=0.80, doors=2, tumble=0.76, roof_crown=0.05,
    nose_taper=0.84, tail_taper=0.93, flare_f=0.025, flare_r=0.03, rear_seats=True,
    headlight=dict(w=0.36, h=0.10, x=0.6, z=0.80, wrap=0.45, up=0.2, shape="slant"),
    taillight=dict(w=0.22, h=0.18, x=0.72, z=1.00, wrap=0.6),
    grille=dict(w=0.75, h=0.09, z=0.66, shape="rect"), intake=dict(w=1.2, h=0.12, dz=0.12),
    exhaust=[(0.42, 0.04)], exhaust_dual=False, spoilers=["roof"], rim_style="y",
    paint=(0.85, 0.08, 0.06), caliper=(0.85, 0.1, 0.05), plate_zr=0.62,
)

ARDEN = dict(
    name="Arden_Saloon", file="arden_saloon", L=4.75, W=1.83, wb=2.76, fo=0.95, wheel_r=0.32, wheel_w=0.215, ride=0.15,
    nose_z=0.78, nose_drop=0.1, cowl_y=1.12, cowl_z=1.0, roof_front_y=0.36, roof_z=1.46, roof_rear_y=-0.92,
    deck_y=-1.58, deck_z=1.05, tail_z=1.0, belt_r=1.0, belt_f=0.9, front_lift=0.14,
    trunk_keys=[(-2.1, 1.05)], hood_keys=[(1.9, 0.88)],
    glass_rear_y=-0.95, glass_front_y=0.95, doors=4, b_pillar_y=-0.22, tumble=0.8,
    nose_taper=0.86, tail_taper=0.92, rear_seats=True,
    headlight=dict(w=0.42, h=0.12, x=0.6, z=0.8, wrap=0.4, up=0.15, shape="rect"),
    taillight=dict(w=0.38, h=0.12, x=0.66, z=0.98, wrap=0.5),
    grille=dict(w=0.8, h=0.13, z=0.72, chrome=False, slats=3), intake=dict(w=1.1, h=0.1, dz=0.12),
    exhaust=[(0.5, 0.04)], exhaust_dual=False, spoilers=[], rim_style="multi",
    paint=(0.16, 0.27, 0.46), caliper=(0.3, 0.3, 0.32), plate_zr=0.66,
)

BRUTE = dict(
    name="Brute_69", file="brute_69", L=4.85, W=1.92, wb=2.84, fo=1.05, wheel_r=0.34, wheel_w=0.25, ride=0.16,
    nose_z=0.86, nose_drop=0.04, front_lift=0.08, cowl_y=0.5, cowl_z=1.02, roof_front_y=-0.16, roof_z=1.34,
    roof_rear_y=-0.92, deck_y=-1.78, deck_z=1.03, tail_z=1.0, tail_drop=0.03, belt_r=0.98, belt_f=0.94,
    hood_keys=[(1.5, 0.95), (2.2, 0.9)],
    glass_rear_y=-0.85, glass_front_y=0.25, doors=2, tumble=0.74, roof_crown=0.04, hood_crown=0.03,
    nose_taper=0.97, tail_taper=0.98, flare_r=0.05, flare_f=0.02, rear_seats=True, black_sill=False,
    headlight=dict(w=0.16, h=0.16, x=0.72, z=0.8, wrap=0.0, up=0.0, shape="ellipse", twin=0.2),
    taillight=dict(bar=True, h=0.08, z=0.88),
    grille=dict(w=1.55, h=0.2, z=0.78, chrome=False, slats=4), intake=dict(w=0.0, h=0.0),
    extras=["hood_scoop", "chrome_bumpers"], bumper_z=0.22,
    exhaust=[(0.55, 0.0)], exhaust_dual=True, spoilers=["ducktail"], rim_style="five",
    paint=(0.95, 0.5, 0.05), rim_color=(0.8, 0.8, 0.82), caliper=(0.2, 0.2, 0.2), plate_zr=0.58,
)

SORA = dict(
    name="Sora_Coupe", file="sora_coupe", L=4.45, W=1.80, wb=2.60, fo=0.95, wheel_r=0.33, wheel_w=0.245, ride=0.12,
    nose_z=0.7, nose_drop=0.15, front_lift=0.12, cowl_y=0.88, cowl_z=0.94, roof_front_y=0.05, roof_z=1.3,
    roof_rear_y=-0.78, deck_y=-1.78, deck_z=0.99, tail_z=0.95, belt_r=0.95, belt_f=0.84,
    hood_keys=[(1.8, 0.8)],
    glass_rear_y=-0.75, glass_front_y=0.65, doors=2, tumble=0.74, roof_crown=0.05,
    nose_taper=0.8, tail_taper=0.9, flare_r=0.045, flare_f=0.02, rear_seats=True,
    headlight=dict(w=0.42, h=0.07, x=0.6, z=0.74, wrap=0.6, up=0.35, shape="slant"),
    taillight=dict(w=0.16, h=0.16, x=0.62, z=0.92, wrap=0.2, shape="ellipse"),
    grille=dict(w=0.5, h=0.06, z=0.62), intake=dict(w=1.3, h=0.16, dz=0.12),
    exhaust=[(0.5, 0.02)], exhaust_dual=True, spoilers=["wing"], rim_style="six",
    paint=(0.92, 0.92, 0.94), rim_color=(0.12, 0.12, 0.13), caliper=(0.95, 0.75, 0.05), plate_zr=0.6,
)

VALCOURT = dict(
    name="Valcourt_GT", file="valcourt_gt", L=4.85, W=1.96, wb=2.86, fo=1.0, wheel_r=0.355, wheel_w=0.265, ride=0.12,
    nose_z=0.7, nose_drop=0.13, front_lift=0.12, cowl_y=0.42, cowl_z=0.98, roof_front_y=-0.32, roof_z=1.29,
    roof_rear_y=-1.12, deck_y=-1.9, deck_z=0.99, tail_z=0.95, belt_r=0.96, belt_f=0.9,
    hood_keys=[(1.4, 0.9), (2.1, 0.8)],
    glass_rear_y=-1.05, glass_front_y=0.2, doors=2, tumble=0.72, roof_crown=0.05,
    nose_taper=0.82, tail_taper=0.9, flare_r=0.055, flare_f=0.03, waist=0.97, rear_seats=True,
    headlight=dict(w=0.4, h=0.08, x=0.64, z=0.74, wrap=0.55, up=0.3, shape="slant"),
    taillight=dict(w=0.42, h=0.07, x=0.6, z=0.93, wrap=0.6),
    grille=dict(w=0.85, h=0.17, z=0.6, shape="ellipse", slats=5, chrome=False), intake=dict(w=1.4, h=0.08, dz=0.1),
    exhaust=[(0.42, 0.02), (0.6, 0.02)], exhaust_dual=True, spoilers=["ducktail"], rim_style="multi",
    paint=(0.05, 0.2, 0.14), rim_color=(0.6, 0.6, 0.62), caliper=(0.75, 0.6, 0.1), plate_zr=0.6,
)

NYX = dict(
    name="Nyx_Strata", file="nyx_strata", L=4.55, W=2.0, wb=2.7, fo=1.05, wheel_r=0.345, wheel_r_rear=0.36,
    wheel_w=0.26, wheel_w_rear=0.33, ride=0.1,
    nose_z=0.58, nose_drop=0.13, front_lift=0.1, cowl_y=1.12, cowl_z=0.86, roof_front_y=0.3, roof_z=1.16,
    roof_rear_y=-0.5, deck_y=-1.5, deck_z=0.98, tail_z=0.92, belt_r=0.95, belt_f=0.74,
    hood_keys=[(1.9, 0.68)], trunk_keys=[(-1.0, 1.06)],
    glass_rear_y=-0.45, glass_front_y=0.95, doors=2, tumble=0.66, roof_crown=0.05,
    nose_taper=0.78, tail_taper=0.95, flare_r=0.07, flare_f=0.04, waist=0.93, rear_glass=False,
    headlight=dict(w=0.4, h=0.06, x=0.68, z=0.66, wrap=0.7, up=0.45, shape="slant"),
    taillight=dict(bar=True, h=0.05, z=0.88),
    grille=dict(w=0.0), intake=dict(w=1.55, h=0.2, dz=0.1),
    extras=["side_intakes", "roof_scoop"],
    exhaust=[(0.12, 0.22)], exhaust_dual=True, spoilers=["wing"], rim_style="turbine",
    paint=(0.4, 0.82, 0.12), rim_color=(0.08, 0.08, 0.09), caliper=(0.85, 0.85, 0.85), plate_zr=0.5,
    seat_y=-0.05,
)

MISTRAL = dict(
    name="Mistral_R5", file="mistral_r5", L=4.05, W=1.86, wb=2.56, fo=0.82, wheel_r=0.33, wheel_w=0.235, ride=0.21,
    nose_z=0.86, nose_drop=0.1, front_lift=0.18, cowl_y=0.95, cowl_z=1.06, roof_front_y=0.15, roof_z=1.52,
    roof_rear_y=-1.15, deck_y=-1.8, deck_z=1.14, tail_z=1.0, belt_r=1.05, belt_f=0.94,
    trunk_keys=[(-1.5, 1.4)], hood_keys=[(1.6, 0.97)],
    glass_rear_y=-1.05, glass_front_y=0.78, doors=2, tumble=0.78, roof_crown=0.05,
    nose_taper=0.86, tail_taper=0.95, flare_f=0.06, flare_r=0.065, rear_seats=False,
    headlight=dict(w=0.3, h=0.12, x=0.6, z=0.88, wrap=0.4, up=0.2, shape="rect"),
    taillight=dict(w=0.18, h=0.2, x=0.74, z=1.06, wrap=0.6),
    grille=dict(w=0.7, h=0.12, z=0.74), intake=dict(w=1.3, h=0.16, dz=0.14),
    extras=["light_pod", "mudflaps", "roof_scoop"],
    exhaust=[(0.5, 0.06)], exhaust_dual=False, spoilers=["roof"], rim_style="five",
    paint=(0.1, 0.32, 0.85), rim_color=(0.95, 0.95, 0.95), caliper=(0.95, 0.5, 0.05), plate_zr=0.7,
)

TRAILHOUND = dict(
    name="Trailhound", file="trailhound", L=4.7, W=1.96, wb=2.84, fo=0.85, wheel_r=0.4, wheel_w=0.29, ride=0.3,
    rim_ratio=0.58, tread_groove=0.014,
    nose_z=1.12, nose_drop=0.05, front_lift=0.2, cowl_y=1.0, cowl_z=1.3, roof_front_y=0.55, roof_z=1.9,
    roof_rear_y=-2.2, deck_y=-2.36, deck_z=1.72, tail_z=1.5, tail_drop=0.02, belt_r=1.38, belt_f=1.28,
    hood_keys=[(1.8, 1.2)],
    glass_rear_y=-2.05, glass_front_y=0.7, doors=4, b_pillar_y=-0.35, pillars=[(-1.32, -1.2)],
    tumble=0.9, roof_crown=0.03, hood_crown=0.03, deck_round=0.94, shoulder=0.975,
    nose_taper=0.93, tail_taper=0.97, flare_f=0.06, flare_r=0.06, rear_seats=True,
    headlight=dict(w=0.32, h=0.16, x=0.66, z=1.1, wrap=0.3, up=0.0, shape="rect"),
    taillight=dict(w=0.14, h=0.32, x=0.84, z=1.35, wrap=0.6),
    grille=dict(w=0.95, h=0.24, z=1.0, slats=4), intake=dict(w=1.2, h=0.12, dz=0.18),
    extras=["roof_rack", "bull_bar", "spare_wheel"],
    exhaust=[(0.6, 0.05)], exhaust_dual=False, spoilers=[], rim_style="six",
    paint=(0.36, 0.38, 0.28), paint_metal=0.1, paint_rough=0.6, rim_color=(0.2, 0.2, 0.21), caliper=(0.3, 0.3, 0.3),
    plate_zr=0.95, plate_zf=0.62, seat_x=0.4, eye_z=1.1,
)

HAULMARK = dict(
    name="Haulmark_2500", file="haulmark_2500", L=5.6, W=2.0, wb=3.6, fo=0.95, wheel_r=0.4, wheel_w=0.28, ride=0.28,
    rim_ratio=0.6, tread_groove=0.012,
    nose_z=1.2, nose_drop=0.05, front_lift=0.16, cowl_y=1.12, cowl_z=1.36, roof_front_y=0.55, roof_z=1.92,
    roof_rear_y=-0.42, deck_y=-0.58, deck_z=1.34, tail_z=1.32, tail_drop=0.01, belt_r=1.32, belt_f=1.3,
    hood_keys=[(2.2, 1.3)], trunk_keys=[(-1.5, 1.34), (-2.5, 1.33)],
    glass_rear_y=-0.32, glass_front_y=0.85, doors=4, b_pillar_y=0.12,
    tumble=0.9, roof_crown=0.03, hood_crown=0.03, deck_round=0.96, shoulder=0.98,
    nose_taper=0.95, tail_taper=0.99, flare_f=0.04, flare_r=0.04, rear_seats=True,
    open_regions=[(-2.75, -0.7, (8, 9, 10))],
    headlight=dict(w=0.3, h=0.2, x=0.7, z=1.16, wrap=0.3, up=0.0, shape="rect"),
    taillight=dict(w=0.12, h=0.36, x=0.9, z=1.1, wrap=0.6),
    grille=dict(w=1.1, h=0.36, z=1.06, chrome=True, slats=3), intake=dict(w=1.3, h=0.12, dz=0.16),
    extras=["bed", "chrome_bumpers"], bumper_z=0.32,
    exhaust=[(0.7, 0.05)], exhaust_dual=False, spoilers=[], rim_style="five",
    paint=(0.55, 0.06, 0.06), rim_color=(0.78, 0.78, 0.8), caliper=(0.3, 0.3, 0.3), plate_zr=0.7, plate_zf=0.72,
    seat_x=0.42, eye_z=1.1, cabin_closed=True,
)

SPATZ = dict(
    name="Spatz_Roadster", file="spatz_roadster", L=3.75, W=1.52, wb=2.2, fo=0.72, wheel_r=0.3, wheel_w=0.165, ride=0.15,
    rim_ratio=0.62,
    nose_z=0.76, nose_drop=0.18, front_lift=0.12, cowl_y=0.32, cowl_z=0.9, roof_front_y=0.2, roof_z=0.93,
    roof_rear_y=-0.75, deck_y=-0.95, deck_z=0.9, tail_z=0.74, tail_drop=0.14, belt_r=0.86, belt_f=0.82,
    hood_keys=[(1.2, 0.86)], trunk_keys=[(-1.5, 0.84)],
    glass_rear_y=-0.6, glass_front_y=-0.5, doors=2, tumble=0.85, roof_crown=0.02, hood_crown=0.06,
    nose_taper=0.7, tail_taper=0.75, flare_f=0.08, flare_r=0.085, waist=0.9, black_sill=False,
    open_regions=[(-0.88, 0.22, (7, 8, 9, 10))], rear_glass=False, cabin_closed=False, mirrors=False,
    headlight=dict(w=0.17, h=0.17, x=0.5, z=0.74, wrap=0.2, up=0.1, shape="ellipse"),
    taillight=dict(w=0.09, h=0.09, x=0.5, z=0.72, wrap=0.1, shape="ellipse"),
    grille=dict(w=0.42, h=0.22, z=0.56, shape="ellipse", chrome=True, slats=5), intake=dict(w=0.0, h=0.0),
    extras=["windscreen", "chrome_bumpers"], bumper_z=0.16,
    exhaust=[(0.35, 0.02)], exhaust_dual=False, spoilers=[], rim_style="mesh",
    paint=(0.55, 0.78, 0.72), rim_color=(0.85, 0.85, 0.86), caliper=(0.25, 0.25, 0.25), plate_zr=0.5,
    seat_y=-0.4, seat_x=0.3, eye_z=0.95, dash_y=0.15,
)

CARS = [KESTREL, ARDEN, BRUTE, SORA, VALCOURT, NYX, MISTRAL, TRAILHOUND, HAULMARK, SPATZ]
