"""Read-only reviewer check: do the front wheels (and calipers) hit the Body when steered +-STEER deg
or when the suspension compresses BUMP metres? Works on evaluated mesh COPIES only (no edits)."""
import bpy, bmesh, math
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

IDS = ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x",
       "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]
dg = bpy.context.evaluated_depsgraph_get()


def bm_local(ob):
    oe = ob.evaluated_get(dg); me = oe.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me); oe.to_mesh_clear()
    return bm


def main(steers=(-32, -20, 0, 20, 32), bumps=(0.0, 0.03)):
    for cid in IDS:
        body = bpy.data.objects['Body__' + cid]
        bb = bm_local(body); bb.transform(body.matrix_world); tb = BVHTree.FromBMesh(bb); bb.free()
        res = {}
        for w in ('FL', 'FR'):
            wo = bpy.data.objects['Wheel_%s__%s' % (w, cid)]
            base = bm_local(wo)
            for b in bumps:
                for s in steers:
                    m = (Matrix.Translation(wo.matrix_world.translation + Vector((0, 0, b))) @
                         Matrix.Rotation(math.radians(s), 4, 'Z'))
                    c = base.copy(); c.transform(m)
                    n = len(tb.overlap(BVHTree.FromBMesh(c))); c.free()
                    if n:
                        res.setdefault(w, []).append((s, b, n))
            base.free()
        # rear wheels at bump
        for w in ('RL', 'RR'):
            wo = bpy.data.objects['Wheel_%s__%s' % (w, cid)]
            base = bm_local(wo)
            for b in bumps:
                c = base.copy(); c.transform(Matrix.Translation(wo.matrix_world.translation + Vector((0, 0, b))))
                n = len(tb.overlap(BVHTree.FromBMesh(c))); c.free()
                if n:
                    res.setdefault(w, []).append((0, b, n))
            base.free()
        print(cid, res if res else 'no contact (steer +-32 deg, bump 3 cm)')


if __name__ == '__main__':
    main()
