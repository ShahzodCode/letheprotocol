class_name Subtitles
extends Control
## The subtitle box at the bottom of the screen (owned by HUD): every Game.radio_line is shown in a dark box sized to the text, the speaker's name
## in his colour before it. Up to two lines stack; the older one dims and moves up when a new one comes.
## Who speaks: the "NAME:" prefix a line already has ("@MUM: ...", "CITY GUARD: ..."), else the style of its voice clip (audio/voices/index.json,
## read here so voice.gd stays as it is), else "@" = Noah's thoughts / the story's narration (grey italics, no name), else a soldier on the radio.
## A line stays as long as its clip plays plus a second, or a reading time. Settings: on / off, size, box opacity, names.

const MAX_LINES := 2
const WIDTH := 760.0
const BOTTOM := 96.0                  # pixels from the bottom of the screen to the lowest box
const FONT_SIZES := [16, 20, 25]
const INK := Color(0.93, 0.95, 0.95)
## speaker -> [name shown, colour]
const SPEAKERS := {
	"noah": ["NOAH", Color(0.35, 0.9, 0.85)],
	"mum": ["MUM", Color(1.0, 0.72, 0.38)],
	"mira": ["MIRA", Color(1.0, 0.62, 0.78)],
	"radio": ["SOLDIER (RADIO)", Color(1.0, 0.45, 0.3)],
	"soldier": ["SOLDIER", Color(1.0, 0.45, 0.3)],
	"commander": ["THE COMMANDER", Color(0.95, 0.22, 0.2)],
	"intercom": ["SHIP INTERCOM", Color(0.72, 0.58, 1.0)],
	"guard": ["CITY GUARD", Color(0.5, 0.7, 1.0)],
	"thought": ["", Color(0.72, 0.74, 0.76)],
}
## a "NAME:" prefix -> speaker
const PREFIXES := {"NOAH": "noah", "MUM": "mum", "MIRA": "mira", "COMMANDER": "commander", "THE COMMANDER": "commander",
	"CITY GUARD": "guard", "INTERCOM": "intercom", "SOLDIER": "soldier"}

static var _index := {}
static var _index_loaded := false

var last_speaker := ""                # the newest line's speaker key (tests read it)
var last_text := ""
var _box: VBoxContainer
var _lines: Array = []                # {panel, label, t}
var _prefix_re := RegEx.create_from_string("^([A-Z][A-Z ]{1,18}):\\s+(.*)$")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	Game.radio_line.connect(show_line)


static func _voice_style(text: String) -> String:
	if not _index_loaded:
		_index_loaded = true
		var f := FileAccess.open(Voice.DIR + "index.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_index = parsed
	return String(_index.get(text.sha1_text().substr(0, 12), ""))


## [speaker key, the words without any prefix] of a radio_line text.
func parse(raw: String) -> Array:
	var spoken := raw.begins_with("@")
	var text := raw.substr(1) if spoken else raw
	var m := _prefix_re.search(text)
	if m != null and PREFIXES.has(m.get_string(1)):
		return [PREFIXES[m.get_string(1)], m.get_string(2)]
	var style := _voice_style(raw)
	if style != "":
		return ["radio" if style == "soldier" and not spoken else style, text]
	return ["thought" if spoken else "radio", text]


func show_line(raw: String) -> void:
	var p := parse(raw)
	var who: String = p[0]
	var text: String = p[1]
	last_speaker = who
	last_text = text
	var hold := 0.0
	var main := get_tree().current_scene if is_inside_tree() else null
	if main != null and main.get("voice") != null:
		hold = (main.voice as Voice).duration(raw)
	if hold > 0.0:
		hold += 1.0
	elif raw.begins_with("@"):
		hold = clampf(2.0 + float(text.length()) * 0.04, 3.0, 6.0)
	else:
		hold = clampf(1.5 + float(text.length()) * 0.035, 3.2, 6.0)
	while _lines.size() >= MAX_LINES:
		(_lines.pop_front()["panel"] as Control).queue_free()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.05, float(Settings.sub_box) / 100.0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs: int = FONT_SIZES[clampi(Settings.sub_size, 0, 2)]
	for key in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		rt.add_theme_font_size_override(key, fs)
	rt.add_theme_color_override("default_color", INK)
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	rt.add_theme_constant_override("outline_size", 3 if Settings.sub_box < 40 else 0)
	var sp: Array = SPEAKERS.get(who, SPEAKERS["radio"])
	var col: Color = sp[1]
	var name_txt := String(sp[0]) if Settings.sub_names else ""
	var bb := ""
	var plain := text
	if who == "thought":
		bb = "[center][i][color=#%s]%s[/color][/i][/center]" % [col.to_html(false), _esc(text)]
	elif name_txt != "":
		bb = "[center][b][color=#%s]%s[/color][/b]   %s[/center]" % [col.to_html(false), name_txt, _esc(text)]
		plain = name_txt + "   " + text
	else:
		bb = "[center][color=#%s]%s[/color][/center]" % [col.lerp(INK, 0.5).to_html(false), _esc(text)]
	rt.text = bb
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
	rt.custom_minimum_size = Vector2(minf(w, WIDTH - 28.0), 0)
	panel.add_child(rt)
	_box.add_child(panel)
	_lines.append({"panel": panel, "label": rt, "t": hold})
	visible = Settings.subtitles


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


## Remove every line (a checkpoint restore, the menu).
func clear() -> void:
	for l in _lines:
		(l["panel"] as Control).queue_free()
	_lines.clear()


func _process(delta: float) -> void:
	visible = Settings.subtitles and not _lines.is_empty()
	for i in range(_lines.size() - 1, -1, -1):
		var l: Dictionary = _lines[i]
		l["t"] = float(l["t"]) - delta
		if float(l["t"]) <= 0.0:
			(l["panel"] as Control).queue_free()
			_lines.remove_at(i)
			continue
		var older := i < _lines.size() - 1
		(l["panel"] as Control).modulate.a = clampf(float(l["t"]) / 0.5, 0.0, 1.0) * (0.6 if older else 1.0)
	if _lines.is_empty():
		return
	var vs := get_viewport().get_visible_rect().size
	var h := _box.get_combined_minimum_size().y
	_box.size = Vector2(WIDTH, h)
	_box.position = Vector2(vs.x * 0.5 - WIDTH * 0.5, vs.y - BOTTOM - h)
