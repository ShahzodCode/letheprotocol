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
var arm_icon: Control              # the wounded-arm icon on the health plate (Game.arm_injured)
var ammo_big: Label
var ammo_small: Label
var weapon_name: Label
var reload_bar: ColorRect
var reload_bg: ColorRect
var kills_label: Label
var vignette: TextureRect
var scope_rect: ColorRect
var hint: Label
var death_panel: Control
var death_stats: Label
var objective_label: Label
var toast_label: Label
var interact_label: Label
var win_title_label: Label
var toast_t := 0.0
var win_panel: Control
var win_stats: Label
var pause_panel: Control
var cross: _Cross
var stealth: _Stealth
var context_hint: _Context
var grenade_badge: _Grenades
var radio_label: Label
var radio_t := 0.0
var health_plate: Panel
var ammo_plate: Panel
var mags: _Mags
var loadout_view: _Loadout
var pickup_plate: Panel
var pickup_key: Label
var pickup_icon: _Icon
var pickup_name: Label
var pickup_info: Label
var notice_label: Label
var hit_t := 0.0
var hit_kill := false
var hit_head := false
var hint_t := 14.0
var _last_health := -1.0
var debug_overlay: PerfOverlay
var gpu_warning: Label


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


## Stealth indicator above the crosshair: nothing when hidden, a yellow eye that fills up while a suspicious soldier gets closer
## to noticing the player, a red eye once someone hunts him; short arcs round the crosshair point at whoever is suspicious or
## shooting (yellow / red).
class _Stealth extends Control:
	var mode := 0           # 0 hidden, 1 suspicious, 2 alerted
	var fill := 0.0
	var arcs: Array = []    # [screen angle, Color]

	func _lens(w: float, h: float, x_from: float, x_to: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var n := 14
		for i in n + 1:
			var x := lerpf(x_from, x_to, float(i) / n)
			pts.append(Vector2(x, -h * (1.0 - pow(x / w, 2.0))))
		for i in range(n, -1, -1):
			var x2 := lerpf(x_from, x_to, float(i) / n)
			pts.append(Vector2(x2, h * (1.0 - pow(x2 / w, 2.0))))
		return pts

	func _draw() -> void:
		var c := size * 0.5
		for a in arcs:
			draw_arc(c, 40.0, float(a[0]) - 0.3, float(a[0]) + 0.3, 8, a[1], 3.5, true)
		if mode == 0:
			return
		var eye_c := c + Vector2(0, -62)
		var w := 14.0
		var h := 7.0
		var col := Color(1.0, 0.82, 0.2) if mode == 1 else Color(0.95, 0.2, 0.18)
		draw_set_transform(eye_c)
		draw_colored_polygon(_lens(w, h, -w, w), Color(0, 0, 0, 0.55))
		if mode == 1:
			var to_x := lerpf(-w + 0.5, w - 0.5, clampf(fill, 0.0, 1.0))
			if to_x > -w + 1.0:
				draw_colored_polygon(_lens(w, h, -w + 0.5, to_x), Color(col.r, col.g, col.b, 0.85))
		else:
			draw_colored_polygon(_lens(w, h, -w + 0.5, w - 0.5), Color(col.r, col.g, col.b, 0.9))
			draw_circle(Vector2.ZERO, 3.2, Color(0.1, 0, 0, 0.9))
		draw_polyline(_lens(w, h, -w, w), col, 1.8)
		draw_set_transform(Vector2.ZERO)


## A small prompt under the crosshair: a crouching figure under a bar and "CTRL  CROUCH" before a passage you can only pass crouched,
## a ladder and "W  CLIMB" at the foot of a ladder.
class _Context extends Control:
	var kind := 0           # 0 hidden, 1 climb, 2 crouch

	func _draw() -> void:
		if kind == 0:
			return
		var plate := Rect2(Vector2.ZERO, size)
		draw_rect(plate, Color(0.05, 0.07, 0.08, 0.72))
		draw_rect(plate, Color(0.2, 0.85, 0.8, 0.8), false, 1.5)
		var ink := Color(0.9, 0.95, 0.95)
		var accent := Color(0.2, 0.85, 0.8)
		var o := Vector2(34.0, size.y * 0.5)
		if kind == 2:
			draw_line(o + Vector2(-20, -17), o + Vector2(20, -17), accent, 3.0)             # the low beam
			draw_circle(o + Vector2(-6, -7), 4.5, ink)                                       # head
			draw_polyline(PackedVector2Array([o + Vector2(-7, -2), o + Vector2(-2, 7), o + Vector2(8, 8), o + Vector2(8, 16)]), ink, 3.5)
			draw_line(o + Vector2(-4, 0), o + Vector2(6, 4), ink, 2.5)                       # arm
		else:
			draw_line(o + Vector2(-8, -18), o + Vector2(-8, 18), ink, 2.5)
			draw_line(o + Vector2(8, -18), o + Vector2(8, 18), ink, 2.5)
			for k in 5:
				draw_line(o + Vector2(-8, -14.0 + 7.0 * k), o + Vector2(8, -14.0 + 7.0 * k), accent, 2.0)
		var font := ThemeDB.fallback_font
		var key := "CTRL" if kind == 2 else "W"
		var label := "CROUCH" if kind == 2 else "CLIMB"
		draw_string(font, Vector2(66.0, size.y * 0.5 + 6.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, accent)
		draw_string(font, Vector2(66.0 + (46.0 if kind == 2 else 24.0), size.y * 0.5 + 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)


## Frag grenade count next to the ammo box: a small grenade icon and "x N" (dim when empty).
class _Grenades extends Control:
	var count := 0

	func _draw() -> void:
		var on := count > 0
		var body := Color(0.5, 0.6, 0.32, 1.0 if on else 0.35)
		var metal := Color(0.75, 0.76, 0.78, 1.0 if on else 0.35)
		draw_circle(Vector2(18, 30), 11.0, body)               # the body
		draw_rect(Rect2(14, 15, 8, 6), metal)                   # the cap
		draw_rect(Rect2(21, 14, 9, 3), metal)                   # the lever
		draw_arc(Vector2(13, 14), 4.0, 0.0, TAU, 10, metal, 1.5)  # the pin ring
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(36, 36), "x %d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.95 if on else 0.4))
		draw_string(font, Vector2(2, 56), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))


## The wounded right arm next to the health blocks: a bent arm with a bandage and a red pulse (shown after the story wound).
class _ArmIcon extends Control:
	var t := 0.0

	func _draw() -> void:
		var hurt := Color(0.9, 0.2, 0.18, 0.9)
		var limb := Color(0.82, 0.84, 0.86, 0.95)
		draw_line(Vector2(8, 6), Vector2(20, 18), limb, 6.0)          # upper arm
		draw_line(Vector2(20, 18), Vector2(34, 10), limb, 5.0)        # forearm, bent at the elbow
		draw_circle(Vector2(36, 9), 4.0, limb)                        # the hand
		draw_line(Vector2(24, 17), Vector2(29, 13), Color(0.95, 0.95, 0.95), 7.0)     # the bandage
		draw_circle(Vector2(26, 15), 3.0 + 1.0 * sin(t * 6.0), hurt)     # the wound pulses
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(2, 32), "ARM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hurt)

	func _process(delta: float) -> void:
		if visible:
			t += delta
			queue_redraw()


## Magazine strip: the loaded magazine first (highlighted), then every spare one, each filled by its rounds.
class _Mags extends Control:
	var loaded := 0
	var cap := 0
	var spares: Array = []

	func _draw() -> void:
		if cap <= 0:
			return
		var font := ThemeDB.fallback_font
		var bw := 20.0
		var bh := 34.0
		var x := 0.0
		for i in spares.size() + 1:
			var rounds := loaded if i == 0 else int(spares[i - 1])
			var frac := clampf(float(rounds) / float(cap), 0.0, 1.0)
			var r := Rect2(x, 0, bw, bh)
			draw_rect(r, Color(1, 1, 1, 0.1))
			var col := Color(0.2, 0.85, 0.8) if i == 0 else Color(0.95, 0.8, 0.35)
			if i == 0 and frac <= 0.25:
				col = Color(0.9, 0.25, 0.22)
			elif i > 0 and frac < 1.0:
				col = Color(0.75, 0.62, 0.3)
			draw_rect(Rect2(x, bh * (1.0 - frac), bw, bh * frac), col)
			if i == 0:
				draw_rect(r, Color(0.2, 0.85, 0.8, 0.9), false, 1.5)
				x += bw + 12.0
				draw_line(Vector2(x - 6.0, 0), Vector2(x - 6.0, bh), Color(1, 1, 1, 0.25), 1.0)
			else:
				x += bw + 4.0
			var label_x := r.position.x + 1.0
			draw_string(font, Vector2(label_x, bh + 13.0), str(rounds), HORIZONTAL_ALIGNMENT_LEFT, bw, 11, Color(1, 1, 1, 0.75))


## The three slots with their two weapons each; the one in hand is lit.
class _Loadout extends Control:
	var data := {}
	var active_slot := ""
	var active_idx := 0

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var gx := 0.0
		var n := 1
		for slot in ["pistol", "rifle", "melee"]:
			draw_string(font, Vector2(gx, 11), "%d  %s" % [n, WeaponsDB.SLOT_NAMES[slot]], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
			for i in 2:
				var r := Rect2(gx + i * 46.0, 16, 42, 32)
				var arr: Array = data.get(slot, [])
				var on: bool = slot == active_slot and i == active_idx
				draw_rect(r, Color(0.05, 0.07, 0.08, 0.72))
				if i < arr.size():
					var inst: Dictionary = arr[i]
					var w: Dictionary = WeaponsDB.WEAPONS[inst["id"]]
					var glow: Color = w.get("glow", Color(0.8, 0.8, 0.85))
					draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), glow)
					draw_string(font, r.position + Vector2(6, 14), String(w["short"]), HORIZONTAL_ALIGNMENT_LEFT, 36, 11, Color(1, 1, 1, 1.0 if on else 0.6))
					if not bool(w.get("melee", false)):
						draw_string(font, r.position + Vector2(6, 27), "%d" % int(inst["ammo"]), HORIZONTAL_ALIGNMENT_LEFT, 36, 11, Color(0.95, 0.8, 0.35, 1.0 if on else 0.55))
				else:
					draw_string(font, r.position + Vector2(14, 20), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.25))
				if on:
					draw_rect(r, Color(0.2, 0.85, 0.8, 0.95), false, 2.0)
			gx += 88.0 + 14.0
			n += 1


