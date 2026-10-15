class_name HUD
extends CanvasLayer
## Flat dark HUD: health blocks, ammo box, spread-aware crosshair, hit marker, damage vignette,
## death and pause screens. Keeps running while the tree is paused (process_mode ALWAYS).

const ACCENT := Color(0.2, 0.85, 0.8)
const PLATE := Color(0.05, 0.07, 0.08, 0.72)
const RED := Color(0.9, 0.25, 0.22)
const GOLD := Color(0.95, 0.8, 0.35)

var player: Player
var health_blocks: Array[ColorRect] = []
var health_label: Label
var ammo_big: Label
var ammo_small: Label
var weapon_name: Label
var reload_bar: ColorRect
var reload_bg: ColorRect
var kills_label: Label
var vignette: TextureRect
var hint: Label
var death_panel: Control
var death_stats: Label
var pause_panel: Control
var cross: _Cross
var health_plate: Panel
var ammo_plate: Panel
var hit_t := 0.0
var hit_kill := false
var hit_head := false
var hint_t := 14.0
var _last_health := -1.0


class _Cross extends Control:
	var spread_px := 8.0
	var hit_t := 0.0
	var hit_kill := false
	var hit_head := false
	var alpha := 1.0
	var show_dot := false

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1, 1, 1, 0.9 * alpha)
		var gap := spread_px
		var len := 9.0
		var w := 2.0
		if show_dot:
			draw_rect(Rect2(c.x - 1.5, c.y - 1.5, 3, 3), Color(1, 0.3, 0.25, 0.9))
		else:
			draw_rect(Rect2(c.x - w * 0.5, c.y - gap - len, w, len), col)
			draw_rect(Rect2(c.x - w * 0.5, c.y + gap, w, len), col)
			draw_rect(Rect2(c.x - gap - len, c.y - w * 0.5, len, w), col)
			draw_rect(Rect2(c.x + gap, c.y - w * 0.5, len, w), col)
		if hit_t > 0.0:
			var hc := Color(0.9, 0.2, 0.2, hit_t / 0.18) if hit_kill else (Color(1.0, 0.85, 0.3, hit_t / 0.18) if hit_head else Color(1, 1, 1, hit_t / 0.18))
			var a := 7.0
			var b := 15.0
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					draw_line(c + Vector2(sx * a, sy * a), c + Vector2(sx * b, sy * b), hc, 2.5)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10


