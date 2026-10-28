class_name SettingsMenu
extends TabContainer
## The settings tabs, the same in the pause menu (HUD) and the main menu (MainMenu): GRAPHICS, GAME, SUBTITLES, CONTROLS (key rebinding
## and the short guide). Every change is applied (Settings.apply) and saved at once. The pause menu adds its CHEATS tab with `page()`.

const ACCENT := Color(0.2, 0.85, 0.8)
const INK := Color(0.9, 0.95, 0.95)
const NOTE := Color(0.62, 0.7, 0.72)

const GUIDE_MOVE := """Sprint only runs forward (8 m/s, loud, cancels aiming). Crouched you are slow, silent to soldiers and short enough for low pipes and slabs; crouch while sprinting to slide.
Hold jump for a higher jump; you can still jump a moment after leaving a ledge. Small ledges (up to 0.55 m: kerbs, steps, stairs) are climbed automatically.
Ladders: walk into one and press forward; back climbs down, jump jumps off backwards, the top steps onto the roof. You cannot shoot on a ladder, but you can change weapon.
Fall damage starts above about 2 storeys; 4 storeys nearly kills, 6 storeys does."""
const GUIDE_STEALTH := """Crouched, nobody hears you. Stand behind a soldier with a knife and press interact for a silent takedown."""
const GUIDE_COMBAT := """RELOADING: the rounds left in the gun are lost; you get a full magazine from your spares. The counter shows how many spare magazines you carry.
A slot key again swaps between the two weapons in that slot; the mouse wheel cycles too. Hold the grenade key to aim the throw, let go to throw."""

var widgets := {}
var _waiting := ""                    # the action whose key button waits for a key ("" = none)
var _key_buttons := {}                # action -> Button


func _ready() -> void:
	Settings.load_settings()
	add_theme_font_size_override("font_size", 18)
	_build()


func _apply() -> void:
	Settings.apply(get_tree(), get_tree().current_scene)
	Settings.save()


func _build() -> void:
	# --- GRAPHICS
	var gfx := page("GRAPHICS")
	option(gfx, "Quality preset", "preset", ["Custom", "Low", "Medium", "High"], 0, func(i: int) -> void:
		if i > 0:
			Settings.preset(i - 1)
			sync()
			_apply())
	note(gfx, "Sets shadows, anti-aliasing, render scale and view distance in one go. Change any of them below and it becomes Custom.")
	option(gfx, "Shadows", "shadows", ["Off", "Low", "High"], Settings.shadows, func(i: int) -> void:
		Settings.shadows = i
		_apply())
	note(gfx, "Sun shadows. Low only shades the area right around you; the biggest saving after render scale.")
	option(gfx, "Anti-aliasing", "aa", ["Off", "MSAA 2x", "MSAA 4x"], Settings.aa, func(i: int) -> void:
		Settings.aa = i
		_apply())
	note(gfx, "Smooths jagged edges of buildings and weapons. Costs speed on weaker cards.")
	option(gfx, "View distance", "view", ["Short", "Medium", "Long"], Settings.view, func(i: int) -> void:
		Settings.view = i
		_apply())
	note(gfx, "How far you can see down the avenues before the haze takes the city.")
	slider(gfx, "Render scale", "scale", 50.0, 100.0, 5.0, float(Settings.scale_pct), "%d%%", func(v: float) -> void:
		Settings.scale_pct = int(v)
		_apply())
	note(gfx, "Draws the 3D view at a lower resolution and stretches it. 100% is sharpest.")
	check(gfx, "Fullscreen", "fullscreen", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		_apply())
	check(gfx, "VSync", "vsync", Settings.vsync, func(on: bool) -> void:
		Settings.vsync = on
		_apply())
	note(gfx, "VSync locks the frame rate to your screen and stops tearing; turn it off for the highest FPS.")
	# --- GAME
	var game := page("GAME")
	slider(game, "Mouse sensitivity", "sens", 0.3, 2.5, 0.1, Settings.sens, "x%.1f", func(v: float) -> void:
		Settings.sens = v
		_apply())
	note(game, "Multiplies how far the view turns for each mouse movement.")
	check(game, "Compass", "compass", Settings.compass, func(on: bool) -> void:
		Settings.compass = on
		Settings.save())
	note(game, "The strip under the objective with the directions and a marker towards the objective.")
	slider(game, "Field of view", "fov", 60.0, 100.0, 1.0, Settings.fov, "%d", func(v: float) -> void:
		Settings.fov = v
		_apply())
	note(game, "How wide you see when not aiming (75 is the default). Wider shows more round you; aiming and scopes still zoom the same.")
	check(game, "Colour-blind markers", "colorblind", Settings.colorblind, func(on: bool) -> void:
		Settings.colorblind = on
		Settings.save())
	note(game, "Red warnings (low health, low ammo, the hunting eye, kill hits, the arm wound) turn magenta, healing turns blue instead of green, and the marksman's laser turns a thicker magenta. Safe for red-green colour blindness.")
	# --- AUDIO
	var snd := page("AUDIO")
	slider(snd, "Master volume", "vol_master", 0.0, 100.0, 5.0, float(Settings.vol_master), "%d%%", func(v: float) -> void:
		Settings.vol_master = int(v)
		_apply())
	slider(snd, "Voices", "vol_voice", 0.0, 100.0, 5.0, float(Settings.vol_voice), "%d%%", func(v: float) -> void:
		Settings.vol_voice = int(v)
		_apply())
	note(snd, "The spoken lines (Noah, his family, the soldiers, the Commander, the intercom), on top of the master volume.")
	# --- SUBTITLES
	var sub := page("SUBTITLES")
	check(sub, "Subtitles", "sub_on", Settings.subtitles, func(on: bool) -> void:
		Settings.subtitles = on
		Settings.save())
	option(sub, "Size", "sub_size", ["Small", "Medium", "Large"], Settings.sub_size, func(i: int) -> void:
		Settings.sub_size = i
		Settings.save())
	slider(sub, "Background", "sub_box", 0.0, 100.0, 5.0, float(Settings.sub_box), "%d%%", func(v: float) -> void:
		Settings.sub_box = int(v)
		Settings.save())
	note(sub, "How dark the box behind the lines is. 0% shows the words alone, with an outline.")
	check(sub, "Speaker names", "sub_names", Settings.sub_names, func(on: bool) -> void:
		Settings.sub_names = on
		Settings.save())
	note(sub, "The name of who is speaking before the line, in his colour: Noah, Mum, Mira, soldiers on the radio, the Commander, the intercom, the city guard. Noah's own thoughts are grey italics.")
	# --- CONTROLS
	var ctl := page("CONTROLS")
	check(ctl, "Invert mouse Y", "invert_y", Settings.invert_y, func(on: bool) -> void:
		Settings.invert_y = on
		Settings.save())
	option(ctl, "Aim", "toggle_aim", ["Hold", "Toggle"], 1 if Settings.toggle_aim else 0, func(i: int) -> void:
		Settings.toggle_aim = i == 1
		_apply())
	option(ctl, "Crouch", "toggle_crouch", ["Hold", "Toggle"], 1 if Settings.toggle_crouch else 0, func(i: int) -> void:
		Settings.toggle_crouch = i == 1
		_apply())
	option(ctl, "Sprint", "toggle_sprint", ["Hold", "Toggle"], 1 if Settings.toggle_sprint else 0, func(i: int) -> void:
		Settings.toggle_sprint = i == 1
		_apply())
	note(ctl, "Hold: the key works while you hold it. Toggle: press once to start, again to stop. A toggled sprint ends when you stop running forward; sprinting ends a toggled aim or crouch.")
	note(ctl, "Click a key, then press the new key or mouse button (Esc cancels). A key another action uses is swapped with it. Esc (pause), F3 and R on the death screen stay fixed.")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	ctl.add_child(grid)
	for b in Settings.BINDABLE:
		var l := label(String(b[1]), INK, 15)
		l.custom_minimum_size = Vector2(190, 0)
		grid.add_child(l)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(190, 30)
		btn.focus_mode = Control.FOCUS_NONE
		var act: String = b[0]
		btn.pressed.connect(func() -> void: _wait_for(act))
		grid.add_child(btn)
		_key_buttons[act] = btn
	var reset := Button.new()
	reset.text = "RESET TO DEFAULTS"
	reset.custom_minimum_size = Vector2(0, 34)
	reset.pressed.connect(func() -> void:
		_waiting = ""
		Settings.reset_keys()
		_refresh_keys())
	ctl.add_child(reset)
	for part in [["MOVEMENT", GUIDE_MOVE], ["STEALTH", GUIDE_STEALTH], ["COMBAT", GUIDE_COMBAT]]:
		ctl.add_child(label(String(part[0]), ACCENT, 17))
		var g := label(String(part[1]), Color(0.85, 0.92, 0.92), 14)
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		g.custom_minimum_size = Vector2(850, 0)
		ctl.add_child(g)
	_refresh_keys()


