extends RefCounted
## Procedural pictograms for maps and HUD: POI kinds, activity kinds, waypoint pin and player arrow.
## Glyphs are defined in a unit box (-1..1, y down) and drawn into any CanvasItem.

const Style := preload("res://scripts/ui/ui_style.gd")

const KIND_COLORS := {
	"hub": Color(1.0, 0.6, 0.16), "village": Color(0.47, 0.72, 1.0), "hamlet": Color(0.47, 0.72, 1.0),
	"farm": Color(0.56, 0.82, 0.36), "diner": Color(1.0, 0.45, 0.42), "gas": Color(1.0, 0.82, 0.3),
	"landmark": Color(0.33, 0.86, 0.8), "viewpoint": Color(0.72, 0.58, 1.0), "castle": Color(0.78, 0.75, 0.7),
	"harbour": Color(0.38, 0.66, 1.0), "lighthouse": Color(0.96, 0.96, 0.96), "road": Color(0.85, 0.87, 0.92),
	"speed_trap": Color(1.0, 0.56, 0.16), "speed_zone": Color(1.0, 0.7, 0.2), "drift": Color(0.93, 0.25, 0.53),
	"jump": Color(1.0, 0.45, 0.2), "race": Color(0.93, 0.25, 0.53), "time_trial": Color(0.8, 0.35, 0.95),
	"collectible": Color(1.0, 0.82, 0.3),
}
const KIND_NAMES := {
	"hub": "Festival hub", "village": "Village", "hamlet": "Hamlet", "farm": "Farm", "diner": "Diner",
	"gas": "Fuel station", "landmark": "Landmark", "viewpoint": "Viewpoint", "castle": "Ruins", "harbour": "Harbour",
	"lighthouse": "Lighthouse", "road": "Road start", "speed_trap": "Speed trap", "speed_zone": "Speed zone",
	"drift": "Drift zone", "jump": "Danger sign", "race": "Road race", "time_trial": "Time trial",
	"collectible": "Festival flag",
}


static func color_for(kind: String) -> Color:
	return KIND_COLORS.get(kind, Style.ACCENT)


static func name_for(kind: String) -> String:
	return KIND_NAMES.get(kind, kind.capitalize())


## Round badge with a pictogram. r = badge radius in pixels.
static func draw_badge(ci: CanvasItem, kind: String, c: Vector2, r: float, alpha := 1.0, highlight := false) -> void:
	var col := color_for(kind)
	col.a = alpha
	ci.draw_circle(c + Vector2(0, r * 0.14), r * 1.1, Color(0, 0, 0, 0.35 * alpha), true, -1.0, true)
	if highlight:
		ci.draw_circle(c, r * 1.42, Color(col.r, col.g, col.b, 0.28 * alpha), true, -1.0, true)
		ci.draw_arc(c, r * 1.42, 0.0, TAU, 32, Color(1, 1, 1, 0.9 * alpha), 2.0, true)
	ci.draw_circle(c, r, Color(0.07, 0.08, 0.12, 0.95 * alpha), true, -1.0, true)
	ci.draw_circle(c, r * 0.8, col, true, -1.0, true)
	draw_glyph(ci, kind, c, r * 0.52, Color(Style.INK.r, Style.INK.g, Style.INK.b, alpha), col)


