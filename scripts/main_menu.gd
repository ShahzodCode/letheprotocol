class_name MainMenu
extends CanvasLayer
## The title screen of a plain start (Main shows it before anything is built): CONTINUE, NEW GAME, CHAPTER SELECT, SETTINGS, QUIT; then the
## loading screen while Main builds the game: the part of the book as a title card, the recap of the story so far, a progress bar with the
## build steps, a tip, and "PRESS ANY KEY" at the end. Everything is built in code; it keeps running while the tree is paused.

signal chosen(boot: Dictionary)

const ACCENT := Color(0.2, 0.85, 0.8)
const INK := Color(0.9, 0.95, 0.95)
const DIM := Color(0.55, 0.62, 0.64)
const RED := Color(0.9, 0.3, 0.25)
const FADE_TIME := 0.8
const TIPS := [
	"Crouched, nobody hears you. A knife from behind is silent.",
	"Soldiers who lose you search where they saw you last. Move.",
	"Reloading throws away the rounds left in the magazine.",
	"Med kits heal over three seconds: find cover first.",
	"The yellow eye fills while a soldier is making you out. Get out of his sight before it is full.",
	"Every kill matters: nobody comes back.",
	"Hold the grenade key to see the arc, let go to throw.",
	"The map (M) shows the way to the objective. It does not show the soldiers.",
]

var _bg: ColorRect
var _title_box: Control
var _buttons: VBoxContainer
var _side: PanelContainer            # chapter select / settings
var _side_body: VBoxContainer
var _continue_btn: Button
var _load: Control
var _load_section: Label
var _load_name: Label
var _load_recap: Label
var _load_step: Label
var _load_tip: Label
var _bar: ColorRect
var _bar_bg: ColorRect
var _waiting_key := false
var _pick := ""                      # chapter select: the place shown


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	HUD._set_font()
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// dark haze drifting over a dim red wound in the sky (the broken Veil)
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.02;
	float n = noise(uv * 3.0 + vec2(t, t * 0.4)) * 0.6 + noise(uv * 7.0 - vec2(t * 1.7, 0.0)) * 0.4;
	float wound = exp(-pow(length((uv - vec2(0.72, 0.28)) * vec2(1.0, 2.2)) * 3.2, 2.0));
	vec3 col = mix(vec3(0.03, 0.04, 0.05), vec3(0.09, 0.1, 0.11), n * (1.0 - uv.y * 0.6));
	col += vec3(0.55, 0.12, 0.08) * wound * (0.75 + 0.25 * sin(TIME * 0.7)) * (0.6 + 0.4 * n);
	col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.3, 2.0);
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_bg.material = mat
	add_child(_bg)
	_build_title()
	_build_loading()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 46)
	b.add_theme_font_size_override("font_size", 22)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.content_margin_left = 14
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16)
	hover.border_color = ACCENT
	hover.border_width_left = 3
	hover.content_margin_left = 14
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", flat)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(DIM.r, DIM.g, DIM.b, 0.5))
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- the title screen

func _build_title() -> void:
	_title_box = Control.new()
	_title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_box)
	var col := VBoxContainer.new()
	col.position = Vector2(80, 90)
	col.add_theme_constant_override("separation", 4)
	_title_box.add_child(col)
	col.add_child(_label("LETHE PROTOCOL", 64, INK))
	col.add_child(_label("%s  -  %s" % [StoryPlaces.CHAPTER, StoryPlaces.CHAPTER_TITLE], 18, RED))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 50)
	col.add_child(gap)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 2)
	col.add_child(_buttons)
	_continue_btn = _button("CONTINUE", func() -> void: chosen.emit({"mode": "continue"}))
	_buttons.add_child(_continue_btn)
	var cont_note := _label(SaveGame.continue_text(), 14, DIM)
	cont_note.add_theme_constant_override("line_spacing", 0)
	_buttons.add_child(cont_note)
	_continue_btn.disabled = not SaveGame.has_continue()
	_buttons.add_child(_button("NEW GAME", func() -> void: chosen.emit({"mode": "new"})))
	_buttons.add_child(_button("CHAPTER SELECT", _show_chapters))
	_buttons.add_child(_button("SETTINGS", _show_settings))
	_buttons.add_child(_button("QUIT", func() -> void: get_tree().quit()))
	_side = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.92)
	sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
	sb.border_width_left = 2
	sb.set_content_margin_all(20)
	_side.add_theme_stylebox_override("panel", sb)
	_side.visible = false
	_title_box.add_child(_side)
	_side_body = VBoxContainer.new()
	_side_body.add_theme_constant_override("separation", 10)
	_side.add_child(_side_body)


