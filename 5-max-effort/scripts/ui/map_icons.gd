class_name MapIcons
extends RefCounted
## Shared map helpers: world <-> map-image conversion and the marker icons used by the minimap
## and the world map (activities, festival boards, landmarks, waypoint, player arrow).

const MAP_PX := 2048.0
const COLORS := {
	"trap": Color(1.0, 0.82, 0.2), "zone": Color(1.0, 0.55, 0.15), "drift": Color(0.95, 0.3, 0.75),
	"jump": Color(1.0, 0.35, 0.25), "race": Color(0.25, 0.85, 1.0), "trial": Color(0.55, 1.0, 0.45),
	"board": Color(1.0, 0.9, 0.35), "landmark": Color(0.85, 0.88, 0.95), "festival": Color(1.0, 0.64, 0.12),
	"waypoint": Color(0.22, 0.86, 0.94),
}
const GLYPH := {"trap": "S", "zone": "Z", "drift": "D", "jump": "!", "race": "R", "trial": "T", "landmark": "•", "festival": "F"}


static func world_to_px(p: Vector3, half: float) -> Vector2:
	return Vector2((p.x + half) / (2.0 * half) * MAP_PX, (p.z + half) / (2.0 * half) * MAP_PX)


static func px_to_world(px: Vector2, half: float) -> Vector3:
	return Vector3(px.x / MAP_PX * 2.0 * half - half, 0.0, px.y / MAP_PX * 2.0 * half - half)


static func draw_icon(ci: CanvasItem, kind: String, at: Vector2, size: float, stars: int = 0) -> void:
	var col: Color = COLORS.get(kind, Color.WHITE)
	if kind == "board":
		var pts := PackedVector2Array([at + Vector2(0, -size * 0.55), at + Vector2(size * 0.4, 0), at + Vector2(0, size * 0.55),
			at + Vector2(-size * 0.4, 0)])
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.5)
		return
	ci.draw_circle(at, size * 0.62, Color(0.04, 0.05, 0.07, 0.85))
	ci.draw_circle(at, size * 0.5, col)
	var font := UiTheme.font(true)
	var fs := int(size * 0.7)
	var g: String = GLYPH.get(kind, "?")
	var w := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, at + Vector2(-w * 0.5, fs * 0.36), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.07))
	if stars > 0:
		for k in stars:
			ci.draw_circle(at + Vector2((k - 1) * size * 0.32, size * 0.78), size * 0.12, Color(1, 0.85, 0.25))


static func draw_arrow(ci: CanvasItem, at: Vector2, angle: float, size: float, col: Color = Color.WHITE) -> void:
	var r := Transform2D(angle, at)
	var pts := PackedVector2Array([r * Vector2(0, -size), r * Vector2(size * 0.62, size * 0.7), r * Vector2(0, size * 0.32),
		r * Vector2(-size * 0.62, size * 0.7)])
	ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(at + (p - at) * 0.78)
	ci.draw_colored_polygon(inner, col)


static func markers() -> Array:
	## everything both maps show: activities, unsmashed boards, landmarks, festival
	var out: Array = []
	if Game.activities != null and Game.activities.has_method("get_markers"):
		out.append_array(Game.activities.call("get_markers"))
	if Game.world != null and "data" in Game.world:
		var meta: Dictionary = (Game.world.get("data") as WorldData).meta
		for l in meta.get("landmarks", []):
			var p: Array = l["pos"]
			out.append({"pos": Vector3(float(p[0]), 0, float(p[1])), "kind": "landmark", "name": String(l["name"]), "stars": 0})
		var tp: Dictionary = meta.get("teleports", {})
		if tp.has("festival"):
			var f: Array = tp["festival"]
			out.append({"pos": Vector3(float(f[0]), 0, float(f[1])), "kind": "festival", "name": "Ridgeline Festival", "stars": 0})
	return out
