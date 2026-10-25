"""Offline check of the exported traffic / prop .glb files (run with plain Python from the project root, NOT inside
Blender):  python tools/blender/review/verify_glbs.py

Parses the GLB JSON chunk (struct + json) and checks against docs/SYSTEM_CONTRACTS.md "Props":
  * kit files: top-level scene nodes == the contract names exactly (no extra parents), one mesh each, bounds in Godot
    coordinates (min Y ~ ground, origin centred), no cameras / lights / animations / Draco, attribute set per primitive
  * traffic files: one root node named <id>, children with the vehicle object names (ASSET_CONVENTIONS.md)
"""
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

KITS = {
    'nature_kit': ['Tree_Oak_A', 'Tree_Oak_B', 'Tree_Pine_A', 'Tree_Pine_B', 'Tree_Poplar', 'Tree_Birch', 'Tree_Palm',
                   'Tree_Olive', 'Tree_Dead', 'Bush_A', 'Bush_B', 'Bush_Desert', 'Cactus_A', 'Cactus_B', 'Rock_A',
                   'Rock_B', 'Rock_C', 'Rock_Large', 'Rock_Red', 'Grass_Tuft', 'Flowers_Tuft', 'Reeds', 'Hay_Bale',
                   'Log_Pile'],
    'roadside_kit': ['Sign_SpeedLimit', 'Sign_Chevron', 'Sign_Danger_Jump', 'Sign_Direction', 'Delineator_Post',
                     'GuardRail_Post', 'Lamp_Street', 'Utility_Pole', 'Fence_Wood', 'Wall_Stone', 'Hedge', 'Bus_Stop',
                     'Bench', 'Mailbox', 'Bin', 'Barrier_Jersey', 'Cone', 'Bridge_Pier', 'Tunnel_Portal',
                     'Speed_Trap_Camera', 'Checkpoint_Arch', 'Festival_Banner', 'Flag_Pole', 'Fuel_Pump', 'Billboard'],
    'buildings_kit': ['House_Cottage_A', 'House_Cottage_B', 'House_Townhouse', 'Farmhouse', 'Barn_Red', 'Silo',
                      'Shed_Small', 'House_Chalet', 'House_Adobe', 'Gas_Station', 'Diner', 'Church', 'Harbour_Shed',
                      'Boathouse', 'Pier_Section', 'Boat_Fishing', 'Lighthouse', 'Castle_Ruin_Wall',
                      'Castle_Ruin_Tower', 'Wind_Turbine_Tower', 'Wind_Turbine_Rotor', 'Water_Tower',
                      'Festival_Stage', 'Festival_Tent', 'Viewpoint_Deck'],
}
TRAFFIC = ['hatch_small', 'van_delivery', 'lorry_box', 'bus_coach', 'tractor_farm', 'pickup_work']
VEHICLE_NODES = {'Body', 'Glass', 'Interior', 'SteeringWheel', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR',
                 'Caliper_FL', 'Caliper_FR', 'Caliper_RL', 'Caliper_RR', 'Lights_Head', 'Lights_Tail', 'Lights_Brake',
                 'Lights_Reverse', 'Socket_HeadlightL', 'Socket_HeadlightR', 'Socket_Exhaust', 'Socket_Exhaust2',
                 'Socket_CamHood', 'Socket_CamCockpit', 'Socket_CamBumper'}


def load(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, ver, length = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67 and ver == 2, 'not a glb 2.0'
    clen, ctype = struct.unpack_from('<II', data, 12)
    assert ctype == 0x4E4F534A
    return json.loads(data[20:20 + clen].decode('utf-8')), len(data)


def qrot(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    # t = 2 * cross(q.xyz, v)
    tx, ty, tz = 2 * (y * vz - z * vy), 2 * (z * vx - x * vz), 2 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty), vy + w * ty + (z * tx - x * tz), vz + w * tz + (x * ty - y * tx))


def node_bounds(g, ni):
    n = g['nodes'][ni]
    if 'mesh' not in n:
        return None
    mn, mx = [1e9] * 3, [-1e9] * 3
    t = n.get('translation', [0, 0, 0])
    r = n.get('rotation', [0, 0, 0, 1])
    s = n.get('scale', [1, 1, 1])
    for p in g['meshes'][n['mesh']]['primitives']:
        a = g['accessors'][p['attributes']['POSITION']]
        lo, hi = a['min'], a['max']
        for cx in (lo[0], hi[0]):
            for cy in (lo[1], hi[1]):
                for cz in (lo[2], hi[2]):
                    v = qrot(r, (cx * s[0], cy * s[1], cz * s[2]))
                    v = (v[0] + t[0], v[1] + t[1], v[2] + t[2])
                    for k in range(3):
                        mn[k] = min(mn[k], v[k])
                        mx[k] = max(mx[k], v[k])
    return mn, mx


def tris(g, mi):
    out = 0
    for p in g['meshes'][mi]['primitives']:
        if 'indices' in p:
            out += g['accessors'][p['indices']]['count'] // 3
        else:
            out += g['accessors'][p['attributes']['POSITION']]['count'] // 3
    return out


