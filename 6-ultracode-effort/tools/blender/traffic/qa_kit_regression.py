"""QA: the traffic additions to car_kit.py must not change the player cars. Rebuilds two player-car wheels with the
current kit (defaults) in memory only and compares them with the meshes stored in the master file (no scene edits)."""
import sys, importlib
P = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort\tools\blender"
sys.path.insert(0, P)
import bpy
import car_kit as ck
importlib.reload(ck)

CASES = {
    'Wheel_FR__sora_s2': dict(R=0.320, W=0.225, rim_d_in=18, spokes=10, style='split', segs=48, rim_segs=40,
                              spoke_thick=0.022, spoke_dish=0.030, hub_r=0.060, nuts=5, disc_r=0.172,
                              caliper_angle=150.0, caliper_span=46.0,
                              split=dict(split_f=0.40, stem_w=(0.030, 0.006), arm_w=(0.0135, 0.004), arm_gap=0.050)),
    'Wheel_FR__hauler_2500': dict(R=0.400, W=0.275, rim_d_in=18, spokes=8, style='single', segs=36, rim_segs=36,
                                  spoke_w=(0.060, 0.022), spoke_thick=0.026, spoke_dish=0.042, hub_r=0.080, nuts=8,
                                  tyre='tall', blocks=dict(n=26, h=0.013), disc_r=0.185, caliper_angle=150.0,
                                  caliper_span=46.0),
}
for name, spec in CASES.items():
    ob = bpy.data.objects.get(name)
    w, cal = ck.build_wheel(**spec)
    me = ob.data
    stored = sorted((round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4)) for v in me.vertices)
    fresh = sorted((round(v.x, 4), round(v.y, 4), round(v.z, 4)) for v in w.v)
    print(name, 'stored verts', len(stored), 'fresh verts', len(fresh), 'identical', stored == fresh,
          'tris stored', sum(len(p.vertices) - 2 for p in me.polygons), 'fresh', w.tris())
