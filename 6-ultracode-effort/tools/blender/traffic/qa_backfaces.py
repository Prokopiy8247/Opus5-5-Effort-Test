"""Debug: locations / materials of Body faces hit from behind by the kit's outward-normal ray test."""
import bpy, random
from mathutils import Vector
CID = globals().get('CID', 'bus_coach')
body = bpy.data.objects['Body__' + CID]
dg = bpy.context.evaluated_depsgraph_get()
vs = [body.matrix_world @ v.co for v in body.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
cen = (mn + mx) / 2
random.seed(1)
bad = []
for i in range(4000):
    d = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.2, 1))).normalized()
    o = cen + d * 9.0
    tgt = cen + Vector((random.uniform(-0.6, 0.6), random.uniform(-1.6, 1.6), random.uniform(-0.2, 0.3)))
    dirn = (tgt - o).normalized()
    res, loc, nor, idx, ob, mat = bpy.context.scene.ray_cast(dg, o, dirn)
    if res and ob == body and nor.dot(dirn) > 0:
        p = body.data.polygons[idx]
        bad.append((tuple(round(c, 3) for c in loc), body.data.materials[p.material_index].name))
print(len(bad), bad[:20])
