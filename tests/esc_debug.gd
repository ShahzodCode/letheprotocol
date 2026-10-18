extends Node
## Walks up the first fire escape and prints where the player is every half second. `-- --script res://tests/esc_debug.gd`
func run(m) -> void:
	Game.force_input = true
	await get_tree().physics_frame
	var pl: Player = m.player
	for e in Game.enemies:
		e.stun = 999.0
		e.global_position = Vector3(260.0, 0.1, 0.0)
	var es: Dictionary = City.escapes[0]
	print("escape 0 ", es)
	var st: Vector3 = es["start"]
	var side: int = es["side"]
	var d := Vector2(1, 0) if side < 2 else Vector2(0, 1)
	pl.global_position = Vector3(st.x - d.x * 0.3, 0.1, st.z - d.y * 0.3)
	pl.yaw = atan2(-d.x, -d.y)
	pl.rotation.y = pl.yaw
	pl.velocity = Vector3.ZERO
	for k in 40:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for i in 360:
		await get_tree().physics_frame
		if i % 40 == 0:
			print("  t ", i, " pos ", pl.global_position, " floor ", pl.is_on_floor(), " vel ", pl.velocity)
	Input.action_release("move_forward")
	# what is around the stair: ramps near the start
	for r in City.ramps:
		var a: Vector3 = r["a"]
		var b: Vector3 = r["b"]
		if a.distance_to(st) < 12.0 or b.distance_to(st) < 12.0:
			print("  ramp ", a, " -> ", b, " width ", r["width"])
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(-121.2, 1.2, -205.6539), Vector3(-119.5, 1.2, -205.6539), 1)
	var h := space.intersect_ray(q)
	if not h.is_empty():
		var col: Node = h["collider"]
		print("  hit ", col, " at ", h["position"], " meta ", col.get_meta_list())
		for c in col.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).global_position.distance_to(h["position"]) < 4.0:
				print("   shape ", (c as CollisionShape3D).shape, " at ", (c as CollisionShape3D).global_position, " size ", (c as CollisionShape3D).shape.size if (c as CollisionShape3D).shape is BoxShape3D else "")
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(-121.2, 0.3, -205.6539), Vector3(-119.5, 0.3, -205.6539), 1)
	var h2 := space.intersect_ray(q2)
	if not h2.is_empty():
		var col2: Node = h2["collider"]
		print("  low hit ", col2, " at ", h2["position"], " normal ", h2["normal"])
		for c2 in col2.get_children():
			if c2 is CollisionShape3D and (c2 as CollisionShape3D).global_position.distance_to(h2["position"]) < 4.0:
				print("   shape ", (c2 as CollisionShape3D).shape, " at ", (c2 as CollisionShape3D).global_position, " size ", (c2 as CollisionShape3D).shape.size if (c2 as CollisionShape3D).shape is BoxShape3D else "")
	get_tree().quit()
