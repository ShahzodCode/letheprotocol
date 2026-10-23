extends Node
## Interior probe: `-- --script res://tests/interior_probe.gd [shot=<png>]` (a few seconds, headless unless shot=). Walks up to the first enterable
## building, checks that it streams in (alive, closed collider off, doors open to a ray, entrance path found, a path from the inside to the
## escape door's street), then goes away and checks it is freed and the building is closed again.
func run(m) -> void:
	Game.force_input = true
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.substr(5)
	var out := PackedStringArray()
	out.append("interiors planned: %d of %d buildings" % [City.interiors.size(), City.buildings.size()])
	if City.interiors.is_empty():
		print("INTERIOR PROBE FAIL: none planned")
		get_tree().quit(1)
		return
	var plan: Dictionary = City.interiors[0]
	var ent: Dictionary = plan["entrance"]
	var esc: Dictionary = plan["escape"]
	var pl: Player = m.player
	var outer: Vector3 = ent["outer"]
	for k in 90:
		pl.global_position = Vector3(outer.x, 0.1, outer.z)
		pl.velocity = Vector3.ZERO
		await get_tree().physics_frame
	var inter: Interiors = m.interiors
	var ok := true
	var alive := inter.alive.has(0)
	out.append("alive after 90 frames near it: %s (max alive %d, built %d)" % [alive, inter.max_alive_seen, inter.built_total])
	ok = ok and alive
	var space := get_viewport().world_3d.direct_space_state
	for d in [ent, esc]:
		var from: Vector3 = Vector3(d["outer"].x, 1.0, d["outer"].z)
		var inside: Vector2 = (d["centre"] as Vector2) - (d["n"] as Vector2) * 0.8
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(inside.x, 1.0, inside.y), 1)
		var hit := space.intersect_ray(q)
		var side_pt: Vector2 = (d["wall_pt"] as Vector2) + Vector2(-(d["n"] as Vector2).y, (d["n"] as Vector2).x) * 2.5
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(side_pt.x + (d["n"] as Vector2).x * 1.5, 1.0, side_pt.y + (d["n"] as Vector2).y * 1.5), Vector3(side_pt.x - (d["n"] as Vector2).x * 0.8, 1.0, side_pt.y - (d["n"] as Vector2).y * 0.8), 1)
		var hit2 := space.intersect_ray(q2)
		out.append("door side %d: ray through the doorway %s, ray at the wall beside it %s" % [d["side"], "BLOCKED" if not hit.is_empty() else "free", "hits" if not hit2.is_empty() else "MISSES"])
		ok = ok and hit.is_empty() and not hit2.is_empty()
	var far_street := outer + Vector3(0, 0, 0)
	var p_in := City.path(Vector3(outer.x, 0.1, outer.z) + (ent["n"] as Vector2).x * Vector3.RIGHT * 6.0, ent["in"])
	out.append("path from the street to just inside the entrance: %d waypoints, layer there %d (slot %d)" % [p_in.size(), City.layer_of(ent["in"]), plan["slot"]])
	ok = ok and p_in.size() > 0 and City.layer_of(ent["in"]) == int(plan["slot"])
	var p_out := City.path(ent["in"], esc["outer"])
	out.append("path from inside to the street at the escape door: %d waypoints" % p_out.size())
	ok = ok and p_out.size() > 0
	var shapes_n := 0
	for c in inter.get_children():
		if c is StaticBody3D:
			shapes_n = c.get_child_count()
	out.append("collision shapes in the interior body: %d (limit %d)" % [shapes_n, Interiors.MAX_SHAPES])
	ok = ok and shapes_n <= Interiors.MAX_SHAPES
	if shot != "":
		pl.global_position = Vector3(ent["in"].x, 0.1, ent["in"].z)
		pl.yaw = atan2(-(-(ent["n"] as Vector2)).x, -(-(ent["n"] as Vector2)).y)
		for k in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
	# away: it must be freed and the building closed again
	for k in 120:
		pl.global_position = Vector3(0, 0.1, 0)
		pl.velocity = Vector3.ZERO
		await get_tree().physics_frame
	var gone := not inter.alive.has(0)
	var q3 := PhysicsRayQueryParameters3D.create(Vector3(outer.x, 1.0, outer.z), Vector3((ent["centre"] as Vector2).x - (ent["n"] as Vector2).x * 0.8, 1.0, (ent["centre"] as Vector2).y - (ent["n"] as Vector2).y * 0.8), 1)
	var closed := not space.intersect_ray(q3).is_empty()
	out.append("after walking away: freed %s, building closed again %s (freed %d)" % [gone, closed, inter.freed_total])
	ok = ok and gone and closed
	for line in out:
		print(line)
	print("rejected: ", CityInteriors.stats)
	print("INTERIOR PROBE ", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
