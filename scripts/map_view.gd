class_name MapView
extends Control
## The map and objective log (owned by HUD, opened with the map key over a paused game). Right: the whole city, north up, drawn from City
## (streets, building footprints, the park, the courtyard, the border ring), the places the player knows by name, the player as an arrow,
## the objective as a pulsing triangle and the walking route to it (one City.path when the map opens). No soldiers. Inside the home, the
## cellar or the lander a note says where you are. Left: STORY SO FAR (the recap of the part you are in), the current objective and the
## finished ones of this chapter.

const ACCENT := Color(0.2, 0.85, 0.8)
const INK := Color(0.9, 0.95, 0.95)
const DIM := Color(0.55, 0.62, 0.64)
const LOG_W := 380.0
const MARGIN := 30.0

var player: Player
var _route := PackedVector3Array()
var _target: Variant = null
var _note := ""
var _log: VBoxContainer
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var side := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.96)
	sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
	sb.border_width_right = 2
	sb.set_content_margin_all(22)
	side.add_theme_stylebox_override("panel", sb)
	side.position = Vector2.ZERO
	side.custom_minimum_size = Vector2(LOG_W, 0)
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_right = LOG_W
	add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 6)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)


func _lbl(text: String, size: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(LOG_W - 50.0, 0)
	_log.add_child(l)
	return l


## Called by HUD each time the map opens: the log, the route, the note.
func open(p: Player) -> void:
	player = p
	_t = 0.0
	for c in _log.get_children():
		c.queue_free()
	var ms := Game.mission
	_lbl("%s  -  %s" % [StoryPlaces.CHAPTER, StoryPlaces.CHAPTER_TITLE], 14, Color(0.9, 0.3, 0.25), true)
	if ms != null and ms.id != "sandbox":
		var place := StoryPlaces.recap_at(ms.index)
		_lbl(String(place.get("section", "")), 20, INK, true)
		_lbl("STORY SO FAR", 13, ACCENT)
		_lbl(String(place.get("recap", "")), 15, Color(0.8, 0.85, 0.85), true)
	_lbl("", 6, DIM)
	_lbl("OBJECTIVE", 13, ACCENT)
	var o := ms.active() if ms != null else {}
	_lbl(String(o.get("text", "NONE")) if not o.is_empty() else ("CHAPTER COMPLETE" if ms != null and ms.finished else "NONE"), 19, Color(0.95, 0.8, 0.35), true)
	if ms != null and ms.index > 0:
		_lbl("", 6, DIM)
		_lbl("DONE", 13, ACCENT)
		for i in range(mini(ms.index, ms.objectives.size()) - 1, -1, -1):
			_lbl("+  " + String(ms.objectives[i]["text"]), 14, DIM, true)
	_lbl("", 8, DIM)
	_lbl("%s or Esc - back to the game" % Settings.key_name("map"), 13, DIM)
	# the map side
	_target = ms.marker_pos() if ms != null else null
	_note = ""
	var pp := p.global_position
	var main := get_tree().current_scene
	var ship_inside: bool = main != null and main.get("ship") != null and main.ship.inside
	if ship_inside:
		_note = "INSIDE THE LANDER"
	elif pp.y < -1.0 and City.CELLAR_RECT.grow(1.0).has_point(Vector2(pp.x, pp.z)):
		_note = "IN THE CELLAR"
	elif City.HOME_RECT.has_point(Vector2(pp.x, pp.z)):
		_note = "AT HOME"
	_route = PackedVector3Array()
	if _target != null and not ship_inside:
		_route = City.path(pp, _target)
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


## World (x, z) -> screen, north (-z) up, the whole map fitted into the area right of the log.
func _xf() -> Array:
	var area := Rect2(LOG_W + MARGIN, MARGIN, size.x - LOG_W - MARGIN * 2.0, size.y - MARGIN * 2.0)
	var s := minf(area.size.x / (City.OUT_X * 2.0), area.size.y / (City.OUT_Z * 2.0))
	var origin := area.position + area.size * 0.5
	return [origin, s]


func _to(p: Vector2, xf: Array) -> Vector2:
	return (xf[0] as Vector2) + p * float(xf[1])


func _rect(r: Rect2, xf: Array) -> Rect2:
	return Rect2(_to(r.position, xf), r.size * float(xf[1]))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.97))
	var xf := _xf()
	var font := ThemeDB.fallback_font
	draw_rect(_rect(Rect2(-City.OUT_X, -City.OUT_Z, City.OUT_X * 2.0, City.OUT_Z * 2.0), xf), Color(0.07, 0.08, 0.075))
	for st in City.streets:
		var cls := String(st["cls"])
		var col := Color(0.2, 0.21, 0.22) if cls == "avenue" else (Color(0.17, 0.18, 0.19) if cls in ["street", "plaza"] else Color(0.14, 0.15, 0.155))
		draw_rect(_rect(st["rect"], xf), col)
	draw_rect(_rect(City.PARK_RECT, xf), Color(0.12, 0.22, 0.13))
	draw_rect(_rect(City.COURT_RECT, xf), Color(0.16, 0.16, 0.15))
	for b in City.buildings:
		var border := bool(b.get("border", false))
		var c := Color(0.05, 0.055, 0.06) if border else Color(0.3, 0.32, 0.33).darkened(clampf(float(b.get("h", 10.0)) / 120.0, 0.0, 0.5))
		var r := _rect(b["rect"], xf)
		draw_rect(r, c)
		if not border:
			draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
	# the places the player knows
	var ms := Game.mission
	var idx := ms.index if ms != null else 0
	var main := get_tree().current_scene
	_place(_rect(City.INSTITUTE_RECT, xf), "THE INSTITUTE", font)
	_place(_rect(City.HOME_RECT, xf), "HOME", font)
	_place(_rect(City.PARK_RECT, xf), "THE PARK", font)
	if main != null and main.get("world") != null and main.world.lander != null and main.world.lander.landed:
		var lp := _to(Vector2(City.LANDER_POS.x, City.LANDER_POS.z), xf)
		draw_rect(Rect2(lp - Vector2(10, 5), Vector2(20, 10)), Color(0.75, 0.3, 0.25))
		draw_string(font, lp + Vector2(-26, -10), "THE LANDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.5, 0.4))
	if not CityStory.lookout.is_empty() and main != null and idx >= main._objective_index("climb_roof") and main._objective_index("climb_roof") >= 0:
		var fp: Vector3 = CityStory.lookout["foot"]
		draw_string(font, _to(Vector2(fp.x, fp.z), xf) + Vector2(6, 4), "LOOKOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	# the route and the objective
	if _route.size() > 1:
		var prev := _to(Vector2(_route[0].x, _route[0].z), xf)
		var acc := 0.0
		for i in range(1, _route.size()):
			var q := _to(Vector2(_route[i].x, _route[i].z), xf)
			acc += prev.distance_to(q)
			if int(acc / 5.0) % 2 == 0:
				draw_line(prev, q, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75), 2.0)
			prev = q
	var ship_inside: bool = main != null and main.get("ship") != null and main.ship.inside
	if _target != null and not ship_inside:
		var tp := _to(Vector2((_target as Vector3).x, (_target as Vector3).z), xf)
		var k := 1.0 + 0.25 * sin(_t * 5.0)
		draw_colored_polygon(PackedVector2Array([tp + Vector2(-7, -12) * k, tp + Vector2(7, -12) * k, tp]), Color(0.95, 0.8, 0.35))
		draw_arc(tp, 9.0 * k, 0.0, TAU, 20, Color(0.95, 0.8, 0.35, 0.6), 1.5)
	# the player
	if player != null:
		var at := Vector2(City.LANDER_POS.x, City.LANDER_POS.z) if ship_inside else Vector2(player.global_position.x, player.global_position.z)
		var pp := _to(at, xf)
		var fwd := Vector2(-sin(player.yaw), -cos(player.yaw))
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([pp + fwd * 11.0, pp - fwd * 6.0 + side * 6.0, pp - fwd * 3.0, pp - fwd * 6.0 - side * 6.0]), ACCENT)
		draw_polyline(PackedVector2Array([pp + fwd * 11.0, pp - fwd * 6.0 + side * 6.0, pp - fwd * 3.0, pp - fwd * 6.0 - side * 6.0, pp + fwd * 11.0]), Color(0, 0, 0, 0.8), 1.5)
		if _note != "":
			draw_string(font, pp + Vector2(14, -10), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)
	# north and the scale
	var mr := _rect(Rect2(-City.OUT_X, -City.OUT_Z, City.OUT_X * 2.0, City.OUT_Z * 2.0), xf)
	draw_string(font, mr.position + Vector2(mr.size.x + 8.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.45, 0.35))
	draw_line(mr.position + Vector2(mr.size.x + 14.0, 24.0), mr.position + Vector2(mr.size.x + 14.0, 50.0), Color(1.0, 0.45, 0.35), 2.0)
	var s100 := 100.0 * float(xf[1])
	var sb := mr.position + Vector2(10.0, mr.size.y - 12.0)
	draw_line(sb, sb + Vector2(s100, 0), INK, 2.0)
	draw_string(font, sb + Vector2(s100 + 6.0, 5.0), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)


func _place(r: Rect2, text: String, font: Font) -> void:
	draw_rect(r, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9), false, 2.0)
	draw_string(font, r.position + Vector2(r.size.x + 5.0, r.size.y * 0.5 + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
