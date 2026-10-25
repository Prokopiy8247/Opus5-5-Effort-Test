"""
car_kit.py - Sunward Roads parametric car builder
=================================================
Blender 5.2 LTS / Python 3.13, pure bpy + bmesh + mathutils. No external assets, no generators.
Contract with Godot: docs/ASSET_CONVENTIONS.md (names, axes, origins, materials, sockets).
Reference car built with this kit: tools/blender/cars/kestrel_r4.py  (copy it as a template).

HOW A CAR SCRIPT USES THE KIT
-----------------------------
    import sys, importlib
    sys.path.insert(0, r"<project>\\tools\\blender")
    import car_kit as ck; importlib.reload(ck)

    car  = ck.CarAssembly("kestrel_r4", "Kestrel R4", ck.default_materials(paint=(0.888, 0.539, 0.0)))
    body = ck.LoftBody(stations=[...], band_segments=[...], rules=[...], nose={...}, tail={...}, warps=[...])
    shell = body.build(car, arches=[...], inner={...})      # closed, arch-cut, windowed body shell
    car.add("Body", shell.bm); car.add("Glass", shell.glass); car.add("Interior", shell.inner)
    S = shell.surface                                      # projection helper (BVH of the outer shell)
    car.add("Body", S.patch(...), S.honeycomb(...), ck.sweep_axis(...), ...)   # details -> Body
    car.add("Lights_Head", part_with_mat_HeadlightLens) ... ("Lights_Tail"/"Lights_Brake"/"Lights_Reverse")
    ck.add_wheels(car, wheel_spec, axles)                  # Wheel_FL..RR + Caliper_FL..RR
    car.add("SteeringWheel", ck.steering_wheel_part(), location=hub, rotation=(-tilt, 0, 0))
    car.socket("Socket_CamCockpit", (x, y, z)) ...         # all sockets from ASSET_CONVENTIONS.md
    car.finalize()                                         # creates the objects, parents to root
    ck.qa_checks(car, R, W); ck.render_hero(car, png)      # numeric QA + EEVEE hero image
    ck.export_car(car, glb_path); ck.write_car_json(car, json_path, data)
    bpy.ops.wm.save_mainfile()
Each part keeps its material KEY per face (e.g. 'Paint', 'Trim'); finalize() maps keys to the car's
materials. The parts of one object are merged; objects are smooth shaded with sharp edges > 35 deg.

OBJECT NAMES IN THE MASTER .BLEND
---------------------------------
Several cars live in one .blend, but Blender object names must be unique. Therefore every part is
stored as "<Part>__<car_id>" (e.g. "Body__kestrel_r4", "Socket_CamCockpit__kestrel_r4"); the root
empty is "<car_id>". export_car() temporarily renames the parts to the canonical names from
ASSET_CONVENTIONS.md ("Body", "Wheel_FL", ...) for the glTF export and restores them afterwards.
Materials are "<Key>_<car_id>" (e.g. "Paint_kestrel_r4"); Godot matches by the prefix token.

COORDINATES
-----------
Blender metres, Z up, car faces +Y, +X = right side, Z=0 = tyre contact patch, Y=0 = midpoint of the
axles, X=0 = centre line. Left side = -X. LHD: driver sits at x < 0.

LOFT BODY (class LoftBody)
--------------------------
The body is a loft of cross-sections ("stations") along Y. Each station is a dict with "y" and any of
the section parameters below (missing ones inherit from the previous station; the first station must
define all). Half-section key points (right side, x >= 0, (x, z) pairs), from bottom centre to roof
centre:
    K0 (0, zb)   floor centre          K1 (wb, zb)  floor edge
    K2 (ws, zs)  sill / rocker         K3 (ww, zw)  waist = widest point of the body side
    K4 (wh, zh)  shoulder / belt crease
    K5 (wg, zg)  glass base (DLO lower edge); on the hood/deck this is the hood shut line
    K6 (wr, zr)  roof rail (top of side glass); on hood/deck stations a point on the hood/deck
    K7           derived: K6 moved `rail` metres toward K8 (A/C pillar / roof rail width), raised by
                 `bulge` metres off the K6-K8 chord (hood power-dome ridges; use with ks {7: 0.5})
    K8 (0, zc)   roof crown; on hood/deck stations the hood/deck centre height
Bands (faces between key points): 0 floor, 1 floor->sill, 2 lower side, 3 upper side, 4 shoulder ledge,
5 side glass band (DLO), 6 roof rail / A-pillar, 7 roof / windscreen / rear window.
Optional per-station keys: "sharp" (0..1 longitudinal crease at this station for all params, or a
dict {param: 0..1}, e.g. the cowl: sharp=dict(zc=1, zr=1, wr=1) creases only the hood/windscreen),
"ks" {key_index: sharpness 0..1} (cross-section crease at a key point, interpolated along Y),
"rail" (pillar width). Parameters are interpolated along Y with a monotone cubic (no overshoot,
no lumps); sections are Hermite splines through the key points (chord-length tangents).
band_segments: 8 ints = quads per band across the half section (controls density / budget).
rules: list of dict(bands=(b0, b1), y=(y0, y1), role=..., side=0|1|-1). The last matching rule wins.
    roles: 'paint', 'trim', 'chrome', 'grille', 'carbon', 'under', 'glass' (hole + glass pane),
    'open' (hole without glass, e.g. roadster cockpit or pickup bed). Rule boundaries become exact
    grid lines, so window openings are clean.
nose / tail: end caps (Hermite caps from the last loft ring to a pole point):
    dict(y=pole_y, z=pole_z, tilt=deg (face looks up), k_edge=0.5..2.5 (edge fullness),
         k_face=0.8..2.8 (face flatness), rings=8)
bulge (station param): raises K7 (hood ridges). warps: slanted grid lines for raked window edges,
    e.g. a forward-leaning C-pillar: dict(y=-1.31, t=(5.0, 6.0), y_t=(-1.46, -1.17), margin=0.24);
    rules keep using the BASE y (-1.31) so the window edge follows the slanted line exactly.
step: target edge length along Y (adaptive: denser where the sections change quickly).
LoftBody.build(car, arches=[dict(y, z, r, x_in)], inner=dict(y=(y0, y1), d=0.035, tubs=[(y, z, r,
    x_limit)], dy_ramp=(ya, yb)), glass_inset=0.006) -> Shell with: .bm (BMesh of the body shell:
    boolean wheel wells (Underbody liners) with bevelled arch lips, window holes with Trim reveal
    frames that meet the inner shell), .glass (Part, inset 6 mm), .inner (Part: cabin tub with
    headliner, pillar trims, door cards, floor, firewall, wheel tubs), .surface (Surface), .ys
    Wheel arch r = tyre R + ~0.03 with the centre ~7 mm above the axle -> ~3 cm visible gap.
LoftBody.point(y, t, side=1) -> Vector on the analytic surface (t = key index + fraction, 0..8)
LoftBody.params_at(y) -> dict of interpolated parameters

SURFACE PROJECTION (class Surface; shell.surface)
-------------------------------------------------
Views: 'front' (coords x, z), 'rear' (x, z), 'right' / 'left' (y, z), 'top' (x, y), or a tuple
(O, U, V, D). Details are projected onto the shell along the view direction and offset along the
surface normal, so they hug the body exactly:
    patch(outline2d, view, offset, depth, bulge, res, mat)    raised conforming panel (lamps, grilles)
    patch3d(points3d, ...)                                    same, outline given as 3D points
    rim(outline2d, view, width, offset, depth, mat)           raised frame around an outline
    line(points2d, view, width, offset, mat) / line3d(...)    panel shut lines (thin dark ribbons)
    honeycomb(outline2d, view, cell, wall, ...)               hex mesh grille
    snap(view, a, b) -> 3D surface point;  nearest(p) -> (location, normal)
All return Part objects (or Vector). Build right-side details and use part.mirrored_x().

GEOMETRY HELPERS (all return Part)
----------------------------------
Part: v (verts), f (faces), m (material keys). part.extend(), mirrored_x(), transformed(Matrix),
    set_mat(key), tris().
revolve(profile[(a, r)], segs, mats, axis='x', theta0, theta1, caps)  lathe about X (wheels)
sweep_axis(axis, stations, profiles, mats, caps)    loft of 2D profiles along x|y|z
box_between(p0, p1, width, height, mat, up)        oriented box;  ellipsoid(c, radii, mat, ...)
tube(p0, p1, r_out, r_in, mat_out, mat_in)         exhaust tip;   disc(center, normal, r, mat)
cr_resample / offset_poly / rrect_pts / superellipse_pts           2D outline helpers
fillet_poly(pts, r, n)  polygon with rounded corners and STRAIGHT edges (cr_resample bulges long edges;
    use fillet_poly + patch/rim(..., smooth=False) for wide grilles, valances, lips)   [added: aurelia_sedan]
Wheels: build_wheel(spec) -> (wheel_part, caliper_part) for the RIGHT side (rim faces +X);
    optional spoke_w=(w_hub, taper), spoke_thick, spoke_dish, hub_r, nuts (e.g. 10 thin single spokes
    with 5 lug nuts); defaults reproduce kestrel_r4 exactly                       [added: aurelia_sedan]
    add_wheels(car, spec, axles) creates Wheel_FL/FR/RL/RR + Caliper_* with origins at the axle
    centres, identity rotation; left wheels are geometry-mirrored.
Interior: bucket_seat(x, y_front, y_back, z_base, ..., bench=False) (bench=True -> rear bench),
    steering_wheel_part(R) (hub at origin, rim in local XZ, +Y = column toward the dash; parent it
    with rotation (-column_tilt, 0, 0); optional spokes=[(angle_deg, width)], hub_r, flat_bottom),
    gauge(center, normal, r); dash/console via sweep_axis.
    Extra material keys (e.g. 'InteriorWood') can be added to the materials dict; they are appended as
    extra slots of the object that uses them (Godot matches materials by name prefix).
    After the +Y-up glTF export the steering column axis is node-local -Z in Godot (Blender +Y),
    wheels still spin about local X.

MATERIALS
---------
default_materials(paint=(r, g, b), ...) -> dict key -> spec; CarAssembly creates "<Key>_<car_id>".
Keys used: Paint Trim Chrome Grille Carbon Underbody Glass Interior InteriorDark Gauge Rubber Rim
BrakeDisc Caliper HeadlightLens TaillightLens BrakeLens ReverseLens. Glass is BLENDED (glTF
alphaMode BLEND) and double sided. Values are plain Principled inputs (survive glTF).

QA / EXPORT
-----------
tri_counts(car) -> {object: tris, 'total': n};  render_hero(car, png_path, cam_loc, target, lens)
(EEVEE, camera/sun/ground/world in the hidden "_QA" collection, Standard view transform, all render
settings restored); qa_checks(car, R, W) -> wheel ground contact, arch clearance, outward normals;
read_glb(path) -> node/material summary parsed from the GLB JSON chunk (alphaMode etc.).
export_car(car, glb_path) -> (operator result, read_glb summary); selects root + children only.
write_car_json(car, json_path, data) -> writes the dict (build it like kestrel_r4.measure()).
to_godot(v) -> [x, z, -y] (Blender -> Godot coordinates).

TIPS (learned building kestrel_r4)
----------------------------------
* Keep the key polygon K0..K8 ordered and roughly convex at every station, otherwise the section
  spline loops. On hood/deck stations put K5..K8 on the hood surface (K6 just a hood sample point).
* Use per-param "sharp" dicts; a float sharp creases EVERY band at that station (visible streaks).
* End caps need the pole plane in front of the whole end ring (D > 0); k_face ~2 gives a flat
  fascia with a tight edge, k_edge ~0.8-1.0 controls the edge radius.
* The `look` tool's "front" view looks from -Y, i.e. it shows the car's REAR (car faces +Y).
* Budget (evaluated): Body <= 30k, Interior <= 10k, each wheel <= 3.5k, car <= 60k tris. kestrel_r4:
  Body 27k (shell ~15k with step 0.05 + bands [3,3,5,5,2,6,2,7]), wheel 3.26k (48 segments).
* Check the cockpit view from Socket_CamCockpit: the dash/binnacle must stay below the line of sight
  over the windscreen base or the hood disappears. qa_checks + an "interior vertices inside wheel
  wells" test catch most intersections; Interior must stay inside the inner shell.
* Write WIP renders to docs/screenshots/ (allowed folder), the hero image to docs/blender_cars/.

TIPS (learned building aurelia_sedan)
-------------------------------------
* All cars sit at the origin: exclude the other Car_* layer collections while looking/rendering
  (view-layer exclude only; see aurelia_sedan.isolate()) and restore before saving.
* End caps: a short loft-to-pole distance (2.5-4 cm) with k_edge ~2.4 / k_face ~2.8 gives a flat,
  crease-free fascia with a tight edge; a long cap (8 cm) makes a visible pyramid (X-shaped shading).
* Arch lips: the bevelled lip darkens the clear coat above the wheel through shared vertex normals.
  After finalize(), mark the panel<->lip boundary edges sharp (aurelia_sedan.sharpen_arch_lips()).
* Cockpit: put the dials on the dash face so they are seen through the upper half of the wheel
  (from the eye: rim top ~18 deg, hub top ~27 deg below horizontal); a tall binnacle hides the bonnet.

ADDED FOR brute_68 (all optional; existing defaults unchanged)
-------------------------------------------------------------
densify(pts, max_len, closed)        split long outline edges before patch/rim/line(smooth=False)
sweep_path(path, profiles, mats, normals=...)   loft a 2D profile (u = side/outward, v = up) along a
    3D polyline, e.g. wrap-around chrome bumpers or a hood brow (see brute_68.blade_bumper)
Surface.outline_at_z(z, center, a0, a1, n, ahead) -> [(point, outward horizontal normal)] plan outline
Surface.patch(..., bulge_fn=f(co2d, dist))      variable-height raised panel (hood power bulge)
build_wheel(style='slot', slot_r=(ra, rb), slot_w=(wa, wb), tyre='tall', grooves=[...], groove_w)
    solid dished "slot mag" face (CDT with holes) and a bulged tall-tyre sidewall
steering_wheel_part(rim_mat='InteriorWood', spoke_mat='Chrome', hub_mat, marker=False, spoke_thick, dish)

TIPS (learned building brute_68)
--------------------------------
* Projected details only follow the shell at their vertices: a fillet_poly/rrect outline with long
  straight edges (grilles, tail panels, bars) sinks into a domed fascia in the middle -> densify() it
  (0.05-0.1 m is enough on a flat face); patches without interior points (res=0) on curved areas
  (plate recess at a rounded lower edge) also sink -> give them res > 0.
* A rim/tub coplanar with the wheel-well wall z-fights: keep the inner-shell tub x-limit ~1.5 cm
  inside the arch x_in.
* Line ribbons cost 6 tris per sample: use step 0.025-0.045 on long mouldings (default 0.012 is for
  short shut lines); walls=False on big flat patches framed by a rim.
* `look` cannot frame objects in the hidden _QA collection, and an empty (zero size) as target gives
  a broken clip range; to inspect a region target a small MESH part of the car (Lights_*, a wheel,
  the steering wheel) with an explicit distance; for the cockpit view set the
  QA camera's matrix_world directly, look(mode='camera'), then restore scene.camera.

ADDED FOR sora_s2 (all optional; existing defaults unchanged)
-------------------------------------------------------------
build_wheel(style='split', spokes=10, split=dict(split_f=0.40, stem_w=(0.030, 0.006), arm_w=(0.0135, 0.004),
    arm_gap=0.050), rim_segs=40)   Y-shaped split spokes (stem from the hub, two thin arms to the rim; arms sit
    0.8 mm under the capped stem so the junction never z-fights); rim_segs = rim-barrel segment count (default =
    segs). 10 split spokes + 48-seg tyre + 40-seg barrel = 3.44k tris per wheel.

TIPS (learned building sora_s2)
-------------------------------
* Plan-view curvature makes or breaks a modern nose/tail: taper ww/ws/wh over the last ~0.4 m with several
  stations (e.g. 0.87 -> 0.84 -> 0.78 -> 0.70 -> 0.59 -> 0.46 -> 0.35) and keep the cap short (1-3 cm).
* Wing crowns above the hood: K5 (zg) 2-3 cm above K8 (zc) on hood stations + ks {5: 0.6} gives fender peaks
  without loops (mild concavity is fine).
* Patches on a strongly curved lower fascia / rear valance sink (white blotches): use offset >= 3 mm and
  res <= 0.025, and give small patches res > 0 (curtains, reflectors).
* bucket_seat's runner box reaches 0.13 m below z_base: keep z_base >= floor zb + 0.13 or it pokes out under the
  car. sora_s2.interior_leaks() (down ray must hit the Body floor, +-X rays must hit Body or Glass) catches it.
* Cockpit: the hood is only visible if its slope is flatter than the sight line over the cowl
  (eye -> windscreen base); raise the eye / lower the cowl rather than shrinking the dash.
* look(target=<small part>, distance=...) clips everything nearer than the target -> cut-away views; target the
  car root for exterior close-ups. Glossy near-black panels (carbon roof) look grey in material preview (Fresnel);
  check them in solid shading or the EEVEE hero render.

ADDED FOR vortex_x (all optional; existing defaults unchanged)
-------------------------------------------------------------
add_wheels: a per-axle 'R' in spec['front'] / spec['rear'] now also sets that axle's centre height (staggered
    wheel radii, e.g. 0.345 front / 0.36 rear); without a per-axle R the location is the top-level R as before.
build_wheel(center_lock=dict(r, h, sides, mat, ring_mat), nuts=0)   big n-sided centre-lock nut + ring + pin.
steering_wheel_part(flat_top=0.80)   squared-off top (with flat_bottom -> yoke-like racing wheel).

TIPS (learned building vortex_x)
--------------------------------
* Mid-engine rear deck: K5 = haunch crown, K6 = valley, K7 = engine-cover edge raised with `bulge` (0.05-0.07) and
  ks {7: 0.85}; fade bulge -> 0 and lift K6 over the last ~0.3 m or the cover step pinches the rear-face corner.
* Door scoop into a side intake: pull K4 (wh) in by 8-12 cm over ~0.3 m ahead of the haunch and give the haunch
  edge a station `sharp=dict(wh=0.8)`; leave K3 (ww) smooth or the lower door ripples. Keep projected intake
  patches outside the arch circle (+1 cm lip) or they land on the wheel-well liner next to the tyre.
* A long K6 jump from the A-pillar base (cowl) to the hood valley twists the panel: add a station ~0.1 m ahead of
  the cowl with intermediate wr/zr.
* Honeycomb on a bulged fascia needs res > 0 for its base patch (res=0 sinks behind the paint -> orange cells).
* All cars sit at the origin, so ck.qa_checks' scene ray casts also hit the other cars: exclude them first.

ADDED FOR granite_rally (all optional; existing defaults unchanged)
-------------------------------------------------------------------
build_wheel(groove_depth=0.010, zigzag=0.006, shoulder_zigzag=0.005)   zig-zag gravel tread: every groove (and the two
    tread-edge rows) shifts sideways on alternate angular segments - no extra triangles. 15" 6-spoke gravel wheel with a
    44-seg 'tall' tyre, 3 grooves and a 36-seg barrel = 3.38k tris.
rod(p0, p1, r, mat, n=8) / rod_path(points, r, mat, n=8, caps=True, closed=False)   round tubes with mitred joints and
    twist-free frames (roll cages, brackets, levers, antennas); torus(center, normal, R, r, mat, nu, nv)   tow loops.

TIPS (learned building granite_rally)
-------------------------------------
* Warps: a band-7 rule boundary (e.g. the rear-glass top on the roof) must sit >= `margin` away from the warp's base y or
  its grid line is dragged along (warps stay constant for t > t1); and `margin` must exceed |y_t - y| or the grid folds.
* Blister flares: doors ~6 cm narrower than the arches (ww 0.866 vs 0.925) with a creased flare-start station
  (sharp=dict(ww=0.6, ws=0.6, wh=0.4)), plus an over-fender seam (S.line on a circle of r_arch + 0.10, clipped at the
  door shut line) - without the seam the bulge hardly reads on a white car.
* The Surface BVH still contains the window faces: a patch with offset = -(glass_inset - 1.5 mm), walls=False, lands
  just above the glass (rally sun strip).
* Long straight lines across a plan-curved fascia sink between samples and look dashed: step <= 0.02, offset 1.5 mm.
* White paint (linear ~0.9) clips in the hero render: exposure ~-0.85 keeps the panel shading readable.
* Chrome lamp reflectors pick up the HDRI tint (olive) in material preview; a rough 'Alu' metal reads as clean silver.

ADDED FOR ridgeback_sx (all optional; existing defaults unchanged)
-----------------------------------------------------------------
block_tyre(R, W, rim_d_in, segs, n, h, rows)   all-terrain tyre: smooth 'tall' carcass with its crown lowered by h, plus n
    raised tread blocks per row (default 4 staggered rows: two shoulder lugs that run down onto the sidewall with
    alternating long/short drops, two skewed centre rows). Each block is a 5-quad hexahedron sunk into the carcass.
build_wheel(blocks=dict(n=26, h=0.013, rows=None) | True)   uses block_tyre for the tyre (segs = carcass segments).
    17" 6-spoke steel-look wheel, 36-seg carcass + 26 blocks x 4 rows + 36-seg barrel = ~3.4k tris.
arch_flare(y, z, r_in, r_out, x_out, x_body, a0, a1, segs, mat)   bolt-on plastic wheel-arch flare (RIGHT side; use
    .mirrored_x()), an arc around the arch centre with a chunky 7-point cross-section whose root is embedded in the
    body side (x_body: float or f(y, z) -> body side x); ends are capped.

ADDED FOR lark_roadster (all optional; existing defaults unchanged)
------------------------------------------------------------------
LoftBody warps may be piecewise linear: dict(y=-0.74, t=(5.0, 6.0, 7.0, 8.0), y_t=(-0.60, -0.70, -0.76, -0.78),
    margin=0.22) bends one grid line into a polyline in (t, y) - e.g. the rounded rear edge of an open roadster cockpit
    (rule role 'open' on bands 5..7). Two-element t / y_t behave exactly as before.

ADDED FOR the kestrel_r4 rework (all optional; existing defaults unchanged)
--------------------------------------------------------------------------
LoftBody.build(cutters=[Part, ...] | f(Surface of the uncut shell) -> [Part, ...])   closed cutter Parts subtracted in the
    arch boolean (use_self is enabled only when cutters are given); their faces keep their material keys and become
    pocket walls: recessed grille mouths, intakes, a plate recess, or a wheel-well liner relief (see kestrel_r4.pocket(),
    kestrel_r4.liner_relief()). Projected details (honeycomb, lines) then land on the pocket floor.
LoftBody.build(frame_backs=0.0006)   reversed copy of every window reveal face just behind it, so the reveals stay solid
    from both sides with single-sided glTF materials (no sky slivers at the screen header in the cockpit camera).

ADDED FOR the traffic vehicles (tools/blender/traffic/*; all optional, existing defaults unchanged)
------------------------------------------------------------------------------------------------
CarAssembly(car_id, name, mats, group='Traffic') -> collection SUNWARD_GODOT/Traffic/Traffic_<car_id> (default None =
    Cars/Car_<car_id> as before); export_car(car, path, extra={...}) passes extra glTF exporter kwargs.
ProfileBody(profile=[(y, z, fillet_r)..], hw, edge_r, edge_segs, step, flat_x, splits, marks)   boxy body: the side
    silhouette extruded across the car with rounded long edges; flat CDT side panels with window holes, a quad
    'band' (floor/front/hood/windscreen/roof/rear) with band windows between two marks. build(car, arches,
    side_holes, band_holes, lining, mat_fn) -> .part (shell, boolean arches + lips), .glass, .reveals, .lining
    (inner cabin skin clipped to the cabin, filled bulkheads), .surface (Surface for projected details).
    splits=[('z', 1.4)] give crisp two-tone livery lines. Use weighted_normals(ob) on the finished Body.
fillet_profile(pts, step) per-corner fillets; abox(p0, p1, mat) axis-aligned box; rbox(axis, s0, s1, c, w, h, r, mat)
    rounded-section bar; bm_to_part(bm, keys, key_of_face); dual_wheel(spec, gap) twin rear tyres; add_axle(car, key,
    wheel, cal, y, half_track, z) wheel pair with per-axle radius (tractor); weighted_normals(ob) modifier.
"""

