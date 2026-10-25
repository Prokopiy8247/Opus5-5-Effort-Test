"""Read-only reviewer check: what Godot (backface culling, all non-glass glTF materials are single-sided)
would show. Rays are cast at each car from outside and from the cockpit eye point; glass is treated as
transparent; back faces are skipped as the GPU would cull them. Reports rays whose first non-glass hit
is a back face ("culled") and whether they then see through the car to the background ("hole").
No geometry changes. Run via exec(compile(...)) inside Blender."""
import bpy, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from collections import Counter

IDS = ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x",
       "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]
dg = bpy.context.evaluated_depsgraph_get()


def build(cid):
    verts = []; polys = []; fobj = []; fmat = []
    col = bpy.data.collections['Car_' + cid]
    for ob in col.objects:
        if ob.type != 'MESH':
            continue
        oe = ob.evaluated_get(dg); me = oe.to_mesh()
        mw = ob.matrix_world
        off = len(verts)
        verts.extend([mw @ v.co for v in me.vertices])
        for p in me.polygons:
            polys.append([off + i for i in p.vertices])
            fobj.append(ob.name.split('__')[0])
            m = ob.material_slots[p.material_index].material if ob.material_slots else None
            fmat.append(m.name.rsplit('_' + cid, 1)[0] if m else 'None')
        oe.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0), fobj, fmat


def trace(t, fobj, fmat, o, d, maxd=40.0):
    """returns (first_hit_kind, culled_list, final) ; kind in 'none','front','culled'"""
    culled = []
    p = o.copy(); travelled = 0.0
    for _ in range(64):
        loc, nor, idx, dist = t.ray_cast(p, d, maxd - travelled)
        if loc is None:
            return culled, None
        travelled += dist
        if fmat[idx] == 'Glass':
            p = loc + d * 1e-4; continue
        if nor.dot(d) > 0:  # back face: culled in Godot
            culled.append((fobj[idx], fmat[idx], loc.copy()))
            p = loc + d * 1e-4; continue
        return culled, (fobj[idx], fmat[idx], loc.copy())
    return culled, None


def fib_dirs(n):
    out = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(1 - z * z)
        out.append(Vector((math.cos(ga * i) * r, math.sin(ga * i) * r, z)))
    return out


def exterior(cid, t, fobj, fmat):
    dirs = [v for v in fib_dirs(160) if v.z > -0.15]  # viewer directions (from car to eye)
    root = bpy.data.objects[cid]
    stats = Counter(); where = Counter(); holes = Counter(); nhit = 0
    for e in dirs:
        d = -e
        # orthonormal basis
        a = Vector((0, 0, 1)) if abs(e.z) < 0.9 else Vector((1, 0, 0))
        u = e.cross(a).normalized(); w = e.cross(u).normalized()
        for i in range(-30, 31):
            for j in range(-14, 15):
                o = Vector((0, 0, 0.8)) + e * 12 + u * (i * 0.1) + w * (j * 0.1)
                culled, final = trace(t, fobj, fmat, o, d)
                if not culled and final is None:
                    continue
                nhit += 1
                if culled:
                    c = culled[0]
                    stats['culled_first'] += 1
                    where[(c[0], c[1])] += 1
                    if final is None:
                        stats['see_through_hole'] += 1
                        holes[(c[0], c[1], round(c[2].x, 1), round(c[2].y, 1), round(c[2].z, 1))] += 1
    return nhit, stats, where, holes


def cockpit(cid, t, fobj, fmat):
    eye = bpy.data.objects['Socket_CamCockpit__' + cid].matrix_world.translation
    stats = Counter(); where = Counter(); holes = Counter(); n = 0
    for d in fib_dirs(6000):
        # only the forward-ish viewing cone a cockpit camera uses (+-75 deg yaw, -45..+30 pitch)
        yaw = math.degrees(math.atan2(d.x, d.y)); pitch = math.degrees(math.asin(max(-1, min(1, d.z))))
        if abs(yaw) > 75 or pitch < -45 or pitch > 30:
            continue
        n += 1
        culled, final = trace(t, fobj, fmat, eye.copy(), d, 30.0)
        if culled:
            c = culled[0]
            stats['culled_first'] += 1
            where[(c[0], c[1])] += 1
            if final is None:
                stats['see_through_hole'] += 1
                holes[(c[0], c[1], round(c[2].x, 1), round(c[2].y, 1), round(c[2].z, 1))] += 1
        elif final is None:
            stats['open_sky'] += 1
    return n, stats, where, holes


def main(ids=IDS):
    for cid in ids:
        t, fobj, fmat = build(cid)
        nh, st, wh, ho = exterior(cid, t, fobj, fmat)
        print('=====', cid)
        print('  EXTERIOR rays hitting car', nh, dict(st), 'culled-first %.2f%%' % (100.0 * st['culled_first'] / max(1, nh)))
        print('    culled by part:', wh.most_common(8))
        print('    holes (see-through):', ho.most_common(10))
        n, st2, wh2, ho2 = cockpit(cid, t, fobj, fmat)
        print('  COCKPIT rays', n, dict(st2))
        print('    culled by part:', wh2.most_common(8))
        print('    holes:', ho2.most_common(10))


if __name__ == '__main__':
    import builtins
    main(getattr(builtins, '_REVIEW_IDS', IDS))