## Side-on picture of a weapon for the pick-up box: the weapon's own parts (GunModels.profile) drawn as rectangles,
## barrel to the right, glowing parts in their glow colour.
class _Icon extends Control:
	var id := ""

	func _draw() -> void:
		if id == "":
			return
		var w: Dictionary = WeaponsDB.WEAPONS[id]
		var length := float(w["length"])
		var px := clampf(length * 150.0, 60.0, 170.0)      # drawn width in pixels
		var scale := px / maxf(0.2, length)                 # pixels per metre
		var c := size * 0.5
		var melee := bool(w.get("melee", false))
		# centre the drawing: guns by their length middle (z = 0), melee weapons by the middle of the blade
		var z_mid := (-length * 0.5 + 0.05) if melee else 0.0
		var y_mid := 0.0 if melee else -0.06
		for part in GunModels.profile(id):
			var r: Rect2 = part[0]
			var col: Color = part[1]
			var glowing: bool = part[2]
			var x0 := c.x + (-(r.position.x + r.size.x) - (-z_mid)) * scale        # muzzle (-z) to the right
			var y0 := c.y - ((r.position.y + r.size.y) - y_mid) * scale
			var rect := Rect2(x0, y0, maxf(r.size.x * scale, 1.5), maxf(r.size.y * scale, 1.5))
			draw_rect(rect, col if glowing else col.lightened(0.35))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_set_font()