import bpy
import bmesh
import math
import json
import os
import struct
import bisect
from mathutils import Vector, Matrix, geometry
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

try:
    _HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:  # executed via exec() without __file__
    _HERE = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort\tools\blender"
PROJECT_DIR = os.path.dirname(os.path.dirname(_HERE))

BODY_MATS = ['Paint', 'Trim', 'Chrome', 'Grille', 'Carbon', 'Underbody']
ROLE_MAT = {'paint': 'Paint', 'trim': 'Trim', 'chrome': 'Chrome', 'grille': 'Grille',
            'carbon': 'Carbon', 'under': 'Underbody'}
PARAMS = ('zb', 'wb', 'zs', 'ws', 'zw', 'ww', 'zh', 'wh', 'zg', 'wg', 'zr', 'wr', 'zc', 'rail', 'bulge',
          's1', 's2', 's3', 's4', 's5', 's6', 's7')


# =====================================================================================
# small math helpers
# =====================================================================================
def clamp(x, a, b):
    return a if x < a else b if x > b else x


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    if e1 == e0:
        return 0.0 if x < e0 else 1.0
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def hermite(p0, m0, p1, m1, u):
    u2 = u * u
    u3 = u2 * u
    return p0 * (2 * u3 - 3 * u2 + 1) + m0 * (u3 - 2 * u2 + u) + p1 * (-2 * u3 + 3 * u2) + m1 * (u3 - u2)


def _unit(v, fallback=None):
    L = v.length
    if L < 1e-12:
        return fallback.copy() if fallback is not None else v.copy()
    return v / L


class Curve1D:
    """Monotone cubic (PCHIP) y(x) with optional per-knot sharpness (0 smooth .. 1 crease)."""

    def __init__(self, xs, ys, sharp=None):
        n = len(xs)
        self.xs = list(xs)
        self.ys = list(ys)
        sharp = sharp or [0.0] * n
        self.h = [xs[k + 1] - xs[k] for k in range(n - 1)]
        d = [(ys[k + 1] - ys[k]) / self.h[k] if self.h[k] > 1e-12 else 0.0 for k in range(n - 1)]
        self.mL = [0.0] * n
        self.mR = [0.0] * n
        for k in range(n):
            if n == 1:
                break
            if k == 0:
                m = d[0]
            elif k == n - 1:
                m = d[-1]
            else:
                d0, d1 = d[k - 1], d[k]
                if d0 * d1 <= 0:
                    m = 0.0
                else:
                    h0, h1 = self.h[k - 1], self.h[k]
                    w1, w2 = 2 * h1 + h0, h1 + 2 * h0
                    m = (w1 + w2) / (w1 / d0 + w2 / d1)
            s = sharp[k]
            self.mL[k] = m * (1 - s) + (d[k - 1] if k > 0 else m) * s
            self.mR[k] = m * (1 - s) + (d[k] if k < n - 1 else m) * s

    def __call__(self, x):
        xs = self.xs
        if len(xs) == 1:
            return self.ys[0]
        if x <= xs[0]:
            return self.ys[0] + self.mR[0] * (x - xs[0])
        if x >= xs[-1]:
            return self.ys[-1] + self.mL[-1] * (x - xs[-1])
        k = bisect.bisect_right(xs, x) - 1
        k = min(max(k, 0), len(xs) - 2)
        h = self.h[k]
        u = (x - xs[k]) / h
        return hermite(self.ys[k], self.mR[k] * h, self.ys[k + 1], self.mL[k + 1] * h, u)


# =====================================================================================
# 2D outline helpers
# =====================================================================================
def poly_area(pts):
    a = 0.0
    n = len(pts)
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        a += p[0] * q[1] - q[0] * p[1]
    return 0.5 * a


def point_in_poly(p, pts):
    x, y = p[0], p[1]
    inside = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i][0], pts[i][1]
        xj, yj = pts[j][0], pts[j][1]
        if (yi > y) != (yj > y):
            xc = (xj - xi) * (y - yi) / (yj - yi + 1e-18) + xi
            if x < xc:
                inside = not inside
        j = i
    return inside


def dist_to_poly(p, pts, closed=True):
    best = 1e9
    n = len(pts)
    rng = range(n) if closed else range(n - 1)
    px, py = p[0], p[1]
    for i in rng:
        ax, ay = pts[i][0], pts[i][1]
        bx, by = pts[(i + 1) % n][0], pts[(i + 1) % n][1]
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 < 1e-18 else clamp(((px - ax) * dx + (py - ay) * dy) / L2, 0.0, 1.0)
        qx, qy = ax + t * dx - px, ay + t * dy - py
        best = min(best, math.sqrt(qx * qx + qy * qy))
    return best


def cr_resample(pts, closed=True, sub=6, corners=()):
    """Hermite/Catmull-Rom resampling of a 2D or 3D polyline. `corners`: indices kept sharp."""
    P = [Vector(p) for p in pts]
    n = len(P)
    if n < 3 or sub <= 1:
        return [p.copy() for p in P]
    out = []
    segs = n if closed else n - 1
    cs = set(corners)
    for i in range(segs):
        p1 = P[i]
        p2 = P[(i + 1) % n]
        p0 = P[(i - 1) % n] if (closed or i > 0) else P[0]
        p3 = P[(i + 2) % n] if (closed or i + 2 < n) else P[n - 1]
        L = (p2 - p1).length
        chord = p2 - p1
        t1 = _unit(_unit(p1 - p0, chord) + _unit(chord, chord), chord) if (p1 - p0).length > 1e-9 else _unit(chord)
        t2 = _unit(_unit(chord, chord) + _unit(p3 - p2, chord), chord) if (p3 - p2).length > 1e-9 else _unit(chord)
        if i in cs:
            t1 = _unit(chord)
        if ((i + 1) % n) in cs:
            t2 = _unit(chord)
        for k in range(sub):
            out.append(hermite(p1, t1 * L, p2, t2 * L, k / sub))
    if not closed:
        out.append(P[-1].copy())
    return out


def offset_poly(pts, d):
    """Offset a closed 2D polygon by d (positive = outward for CCW input)."""
    n = len(pts)
    ccw = poly_area(pts) > 0
    out = []
    for i in range(n):
        a, p, b = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0 = _unit(p - a)
        e1 = _unit(b - p)
        n0 = Vector((e0.y, -e0.x))
        n1 = Vector((e1.y, -e1.x))
        if not ccw:
            n0, n1 = -n0, -n1
        nm = _unit(n0 + n1, n1)
        c = max(nm.dot(n1), 0.35)
        out.append(p + nm * (d / c))
    return out


def rrect_pts(cx, cy, w, h, r, n=4):
    """Rounded rectangle (CCW) centred at (cx, cy)."""
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    pts = []
    for (ox, oy, a0) in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                         (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append(Vector((cx + ox + r * math.cos(a), cy + oy + r * math.sin(a))))
    return pts


def fillet_poly(pts, r, n=4):
    """Closed 2D polygon with every corner rounded by radius r (float or one per corner; 0 = sharp).
    Straight edges stay straight (unlike cr_resample, which bulges long edges). Use with
    Surface.patch/rim(..., smooth=False)."""
    P = [Vector((p[0], p[1])) for p in pts]
    m = len(P)
    rs = list(r) if hasattr(r, '__len__') else [r] * m
    out = []
    for i in range(m):
        a, p, b = P[i - 1], P[i], P[(i + 1) % m]
        ea, eb = a - p, b - p
        la, lb = ea.length, eb.length
        if rs[i] <= 0 or la < 1e-9 or lb < 1e-9:
            out.append(p.copy())
            continue
        ua, ub = ea / la, eb / lb
        cosang = clamp(ua.dot(ub), -0.9999, 0.9999)
        half = math.acos(cosang) / 2.0
        d = min(rs[i] / max(math.tan(half), 1e-6), 0.45 * la, 0.45 * lb)
        t0, t1 = p + ua * d, p + ub * d
        for k in range(n + 1):           # quadratic Bezier t0 -> corner -> t1 (tangent continuous)
            s = k / n
            out.append(t0 * (1 - s) * (1 - s) + p * 2 * s * (1 - s) + t1 * s * s)
    return out


def densify(pts, max_len=0.02, closed=True):
    """Split polygon edges longer than max_len (added for brute_68). Projected details (patch / rim /
    line with smooth=False) only follow the surface at their vertices, so long straight edges on a
    curved panel sink into it; densify the outline first."""
    P = [Vector((p[0], p[1])) if len(p) == 2 else Vector(p) for p in pts]
    n = len(P)
    out = []
    for i in range(n if closed else n - 1):
        a, b = P[i], P[(i + 1) % n]
        k = max(1, int(math.ceil((b - a).length / max_len)))
        for j in range(k):
            out.append(a.lerp(b, j / k))
    if not closed:
        out.append(P[-1].copy())
    return out


def superellipse_pts(cx, cy, a, b, e=2.5, n=32):
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / e), c)
        y = b * math.copysign(abs(s) ** (2 / e), s)
        pts.append(Vector((cx + x, cy + y)))
    return pts


# =====================================================================================
# Part: lightweight mesh accumulator
# =====================================================================================
class Part:
    def __init__(self):
        self.v = []
        self.f = []
        self.m = []

    def vert(self, co):
        self.v.append(Vector(co))
        return len(self.v) - 1

    def face(self, idx, mat):
        out = []
        for i in idx:                      # drop consecutive duplicates (poles -> triangles)
            if not out or out[-1] != i:
                out.append(i)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
        if len(out) < 3 or len(set(out)) != len(out):
            return
        self.f.append(tuple(out))
        self.m.append(mat)

    def extend(self, *others):
        for other in others:
            if other is None:
                continue
            o = len(self.v)
            self.v.extend(v.copy() for v in other.v)
            self.f.extend(tuple(i + o for i in f) for f in other.f)
            self.m.extend(other.m)
        return self

    def copy(self):
        return Part().extend(self)

    def mirrored_x(self):
        p = Part()
        p.v = [Vector((-v.x, v.y, v.z)) for v in self.v]
        p.f = [tuple(reversed(f)) for f in self.f]
        p.m = list(self.m)
        return p

    def with_mirror(self):
        return self.copy().extend(self.mirrored_x())

    def transformed(self, M):
        p = Part()
        p.v = [M @ v for v in self.v]
        flip = M.to_3x3().determinant() < 0
        p.f = [tuple(reversed(f)) if flip else f for f in self.f]
        p.m = list(self.m)
        return p

    def translated(self, d):
        return self.transformed(Matrix.Translation(Vector(d)))

    def set_mat(self, mat):
        self.m = [mat] * len(self.f)
        return self

    def tris(self):
        return sum(len(f) - 2 for f in self.f)

    def centroid(self):
        if not self.v:
            return Vector()
        c = Vector()
        for v in self.v:
            c += v
        return c / len(self.v)

    def face_normal(self, fi):
        f = self.f[fi]
        n = Vector()
        for k in range(len(f)):
            a = self.v[f[k]]
            b = self.v[f[(k + 1) % len(f)]]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        return n

    def face_center(self, fi):
        f = self.f[fi]
        c = Vector()
        for i in f:
            c += self.v[i]
        return c / len(f)

    def orient(self, start=0, ref=None, ref_fn=None, inward=False):
        """Reverse faces (from index `start`) whose normal points toward `ref` (or ref_fn(center))."""
        for fi in range(start, len(self.f)):
            c = self.face_center(fi)
            r = ref_fn(c) if ref_fn else ref
            n = self.face_normal(fi)
            d = n.dot(c - r)
            if (d < 0) != inward:
                self.f[fi] = tuple(reversed(self.f[fi]))
        return self


# =====================================================================================
# primitive builders
# =====================================================================================
def revolve(profile, segs, mats, theta0=-math.pi / 2, theta1=None, caps=False, cap_mat=None):
    """Lathe about the X axis. profile: [(a, r)] with a = x, r = radius; angle 0 = +Y, pi/2 = +Z.
    Traverse the profile so the outside lies on the LEFT of travel in the (a, r) plane (e.g. tread
    from -x to +x) to get outward normals. mats: one key or one per profile segment."""
    full = theta1 is None
    if full:
        theta1 = theta0 + 2 * math.pi
    n_ang = segs if full else segs + 1
    part = Part()
    rows = []
    for (a, r) in profile:
        if r < 1e-7:
            rows.append([part.vert((a, 0, 0))] * n_ang)
            continue
        row = []
        for j in range(n_ang):
            t = theta0 + (theta1 - theta0) * j / segs
            row.append(part.vert((a, r * math.cos(t), r * math.sin(t))))
        rows.append(row)
    for k in range(len(profile) - 1):
        mk = mats[k] if isinstance(mats, (list, tuple)) else mats
        for j in range(segs):
            j2 = (j + 1) % n_ang if full else j + 1
            part.face((rows[k][j], rows[k][j2], rows[k + 1][j2], rows[k + 1][j]), mk)
    if caps and not full:
        cm = cap_mat or (mats[0] if isinstance(mats, (list, tuple)) else mats)
        part.face([rows[k][0] for k in range(len(profile))], cm)
        part.face([rows[k][n_ang - 1] for k in reversed(range(len(profile)))], cm)
    return part


def sweep_axis(axis, stations, profiles, mats, cap0=True, cap1=True, cap_mat=None, closed=True):
    """Loft 2D profiles along a principal axis. axis 'x': profile (y, z); 'y': (x, z); 'z': (x, y).
    profiles: list (one per station) of equal-length point lists, or a single list for all.
    mats: key or list per profile segment. Faces are oriented outward automatically."""
    if hasattr(profiles[0][0], '__len__'):
        profs = profiles                      # one profile per station
    else:
        profs = [profiles] * len(stations)    # a single profile for all stations

    def to3(s, p):
        a, b = p[0], p[1]
        if axis == 'x':
            return Vector((s, a, b))
        if axis == 'y':
            return Vector((a, s, b))
        return Vector((a, b, s))

    part = Part()
    rows = []
    for s, prof in zip(stations, profs):
        rows.append([part.vert(to3(s, p)) for p in prof])
    n = len(profs[0])
    nseg = n if closed else n - 1
    for i in range(len(stations) - 1):
        for k in range(nseg):
            k2 = (k + 1) % n
            mk = mats[k] if isinstance(mats, (list, tuple)) else mats
            part.face((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]), mk)
    # orientation of the side faces: outward from the station centroid
    centers = []
    for prof, s in zip(profs, stations):
        c = Vector()
        for p in prof:
            c += to3(s, p)
        centers.append(c / len(prof))
    # decide using majority vote
    votes = 0
    for fi in range(len(part.f)):
        i = fi // nseg
        c = part.face_center(fi)
        ax = {'x': 0, 'y': 1, 'z': 2}[axis]
        ref = centers[i].lerp(centers[i + 1], 0.5)
        ref[ax] = c[ax]
        votes += 1 if part.face_normal(fi).dot(c - ref) > 0 else -1
    if votes < 0:
        part.f = [tuple(reversed(f)) for f in part.f]
    cm = cap_mat or (mats[0] if isinstance(mats, (list, tuple)) else mats)
    axv = {'x': Vector((1, 0, 0)), 'y': Vector((0, 1, 0)), 'z': Vector((0, 0, 1))}[axis]
    sgn = 1 if stations[-1] > stations[0] else -1
    if closed and cap0:
        part.face(rows[0], cm)
        if part.face_normal(len(part.f) - 1).dot(axv) * sgn > 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    if closed and cap1:
        part.face(rows[-1], cm)
        if part.face_normal(len(part.f) - 1).dot(axv) * sgn < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def sweep_path(path, profiles, mats, up=(0, 0, 1), cap0=True, cap1=True, cap_mat=None, normals=None):
    """Loft a closed 2D profile along a 3D polyline (added for brute_68: wrap-around bumpers, mouldings).
    Profile coords (u, v): u along the side vector (tangent x up, i.e. to the RIGHT of travel, or the given
    per-point `normals`), v along the local up. profiles: one list for all points or one per point.
    mats: key or one per profile segment. Faces are oriented outward (majority vote), caps flat."""
    P = [Vector(p) for p in path]
    n = len(P)
    if hasattr(profiles[0][0], '__len__'):
        profs = profiles
    else:
        profs = [profiles] * n
    upv = Vector(up)
    part = Part()
    rows = []
    frames = []
    for i in range(n):
        t = _unit(P[min(i + 1, n - 1)] - P[max(i - 1, 0)], Vector((0, 1, 0)))
        if normals is not None:
            s = Vector(normals[i])
            s = _unit(s - t * s.dot(t), Vector((1, 0, 0)))
        else:
            s = _unit(t.cross(upv), Vector((1, 0, 0)))
        u = _unit(s.cross(t), upv)
        if u.dot(upv) < 0:
            u = -u
        frames.append((s, u))
        rows.append([part.vert(P[i] + s * a + u * b) for (a, b) in profs[i]])
    m = len(profs[0])
    for i in range(n - 1):
        for k in range(m):
            k2 = (k + 1) % m
            mk = mats[k] if isinstance(mats, (list, tuple)) else mats
            part.face((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]), mk)
    votes = 0
    for fi in range(len(part.f)):
        i = fi // m
        c = part.face_center(fi)
        cen = sum((part.v[j] for j in rows[i]), Vector()) / m
        votes += 1 if part.face_normal(fi).dot(c - cen) > 0 else -1
    if votes < 0:
        part.f = [tuple(reversed(f)) for f in part.f]
    cm = cap_mat or (mats[0] if isinstance(mats, (list, tuple)) else mats)
    for (do, i, sgn) in ((cap0, 0, -1), (cap1, n - 1, 1)):
        if not do:
            continue
        part.face(rows[i], cm)
        t = _unit(P[min(i + 1, n - 1)] - P[max(i - 1, 0)])
        if part.face_normal(len(part.f) - 1).dot(t) * sgn < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def box_between(p0, p1, width, height, mat, up=(0, 0, 1)):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    upv = Vector(up)
    side = _unit(d.cross(upv), Vector((1, 0, 0)))
    upn = _unit(side.cross(d), Vector((0, 0, 1)))
    part = Part()
    idx = {}
    for e, base in ((0, p0), (1, p1)):
        for sx in (-1, 1):
            for sz in (-1, 1):
                idx[(e, sx, sz)] = part.vert(base + side * (sx * width / 2) + upn * (sz * height / 2))
    quads = [
        [(0, -1, -1), (0, 1, -1), (0, 1, 1), (0, -1, 1)],
        [(1, -1, -1), (1, -1, 1), (1, 1, 1), (1, 1, -1)],
        [(0, -1, -1), (0, -1, 1), (1, -1, 1), (1, -1, -1)],
        [(0, 1, -1), (1, 1, -1), (1, 1, 1), (0, 1, 1)],
        [(0, -1, 1), (0, 1, 1), (1, 1, 1), (1, -1, 1)],
        [(0, -1, -1), (1, -1, -1), (1, 1, -1), (0, 1, -1)],
    ]
    for q in quads:
        part.face([idx[k] for k in q], mat)
    part.orient(0, ref=(p0 + p1) / 2)
    return part


def ellipsoid(center, radii, mat, nu=16, nv=10, exp=2.0, deform=None):
    """Super-ellipsoid. deform(local_vec) -> local_vec lets callers flatten/skew it."""
    c = Vector(center)
    part = Part()
    rows = []
    for i in range(nv + 1):
        v = -math.pi / 2 + math.pi * i / nv
        cv, sv = math.cos(v), math.sin(v)
        cvp = math.copysign(abs(cv) ** (2 / exp), cv)
        svp = math.copysign(abs(sv) ** (2 / exp), sv)
        if i in (0, nv):
            p = Vector((0, 0, radii[2] * svp))
            if deform:
                p = deform(p)
            rows.append([part.vert(c + p)] * nu)
            continue
        row = []
        for j in range(nu):
            u = 2 * math.pi * j / nu
            cu, su = math.cos(u), math.sin(u)
            p = Vector((radii[0] * cvp * math.copysign(abs(cu) ** (2 / exp), cu),
                        radii[1] * cvp * math.copysign(abs(su) ** (2 / exp), su),
                        radii[2] * svp))
            if deform:
                p = deform(p)
            row.append(part.vert(c + p))
        rows.append(row)
    for i in range(nv):
        for j in range(nu):
            j2 = (j + 1) % nu
            part.face((rows[i][j], rows[i][j2], rows[i + 1][j2], rows[i + 1][j]), mat)
    part.orient(0, ref=c)
    return part


def disc(center, normal, radius, mat, n=24, ring_mat=None, ring_w=0.0):
    c = Vector(center)
    nrm = _unit(Vector(normal))
    u = _unit(nrm.cross(Vector((0, 0, 1))), Vector((1, 0, 0)))
    if u.length < 0.5:
        u = _unit(nrm.cross(Vector((1, 0, 0))))
    w = nrm.cross(u)
    part = Part()
    cv = part.vert(c)
    ring = [part.vert(c + (u * math.cos(2 * math.pi * k / n) + w * math.sin(2 * math.pi * k / n)) * radius) for k in range(n)]
    for k in range(n):
        part.face((cv, ring[k], ring[(k + 1) % n]), mat)
    if ring_mat and ring_w > 0:
        outer = [part.vert(c + (u * math.cos(2 * math.pi * k / n) + w * math.sin(2 * math.pi * k / n)) * (radius + ring_w) + nrm * 0.001) for k in range(n)]
        for k in range(n):
            part.face((ring[k], outer[k], outer[(k + 1) % n], ring[(k + 1) % n]), ring_mat)
    for fi in range(len(part.f)):
        if part.face_normal(fi).dot(nrm) < 0:
            part.f[fi] = tuple(reversed(part.f[fi]))
    return part


