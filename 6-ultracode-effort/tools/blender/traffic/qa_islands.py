"""QA: floating-part check for the traffic vehicles.

Splits every mesh of each Traffic_<id> collection (except the wheels / calipers, which hang on their axles) into
connected islands and reports islands whose bounding box does not touch (within TOL) the box of any other island of
the same vehicle - i.e. parts that would float. Run inside Blender (execute_blender_code), globals: IDS, TOL.
"""
import bpy
import bmesh
from mathutils import Vector

IDS = globals().get('IDS', ['hatch_small', 'van_delivery', 'lorry_box', 'bus_coach', 'tractor_farm', 'pickup_work'])
TOL = globals().get('TOL', 0.012)


def islands(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    parent = list(range(len(bm.verts)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in bm.edges:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b:
            parent[a] = b
    M = ob.matrix_world
    boxes = {}
    for v in bm.verts:
        r = find(v.index)
        p = M @ v.co
        if r not in boxes:
            boxes[r] = [p.copy(), p.copy(), 0]
        mn, mx, n = boxes[r]
        for k in range(3):
            mn[k] = min(mn[k], p[k])
            mx[k] = max(mx[k], p[k])
        boxes[r][2] = n + 1
    bm.free()
    return [(ob.name, mn, mx, n) for (mn, mx, n) in boxes.values()]


def touch(a, b, tol):
    return all(a[1][k] - tol <= b[2][k] and b[1][k] - tol <= a[2][k] for k in range(3))


for cid in IDS:
    col = bpy.data.collections.get('Traffic_' + cid)
    if col is None:
        print(cid, 'missing')
        continue
    isl = []
    for ob in col.objects:
        if ob.type != 'MESH' or ob.name.startswith(('Wheel_', 'Caliper_', 'QA_')):
            continue
        isl += islands(ob)
    floating = []
    for i, a in enumerate(isl):
        if not any(touch(a, b, TOL) for j, b in enumerate(isl) if j != i):
            floating.append((a[0].split('__')[0], tuple(round(c, 3) for c in a[1]), tuple(round(c, 3) for c in a[2]), a[3]))
    print(cid, 'islands', len(isl), 'floating', len(floating), floating[:8])