## Show the menu and wait for a choice: {"mode": "new" | "continue" | "place", "place": id}.
func choose() -> Dictionary:
	_title_box.visible = true
	_load.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_continue_btn if not _continue_btn.disabled else _buttons.get_child(2)).grab_focus()
	var boot: Dictionary = await chosen
	return boot


func _process(_delta: float) -> void:
	if _side.visible:
		var vs := get_viewport().get_visible_rect().size
		_side.position = Vector2(460, 60)
		_side.size = Vector2(maxf(vs.x - 460 - 50, 600), vs.y - 120)


func _clear_side() -> void:
	for c in _side_body.get_children():
		c.queue_free()
	_side.visible = true


func _back_row() -> void:
	var back := _button("BACK  (Esc)", func() -> void: _side.visible = false)
	back.custom_minimum_size = Vector2(200, 40)
	_side_body.add_child(back)


func _input(event: InputEvent) -> void:
	if not _waiting_key:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_waiting_key = false
		chosen.emit({})
	get_viewport().set_input_as_handled()          # nothing reaches the HUD (Esc would unpause) or the player meanwhile


func _unhandled_input(event: InputEvent) -> void:
	if _title_box.visible and _side.visible and event is InputEventKey and event.is_pressed() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_side.visible = false
		get_viewport().set_input_as_handled()


func _show_settings() -> void:
	_clear_side()
	_side_body.add_child(_label("SETTINGS", 30, ACCENT))
	var tabs := SettingsMenu.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_body.add_child(tabs)
	_back_row()


func _show_chapters() -> void:
	_clear_side()
	_side_body.add_child(_label("CHAPTER SELECT", 30, ACCENT))
	_side_body.add_child(_label("%s  -  %s" % [StoryPlaces.CHAPTER, StoryPlaces.CHAPTER_TITLE], 15, RED))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	_side_body.add_child(row)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(300, 0)
	row.add_child(list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	row.add_child(detail)
	var first_open := ""
	for p in StoryPlaces.PLACES:
		var id := String(p["id"])
		var open := SaveGame.place_open(id)
		var b := _button(("%s" % p["name"]) if open else "%s   (not reached)" % p["name"], func() -> void: _show_place(detail, id))
		b.custom_minimum_size = Vector2(300, 38)
		b.add_theme_font_size_override("font_size", 17)
		if not open:
			b.add_theme_color_override("font_color", DIM)
		b.focus_entered.connect(func() -> void: _show_place(detail, id))
		list.add_child(b)
		if open:
			first_open = id
	_show_place(detail, first_open if first_open != "" else String(StoryPlaces.PLACES[0]["id"]))
	_back_row()


func _show_place(detail: VBoxContainer, id: String) -> void:
	_pick = id
	for c in detail.get_children():
		c.queue_free()
	var p := StoryPlaces.get_place(id)
	var open := SaveGame.place_open(id)
	detail.add_child(_label(String(p["section"]), 16, RED))
	detail.add_child(_label(String(p["name"]), 32, INK))
	var recap := _label(String(p["recap"]), 17, Color(0.82, 0.87, 0.87))
	recap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recap.custom_minimum_size = Vector2(420, 0)
	detail.add_child(recap)
	var entry := SaveGame.place_entry(id)
	var kit_text := ""
	if not entry.is_empty():
		kit_text = "You start with the weapons you had when you got here."
	else:
		var names: Array = []
		var kit: Dictionary = p["kit"]
		for slot in ["pistol", "rifle", "melee"]:
			for wid in kit.get(slot, []):
				names.append(String(WeaponsDB.WEAPONS[wid]["name"]))
		if int(kit.get("grenades", 0)) > 0:
			names.append("%d GRENADES" % int(kit["grenades"]))
		kit_text = "Standard kit: " + ", ".join(names) + (".  The right arm is wounded." if bool(kit.get("arm", false)) else ".")
	var kit_l := _label(kit_text if open else "Play up to this place to open it (or use the cheat in the pause menu).", 15, ACCENT if open else DIM)
	kit_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kit_l.custom_minimum_size = Vector2(420, 0)
	detail.add_child(kit_l)
	var start := _button("START HERE", func() -> void: chosen.emit({"mode": "place", "place": _pick}))
	start.disabled = not open
	detail.add_child(start)


# ---------------------------------------------------------------- the loading screen

func _build_loading() -> void:
	_load = Control.new()
	_load.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load.visible = false
	add_child(_load)
	var black := ColorRect.new()
	black.color = Color(0.015, 0.018, 0.02)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load.add_child(black)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 120
	col.offset_top = 0
	col.offset_right = -120
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_load.add_child(col)
	col.add_child(_label("%s  -  %s" % [StoryPlaces.CHAPTER, StoryPlaces.CHAPTER_TITLE], 16, DIM))
	_load_section = _label("", 22, RED)
	col.add_child(_load_section)
	_load_name = _label("", 56, INK)
	col.add_child(_load_name)
	_load_recap = _label("", 19, Color(0.8, 0.85, 0.85))
	_load_recap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_load_recap.custom_minimum_size = Vector2(700, 0)
	col.add_child(_load_recap)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.1)
	_bar_bg.custom_minimum_size = Vector2(0, 3)
	col.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = ACCENT
	_bar.size = Vector2(0, 3)
	_bar_bg.add_child(_bar)
	_load_step = _label("", 14, DIM)
	col.add_child(_load_step)
	_load_tip = _label("", 15, Color(0.7, 0.76, 0.76))
	_load_tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_load_tip.offset_left = 120
	_load_tip.offset_top = -70
	_load.add_child(_load_tip)