func setup(p: Player) -> void:
	player = p
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	debug_overlay = PerfOverlay.new()       # F3, hidden and not processing until toggled
	add_child(debug_overlay)

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

	# scope mask for high-zoom weapons: black outside a circle, thin cross-hair lines through the middle
	scope_rect = ColorRect.new()
	scope_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sc_shader := Shader.new()
	sc_shader.code = """
shader_type canvas_item;
uniform float aspect = 1.78;
uniform float breath = -1.0;     // < 0: no bar (weapons that cannot hold their breath)
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float r = length(p);
	float mask = smoothstep(0.38, 0.4, r);
	float line = (1.0 - smoothstep(0.0006, 0.0016, abs(p.x))) + (1.0 - smoothstep(0.0006, 0.0016, abs(p.y)));
	line *= 1.0 - smoothstep(0.34, 0.38, r);
	line *= smoothstep(0.012, 0.03, r);
	float bar = step(0.0, breath) * step(abs(p.x), 0.07 * breath) * step(abs(p.y - 0.31), 0.004);
	COLOR = vec4(vec3(bar * 0.85), clamp(mask + line * 0.85 + bar, 0.0, 1.0));
}
"""
	var sc_mat := ShaderMaterial.new()
	sc_mat.shader = sc_shader
	scope_rect.material = sc_mat
	scope_rect.visible = false
	root.add_child(scope_rect)

	cross = _Cross.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	stealth = _Stealth.new()
	stealth.set_anchors_preset(Control.PRESET_FULL_RECT)
	stealth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stealth)
	context_hint = _Context.new()
	context_hint.size = Vector2(190, 46)
	context_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(context_hint)
	grenade_badge = _Grenades.new()
	grenade_badge.size = Vector2(90, 62)
	grenade_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grenade_badge)
	radio_label = _label(root, "", 18, Color(0.75, 0.95, 0.85))
	radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radio_label.size = Vector2(700, 28)
	Game.radio_line.connect(_on_radio_line)

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
	arm_icon = _ArmIcon.new()
	arm_icon.size = Vector2(48, 36)
	arm_icon.position = Vector2(196, 2)
	arm_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arm_icon.visible = false
	hp.add_child(arm_icon)

	# ammo box (bottom right)
	ammo_plate = _plate(root, Vector2(0, 0), Vector2(122, 48))
	var ap := ammo_plate
	weapon_name = _label(ap, "M9 PISTOL", 10, Color(0.75, 0.8, 0.8))
	weapon_name.position = Vector2(8, 0)
	ammo_big = _label(ap, "15", 24, Color.WHITE)
	ammo_big.position = Vector2(8, 10)
	ammo_small = _label(ap, "/ 60", 11, GOLD)
	ammo_small.position = Vector2(52, 21)
	mags = _Mags.new()
	mags.position = Vector2(12, 56)
	mags.size = Vector2(266, 50)
	mags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ap.add_child(mags)
	reload_bg = ColorRect.new()
	reload_bg.color = Color(1, 1, 1, 0.12)
	reload_bg.size = Vector2(106, 3)
	reload_bg.position = Vector2(8, 42)
	reload_bg.visible = false
	ap.add_child(reload_bg)
	reload_bar = ColorRect.new()
	reload_bar.color = ACCENT
	reload_bar.size = Vector2(0, 3)
	reload_bg.add_child(reload_bar)

	# weapon slots strip (above the ammo box)
	loadout_view = _Loadout.new()
	loadout_view.size = Vector2(290, 52)
	loadout_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(loadout_view)

	# pick-up box (right side of the screen), shown while standing over a weapon
	pickup_plate = _plate(root, Vector2(0, 0), Vector2(300, 150))
	pickup_key = _label(pickup_plate, "[Q]  PICK UP", 15, GOLD)
	pickup_key.position = Vector2(12, 6)
	pickup_icon = _Icon.new()
	pickup_icon.position = Vector2(0, 26)
	pickup_icon.size = Vector2(300, 52)
	pickup_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pickup_plate.add_child(pickup_icon)
	pickup_name = _label(pickup_plate, "", 20, Color.WHITE)
	pickup_name.position = Vector2(12, 80)
	pickup_info = _label(pickup_plate, "", 14, Color(0.8, 0.85, 0.85))
	pickup_info.position = Vector2(12, 106)
	pickup_info.size = Vector2(280, 40)
	pickup_plate.visible = false

	# toast ("+ MAGAZINE ...")
	notice_label = _label(root, "", 18, GOLD)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice_label.size = Vector2(400, 28)

	# controls hint
	hint = _label(root, "WASD move   SHIFT sprint   CTRL crouch / slide   SPACE jump   LMB fire   RMB aim   R reload   ESC pause\n1 / 2 / 3 weapon slots (again = swap)   Q pick up   E interact   TAB / wheel cycle", 15, Color(1, 1, 1, 0.85))
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

	# objective (top centre) and the win screen
	objective_label = _label(root, "", 20, GOLD)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.size = Vector2(600, 30)
	toast_label = _label(root, "", 22, ACCENT)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.size = Vector2(600, 30)
	interact_label = _label(root, "", 26, Color.WHITE)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_label.size = Vector2(600, 36)
	win_panel = _overlay(root, Color(0.0, 0.2, 0.15, 0.6))
	var wt := _label(win_panel, "HOME", 56, ACCENT)
	win_title_label = wt
	wt.set_anchors_preset(Control.PRESET_CENTER)
	wt.position = Vector2(-300, -90)
	wt.size = Vector2(600, 80)
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_stats = _label(win_panel, "", 20, Color.WHITE)
	win_stats.set_anchors_preset(Control.PRESET_CENTER)
	win_stats.position = Vector2(-250, -5)
	win_stats.size = Vector2(500, 100)
	win_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_panel.visible = false

	# pause screen: a menu with graphics settings and a short guide to the movement
	pause_panel = _overlay(root, Color(0, 0, 0, 0.7))
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_pause_menu()
	pause_panel.visible = false

	Game.player_died.connect(_on_died)
	Game.goal_reached.connect(_on_goal)
	Game.objective_completed.connect(_on_objective_completed)
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


