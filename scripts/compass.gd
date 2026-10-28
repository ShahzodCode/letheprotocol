class_name Compass
extends Control
## The compass strip under the objective text (owned by HUD): half the horizon (180 degrees) across WIDTH pixels, ticks every 15 degrees,
## N / NE / E ... letters, and a teal triangle at the bearing of the current objective (pinned to the edge with an arrow when it is behind).
## Settings.compass turns it off.

const WIDTH := 420.0
const SPAN := PI                       # radians shown across the strip
const ACCENT := Color(0.2, 0.85, 0.8)
## yaw-style angles (0 = north = -z, +PI/2 = west) of the letters
const LETTERS := [[0.0, "N"], [PI * 0.25, "NW"], [PI * 0.5, "W"], [PI * 0.75, "SW"], [PI, "S"], [-PI * 0.75, "SE"], [-PI * 0.5, "E"], [-PI * 0.25, "NE"]]

var yaw := 0.0
var target: Variant = null             # Vector3 of the objective, or null
var from := Vector3.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _x(a: float) -> float:
	return size.x * 0.5 - wrapf(a - yaw, -PI, PI) / SPAN * size.x


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x
	draw_rect(Rect2(0, 6, w, 20), Color(0.05, 0.07, 0.08, 0.55))
	for i in 24:
		var a := float(i) * PI / 12.0
		var rel := wrapf(a - yaw, -PI, PI)
		if absf(rel) > SPAN * 0.5:
			continue
		var x := _x(a)
		var fade := 1.0 - absf(rel) / (SPAN * 0.5)
		draw_line(Vector2(x, 20), Vector2(x, 26), Color(1, 1, 1, 0.35 * fade + 0.1), 1.0)
	for l in LETTERS:
		var rel2 := wrapf(float(l[0]) - yaw, -PI, PI)
		if absf(rel2) > SPAN * 0.5:
			continue
		var x2 := _x(float(l[0]))
		var fade2 := 1.0 - absf(rel2) / (SPAN * 0.5)
		var big := String(l[1]).length() == 1
		var fs := 15 if big else 11
		var tw := font.get_string_size(String(l[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := (Color(1.0, 0.45, 0.35) if l[1] == "N" else Color(0.92, 0.95, 0.95))
		col.a = 0.35 + 0.65 * fade2
		draw_string(font, Vector2(x2 - tw * 0.5, 20), String(l[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_line(Vector2(w * 0.5, 4), Vector2(w * 0.5, 9), Color(1, 1, 1, 0.8), 2.0)        # where you look
	if target == null:
		return
	var to: Vector3 = (target as Vector3) - from
	if Vector2(to.x, to.z).length() < 0.5:
		return
	var b := atan2(-to.x, -to.z)
	var rel3 := wrapf(b - yaw, -PI, PI)
	var y := 30.0
	if absf(rel3) <= SPAN * 0.5:
		var x3 := _x(b)
		draw_colored_polygon(PackedVector2Array([Vector2(x3 - 6, y + 2), Vector2(x3 + 6, y + 2), Vector2(x3, y - 6)]), ACCENT)
	else:
		var left := rel3 > 0.0          # behind and to the left: the arrow sits on the left edge
		var xe := 8.0 if left else w - 8.0
		var d := -1.0 if left else 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(xe + d * 6, 16), Vector2(xe - d * 4, 9), Vector2(xe - d * 4, 23)]), ACCENT)