func setup(p: Player) -> void:
	player = p
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# damage vignette
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.8, 0.0, 0.0, 0.75))
	grad.set_offset(0, 0.55)
	grad.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	vignette = TextureRect.new()
	vignette.texture = gt
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	root.add_child(vignette)

	cross = _Cross.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	# kills plate (top left)
	var kp := _plate(root, Vector2(16, 16), Vector2(150, 44))
	kills_label = _label(kp, "KILLS 0", 22, ACCENT)
	kills_label.position = Vector2(12, 7)

	# health (bottom left)
	health_plate = _plate(root, Vector2(16, 0), Vector2(290, 62))
	var hp := health_plate
	for i in 10:
		var b := ColorRect.new()
		b.size = Vector2(22, 14)
		b.position = Vector2(12 + i * 26, 38)
		b.color = ACCENT
		hp.add_child(b)
		health_blocks.append(b)
	health_label = _label(hp, "HEALTH 100", 18, Color.WHITE)
	health_label.position = Vector2(12, 6)

	# ammo box (bottom right)
	ammo_plate = _plate(root, Vector2(0, 0), Vector2(200, 112))
	var ap := ammo_plate
	weapon_name = _label(ap, "M9 PISTOL", 15, Color(0.75, 0.8, 0.8))
	weapon_name.position = Vector2(12, 6)
	ammo_big = _label(ap, "15", 52, Color.WHITE)
	ammo_big.position = Vector2(12, 24)
	ammo_small = _label(ap, "/ 60", 20, GOLD)
	ammo_small.position = Vector2(100, 56)
	reload_bg = ColorRect.new()
	reload_bg.color = Color(1, 1, 1, 0.12)
	reload_bg.size = Vector2(176, 5)
	reload_bg.position = Vector2(12, 98)
	reload_bg.visible = false
	ap.add_child(reload_bg)
	reload_bar = ColorRect.new()
	reload_bar.color = ACCENT
	reload_bar.size = Vector2(0, 5)
	reload_bg.add_child(reload_bar)

	# controls hint
	hint = _label(root, "WASD move   SHIFT sprint   CTRL crouch / slide   SPACE jump   LMB fire   RMB aim   R reload   1 / 2 / Q weapons   ESC pause", 15, Color(1, 1, 1, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size = Vector2(760, 44)

	# death screen
	death_panel = _overlay(root, Color(0.35, 0.0, 0.0, 0.55))
	var dt := _label(death_panel, "YOU DIED", 64, RED)
	dt.set_anchors_preset(Control.PRESET_CENTER)
	dt.position = Vector2(-200, -90)
	dt.size = Vector2(400, 80)
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_stats = _label(death_panel, "", 20, Color.WHITE)
	death_stats.set_anchors_preset(Control.PRESET_CENTER)
	death_stats.position = Vector2(-250, -5)
	death_stats.size = Vector2(500, 80)
	death_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_panel.visible = false

	# pause screen
	pause_panel = _overlay(root, Color(0, 0, 0, 0.55))
	var pt := _label(pause_panel, "PAUSED\nclick to resume", 36, ACCENT)
	pt.set_anchors_preset(Control.PRESET_CENTER)
	pt.position = Vector2(-200, -50)
	pt.size = Vector2(400, 100)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel.visible = false

	Game.player_died.connect(_on_died)
	player.weapons.hit_marker.connect(_on_hit_marker)


func _plate(parent: Control, pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE
	sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5)
	sb.border_width_left = 2
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _overlay(parent: Control, color: Color) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _on_hit_marker(head: bool, killed: bool) -> void:
	cross.hit_t = 0.18
	cross.hit_kill = killed
	cross.hit_head = head


func _on_died() -> void:
	death_stats.text = "Kills: %d\nShots: %d   Hits: %d   Accuracy: %d%%\n\nPress R to restart" % [
		Game.kills, Game.shots_fired, Game.shots_hit,
		int(100.0 * Game.shots_hit / maxf(1.0, Game.shots_fired))]
	death_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if Game.dead:
		if event.is_action_pressed("restart"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		return
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event is InputEventMouseButton and event.pressed:
		_set_paused(false)
		get_viewport().set_input_as_handled()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	Game.paused = p
	pause_panel.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	health_plate.position = Vector2(16, vs.y - 78)
	ammo_plate.position = Vector2(vs.x - 216, vs.y - 128)
	hint.position = Vector2(vs.x * 0.5 - 380, vs.y - 64)


func _process(delta: float) -> void:
	if player == null:
		return
	_layout()
	var w := player.weapons
	var s := w.stats()
	weapon_name.text = String(s["name"])
	ammo_big.text = str(w.ammo())
	ammo_big.add_theme_color_override("font_color", RED if w.ammo() <= int(int(s["mag"]) * 0.25) else Color.WHITE)
	ammo_small.text = "/ %d   (%d mags)" % [w.reserve(), w.spare_mags()]
	if w.reloading:
		reload_bg.visible = true
		reload_bar.size.x = 176.0 * clampf(w.reload_t / float(s["reload_time"]), 0.0, 1.0)
	else:
		reload_bg.visible = false

	if player.health != _last_health:
		_last_health = player.health
		health_label.text = "HEALTH %d" % int(ceil(player.health))
		var lit := int(ceil(player.health / 10.0))
		for i in 10:
			health_blocks[i].color = (ACCENT if player.health > 30.0 else RED) if i < lit else Color(1, 1, 1, 0.1)
	kills_label.text = "KILLS %d" % Game.kills
	vignette.modulate.a = clampf(player.hurt_k, 0.0, 1.0) + (0.5 if player.health < 25.0 and not Game.dead else 0.0) * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008))

	# crosshair opens with the weapon's real spread; hidden while aiming down sights
	var vp_h := get_viewport().get_visible_rect().size.y
	var fov_rad := deg_to_rad(player.camera.fov)
	var px := tan(deg_to_rad(w.current_spread())) / tan(fov_rad * 0.5) * vp_h * 0.5
	cross.spread_px = lerpf(cross.spread_px, 4.0 + px, 1.0 - exp(-25.0 * delta))
	cross.alpha = 1.0 - clampf(w.ads_k * 1.6, 0.0, 1.0)
	cross.show_dot = w.ads_k > 0.5
	cross.alpha = maxf(cross.alpha, 0.0)
	if cross.show_dot:
		cross.alpha = 0.9
		cross.spread_px = 0.0
	cross.hit_t = maxf(0.0, cross.hit_t - delta)
	cross.queue_redraw()

	if hint_t > 0.0 and not get_tree().paused:
		hint_t -= delta
		hint.modulate.a = clampf(hint_t / 2.0, 0.0, 1.0)
