extends Node
## Prints what one civilian costs to draw (meshes, surfaces, skeleton bones): `-- --script res://tests/civ_probe.gd`
func run(m) -> void:
	Game.force_input = true
	await get_tree().physics_frame
	var tot_vis := 0
	for c in Game.civilians.slice(0, 3):
		var cv := c as Civilian
		var meshes := 0
		var surfs := 0
		var hidden := 0
		for mi in cv._meshes:
			if not mi.is_visible_in_tree():
				hidden += 1
				continue
			meshes += 1
			surfs += mi.mesh.get_surface_count() if mi.mesh != null else 0
		print("civilian ", cv.look_seed, " outfit meshes: ", cv._meshes.size(), " visible ", meshes, " surfaces ", surfs, " hidden ", hidden, " bones ", cv.model.skeleton.get_bone_count() if cv.model.skeleton != null else -1)
		for mi in cv._meshes:
			if mi.is_visible_in_tree():
				print("   ", mi.name, " surfaces ", mi.mesh.get_surface_count(), " verts ", (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	get_tree().quit()
