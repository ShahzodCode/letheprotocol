extends Node
## Where do the draw calls and triangles come from? `-- --script res://tests/perf_groups.gd [out=<json>]` (windowed, 1280x720)
## At a few spots (the Institute exit looking up the avenue, the densest point, a side street) it measures draw calls and primitives of the
## whole view, then hides ONE group of nodes at a time and prints what disappeared: buildings (the window-shader MultiMeshes), scenery
## (flat MultiMeshes: decals, props, balconies, awnings, trees), cars, characters (skinned meshes), sites and fires, the rest.
## Used for the building pass (docs/performance.md "city pass"): compare the building and scenery rows before and after.
const GROUPS := ["buildings", "scenery", "cars", "characters", "other"]
var out_path := "res://.shots/perf_groups.json"


func run(m) -> void:
	Game.force_input = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_path = a.substr(4)
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.shadows = 2
	Settings.aa = 0
	Settings.scale_pct = 100
	Settings.view = 1
	Settings.apply(get_tree(), m)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1280, 720))
	Engine.max_fps = 0
	m.hud.visible = false
	for n in Game.enemies + Game.civilians:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_DISABLED          # frozen: the counts are about the view, not the AI
	var pl: Player = m.player
	var spots := {
		"exit_avenue": [City.INSTITUTE_EXIT + Vector3(0, 0.1, 0), 0.0],
		"central_avenue": [Vector3(0, 0.1, 120), 0.0],
		"cross_street": [Vector3(-60, 0.1, 70), PI * 0.5],
		"side_street": [Vector3(-80, 0.1, -110), 0.0],
	}
	var result := {}
	var nodes := _classify(m)
	print("nodes: ", {"buildings": nodes["buildings"].size(), "scenery": nodes["scenery"].size(), "cars": nodes["cars"].size(), "characters": nodes["characters"].size(), "other": nodes["other"].size()})
	for k in spots:
		var f: Vector3 = spots[k][0]
		var yaw: float = spots[k][1]
		for i in 90:
			_hold(pl, f, yaw)
			await get_tree().process_frame
		var base := _read()
		var row := {"all": base}
		for g in GROUPS:
			for n in nodes[g]:
				if is_instance_valid(n):
					(n as Node3D).visible = false
			for i in 3:
				_hold(pl, f, yaw)
				await get_tree().process_frame
			var s := _read()
			row[g] = {"draws": base["draws"] - s["draws"], "prims": base["prims"] - s["prims"]}
			for n in nodes[g]:
				if is_instance_valid(n):
					(n as Node3D).visible = true
			for i in 2:
				_hold(pl, f, yaw)
				await get_tree().process_frame
		result[k] = row
		print("%-15s all: %d draws, %d prims | hidden alone -> " % [k, base["draws"], base["prims"]], _fmt(row))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify({"nodes": {"buildings": nodes["buildings"].size(), "scenery": nodes["scenery"].size()}, "spots": result}, "\t"))
		fa.close()
	get_tree().quit()


func _fmt(row: Dictionary) -> String:
	var s := ""
	for g in GROUPS:
		s += "%s -%d draws -%d prims  " % [g, row[g]["draws"], row[g]["prims"]]
	return s


func _read() -> Dictionary:
	return {"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), "prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))}


func _hold(pl: Player, f: Vector3, yaw: float) -> void:
	pl.health = 100.0
	pl.velocity = Vector3.ZERO
	pl.global_position = f
	pl.yaw = yaw
	pl.pitch = 0.0
	Game.dead = false


## Sorts every drawn node of the city into a group. Buildings are the MultiMeshes drawn with the window shader (or its far-LOD twin).
func _classify(m) -> Dictionary:
	var out := {"buildings": [], "scenery": [], "cars": [], "characters": [], "other": []}
	var stack: Array = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			var mat: Material = mmi.material_override
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and (mat as ShaderMaterial).shader.code.contains("wpos") or mmi.has_meta("building_lod"):
				out["buildings"].append(n)
			elif n.get_parent() is World and mmi.multimesh != null and mmi.multimesh.mesh is ArrayMesh and mmi.multimesh.instance_count <= 400 and String(n.name).begins_with("Car"):
				out["cars"].append(n)
			elif mmi.multimesh != null and (mmi.multimesh.mesh is BoxMesh or mmi.multimesh.mesh is CylinderMesh or mmi.multimesh.mesh is SphereMesh):
				out["scenery"].append(n)
			else:
				out["other"].append(n)
		elif n is MeshInstance3D:
			var p := n.get_parent()
			var ischar := false
			while p != null and p != m:
				if p is Enemy or p is Civilian:
					ischar = true
					break
				p = p.get_parent()
			if ischar:
				out["characters"].append(n)
			else:
				out["other"].append(n)
	return out
