"""Read-only reviewer inspection of all cars in the master .blend (no geometry changes).
Run inside Blender via execute_blender_code:
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
"""
import bpy, bmesh, math, json, os
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJ = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
IDS = ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x",
       "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]
dg = bpy.context.evaluated_depsgraph_get()


def ev_bm(ob, world=True):
    oe = ob.evaluated_get(dg)
    me = oe.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    if world:
        bm.transform(ob.matrix_world)
    oe.to_mesh_clear()
    return bm


def tri_count(ob):
    oe = ob.evaluated_get(dg)
    me = oe.to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    oe.to_mesh_clear()
    return n


def bvh_of(ob):
    bm = ev_bm(ob)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def main():
    report = {}
    for cid in IDS:
        r = {}
        root = bpy.data.objects[cid]
        g = lambda p: bpy.data.objects.get('%s__%s' % (p, cid))
        J = json.load(open(os.path.join(PROJ, 'assets', 'imported', 'cars', cid + '.json'), encoding='utf-8'))
        # tri counts vs json
        mism = []
        for k, v in J['tris'].items():
            if k == 'total':
                continue
            o = g(k)
            if o is None:
                mism.append('%s missing' % k); continue
            n = tri_count(o)
            if n != v:
                mism.append('%s blend %d json %d' % (k, n, v))
        r['tri_mismatch_vs_json'] = mism
        # uv / transforms / normals
        issues = []
        for o in [o for o in bpy.data.collections['Car_' + cid].objects]:
            if o.type == 'MESH':
                if not o.data.uv_layers:
                    issues.append('%s no UV' % o.name)
                if len(o.data.polygons) and not any(p.use_smooth for p in o.data.polygons[:2000]):
                    issues.append('%s flat shaded' % o.name)
            if o.parent is None and o is not root:
                issues.append('%s unparented' % o.name)
        for w in ('FL', 'FR', 'RL', 'RR'):
            wo = g('Wheel_' + w); co = g('Caliper_' + w)
            if wo.rotation_euler.to_quaternion().angle > 1e-4 or any(abs(s - 1) > 1e-5 for s in wo.scale):
                issues.append('Wheel_%s rot/scale not identity' % w)
            if (wo.location - co.location).length > 1e-4:
                issues.append('Caliper_%s origin != wheel origin' % w)
            bb = [wo.matrix_world @ Vector(c) for c in wo.bound_box]
            zmin = min(v.z for v in bb)
            if abs(zmin) > 0.002:
                issues.append('Wheel_%s bottom z=%.4f' % (w, zmin))
        r['issues'] = issues
        # wheel vs body overlap + arch gap
        body = g('Body')
        tb = bvh_of(body)
        wheel_info = {}
        for w in ('FL', 'FR', 'RL', 'RR'):
            wo = g('Wheel_' + w)
            tw = bvh_of(wo)
            ov = tb.overlap(tw)
            # arch gap: from tyre tread top, cast radially outward in the YZ plane, angles -50..+50 deg
            c = wo.matrix_world.translation
            R = J['wheel_radius_front'] if w[0] == 'F' else J['wheel_radius_rear']
            gaps = []
            for a in range(-50, 51, 10):
                th = math.radians(a)
                d = Vector((0, math.sin(th), math.cos(th)))
                for xo in (-0.05, 0.0, 0.05):
                    o = c + Vector((xo, 0, 0)) + d * (R - 0.002)
                    hit = tb.ray_cast(o, d, 0.5)
                    if hit[0] is not None:
                        gaps.append(round(hit[3], 3))
            # lateral: outer face of tyre vs body (is tyre poking outside fender?)
            sign = -1 if w[1] == 'L' else 1
            wbm = ev_bm(wo)
            xs = [v.co.x for v in wbm.verts]
            wbm.free()
            outer = max(xs) if sign > 0 else min(xs)
            # body half-width near this axle (verts within +-0.5m of axle y, above wheel centre)
            wheel_info[w] = {'overlap_pairs': len(ov), 'radial_gap_min': min(gaps) if gaps else None,
                             'radial_gap_med': sorted(gaps)[len(gaps) // 2] if gaps else None,
                             'rays_hit': len(gaps), 'tyre_outer_x': round(outer, 4)}
        bbm = ev_bm(body)
        for w in ('FL', 'RL'):
            wo = g('Wheel_' + w)
            cy = wo.matrix_world.translation.y
            near = [v.co for v in bbm.verts if abs(v.co.y - cy) < 0.45 and v.co.z > wo.matrix_world.translation.z]
            if near:
                wheel_info[w]['body_halfwidth_over_axle'] = round(max(abs(v.x) for v in near), 4)
        bbm.free()
        r['wheels'] = wheel_info
        # glass / interior / steering
        gl = g('Glass'); it = g('Interior'); sw = g('SteeringWheel')
        r['glass_faces'] = len(gl.data.polygons)
        gm = gl.material_slots[0].material
        bs = [n for n in gm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED']
        r['glass_alpha'] = round(bs[0].inputs['Alpha'].default_value, 3) if bs else None
        r['glass_surface_render_method'] = getattr(gm, 'surface_render_method', None)
        tg = bvh_of(gl)
        r['glass_body_overlap_pairs'] = len(tb.overlap(tg))
        ti = bvh_of(it)
        r['interior_body_overlap_pairs'] = len(tb.overlap(ti))
        r['steering_loc'] = [round(v, 3) for v in sw.location]
        r['steering_rot_deg'] = [round(math.degrees(v), 1) for v in sw.rotation_euler]
        cam = g('Socket_CamCockpit')
        r['cockpit_cam'] = [round(v, 3) for v in cam.location]
        # is cockpit eye inside body shell & below roof? ray up from eye should hit body roof (if not roadster)
        hit_up = tb.ray_cast(cam.matrix_world.translation, Vector((0, 0, 1)), 2.0)
        r['eye_to_roof'] = round(hit_up[3], 3) if hit_up[0] is not None else None
        hit_fwd = tg.ray_cast(cam.matrix_world.translation, Vector((0, 1, -0.08)).normalized(), 3.0)
        r['eye_fwd_hits_glass_at'] = round(hit_fwd[3], 3) if hit_fwd[0] is not None else None
        hit_fwd_b = tb.ray_cast(cam.matrix_world.translation, Vector((0, 1, -0.08)).normalized(), 3.0)
        r['eye_fwd_hits_body_at'] = round(hit_fwd_b[3], 3) if hit_fwd_b[0] is not None else None
        # Body non-manifold / loose
        bm = ev_bm(body, world=False)
        r['body_nonmanifold_edges'] = sum(1 for e in bm.edges if not e.is_manifold)
        r['body_loose_verts'] = sum(1 for v in bm.verts if not v.link_edges)
        r['body_zero_area_faces'] = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
        bm.free()
        report[cid] = r
    for k, v in report.items():
        print('=====', k)
        for kk, vv in v.items():
            print('   ', kk, ':', vv)


if __name__ == '__main__':
    main()