## The place a boot request starts at (for the title card).
func _place_of(boot: Dictionary) -> Dictionary:
	match String(boot.get("mode", "new")):
		"place":
			return StoryPlaces.get_place(String(boot.get("place", "")))
		"continue":
			var d := SaveGame.data()
			var ids: Array = d.get("ids", [])
			var idx := int((d.get("last", {}) as Dictionary).get("index", 0))
			var best: Dictionary = StoryPlaces.PLACES[0]
			for i in mini(idx + 1, ids.size()):
				var p := StoryPlaces.get_place(String(ids[i]))
				if not p.is_empty():
					best = p
			return best
	return StoryPlaces.PLACES[0]


func show_loading(boot: Dictionary) -> void:
	_title_box.visible = false
	_bg.visible = false
	_load.visible = true
	_load.modulate.a = 1.0
	var p := _place_of(boot)
	_load_section.text = String(p["section"])
	_load_name.text = String(p["name"])
	var prev := String(boot.get("mode", "new")) != "new"
	_load_recap.text = ("PREVIOUSLY:  " if prev else "") + String(p["recap"])
	_load_tip.text = "TIP:  " + String(TIPS[randi() % TIPS.size()])
	_bar.size.x = 0.0
	_load_step.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	await get_tree().process_frame
	await get_tree().process_frame


## A build step: move the bar and give the screen a frame to show it (the parts themselves block while they run).
func step(frac: float, text: String) -> void:
	_bar.size.x = _bar_bg.size.x * clampf(frac, 0.0, 1.0)
	_load_step.text = text
	await get_tree().process_frame
	await get_tree().process_frame


## The build is done: wait for a key (the game is paused meanwhile), then fade the loading screen out over the game.
func finish_loading() -> void:
	_bar.size.x = _bar_bg.size.x
	_load_step.text = "PRESS ANY KEY"
	_load_step.add_theme_color_override("font_color", ACCENT)
	get_tree().paused = true
	_waiting_key = true
	await chosen
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(_load, "modulate:a", 0.0, FADE_TIME)
	await tw.finished