func _refresh_keys() -> void:
	for a in _key_buttons:
		(_key_buttons[a] as Button).text = "PRESS A KEY..." if a == _waiting else Settings.key_name(a)


func _wait_for(action: String) -> void:
	_waiting = action
	_refresh_keys()


func _input(event: InputEvent) -> void:
	if _waiting == "" or not is_visible_in_tree():
		return
	var code := ""
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_ESCAPE:
			_waiting = ""
			_refresh_keys()
			get_viewport().set_input_as_handled()
			return
		if k.physical_keycode == KEY_F3:
			return
		code = "k%d" % int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	elif event is InputEventMouseButton and event.pressed:
		code = "m%d" % int((event as InputEventMouseButton).button_index)
	if code == "":
		return
	get_viewport().set_input_as_handled()
	Settings.bind(_waiting, code)
	_waiting = ""
	_refresh_keys()


## Put the quality widgets back on the values in Settings (after a preset).
func sync() -> void:
	(widgets["shadows"] as OptionButton).select(Settings.shadows)
	(widgets["aa"] as OptionButton).select(Settings.aa)
	(widgets["view"] as OptionButton).select(Settings.view)
	(widgets["scale"] as HSlider).value = float(Settings.scale_pct)


# ---------------------------------------------------------------- builders

## A tab page (a scrolling column) returned as the VBox to fill.
func page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	add_child(scroll)
	return col


## A small grey line under a setting that says what it does.
func note(parent: Control, text: String) -> void:
	var l := label(text, NOTE, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(840, 0)
	parent.add_child(l)


static func label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(text, INK, 16)
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	parent.add_child(row)
	return row


func option(parent: Control, text: String, key: String, items: Array, selected: int, on_pick: Callable) -> void:
	var row := _row(parent, text)
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(String(it))
	ob.select(selected)
	ob.custom_minimum_size = Vector2(190, 0)
	ob.item_selected.connect(on_pick)
	row.add_child(ob)
	widgets[key] = ob


func slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(130, 24)
	var val := label(fmt % value, INK, 16)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % v
		on_change.call(v))
	row.add_child(s)
	row.add_child(val)
	widgets[key] = s


func check(parent: Control, text: String, key: String, on: bool, on_toggle: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	widgets[key] = c