static func _poly(c: Vector2, s: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(c + p * s)
	return out


static func draw_glyph(ci: CanvasItem, kind: String, c: Vector2, s: float, ink: Color, bg: Color) -> void:
	var lw := maxf(s * 0.2, 1.4)
	match kind:
		"hub":
			var star := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				var rr := 1.0 if i % 2 == 0 else 0.45
				star.append(c + Vector2(cos(a), sin(a)) * rr * s * 1.05)
			ci.draw_colored_polygon(star, ink)
		"village", "hamlet":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.8, 0.85), Vector2(0.8, 0.85), Vector2(0.8, -0.1), Vector2(0, -0.85), Vector2(-0.8, -0.1)]), ink)
			ci.draw_rect(Rect2(c + Vector2(-0.2, 0.25) * s, Vector2(0.4, 0.6) * s), bg)
		"farm":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.85, 0.85), Vector2(0.85, 0.85), Vector2(0.85, -0.2), Vector2(0.45, -0.75), Vector2(-0.45, -0.75), Vector2(-0.85, -0.2)]), ink)
			ci.draw_line(c + Vector2(-0.4, 0.15) * s, c + Vector2(0.4, 0.75) * s, bg, lw * 0.6, true)
			ci.draw_line(c + Vector2(0.4, 0.15) * s, c + Vector2(-0.4, 0.75) * s, bg, lw * 0.6, true)
		"diner":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.75, -0.35), Vector2(0.4, -0.35), Vector2(0.3, 0.75), Vector2(-0.65, 0.75)]), ink)
			ci.draw_arc(c + Vector2(0.45, 0.1) * s, s * 0.3, -PI * 0.5, PI * 0.5, 10, ink, lw * 0.8, true)
			ci.draw_line(c + Vector2(-0.35, -0.95) * s, c + Vector2(-0.35, -0.55) * s, ink, lw * 0.6, true)
			ci.draw_line(c + Vector2(0.0, -0.95) * s, c + Vector2(0.0, -0.55) * s, ink, lw * 0.6, true)
		"gas":
			var drop := PackedVector2Array([c + Vector2(0, -0.95) * s])
			for i in 13:
				var a := deg_to_rad(-30.0 + i * 20.0)
				drop.append(c + (Vector2(0, 0.25) + Vector2(cos(a), sin(a)) * 0.62) * s)
			ci.draw_colored_polygon(drop, ink)
		"landmark":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(0, -0.95), Vector2(0.72, 0), Vector2(0, 0.95), Vector2(-0.72, 0)]), ink)
			ci.draw_circle(c, s * 0.24, bg, true, -1.0, true)
		"viewpoint":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.95, 0.75), Vector2(-0.3, -0.55), Vector2(0.05, 0.05), Vector2(0.4, -0.35), Vector2(0.95, 0.75)]), ink)
		"castle":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.7, 0.85), Vector2(0.7, 0.85), Vector2(0.7, -0.55), Vector2(0.42, -0.55), Vector2(0.42, -0.85),
				Vector2(0.14, -0.85), Vector2(0.14, -0.55), Vector2(-0.14, -0.55), Vector2(-0.14, -0.85), Vector2(-0.42, -0.85),
				Vector2(-0.42, -0.55), Vector2(-0.7, -0.55)]), ink)
			ci.draw_rect(Rect2(c + Vector2(-0.18, 0.3) * s, Vector2(0.36, 0.55) * s), bg)
		"harbour":
			ci.draw_line(c + Vector2(0, -0.55) * s, c + Vector2(0, 0.8) * s, ink, lw, true)
			ci.draw_line(c + Vector2(-0.45, -0.25) * s, c + Vector2(0.45, -0.25) * s, ink, lw, true)
			ci.draw_arc(c + Vector2(0, -0.75) * s, s * 0.2, 0.0, TAU, 12, ink, lw * 0.8, true)
			ci.draw_arc(c + Vector2(0, 0.1) * s, s * 0.7, deg_to_rad(15.0), deg_to_rad(165.0), 14, ink, lw, true)
		"lighthouse":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.38, 0.9), Vector2(0.38, 0.9), Vector2(0.22, -0.35), Vector2(-0.22, -0.35)]), ink)
			ci.draw_rect(Rect2(c + Vector2(-0.26, -0.8) * s, Vector2(0.52, 0.35) * s), ink)
			ci.draw_line(c + Vector2(0.35, -0.65) * s, c + Vector2(0.95, -0.85) * s, ink, lw * 0.6, true)
			ci.draw_line(c + Vector2(-0.35, -0.65) * s, c + Vector2(-0.95, -0.85) * s, ink, lw * 0.6, true)
		"road":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(0, -0.9), Vector2(0.75, 0.65), Vector2(0, 0.3), Vector2(-0.75, 0.65)]), ink)
		"speed_trap":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.85, -0.4), Vector2(-0.35, -0.4), Vector2(-0.25, -0.7), Vector2(0.25, -0.7),
				Vector2(0.35, -0.4), Vector2(0.85, -0.4), Vector2(0.85, 0.7), Vector2(-0.85, 0.7)]), ink)
			ci.draw_circle(c + Vector2(0, 0.12) * s, s * 0.38, bg, true, -1.0, true)
			ci.draw_circle(c + Vector2(0, 0.12) * s, s * 0.18, ink, true, -1.0, true)
		"speed_zone":
			ci.draw_arc(c + Vector2(0, 0.25) * s, s * 0.78, deg_to_rad(195.0), deg_to_rad(345.0), 16, ink, lw, true)
			ci.draw_line(c + Vector2(0, 0.25) * s, c + Vector2(0.5, -0.3) * s, ink, lw, true)
			ci.draw_circle(c + Vector2(0, 0.25) * s, s * 0.2, ink, true, -1.0, true)
		"drift":
			var pts := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				pts.append(c + Vector2(sin(t * TAU) * 0.5, 0.85 - t * 1.5) * s)
			ci.draw_polyline(pts, ink, lw, true)
			ci.draw_colored_polygon(_poly(c, s, [Vector2(0, -0.95), Vector2(0.38, -0.5), Vector2(-0.38, -0.5)]), ink)
		"jump":
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.9, 0.75), Vector2(0.15, 0.75), Vector2(0.15, 0.05)]), ink)
			ci.draw_arc(c + Vector2(0.55, 0.15) * s, s * 0.45, deg_to_rad(200.0), deg_to_rad(340.0), 10, ink, lw * 0.8, true)
			ci.draw_circle(c + Vector2(0.9, 0.55) * s, s * 0.14, ink, true, -1.0, true)
		"race":
			ci.draw_line(c + Vector2(-0.65, -0.9) * s, c + Vector2(-0.65, 0.9) * s, ink, lw * 0.8, true)
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.85) * s, Vector2(1.45, 0.9) * s), ink)
			for i in 4:
				for j in 2:
					if (i + j) % 2 == 0:
						ci.draw_rect(Rect2(c + Vector2(-0.6 + i * 0.3625, -0.85 + j * 0.45) * s, Vector2(0.3625, 0.45) * s), bg)
		"time_trial":
			ci.draw_arc(c + Vector2(0, 0.15) * s, s * 0.66, 0.0, TAU, 20, ink, lw, true)
			ci.draw_rect(Rect2(c + Vector2(-0.16, -0.95) * s, Vector2(0.32, 0.3) * s), ink)
			ci.draw_line(c + Vector2(0, 0.15) * s, c + Vector2(0.28, -0.22) * s, ink, lw * 0.8, true)
		"collectible":
			ci.draw_line(c + Vector2(-0.5, -0.9) * s, c + Vector2(-0.5, 0.9) * s, ink, lw * 0.8, true)
			ci.draw_colored_polygon(_poly(c, s, [Vector2(-0.45, -0.9), Vector2(0.85, -0.5), Vector2(-0.45, -0.1)]), ink)
		_:
			ci.draw_circle(c, s * 0.45, ink, true, -1.0, true)