## The stealth indicator: who is suspicious (eye + arcs), who hunts or shoots (red eye, red arcs).
func _update_stealth() -> void:
	var arcs: Array = []
	var near: Enemy = null
	var near_d := 1.0e9
	var alerted := false
	var pp := player.global_position
	for e in Game.enemies:
		if not is_instance_valid(e):
			continue
		var en := e as Enemy
		if en.state == Enemy.State.DEAD:
			continue
		var to := en.global_position - pp
		var d := Vector2(to.x, to.z).length()
		var screen_angle := -PI * 0.5 - (atan2(-to.x, -to.z) - player.yaw)
		match en.state:
			Enemy.State.SUSPICIOUS:
				if d < 90.0:
					arcs.append([screen_angle, Color(1.0, 0.82, 0.2, 0.7)])
					if d < near_d:
						near_d = d
						near = en
			Enemy.State.SHOOT:
				if d < 120.0:
					alerted = true
					arcs.append([screen_angle, Color(0.95, 0.2, 0.18, 0.8)])
			Enemy.State.ALERT, Enemy.State.CHASE, Enemy.State.ATTACK:
				if d < 120.0:
					alerted = true
	stealth.mode = 2 if alerted else (1 if near != null else 0)
	stealth.fill = near.notice_progress() if near != null else 0.0
	stealth.arcs = arcs
	stealth.queue_redraw()


