"""Builders for vehicles that are not lofted bodies (farm tractor)."""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import carkit
import kit_common as K


def _fender(radius, width, x, y, z, a0=-15, a1=195, thick=0.02, segs=16):
    """Arched mud-guard shell over a wheel (axis X)."""
    bm = bmesh.new()
    inner, outer = [], []
    for s in range(segs + 1):
        a = math.radians(a0 + (a1 - a0) * s / segs)
        for side, lst in ((-1, inner), (1, outer)):
            pass
    rows = []
    for s in range(segs + 1):
        a = math.radians(a0 + (a1 - a0) * s / segs)
        cy = math.cos(a) * radius
        cz = math.sin(a) * radius
        rows.append([bm.verts.new((x - width / 2, y + cy, z + cz)), bm.verts.new((x + width / 2, y + cy, z + cz))])
    for s in range(segs):
        f = bm.faces.new((rows[s][0], rows[s][1], rows[s + 1][1], rows[s + 1][0]))
    # side flange
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=thick)
    bm.normal_update()
    return bm


def build_tractor(export_path=None):
    K.guard()
    parent = K.sub_collection("Traffic")
    col_name = "CAR_t_tractor"
    col = bpy.data.collections.get(col_name)
    if col is not None:
        K.clear_collection(col)
    col = K.collection(col_name, parent)
    mats = K.std_materials((0.15, 0.5, 0.15))
    objs = []

    def part(name, bm, mat, smooth=40):
        o = K.mesh_object(name, bm, col, [mats[mat]])
        K.shade_auto(o, smooth)
        objs.append(o)
        return o

    # engine block, hood, grille
    part("Body", K.rounded_box_bm((0.78, 1.75, 0.62), (0, 0.95, 1.38), 0.08, 3), "Paint")
    part("EngineBlock", K.rounded_box_bm((0.62, 1.6, 0.42), (0, 0.85, 0.92), 0.04, 2), "Under")
    part("Grille", K.rounded_box_bm((0.66, 0.06, 0.48), (0, 1.84, 1.36), 0.02, 1), "Grille")
    lights = K.rounded_box_bm((0.16, 0.06, 0.1), (0.24, 1.86, 1.62), 0.02, 1)
    K.join_bm(lights, K.rounded_box_bm((0.16, 0.06, 0.1), (-0.24, 1.86, 1.62), 0.02, 1))
    part("Lights_Head", lights, "LightHead")
    part("FrontAxle", K.rounded_box_bm((1.42, 0.14, 0.14), (0, 1.2, 0.47), 0.03, 1), "Under")
    part("FrontWeights", K.rounded_box_bm((0.7, 0.3, 0.3), (0, 1.95, 0.85), 0.05, 2), "TrimMatte")
    # cab
    part("CabFloor", K.rounded_box_bm((1.3, 1.15, 0.12), (0, -0.55, 1.08), 0.02, 1), "TrimMatte")
    posts = bmesh.new()
    for px in (-0.58, 0.58):
        for py in (-0.02, -1.08):
            K.join_bm(posts, K.cylinder_bm(0.035, 1.6, 10, "Z", (px, py, 1.9)))
    part("CabPosts", posts, "TrimMatte")
    part("CabRoof", K.rounded_box_bm((1.32, 1.24, 0.1), (0, -0.55, 2.72), 0.04, 2), "Paint")
    glass = bmesh.new()
    K.join_bm(glass, K.rounded_box_bm((1.12, 0.02, 1.2), (0, 0.0, 2.0), 0.0, 1))
    K.join_bm(glass, K.rounded_box_bm((1.12, 0.02, 1.2), (0, -1.1, 2.0), 0.0, 1))
    K.join_bm(glass, K.rounded_box_bm((0.02, 1.02, 1.2), (0.6, -0.55, 2.0), 0.0, 1))
    K.join_bm(glass, K.rounded_box_bm((0.02, 1.02, 1.2), (-0.6, -0.55, 2.0), 0.0, 1))
    part("Glass", glass, "Glass", 10)
    # seat, wheel, levers
    seat = K.rounded_box_bm((0.5, 0.45, 0.12), (0, -0.62, 1.4), 0.04, 2)
    back = K.rounded_box_bm((0.5, 0.1, 0.5), (0, -0.86, 1.68), 0.04, 2)
    K.join_bm(seat, back)
    part("Interior", seat, "Seat")
    sw = bmesh.new()
    segs = 24
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ring = []
        for j in range(6):
            b = 2 * math.pi * j / 6
            r = 0.2 + math.cos(b) * 0.015
            ring.append(sw.verts.new((r * math.cos(a), math.sin(b) * 0.015, r * math.sin(a))))
        rings.append(ring)
    for i in range(segs):
        for j in range(6):
            sw.faces.new((rings[i][j], rings[(i + 1) % segs][j], rings[(i + 1) % segs][(j + 1) % 6], rings[i][(j + 1) % 6]))
    K.join_bm(sw, K.cylinder_bm(0.025, 0.55, 8, "Y", (0, 0.28, 0)))
    steer = K.mesh_object("SteeringWheel", sw, col, [mats["Dash"]])
    K.shade_auto(steer, 40)
    steer.rotation_euler = (math.radians(35), 0, 0)
    steer.location = (0, -0.2, 1.9)
    objs.append(steer)
    # fenders, exhaust, hitch, tail lights
    fb = _fender(0.9, 0.55, 0.88, -1.2, 0.82, -5, 185, 0.025, 18)
    K.join_bm(fb, _fender(0.9, 0.55, -0.88, -1.2, 0.82, -5, 185, 0.025, 18))
    part("Fenders_Rear", fb, "Paint", 30)
    ff = _fender(0.55, 0.36, 0.75, 1.2, 0.47, 20, 160, 0.02, 12)
    K.join_bm(ff, _fender(0.55, 0.36, -0.75, 1.2, 0.47, 20, 160, 0.02, 12))
    part("Fenders_Front", ff, "Paint", 30)
    ex = K.cylinder_bm(0.05, 1.25, 12, "Z", (0.3, 1.35, 2.15))
    K.join_bm(ex, K.cylinder_bm(0.065, 0.1, 12, "Z", (0.3, 1.35, 2.8)))
    part("Exhaust", ex, "Exhaust")
    hitch = K.rounded_box_bm((0.9, 0.35, 0.18), (0, -1.75, 0.75), 0.03, 1)
    K.join_bm(hitch, K.rounded_box_bm((0.08, 0.6, 0.08), (0.35, -1.95, 0.6), 0.02, 1))
    K.join_bm(hitch, K.rounded_box_bm((0.08, 0.6, 0.08), (-0.35, -1.95, 0.6), 0.02, 1))
    part("Hitch", hitch, "Under")
    tl = K.rounded_box_bm((0.12, 0.04, 0.08), (0.95, -1.95, 1.45), 0.01, 1)
    K.join_bm(tl, K.rounded_box_bm((0.12, 0.04, 0.08), (-0.95, -1.95, 1.45), 0.01, 1))
    part("Lights_Tail", tl, "LightTail")
    part("Plate_Rear", K.rounded_box_bm((0.34, 0.02, 0.1), (0, -1.94, 1.05), 0.0, 1), "Plate")
    # wheels: small steered front, big lugged rear
    spec = {"wheel_radius_front": 0.47, "wheel_radius_rear": 0.82, "wheel_width_front": 0.28, "wheel_width_rear": 0.46,
            "rim_ratio": 0.52, "rim_style": "steel", "rim_material": "Paint", "tread": "lug", "tire_segments": 44,
            "sidewall": 0.03}
    for key, (x, y) in (("FL", (-0.75, 1.2)), ("FR", (0.75, 1.2)), ("RL", (-0.88, -1.2)), ("RR", (0.88, -1.2))):
        r = spec["wheel_radius_front"] if key.startswith("F") else spec["wheel_radius_rear"]
        w, cal = carkit.build_wheel(spec, key, (x, y, r), col, mats)
        objs += [w, cal]
    # collision hull
    hb = bmesh.new()
    for p in [(-0.95, -2.0, 0.35), (0.95, -2.0, 0.35), (-0.95, -2.0, 2.75), (0.95, -2.0, 2.75),
              (-0.7, 2.05, 0.4), (0.7, 2.05, 0.4), (-0.45, 2.0, 1.7), (0.45, 2.0, 1.7), (-0.7, 0.0, 2.78), (0.7, 0.0, 2.78)]:
        hb.verts.new(p)
    bmesh.ops.convex_hull(hb, input=hb.verts)
    hull = K.mesh_object("Collision_Hull", hb, col)
    hull.display_type = "WIRE"
    colcol = K.sub_collection("Collision")
    if hull.name not in colcol.objects:
        colcol.objects.link(hull)
    K.empty("CAM_Cockpit", col, (0.0, -0.6, 2.25))
    K.empty("CAM_Hood", col, (0.0, 0.6, 2.4))
    K.empty("CAM_Bumper", col, (0.0, 2.1, 0.9))
    K.empty("LIGHT_Head_L", col, (-0.24, 1.9, 1.62))
    K.empty("LIGHT_Head_R", col, (0.24, 1.9, 1.62))
    for o in col.objects:
        if o.type == "MESH":
            K.box_uv(o)
    if export_path:
        K.export_glb(list(col.objects), export_path)
    hull.hide_set(True)
    return col
