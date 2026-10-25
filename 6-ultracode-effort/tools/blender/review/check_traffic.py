"""Review pass: read-only checks of the traffic vehicles (SUNWARD_GODOT/Traffic/Traffic_<id>) inside Blender.

Per vehicle: evaluated triangles vs the 25000 budget, root transform, wheel origins (identity rotation/scale, origin
at the axle centre = mesh bbox centre), lowest tyre point (ground contact at Z 0), closed shells with negative signed
volume (inverted normals) per object, objects with unapplied scale/rotation, missing UV layers.
Run: python tools/blender/mcp_call.py call execute_blender_code --code-file tools/blender/review/check_traffic.py
"""
import bpy
import bmesh
from mathutils import Vector

IDS = ['hatch_small', 'van_delivery', 'lorry_box', 'bus_coach', 'tractor_farm', 'pickup_work']


def shells(bm):
    bm.verts.ensure_lookup_table()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        group = []
        while stack:
            g = stack.pop()
            group.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(group)
    return out


def inverted_shells(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    bad = []
    n_closed = 0
    for grp in shells(bm):
        edges = {e for f in grp for e in f.edges}
        if any(len(e.link_faces) != 2 for e in edges):
            continue
        n_closed += 1
        vol = 0.0
        for f in grp:
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
        if vol < -1e-7:
            c = sum((f.calc_center_median() for f in grp), Vector()) / len(grp)
            bad.append((round(vol, 5), tuple(round(x, 2) for x in ob.matrix_world @ c), len(grp)))
    bm.free()
    return n_closed, bad


dg = bpy.context.evaluated_depsgraph_get()
for cid in IDS:
    col = bpy.data.collections.get('Traffic_' + cid)
    root = bpy.data.objects.get(cid)
    tris = 0
    issues = []
    zmin = 1e9
    if root.matrix_world != root.matrix_world.Identity(4):
        issues.append('root transform not identity')
    for ob in col.objects:
        if ob.type != 'MESH':
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        tris += sum(len(p.vertices) - 2 for p in me.polygons)
        ev.to_mesh_clear()
        if not ob.data.uv_layers:
            issues.append('%s no UV' % ob.name)
        nc, bad = inverted_shells(ob)
        if bad:
            issues.append('%s inverted %d/%d %s' % (ob.name, len(bad), nc, bad[:3]))
        if ob.name.startswith('Wheel_'):
            zmin = min(zmin, min((ob.matrix_world @ v.co).z for v in ob.data.vertices))
            vs = [v.co for v in ob.data.vertices]
            c = Vector([(min(v[k] for v in vs) + max(v[k] for v in vs)) / 2 for k in range(3)])
            if c.length > 0.01 or tuple(ob.rotation_euler) != (0, 0, 0) or tuple(ob.scale) != (1, 1, 1):
                issues.append('%s origin/axle offset %s rot %s scale %s' % (ob.name, tuple(round(x, 3) for x in c),
                                                                          tuple(ob.rotation_euler), tuple(ob.scale)))
        elif not ob.name.startswith(('Caliper_', 'SteeringWheel')):
            if tuple(ob.scale) != (1, 1, 1) or tuple(ob.rotation_euler) != (0, 0, 0):
                issues.append('%s unapplied transform' % ob.name)
    print(cid, 'tris', tris, '/ 25000', 'tyre_zmin', round(zmin, 4), 'issues', issues if issues else 'none')