## Soldiers talking over the radio (subtitle at the bottom of the screen).
func _on_radio_line(text: String) -> void:
	radio_label.text = "[RADIO]  " + text
	radio_label.modulate.a = 1.0
	radio_t = 3.2


func _on_objective_completed(_id: String, _text: String) -> void:
	toast_label.text = "OBJECTIVE COMPLETE"
	toast_label.modulate.a = 1.0
	toast_t = 2.6


## Called by Main after a checkpoint was restored: back to the game.
func on_restored() -> void:
	death_panel.visible = false
	toast_label.text = ""
	toast_t = 0.0
	_last_health = -1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_goal() -> void:
	if Game.mission != null:
		win_title_label.text = Game.mission.win_title
	win_stats.text = "Kills: %d   Takedowns: %d   Civilians lost: %d
Shots: %d   Hits: %d   Accuracy: %d%%
Health left: %d

Press R to play again" % [
		Game.kills, Game.takedowns, Game.civilians_lost, Game.shots_fired, Game.shots_hit,
		int(100.0 * Game.shots_hit / maxf(1.0, Game.shots_fired)), int(ceil(player.health))]
	win_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_died() -> void:
	death_stats.text = "Kills: %d   Takedowns: %d   Civilians lost: %d\nShots: %d   Hits: %d   Accuracy: %d%%\n\nR - restart from checkpoint      SHIFT+R - restart the whole mission" % [
		Game.kills, Game.takedowns, Game.civilians_lost, Game.shots_fired, Game.shots_hit,
		int(100.0 * Game.shots_hit / maxf(1.0, Game.shots_fired))]
	death_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		debug_overlay.toggle()
		return
	if Game.dead or Game.won:
		if event.is_action_pressed("restart"):
			var shift := Input.is_key_pressed(KEY_SHIFT) or (event is InputEventKey and (event as InputEventKey).shift_pressed)
			if Game.dead and not Game.won and not shift and Game.has_checkpoint:
				Game.checkpoint_requested.emit()
			else:
				get_tree().paused = false
				get_tree().reload_current_scene()
		return
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif false:
		_set_paused(false)
		get_viewport().set_input_as_handled()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	Game.paused = p
	pause_panel.visible = p
	Game.mark("pause")
	if p:
		_show_gpu_warning()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	health_plate.position = Vector2(16, vs.y - 78)
	ammo_plate.position = Vector2(vs.x - 138, vs.y - 64)
	loadout_view.position = Vector2(vs.x - 306, vs.y - 120)
	pickup_plate.position = Vector2(vs.x - 316, vs.y * 0.5 - 75)
	objective_label.position = Vector2(vs.x * 0.5 - 300, 14)
	grenade_badge.position = Vector2(vs.x - 138 - 96, vs.y - 64 + 4)
	radio_label.position = Vector2(vs.x * 0.5 - 350, vs.y - 112)
	toast_label.position = Vector2(vs.x * 0.5 - 300, 48)
	interact_label.position = Vector2(vs.x * 0.5 - 300, vs.y * 0.62)
	context_hint.position = Vector2(vs.x * 0.5 - 95, vs.y * 0.62 + 34)
	notice_label.position = Vector2(vs.x - 416, vs.y * 0.5 - 112)
	hint.position = Vector2(vs.x * 0.5 - 380, vs.y - 64)


