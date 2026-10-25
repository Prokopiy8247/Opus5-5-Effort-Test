"""Detect unintended at-grade crossings / near-overlaps between baked roads (data/world/roads.json).
Junction ends (child road endpoints snapped to a parent) are excluded.
Usage: python tools/check_crossings.py"""
import json, math
d = json.load(open('data/world/roads.json'))
roads = {}
for r in d['roads']:
    p = r['pos']; n = len(p) // 3
    roads[r['id']] = dict(pts=[(p[i*3], p[i*3+2]) for i in range(n)], loop=r['loop'], j=(bool(r.get('j_start')), bool(r.get('j_end'))), w=r['width'])
def seg_int(a, b, c, d):
    def cr(o, p, q): return (p[0]-o[0])*(q[1]-o[1]) - (p[1]-o[1])*(q[0]-o[0])
    d1, d2, d3, d4 = cr(c, d, a), cr(c, d, b), cr(a, b, c), cr(a, b, d)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0)
ids = list(roads)
found = []
for i, ra in enumerate(ids):
    A = roads[ra]
    for rb in ids[i+1:]:
        B = roads[rb]
        pa, pb = A['pts'], B['pts']
        # bounding-box prefilter per 20-sample chunk
        for ia in range(0, len(pa) - 1):
            a0, a1 = pa[ia], pa[ia+1]
            for ib in range(0, len(pb) - 1, 1):
                b0, b1 = pb[ib], pb[ib+1]
                if abs(a0[0]-b0[0]) > 40 or abs(a0[1]-b0[1]) > 40:
                    continue
                if seg_int(a0, a1, b0, b1):
                    # ignore crossings within 25 m of a junction end of either road
                    near_end = False
                    for R, idx in ((A, ia), (B, ib)):
                        n = len(R['pts'])
                        if (R['j'][0] and idx * 3 < 25) or (R['j'][1] and (n - idx) * 3 < 25):
                            near_end = True
                    if not near_end:
                        found.append((ra, ia*3, rb, ib*3, (round(a0[0]), round(a0[1]))))
for f in found:
    print("CROSSING %s s=%d  x  %s s=%d  at %s" % f)
print("total crossings:", len(found))