def tube(p0, p1, r_out, r_in, mat_out, mat_in, n=20, inner_depth=0.05, cap_mat=None):
    """Exhaust-tip style tube from p0 (inside body) to p1 (open end)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = _unit(p1 - p0)
    u = _unit(d.cross(Vector((0, 0, 1))), Vector((1, 0, 0)))
    w = d.cross(u)
    part = Part()

    def circ(c, r):
        return [part.vert(c + (u * math.cos(2 * math.pi * k / n) + w * math.sin(2 * math.pi * k / n)) * r) for k in range(n)]
    a0 = circ(p0, r_out)
    a1 = circ(p1, r_out)
    b1 = circ(p1, r_in)
    b0 = circ(p1 - d * inner_depth, r_in)
    start = 0
    for k in range(n):
        k2 = (k + 1) % n
        part.face((a0[k], a0[k2], a1[k2], a1[k]), mat_out)
    part.orient(start, ref_fn=lambda c: p0 + d * (c - p0).dot(d))
    s2 = len(part.f)
    for k in range(n):
        k2 = (k + 1) % n
        part.face((a1[k], a1[k2], b1[k2], b1[k]), mat_out)
    for fi in range(s2, len(part.f)):
        if part.face_normal(fi).dot(d) < 0:
            part.f[fi] = tuple(reversed(part.f[fi]))
    s3 = len(part.f)
    for k in range(n):
        k2 = (k + 1) % n
        part.face((b1[k], b1[k2], b0[k2], b0[k]), mat_in)
    part.orient(s3, ref_fn=lambda c: p0 + d * (c - p0).dot(d), inward=True)
    part.face(list(reversed(b0)), cap_mat or mat_in)
    if part.face_normal(len(part.f) - 1).dot(d) < 0:
        part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def rod_path(points, r, mat, n=8, caps=True, closed=False):
    """Round tube of radius r along a 3D polyline (added for granite_rally: roll cages, brackets, tow loops).
    Mitred joints (the ring at an inner point lies in the bisector plane, scaled so the wall stays r thick);
    parallel-transported ring frames (no twist). closed=True joins the last point back to the first."""
    P = [Vector(p) for p in points]
    m = len(P)
    if closed and (P[0] - P[-1]).length < 1e-9:
        P.pop()
        m -= 1
    part = Part()
    if m < 2:
        return part

    def seg_dir(i):
        return _unit(P[(i + 1) % m] - P[i], Vector((0, 0, 1)))
    nseg = m if closed else m - 1
    dirs = [seg_dir(i) for i in range(nseg)]
    t0 = dirs[-1] if closed else dirs[0]
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    u = _unit(ref - t0 * ref.dot(t0))
    rows = []
    for i in range(m):
        if closed:
            din, dout = dirs[i - 1], dirs[i % nseg]
        else:
            din = dirs[max(i - 1, 0)]
            dout = dirs[min(i, nseg - 1)]
        tb = _unit(din + dout, dout)                       # bisector plane normal
        # parallel transport u onto the plane perpendicular to dout (keeps the frame twist-free)
        u = _unit(u - dout * u.dot(dout), u)
        w = dout.cross(u)
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            off = u * (r * math.cos(a)) + w * (r * math.sin(a))
            # slide the circle point along dout onto the bisector (mitre) plane
            s = -off.dot(tb) / max(dout.dot(tb), 0.3)
            ring.append(part.vert(P[i] + off + dout * s))
        rows.append(ring)
    for i in range(nseg):
        a_, b_ = rows[i], rows[(i + 1) % m]
        for k in range(n):
            k2 = (k + 1) % n
            part.face((a_[k], a_[k2], b_[k2], b_[k]), mat)
    part.orient(0, ref_fn=lambda c: _closest_on_poly(P, c, closed))
    if caps and not closed:
        part.face(list(reversed(rows[0])), mat)
        if part.face_normal(len(part.f) - 1).dot(dirs[0]) > 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
        part.face(list(rows[-1]), mat)
        if part.face_normal(len(part.f) - 1).dot(dirs[-1]) < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def _closest_on_poly(P, c, closed=False):
    best, bd = P[0], 1e18
    m = len(P)
    for i in range(m if closed else m - 1):
        a, b = P[i], P[(i + 1) % m]
        ab = b - a
        L2 = ab.length_squared
        t = 0.0 if L2 < 1e-18 else clamp((c - a).dot(ab) / L2, 0.0, 1.0)
        q = a + ab * t
        d = (q - c).length_squared
        if d < bd:
            best, bd = q, d
    return best


def rod(p0, p1, r, mat, n=8, caps=True):
    """Straight round tube from p0 to p1 (added for granite_rally)."""
    return rod_path([p0, p1], r, mat, n=n, caps=caps)


def torus(center, normal, R, r, mat, nu=16, nv=8):
    """Torus (ring) of major radius R and tube radius r around `normal` (added for granite_rally: tow loops)."""
    c = Vector(center)
    nrm = _unit(Vector(normal))
    u = _unit(nrm.cross(Vector((0, 0, 1))), Vector((1, 0, 0)))
    if u.length < 0.5:
        u = _unit(nrm.cross(Vector((1, 0, 0))))
    w = nrm.cross(u)
    part = Part()
    rows = []
    for i in range(nu):
        a = 2 * math.pi * i / nu
        e = u * math.cos(a) + w * math.sin(a)
        rows.append([part.vert(c + e * (R + r * math.cos(2 * math.pi * j / nv)) + nrm * (r * math.sin(2 * math.pi * j / nv)))
                     for j in range(nv)])
    for i in range(nu):
        for j in range(nv):
            part.face((rows[i][j], rows[(i + 1) % nu][j], rows[(i + 1) % nu][(j + 1) % nv], rows[i][(j + 1) % nv]), mat)
    part.orient(0, ref_fn=lambda q: c + _unit((q - c) - nrm * (q - c).dot(nrm)) * R)
    return part


# =====================================================================================
# Surface projection
# =====================================================================================
class Surface:
    VIEWS = {
        'right': (Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((-1, 0, 0))),
        'left': (Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))),
        'front': (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0))),
        'rear': (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0))),
        'top': (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, -1))),
    }

    def __init__(self, bm):
        self.bvh = BVHTree.FromBMesh(bm)

    def frame(self, view):
        if isinstance(view, str):
            U, V, D = self.VIEWS[view]
            return (Vector((0, 0, 0)), U, V, D)
        return tuple(Vector(x) for x in view)

    def hit(self, frame, a, b):
        O, U, V, D = frame
        origin = O + U * a + V * b - D * 8.0
        loc, nor, idx, dist = self.bvh.ray_cast(origin, D, 30.0)
        if loc is None:
            return None, None
        if nor.dot(D) > 0:
            nor = -nor
        return loc, nor

    def snap(self, view, a, b):
        loc, nor = self.hit(self.frame(view), a, b)
        return loc

    def nearest(self, p):
        loc, nor, idx, d = self.bvh.find_nearest(Vector(p))
        return loc, nor

    def frame_from_points(self, pts3d):
        snapped = []
        nsum = Vector()
        for p in pts3d:
            loc, nor = self.nearest(p)
            snapped.append(loc)
            nsum += nor
        D = -_unit(nsum)
        O = Vector()
        for p in snapped:
            O += p
        O /= len(snapped)
        U = _unit(D.cross(Vector((0, 0, 1))), Vector((1, 0, 0)))
        if U.length < 0.5:
            U = _unit(D.cross(Vector((1, 0, 0))))
        V = U.cross(D)
        # make (U, V, -D) right handed with U x V = -D
        if U.cross(V).dot(D) > 0:
            V = -V
        frame = (O, U, V, D)
        pts2d = [Vector(((p - O).dot(U), (p - O).dot(V))) for p in snapped]
        return frame, pts2d

    # -------------------------------------------------------------------------------
    def patch(self, outline, view, offset=0.002, depth=0.004, bulge=0.0, bulge_w=0.02, res=0.02,
              mat='Trim', smooth=True, sub=4, corners=(), walls=True, wall_mat=None, bulge_fn=None):
        """bulge_fn (optional, added for brute_68): f(co2d, dist_to_outline) -> extra offset along the
        surface normal (e.g. a hood power bulge whose height varies along the car)."""
        frame = self.frame(view)
        O, U, V, D = frame
        pts = [Vector((p[0], p[1])) for p in outline]
        if smooth:
            pts = cr_resample(pts, True, sub, corners)
        if poly_area(pts) < 0:
            pts.reverse()
        nb = len(pts)
        verts2d = list(pts)
        if res > 0:
            xs = [p.x for p in pts]
            ys = [p.y for p in pts]
            gx = min(xs) + res * 0.5
            while gx < max(xs):
                gy = min(ys) + res * 0.5
                while gy < max(ys):
                    g = Vector((gx, gy))
                    if point_in_poly(g, pts) and dist_to_poly(g, pts) > res * 0.45:
                        verts2d.append(g)
                    gy += res
                gx += res
        out = geometry.delaunay_2d_cdt(verts2d, [(k, (k + 1) % nb) for k in range(nb)], [list(range(nb))], 1, 1e-7)
        ov, of, orig_v = out[0], out[2], out[3]
        part = Part()
        top = {}
        hits = {}
        for k, co in enumerate(ov):
            loc, nor = self.hit(frame, co.x, co.y)
            if loc is None:
                continue
            b_amt = 0.0
            if bulge_fn is not None:
                b_amt = bulge_fn(co, dist_to_poly(co, pts))
            elif bulge:
                b_amt = bulge * smoothstep(0.0, bulge_w, dist_to_poly(co, pts))
            top[k] = part.vert(loc + nor * (offset + b_amt))
            hits[k] = (loc, nor)
        want = -D
        for f in of:
            if all(k in top for k in f):
                part.face([top[k] for k in f], mat)
                if part.face_normal(len(part.f) - 1).dot(want) < 0:
                    part.f[-1] = tuple(reversed(part.f[-1]))
        if walls:
            bmap = {}
            for k, origs in enumerate(orig_v):
                for o in origs:
                    if o < nb:
                        bmap[o] = k
            loop = [bmap.get(i) for i in range(nb)]
            bot = {}
            for k in loop:
                if k is not None and k in hits:
                    loc, nor = hits[k]
                    bot[k] = part.vert(loc - nor * depth)
            for i in range(nb):
                a, b = loop[i], loop[(i + 1) % nb]
                if a is None or b is None or a not in top or b not in top:
                    continue
                part.face((top[a], top[b], bot[b], bot[a]), wall_mat or mat)
                e = pts[(i + 1) % nb] - pts[i]
                o2 = Vector((e.y, -e.x))
                o3 = U * o2.x + V * o2.y
                if part.face_normal(len(part.f) - 1).dot(o3) < 0:
                    part.f[-1] = tuple(reversed(part.f[-1]))
        return part

    def outline_at_z(self, z, center=(0.0, 0.0), a0=-90.0, a1=90.0, n=40, ahead=1):
        """Plan outline of the shell at height z (added for brute_68): horizontal rays from outside toward
        `center` (x, y) for angles a0..a1 (deg; 0 = +Y (ahead=1) or -Y (ahead=-1), +90 = +X).
        Returns [(point, outward horizontal normal)] (misses skipped)."""
        out = []
        c = Vector((center[0], center[1], z))
        for k in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * k / n)
            d = Vector((math.sin(a), ahead * math.cos(a), 0.0))
            loc, nor, idx, dist = self.bvh.ray_cast(c + d * 6.0, -d, 12.0)
            if loc is None:
                continue
            nh = Vector((nor.x, nor.y, 0.0))
            if nh.length < 1e-6 or nh.dot(d) < 0:
                nh = d.copy()
            out.append((loc, nh.normalized()))
        return out

    def patch3d(self, pts3d, **kw):
        frame, pts2d = self.frame_from_points(pts3d)
        kw.setdefault('smooth', True)
        return self.patch(pts2d, frame, **kw), frame

    def rim(self, outline, view, width=0.01, offset=0.004, depth=0.004, mat='Trim', smooth=True, sub=4,
            corners=(), inner_walls=True):
        """Raised frame around (outside) a closed outline."""
        frame = self.frame(view)
        O, U, V, D = frame
        pts = [Vector((p[0], p[1])) for p in outline]
        if smooth:
            pts = cr_resample(pts, True, sub, corners)
        if poly_area(pts) < 0:
            pts.reverse()
        outer = offset_poly(pts, width)
        part = Part()
        n = len(pts)
        rows = []
        for ring in (pts, outer):
            row = []
            for p in ring:
                loc, nor = self.hit(frame, p.x, p.y)
                if loc is None:
                    row.append(None)
                    continue
                row.append((part.vert(loc + nor * offset), part.vert(loc - nor * depth)))
            rows.append(row)
        want = -D
        for i in range(n):
            j = (i + 1) % n
            a0, a1, b0, b1 = rows[0][i], rows[0][j], rows[1][i], rows[1][j]
            if None in (a0, a1, b0, b1):
                continue
            part.face((a0[0], a1[0], b1[0], b0[0]), mat)
            if part.face_normal(len(part.f) - 1).dot(want) < 0:
                part.f[-1] = tuple(reversed(part.f[-1]))
            e = pts[j] - pts[i]
            o2 = Vector((e.y, -e.x))
            o3 = U * o2.x + V * o2.y
            part.face((b0[0], b1[0], b1[1], b0[1]), mat)
            if part.face_normal(len(part.f) - 1).dot(o3) < 0:
                part.f[-1] = tuple(reversed(part.f[-1]))
            if inner_walls:
                part.face((a0[0], a1[0], a1[1], a0[1]), mat)
                if part.face_normal(len(part.f) - 1).dot(-o3) < 0:
                    part.f[-1] = tuple(reversed(part.f[-1]))
        return part

    def _ribbon(self, samples, width, offset, mat, closed=False, depth=0.0015):
        part = Part()
        n = len(samples)
        rows = []
        for k in range(n):
            s = samples[k]
            if s is None:
                rows.append(None)
                continue
            loc, nor = s
            prv = samples[k - 1] if (k > 0 or closed) else None
            nxt = samples[(k + 1) % n] if (k < n - 1 or closed) else None
            a = prv[0] if prv else loc
            b = nxt[0] if nxt else loc
            t = _unit(b - a, Vector((1, 0, 0)))
            side = _unit(nor.cross(t), Vector((0, 0, 1)))
            c = loc + nor * offset
            rows.append((part.vert(c - side * width / 2), part.vert(c + side * width / 2),
                         part.vert(loc - side * width / 2 - nor * depth), part.vert(loc + side * width / 2 - nor * depth), nor))
        segs = n if closed else n - 1
        for k in range(segs):
            a, b = rows[k], rows[(k + 1) % n]
            if a is None or b is None:
                continue
            nor = a[4]
            part.face((a[0], b[0], b[1], a[1]), mat)
            if part.face_normal(len(part.f) - 1).dot(nor) < 0:
                part.f[-1] = tuple(reversed(part.f[-1]))
            # small side walls so the ribbon never shows a gap from grazing angles
            for (i0, i1) in ((0, 2), (1, 3)):
                part.face((a[i0], b[i0], b[i1], a[i1]), mat)
                c = part.face_center(len(part.f) - 1)
                mid = (part.v[a[0]] + part.v[a[1]]) / 2
                if part.face_normal(len(part.f) - 1).dot(c - mid) < 0:
                    part.f[-1] = tuple(reversed(part.f[-1]))
        return part

    def line(self, pts2d, view, width=0.003, offset=0.0008, mat='Trim', step=0.012, closed=False, smooth=True):
        frame = self.frame(view)
        pts = [Vector((p[0], p[1])) for p in pts2d]
        if smooth and len(pts) > 2:
            dense = cr_resample(pts, closed, 8)
        else:
            dense = pts + ([pts[0]] if closed else [])
        # resample at ~step spacing
        res = [dense[0]]
        acc = 0.0
        for k in range(1, len(dense)):
            seg = (dense[k] - dense[k - 1]).length
            acc += seg
            if acc >= step:
                res.append(dense[k])
                acc = 0.0
        if (res[-1] - dense[-1]).length > 1e-6 and not closed:
            res.append(dense[-1])
        samples = []
        for p in res:
            loc, nor = self.hit(frame, p.x, p.y)
            samples.append((loc, nor) if loc is not None else None)
        return self._ribbon(samples, width, offset, mat, closed)

    def line3d(self, pts3d, width=0.003, offset=0.0008, mat='Trim', step=0.012, closed=False):
        pts = cr_resample([Vector(p) for p in pts3d], closed, 8) if len(pts3d) > 2 else [Vector(p) for p in pts3d]
        res = [pts[0]]
        acc = 0.0
        for k in range(1, len(pts)):
            acc += (pts[k] - pts[k - 1]).length
            if acc >= step:
                res.append(pts[k])
                acc = 0.0
        if not closed:
            res.append(pts[-1])
        samples = [self.nearest(p) for p in res]
        return self._ribbon(samples, width, offset, mat, closed)

    def honeycomb(self, outline, view, cell=0.045, wall=0.006, base_offset=0.0015, height=0.007, margin=0.01,
                  mat_base='Grille', mat_cell='Grille', base=True, smooth=True, sub=4, corners=(), res=0.03,
                  outer_walls=False):
        frame = self.frame(view)
        O, U, V, D = frame
        part = Part()
        pts = [Vector((p[0], p[1])) for p in outline]
        if smooth:
            pts = cr_resample(pts, True, sub, corners)
        if poly_area(pts) < 0:
            pts.reverse()
        if base:
            part.extend(self.patch(pts, frame, offset=base_offset, depth=0.004, res=res, mat=mat_base, smooth=False))
        R = cell / 2.0
        r_in = R - (wall / 2.0) / math.cos(math.radians(30))
        dx = 1.5 * R
        dy = math.sqrt(3) * R
        xs = [p.x for p in pts]
        ys = [p.y for p in pts]
        want = -D
        col = 0
        x = min(xs)
        while x <= max(xs) + R:
            y = min(ys) + (dy / 2 if col % 2 else 0.0)
            while y <= max(ys) + R:
                c = Vector((x, y))
                corners_ok = all(point_in_poly(c + Vector((R * math.cos(math.radians(60 * k)), R * math.sin(math.radians(60 * k)))), pts) for k in range(6))
                if corners_ok and dist_to_poly(c, pts) > R * 0.9 + margin * 0.5:
                    outer = []
                    inner = []
                    ok = True
                    for k in range(6):
                        a = math.radians(60 * k)
                        for rr, lst in ((R, outer), (r_in, inner)):
                            p = c + Vector((rr * math.cos(a), rr * math.sin(a)))
                            loc, nor = self.hit(frame, p.x, p.y)
                            if loc is None:
                                ok = False
                                break
                            lst.append((loc, nor))
                        if not ok:
                            break
                    if ok:
                        ot = [part.vert(l + n * (base_offset + height)) for (l, n) in outer]
                        it = [part.vert(l + n * (base_offset + height)) for (l, n) in inner]
                        ib = [part.vert(l + n * (base_offset * 0.5)) for (l, n) in inner]
                        ob = [part.vert(l + n * (base_offset * 0.5)) for (l, n) in outer] if outer_walls else []
                        cen3 = Vector()
                        for (l, n) in inner:
                            cen3 += l
                        cen3 /= 6
                        for k in range(6):
                            k2 = (k + 1) % 6
                            part.face((ot[k], ot[k2], it[k2], it[k]), mat_cell)
                            if part.face_normal(len(part.f) - 1).dot(want) < 0:
                                part.f[-1] = tuple(reversed(part.f[-1]))
                            part.face((it[k], it[k2], ib[k2], ib[k]), mat_cell)
                            fc = part.face_center(len(part.f) - 1)
                            if part.face_normal(len(part.f) - 1).dot(cen3 - fc) < 0:
                                part.f[-1] = tuple(reversed(part.f[-1]))
                            if outer_walls:
                                part.face((ot[k], ot[k2], ob[k2], ob[k]), mat_cell)
                                fc = part.face_center(len(part.f) - 1)
                                if part.face_normal(len(part.f) - 1).dot(fc - cen3) < 0:
                                    part.f[-1] = tuple(reversed(part.f[-1]))
                y += dy
            x += dx
            col += 1
        return part


# =====================================================================================
# Loft body
# =====================================================================================
def _section_tangents(K, S):
    n = len(K)
    ext = [Vector((-K[1].x, K[1].y))] + K + [Vector((-K[n - 2].x, K[n - 2].y))]
    Tin, Tout = [], []
    for m in range(n):
        a, p, b = ext[m], ext[m + 1], ext[m + 2]
        din = p - a
        dout = b - p
        din = din.normalized() if din.length > 1e-9 else None
        dout = dout.normalized() if dout.length > 1e-9 else None
        if din is None and dout is None:
            din = dout = Vector((1.0, 0.0))
        elif din is None:
            din = dout
        elif dout is None:
            dout = din
        avg = din + dout
        avg = avg.normalized() if avg.length > 1e-9 else dout
        s = S[m]
        ti = avg.lerp(din, s)
        to = avg.lerp(dout, s)
        Tin.append(ti.normalized() if ti.length > 1e-9 else din)
        Tout.append(to.normalized() if to.length > 1e-9 else dout)
    return Tin, Tout


def _section_eval(K, Tin, Tout, t):
    m = min(int(t), len(K) - 2)
    u = t - m
    p0, p1 = K[m], K[m + 1]
    L = (p1 - p0).length
    return hermite(p0, Tout[m] * L, p1, Tin[m + 1] * L, u)


class Shell:
    pass


class LoftBody:
    def __init__(self, stations, band_segments, key_sharp=(0, 0.7, 0.2, 0.0, 0.35, 0.2, 0.4, 0.0, 0),
                 rules=(), default_roles=None, nose=None, tail=None, step=0.045, force_y=(), rail=0.05,
                 warps=()):
        """warps: slanted grid lines, e.g. a forward-leaning C-pillar window edge:
        dict(y=-1.31, t=(5.0, 6.0), y_t=(-1.42, -1.20), margin=0.25) moves the grid line whose base
        Y is `y` so that it runs from y_t[0] at section param t[0] to y_t[1] at t[1] (constant
        outside). Rules still refer to the BASE y (-1.31), so a rule boundary at that y becomes the
        slanted edge. Neighbouring lines within +-margin are blended (monotone, no overlaps)."""
        self.warps = list(warps)
        st = sorted(stations, key=lambda s: s['y'])
        cur = {'rail': rail, 'bulge': 0.0}
        for m in range(1, 8):
            cur['s%d' % m] = key_sharp[m]
        rows = []
        for s in st:
            cur = dict(cur)
            for k, v in s.items():
                if k in PARAMS:
                    cur[k] = v
            for m, v in s.get('ks', {}).items():
                cur['s%d' % int(m)] = v
            missing = [k for k in PARAMS if k not in cur]
            if missing:
                raise ValueError('station y=%s missing params %s' % (s['y'], missing))
            rows.append(cur)
        self.st_y = [s['y'] for s in st]

        def sharp_of(s, k):
            v = s.get('sharp', 0.0)        # float = all params, dict = {param: sharpness}
            return float(v.get(k, 0.0)) if isinstance(v, dict) else float(v)
        self.sharp_y = [s['y'] for s in st
                        if max([sharp_of(s, k) for k in PARAMS]) > 0.2]
        self.curves = {k: Curve1D(self.st_y, [r[k] for r in rows], [sharp_of(s, k) for s in st]) for k in PARAMS}
        self.bands = list(band_segments)
        assert len(self.bands) == 8
        t = []
        for m, n in enumerate(self.bands):
            for k in range(n):
                t.append(m + k / n)
        t.append(8.0)
        self.t = t
        self.J = len(t) - 1
        self.y0, self.y1 = self.st_y[0], self.st_y[-1]
        self.rules = list(rules)
        self.default_roles = dict(default_roles or {0: 'under'})
        self.nose = nose or dict(y=self.y1 + 0.06, z=0.45, tilt=0, k_edge=1.0, k_face=1.5, rings=8)
        self.tail = tail or dict(y=self.y0 - 0.06, z=0.55, tilt=0, k_edge=1.0, k_face=1.5, rings=8)
        self.step = step
        self.force_y = list(force_y)

    # ---- evaluation -------------------------------------------------------------
    def params_at(self, y):
        return {k: c(y) for k, c in self.curves.items()}

    def keys_at(self, y, inset=0.0):
        p = self.params_at(y)
        K = [Vector((0.0, p['zb'])), Vector((p['wb'], p['zb'])), Vector((p['ws'], p['zs'])),
             Vector((p['ww'], p['zw'])), Vector((p['wh'], p['zh'])), Vector((p['wg'], p['zg'])),
             Vector((p['wr'], p['zr'])), None, Vector((0.0, p['zc']))]
        d68 = K[8] - K[6]
        L = d68.length
        K[7] = K[6] + (d68 / L) * min(p['rail'], 0.45 * L) if L > 1e-6 else K[6].copy()
        if p['bulge'] and L > 1e-6:
            K[7] = K[7] + Vector((d68.y, -d68.x)) / L * p['bulge']   # raise K7 off the K6-K8 chord (outward)
        S = [0.0] + [clamp(p['s%d' % m], 0.0, 1.0) for m in range(1, 8)] + [0.0]
        if inset:
            Tin, Tout = _section_tangents(K, S)
            K2 = []
            for m in range(9):
                tv = _unit(Tin[m] + Tout[m], Tout[m])
                nin = Vector((-tv.y, tv.x))   # left normal of a CCW section = inward
                K2.append(K[m] + nin * inset)
            K2[0].x = 0.0
            K2[8].x = 0.0
            K = K2
        return K, S

    def half(self, y, inset=0.0):
        K, S = self.keys_at(y, inset)
        Tin, Tout = _section_tangents(K, S)
        return [_section_eval(K, Tin, Tout, t) for t in self.t]

    def point(self, y, t, side=1):
        K, S = self.keys_at(y)
        Tin, Tout = _section_tangents(K, S)
        p = _section_eval(K, Tin, Tout, t)
        return Vector((side * p.x, y, p.y))

    def ring_from_half(self, h, y, ydisp=0.0):
        J = self.J
        pts = [Vector((p.x, y + ydisp, p.y)) for p in h]
        pts += [Vector((-h[ti].x, y + ydisp, h[ti].y)) for ti in range(J - 1, 0, -1)]
        return pts

    def ti_of(self, r):
        return r if r <= self.J else 2 * self.J - r

    def band_of(self, r_a, r_b):
        return int(self.t[min(self.ti_of(r_a), self.ti_of(r_b))] + 1e-9)

    def role_at(self, band, y, side=1):
        role = self.default_roles.get(band, 'paint')
        for rule in self.rules:
            b0, b1 = rule['bands']
            ya, yb = rule['y']
            if b0 <= band <= b1 and ya <= y <= yb:
                sd = rule.get('side', 0)
                if sd == 0 or sd == side:
                    role = rule['role']
        return role

    # ---- sampling ---------------------------------------------------------------
    def warp_y(self, yb, t):
        y = yb
        for w in self.warps:
            m = w.get('margin', 0.25)
            hat = 1.0 - abs(yb - w['y']) / m
            if hat <= 0:
                continue
            if len(w['t']) == 2:
                ta, tb = w['t']
                u = clamp((t - ta) / (tb - ta), 0.0, 1.0)
                y += (lerp(w['y_t'][0], w['y_t'][1], u) - w['y']) * hat
            else:       # piecewise-linear warp (added for lark_roadster): t=(t0, t1, ..), y_t=(y0, y1, ..)
                ts, yts = w['t'], w['y_t']
                if t <= ts[0]:
                    yw = yts[0]
                elif t >= ts[-1]:
                    yw = yts[-1]
                else:
                    k = max(0, min(bisect.bisect_right(ts, t) - 1, len(ts) - 2))
                    yw = lerp(yts[k], yts[k + 1], (t - ts[k]) / (ts[k + 1] - ts[k]))
                y += (yw - w['y']) * hat
        return y

    def warped(self, yb):
        return any(abs(yb - w['y']) < w.get('margin', 0.25) for w in self.warps)

    def ring_at(self, yb, d=0.0, ydisp=0.0):
        """Full ring at base station yb (warp aware). d = inward inset (inner shell)."""
        if not self.warped(yb):
            return self.ring_from_half(self.half(yb, inset=d), yb, ydisp)
        J = self.J
        cache = {}
        half = []
        ycoord = []
        for t in self.t:
            yw = self.warp_y(yb, t)
            key = round(yw, 7)
            if key not in cache:
                K, S = self.keys_at(yw, d)
                Tin, Tout = _section_tangents(K, S)
                cache[key] = (K, Tin, Tout)
            K, Tin, Tout = cache[key]
            half.append(_section_eval(K, Tin, Tout, t))
            ycoord.append(yw)
        pts = [Vector((p.x, y + ydisp, p.y)) for p, y in zip(half, ycoord)]
        pts += [Vector((-half[ti].x, ycoord[ti] + ydisp, half[ti].y)) for ti in range(J - 1, 0, -1)]
        return pts

    def forced_ys(self):
        f = [self.y0, self.y1] + list(self.sharp_y) + list(self.force_y) + [w['y'] for w in self.warps]
        for rule in self.rules:
            for yv in rule['y']:
                if self.y0 < yv < self.y1:
                    f.append(yv)
        f = sorted(set(round(v, 5) for v in f if self.y0 <= v <= self.y1))
        out = []
        for v in f:
            if not out or v - out[-1] > 0.002:
                out.append(v)
        return out

    def sample_ys(self):
        n = max(2, int((self.y1 - self.y0) / 0.004) + 1)
        fine = [self.y0 + (self.y1 - self.y0) * k / (n - 1) for k in range(n)]
        cum = [0.0]
        prev = self.half(fine[0])
        for k in range(1, n):
            cur = self.half(fine[k])
            dy = fine[k] - fine[k - 1]
            dmax = 0.0
            for a, b in zip(prev, cur):
                dx, dz = b.x - a.x, b.y - a.y
                dmax = max(dmax, math.sqrt(dx * dx + dy * dy + dz * dz))
            cum.append(cum[-1] + dmax)
            prev = cur

        def C(y):
            if y <= fine[0]:
                return 0.0
            if y >= fine[-1]:
                return cum[-1]
            k = bisect.bisect_right(fine, y) - 1
            u = (y - fine[k]) / (fine[k + 1] - fine[k])
            return lerp(cum[k], cum[k + 1], u)

        def Cinv(target):
            k = bisect.bisect_left(cum, target)
            k = clamp(k, 1, n - 1)
            c0, c1 = cum[k - 1], cum[k]
            u = 0.0 if c1 - c0 < 1e-12 else (target - c0) / (c1 - c0)
            return lerp(fine[k - 1], fine[k], clamp(u, 0.0, 1.0))

        forced = self.forced_ys()
        self._forced = set(forced)
        ys = []
        for a, b in zip(forced[:-1], forced[1:]):
            Da, Db = C(a), C(b)
            m = max(1, int(round((Db - Da) / self.step)))
            for k in range(m):
                ys.append(a if k == 0 else Cinv(Da + (Db - Da) * k / m))
        ys.append(forced[-1])
        return ys

    # ---- end caps ---------------------------------------------------------------
    def _cap(self, ring, tangents, spec, sign):
        N = Vector((0.0, spec['y'], spec['z']))
        tilt = math.radians(spec.get('tilt', 0.0))
        A = Vector((0.0, sign * math.cos(tilt), math.sin(tilt)))
        K = int(spec.get('rings', 8))
        ke = spec.get('k_edge', 1.0)
        kf = spec.get('k_face', 1.5)
        pw = spec.get('pow', 1.0)
        pre = []
        for p, t in zip(ring, tangents):
            D = (N - p).dot(A)
            proj = p + A * D
            rad = N - proj
            rho = rad.length
            d = rad / rho if rho > 1e-6 else Vector((0, 0, 0))
            ta = max(t.dot(A), 0.15)
            L1 = ke * max(D, 0.004) / ta
            L1 = min(L1, 0.9 * rho + 0.01)
            L2 = kf * rho
            pre.append((p, t * L1, d * L2))
        rings = []
        for k in range(1, K):
            s = (k / K) ** pw
            s2, s3 = s * s, s * s * s
            h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
            rings.append([p * h00 + m0 * h10 + N * h01 + m1 * h11 for (p, m0, m1) in pre])
        return rings, N

    # ---- the build --------------------------------------------------------------
    def build(self, car, arches=(), inner=None, glass_inset=0.006, frame_extra=0.004, lip=0.009,
              lip_segments=2, solver='EXACT', cutters=None, frame_backs=0.0):
        """cutters (optional, added in the kestrel_r4 rework; default None = unchanged behaviour): closed Parts
        (or a callable(Surface of the uncut shell) -> list of closed Parts) subtracted from the shell in the
        same boolean as the wheel arches. The cutter faces become the pocket walls and keep their material
        keys (BODY_MATS), e.g. a recessed grille mouth, intakes or a number-plate recess (see
        kestrel_r4.pocket()).
        frame_backs (optional, default 0 = unchanged): > 0 adds a reversed copy of every window reveal face,
        offset by this distance behind it, so the reveals are solid from both sides once the glTF materials
        are single-sided (no see-through slivers at the screen header from the cockpit camera)."""
        sh = Shell()
        ys = self.sample_ys()
        N = len(ys)
        J = self.J
        R = 2 * J
        self.ys = ys
        P = [self.ring_at(y) for y in ys]
        self.P = P

        def loft_tangents(i_end, sign):
            h = 0.003
            yb = ys[i_end] - sign * h
            rb = self.ring_from_half(self.half(yb), yb)
            return [_unit(P[i_end][r] - rb[r], Vector((0, sign, 0))) for r in range(R)]

        cap_f, pole_f = self._cap(P[-1], loft_tangents(N - 1, 1), self.nose, 1)
        cap_r, pole_r = self._cap(P[0], loft_tangents(0, -1), self.tail, -1)

        bm = bmesh.new()
        midx = {k: i for i, k in enumerate(BODY_MATS)}
        V = [[bm.verts.new(p) for p in ring] for ring in P]
        window = {}
        for i in range(N - 1):
            ymid = 0.5 * (ys[i] + ys[i + 1])
            for r in range(R):
                r2 = (r + 1) % R
                band = self.band_of(r, r2)
                side = 1 if r < J else -1
                role = self.role_at(band, ymid, side)
                f = bm.faces.new((V[i][r], V[i][r2], V[i + 1][r2], V[i + 1][r]))
                if role in ('glass', 'open'):
                    window[(i, r)] = role
                    f.material_index = midx['Paint']
                else:
                    f.material_index = midx[ROLE_MAT.get(role, 'Paint')]

        def add_cap(ring_verts, rings, pole):
            prev = ring_verts
            for ring in rings:
                cur = [bm.verts.new(p) for p in ring]
                for r in range(R):
                    r2 = (r + 1) % R
                    f = bm.faces.new((prev[r], prev[r2], cur[r2], cur[r]))
                    f.material_index = midx['Paint']
                prev = cur
            pv = bm.verts.new(pole)
            for r in range(R):
                f = bm.faces.new((prev[r], prev[(r + 1) % R], pv))
                f.material_index = midx['Paint']

        add_cap(V[-1], cap_f, pole_f)
        add_cap(V[0], cap_r, pole_r)
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        # make sure normals point outward (recalc can choose inward for the whole shell)
        bm.faces.ensure_lookup_table()
        vol = 0.0
        for f in bm.faces:
            vol += f.calc_center_median().dot(f.normal) * f.calc_area()
        if vol < 0:
            for f in bm.faces:
                f.normal_flip()

        # ---- wheel arches (boolean) + optional extra cutters ----
        extra = []
        if cutters:
            extra = list(cutters(Surface(bm)) if callable(cutters) else cutters)
        if arches or extra:
            bm = _boolean_arches(car, bm, arches, midx['Underbody'], solver, extra=extra, midx=midx)
            if lip > 0 and arches:
                _bevel_arch_lips(bm, arches, midx, lip, lip_segments)
        bm.normal_update()
        sh.surface = Surface(bm)

        # ---- windows: delete faces, build frames ----
        kd_face = KDTree(len(bm.faces))
        bm.faces.ensure_lookup_table()
        for fi, f in enumerate(bm.faces):
            kd_face.insert(f.calc_center_median(), fi)
        kd_face.balance()
        hole_faces = []
        for (i, r), role in window.items():
            r2 = (r + 1) % R
            c = (P[i][r] + P[i][r2] + P[i + 1][r2] + P[i + 1][r]) / 4
            co, fi, dist = kd_face.find(c)
            if dist < 2e-4:
                hole_faces.append(bm.faces[fi])
        kd_grid = KDTree(N * R)
        for i in range(N):
            for r in range(R):
                kd_grid.insert(P[i][r], i * R + r)
        kd_grid.balance()

        inner = inner or {}
        d_in = inner.get('d', 0.035)
        ramp = inner.get('dy_ramp', None)

        def ydisp(y):
            # inner shell is pushed toward the car centre near steep end faces (tailgate):
            # ramp (ya, yb): 0 at ya, full d_in at yb; yb < ya = rear end (+Y push), else front (-Y push)
            if not ramp:
                return 0.0
            ya, yb = ramp
            sgn = 1.0 if yb < ya else -1.0
            return sgn * d_in * smoothstep(ya, yb, y)

        ring_cache = {}

        def inner_pt(i, r, d):
            key = (i, round(d, 5))
            if key not in ring_cache:
                ring_cache[key] = self.ring_at(ys[i], d=d, ydisp=ydisp(ys[i]))
            return ring_cache[key][r].copy()

        # map frame boundary edges
        boundary_info = []
        hole_set = set(hole_faces)
        for f in hole_faces:
            for e in f.edges:
                others = [g for g in e.link_faces if g not in hole_set]
                if len(others) == 1:
                    boundary_info.append((e.verts[0].co.copy(), e.verts[1].co.copy(), others[0].calc_center_median()))
        bmesh.ops.delete(bm, geom=hole_faces, context='FACES')
        qcache = {}
        trim_i = midx['Trim']

        def vkey(co):
            c, idx, dist = kd_grid.find(co)
            if dist > 2e-4:
                return None
            return idx // R, idx % R

        vlist = list(bm.verts)
        kd_v = KDTree(len(vlist))
        for vi, v in enumerate(vlist):
            kd_v.insert(v.co, vi)
        kd_v.balance()

        def bmv(co):
            c, vi, dist = kd_v.find(co)
            return vlist[vi] if dist < 1e-5 else None

        frame_faces = []
        for (ca, cb, ck) in boundary_info:
            ka, kb = vkey(ca), vkey(cb)
            va, vb = bmv(ca), bmv(cb)
            if ka is None or kb is None or va is None or vb is None:
                continue
            qs = []
            for kk in (ka, kb):
                if kk not in qcache:
                    qcache[kk] = bm.verts.new(inner_pt(kk[0], kk[1], d_in + frame_extra))
                qs.append(qcache[kk])
            try:
                f = bm.faces.new((va, vb, qs[1], qs[0]))
            except ValueError:
                continue
            f.material_index = trim_i
            f.normal_update()
            mid = (ca + cb) / 2
            if f.normal.dot(mid - ck) < 0:
                f.normal_flip()
            frame_faces.append(f)
        if frame_backs > 0:
            for f in frame_faces:
                n = f.normal.copy()
                vs = [bm.verts.new(v.co - n * frame_backs) for v in reversed(list(f.verts))]
                try:
                    g = bm.faces.new(vs)
                    g.material_index = trim_i
                except ValueError:
                    pass
        bm.normal_update()
        sh.bm = bm

        # ---- glass ----
        ycen = 0.5 * (ys[0] + ys[-1])

        def grid_normal(i, r):
            i0, i1 = max(i - 1, 0), min(i + 1, N - 1)
            a = P[i][(r + 1) % R] - P[i][(r - 1) % R]
            b = P[i1][r] - P[i0][r]
            n = _unit(b.cross(a))
            ref = P[i][r] - Vector((0, ycen, 0.7))
            if n.dot(ref) < 0:
                n = -n
            return n

        glass = Part()
        gcache = {}

        def gv(i, r):
            if (i, r) not in gcache:
                gcache[(i, r)] = glass.vert(P[i][r] - grid_normal(i, r) * glass_inset)
            return gcache[(i, r)]

        for (i, r), role in window.items():
            if role != 'glass':
                continue
            r2 = (r + 1) % R
            glass.face((gv(i, r), gv(i, r2), gv(i + 1, r2), gv(i + 1, r)), 'Glass')
            fi = len(glass.f) - 1
            if glass.face_normal(fi).dot(grid_normal(i, r)) < 0:
                glass.f[fi] = tuple(reversed(glass.f[fi]))
        sh.glass = glass

        # ---- inner cabin shell ----
        sh.inner = Part()
        if inner and 'y' in inner:
            sh.inner = self._inner_shell(inner, ys, inner_pt, d_in)
        sh.ys = ys
        sh.P = P
        sh.window = window
        return sh

    def _inner_shell(self, inner, ys, inner_pt, d_in):
        J, R = self.J, 2 * self.J
        y_a, y_b = inner['y']
        idx = [i for i, y in enumerate(ys) if y_a - 1e-6 <= y <= y_b + 1e-6]
        forced = getattr(self, '_forced', set())
        stride = inner.get('stride', 2)
        sel = []
        for k, i in enumerate(idx):
            if k % stride == 0 or k == len(idx) - 1 or round(ys[i], 5) in forced:
                sel.append(i)
        tis = [ti for ti in range(J + 1) if ti % stride == 0 or abs(self.t[ti] - round(self.t[ti])) < 1e-9 or ti == J]
        ring_r = list(tis) + [2 * J - ti for ti in reversed(tis) if 0 < ti < J]
        tubs = inner.get('tubs', [])
        mats_band = inner.get('band_mats', {0: 'InteriorDark', 1: 'InteriorDark', 2: 'InteriorDark', 3: 'Interior',
                                            4: 'Interior', 5: 'Interior', 6: 'Interior', 7: 'Interior'})
        part = Part()
        rows = []
        for i in sel:
            row = []
            for r in ring_r:
                p = inner_pt(i, r, d_in)
                for (ty, tz, tr, tx) in tubs:
                    dd = math.hypot(p.y - ty, p.z - tz)
                    w = smoothstep(tr + 0.04, tr, dd)
                    if abs(p.x) > tx and w > 0:
                        p.x = math.copysign(lerp(abs(p.x), tx, w), p.x)
                row.append(part.vert(p))
            rows.append(row)
        nr = len(ring_r)
        for a in range(len(sel) - 1):
            ymid = 0.5 * (ys[sel[a]] + ys[sel[a + 1]])
            for k in range(nr):
                k2 = (k + 1) % nr
                band = self.band_of(ring_r[k], ring_r[k2])
                side = 1 if ring_r[k] < J else -1
                role = self.role_at(band, ymid, side)
                if role in ('glass', 'open'):
                    continue
                part.face((rows[a][k], rows[a][k2], rows[a + 1][k2], rows[a + 1][k]), mats_band.get(band, 'Interior'))
        cap_mat = inner.get('cap_mat', 'InteriorDark')
        part.face(rows[0], cap_mat)
        part.face(rows[-1], cap_mat)
        y0c = ys[sel[0]] + 0.25
        y1c = ys[sel[-1]] - 0.25
        zc = inner.get('center_z', 0.75)

        def ref(c):
            yy = clamp(c.y, min(y0c, y1c), max(y0c, y1c))
            return Vector((0.0, yy, zc))
        part.orient(0, ref_fn=ref, inward=True)
        return part


def _boolean_arches(car, bm, arches, under_idx, solver, extra=None, midx=None):
    """extra / midx (optional): additional closed cutter Parts whose faces keep their material keys."""
    col = car.col
    me = bpy.data.meshes.new('_tmp_shell')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('_tmp_shell', me)
    col.objects.link(ob)
    for k in BODY_MATS:
        me.materials.append(car.mats[k])
    cut = Part()
    for a in arches:
        for side in (1, -1):
            x_in = a['x_in']
            x_out = a.get('x_out', 1.6)
            prof = [(x_in, 0.0), (x_in, a['r']), (x_out, a['r']), (x_out, 0.0)]
            p = revolve(prof, a.get('segs', 72), 'Underbody')
            p = p.translated((0, a['y'], a['z']))
            if side < 0:
                p = p.mirrored_x()
            cut.extend(p)
    for p in (extra or []):
        cut.extend(p)
    cme = bpy.data.meshes.new('_tmp_cut')
    cbm = bmesh.new()
    vs = [cbm.verts.new(v) for v in cut.v]
    for f, m in zip(cut.f, cut.m):
        try:
            ff = cbm.faces.new([vs[i] for i in f])
            ff.material_index = midx.get(m, under_idx) if midx else under_idx
        except ValueError:
            pass
    bmesh.ops.remove_doubles(cbm, verts=cbm.verts[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(cbm, faces=cbm.faces[:])
    cbm.to_mesh(cme)
    cbm.free()
    for k in BODY_MATS:
        cme.materials.append(car.mats[k])
    cob = bpy.data.objects.new('_tmp_cut', cme)
    col.objects.link(cob)
    mod = ob.modifiers.new('arches', 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cob
    try:
        mod.solver = solver
    except TypeError:
        pass
    try:
        mod.material_mode = 'INDEX'
    except TypeError:
        pass
    if extra:                       # extra cutters may overlap the arch cylinders (e.g. a liner relief)
        try:
            mod.use_self = True
        except (TypeError, AttributeError):
            pass
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    res = bpy.data.meshes.new_from_object(ev)
    nbm = bmesh.new()
    nbm.from_mesh(res)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.objects.remove(cob, do_unlink=True)
    for m in (me, cme, res):
        bpy.data.meshes.remove(m)
    return nbm


def _bevel_arch_lips(bm, arches, midx, lip, segments):
    paint, under = midx['Paint'], midx['Underbody']
    edges = []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        ms = {f.material_index for f in e.link_faces}
        if ms != {paint, under}:
            continue
        mid = (e.verts[0].co + e.verts[1].co) / 2
        ok = False
        for a in arches:
            if abs(abs(mid.x) - a['x_in']) < 0.03:
                continue
            d = math.hypot(mid.y - a['y'], mid.z - a['z'])
            if abs(d - a['r']) < 0.02 and abs(mid.x) > a['x_in'] + 0.05:
                ok = True
        if ok:
            edges.append(e)
    if not edges:
        return 0
    verts = list({v for e in edges for v in e.verts})
    try:
        bmesh.ops.bevel(bm, geom=edges + verts, offset=lip, offset_type='OFFSET', profile_type='SUPERELLIPSE',
                        segments=segments, profile=0.5, affect='EDGES', clamp_overlap=True, material=paint)
    except Exception as ex:  # pragma: no cover - keep the build going
        print('arch bevel failed:', ex)
    return len(edges)


# =====================================================================================
# Materials
# =====================================================================================
def make_material(name, base=(0.8, 0.8, 0.8), metallic=0.0, roughness=0.5, emission=None, strength=0.0,
                  alpha=1.0, coat=0.0, coat_rough=0.03, double_sided=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
    if bsdf is None:
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    if out is None:
        out = nt.nodes.new('ShaderNodeOutputMaterial')
    if not any(l.to_node == out for l in nt.links):
        nt.links.new(bsdf.outputs[0], out.inputs[0])

    def inp(ident):
        return next(s for s in bsdf.inputs if s.identifier == ident)
    inp('Base Color').default_value = (base[0], base[1], base[2], 1.0)
    inp('Metallic').default_value = metallic
    inp('Roughness').default_value = roughness
    inp('Alpha').default_value = alpha
    inp('Coat Weight').default_value = coat
    inp('Coat Roughness').default_value = coat_rough
    if emission is not None:
        inp('Emission Color').default_value = (emission[0], emission[1], emission[2], 1.0)
        inp('Emission Strength').default_value = strength
    else:
        inp('Emission Strength').default_value = 0.0
    methods = [i.identifier for i in bpy.types.Material.bl_rna.properties['surface_render_method'].enum_items]
    if alpha < 1.0 and 'BLENDED' in methods:
        mat.surface_render_method = 'BLENDED'
    elif 'DITHERED' in methods:
        mat.surface_render_method = 'DITHERED'
    mat.use_backface_culling = not double_sided
    mat.diffuse_color = (base[0], base[1], base[2], alpha)
    mat.metallic = metallic
    mat.roughness = roughness
    return mat


def default_materials(paint=(0.888, 0.539, 0.0), paint_metallic=0.0, paint_rough=0.28, paint_coat=0.6,
                      rim=(0.06, 0.06, 0.065), rim_metallic=0.85, rim_rough=0.35, caliper=(0.55, 0.02, 0.015),
                      interior=(0.05, 0.05, 0.055), interior_dark=(0.014, 0.014, 0.016)):
    return {
        'Paint': dict(base=paint, metallic=paint_metallic, roughness=paint_rough, coat=paint_coat, coat_rough=0.04),
        'Trim': dict(base=(0.018, 0.018, 0.02), roughness=0.38),
        'Chrome': dict(base=(0.85, 0.86, 0.88), metallic=1.0, roughness=0.12),
        'Grille': dict(base=(0.012, 0.012, 0.013), roughness=0.6),
        'Carbon': dict(base=(0.03, 0.03, 0.033), metallic=0.3, roughness=0.32),
        'Underbody': dict(base=(0.012, 0.012, 0.012), roughness=0.85),
        'Glass': dict(base=(0.015, 0.02, 0.025), roughness=0.04, alpha=0.3, double_sided=True),
        'Interior': dict(base=interior, roughness=0.75),
        'InteriorDark': dict(base=interior_dark, roughness=0.55),
        'Gauge': dict(base=(0.02, 0.02, 0.02), roughness=0.4, emission=(1.0, 0.95, 0.85), strength=1.5),
        'Rubber': dict(base=(0.022, 0.022, 0.024), roughness=0.88),
        'Rim': dict(base=rim, metallic=rim_metallic, roughness=rim_rough),
        'BrakeDisc': dict(base=(0.33, 0.33, 0.34), metallic=1.0, roughness=0.42),
        'Caliper': dict(base=caliper, roughness=0.32),
        'HeadlightLens': dict(base=(0.9, 0.92, 0.95), roughness=0.08, emission=(1.0, 0.97, 0.92), strength=3.0),
        'TaillightLens': dict(base=(0.32, 0.01, 0.012), roughness=0.12, emission=(1.0, 0.04, 0.03), strength=0.8),
        'BrakeLens': dict(base=(0.45, 0.015, 0.015), roughness=0.12, emission=(1.0, 0.03, 0.02), strength=0.4),
        'ReverseLens': dict(base=(0.85, 0.85, 0.88), roughness=0.1, emission=(1.0, 1.0, 1.0), strength=0.0),
    }


OBJ_MATS = {
    'Body': BODY_MATS,
    'Glass': ['Glass'],
    'Interior': ['Interior', 'InteriorDark', 'Gauge'],
    'SteeringWheel': ['InteriorDark', 'Interior', 'Gauge'],
    'Wheel': ['Rubber', 'Rim', 'BrakeDisc'],
    'Caliper': ['Caliper'],
    'Lights_Head': ['HeadlightLens'],
    'Lights_Tail': ['TaillightLens'],
    'Lights_Brake': ['BrakeLens'],
    'Lights_Reverse': ['ReverseLens'],
}


# =====================================================================================
# Car assembly (collections, objects, naming)
# =====================================================================================
def _ensure_child_collection(name, parent):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    if col.name not in [c.name for c in parent.children]:
        parent.children.link(col)
    return col


def cars_collection():
    root = bpy.data.collections.get('SUNWARD_GODOT')
    if root is None:
        root = bpy.data.collections.new('SUNWARD_GODOT')
        bpy.context.scene.collection.children.link(root)
    return _ensure_child_collection('Cars', root)


def reset_car_collection(car_id, group=None):
    """group (optional, added for the traffic vehicles; default None = unchanged): put the collection under
    SUNWARD_GODOT/<group>/<group>_<car_id> (e.g. Traffic/Traffic_van_delivery) instead of Cars/Car_<car_id>."""
    cars = cars_collection() if group is None else group_collection(group)
    name = 'Car_%s' % car_id if group is None else '%s_%s' % (group, car_id)
    col = bpy.data.collections.get(name)
    if col is not None:
        def purge(c):
            for ch in list(c.children):
                purge(ch)
                bpy.data.collections.remove(ch)
            for ob in list(c.objects):
                data = ob.data
                bpy.data.objects.remove(ob, do_unlink=True)
                if data is not None and getattr(data, 'users', 1) == 0 and isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
        purge(col)
        bpy.data.collections.remove(col)
    col = bpy.data.collections.new(name)
    cars.children.link(col)
    return col


def _empty_type(pref='PLAIN_AXES'):
    items = [i.identifier for i in bpy.types.Object.bl_rna.properties['empty_display_type'].enum_items]
    return pref if pref in items else items[0]


def box_uv(bm, scale=0.5):
    uv = bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for l in f.loops:
            co = l.vert.co
            if ax == 0:
                l[uv].uv = (co.y * scale * (1 if n.x > 0 else -1), co.z * scale)
            elif ax == 1:
                l[uv].uv = (co.x * scale * (-1 if n.y > 0 else 1), co.z * scale)
            else:
                l[uv].uv = (co.x * scale, co.y * scale * (1 if n.z > 0 else -1))


class CarAssembly:
    def __init__(self, car_id, name, materials, group=None):
        """group (optional, added for the traffic vehicles): collection group under SUNWARD_GODOT, e.g. 'Traffic'."""
        self.car_id = car_id
        self.name = name
        self.col = reset_car_collection(car_id) if group is None else reset_car_collection(car_id, group)
        self.mats = {k: make_material('%s_%s' % (k, car_id), **spec) for k, spec in materials.items()}
        self.parts = {}     # obj part name -> list of Part / BMesh
        self.obj_specs = {}  # part name -> dict(location, rotation, mats)
        self.sockets = {}
        self.objects = {}
        root = bpy.data.objects.get(car_id)
        if root is not None:
            bpy.data.objects.remove(root, do_unlink=True)
        self.root = bpy.data.objects.new(car_id, None)
        self.root.empty_display_type = _empty_type('PLAIN_AXES')
        self.root.empty_display_size = 0.5
        self.col.objects.link(self.root)
        self.info = {}

    def oname(self, part):
        return '%s__%s' % (part, self.car_id)

    def add(self, part_name, *parts, location=(0, 0, 0), rotation=(0, 0, 0), mats=None):
        lst = self.parts.setdefault(part_name, [])
        for p in parts:
            if p is not None:
                lst.append(p)
        spec = self.obj_specs.setdefault(part_name, {})
        spec.setdefault('location', Vector(location))
        spec.setdefault('rotation', rotation)
        if mats:
            spec['mats'] = mats

    def socket(self, name, loc, rotation=(0, 0, 0)):
        self.sockets[name] = (Vector(loc), rotation)

    def _mat_keys(self, part_name):
        spec = self.obj_specs.get(part_name, {})
        if 'mats' in spec:
            return spec['mats']
        base = part_name.split('_')[0] if part_name.startswith(('Wheel_', 'Caliper_')) else part_name
        return OBJ_MATS.get(base, BODY_MATS)

    def _build_mesh(self, part_name, sources, mat_keys):
        bm = bmesh.new()
        keyidx = {k: i for i, k in enumerate(mat_keys)}
        for src in sources:
            if isinstance(src, bmesh.types.BMesh):
                tmp = bpy.data.meshes.new('_tmp_merge')
                src.to_mesh(tmp)
                bm.from_mesh(tmp)
                bpy.data.meshes.remove(tmp)
                continue
            vs = [bm.verts.new(v) for v in src.v]
            for f, m in zip(src.f, src.m):
                try:
                    face = bm.faces.new([vs[i] for i in f])
                except ValueError:
                    continue
                if m not in keyidx:
                    keyidx[m] = len(mat_keys)
                    mat_keys.append(m)
                face.material_index = keyidx[m]
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-9], context='FACES_ONLY')
        bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        bm.normal_update()
        box_uv(bm)
        return bm

    def finalize(self, sharp_angle=35.0):
        for part_name, sources in self.parts.items():
            mat_keys = list(self._mat_keys(part_name))
            bm = self._build_mesh(part_name, sources, mat_keys)
            me = bpy.data.meshes.new(self.oname(part_name))
            bm.to_mesh(me)
            bm.free()
            for k in mat_keys:
                me.materials.append(self.mats[k])
            me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
            ang = self.obj_specs[part_name].get('sharp', sharp_angle)
            me.set_sharp_from_angle(angle=math.radians(ang))
            me.update()
            ob = bpy.data.objects.new(self.oname(part_name), me)
            spec = self.obj_specs[part_name]
            ob.location = spec['location']
            ob.rotation_euler = spec['rotation']
            self.col.objects.link(ob)
            ob.parent = self.root
            self.objects[part_name] = ob
        for name, (loc, rot) in self.sockets.items():
            e = bpy.data.objects.new(self.oname(name), None)
            e.empty_display_type = _empty_type('PLAIN_AXES')
            e.empty_display_size = 0.08
            e.location = loc
            e.rotation_euler = rot
            self.col.objects.link(e)
            e.parent = self.root
            self.objects[name] = e
        bpy.context.view_layer.update()
        return self.objects


# =====================================================================================
# Wheels
# =====================================================================================
def _slot_face(n_slots, r_in, r_out, slot_r, slot_w, x_face, thick, seg_out, phase, mat='Rim', wall_mat=None):
    """Solid dished wheel face (annulus r_in..r_out) with n_slots radial tapered slots ("slot mag").
    slot_r=(r_a, r_b) slot inner/outer end radius, slot_w=(w_a, w_b) slot width at each end.
    x_face(r) -> axial x of the front face; the back face is `thick` behind it. Built in the (y, z)
    plane (lathe axis X), front faces toward +X. Returns Part."""
    def stadium(k):
        a = phase + 2 * math.pi * k / n_slots
        e = Vector((math.cos(a), math.sin(a)))
        p = Vector((-e.y, e.x))
        (ra, rb), (wa, wb) = slot_r, slot_w
        ca, cb = e * (ra + wa / 2), e * (rb - wb / 2)
        pts = []
        for j in range(7):                    # inner end (semicircle around ca, facing the hub)
            t = math.pi / 2 + math.pi * j / 6
            pts.append(ca + (e * math.cos(t) + p * math.sin(t)) * (wa / 2))
        for j in range(7):                    # outer end (semicircle around cb, facing the rim)
            t = -math.pi / 2 + math.pi * j / 6
            pts.append(cb + (e * math.cos(t) + p * math.sin(t)) * (wb / 2))
        if poly_area(pts) < 0:
            pts.reverse()
        return pts
    holes = [stadium(k) for k in range(n_slots)]
    outer = [Vector((r_out * math.cos(2 * math.pi * j / seg_out), r_out * math.sin(2 * math.pi * j / seg_out)))
             for j in range(seg_out)]
    inner = [Vector((r_in * math.cos(2 * math.pi * j / 16), r_in * math.sin(2 * math.pi * j / 16))) for j in range(16)]
    loops = [outer, inner] + holes
    verts2d, edges, faces = [], [], []
    for lp in loops:
        o = len(verts2d)
        verts2d.extend(lp)
        edges.extend((o + j, o + (j + 1) % len(lp)) for j in range(len(lp)))
        faces.append(list(range(o, o + len(lp))))
    nb = len(verts2d)
    # Steiner rings (front face only) for smooth dish shading
    steiner = list(verts2d)
    for rr_ in (r_in + 0.45 * (r_out - r_in), r_in + 0.80 * (r_out - r_in)):
        m = max(12, int(2 * math.pi * rr_ / 0.026))
        for j in range(m):
            q = Vector((rr_ * math.cos(2 * math.pi * (j + 0.5) / m), rr_ * math.sin(2 * math.pi * (j + 0.5) / m)))
            if all(not point_in_poly(q, h) and dist_to_poly(q, h) > 0.009 for h in holes):
                steiner.append(q)
    part = Part()
    rings = {}
    for side, pts in ((1, steiner), (-1, verts2d)):
        out = geometry.delaunay_2d_cdt(pts, edges, faces, 2, 1e-7)
        ov, of = out[0], out[2]
        dx = 0.0 if side > 0 else -thick
        vi = [part.vert((x_face(co.length) + dx, co.x, co.y)) for co in ov]
        for f in of:
            part.face([vi[i] for i in f], mat)
            if part.face_normal(len(part.f) - 1).x * side < 0:
                part.f[-1] = tuple(reversed(part.f[-1]))
        kd = KDTree(len(ov))
        for i, co in enumerate(ov):
            kd.insert((co.x, co.y, 0.0), i)
        kd.balance()
        rings[side] = [[vi[kd.find((q.x, q.y, 0.0))[1]] for q in h] for h in holes]
    # slot walls (front ring -> back ring) facing into the slot
    for hi, h in enumerate(holes):
        fr, bk = rings[1][hi], rings[-1][hi]
        c = sum(h, Vector((0.0, 0.0))) / len(h)
        for j in range(len(h)):
            j2 = (j + 1) % len(h)
            part.face((fr[j], fr[j2], bk[j2], bk[j]), wall_mat or mat)
            fc = part.face_center(len(part.f) - 1)
            want = Vector((0.0, c.x - fc.y, c.y - fc.z))
            if part.face_normal(len(part.f) - 1).dot(want) < 0:
                part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def _split_spokes(n, r0, r1, x_front, thick, split_f=0.42, stem_w=(0.030, 0.006), arm_w=(0.0135, 0.004),
                  arm_gap=0.050, mat='Rim', ch=0.0025):
    """`n` Y-shaped split spokes (added for sora_s2): a single stem from the hub (r0) to the split radius,
    then two thin arms diverging to the rim (r1), their centre lines `arm_gap` apart at the rim.
    The arms start inside the stem end and sit 0.8 mm lower, so the junction never z-fights; the stem end
    is capped. Built in the (y, z) plane (lathe axis X), front faces toward +X. Returns Part."""
    rs = r0 + split_f * (r1 - r0)
    part = Part()

    def section(c, p, xf, w):
        xb = xf - thick
        sec = [(xf, -w / 2 + ch), (xf, w / 2 - ch), (xf - ch, w / 2), (xb, w / 2 * 0.8),
               (xb, -w / 2 * 0.8), (xf - ch, -w / 2)]
        return [Vector((x, c.y + p.y * l, c.z + p.z * l)) for (x, l) in sec]

    def loft(rows, cap_end=False, out_dir=None):
        sp = Part()
        idx = [[sp.vert(v) for v in row] for row in rows]
        ns = len(rows[0])
        for i in range(len(rows) - 1):
            for j in range(ns):
                j2 = (j + 1) % ns
                sp.face((idx[i][j], idx[i][j2], idx[i + 1][j2], idx[i + 1][j]), mat)
        cen = [sum(r, Vector()) / ns for r in rows]
        sp.orient(0, ref_fn=lambda c: min(cen, key=lambda q: (q - c).length))
        if cap_end:
            sp.face(list(idx[-1]), mat)
            if sp.face_normal(len(sp.f) - 1).dot(out_dir) < 0:
                sp.f[-1] = tuple(reversed(sp.f[-1]))
        return sp

    for k in range(n):
        a = math.pi / 2 + 2 * math.pi * k / n
        e = Vector((0, math.cos(a), math.sin(a)))
        p = Vector((0, -math.sin(a), math.cos(a)))
        # stem (hub -> split), capped at the split
        rows = []
        for r in (r0, rs):
            f = (r - r0) / (r1 - r0)
            rows.append(section(e * r, p, x_front(r), stem_w[0] - stem_w[1] * f))
        part.extend(loft(rows, cap_end=True, out_dir=e))
        # two arms (split -> rim)
        for side in (-1, 1):
            rows = []
            for r in (rs - 0.008, rs + 0.35 * (r1 - rs), r1):
                u = clamp((r - rs) / (r1 - rs), 0.0, 1.0)
                w = arm_w[0] - arm_w[1] * u
                sep = w / 2 + (arm_gap / 2 - w / 2) * (u ** 0.8)
                rows.append(section(e * r + p * (sep * side), p, x_front(r) - 0.0008, w))
            part.extend(loft(rows))
    return part


def _tyre_profile(R, rr, hw, lip_x, kind):
    if kind == 'tall':          # tall sidewall (14-15" rims): bulged sidewall, round shoulder
        return [(-lip_x + 0.006, rr + 0.006), (-hw + 0.007, rr + 0.028), (-hw, rr + 0.45 * (R - rr)),
                (-hw + 0.005, R - 0.030), (-hw + 0.015, R - 0.009), (-hw + 0.032, R)]
    return [(-lip_x + 0.006, rr + 0.006), (-hw, rr + 0.034),
            (-hw + 0.003, R - 0.022), (-hw + 0.012, R - 0.006), (-hw + 0.027, R)]


def block_tyre(R=0.40, W=0.265, rim_d_in=17, segs=36, n=26, h=0.013, rows=None, mat='Rubber'):
    """All-terrain tyre with raised tread blocks (added for ridgeback_sx). RIGHT-side frame of build_wheel: axle at
    the origin, spin axis X, contact at z = -R. The carcass is the 'tall' profile with its crown at R - h; the blocks
    reach R. rows: list of dict(x=(x0, x1), phase=0..1 (fraction of the pitch), frac=block length / pitch,
    skew=angular shift of the outer edge vs the inner edge in pitches, shoulder=-1|0|1 (which x edge runs down the
    sidewall), drop=how far that edge runs down (alternating long / short lugs), alt=frac change on odd blocks).
    Every block = 8 vertices, top + 4 walls (+ bottom for shoulder lugs); its base is sunk 4 mm into the carcass."""
    rr = rim_d_in * 0.0254 / 2.0
    hw = W / 2.0
    lip_x = hw - 0.012
    rc = R - h
    side = [(-lip_x + 0.006, rr + 0.006), (-hw + 0.007, rr + 0.028), (-hw, rr + 0.45 * (rc - rr)),
            (-hw + 0.003, rc - 0.040), (-hw + 0.012, rc - 0.011), (-hw + 0.030, rc)]
    prof = side + [(-a, r) for (a, r) in reversed(side)]
    part = revolve(prof, segs, mat)
    if rows is None:
        rows = [dict(x=(-hw - 0.004, -0.48 * hw), phase=0.0, frac=0.70, shoulder=-1, drop=0.050, alt=0.0),
                dict(x=(-0.41 * hw, -0.05 * hw), phase=0.5, frac=0.64, skew=0.14),
                dict(x=(0.05 * hw, 0.41 * hw), phase=0.0, frac=0.64, skew=-0.14),
                dict(x=(0.48 * hw, hw + 0.004), phase=0.5, frac=0.70, shoulder=1, drop=0.050, alt=0.0)]
    pitch = 2 * math.pi / n

    def P(x, a, r):
        return Vector((x, r * math.cos(a), r * math.sin(a)))
    for row in rows:
        x0, x1 = row['x']
        sh = row.get('shoulder', 0)
        skew = row.get('skew', 0.0) * pitch
        for k in range(n):
            frac = row.get('frac', 0.66) + (row.get('alt', 0.0) * (1 if k % 2 else -1))
            half = 0.5 * frac * pitch
            ac = pitch * (k + row.get('phase', 0.0))
            drop = row.get('drop', 0.045) * (1.0 if k % 2 == 0 else 0.62)
            vid = {}
            start = len(part.f)
            for xi, x in enumerate((x0, x1)):
                u = 0.0 if x1 == x0 else (x - x0) / (x1 - x0)
                sh_edge = (sh > 0 and xi == 1) or (sh < 0 and xi == 0)
                da = skew * (u - 0.5)
                for ai, sgn in enumerate((-1, 1)):
                    a = ac + sgn * half + da
                    if sh_edge:
                        top = P(x - sh * 0.004, a, R - 0.006)
                        bot = P(x, a, R - drop)
                    else:
                        top = P(x, a, R)
                        bot = P(x, a, rc - 0.004)
                    vid[(xi, ai, 0)] = part.vert(top)
                    vid[(xi, ai, 1)] = part.vert(bot)
            V = vid
            part.face((V[0, 0, 0], V[1, 0, 0], V[1, 1, 0], V[0, 1, 0]), mat)          # top
            part.face((V[0, 0, 0], V[0, 0, 1], V[1, 0, 1], V[1, 0, 0]), mat)          # leading wall
            part.face((V[0, 1, 0], V[1, 1, 0], V[1, 1, 1], V[0, 1, 1]), mat)          # trailing wall
            part.face((V[0, 0, 0], V[0, 1, 0], V[0, 1, 1], V[0, 0, 1]), mat)          # x0 wall
            part.face((V[1, 0, 0], V[1, 0, 1], V[1, 1, 1], V[1, 1, 0]), mat)          # x1 wall
            if sh:
                part.face((V[0, 0, 1], V[0, 1, 1], V[1, 1, 1], V[1, 0, 1]), mat)      # underside of the lug
            cen = sum((part.v[i] for i in V.values()), Vector()) / 8.0
            part.orient(start, ref=cen)
    return part


def arch_flare(y, z, r_in, r_out, x_out, x_body, a0=10.0, a1=170.0, segs=32, mat='Trim', embed=0.012):
    """Bolt-on plastic wheel-arch flare (added for ridgeback_sx), RIGHT side (mirror for the left).
    Arc around the arch centre (y, z) from a0 to a1 degrees (0 = +Y forward, 90 = up). Cross-section (radial r from
    the centre, lateral x): root (r_out, xb - embed) -> top surface leaving the body -> rounded top edge -> flat outer
    face at x_out -> rounded lip -> inner face at r_in back into the body. x_body: float or f(y, z) -> body side x."""
    xb_fn = x_body if callable(x_body) else (lambda yy, zz: x_body)
    part = Part()
    rows = []
    cents = []
    for k in range(segs + 1):
        a = math.radians(a0 + (a1 - a0) * k / segs)
        e = Vector((0.0, math.cos(a), math.sin(a)))
        c = Vector((0.0, y, z))
        pm = c + e * (0.5 * (r_in + r_out))
        xb = xb_fn(pm.y, pm.z)
        sec = [(r_out, xb - embed), (r_out - 0.004, xb + 0.010), (r_out - 0.020, x_out - 0.008),
               (r_out - 0.034, x_out), (r_in + 0.010, x_out), (r_in, x_out - 0.012), (r_in, xb - embed)]
        row = [part.vert(Vector((x, 0, 0)) + c + e * r) for (r, x) in sec]
        rows.append(row)
        cents.append(sum((part.v[i] for i in row), Vector()) / len(row))
    m = len(rows[0])
    for k in range(segs):
        for j in range(m):
            j2 = (j + 1) % m
            part.face((rows[k][j], rows[k][j2], rows[k + 1][j2], rows[k + 1][j]), mat)
    part.orient(0, ref_fn=lambda q: min(cents, key=lambda p: (p - q).length_squared))
    for (k, sgn) in ((0, -1), (segs, 1)):
        part.face(list(rows[k]), mat)
        a = math.radians(a0 if k == 0 else a1)
        tang = Vector((0.0, -math.sin(a), math.cos(a))) * sgn       # direction of increasing angle at the end
        if part.face_normal(len(part.f) - 1).dot(tang) < 0:
            part.f[-1] = tuple(reversed(part.f[-1]))
    return part


def _disc_face(n_holes, r_in, r_out, x_face, segs, hole_r=0.035, ring_f=0.62, hole_mat='Rubber', rings=3,
               mat='Rim'):
    """Solid dished wheel disc (added for the traffic vehicles): a lathed face from r_in to r_out following
    x_face(r) (front faces +X) plus `n_holes` dark inset discs ("hand holes") on the ring r_in + ring_f * (r_out - r_in).
    Cheap stand-in for the 'slot' style (no CDT holes). Returns Part."""
    rs = [r_out + (r_in - r_out) * k / rings for k in range(rings + 1)]
    part = revolve([(x_face(r), r) for r in rs], segs, mat)
    rh = r_in + ring_f * (r_out - r_in)
    for k in range(n_holes):
        a = math.pi / 2 + 2 * math.pi * (k + 0.5) / n_holes
        c = Vector((x_face(rh) + 0.0015, rh * math.cos(a), rh * math.sin(a)))
        part.extend(disc(c, (1, 0, 0), hole_r, hole_mat, n=10))
    return part


def build_wheel(R=0.315, W=0.225, rim_d_in=18, spokes=5, style='double', segs=48, disc_r=0.17,
                caliper_angle=150.0, caliper_span=44.0, spoke_w=None, spoke_thick=0.024, spoke_dish=0.036,
                hub_r=0.074, nuts=None, tyre='default', grooves=None, groove_w=0.012, slot_r=None, slot_w=None,
                face_segs=None, slot_wall_mat=None, barrel_mat=None, rim_segs=None, split=None, center_lock=None,
                groove_depth=None, zigzag=0.0, shoulder_zigzag=0.0, blocks=None, brake=True, disc=None):
    """Returns (wheel_part, caliper_part) for the RIGHT side: axle centre at origin, spin axis X,
    rim face toward +X, +Y forward, +Z up. Tyre contact at z = -R.
    Optional (added for aurelia_sedan, defaults keep the original look):
      spoke_w=(w_hub, w_taper) spoke width at the hub and its reduction toward the rim
              (default single (0.042, 0.012), double (0.034, 0.008));
      spoke_thick (front-back depth), spoke_dish (how far the spoke face rises from hub to rim),
      hub_r (centre cap radius), nuts (lug nut count; default = spokes).
    Optional (added for brute_68, defaults keep the original look):
      style='slot': solid dished face with `spokes` tapered radial slots ("slot mag"); slot_r=(r_a, r_b)
              slot end radii (default 0.48 / 0.86 of the rim radius), slot_w=(w_a, w_b) end widths,
              face thickness = spoke_thick, dish = spoke_dish, face_segs = outer ring vertex count;
      tyre='tall' (bulged sidewall for small rims / tall tyres); grooves=[x, ...] tread groove centres
              (default [-0.034, 0.034]); groove_w groove width at the tread;
      slot_wall_mat (material key of the slot walls, default 'Rim'), barrel_mat (material key of the
              inner rim barrel seen through the openings, default 'Rim').
    Optional (added for sora_s2, defaults keep the original look):
      style='split': `spokes` Y-shaped split spokes (stem from the hub, two thin arms to the rim);
              split=dict(split_f, stem_w=(w_hub, taper), arm_w=(w, taper), arm_gap) tunes them (see
              _split_spokes); rim_segs = segment count of the rim barrel (default = segs, the tyre's).
    Optional (added for vortex_x, defaults keep the original look):
      center_lock=dict(r=0.040, h=0.024, sides=6, mat='BrakeDisc', ring_mat='Rim') adds a big centre-lock
              nut (n-sided, chamfered) with a raised ring on the hub cap; combine with nuts=0.
    Optional (added for granite_rally, defaults keep the original look):
      groove_depth (default 0.0075) tread groove depth; zigzag=a shifts every tread groove sideways by +-a on
              alternate angular segments (zig-zag gravel grooves, no extra triangles; neighbouring grooves zig in
              opposite directions); shoulder_zigzag=a does the same for the two tread-edge rows (notched
              shoulder blocks).
    Optional (added for ridgeback_sx, default None keeps the original look):
      blocks=dict(n, h, rows) or True: all-terrain tyre with raised tread blocks (block_tyre; segs = carcass
              segments); grooves / zigzag are ignored then.
    Optional (added for the traffic vehicles, default True keeps the original look):
      brake=False skips the brake disc + hat (hidden behind solid steel-wheel faces; saves ~350 tris).
      style='disc': low-poly dished steel / alloy disc with `spokes` round hand holes (dark inset discs, no boolean);
              disc=dict(hole_r=0.035, ring_f=0.62, hole_mat='Rubber', rings=3) (see _disc_face)."""
    rr = rim_d_in * 0.0254 / 2.0           # bead seat radius
    hw = W / 2.0
    lip_x = hw - 0.012
    # ---- tyre ----
    g = 0.0075 if groove_depth is None else groove_depth
    prof = _tyre_profile(R, rr, hw, lip_x, tyre)
    nside = len(prof)
    grooves = [-0.034, 0.034] if grooves is None else list(grooves)
    gw = groove_w / 2.0
    tread = []
    for gx in grooves:
        tread += [(gx - gw, R), (gx - gw + 0.001, R - g), (gx + gw - 0.001, R - g), (gx + gw, R)]
    prof += tread
    prof += [(-a, r) for (a, r) in reversed(prof[:nside])]
    if blocks:
        tyre = block_tyre(R=R, W=W, rim_d_in=rim_d_in, segs=segs, **(blocks if isinstance(blocks, dict) else {}))
    else:
        tyre = revolve(prof, segs, 'Rubber')
    if (zigzag or shoulder_zigzag) and not blocks:   # every profile row is a full ring of `segs` vertices (r > 0)
        def _shift(row, amp):
            for j in range(segs):
                tyre.v[row * segs + j].x += amp * (1.0 if j % 2 == 0 else -1.0)
        for gi in range(len(grooves)):
            for k in range(4):
                _shift(nside + 4 * gi + k, zigzag * (1.0 if gi % 2 == 0 else -1.0))
        if shoulder_zigzag:
            _shift(nside - 1, shoulder_zigzag)
            _shift(nside + 4 * len(grooves), -shoulder_zigzag)
    # ---- rim barrel / lip ----
    rim_prof = [(lip_x + 0.006, rr + 0.010), (lip_x + 0.007, rr + 0.004), (lip_x + 0.004, rr - 0.004),
                (lip_x - 0.004, rr - 0.010), (lip_x - 0.020, rr - 0.015), (-lip_x + 0.010, rr - 0.015),
                (-lip_x, rr + 0.006)]
    rim = revolve(rim_prof, segs if rim_segs is None else rim_segs,
                  'Rim' if barrel_mat is None else ['Rim', 'Rim', 'Rim', 'Rim', barrel_mat, barrel_mat])
    # rim barrel inner surface must face the axis -> profile goes +x to -x along the inside: ok
    wheel = Part().extend(tyre, rim)
    # ---- spokes ----
    r0, r1 = 0.055, rr - 0.006
    x_front = lambda r: lip_x - 0.040 + spoke_dish * smoothstep(r0, r1, r)
    thick = spoke_thick
    nsec = [r0, r0 + 0.05, r0 + 0.11, r1]
    pairs = [(0.0, 0.0)] if style == 'single' else [(-1, 1), (1, 1)]
    if style == 'slot':
        sr = slot_r or (0.48 * rr, 0.86 * rr)
        sw = slot_w or (0.040, 0.056)
        wheel.extend(_slot_face(spokes, hub_r - 0.006, r1, sr, sw, x_front, thick, face_segs or segs,
                                math.pi / 2 + math.pi / spokes, wall_mat=slot_wall_mat))
    if style == 'split':
        wheel.extend(_split_spokes(spokes, r0, r1, x_front, thick, **(split or {})))
    if style == 'disc':
        wheel.extend(_disc_face(spokes, hub_r - 0.006, r1, x_front, face_segs or segs, **(disc or {})))
    for k in range(spokes if style not in ('slot', 'split', 'disc') else 0):
        a = math.pi / 2 + 2 * math.pi * k / spokes
        e = Vector((0, math.cos(a), math.sin(a)))
        p = Vector((0, -math.sin(a), math.cos(a)))
        for (sgn, _) in pairs:
            rows = []
            for r in nsec:
                f = (r - r0) / (r1 - r0)
                sep = 0.0 if style == 'single' else (0.0172 + 0.013 * f) * sgn
                if spoke_w is not None:
                    w = spoke_w[0] - spoke_w[1] * f
                else:
                    w = (0.042 - 0.012 * f) if style == 'single' else (0.034 - 0.008 * f)
                c = e * r + p * sep
                xf = x_front(r)
                xb = xf - thick
                ch = 0.003
                sec = [(xf, -w / 2 + ch), (xf, w / 2 - ch), (xf - ch, w / 2), (xb, w / 2 * 0.8),
                       (xb, -w / 2 * 0.8), (xf - ch, -w / 2)]
                rows.append([Vector((x, c.y + p.y * l, c.z + p.z * l)) for (x, l) in sec])
            sp = Part()
            idx = [[sp.vert(v) for v in row] for row in rows]
            ns = len(rows[0])
            for i in range(len(rows) - 1):
                for j in range(ns):
                    j2 = (j + 1) % ns
                    sp.face((idx[i][j], idx[i][j2], idx[i + 1][j2], idx[i + 1][j]), 'Rim')
            cen = [sum(rows[i], Vector()) / ns for i in range(len(rows))]

            def refc(c, cen=cen):
                best = min(cen, key=lambda q: (q - c).length)
                return best
            sp.orient(0, ref_fn=refc)
            wheel.extend(sp)
    # ---- hub + centre cap + lug nuts ----
    hub_x = x_front(r0) + 0.004
    hs = hub_r / 0.074
    hub = revolve([(hub_x - 0.035, hub_r), (hub_x - 0.002, hub_r), (hub_x + 0.002, 0.069 * hs),
                   (hub_x + 0.004, 0.040 * hs), (hub_x + 0.009, 0.034 * hs), (hub_x + 0.011, 0.0)], 24, 'Rim')
    wheel.extend(hub)
    if center_lock:
        cl = dict(r=0.040, h=0.024, sides=6, mat='BrakeDisc', ring_mat='Rim')
        cl.update(center_lock)
        x0 = hub_x + 0.002
        r_n, h_n = cl['r'], cl['h']
        ring = revolve([(x0, r_n * 1.30), (x0 + 0.006, r_n * 1.26), (x0 + 0.008, r_n * 1.02), (x0, r_n * 1.0)],
                       24, cl['ring_mat'])
        ring.orient(0, ref_fn=lambda c: Vector((x0 + 0.002, 0, 0)) + _unit(Vector((0, c.y, c.z))) * r_n * 1.14)
        wheel.extend(ring)
        nut = revolve([(x0, 0.0), (x0, r_n), (x0 + h_n - 0.005, r_n), (x0 + h_n, r_n * 0.72),
                       (x0 + h_n, 0.0)], int(cl['sides']), cl['mat'], theta0=math.pi / 2)
        wheel.extend(nut)
        pin = revolve([(x0 + h_n - 0.001, 0.0), (x0 + h_n - 0.001, r_n * 0.34), (x0 + h_n + 0.006, r_n * 0.30),
                       (x0 + h_n + 0.008, 0.0)], 12, cl['ring_mat'])
        wheel.extend(pin)
    n_nuts = spokes if nuts is None else nuts
    for k in range(n_nuts):
        a = math.pi / 2 + 2 * math.pi * (k + 0.5) / n_nuts
        c = Vector((hub_x + 0.002, 0.052 * math.cos(a), 0.052 * math.sin(a)))
        nut = revolve([(0.0, 0.0), (0.0, 0.0095), (0.013, 0.0090), (0.0145, 0.0)], 6, 'BrakeDisc')
        wheel.extend(nut.translated(c))
    # ---- brake disc + hat ----
    dx0, dx1 = -0.034, -0.008
    dprof = [(dx0, disc_r - 0.062), (dx0, disc_r), (dx1, disc_r), (dx1, disc_r - 0.062), (dx0, disc_r - 0.062)]
    dprof = [dprof[0], dprof[1], dprof[2], dprof[3], dprof[4]]
    if brake:
        disc_p = revolve(list(reversed(dprof)), 32, 'BrakeDisc')
        disc_p.orient(0, ref_fn=lambda c: Vector((-0.021, 0, 0)) + _unit(Vector((0, c.y, c.z))) * (disc_r - 0.031))
        wheel.extend(disc_p)
        hat = revolve([(dx1, disc_r - 0.062), (dx1 + 0.004, 0.090), (hub_x - 0.035, 0.074)], 24, 'BrakeDisc')
        hat.orient(0, ref=Vector((0, 0, 0)))
        wheel.extend(hat)
    # ---- caliper (does not spin) ----
    ca = math.radians(caliper_angle)
    span = math.radians(caliper_span) / 2
    cal_prof = [(-0.054, disc_r - 0.052), (-0.054, disc_r + 0.020), (0.014, disc_r + 0.020), (0.014, disc_r - 0.052),
                (-0.054, disc_r - 0.052)]
    cal = revolve(list(reversed(cal_prof)), 8, 'Caliper', theta0=ca - span, theta1=ca + span, caps=True)
    cal.orient(0, ref_fn=lambda c: Vector((-0.02, 0, 0)) + _unit(Vector((0, c.y, c.z))) * (disc_r - 0.016))
    return wheel, cal


def add_wheels(car, spec, axles):
    """axles: dict(front=(y, half_track), rear=(y, half_track)). spec: build_wheel kwargs.
    Creates Wheel_FL/FR/RL/RR and Caliper_* parts with origins at the axle centres."""
    R = spec.get('R', 0.315)
    out = {}
    for axle, key in (('front', 'F'), ('rear', 'R')):
        y, ht = axles[axle]
        sp = dict(spec)
        sp.update(spec.get(axle, {}))
        sp.pop('front', None)
        sp.pop('rear', None)
        wheel, cal = build_wheel(**sp)
        Ra = sp.get('R', R)        # per-axle radius (added for vortex_x; equals R when not overridden)
        for side, sk in ((1, 'R'), (-1, 'L')):
            w = wheel if side > 0 else wheel.mirrored_x()
            c = cal if side > 0 else cal.mirrored_x()
            loc = Vector((side * ht, y, Ra))
            car.add('Wheel_%s%s' % (key, sk), w, location=loc)
            car.add('Caliper_%s%s' % (key, sk), c, location=loc)
            out['%s%s' % (key, sk)] = loc
    car.info['wheels'] = out
    return out


# =====================================================================================
# Interior builders
# =====================================================================================
def _cushion_profile(w, h, b, r=0.03, n_top=12):
    hw = w / 2.0
    pts = [(-hw + r, 0.0), (hw - r, 0.0), (hw, r), (hw, h + b - r * 0.7)]
    for k in range(n_top + 1):
        u = 1.0 - 2.0 * k / n_top
        x = u * (hw - r * 0.5)
        z = h + b * smoothstep(0.42, 0.92, abs(u))
        pts.append((x, z))
    pts += [(-hw, h + b - r * 0.7), (-hw, r)]
    return pts


def _cushion_mats(n_top=12, side='InteriorDark', center='Interior'):
    mats = [side, side, side, side]     # bottom, right lower corner, right side, right top corner
    for k in range(n_top):
        u = 1.0 - 2.0 * (k + 0.5) / n_top
        mats.append(center if abs(u) < 0.55 else side)
    mats += [side, side, side]
    return mats


def bucket_seat(x, y_front, y_back, z_base, width=0.52, recline=17.0, back_h=0.86, bolster=0.075,
                headrest_w=0.27, bench=False):
    """Sport bucket seat (or a bench when bench=True). Returns Part (Interior / InteriorDark)."""
    part = Part()
    n_top = 12
    # cushion (along -Y): profile (x, z)
    ys = [y_front, y_front - 0.02, y_front - 0.06, (y_front + y_back) / 2, y_back + 0.03, y_back]
    profs = []
    L = y_front - y_back
    for yy in ys:
        f = (y_front - yy) / L
        hgt = 0.10 + 0.03 * (1 - f)
        sc = 0.85 if yy == y_front else (0.96 if yy == ys[1] else 1.0)
        b = bolster * (0.5 if bench else 1.0)
        pr = _cushion_profile(width * (0.97 if yy == y_front else 1.0), hgt * sc, b * sc, n_top=n_top)
        profs.append([(x + px, z_base + pz) for (px, pz) in pr])
    cush = sweep_axis('y', ys, profs, _cushion_mats(n_top), cap0=True, cap1=True, cap_mat='InteriorDark')
    part.extend(cush)
    # backrest: built upright along Z then reclined about X at its base
    zs = [0.0, 0.04, 0.25, 0.48, 0.56, 0.62, 0.66, back_h - 0.04, back_h]
    if bench:
        zs = [0.0, 0.04, 0.25, 0.45, back_h - 0.03, back_h]
    profs = []
    for zz in zs:
        f = zz / back_h
        if bench:
            w = width
            b = bolster * 0.5 * (1 - f)
            t = 0.10
        else:
            if zz <= 0.56:
                w = width * (0.96 + 0.06 * smoothstep(0.0, 0.48, zz))
                b = bolster * (1.1 - 0.5 * smoothstep(0.25, 0.56, zz))
            elif zz <= 0.62:
                w = lerp(width * 1.0, headrest_w + 0.04, smoothstep(0.56, 0.62, zz))
                b = bolster * 0.3
            else:
                w = headrest_w * (0.94 if zz == back_h else 1.0)
                b = 0.018
            t = 0.11 - 0.02 * f
        if zz in (0.0, back_h):
            w *= 0.97
        pr = _cushion_profile(w, t, b, r=0.025, n_top=n_top)
        profs.append([(x + px, pz) for (px, pz) in pr])
    # axis 'z' sweep: profile (x, y) -> the bolster side (profile "top") faces +Y = forward
    back = sweep_axis('z', zs, profs, _cushion_mats(n_top), cap0=True, cap1=True, cap_mat='InteriorDark')
    M = Matrix.Translation((0, y_back - 0.05, z_base + 0.05)) @ Matrix.Rotation(math.radians(recline), 4, 'X')
    part.extend(back.transformed(M))
    if not bench:
        # seat base / runners
        part.extend(box_between((x, y_front - 0.08, z_base - 0.07), (x, y_back + 0.04, z_base - 0.07), width * 0.7, 0.12, 'InteriorDark'))
    return part


def steering_wheel_part(R=0.180, tube_r=(0.016, 0.019), segs=40, flat_bottom=True, spokes=None,
                        hub_r=0.058, rim_mat='InteriorDark', spoke_mat='Interior', hub_mat='InteriorDark',
                        marker=True, spoke_thick=0.014, dish=0.030, flat_top=None):
    """Local frame: hub at origin, rim in the XZ plane, +Y = column toward the dashboard.
    spokes: optional [(angle_deg, width)] (0 = 3 o'clock, 270 = 6 o'clock); default 3 spokes
    ((0, 0.05), (180, 0.05), (270, 0.04)). hub_r: hub pad radius (default 0.058).
    Optional (added for brute_68; defaults unchanged): rim_mat / spoke_mat / hub_mat material keys
    (e.g. 'InteriorWood' rim + 'Chrome' spokes), marker (12 o'clock band), spoke_thick, dish (how far
    the spokes' hub end sits toward the column).
    Optional (added for vortex_x; default None = round top): flat_top=f flattens the rim above z = f*R
    (e.g. 0.80 with flat_bottom for a squared, yoke-like racing wheel)."""
    part = Part()
    rows = []
    ns = 10

    def _flat(c):
        if flat_bottom and c.z < -R * 0.86:
            c.z = -R * 0.86 + (c.z + R * 0.86) * 0.25
        if flat_top is not None and c.z > R * flat_top:
            c.z = R * flat_top + (c.z - R * flat_top) * 0.25
        return c
    for k in range(segs):
        a = 2 * math.pi * k / segs
        c = _flat(Vector((R * math.cos(a), 0.0, R * math.sin(a))))
        radial = _unit(Vector((c.x, 0, c.z)))
        row = []
        for j in range(ns):
            b = 2 * math.pi * j / ns
            row.append(part.vert(c + radial * (tube_r[1] * math.cos(b)) + Vector((0, 1, 0)) * (tube_r[0] * math.sin(b))))
        rows.append(row)
    for k in range(segs):
        k2 = (k + 1) % segs
        a = 2 * math.pi * (k + 0.5) / segs
        top = abs(a - math.pi / 2) < 0.07
        for j in range(ns):
            j2 = (j + 1) % ns
            part.face((rows[k][j], rows[k][j2], rows[k2][j2], rows[k2][j]), 'Gauge' if (top and marker) else rim_mat)
    centers = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        centers.append(_flat(Vector((R * math.cos(a), 0.0, R * math.sin(a)))))
    part.orient(0, ref_fn=lambda c: min(centers, key=lambda q: (q - c).length))
    # spokes (3 o'clock, 9 o'clock, 6 o'clock)
    spoke_list = spokes if spokes is not None else ((0.0, 0.050), (180.0, 0.050), (270.0, 0.040))
    for ang, w in spoke_list:
        a = math.radians(ang)
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        p0 = d * 0.045 + Vector((0, dish, 0))
        p1 = d * (R - 0.010) + Vector((0, 0.004, 0))
        part.extend(box_between(p0, p1, w, spoke_thick, spoke_mat, up=(0, 1, 0)))
    # hub
    hk = hub_r / 0.058
    hub = revolve([(0.0, 0.0), (0.0, 0.050 * hk), (0.004, hub_r), (0.060, hub_r), (0.064, 0.0)], 24, hub_mat)
    hub = hub.transformed(Matrix.Rotation(math.radians(90), 4, 'Z'))   # lathe axis X -> Y
    hub = hub.translated((0, -0.012, 0))
    part.extend(hub)
    return part


def gauge(center, normal, radius, n_ticks=11, arc=240.0, needle_deg=210.0):
    c = Vector(center)
    nrm = _unit(Vector(normal))
    u = _unit(Vector((0, 0, 1)).cross(nrm), Vector((1, 0, 0)))
    if u.length < 0.5:
        u = Vector((1, 0, 0))
    w = nrm.cross(u)
    part = disc(c, nrm, radius, 'InteriorDark', n=28, ring_mat='Gauge', ring_w=0.004)
    for k in range(n_ticks):
        a = math.radians(90 + arc / 2 - arc * k / (n_ticks - 1))
        d = u * math.cos(a) + w * math.sin(a)
        p0 = c + d * radius * 0.78 + nrm * 0.0015
        p1 = c + d * radius * 0.94 + nrm * 0.0015
        side = nrm.cross(d) * 0.0022
        t = Part()
        i0 = t.vert(p0 - side)
        i1 = t.vert(p1 - side)
        i2 = t.vert(p1 + side)
        i3 = t.vert(p0 + side)
        t.face((i0, i1, i2, i3), 'Gauge')
        if t.face_normal(0).dot(nrm) < 0:
            t.f[0] = tuple(reversed(t.f[0]))
        part.extend(t)
    a = math.radians(needle_deg)
    d = u * math.cos(a) + w * math.sin(a)
    side = nrm.cross(d) * 0.002
    t = Part()
    i0 = t.vert(c - d * 0.01 - side + nrm * 0.003)
    i1 = t.vert(c + d * radius * 0.85 + nrm * 0.003)
    i2 = t.vert(c - d * 0.01 + side + nrm * 0.003)
    t.face((i0, i1, i2), 'Gauge')
    if t.face_normal(0).dot(nrm) < 0:
        t.f[0] = tuple(reversed(t.f[0]))
    part.extend(t)
    return part


# =====================================================================================
# QA / export
# =====================================================================================
def tri_counts(car):
    dg = bpy.context.evaluated_depsgraph_get()
    out = {}
    total = 0
    for name, ob in car.objects.items():
        if ob.type != 'MESH':
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        n = len(me.loop_triangles)
        ev.to_mesh_clear()
        out[name] = n
        total += n
    out['total'] = total
    return out


def qa_checks(car, wheel_R, wheel_W, rays=400):
    """Numeric sanity checks: wheel ground contact, arch clearance, outward normals (ray test),
    degenerate faces. Returns a dict (also printed by the car scripts)."""
    import random
    dg = bpy.context.evaluated_depsgraph_get()
    out = {}
    body = car.objects['Body']
    bvh = BVHTree.FromObject(body, dg)
    for key in ('FL', 'FR', 'RL', 'RR'):
        w = car.objects.get('Wheel_' + key)
        if w is None:
            continue
        zs = [(w.matrix_world @ v.co).z for v in w.data.vertices]
        c = w.matrix_world.translation
        clear = 1e9
        for k in range(0, 181, 6):
            a = math.radians(k)
            for xo in (-wheel_W * 0.45, 0.0, wheel_W * 0.45):
                p = Vector((c.x + xo, c.y + wheel_R * math.cos(a), c.z + wheel_R * math.sin(a)))
                loc, nor, idx, d = bvh.find_nearest(p)
                if loc is not None:
                    clear = min(clear, d)
        out['wheel_%s' % key] = dict(min_z=round(min(zs), 4), arch_clearance=round(clear, 4))
    # outward normal test: rays from outside toward the car centre hit front faces of the body
    random.seed(1)
    bad = 0
    total = 0
    mn, mx = world_aabb([body])
    cen = (mn + mx) / 2
    for i in range(rays):
        d = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.2, 1))).normalized()
        o = cen + d * 6.0
        tgt = cen + Vector((random.uniform(-0.6, 0.6), random.uniform(-1.6, 1.6), random.uniform(-0.2, 0.3)))
        res, loc, nor, idx, ob, mat = bpy.context.scene.ray_cast(dg, o, (tgt - o).normalized())
        if res and ob == body:
            total += 1
            if nor.dot((tgt - o).normalized()) > 0:
                bad += 1
    out['body_ray_hits'] = total
    out['body_backface_hits'] = bad
    me = body.data
    out['body_degenerate_faces'] = sum(1 for p in me.polygons if p.area < 1e-9)
    return out


def car_objects(car):
    obs = [car.root]

    def rec(o):
        for c in o.children:
            obs.append(c)
            rec(c)
    rec(car.root)
    return obs


def export_car(car, glb_path, extra=None):
    """extra (optional, added for the traffic vehicles; default None = unchanged): additional glTF exporter keyword
    arguments (e.g. export_vertex_color='ACTIVE'); unknown keys are dropped like the defaults."""
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    names = {p.identifier for p in props}
    obs = car_objects(car)
    # canonical names for export
    renames = []
    blockers = []
    try:
        for ob in obs:
            if '__' in ob.name:
                canon = ob.name.split('__')[0]
                other = bpy.data.objects.get(canon)
                if other is not None and other != ob:
                    blockers.append((other, other.name))
                    other.name = canon + '__tmp_export_blocker'
                renames.append((ob, ob.name))
                ob.name = canon
                if ob.name != canon:
                    raise RuntimeError('could not rename %s to %s' % (renames[-1][1], canon))
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = car.root
        kw = dict(filepath=glb_path, export_format='GLB', use_selection=True, export_apply=True,
                  export_yup=True, export_materials='EXPORT', export_texcoords=True, export_normals=True,
                  export_cameras=False, export_lights=False, export_animations=False,
                  export_draco_mesh_compression_enable=False, export_extras=False, export_tangents=False)
        if extra:
            kw.update(extra)
        kw = {k: v for k, v in kw.items() if k in names or k == 'filepath'}
        os.makedirs(os.path.dirname(glb_path), exist_ok=True)
        res = bpy.ops.export_scene.gltf(**kw)
    finally:
        for ob, old in reversed(renames):
            ob.name = old
        for other, old in blockers:
            other.name = old
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
    return res, read_glb(glb_path)


def read_glb(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    magic, version, length = struct.unpack_from('<4sII', data, 0)
    clen, ctype = struct.unpack_from('<I4s', data, 12)
    js = json.loads(data[20:20 + clen].decode('utf-8'))
    nodes = []
    for n in js.get('nodes', []):
        nodes.append({'name': n.get('name'), 'translation': n.get('translation', [0, 0, 0]),
                      'rotation': n.get('rotation', [0, 0, 0, 1]), 'mesh': n.get('mesh'),
                      'children': n.get('children', [])})
    mats = [{'name': m.get('name'), 'alphaMode': m.get('alphaMode', 'OPAQUE'),
             'doubleSided': m.get('doubleSided', False)} for m in js.get('materials', [])]
    return {'magic': magic.decode(), 'version': version, 'length': length, 'file_size': len(data),
            'nodes': nodes, 'materials': mats, 'meshes': len(js.get('meshes', [])),
            'extensionsUsed': js.get('extensionsUsed', []), 'scenes': js.get('scenes', [])}


def to_godot(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def world_aabb(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        if ob.type != 'MESH':
            continue
        M = ob.matrix_world
        for v in ob.data.vertices:
            w = M @ v.co
            for k in range(3):
                mn[k] = min(mn[k], w[k])
                mx[k] = max(mx[k], w[k])
    return mn, mx


def write_car_json(car, path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=2)
    return path


def ensure_qa_collection():
    col = bpy.data.collections.get('_QA')
    if col is None:
        col = bpy.data.collections.new('_QA')
        bpy.context.scene.collection.children.link(col)
    elif col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    return col


def render_hero(car, png_path, cam_loc=(5.6, 5.4, 1.75), target=(0.0, 0.1, 0.55), lens=50.0,
                sun_rot=(math.radians(50), 0.0, math.radians(140)), world_rgb=(0.55, 0.62, 0.72),
                res=(1280, 720), ground_rgb=(0.32, 0.32, 0.33), view_transform='Standard', exposure=0.0,
                sun_energy=4.0, world_strength=1.0):
    scene = bpy.context.scene
    col = ensure_qa_collection()
    col.hide_viewport = False
    col.hide_render = False
    cam = bpy.data.objects.get('QA_Camera')
    if cam is None:
        cam = bpy.data.objects.new('QA_Camera', bpy.data.cameras.new('QA_Camera'))
        col.objects.link(cam)
    sun = bpy.data.objects.get('QA_Sun')
    if sun is None:
        sun = bpy.data.objects.new('QA_Sun', bpy.data.lights.new('QA_Sun', 'SUN'))
        col.objects.link(sun)
    ground = bpy.data.objects.get('QA_Ground')
    if ground is None:
        gm = bpy.data.meshes.new('QA_Ground')
        gbm = bmesh.new()
        bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=40.0)
        gbm.to_mesh(gm)
        gbm.free()
        ground = bpy.data.objects.new('QA_Ground', gm)
        col.objects.link(ground)
    gmat = make_material('QA_GroundMat', base=ground_rgb, roughness=0.9)
    if not ground.data.materials:
        ground.data.materials.append(gmat)
    cam.location = Vector(cam_loc)
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = lens
    sun.rotation_euler = sun_rot
    sun.data.energy = sun_energy
    try:
        sun.data.angle = math.radians(3.0)
    except Exception:
        pass
    world = bpy.data.worlds.get('QA_World') or bpy.data.worlds.new('QA_World')
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = next((n for n in world.node_tree.nodes if n.type == 'BACKGROUND'), None)
    if bg is None:
        bg = world.node_tree.nodes.new('ShaderNodeBackground')
        wo = next((n for n in world.node_tree.nodes if n.type == 'OUTPUT_WORLD'), None) or world.node_tree.nodes.new('ShaderNodeOutputWorld')
        world.node_tree.links.new(bg.outputs[0], wo.inputs[0])
    bg.inputs[0].default_value = (world_rgb[0], world_rgb[1], world_rgb[2], 1.0)
    bg.inputs[1].default_value = world_strength
    r = scene.render
    vs = scene.view_settings
    saved = dict(engine=r.engine, rx=r.resolution_x, ry=r.resolution_y, pct=r.resolution_percentage,
                 fp=r.filepath, fmt=r.image_settings.file_format, cam=scene.camera, world=scene.world,
                 transparent=r.film_transparent, vt=vs.view_transform, look=vs.look, exposure=vs.exposure)
    try:
        try:
            r.engine = 'BLENDER_EEVEE'
        except TypeError as ex:
            print('engine set failed', ex)
        r.resolution_x, r.resolution_y = res
        r.resolution_percentage = 100
        fmts = [i.identifier for i in bpy.types.ImageFormatSettings.bl_rna.properties['file_format'].enum_items]
        if 'PNG' in fmts:
            r.image_settings.file_format = 'PNG'
        r.filepath = png_path
        r.film_transparent = False
        try:                      # view transforms come from the OCIO config (dynamic enum)
            vs.view_transform = view_transform
        except TypeError as ex:
            print('view transform not available:', ex)
        vs.exposure = exposure
        scene.camera = cam
        scene.world = world
        os.makedirs(os.path.dirname(png_path), exist_ok=True)
        bpy.ops.render.render(write_still=True)
    finally:
        r.engine = saved['engine']
        r.resolution_x, r.resolution_y = saved['rx'], saved['ry']
        r.resolution_percentage = saved['pct']
        r.filepath = saved['fp']
        try:
            r.image_settings.file_format = saved['fmt']
        except Exception:
            pass
        r.film_transparent = saved['transparent']
        try:
            vs.view_transform = saved['vt']
            vs.look = saved['look']
        except Exception:
            pass
        vs.exposure = saved['exposure']
        scene.camera = saved['cam']
        scene.world = saved['world']
        col.hide_viewport = True
        lc = bpy.context.view_layer.layer_collection.children.get('_QA')
        if lc is not None:
            lc.hide_viewport = True
    return png_path


# =====================================================================================
# ADDED FOR the traffic vehicles (tools/blender/traffic/*). All optional; existing defaults unchanged.
# =====================================================================================
def group_collection(group):
    """SUNWARD_GODOT/<group> collection (created if missing), e.g. 'Traffic'."""
    root = bpy.data.collections.get('SUNWARD_GODOT')
    if root is None:
        root = bpy.data.collections.new('SUNWARD_GODOT')
        bpy.context.scene.collection.children.link(root)
    return _ensure_child_collection(group, root)


def bm_to_part(bm, keys, key_of_face=None):
    """BMesh -> Part. keys[material_index] gives the material key; key_of_face(face) -> key (or None) overrides it."""
    part = Part()
    vi = {}
    for v in bm.verts:
        vi[v] = part.vert(v.co)
    for f in bm.faces:
        k = key_of_face(f) if key_of_face else None
        if k is None:
            k = keys[f.material_index] if f.material_index < len(keys) else keys[0]
        part.face([vi[v] for v in f.verts], k)
    return part


def abox(p0, p1, mat):
    """Axis-aligned box between two opposite corners (any order)."""
    a = Vector((min(p0[0], p1[0]), min(p0[1], p1[1]), min(p0[2], p1[2])))
    b = Vector((max(p0[0], p1[0]), max(p0[1], p1[1]), max(p0[2], p1[2])))
    cx, cz = (a.x + b.x) / 2, (a.z + b.z) / 2
    return box_between((cx, a.y, cz), (cx, b.y, cz), b.x - a.x, b.z - a.z, mat)


def rbox(axis, s0, s1, c, w, h, r, mat, n=2):
    """Box along `axis` ('x'|'y'|'z') from s0 to s1 whose cross-section is a rounded rectangle (w x h, corner r)
    centred at c = (u, v) in the sweep_axis profile plane ('x': (y, z), 'y': (x, z), 'z': (x, y))."""
    prof = rrect_pts(c[0], c[1], w, h, max(min(r, 0.49 * min(w, h)), 1e-4), n=n)
    return sweep_axis(axis, [s0, s1], prof, mat)


def fillet_profile(pts, step=0.08, arc_step=0.03, min_seg=2):
    """Closed 2D outline [(a, b) or (a, b, r)] -> dense CCW outline (list of Vector) with circular fillets of
    radius r at the corners (convex or concave) and straight edges resampled to <= step."""
    P = [Vector((p[0], p[1])) for p in pts]
    Rr = [float(p[2]) if len(p) > 2 else 0.0 for p in pts]
    if poly_area(P) < 0:
        P.reverse()
        Rr.reverse()
    n = len(P)
    arcs = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        u = _unit(a - b)
        w = _unit(c - b)
        ang = math.acos(clamp(u.dot(w), -1.0, 1.0))
        r = Rr[i]
        if r <= 0 or ang < 1e-3 or ang > math.pi - 1e-3:
            arcs.append([b.copy()])
            continue
        t = min(r / math.tan(ang / 2), 0.5 * (a - b).length, 0.5 * (c - b).length)
        re = t * math.tan(ang / 2)
        p0 = b + u * t
        p1 = b + w * t
        cen = b + _unit(u + w) * (re / math.sin(ang / 2))
        a0 = math.atan2(p0.y - cen.y, p0.x - cen.x)
        a1 = math.atan2(p1.y - cen.y, p1.x - cen.x)
        da = a1 - a0
        while da > math.pi:
            da -= 2 * math.pi
        while da < -math.pi:
            da += 2 * math.pi
        m = max(min_seg, int(math.ceil(abs(da) * re / arc_step)))
        arcs.append([cen + Vector((math.cos(a0 + da * k / m), math.sin(a0 + da * k / m))) * re for k in range(m + 1)])
    out = []
    for i in range(n):
        arc = arcs[i]
        out.extend(arc)
        e0, e1 = arc[-1], arcs[(i + 1) % n][0]
        m = max(1, int(math.ceil((e1 - e0).length / step)))
        for k in range(1, m):
            out.append(e0.lerp(e1, k / m))
    clean = []
    for p in out:
        if not clean or (p - clean[-1]).length > 1e-5:
            clean.append(p)
    if len(clean) > 2 and (clean[0] - clean[-1]).length < 1e-5:
        clean.pop()
    return clean


def _segments_cross(a, b, c, d):
    def orient(p, q, r):
        return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return (o1 * o2 < -1e-14) and (o3 * o4 < -1e-14)


def polyline_self_intersections(pts, closed=True, limit=5):
    """Pairs of crossing (non-adjacent) segments of a 2D polyline (validation helper)."""
    n = len(pts)
    segs = n if closed else n - 1
    out = []
    for i in range(segs):
        a, b = pts[i], pts[(i + 1) % n]
        for j in range(i + 2, segs):
            if closed and i == 0 and j == segs - 1:
                continue
            if _segments_cross(a, b, pts[j], pts[(j + 1) % n]):
                out.append((i, j))
                if len(out) >= limit:
                    return out
    return out


class ProfileBody:
    """Boxy body for vans, lorry cabs, buses, old pickups, tractor hoods (added for the traffic vehicles).

    A closed side-view outline (y, z) is extruded across the car (x = -hw .. +hw). The long edges between the two
    flat side panels (x = +-hw) and the 'band' (everything the outline runs along: floor, front face, hood,
    windscreen, roof, rear face) are rounded with radius edge_r (float or f(y, z)). The band is a quad grid of
    rings (one per outline sample) x cross-section points (right arc, flat part split at +-flat_x, left arc); the
    side panels are planar constrained-Delaunay triangulations whose outline is the band's arc end, so the shell is
    closed and watertight.
      profile : [(y, z) or (y, z, fillet_r)] corners of the side silhouette; fillet_r rounds the corner in side view
                (every convex fillet must be >= edge_r or the side-panel outline self-intersects).
      splits  : [('y'|'z', value)] force rings where the outline crosses that line; on the side panels the matching
                outline points are joined by constraint edges -> crisp two-tone livery / panel boundaries.
      marks   : [(y, z)] points on the outline that become rings (ends of band windows: windscreen, rear glass).
      flat_x  : positive x breakpoints of the flat band part (mirrored), e.g. windscreen / rear window edges.
    build(car, arches, side_holes, band_holes, lining, mat_fn, ...) -> Shell-like object (see build()).
    """

    def __init__(self, profile, hw, edge_r=0.06, edge_segs=3, step=0.10, arc_step=0.03, flat_x=(), splits=(),
                 marks=(), center_line=False):
        self.hw = float(hw)
        self.ka = int(edge_segs)
        pts = [p.copy() for p in fillet_profile(profile, step, arc_step)]
        forced = [False] * len(pts)

        def insert_after(i, q):
            pts.insert(i + 1, q)
            forced.insert(i + 1, True)

        for axis, val in splits:
            ax = 0 if axis == 'y' else 1
            i = 0
            while i < len(pts):
                a, b = pts[i], pts[(i + 1) % len(pts)]
                da, db = a[ax] - val, b[ax] - val
                if abs(da) < 1e-6:
                    a[ax] = val
                    forced[i] = True
                elif abs(db) > 1e-6 and da * db < 0:
                    t = da / (da - db)
                    q = a.lerp(b, t)
                    q[ax] = val
                    insert_after(i, q)
                    i += 1
                i += 1
        self.mark_pts = [Vector(m) for m in marks]
        for mv in self.mark_pts:
            best = None
            for i in range(len(pts)):
                a, b = pts[i], pts[(i + 1) % len(pts)]
                ab = b - a
                L2 = ab.length_squared
                t = 0.0 if L2 < 1e-12 else clamp((mv - a).dot(ab) / L2, 0.0, 1.0)
                q = a + ab * t
                dd = (q - mv).length
                if best is None or dd < best[0]:
                    best = (dd, i, t, q)
            dd, i, t, q = best
            if dd > 0.05:
                raise ValueError('mark %s is %.3f m off the profile' % (tuple(mv), dd))
            if t < 1e-4:
                forced[i] = True
            elif t > 1 - 1e-4:
                forced[(i + 1) % len(pts)] = True
            else:
                insert_after(i, q)
        # drop free samples that crowd a forced one
        keep_p, keep_f = [], []
        n0 = len(pts)
        for i in range(n0):
            if not forced[i]:
                near = False
                for j in (i - 1, (i + 1) % n0):
                    if forced[j] and (pts[j] - pts[i]).length < 0.012:
                        near = True
                if near:
                    continue
            keep_p.append(pts[i])
            keep_f.append(forced[i])
        self.P = keep_p
        self.forced = keep_f
        M = len(self.P)
        self.M = M
        self.N = []
        for i in range(M):
            a, b, c = self.P[i - 1], self.P[i], self.P[(i + 1) % M]
            e0, e1 = _unit(b - a), _unit(c - b)
            self.N.append(_unit(Vector((e0.y, -e0.x)) + Vector((e1.y, -e1.x)), Vector((e1.y, -e1.x))))
        self.r = [float(edge_r(p.x, p.y)) if callable(edge_r) else float(edge_r) for p in self.P]
        self.mark_index = []
        for mv in self.mark_pts:
            k = min(range(M), key=lambda i: (self.P[i] - mv).length_squared)
            self.mark_index.append(k)
        # split pairs (outline points joined across the side panels)
        self.split_pairs = []
        for axis, val in splits:
            ax = 0 if axis == 'y' else 1
            oth = 1 - ax
            idx = sorted([i for i in range(M) if self.forced[i] and abs(self.P[i][ax] - val) < 1e-6],
                         key=lambda i: self.P[i][oth])
            for a_, b_ in zip(idx[0::2], idx[1::2]):
                self.split_pairs.append((a_, b_))
        fx = sorted({round(abs(x), 6) for x in flat_x if abs(x) > 1e-6}, reverse=True)
        self.flat = fx + ([0.0] if center_line else []) + [-x for x in reversed(fx)]
        for i in range(M):
            lim = self.hw - self.r[i]
            if fx and fx[0] > lim - 0.004:
                raise ValueError('flat_x %.3f reaches the rounded edge (hw - r = %.3f at y=%.3f z=%.3f)'
                                 % (fx[0], lim, self.P[i].x, self.P[i].y))
        self.K = 2 * (self.ka + 1) + len(self.flat)
        self.Q = [self.P[i] - self.N[i] * self.r[i] for i in range(M)]
        bad = polyline_self_intersections(self.Q)
        if bad:
            raise ValueError('side-panel outline self-intersects near %s (edge_r larger than a convex fillet?)'
                             % [tuple(round(c, 3) for c in self.Q[i]) for i, j in bad[:3]])

    # ---- cross-section ------------------------------------------------------------
    def k_of_x(self, x):
        """Cross-section index of the flat breakpoint x (exact) or 'right' / 'left' (arc start of that side)."""
        if x == 'right':
            return self.ka
        if x == 'left':
            return self.K - 1 - self.ka
        for j, fxv in enumerate(self.flat):
            if abs(fxv - x) < 1e-6:
                return self.ka + 1 + j
        raise ValueError('x=%s is not a flat_x breakpoint %s' % (x, self.flat))

    def ring(self, i, d=0.0):
        P, N, r = self.P[i], self.N[i], self.r[i]
        rr = r - d
        cx = self.hw - r
        cq = P - N * r
        ka = self.ka
        out = []
        for k in range(ka + 1):
            phi = 0.5 * math.pi * k / ka
            q = cq + N * (rr * math.sin(phi))
            out.append(Vector((cx + rr * math.cos(phi), q.x, q.y)))
        q = P - N * d
        for x in self.flat:
            out.append(Vector((x, q.x, q.y)))
        for k in range(ka, -1, -1):
            phi = 0.5 * math.pi * k / ka
            q = cq + N * (rr * math.sin(phi))
            out.append(Vector((-(cx + rr * math.cos(phi)), q.x, q.y)))
        return out

    def normal3(self, i, k):
        N = self.N[i]
        ka = self.ka
        if k <= ka:
            phi = 0.5 * math.pi * k / ka
            return Vector((math.cos(phi), N.x * math.sin(phi), N.y * math.sin(phi)))
        if k >= self.K - 1 - ka:
            kk = self.K - 1 - k
            phi = 0.5 * math.pi * kk / ka
            return Vector((-math.cos(phi), N.x * math.sin(phi), N.y * math.sin(phi)))
        return Vector((0.0, N.x, N.y))

    def irange(self, i0, i1):
        i = i0
        out = []
        while i != i1:
            out.append(i)
            i = (i + 1) % self.M
        return out

    # ---- side panels --------------------------------------------------------------
    def side_cdt(self, holes, res=0.0):
        """CDT of the side outline Q with hole polygons (as constraint faces) and split edges.
        Returns (verts2d, tris, vmap, tri_hole, polys): vmap[k] = ring index for outline vertices else None;
        tri_hole[t] = index of the hole polygon containing the triangle, or -1."""
        M = self.M
        verts = [q.copy() for q in self.Q]
        faces = [list(range(M))]
        polys = []
        for h in holes:
            pts = [Vector((p[0], p[1])) for p in h]
            if poly_area(pts) < 0:
                pts.reverse()
            polys.append(pts)
            base = len(verts)
            verts += pts
            faces.append(list(range(base, base + len(pts))))
        edges = list(self.split_pairs)
        if res > 0:
            ys = [q.x for q in self.Q]
            zs = [q.y for q in self.Q]
            gy = min(ys) + res * 0.5
            while gy < max(ys):
                gz = min(zs) + res * 0.5
                while gz < max(zs):
                    g = Vector((gy, gz))
                    ok = point_in_poly(g, self.Q) and dist_to_poly(g, self.Q) > res * 0.45
                    if ok:
                        for pts in polys:
                            if point_in_poly(g, pts) or dist_to_poly(g, pts) < res * 0.45:
                                ok = False
                                break
                    if ok:
                        for a_, b_ in self.split_pairs:
                            if dist_to_poly(g, [self.Q[a_], self.Q[b_]], closed=False) < res * 0.45:
                                ok = False
                                break
                    if ok:
                        verts.append(g)
                    gz += res
                gy += res
        out = geometry.delaunay_2d_cdt(verts, edges, faces, 1, 1e-7)
        ov, of, overt = out[0], out[2], out[3]
        vmap = []
        for k in range(len(ov)):
            o = [j for j in overt[k] if j < M]
            vmap.append(o[0] if o else None)
        tri_hole = []
        for f in of:
            c = sum((ov[k] for k in f), Vector((0.0, 0.0))) / len(f)
            hid = -1
            for j, pts in enumerate(polys):
                if point_in_poly(c, pts):
                    hid = j
                    break
            tri_hole.append(hid)
        return ov, of, vmap, tri_hole, polys

    # ---- build --------------------------------------------------------------------
    def build(self, car, arches=(), side_holes=(), band_holes=(), lining=None, mat_fn=None, glass_inset=0.006,
              reveal_mat='Trim', black_mat=None, lip=0.009, lip_segments=2, solver='EXACT', side_res=0.0,
              reveal_depth=0.035):
        """side_holes: [dict(pts=[(y, z)..], role='glass'|'open'|'black', side=0|1|-1, fillet=0.0)]
        band_holes: [dict(a=(y, z), b=(y, z), x=(x0, x1) | None, role=...)]; a/b are `marks` (a -> b in CCW
            outline order: for a +Y-facing car that is front-bottom -> rear-top, e.g. windscreen base -> header);
            x0/x1 are flat_x breakpoints (signed) or None for the whole flat part.
        lining: dict(d=0.035, y=(y0, y1), z=(z0, z1), planes=[((y, z), (ny, nz))], mats=dict(floor, roof, wall,
            fill)) -> inner cabin skin (offset of the shell by d, same window holes) clipped to the cabin region
            (each plane removes the side its normal points to); its cut openings are filled (bulkheads, floor).
        mat_fn(center, normal, where) -> material key (where 'band' | 'side'); default Paint / Underbody below.
        role 'glass': hole + reveal (reveal_mat) to the lining + glass pane; 'open': hole + reveal;
            'black': no hole, faces get black_mat (default reveal_mat) and a glass pane 1.5 mm above them.
        Returns obj with .part (outer shell Part, wheel arches cut + lips), .surface (Surface, BVH before the
        windows are removed), .glass, .reveals, .lining (Parts), .side (CDT data), .holes (3D outlines)."""
        M, K = self.M, self.K
        black_mat = black_mat or reveal_mat
        mat_fn = mat_fn or (lambda c, n, where: 'Underbody' if (where == 'band' and n.z < -0.7) else 'Paint')
        midx = {k: i for i, k in enumerate(BODY_MATS)}
        sh = Shell()
        rings = [self.ring(i) for i in range(M)]
        # ---- band hole cells
        cell_role = {}
        band_regions = []

        def mark_i(p):
            j = min(range(len(self.mark_pts)), key=lambda jj: (self.mark_pts[jj] - Vector(p)).length)
            return self.mark_index[j]
        for hid, h in enumerate(band_holes):
            ia, ib = mark_i(h['a']), mark_i(h['b'])
            if h.get('x') is None:
                k_lo, k_hi = self.k_of_x('right'), self.k_of_x('left')
            else:
                x0, x1 = sorted(h['x'])
                k_lo, k_hi = self.k_of_x(x1), self.k_of_x(x0)
            cells_i = self.irange(ia, ib)
            role = h.get('role', 'glass')
            band_regions.append(dict(i=cells_i, ia=ia, ib=ib, k=(k_lo, k_hi), role=role))
            for i in cells_i:
                for k in range(k_lo, k_hi):
                    cell_role[(i, k)] = (hid, role)
        # ---- side panel CDT
        hole_pts = []
        for h in side_holes:
            pts = [Vector((p[0], p[1])) for p in h['pts']]
            if h.get('fillet', 0.0) > 0:
                pts = fillet_poly(pts, h['fillet'], n=h.get('fillet_n', 3))
            pts = densify(pts, h.get('max_len', 0.25))
            if poly_area(pts) < 0:
                pts.reverse()
            hole_pts.append(pts)
        ov, of, vmap, tri_hole, polys = self.side_cdt(hole_pts, side_res)
        sh.side = (ov, of, vmap, tri_hole)
        # ---- outer shell bmesh
        bm = bmesh.new()
        V = [[bm.verts.new(p) for p in ring] for ring in rings]
        extra_key = {}           # face centre (rounded) -> non-BODY key
        win_faces = []           # (centre, role)

        def tag(f, key, role=None):
            c = f.calc_center_median()
            if key in midx:
                f.material_index = midx[key]
            else:
                f.material_index = midx['Paint']
                extra_key[(round(c.x, 4), round(c.y, 4), round(c.z, 4))] = key
            if role in ('glass', 'open'):
                win_faces.append((c.copy(), role))

        for i in range(M):
            i2 = (i + 1) % M
            for k in range(K - 1):
                f = bm.faces.new((V[i][k], V[i][k + 1], V[i2][k + 1], V[i2][k]))
                hid_role = cell_role.get((i, k))
                n = _unit(self.normal3(i, k) + self.normal3(i, k + 1) + self.normal3(i2, k) + self.normal3(i2, k + 1))
                role = hid_role[1] if hid_role else None
                key = black_mat if role == 'black' else mat_fn(f.calc_center_median(), n, 'band')
                tag(f, key, role)
        for s in (1, -1):
            sv = {}
            for k, co in enumerate(ov):
                if vmap[k] is not None:
                    sv[k] = V[vmap[k]][0 if s > 0 else K - 1]
                else:
                    sv[k] = bm.verts.new((s * self.hw, co.x, co.y))
            for t, f2 in enumerate(of):
                try:
                    f = bm.faces.new([sv[k] for k in f2])
                except ValueError:
                    continue
                hid = tri_hole[t]
                role = None
                if hid >= 0:
                    hs = side_holes[hid].get('side', 0)
                    if hs == 0 or hs == s:
                        role = side_holes[hid].get('role', 'glass')
                key = black_mat if role == 'black' else mat_fn(f.calc_center_median(), Vector((s, 0, 0)), 'side')
                tag(f, key, role)
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        vol = sum(f.calc_center_median().dot(f.normal) * f.calc_area() for f in bm.faces)
        if vol < 0:
            for f in bm.faces:
                f.normal_flip()
        # ---- wheel arches
        if arches:
            bm = _boolean_arches(car, bm, arches, midx['Underbody'], solver)
            if lip > 0:
                _bevel_arch_lips(bm, arches, midx, lip, lip_segments)
        bm.normal_update()
        sh.surface = Surface(bm)
        # ---- windows + extra material keys (faces untouched by the boolean keep their exact centres)
        dead = []
        if win_faces:
            kd = KDTree(len(win_faces))
            for j, (c, role) in enumerate(win_faces):
                kd.insert(c, j)
            kd.balance()
            for f in bm.faces:
                co, j, dist = kd.find(f.calc_center_median())
                if dist is not None and dist < 2e-4:
                    dead.append(f)
        bmesh.ops.delete(bm, geom=dead, context='FACES')

        def key_of(f):
            c = f.calc_center_median()
            return extra_key.get((round(c.x, 4), round(c.y, 4), round(c.z, 4)))
        sh.part = bm_to_part(bm, BODY_MATS, key_of)
        sh.bm = bm
        # ---- reveals + glass
        d = lining.get('d', reveal_depth) if lining else reveal_depth
        inner_rings = [self.ring(i, d) for i in range(M)]
        reveals = Part()
        glass = Part()
        holes3d = []
        for hid, h in enumerate(side_holes):
            role = h.get('role', 'glass')
            pts = polys[hid]
            cen2 = sum(pts, Vector((0.0, 0.0))) / len(pts)
            for s in ((1, -1) if h.get('side', 0) == 0 else (h['side'],)):
                outer = [Vector((s * self.hw, p.x, p.y)) for p in pts]
                holes3d.append(dict(side=s, pts=outer, role=role, index=hid))
                if role in ('glass', 'open'):
                    for j in range(len(pts)):
                        j2 = (j + 1) % len(pts)
                        a0, a1 = outer[j], outer[j2]
                        b0 = Vector((s * (self.hw - d), a0.y, a0.z))
                        b1 = Vector((s * (self.hw - d), a1.y, a1.z))
                        q = Part()
                        q.face((q.vert(a0), q.vert(a1), q.vert(b1), q.vert(b0)), reveal_mat)
                        mid = (a0 + a1 + b0 + b1) / 4
                        ref = Vector((mid.x, cen2.x, cen2.y))
                        if q.face_normal(0).dot(ref - mid) < 0:
                            q.f[0] = tuple(reversed(q.f[0]))
                        reveals.extend(q)
                if role in ('glass', 'black'):
                    xg = s * (self.hw - glass_inset if role == 'glass' else self.hw + 0.0015)
                    cdt = geometry.delaunay_2d_cdt(pts, [], [list(range(len(pts)))], 1, 1e-7)
                    gp = Part()
                    vids = [gp.vert((xg, co.x, co.y)) for co in cdt[0]]
                    for f2 in cdt[2]:
                        gp.face([vids[k] for k in f2], 'Glass')
                        if gp.face_normal(len(gp.f) - 1).x * s < 0:
                            gp.f[-1] = tuple(reversed(gp.f[-1]))
                    glass.extend(gp)
        for reg in band_regions:
            k_lo, k_hi = reg['k']
            role = reg['role']
            cells = reg['i']
            allv = [rings[i][k] for i in cells + [reg['ib']] for k in range(k_lo, k_hi + 1)]
            cen = sum(allv, Vector()) / len(allv)
            holes3d.append(dict(region=reg, role=role))
            if role in ('glass', 'open'):
                edges = []
                for k in range(k_lo, k_hi):
                    edges.append(((reg['ia'], k), (reg['ia'], k + 1)))
                    edges.append(((reg['ib'], k), (reg['ib'], k + 1)))
                for i in cells:
                    i2 = (i + 1) % M
                    edges.append(((i, k_lo), (i2, k_lo)))
                    edges.append(((i, k_hi), (i2, k_hi)))
                for (ia_, ka_), (ib_, kb_) in edges:
                    a0, a1 = rings[ia_][ka_], rings[ib_][kb_]
                    b0, b1 = inner_rings[ia_][ka_], inner_rings[ib_][kb_]
                    q = Part()
                    q.face((q.vert(a0), q.vert(a1), q.vert(b1), q.vert(b0)), reveal_mat)
                    mid = (a0 + a1 + b0 + b1) / 4
                    if q.face_normal(0).dot(cen - mid) < 0:
                        q.f[0] = tuple(reversed(q.f[0]))
                    reveals.extend(q)
            if role in ('glass', 'black'):
                off = -glass_inset if role == 'glass' else 0.0015
                gp = Part()
                gv = {}
                for i in cells + [reg['ib']]:
                    for k in range(k_lo, k_hi + 1):
                        gv[(i, k)] = gp.vert(rings[i][k] + self.normal3(i, k) * off)
                for i in cells:
                    i2 = (i + 1) % M
                    for k in range(k_lo, k_hi):
                        gp.face((gv[(i, k)], gv[(i, k + 1)], gv[(i2, k + 1)], gv[(i2, k)]), 'Glass')
                        n = self.normal3(i, k) + self.normal3(i2, k + 1)
                        if gp.face_normal(len(gp.f) - 1).dot(n) < 0:
                            gp.f[-1] = tuple(reversed(gp.f[-1]))
                glass.extend(gp)
        sh.reveals = reveals
        sh.glass = glass
        sh.holes = holes3d
        sh.rings = rings
        sh.inner_rings = inner_rings
        # ---- lining (inner cabin skin)
        sh.lining = Part()
        if lining:
            sh.lining = self._lining(lining, d, inner_rings, cell_role, side_holes, ov, of, vmap, tri_hole)
        return sh

    def _lining(self, lining, d, inner_rings, cell_role, side_holes, ov, of, vmap, tri_hole):
        M, K = self.M, self.K
        lb = bmesh.new()
        LV = [[lb.verts.new(p) for p in ring] for ring in inner_rings]
        for i in range(M):
            i2 = (i + 1) % M
            for k in range(K - 1):
                hr = cell_role.get((i, k))
                if hr and hr[1] in ('glass', 'open'):
                    continue
                lb.faces.new((LV[i][k], LV[i][k + 1], LV[i2][k + 1], LV[i2][k]))
        for s in (1, -1):
            sv = {}
            for k, co in enumerate(ov):
                if vmap[k] is not None:
                    sv[k] = LV[vmap[k]][0 if s > 0 else K - 1]
                else:
                    sv[k] = lb.verts.new((s * (self.hw - d), co.x, co.y))
            for t, f2 in enumerate(of):
                hid = tri_hole[t]
                if hid >= 0:
                    hs = side_holes[hid].get('side', 0)
                    if (hs == 0 or hs == s) and side_holes[hid].get('role', 'glass') in ('glass', 'open'):
                        continue
                try:
                    lb.faces.new([sv[k] for k in f2])
                except ValueError:
                    pass
        bmesh.ops.remove_doubles(lb, verts=lb.verts[:], dist=1e-6)
        planes = []
        if 'y' in lining:
            y0, y1 = lining['y']
            planes += [((0.0, y0, 0.0), (0.0, -1.0, 0.0)), ((0.0, y1, 0.0), (0.0, 1.0, 0.0))]
        if 'z' in lining:
            z0, z1 = lining['z']
            planes += [((0.0, 0.0, z0), (0.0, 0.0, -1.0)), ((0.0, 0.0, z1), (0.0, 0.0, 1.0))]
        for (co2, no2) in lining.get('planes', []):
            planes.append(((0.0, co2[0], co2[1]), (0.0, no2[0], no2[1])))
        fill_faces = set()
        for co, no in planes:
            co, no = Vector(co), _unit(Vector(no))
            geom = lb.verts[:] + lb.edges[:] + lb.faces[:]
            bmesh.ops.bisect_plane(lb, geom=geom, dist=1e-6, plane_co=co, plane_no=no, clear_outer=True,
                                   clear_inner=False)
            edges = [e for e in lb.edges if e.is_boundary and all(abs((v.co - co).dot(no)) < 1e-5 for v in e.verts)]
            if edges:
                res = bmesh.ops.triangle_fill(lb, use_beauty=True, use_dissolve=False, edges=edges, normal=no)
                for g in res['geom']:
                    if isinstance(g, bmesh.types.BMFace):
                        fill_faces.add(g)
        fill_faces = {f for f in fill_faces if f.is_valid}
        lb.normal_update()
        bmesh.ops.recalc_face_normals(lb, faces=lb.faces[:])
        vol = sum(f.calc_center_median().dot(f.normal) * f.calc_area() for f in lb.faces)
        if vol > 0:                     # make it face inward (seen from inside the cabin)
            for f in lb.faces:
                f.normal_flip()
        lb.normal_update()
        mats = dict(floor='InteriorDark', roof='Interior', wall='Interior', fill='InteriorDark')
        mats.update(lining.get('mats', {}))

        def key_of(f):
            n = f.normal
            if n.z > 0.7:
                return mats['floor']
            if n.z < -0.7:
                return mats['roof']
            if f in fill_faces:
                return mats['fill']
            return mats['wall']
        part = bm_to_part(lb, ['Interior'], key_of)
        lb.free()
        return part


def dual_wheel(spec, gap=0.03):
    """Rear dual-tyre wheel (RIGHT side, rim face +X): two build_wheel(**spec) tyres side by side, centred on the
    axle origin (spec W = single tyre width). Returns (wheel_part, caliper_part)."""
    W = spec.get('W', 0.225)
    off = (W + gap) / 2.0
    outer, cal = build_wheel(**spec)
    inner, _ = build_wheel(**spec)
    return Part().extend(outer.translated((off, 0, 0)), inner.translated((-off, 0, 0))), cal.translated((-off, 0, 0))


def add_axle(car, key, wheel, cal, y, half_track, z):
    """Wheel_<key>R / Wheel_<key>L (+ Caliper_* when cal is given) from a RIGHT-side wheel Part, origin at the axle
    centre (y, +-half_track, z); the left wheel is geometry-mirrored. key: 'F', 'R' (or 'R2' for extra wheels)."""
    out = {}
    for side, sk in ((1, 'R'), (-1, 'L')):
        loc = Vector((side * half_track, y, z))
        car.add('Wheel_%s%s' % (key, sk), wheel if side > 0 else wheel.mirrored_x(), location=loc)
        if cal is not None:
            car.add('Caliper_%s%s' % (key, sk), cal if side > 0 else cal.mirrored_x(), location=loc)
        out[key + sk] = loc
    car.info.setdefault('wheels', {}).update(out)
    return out


def weighted_normals(ob, weight=50, mode='FACE_AREA', keep_sharp=True, thresh=0.01):
    """Face-area weighted normals (big flat panels stay flat next to rounded edge strips). Applied on export."""
    m = ob.modifiers.get('WeightedNormal') or ob.modifiers.new('WeightedNormal', 'WEIGHTED_NORMAL')
    modes = [e.identifier for e in m.bl_rna.properties['mode'].enum_items]
    m.mode = mode if mode in modes else modes[0]
    m.weight = weight
    m.keep_sharp = keep_sharp
    m.thresh = thresh
    return m


def simple_seat(x, y_front, y_back, z_base, width=0.50, back_h=0.60, recline=14.0, cushion_h=0.12, thick=0.11,
                headrest=True, mat='Interior', side_mat='InteriorDark', r=0.035, n=2):
    """Low-poly seat (traffic vehicles, ~200 tris): rounded cushion, reclined backrest, optional headrest.
    Faces +Y; z_base = underside of the cushion; the backrest pivots at the cushion's rear edge."""
    part = Part()
    part.extend(rbox('y', y_back, y_front, (x, z_base + cushion_h / 2), width, cushion_h, r, mat, n=n))
    M = Matrix.Translation((0.0, y_back + thick / 2, z_base + cushion_h * 0.5)) @ \
        Matrix.Rotation(math.radians(recline), 4, 'X')
    part.extend(rbox('z', 0.0, back_h, (x, 0.0), width * 0.96, thick, r, mat, n=n).transformed(M))
    if headrest:
        part.extend(rbox('z', back_h + 0.03, back_h + 0.20, (x, 0.0), min(0.27, width * 0.6), thick * 0.75, 0.03,
                         side_mat, n=n).transformed(M))
        for dx in (-0.06, 0.06):
            part.extend(rod(M @ Vector((x + dx, 0.0, back_h - 0.02)), M @ Vector((x + dx, 0.0, back_h + 0.05)),
                            0.006, side_mat, n=6))
    return part


def keep_outer_faces(part, r_min):
    """Copy of a wheel Part with only the faces whose vertices all lie at radius >= r_min from the X axis (tyre + rim
    barrel). Used for the inner tyre of a dual pair, whose disc / hub / nuts hide behind the outer wheel."""
    out = Part()
    remap = {}
    for f, m in zip(part.f, part.m):
        if min(math.hypot(part.v[i].y, part.v[i].z) for i in f) < r_min:
            continue
        idx = []
        for i in f:
            if i not in remap:
                remap[i] = out.vert(part.v[i])
            idx.append(remap[i])
        out.face(idx, m)
    return out