func _update_pickup_box(w: Weapons) -> void:
	var pk: Pickup = w.hover
	pickup_plate.visible = pk != null and is_instance_valid(pk) and not Game.dead
	if not pickup_plate.visible:
		return
	var d: Dictionary = WeaponsDB.WEAPONS[pk.weapon_id]
	pickup_icon.id = pk.weapon_id
	pickup_icon.queue_redraw()
	pickup_name.text = String(d["name"])
	var slot := String(d["slot"])
	var info := ""
	if bool(d.get("melee", false)):
		info = "MELEE   %d damage" % int(d["damage"])
	else:
		var spare_n := int(d["spare_mags"]) if pk.spare == null else (pk.spare as Array).size()
		info = "%d / %d rounds in the gun   +%d spare mags" % [pk.ammo, int(d["mag"]), spare_n]
	var arr: Array = w.loadout[slot]
	if arr.size() >= Weapons.MAX_PER_SLOT:
		var idx := w.active_idx if w.active_slot == slot else mini(int(w.last_idx[slot]), arr.size() - 1)
		info += "\nreplaces  %s" % String(WeaponsDB.WEAPONS[arr[idx]["id"]]["name"])
	pickup_info.text = info


func _process(delta: float) -> void:
	if player == null:
		return
	_layout()
	var w := player.weapons
	var s := w.stats()
	weapon_name.text = String(s["name"])
	var melee := w.is_melee()
	ammo_big.visible = not melee
	ammo_small.visible = not melee
	mags.visible = false          # only the number of spare magazines is shown
	if not melee:
		ammo_big.text = str(w.ammo())
		ammo_big.add_theme_color_override("font_color", RED if w.ammo() <= int(int(s["mag"]) * 0.25) else Color.WHITE)
		ammo_small.text = "MAGS  %d" % w.spare_mags()
		mags.loaded = w.ammo()
		mags.cap = int(s["mag"])
		mags.spares = (w.state[w.current]["spare"] as Array).duplicate()
		mags.queue_redraw()
	loadout_view.data = w.loadout
	loadout_view.active_slot = w.active_slot
	loadout_view.active_idx = w.active_idx
	loadout_view.queue_redraw()
	_update_pickup_box(w)
	notice_label.text = w.notice
	notice_label.modulate.a = clampf(w.notice_t / 0.6, 0.0, 1.0)
	if w.reloading:
		reload_bg.visible = true
		reload_bar.size.x = 106.0 * clampf(w.reload_t / w.reload_total(), 0.0, 1.0)
	else:
		reload_bg.visible = false

	if player.health != _last_health:
		_last_health = player.health
		health_label.text = "HEALTH %d" % int(ceil(player.health))
		var lit := int(ceil(player.health / 10.0))
		for i in 10:
			health_blocks[i].color = (ACCENT if player.health > 30.0 else RED) if i < lit else Color(1, 1, 1, 0.1)
	kills_label.text = "KILLS %d" % Game.kills
	if arm_icon.visible != Game.arm_injured:
		arm_icon.visible = Game.arm_injured
	grenade_badge.count = Game.grenades
	grenade_badge.queue_redraw()
	if radio_t > 0.0:
		radio_t -= delta
		radio_label.modulate.a = clampf(radio_t / 0.5, 0.0, 1.0)
		if radio_t <= 0.0:
			radio_label.text = ""
	var ms := Game.mission
	objective_label.text = ms.hud_text(player) if ms != null else ""
	interact_label.text = ms.interact_prompt() if ms != null else ""
	if w.takedown_target != null and not Game.dead:
		interact_label.text = "E - TAKEDOWN"
	_update_stealth()
	var ctx := player.context_hint()
	if ctx != context_hint.kind:
		context_hint.kind = ctx
		context_hint.queue_redraw()
	if toast_t > 0.0:
		toast_t -= delta
		toast_label.modulate.a = clampf(toast_t / 0.6, 0.0, 1.0)
		if toast_t <= 0.0:
			toast_label.text = ""
	vignette.modulate.a = clampf(player.hurt_k, 0.0, 1.0) + (0.5 if player.health < 25.0 and not Game.dead else 0.0) * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008))

	# crosshair opens with the weapon's real spread; hidden while aiming down sights
	var vp_h := get_viewport().get_visible_rect().size.y
	var fov_rad := deg_to_rad(player.camera.fov)
	var px := tan(deg_to_rad(w.current_spread())) / tan(fov_rad * 0.5) * vp_h * 0.5
	cross.spread_px = lerpf(cross.spread_px, 4.0 + px, 1.0 - exp(-25.0 * delta))
	cross.alpha = 1.0 - clampf(w.ads_k * 1.6, 0.0, 1.0)
	cross.show_dot = w.ads_k > 0.5
	cross.alpha = maxf(cross.alpha, 0.0)
	if melee:
		cross.alpha = 0.5
		cross.spread_px = 3.0
	if cross.show_dot:
		cross.alpha = 0.9
		cross.spread_px = 0.0
	var scoped := w.is_scoped()
	scope_rect.visible = scoped
	cross.visible = not scoped
	if scoped:
		(scope_rect.material as ShaderMaterial).set_shader_parameter("aspect", get_viewport().get_visible_rect().size.x / maxf(1.0, vp_h))
		(scope_rect.material as ShaderMaterial).set_shader_parameter("breath", w.breath if float(w.stats().get("scope_sway", 0.0)) > 0.0 else -1.0)
	cross.hit_t = maxf(0.0, cross.hit_t - delta)
	cross.queue_redraw()

	if hint_t > 0.0 and not get_tree().paused:
		hint_t -= delta
		hint.modulate.a = clampf(hint_t / 2.0, 0.0, 1.0)


