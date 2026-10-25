"""Read-only reviewer check: coplanar overlaps (z-fighting risk) between Glass / Lights_* and Body,
socket-to-lamp distances. No geometry changes. Run via exec(compile(...)) inside Blender."""
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

IDS = ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x",
       "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]
dg = bpy.context.evaluated_depsgraph_get()


def bmw(ob):
    oe = ob.evaluated_get(dg); me = oe.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me); bm.transform(ob.matrix_world); oe.to_mesh_clear()
    bm.faces.ensure_lookup_table(); bm.normal_update()
    return bm


def coplanar(bm_a, tree_b, bm_b, eps=0.0006, cos_min=0.98):
    """faces of A whose centre lies within eps of a B face with (anti)parallel normal."""
    n = 0; area = 0.0
    for f in bm_a.faces:
        c = f.calc_center_median()
        loc, nor, idx, d = tree_b.find_nearest(c, eps)
        if loc is not None and abs(f.normal.dot(bm_b.faces[idx].normal)) > cos_min:
            n += 1; area += f.calc_area()
    return n, area


def main():
    for cid in IDS:
        g = lambda p: bpy.data.objects['%s__%s' % (p, cid)]
        body = bmw(g('Body')); tb = BVHTree.FromBMesh(body)
        out = []
        # body self coplanar duplicates (detail patches lying exactly on the shell)
        for part in ('Glass', 'Lights_Head', 'Lights_Tail', 'Lights_Brake', 'Lights_Reverse', 'Interior'):
            bm = bmw(g(part))
            n, a = coplanar(bm, tb, body)
            out.append('%s %d/%d faces coplanar(<0.6mm) area %.4f m2' % (part, n, len(bm.faces), a))
            bm.free()
        # sockets vs lamps
        hb = bmw(g('Lights_Head')); th = BVHTree.FromBMesh(hb)
        for s in ('Socket_HeadlightL', 'Socket_HeadlightR'):
            p = g(s).matrix_world.translation
            loc, nor, idx, d = th.find_nearest(p)
            out.append('%s -> nearest head lens %.3f m' % (s, d))
        hb.free()
        for s in ('Socket_Exhaust', 'Socket_Exhaust2'):
            o = bpy.data.objects.get('%s__%s' % (s, cid))
            if o:
                loc, nor, idx, d = tb.find_nearest(o.matrix_world.translation)
                out.append('%s -> nearest body %.3f m (body mat %s)' % (s, d, g('Body').material_slots[body.faces[idx].material_index].material.name))
        body.free()
        print('=====', cid)
        for l in out:
            print('   ', l)


if __name__ == '__main__':
    main()
