extends Node
## Reads the clips in models/anims and the three rigs they will go onto: `-- --script res://tests/anim_probe.gd`. Writes .shots/anim_probe.txt
## (bones, clip names and lengths, how far the hips travel in each clip: 0 means the clip is in place).


func run(_m) -> void:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://models/anims")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".fbx"):
			files.append(f)
	files.sort()
	for f in files:
		out.append("=== %s" % f)
		_probe("res://models/anims/" + f, out, true)
	for id in ["marksman", "agile", "soldier"]:
		out.append("=== rig %s" % id)
		_probe(String(CharModel.DEFS[id]["path"]), out, false)
	var target := OS.get_environment("PROBE_OUT")
	var fa := FileAccess.open(target if target != "" else ProjectSettings.globalize_path("res://.shots/anim_probe.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(out))
	fa.close()
	get_tree().quit()


func _probe(path: String, out: PackedStringArray, clips: bool) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		out.append("  could not load")
		return
	var root := ps.instantiate() as Node3D
	var sks := root.find_children("*", "Skeleton3D", true, false)
	out.append("  skeletons: %d, root scale %s" % [sks.size(), str(root.scale)])
	for sk in sks:
		var s := sk as Skeleton3D
		var names := PackedStringArray()
		for i in s.get_bone_count():
			names.append(s.get_bone_name(i))
		out.append("  skeleton %s: %d bones, node scale %s" % [s.name, s.get_bone_count(), str(s.scale)])
		out.append("  bones: " + ", ".join(names))
		if not clips:
			var tree := PackedStringArray()
			for i in s.get_bone_count():
				var pi := s.get_bone_parent(i)
				var rt := s.get_bone_rest(i)
				tree.append("%s<-%s [rest o (%.2f %.2f %.2f) scale %.2f]" % [s.get_bone_name(i), s.get_bone_name(pi) if pi >= 0 else "-", rt.origin.x, rt.origin.y, rt.origin.z, rt.basis.get_scale().x])
			out.append("  tree: " + "; ".join(tree))
		var hips := -1
		for i in s.get_bone_count():
			if String(s.get_bone_name(i)).containsn("hips") and hips < 0:
				hips = i
		if hips >= 0:
			out.append("  hips bone '%s' rest origin %s, global rest y %.3f" % [s.get_bone_name(hips), str(s.get_bone_rest(hips).origin), s.get_bone_global_rest(hips).origin.y])
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	out.append("  meshes: %d" % meshes.size())
	var aps := root.find_children("*", "AnimationPlayer", true, false)
	for ap in aps:
		var p := ap as AnimationPlayer
		for an in p.get_animation_list():
			var a := p.get_animation(an)
			var pos_tracks := 0
			var rot_tracks := 0
			var hips_move := ""
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var ty := a.track_get_type(t)
				if ty == Animation.TYPE_POSITION_3D:
					pos_tracks += 1
				elif ty == Animation.TYPE_ROTATION_3D:
					rot_tracks += 1
				if ty == Animation.TYPE_POSITION_3D and tp.containsn("hips") and hips_move == "":
					var n := a.track_get_key_count(t)
					var v0: Vector3 = a.track_get_key_value(t, 0)
					var v1: Vector3 = a.track_get_key_value(t, n - 1)
					var lo := v0
					var hi := v0
					for k in n:
						var v: Vector3 = a.track_get_key_value(t, k)
						lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
						hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
					hips_move = "hips keys %d, first %s, last %s, range %s" % [n, str(v0), str(v1), str(hi - lo)]
			out.append("  clip '%s': %.2f s, %d tracks (%d pos, %d rot), loop %d%s" % [an, a.length, a.get_track_count(), pos_tracks, rot_tracks, a.loop_mode, (", " + hips_move) if clips else ""])
			if not clips:
				continue
	root.free()