# ---------------------------------------------------------------- pause menu

const GUIDE := """MOVEMENT
WASD  walk (5 m/s).  Shift  sprint forward (8 m/s, loud, cancels aiming).
Ctrl  crouch (slow and silent to soldiers, shorter: fits under low pipes and slabs).
Shift, then Ctrl while sprinting  slide.
Space  jump, hold for a higher jump. You can jump a moment after leaving a ledge.
Small ledges (up to 0.55 m: kerbs, steps, stairs) are climbed automatically.
Ladders: walk into one and press W. W / S climb, Space jumps off backwards,
the top steps onto the roof. You cannot shoot on a ladder, but you can change weapon.
Fall damage starts above about 2 storeys; 4 storeys nearly kills, 6 storeys does.
STEALTH
Crouched, nobody hears you. Stand behind a soldier with a knife and press E for a silent takedown.
COMBAT
LMB fire, RMB aim, R reload, 1 / 2 / 3 weapon slots, Tab or wheel cycle, Q pick up, hold G grenade.
RELOADING: the rounds left in the gun are lost; you get a full magazine from your spares.
The counter shows how many spare magazines you carry."""

var _menu_widgets := {}


func _build_pause_menu() -> void:
	Settings.load_settings()
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.08, 0.96)
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", sb)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(centre)
	box.custom_minimum_size = Vector2(940, 0)

	centre.add_child(box)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	box.add_child(outer)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", ACCENT)
	outer.add_child(title)
	gpu_warning = _menu_label("", Color(1.0, 0.65, 0.2), 15)
	gpu_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpu_warning.custom_minimum_size = Vector2(900, 0)
	gpu_warning.visible = false
	outer.add_child(gpu_warning)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	outer.add_child(cols)
	# --- left: settings
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(_menu_label("GRAPHICS", ACCENT, 20))
	_menu_option(left, "Quality preset", "preset", ["Custom", "Low", "Medium", "High"], 0, func(i: int) -> void:
		if i > 0:
			Settings.preset(i - 1)
			_sync_menu()
			_apply_settings())
	_menu_option(left, "Shadows", "shadows", ["Off", "Low", "High"], Settings.shadows, func(i: int) -> void:
		Settings.shadows = i
		_apply_settings())
	_menu_option(left, "Anti-aliasing", "aa", ["Off", "MSAA 2x", "MSAA 4x"], Settings.aa, func(i: int) -> void:
		Settings.aa = i
		_apply_settings())
	_menu_option(left, "View distance", "view", ["Short", "Medium", "Long"], Settings.view, func(i: int) -> void:
		Settings.view = i
		_apply_settings())
	_menu_slider(left, "Render scale", "scale", 50.0, 100.0, 5.0, float(Settings.scale_pct), "%d%%", func(v: float) -> void:
		Settings.scale_pct = int(v)
		_apply_settings())
	left.add_child(_menu_label("GAME", ACCENT, 20))
	_menu_slider(left, "Mouse sensitivity", "sens", 0.3, 2.5, 0.1, Settings.sens, "x%.1f", func(v: float) -> void:
		Settings.sens = v
		_apply_settings())
	_menu_check(left, "Fullscreen", "fullscreen", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		_apply_settings())
	_menu_check(left, "VSync", "vsync", Settings.vsync, func(on: bool) -> void:
		Settings.vsync = on
		_apply_settings())
	left.add_child(_menu_label("CHEATS", ACCENT, 20))
	var give := Button.new()
	give.text = "GIVE  SNIPER + HEAVY GUN  (full ammo)"
	give.custom_minimum_size = Vector2(0, 38)
	give.pressed.connect(func() -> void:
		player.weapons.give_heavy_set()
		_set_paused(false))
	left.add_child(give)
	var clear := Button.new()
	clear.text = "KILL SOLDIERS WITHIN 50 m"
	clear.custom_minimum_size = Vector2(0, 38)
	clear.pressed.connect(func() -> void:
		_clear_nearby()
		_set_paused(false))
	left.add_child(clear)
	# --- right: the guide
	var guide := Label.new()
	guide.text = GUIDE
	guide.add_theme_font_size_override("font_size", 13)
	guide.add_theme_color_override("font_color", Color(0.85, 0.92, 0.92))
	guide.custom_minimum_size = Vector2(500, 0)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cols.add_child(guide)
	var resume := Button.new()
	resume.text = "RESUME  (Esc)"
	resume.custom_minimum_size = Vector2(0, 44)
	resume.pressed.connect(func() -> void: _set_paused(false))
	outer.add_child(resume)


