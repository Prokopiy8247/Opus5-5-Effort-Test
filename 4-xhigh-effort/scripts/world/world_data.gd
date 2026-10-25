class_name WorldData
extends Resource
## Baked world (tools/world_bake.gd): heightmap, maps, road network, POIs, dressing placements.

const PATH := "res://world/generated/world_data.res"
## Exported builds cannot write res://; a world generated at runtime there is saved in user://.
const USER_PATH := "user://world_data.res"


## The baked world shipped with the game (or the editor's copy), else the one generated in user://.
static func resolve_path() -> String:
	return PATH if ResourceLoader.exists(PATH) else USER_PATH


## Where a freshly generated world is written.
static func save_path() -> String:
	return PATH if OS.has_feature("editor") else USER_PATH

@export var seed := 0
@export var half := 2048.0
@export var step := 2.0
@export var res := 2049
@export var heights := PackedFloat32Array()
## cell indices (row-major, res grid) whose vertices are holes (tunnel mouths)
@export var holes := PackedInt32Array()
## 1024x1024 (4 m): r desert, g mountain, b coast, a field/beach code
@export var control_img: Image
## 1024x1024 (4 m): r road verge wear, g forest floor, b sand, a wetland/riverbank
@export var detail_img: Image
## 1024x1024 stylised map (minimap / map screen)
@export var map_img: Image
## 1024x1024 (4 m) SurfaceData.Kind per cell
@export var surface := PackedByteArray()
## 1024x1024 (4 m) distance to nearest road edge in metres (clamped 0..255)
@export var road_dist := PackedByteArray()
## roads: {id, name, class, closed, width, lanes, lane_w, shoulder, median, speed, surface, scenic,
##   pts: PackedVector3Array (2 m samples, world, centre line on road surface), bank: PackedFloat32Array,
##   kind: PackedByteArray (0 ground, 1 bridge, 2 tunnel), length, junctions: Array[{s, other, other_s}]}
@export var roads: Array = []
@export var river := {}
@export var pois: Array = []
@export var buildings: Array = []
## per chunk key "cx,cz": PackedFloat32Array of [x, y, z, rot, scale, species] records
@export var trees := {}
@export var props: Array = []
@export var activities: Array = []
@export var regions: Array = []
@export var spawn := Transform3D.IDENTITY
@export var sea_level := 0.0
@export var stats := {}


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half) / step, 0.0, res - 1.001)
	var fz := clampf((z + half) / step, 0.0, res - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i0 := iz * res + ix
	var h00 := heights[i0]
	var h10 := heights[i0 + 1]
	var h01 := heights[i0 + res]
	var h11 := heights[i0 + res + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func cell4(x: float, z: float) -> int:
	var ix := clampi(int((x + half) / 4.0), 0, 1023)
	var iz := clampi(int((z + half) / 4.0), 0, 1023)
	return iz * 1024 + ix


func surface_at(x: float, z: float) -> int:
	return surface[cell4(x, z)]


func region_at(x: float, z: float) -> int:
	var c := control_img.get_pixel(clampi(int((x + half) / 4.0), 0, 1023), clampi(int((z + half) / 4.0), 0, 1023))
	var f := 1.0 - c.r - c.g - c.b
	var best := 0
	var bw := f
	if c.g > bw:
		best = 1
		bw = c.g
	if c.r > bw:
		best = 2
		bw = c.r
	if c.b > bw:
		best = 3
	return best
