extends Node
## Sanity numbers of the retargeted clips: `-- --script res://tests/anim_check.gd` (set PROBE_OUT to a file path to write there).
## For each rig and clip (the M4 soldier too): height (m, world) of the head and hips, the hands and the rifle's muzzle (x right, y up, -z forward),
## at start / middle / end, and how long the first model of each rig took to build (the clips are retargeted then).

var _tip: Node3D


func run(_m) -> void:
	var out := PackedStringArray()
	for id in ["marksman", "agile", "soldier"]:
		var t0 := Time.get_ticks_usec()
		var cm := CharModel.make(id, 1.75)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		get_tree().root.add_child.call_deferred(cm)
		await get_tree().process_frame
		await get_tree().process_frame
		var gun := Node3D.new()
		_tip = Node3D.new()
		_tip.position = GunModels.muzzle("rifle") - GunModels.grip("rifle")
		gun.add_child(_tip)
		cm.hold(gun)
		out.append("=== %s: built in %.0f ms, new_clips %s, clips %s" % [id, ms, str(cm.new_clips), str(cm.clip_of.keys())])
		var sk := cm.skeleton
		var head := sk.find_bone(String(cm.def["head"]))
		var hips := sk.find_bone(String(cm.def["hips"]))
		var hand := sk.find_bone(String(cm.def["hand"]))
		out.append("  rest: %s" % _pose(cm, sk, head, hips, hand, true))
		var names: Array = CharModel.NEW_CLIPS.keys()
		if id == "soldier":
			names.append_array(CharModel.BORROWED.keys())
		for logical in names:
			if not cm.has_anim(logical):
				out.append("  %s: MISSING" % logical)
				continue
			var len := cm.clip_length(logical)
			var line := "  %-10s %.2f s:" % [logical, len]
			for f in [0.0, 0.5, 1.0]:
				cm.player.play(cm.clip_of[logical], 0.0)
				cm.player.seek(len * f, true)
				cm.player.advance(0.0)
				await get_tree().process_frame
				line += "  [%s] %s" % [str(f), _pose(cm, sk, head, hips, hand, false)]
			out.append(line)
		cm.queue_free()
	var target := OS.get_environment("PROBE_OUT")
	var fa := FileAccess.open(target if target != "" else ProjectSettings.globalize_path("res://.shots/anim_check.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(out))
	fa.close()
	get_tree().quit()


func _pose(cm: CharModel, sk: Skeleton3D, head: int, hips: int, hand: int, rest: bool) -> String:
	var xf := cm.global_transform.affine_inverse() * sk.global_transform
	var h: Vector3 = (xf * (sk.get_bone_global_rest(head) if rest else sk.get_bone_global_pose(head))).origin
	var p: Vector3 = (xf * (sk.get_bone_global_rest(hips) if rest else sk.get_bone_global_pose(hips))).origin
	var r: Vector3 = (xf * (sk.get_bone_global_rest(hand) if rest else sk.get_bone_global_pose(hand))).origin
	var li: int = cm.roles.get("LeftHand", hand)
	var l: Vector3 = (xf * (sk.get_bone_global_rest(li) if rest else sk.get_bone_global_pose(li))).origin
	var tip := cm.global_transform.affine_inverse() * _tip.global_position
	return "head y %.2f hips y %.2f | handR x %.2f y %.2f z %.2f | handL x %.2f y %.2f z %.2f | muzzle x %.2f y %.2f z %.2f" % [h.y, p.y, r.x, r.y, r.z, l.x, l.y, l.z, tip.x, tip.y, tip.z]
