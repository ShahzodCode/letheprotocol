extends Node
## Prints where the rifle's grip sits in the right hand of the marksman and agile rigs (rotation as a quaternion, origin in metres):
## `-- --script res://tests/hand_fit_probe.gd` with PROBE_OUT set to a file path.


func run(_m) -> void:
	var out := PackedStringArray()
	for id in ["marksman", "agile"]:
		var cm := CharModel.make(id, 1.75)
		get_tree().root.add_child.call_deferred(cm)
		await get_tree().process_frame
		await get_tree().process_frame
		var rel := cm.hand_fit()
		var upm := cm.global_transform.basis.get_scale().x / cm.hand_node.global_transform.basis.get_scale().x
		var q := Quaternion(rel.basis.orthonormalized())
		out.append("%s: upm %.4f quaternion (%.5f, %.5f, %.5f, %.5f) origin metres (%.5f, %.5f, %.5f) scale %.4f" % [id, upm, q.x, q.y, q.z, q.w,
				rel.origin.x / upm, rel.origin.y / upm, rel.origin.z / upm, rel.basis.get_scale().x / upm])
		cm.queue_free()
	var fa := FileAccess.open(OS.get_environment("PROBE_OUT"), FileAccess.WRITE)
	fa.store_string("\n".join(out))
	fa.close()
	get_tree().quit()
