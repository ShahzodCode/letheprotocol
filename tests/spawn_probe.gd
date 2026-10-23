extends Node
## Where the roaming soldiers stand: `-- --script res://tests/spawn_probe.gd` (headless, seconds). Prints each roamer (group, kind, street width, patrol / post /
## sitting), the share on wide streets, single soldiers, and the alley-mouth rule (mouths with 2 or more roamers within 25 m).
func run(m) -> void:
	await get_tree().physics_frame
	var roam: Array = []
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and (en.group >= 100 and en.group < 200 or en.lone_shout):
			roam.append(en)
	var wide := 0
	var lone := 0
	for en in roam:
		var w := City.street_width_at(en.global_position)
		if en.lone_shout:
			lone += 1
		elif w >= 11.0:
			wide += 1
		print("  %-9s group %3d  street %2.0f m  patrol %d  post %s  at (%.0f, %.0f)" % [en.kind, en.group, w, en.patrol.size(), en.post, en.global_position.x, en.global_position.z])
	var bad := 0
	for mo in City.alley_mouths():
		var mp: Vector2 = mo["pos"]
		var n := 0
		for en in roam:
			if Vector2(en.global_position.x - mp.x, en.global_position.z - mp.y).length() < m.EXIT_CLEAR:
				n += 1
		if n >= 2:
			bad += 1
	print("roamers %d (single %d, in groups %d), of all %d soldiers; alley mouths %d, with 2+ roamers within %d m: %d" % [roam.size(), lone, roam.size() - lone, Game.enemies.size(), City.alley_mouths().size(), int(m.EXIT_CLEAR), bad])
	get_tree().quit()
