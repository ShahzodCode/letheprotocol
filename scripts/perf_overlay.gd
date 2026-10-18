class_name PerfOverlay
extends Label
## F3 debug overlay (HUD owns it). Hidden = not processing at all, so it costs nothing. Shown: refreshes 4 times a second;
## the node walk that counts lights and particle systems runs once a second.

const REFRESH := 0.25
const SCAN_EVERY := 4              # refreshes between node walks
const MB := 1048576.0

var _t := 0.0
var _sum := 0.0
var _n := 0
var _max := 0.0
var _scan_i := 0
var lights := 0
var lights_total := 0
var particles := 0
var particles_total := 0
var _head := ""


func _init() -> void:
	visible = false
	set_process(false)
	position = Vector2(12, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("normal", sb)
	var g: Dictionary = Game.gpu
	_head = "%s  [%s, %s]\n%s %s | %s | Godot %s%s" % [g.get("name", "?"), g.get("type", "?"), g.get("vendor", "?"), g.get("driver", "?"), "(" + String(g.get("method", "?")) + ")", g.get("os", "?"), g.get("godot", "?"), "" if Game.gpu_is_nvidia else "\n!! NOT THE NVIDIA GPU - see README"]


func _ready() -> void:
	set_process(visible)        # Node enables processing on ready when _process exists


func toggle() -> void:
	visible = not visible
	set_process(visible)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)
	if visible:
		_t = REFRESH
		_scan_i = SCAN_EVERY


func _process(delta: float) -> void:
	_sum += delta
	_n += 1
	_max = maxf(_max, delta)
	_t += delta
	if _t < REFRESH:
		return
	_t = 0.0
	_scan_i += 1
	if _scan_i >= SCAN_EVERY:
		_scan_i = 0
		lights = 0
		lights_total = 0
		particles = 0
		particles_total = 0
		_scan(get_tree().root)
	var avg := _sum / float(maxi(_n, 1)) * 1000.0
	var vp := get_viewport().get_viewport_rid()
	var awake := 0
	var hunting := 0
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			awake += 1
			if en.state != Enemy.State.WANDER and en.state != Enemy.State.SUSPICIOUS:
				hunting += 1
	var civs := 0
	for c in Game.civilians:
		var cv := c as Civilian
		if is_instance_valid(cv) and cv.state != Civilian.State.DEAD:
			civs += 1
	var last := "none"
	if not Game.hitches.is_empty():
		var h: Dictionary = Game.hitches[Game.hitches.size() - 1]
		last = "%.0f ms at %.0fs (%s)  total %d" % [h["ms"], h["t"], ", ".join(h["tags"]), Game.hitches.size()]
	text = "%s\n\nFPS %d   frame %.1f ms avg, %.1f worst\nprocess %.2f ms   physics %.2f ms\nrender cpu %.1f ms   gpu %.1f ms\ndraw calls %d   primitives %d   objects %d\nvideo mem %.0f MB (tex %.0f, buf %.0f)\nenemies %d alive, %d hunting   civilians %d\nlights %d on / %d   particle systems %d on / %d\nphysics bodies active %d   pairs %d\nnodes %d   objects %d\nlast hitch: %s" % [
		_head, Engine.get_frames_per_second(), avg, _max * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / MB, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / MB,
		awake, hunting, civs,
		lights, lights_total, particles, particles_total,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		last]
	_sum = 0.0
	_n = 0
	_max = 0.0


func _scan(n: Node) -> void:
	if n is Light3D:
		lights_total += 1
		if (n as Light3D).is_visible_in_tree() and (n as Light3D).light_energy > 0.0:
			lights += 1
	elif n is CPUParticles3D:
		particles_total += 1
		if (n as CPUParticles3D).emitting and (n as CPUParticles3D).is_visible_in_tree():
			particles += 1
	elif n is GPUParticles3D:
		particles_total += 1
		if (n as GPUParticles3D).emitting and (n as GPUParticles3D).is_visible_in_tree():
			particles += 1
	for c in n.get_children():
		_scan(c)