## Map pin whose tip sits at `tip`. s = pin head radius.
static func draw_pin(ci: CanvasItem, tip: Vector2, s: float, col := Style.ROUTE, alpha := 1.0) -> void:
	var head := tip + Vector2(0, -s * 2.0)
	col.a = alpha
	ci.draw_circle(tip, s * 0.45, Color(0, 0, 0, 0.35 * alpha), true, -1.0, true)
	var body := PackedVector2Array([tip])
	var inner := PackedVector2Array([tip + Vector2(0, -s * 0.3)])
	for i in 15:
		var a := deg_to_rad(150.0 + i * (240.0 / 14.0))
		body.append(head + Vector2(cos(a), sin(a)) * s)
		inner.append(head + Vector2(cos(a), sin(a)) * s * 0.78)
	ci.draw_colored_polygon(body, Color(0.06, 0.07, 0.1, 0.9 * alpha))
	ci.draw_colored_polygon(inner, col)
	ci.draw_circle(head, s * 0.34, Color(1, 1, 1, alpha), true, -1.0, true)


## Player arrow pointing along `angle` (0 = up). s = half length.
static func draw_player_arrow(ci: CanvasItem, c: Vector2, angle: float, s: float, alpha := 1.0) -> void:
	var pts: Array[Vector2] = [Vector2(0, -1.0), Vector2(0.74, 0.8), Vector2(0, 0.42), Vector2(-0.74, 0.8)]
	var poly := PackedVector2Array()
	var outline := PackedVector2Array()
	for p in pts:
		poly.append(c + p.rotated(angle) * s)
		outline.append(c + (p * 1.28 + Vector2(0, 0.04)).rotated(angle) * s)
	ci.draw_circle(c, s * 1.55, Color(Style.ACCENT.r, Style.ACCENT.g, Style.ACCENT.b, 0.22 * alpha), true, -1.0, true)
	ci.draw_colored_polygon(outline, Color(0.05, 0.05, 0.08, 0.9 * alpha))
	ci.draw_colored_polygon(poly, Color(1, 1, 1, alpha))
	var tipc := PackedVector2Array([poly[0], c + Vector2(0.37, -0.1).rotated(angle) * s, c + Vector2(-0.37, -0.1).rotated(angle) * s])
	ci.draw_colored_polygon(tipc, Color(Style.ACCENT.r, Style.ACCENT.g, Style.ACCENT.b, alpha))
