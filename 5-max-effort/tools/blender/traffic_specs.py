"""Traffic vehicle specs (simpler than player cars, cheaper subdivision). Built with carkit
(lofted bodies) except the tractor, which traffic_kit builds from parts."""
import bmesh
import bpy
from mathutils import Vector

import kit_common as K
from car_specs import _wheels, door_lines

SPECS = {}


def _pickup_bed(spec, body, col, mats):
    """Hollow out the pickup bed with a boolean so it has floor and side walls."""
    bm = K.rounded_box_bm((spec["bed_w"], spec["bed_len"], 0.9), (0.0, spec["bed_y"], spec["bed_floor"] + 0.45), 0.03, 1)
    cutter = K.mesh_object("_bedcut", bm, col)
    mod = body.modifiers.new("Bed", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    try:
        mod.solver = "EXACT"
    except Exception:
        pass
    K.apply_modifiers(body)
    bpy.data.objects.remove(cutter, do_unlink=True)


SPECS["t_compact"] = _wheels({
    "id": "t_compact", "collection": "Traffic", "paint": (0.1, 0.25, 0.6), "subdiv": 1, "station_step": 0.16,
    "y_rear": -1.85, "y_front": 2.05, "wheelbase": 2.45, "track_front": 1.46, "track_rear": 1.45,
    "wheel_radius": 0.295, "wheel_width": 0.2, "rim_ratio": 0.62, "rim_style": "steel", "rim_material": "Rim",
    "top": [(-1.85, 0.95), (-1.8, 1.08), (-1.7, 1.3), (-1.5, 1.43), (-1.0, 1.47), (0.0, 1.47), (0.35, 1.43),
            (0.62, 1.22), (0.92, 1.0), (1.3, 0.93), (1.7, 0.86), (1.95, 0.76), (2.05, 0.62)],
    "shoulder": [(-1.85, 0.9), (-1.4, 0.96), (0.0, 0.95), (0.92, 0.9), (1.6, 0.83), (2.05, 0.6)],
    "bottom": [(-1.85, 0.38), (-1.7, 0.23), (-1.2, 0.17), (1.2, 0.17), (1.85, 0.22), (2.05, 0.3)],
    "halfwidth": [(-1.85, 0.72), (-1.75, 0.82), (-1.4, 0.85), (0.5, 0.85), (1.4, 0.84), (1.85, 0.78), (2.05, 0.62)],
    "cabin": {"ws_base": 0.92, "ws_top": 0.34, "rw_top": -1.5, "rw_base": -1.8, "sw_front": 0.66, "sw_rear": -1.42},
    "b_pillars": [-0.25, -1.15], "roof_ratio": 0.8, "crown": 0.03, "rear_seats": True, "floor_z": 0.27,
    "features": [
        {"kind": "lamp", "name": "Lights_Head", "mat": "LightHead", "center": (0.58, 1.98, 0.72), "size": (0.32, 0.13), "dir": (-0.4, -1, -0.15)},
        {"kind": "patch", "name": "Grille", "mat": "Grille", "center": (0, 2.06, 0.55), "size": (0.6, 0.11), "dir": (0, -1, 0), "mirror": False},
        {"kind": "patch", "name": "Plate_Front", "mat": "Plate", "center": (0, 2.08, 0.42), "size": (0.44, 0.09), "dir": (0, -1, 0), "mirror": False, "thick": 0.006},
        {"kind": "lamp", "name": "Lights_Tail", "mat": "LightTail", "center": (0.66, -1.85, 0.98), "size": (0.18, 0.22), "dir": (-0.4, 1, 0)},
        {"kind": "patch", "name": "Plate_Rear", "mat": "Plate", "center": (0, -1.88, 0.7), "size": (0.44, 0.1), "dir": (0, 1, 0), "mirror": False, "thick": 0.006},
        {"kind": "patch", "name": "Bumper_Rear", "mat": "TrimMatte", "center": (0, -1.88, 0.42), "size": (1.3, 0.12), "shape": "slim", "dir": (0, 1, 0), "mirror": False},
        {"kind": "box", "name": "Mirror_Housing", "mat": "TrimMatte", "center": (0.9, 0.72, 1.0), "size": (0.09, 0.12, 0.08), "bevel": 0.02, "mirror": True},
    ] + door_lines(1.2, 0.55, -0.27, 0.3, 0.92) + [
        {"kind": "strip", "name": "PanelGap_RearDoor", "mat": "Trim", "dir": (-1, 0, 0), "width": 0.005,
         "points": [(1.2, -1.15, 0.3), (1.2, -1.12, 0.6), (1.2, -1.1, 0.92)]}],
    "empties": [("LIGHT_Head_L", (-0.58, 2.02, 0.72)), ("LIGHT_Head_R", (0.58, 2.02, 0.72))],
})

SPECS["t_pickup"] = _wheels({
    "id": "t_pickup", "collection": "Traffic", "paint": (0.85, 0.85, 0.85), "subdiv": 1, "station_step": 0.16,
    "y_rear": -2.75, "y_front": 2.55, "wheelbase": 3.3, "track_front": 1.7, "track_rear": 1.7,
    "wheel_radius": 0.38, "wheel_width": 0.25, "rim_ratio": 0.6, "rim_style": "steel", "rim_material": "Rim",
    "top": [(-2.75, 1.2), (-0.66, 1.2), (-0.6, 1.5), (-0.55, 1.83), (-0.3, 1.88), (0.55, 1.88), (0.8, 1.78),
            (1.2, 1.36), (1.4, 1.32), (2.1, 1.25), (2.45, 1.15), (2.55, 0.92)],
    "shoulder": [(-2.75, 1.12), (-0.6, 1.14), (0.5, 1.16), (1.3, 1.2), (2.1, 1.15), (2.55, 0.86)],
    "bottom": [(-2.75, 0.6), (-2.6, 0.5), (-1.8, 0.47), (1.8, 0.47), (2.45, 0.5), (2.55, 0.58)],
    "halfwidth": [(-2.75, 0.92), (-2.6, 0.98), (2.1, 0.98), (2.45, 0.94), (2.55, 0.85)],
    "flare": [(-2.75, 0.0), (-2.2, 0.0), (-1.65, 0.03), (-1.1, 0.0), (1.1, 0.0), (1.65, 0.03), (2.2, 0.0), (2.55, 0.0)],
    "cabin": {"ws_base": 1.28, "ws_top": 0.8, "rw_top": -0.54, "rw_base": -0.62, "sw_front": 1.08, "sw_rear": -0.45},
    "extra_stations": [-0.66, -0.6, -0.55], "b_pillars": [0.18], "roof_ratio": 0.88, "glass_base_ratio": 0.96,
    "crown": 0.02, "rear_seats": True, "floor_z": 0.62, "seat_h": 0.2, "eye_h": 0.75, "hull_floor": 0.45,
    "bed_w": 1.72, "bed_len": 1.9, "bed_y": -1.66, "bed_floor": 0.72,
    "post_body": _pickup_bed,
    "features": [
        {"kind": "lamp", "name": "Lights_Head", "mat": "LightHead", "center": (0.72, 2.55, 1.0), "size": (0.3, 0.2), "dir": (0, -1, 0)},
        {"kind": "patch", "name": "Grille", "mat": "Chrome", "center": (0, 2.56, 0.98), "size": (0.95, 0.32), "dir": (0, -1, 0), "mirror": False},
        {"kind": "patch", "name": "Grille_Inner", "mat": "Grille", "center": (0, 2.57, 0.98), "size": (0.85, 0.24), "dir": (0, -1, 0), "mirror": False, "offset": 0.008},
        {"kind": "box", "name": "Bumper_Front", "mat": "Chrome", "center": (0, 2.6, 0.62), "size": (1.9, 0.18, 0.2), "bevel": 0.04},
        {"kind": "box", "name": "Bumper_Rear", "mat": "Chrome", "center": (0, -2.8, 0.62), "size": (1.9, 0.16, 0.18), "bevel": 0.04},
        {"kind": "lamp", "name": "Lights_Tail", "mat": "LightTail", "center": (0.86, -2.76, 1.0), "size": (0.12, 0.3), "dir": (0, 1, 0)},
        {"kind": "patch", "name": "Plate_Rear", "mat": "Plate", "center": (0, -2.79, 0.86), "size": (0.44, 0.1), "dir": (0, 1, 0), "mirror": False, "thick": 0.006},
        {"kind": "box", "name": "Mirror_Housing", "mat": "TrimMatte", "center": (1.06, 1.05, 1.35), "size": (0.08, 0.16, 0.24), "bevel": 0.02, "mirror": True},
        {"kind": "box", "name": "SideStep", "mat": "TrimMatte", "center": (1.0, 0.3, 0.5), "size": (0.16, 1.6, 0.05), "bevel": 0.01, "mirror": True},
    ] + door_lines(1.3, 0.95, -0.55, 0.55, 1.18),
    "empties": [("LIGHT_Head_L", (-0.72, 2.6, 1.0)), ("LIGHT_Head_R", (0.72, 2.6, 1.0))],
})

SPECS["t_van"] = _wheels({
    "id": "t_van", "collection": "Traffic", "paint": (0.92, 0.92, 0.9), "subdiv": 1, "station_step": 0.18,
    "y_rear": -2.6, "y_front": 2.7, "wheelbase": 3.3, "track_front": 1.72, "track_rear": 1.72,
    "wheel_radius": 0.35, "wheel_width": 0.22, "rim_ratio": 0.6, "rim_style": "steel", "rim_material": "Rim",
    "top": [(-2.6, 2.28), (-2.52, 2.33), (-1.0, 2.35), (0.9, 2.34), (1.15, 2.26), (1.5, 1.78), (1.78, 1.38),
            (2.2, 1.26), (2.55, 1.12), (2.7, 0.9)],
    "shoulder": [(-2.6, 1.12), (1.4, 1.14), (2.0, 1.1), (2.7, 0.84)],
    "bottom": [(-2.6, 0.52), (-2.45, 0.4), (2.4, 0.4), (2.7, 0.5)],
    "halfwidth": [(-2.6, 0.95), (-2.5, 1.0), (2.0, 1.0), (2.45, 0.96), (2.7, 0.84)],
    "cabin": {"ws_base": 1.78, "ws_top": 1.08, "rw_top": -2.5, "rw_base": -2.58, "sw_front": 1.52, "sw_rear": 0.52},
    "rear_window": False, "roof_ratio": 0.94, "glass_base_ratio": 0.985, "crown": 0.03, "floor_z": 0.55,
    "seat_h": 0.25, "eye_h": 0.8, "dash_depth": 0.36, "seat_y": 0.35, "hull_floor": 0.4,
    "features": [
        {"kind": "lamp", "name": "Lights_Head", "mat": "LightHead", "center": (0.7, 2.66, 0.98), "size": (0.3, 0.17), "dir": (-0.2, -1, 0)},
        {"kind": "patch", "name": "Grille", "mat": "Grille", "center": (0, 2.7, 0.9), "size": (0.95, 0.22), "dir": (0, -1, 0), "mirror": False},
        {"kind": "patch", "name": "Bumper_Front", "mat": "TrimMatte", "center": (0, 2.72, 0.58), "size": (1.85, 0.2), "shape": "slim", "dir": (0, -1, 0), "mirror": False},
        {"kind": "patch", "name": "Plate_Front", "mat": "Plate", "center": (0, 2.74, 0.6), "size": (0.44, 0.1), "dir": (0, -1, 0), "mirror": False, "thick": 0.006},
        {"kind": "lamp", "name": "Lights_Tail", "mat": "LightTail", "center": (0.9, -2.6, 1.15), "size": (0.12, 0.38), "dir": (0, 1, 0)},
        {"kind": "patch", "name": "Bumper_Rear", "mat": "TrimMatte", "center": (0, -2.62, 0.56), "size": (1.85, 0.18), "shape": "slim", "dir": (0, 1, 0), "mirror": False},
        {"kind": "patch", "name": "Plate_Rear", "mat": "Plate", "center": (0, -2.63, 0.78), "size": (0.44, 0.1), "dir": (0, 1, 0), "mirror": False, "thick": 0.006},
        {"kind": "strip", "name": "RearDoorGap", "mat": "Trim", "dir": (0, 1, 0), "width": 0.008, "mirror": False,
         "points": [(0.0, -3.2, 0.5), (0.0, -3.2, 1.3), (0.0, -3.2, 2.2)]},
        {"kind": "strip", "name": "SlideDoorGap", "mat": "Trim", "dir": (-1, 0, 0), "width": 0.008,
         "points": [(1.4, 0.45, 0.45), (1.4, 0.45, 1.3), (1.4, 0.45, 2.1), (1.4, -0.75, 2.1), (1.4, -0.75, 1.3), (1.4, -0.75, 0.45)]},
        {"kind": "box", "name": "Mirror_Housing", "mat": "TrimMatte", "center": (1.1, 1.55, 1.35), "size": (0.08, 0.14, 0.28), "bevel": 0.02, "mirror": True},
    ] + door_lines(1.3, 1.45, 0.55, 0.45, 1.12),
    "empties": [("LIGHT_Head_L", (-0.7, 2.7, 0.98)), ("LIGHT_Head_R", (0.7, 2.7, 0.98))],
})

SPECS["t_lorry"] = _wheels({
    "id": "t_lorry", "collection": "Traffic", "paint": (0.9, 0.9, 0.88), "subdiv": 1, "station_step": 0.2,
    "y_rear": 1.25, "y_front": 3.75, "wheelbase": 4.6, "track_front": 2.0, "track_rear": 1.85,
    "wheel_radius": 0.5, "wheel_width": 0.3, "wheel_width_rear": 0.5, "rim_ratio": 0.55, "rim_style": "steel",
    "rim_material": "Rim", "arch_clearance": 0.06,
    "top": [(1.25, 2.7), (1.32, 2.86), (2.6, 2.88), (2.95, 2.78), (3.3, 2.25), (3.6, 1.62), (3.72, 1.35), (3.75, 1.02)],
    "shoulder": [(1.25, 1.58), (3.45, 1.58), (3.75, 1.0)],
    "bottom": [(1.25, 0.78), (3.55, 0.72), (3.75, 0.78)],
    "halfwidth": [(1.25, 1.12), (1.35, 1.2), (3.45, 1.22), (3.75, 1.1)],
    "cabin": {"ws_base": 3.55, "ws_top": 2.98, "rw_top": 1.36, "rw_base": 1.3, "sw_front": 3.42, "sw_rear": 2.05},
    "rear_window": False, "roof_ratio": 0.95, "glass_base_ratio": 0.99, "crown": 0.03, "floor_z": 0.9,
    "seat_h": 0.3, "eye_h": 0.85, "dash_depth": 0.4, "seat_y": 2.45, "seat_x": 0.5, "hull_floor": 0.7,
    "hull_extra": [(-1.25, -4.0, 1.1), (1.25, -4.0, 1.1), (-1.25, -4.0, 3.7), (1.25, -4.0, 3.7),
                   (-1.25, 1.15, 1.1), (1.25, 1.15, 1.1), (-1.25, 1.15, 3.7), (1.25, 1.15, 3.7)],
    "features": [
        {"kind": "box", "name": "CargoBox", "mat": "Paint", "center": (0, -1.42, 2.4), "size": (2.5, 5.1, 2.6), "bevel": 0.05},
        {"kind": "box", "name": "CargoFrame", "mat": "TrimMatte", "center": (0, -1.42, 1.08), "size": (2.4, 5.1, 0.12), "bevel": 0.01},
        {"kind": "box", "name": "Chassis", "mat": "Under", "center": (0, -0.3, 0.86), "size": (0.95, 7.3, 0.3), "bevel": 0.02},
        {"kind": "box", "name": "RearUnderrun", "mat": "TrimMatte", "center": (0, -3.95, 0.62), "size": (2.3, 0.12, 0.14), "bevel": 0.01},
        {"kind": "box", "name": "FuelTank", "mat": "Chrome", "center": (0.95, -0.2, 0.9), "size": (0.5, 1.0, 0.5), "bevel": 0.18},
        {"kind": "box", "name": "Mudguard_Rear", "mat": "TrimMatte", "center": (1.05, -2.3, 1.15), "size": (0.55, 1.3, 0.06), "bevel": 0.01, "mirror": True},
        {"kind": "lamp", "name": "Lights_Head", "mat": "LightHead", "center": (0.82, 3.74, 1.05), "size": (0.34, 0.18), "dir": (0, -1, 0)},
        {"kind": "patch", "name": "Grille", "mat": "Grille", "center": (0, 3.76, 1.35), "size": (1.5, 0.5), "dir": (0, -1, 0), "mirror": False},
        {"kind": "box", "name": "Bumper_Front", "mat": "TrimMatte", "center": (0, 3.82, 0.82), "size": (2.35, 0.2, 0.32), "bevel": 0.03},
        {"kind": "box", "name": "Lights_Tail", "mat": "LightTail", "center": (0.95, -4.0, 0.68), "size": (0.3, 0.06, 0.14), "bevel": 0.01, "mirror": True},
        {"kind": "box", "name": "Mirror_Housing", "mat": "TrimMatte", "center": (1.32, 3.1, 2.1), "size": (0.08, 0.16, 0.38), "bevel": 0.02, "mirror": True},
        {"kind": "box", "name": "CargoDoorGap", "mat": "Trim", "center": (0, -3.975, 2.4), "size": (0.025, 0.02, 2.45), "bevel": 0.0},
        {"kind": "box", "name": "CargoDoorHandles", "mat": "Chrome", "center": (0.2, -3.985, 2.0), "size": (0.04, 0.03, 0.9), "bevel": 0.008, "mirror": True},
    ],
    "empties": [("LIGHT_Head_L", (-0.82, 3.8, 1.05)), ("LIGHT_Head_R", (0.82, 3.8, 1.05)),
                ("CAM_Hood", (0.0, 3.5, 3.1))],
})

SPECS["t_bus"] = _wheels({
    "id": "t_bus", "collection": "Traffic", "paint": (0.95, 0.6, 0.1), "subdiv": 1, "station_step": 0.3,
    "y_rear": -5.8, "y_front": 5.8, "wheelbase": 6.6, "track_front": 2.1, "track_rear": 2.0,
    "wheel_radius": 0.52, "wheel_width": 0.3, "wheel_width_rear": 0.5, "rim_ratio": 0.55, "rim_style": "steel",
    "rim_material": "Rim", "arch_clearance": 0.07,
    "top": [(-5.8, 3.2), (-5.72, 3.38), (-5.3, 3.45), (5.1, 3.45), (5.45, 3.34), (5.68, 2.9), (5.78, 1.9), (5.8, 1.1)],
    "shoulder": [(-5.8, 1.32), (5.3, 1.28), (5.6, 1.15), (5.8, 1.0)],
    "bottom": [(-5.8, 0.55), (-5.55, 0.42), (5.5, 0.42), (5.8, 0.5)],
    "halfwidth": [(-5.8, 1.18), (-5.6, 1.27), (5.5, 1.27), (5.8, 1.16)],
    "cabin": {"ws_base": 5.79, "ws_top": 5.35, "rw_top": -5.3, "rw_base": -5.75, "sw_front": 5.25, "sw_rear": -5.05},
    "extra_stations": [5.6, 5.7], "b_pillars": [-3.6, -2.0, -0.4, 1.2, 2.8, 4.25], "black_pillars": True,
    "roof_ratio": 0.965, "glass_base_ratio": 0.99, "crown": 0.05, "floor_z": 0.75, "seat_h": 0.35,
    "eye_h": 0.85, "dash_depth": 0.45, "seat_y": 4.6, "seat_x": 0.65, "rear_seats": False, "hull_floor": 0.45,
    "features": [
        {"kind": "lamp", "name": "Lights_Head", "mat": "LightHead", "center": (0.85, 5.8, 0.85), "size": (0.36, 0.16), "dir": (0, -1, 0)},
        {"kind": "patch", "name": "DestinationSign", "mat": "LightIndicator", "center": (0, 5.82, 3.15), "size": (1.6, 0.22), "dir": (0, -1, 0), "mirror": False},
        {"kind": "patch", "name": "Bumper_Front", "mat": "TrimMatte", "center": (0, 5.82, 0.6), "size": (2.3, 0.24), "shape": "slim", "dir": (0, -1, 0), "mirror": False},
        {"kind": "patch", "name": "Grille", "mat": "Grille", "center": (0, 5.82, 0.95), "size": (1.0, 0.18), "dir": (0, -1, 0), "mirror": False},
        {"kind": "lamp", "name": "Lights_Tail", "mat": "LightTail", "center": (1.0, -5.8, 1.2), "size": (0.16, 0.5), "dir": (0, 1, 0)},
        {"kind": "patch", "name": "EngineGrille", "mat": "Grille", "center": (0, -5.82, 0.95), "size": (1.6, 0.45), "dir": (0, 1, 0), "mirror": False},
        {"kind": "patch", "name": "Plate_Rear", "mat": "Plate", "center": (0, -5.83, 0.55), "size": (0.44, 0.1), "dir": (0, 1, 0), "mirror": False, "thick": 0.006},
        {"kind": "strip", "name": "DoorGap", "mat": "Trim", "dir": (-1, 0, 0), "width": 0.01, "mirror": False,
         "points": [(1.6, 5.15, 0.45), (1.6, 5.15, 2.9), (1.6, 4.25, 2.9), (1.6, 4.25, 0.45)]},
        {"kind": "box", "name": "Mirror_Arm", "mat": "TrimMatte", "center": (1.35, 5.7, 2.6), "size": (0.25, 0.06, 0.06), "bevel": 0.01, "mirror": True},
        {"kind": "box", "name": "Mirror_Housing", "mat": "TrimMatte", "center": (1.45, 5.82, 2.25), "size": (0.08, 0.14, 0.42), "bevel": 0.02, "mirror": True},
        {"kind": "box", "name": "SkirtStripe", "mat": "TrimMatte", "center": (1.27, 0.0, 0.62), "size": (0.02, 9.0, 0.18), "bevel": 0.005, "mirror": True},
    ],
    "empties": [("LIGHT_Head_L", (-0.85, 5.85, 0.85)), ("LIGHT_Head_R", (0.85, 5.85, 0.85))],
})
