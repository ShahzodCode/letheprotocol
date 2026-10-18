extends Node
## Prints what the Chapter One story dressing produced (tram, stalls, first lane, lone soldier, dead, roles): `-- --script res://tests/story_probe.gd`
func run(m) -> void:
	Game.force_input = true
	await get_tree().physics_frame
	print("tram ", CityStory.tram)
	print("stalls ", CityStory.stalls.size())
	for s in CityStory.stalls:
		print("  stall ", s["pos"])
	var brng := RandomNumberGenerator.new()
	brng.seed = 7117
	print("body spots ", CityStory.body_spots(brng))
	var lane := CityStory.first_lane()
	print("lane ", lane)
	var lone := CityStory.lone_soldier_spot()
	print("lone ", lone)
	print("roles ", m.story_roles)
	var way := City.path(City.INSTITUTE_EXIT, City.HOME_POS)
	var total := 0.0
	for i in way.size() - 1:
		total += way[i].distance_to(way[i + 1])
	print("way length ", total, " points ", way.size())
	var dead := 0
	for b in Enemy.bodies:
		if b is Civilian:
			dead += 1
	print("dead civilians ", dead, " living ", Game.civilians.size(), " enemies ", Game.enemies.size())
	for e in Game.enemies:
		if (e as Enemy).uid in m.story_roles:
			print("role ", m.story_roles[e.uid], " kind ", e.kind, " pos ", e.global_position, " ranged ", e.ranged, " weapon ", e.weapon_id, " run ", e.run_speed)
	get_tree().quit()