## One-time warning (once per adapter name, remembered in settings.cfg) when the game is not drawing on the NVIDIA card.
func _show_gpu_warning() -> void:
	if gpu_warning == null:
		return
	if Game.gpu_is_nvidia or Settings.gpu_warned == String(Game.gpu["name"]):
		gpu_warning.visible = false
		return
	Settings.gpu_warned = String(Game.gpu["name"])
	Settings.save()
	gpu_warning.text = "WARNING: the game is running on \"%s\" (%s), not on the NVIDIA GPU. Expect low FPS. Windows Settings > System > Display > Graphics > add Godot.exe / the game exe > Options > High performance (details in README.md, section \"Which GPU is the game using?\")." % [Game.gpu["name"], Game.gpu["type"]]
	gpu_warning.visible = true


func _menu_label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _menu_row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _menu_label(text, Color(0.9, 0.95, 0.95), 16)
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	parent.add_child(row)
	return row


func _menu_option(parent: Control, text: String, key: String, items: Array, selected: int, on_pick: Callable) -> void:
	var row := _menu_row(parent, text)
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(String(it))
	ob.select(selected)
	ob.custom_minimum_size = Vector2(190, 0)
	ob.item_selected.connect(on_pick)
	row.add_child(ob)
	_menu_widgets[key] = ob


func _menu_slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var row := _menu_row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(130, 24)
	var val := _menu_label(fmt % value, Color(0.9, 0.95, 0.95), 16)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % v
		on_change.call(v))
	row.add_child(s)
	row.add_child(val)
	_menu_widgets[key] = s


func _menu_check(parent: Control, text: String, key: String, on: bool, on_toggle: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	_menu_widgets[key] = c


func _sync_menu() -> void:
	(_menu_widgets["shadows"] as OptionButton).select(Settings.shadows)
	(_menu_widgets["aa"] as OptionButton).select(Settings.aa)
	(_menu_widgets["view"] as OptionButton).select(Settings.view)
	(_menu_widgets["scale"] as HSlider).value = float(Settings.scale_pct)


func _apply_settings() -> void:
	Settings.apply(get_tree(), get_tree().current_scene)
	Settings.save()


## One clean, narrow sans for everything (the system's Bahnschrift, else Segoe UI); the engine's own font stays the last fallback.
func _set_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Semibold", "Segoe UI", "Helvetica Neue", "Arial"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.oversampling = 2.0
	ThemeDB.fallback_font = f


## Menu button: every living soldier within CLEAR_RADIUS metres of the player is shot dead (the others stay).
const CLEAR_RADIUS := 50.0


func _clear_nearby() -> void:
	var n := 0
	for e in Game.enemies.duplicate():
		var en := e as Enemy
		if not is_instance_valid(en) or en.state == Enemy.State.DEAD:
			continue
		if en.global_position.distance_to(player.global_position) > CLEAR_RADIUS:
			continue
		var dir := (en.global_position - player.global_position).normalized()
		en.take_hit(99999.0, "head", dir * 4.0, en.global_position + Vector3(0.0, 1.5, 0.0))
		n += 1
	player.weapons.notice = "%d SOLDIERS DOWN WITHIN %d m" % [n, int(CLEAR_RADIUS)]
	player.weapons.notice_t = 2.5