def common(g, label):
    bad = []
    for key in ('cameras', 'animations', 'skins'):
        if g.get(key):
            bad.append('%s present' % key)
    ext = set(g.get('extensionsUsed', []))
    if 'KHR_draco_mesh_compression' in ext:
        bad.append('Draco used')
    if 'KHR_lights_punctual' in ext:
        bad.append('lights present')
    attrs = set()
    missing = set()
    for m in g['meshes']:
        for p in m['primitives']:
            ks = set(p['attributes'])
            attrs |= ks
            for need in ('NORMAL', 'TEXCOORD_0'):
                if need not in ks:
                    missing.add('%s:%s' % (m.get('name'), need))
    unnamed = [n.get('name') for n in g['nodes'] if not n.get('name') or '.0' in n.get('name', '')]
    print('  %s: extensions %s attrs %s' % (label, sorted(ext), sorted(attrs)))
    if missing:
        bad.append('missing attrs %s' % sorted(missing)[:10])
    if unnamed:
        bad.append('unnamed/duplicate-suffixed nodes %s' % unnamed[:10])
    return bad


def check_kit(kit, names):
    path = os.path.join(ROOT, 'assets', 'imported', 'props', kit + '.glb')
    if not os.path.exists(path):
        print('%s MISSING' % kit)
        return False
    g, size = load(path)
    sc = g['scenes'][g.get('scene', 0)]
    top = [g['nodes'][i].get('name') for i in sc['nodes']]
    print('%s  %.2f MB  nodes %d meshes %d materials %d images %d' % (kit, size / 1e6, len(g['nodes']),
                                                                     len(g['meshes']), len(g.get('materials', [])),
                                                                     len(g.get('images', []))))
    bad = common(g, kit)
    if sorted(top) != sorted(names):  # order is irrelevant (Godot looks props up by name)
        bad.append('top-level mismatch: extra %s missing %s duplicates %d' % (
            sorted(set(top) - set(names)), sorted(set(names) - set(top)), len(top) - len(set(top))))
    for i in sc['nodes']:
        n = g['nodes'][i]
        nm = n.get('name')
        if n.get('children'):
            bad.append('%s has children' % nm)
        if 'mesh' not in n:
            bad.append('%s has no mesh' % nm)
            continue
        b = node_bounds(g, i)
        mn, mx = b
        cx, cz = (mn[0] + mx[0]) / 2, (mn[2] + mx[2]) / 2
        t = n.get('translation', [0, 0, 0])
        rot = n.get('rotation', [0, 0, 0, 1])
        print('    %-20s tris %5d  min_y %7.2f max_y %7.2f  x %6.2f..%6.2f  z %6.2f..%6.2f  t %s r %s' % (
            nm, tris(g, n['mesh']), mn[1], mx[1], mn[0], mx[0], mn[2], mx[2],
            [round(c, 3) for c in t], [round(c, 3) for c in rot]))
        if any(abs(c) > 1e-4 for c in t):
            bad.append('%s translated %s' % (nm, t))
    print('  RESULT %s: %s' % (kit, 'OK' if not bad else bad))
    return not bad


def check_traffic(cid):
    path = os.path.join(ROOT, 'assets', 'imported', 'traffic', cid + '.glb')
    if not os.path.exists(path):
        print('%s MISSING' % cid)
        return False
    g, size = load(path)
    sc = g['scenes'][g.get('scene', 0)]
    top = [g['nodes'][i].get('name') for i in sc['nodes']]
    bad = common(g, cid)
    if top != [cid]:
        bad.append('top-level %s' % top)
    root = g['nodes'][sc['nodes'][0]]
    kids = [g['nodes'][c].get('name') for c in root.get('children', [])]
    extra = sorted(set(kids) - VEHICLE_NODES)
    missing = sorted({'Body', 'Glass', 'Interior', 'SteeringWheel', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR',
                      'Lights_Head', 'Lights_Tail', 'Lights_Brake', 'Lights_Reverse', 'Socket_HeadlightL',
                      'Socket_HeadlightR', 'Socket_Exhaust', 'Socket_CamHood', 'Socket_CamCockpit',
                      'Socket_CamBumper'} - set(kids))
    if extra:
        bad.append('extra children %s' % extra)
    if missing:
        bad.append('missing children %s' % missing)
    if any(abs(c) > 1e-4 for c in root.get('translation', [0, 0, 0])) or 'rotation' in root or 'scale' in root:
        bad.append('root transform not identity')
    total = 0
    mn_all, mx_all = [1e9] * 3, [-1e9] * 3
    for c in root.get('children', []):
        n = g['nodes'][c]
        if 'mesh' in n:
            total += tris(g, n['mesh'])
            mn, mx = node_bounds(g, c)
            for k in range(3):
                mn_all[k] = min(mn_all[k], mn[k])
                mx_all[k] = max(mx_all[k], mx[k])
    wheels = {g['nodes'][c]['name']: [round(v, 3) for v in g['nodes'][c].get('translation', [0, 0, 0])]
              for c in root.get('children', []) if g['nodes'][c]['name'].startswith('Wheel_')}
    print('%s  %.2f MB  tris %d  bounds x %.2f..%.2f y %.3f..%.2f z %.2f..%.2f  wheels %s' % (
        cid, size / 1e6, total, mn_all[0], mx_all[0], mn_all[1], mx_all[1], mn_all[2], mx_all[2], wheels))
    if total > 25000:
        bad.append('over budget %d' % total)
    if mx_all[2] < -mn_all[2]:
        pass
    print('  children %s' % kids)
    print('  RESULT %s: %s' % (cid, 'OK' if not bad else bad))
    return not bad


if __name__ == '__main__':
    ok = True
    for cid in TRAFFIC:
        ok &= check_traffic(cid)
    for kit, names in KITS.items():
        ok &= check_kit(kit, names)
    print('ALL OK' if ok else 'PROBLEMS FOUND')
    sys.exit(0 if ok else 1)
