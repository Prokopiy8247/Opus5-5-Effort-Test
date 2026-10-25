"""Review pass: visible back-facing triangles (= holes in Godot, where single-sided materials are back-face culled).

For every kit prop (NatureKit / RoadsideKit / BuildingsKit) and every traffic vehicle mesh, rays are cast from random
viewpoints around the object (from ground level upwards) towards random points of its above-ground bounding box. A
first hit on a face of a single-sided material (use_backface_culling, exported doubleSided = false) whose normal points
away from the viewer is a face the game would cull -> a see-through hole. Reports the hit share and the clusters.
Globals: ONLY (names), RAYS (per object, default 2500), KITS (collection names), TRAFFIC (bool).
Run inside Blender: python tools/blender/mcp_call.py call execute_blender_code --code-file tools/blender/review/check_backfaces.py
"""
import math
import random

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ONLY = globals().get('ONLY')
RAYS = globals().get('RAYS', 2500)
KITS = globals().get('KITS', ['NatureKit', 'RoadsideKit', 'BuildingsKit'])
TRAFFIC = globals().get('TRAFFIC', True)
GROUND = globals().get('GROUND', 0.02)


def test(ob, dg, rays, rng, zmin_world=None):
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    M = ob.matrix_world
    me.calc_loop_triangles()
    verts = [M @ v.co for v in me.vertices]
    tris = me.loop_triangles
    polys = [tuple(t.vertices) for t in tris]
    mats = [me.materials[t.material_index] if t.material_index < len(me.materials) else None for t in tris]
    normals = [(M.to_3x3() @ t.normal).normalized() for t in tris]
    centers = [M @ t.center for t in tris]
    ev.to_mesh_clear()
    if not polys:
        return None
    bvh = BVHTree.FromPolygons(verts, polys)
    mn = Vector([min(v[k] for v in verts) for k in range(3)])
    mx = Vector([max(v[k] for v in verts) for k in range(3)])
    g = GROUND if zmin_world is None else zmin_world
    mn.z = max(mn.z, g)
    if mx.z <= mn.z:
        return None
    c = (mn + mx) / 2
    R = (mx - mn).length * 1.5 + 1.0
    hits = 0
    bad = {}
    for _ in range(rays):
        az = rng.uniform(0, 2 * math.pi)
        el = rng.uniform(-0.02, 1.3)
        eye = c + Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el))) * R
        eye.z = max(eye.z, g + 0.3)
        tgt = Vector((rng.uniform(mn.x, mx.x), rng.uniform(mn.y, mx.y), rng.uniform(mn.z, mx.z)))
        d = (tgt - eye).normalized()
        loc, nor, idx, dist = bvh.ray_cast(eye, d, 3 * R)
        if loc is None:
            continue
        hits += 1
        m = mats[idx]
        if normals[idx].dot(d) > 1e-4 and (m is None or m.use_backface_culling):
            key = m.name if m else 'None'
            bad.setdefault(key, []).append(idx)
    out = {}
    for key, idxs in bad.items():
        uniq = sorted(set(idxs))
        pts = [centers[i] for i in uniq[:6]]
        out[key] = (len(idxs), len(uniq), [tuple(round(x - o, 2) for x, o in zip(p, M.translation)) for p in pts])
    return hits, out


def test_group(obs, dg, rays, rng):
    verts, polys, owner, normals, centers = [], [], [], [], []
    for ob in obs:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        M = ob.matrix_world
        base = len(verts)
        me.calc_loop_triangles()
        verts += [M @ v.co for v in me.vertices]
        for t in me.loop_triangles:
            polys.append(tuple(base + i for i in t.vertices))
            m = me.materials[t.material_index] if t.material_index < len(me.materials) else None
            owner.append((ob.name, m))
            normals.append((M.to_3x3() @ t.normal).normalized())
            centers.append(M @ t.center)
        ev.to_mesh_clear()
    bvh = BVHTree.FromPolygons(verts, polys)
    mn = Vector([min(v[k] for v in verts) for k in range(3)])
    mx = Vector([max(v[k] for v in verts) for k in range(3)])
    mn.z = max(mn.z, GROUND)
    c = (mn + mx) / 2
    R = (mx - mn).length * 1.5 + 1.0
    hits = 0
    bad = {}
    for _ in range(rays):
        az = rng.uniform(0, 2 * math.pi)
        el = rng.uniform(-0.02, 1.3)
        eye = c + Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el))) * R
        eye.z = max(eye.z, 0.3)
        tgt = Vector((rng.uniform(mn.x, mx.x), rng.uniform(mn.y, mx.y), rng.uniform(mn.z, mx.z)))
        d = (tgt - eye).normalized()
        loc, nor, idx, dist = bvh.ray_cast(eye, d, 3 * R)
        if loc is None:
            continue
        hits += 1
        name, m = owner[idx]
        if normals[idx].dot(d) > 1e-4 and (m is None or m.use_backface_culling):
            key = name.split('__')[0] + ':' + (m.name if m else 'None')
            bad.setdefault(key, []).append(idx)
    out = {}
    for key, idxs in bad.items():
        uniq = sorted(set(idxs))
        out[key] = (len(idxs), len(uniq), [tuple(round(x, 2) for x in centers[i]) for i in uniq[:5]])
    return hits, out


def main():
    dg = bpy.context.evaluated_depsgraph_get()
    rng = random.Random(7)
    lines = []
    culling_off = set()
    for kit in KITS:
        col = bpy.data.collections.get(kit)
        if col is None:
            continue
        for ob in sorted(col.objects, key=lambda o: o.name):
            if ob.type != 'MESH' or (ONLY and ob.name not in ONLY):
                continue
            for m in ob.data.materials:
                if m is not None and not m.use_backface_culling:
                    culling_off.add(m.name)
            r = test(ob, dg, RAYS, rng)
            if r is None:
                continue
            hits, bad = r
            nb = sum(v[0] for v in bad.values())
            if nb:
                lines.append('%s hits %d BACK %d (%.2f%%) %s' % (ob.name, hits, nb, 100.0 * nb / max(hits, 1),
                                                                {k: v for k, v in bad.items()}))
            else:
                lines.append('%s hits %d back 0' % (ob.name, hits))
    if TRAFFIC:
        # whole vehicle as one occluder set (Glass excluded: transparent), so a lens behind a housing or a rim behind
        # a tyre only counts when it is really visible
        tr = bpy.data.collections.get('Traffic')
        for col in (tr.children if tr else []):
            obs = [o for o in col.objects if o.type == 'MESH' and not o.name.startswith(('QA_', 'Glass'))]
            if ONLY and not any(o.name in ONLY for o in obs):
                continue
            r = test_group(obs, dg, RAYS * 2, rng)
            hits, bad = r
            nb = sum(v[0] for v in bad.values())
            lines.append('%s hits %d BACK %d (%.2f%%) %s' % (col.name, hits, nb, 100.0 * nb / max(hits, 1), bad))
    print('materials with culling off (double sided):', sorted(culling_off))
    for ln in lines:
        print(ln)


main()
