"""Read-only QA for sora_s2 (no geometry changes): runs the reviewer checks from tools/blender/review/ on this
car only, plus a few extra probes used while fixing the review defects.

Run inside Blender (MCP execute_blender_code):
    PATH = r"<project>\\tools\\blender\\cars\\sora_s2_qa.py"
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
Optional globals in the exec() dict: CHECKS = {'zfight', 'backfaces', 'steer', 'under'} (default: all).
"""
import os
import math
from collections import Counter

import bpy
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

PROJECT = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort"
REVIEW = os.path.join(PROJECT, 'tools', 'blender', 'review')
CID = 'sora_s2'
CHECKS = globals().get('CHECKS', {'zfight', 'backfaces', 'steer', 'under'})


def load(name):
    path = os.path.join(REVIEW, name)
    g = {'__name__': 'review_module'}
    exec(compile(open(path, encoding='utf-8').read(), path, 'exec'), g)
    return g


def zfight():
    Z = load('inspect_zfight.py')
    g = lambda p: bpy.data.objects['%s__%s' % (p, CID)]
    body = Z['bmw'](g('Body'))
    tb = BVHTree.FromBMesh(body)
    out = {}
    for part in ('Glass', 'Lights_Head', 'Lights_Tail', 'Lights_Brake', 'Lights_Reverse', 'Interior'):
        bm = Z['bmw'](g(part))
        n, a = Z['coplanar'](bm, tb, body)
        # also a looser probe (2 mm) so near-misses show up
        n2, a2 = Z['coplanar'](bm, tb, body, eps=0.002)
        out[part] = (n, len(bm.faces), round(a, 5), 'within2mm', n2)
        bm.free()
    body.free()
    return out


def backfaces():
    B = load('inspect_backfaces.py')
    t, fobj, fmat = B['build'](CID)
    nh, st, wh, ho = B['exterior'](CID, t, fobj, fmat)
    n, st2, wh2, ho2 = B['cockpit'](CID, t, fobj, fmat)
    return dict(ext_hits=nh, ext=dict(st), ext_pct=round(100.0 * st['culled_first'] / max(1, nh), 3),
                ext_by_part=wh.most_common(10), ext_holes=ho.most_common(14),
                cockpit_rays=n, cockpit=dict(st2), cockpit_by_part=wh2.most_common(8), cockpit_holes=ho2.most_common(10))


def culled_locations(part_filter=None, top=25):
    """Where (rounded 5 cm cells) the exterior culled-first hits land, optionally for one (object, material)."""
    B = load('inspect_backfaces.py')
    t, fobj, fmat = B['build'](CID)
    dirs = [v for v in B['fib_dirs'](160) if v.z > -0.15]
    cells = Counter()
    for e in dirs:
        d = -e
        a = Vector((0, 0, 1)) if abs(e.z) < 0.9 else Vector((1, 0, 0))
        u = e.cross(a).normalized()
        w = e.cross(u).normalized()
        for i in range(-30, 31):
            for j in range(-14, 15):
                o = Vector((0, 0, 0.8)) + e * 12 + u * (i * 0.1) + w * (j * 0.1)
                culled, final = B['trace'](t, fobj, fmat, o, d)
                if culled:
                    c = culled[0]
                    if part_filter and (c[0], c[1]) not in part_filter:
                        continue
                    cells[(c[0], c[1], round(c[2].x * 20) / 20, round(c[2].y * 20) / 20, round(c[2].z * 20) / 20)] += 1
    return cells.most_common(top)


def steer():
    dg = bpy.context.evaluated_depsgraph_get()

    def bm_local(ob):
        oe = ob.evaluated_get(dg)
        me = oe.to_mesh()
        bm = bmesh.new()
        bm.from_mesh(me)
        oe.to_mesh_clear()
        return bm
    body = bpy.data.objects['Body__' + CID]
    bb = bm_local(body)
    bb.transform(body.matrix_world)
    tb = BVHTree.FromBMesh(bb)
    bb.free()
    res = {}
    for w in ('FL', 'FR', 'RL', 'RR'):
        for kind in ('Wheel', 'Caliper'):
            wo = bpy.data.objects['%s_%s__%s' % (kind, w, CID)]
            base = bm_local(wo)
            for b in (0.0, 0.03, 0.045):
                for s in ((-32, -20, 0, 20, 32) if w[0] == 'F' else (0,)):
                    m = Matrix.Translation(wo.matrix_world.translation + Vector((0, 0, b))) @ Matrix.Rotation(math.radians(s), 4, 'Z')
                    c = base.copy()
                    c.transform(m)
                    n = len(tb.overlap(BVHTree.FromBMesh(c)))
                    c.free()
                    if n:
                        res.setdefault(kind + '_' + w, []).append((s, b, n))
            base.free()
    return res


def under():
    """Low rear / side views of the tail: rays from low eye points behind the car toward the rear underbody
    (y -1.6..-2.3, z 0.1..0.55). Glass transparent, back faces culled. Reports rays that leave the car
    without hitting a front face after entering its bounding box ('see-through') and culled-first hits."""
    B = load('inspect_backfaces.py')
    t, fobj, fmat = B['build'](CID)
    stats = Counter()
    where = Counter()
    for ez in (0.02, 0.15, 0.35):
        for ax in range(-60, 61, 10):
            a = math.radians(ax)
            eye_dir = Vector((math.sin(a), -math.cos(a), 0.0))
            eye = Vector((0, -2.0, 0)) + eye_dir * 7.0
            eye.z = ez
            for gx in range(-17, 18):
                for gz in range(0, 12):
                    tgt = Vector((gx * 0.05, -2.0 + 0.0, 0.08 + gz * 0.04))
                    d = (tgt - eye).normalized()
                    culled, final = B['trace'](t, fobj, fmat, eye.copy(), d)
                    if not culled and final is None:
                        continue
                    stats['hit'] += 1
                    if culled:
                        c = culled[0]
                        stats['culled_first'] += 1
                        if final is None:
                            stats['see_through'] += 1
                        where[(c[0], c[1], round(c[2].x, 1), round(c[2].y, 1), round(c[2].z, 1), final is None)] += 1
    return dict(stats), where.most_common(16)


if __name__ == '__main__':
    if 'zfight' in CHECKS:
        print('ZFIGHT', zfight())
    if 'steer' in CHECKS:
        print('STEER', steer() or 'no contact')
    if 'under' in CHECKS:
        print('UNDER', under())
    if 'backfaces' in CHECKS:
        r = backfaces()
        for k, v in r.items():
            print('BACKFACES', k, v)
    if 'cells' in CHECKS:
        print('CELLS', culled_locations(globals().get('CELL_FILTER')))
