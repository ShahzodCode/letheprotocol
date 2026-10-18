extends Node
## Runs the "The Lander, part two" selftest sections alone: puts the story on THIN OUT THE GUARDS with the ten guards at the ramp, finishes it
## (so ESCAPE INTO THE LANES starts and the chase begins) and runs chase_start_checks + chase_tests.   -- --script res://tests/chase_run.gd
func run(m) -> void:
	var st = load("res://tests/selftest.gd").new()
	add_child(st)
	st.main = m
	st.player = m.player
	st.all = Game.enemies.duplicate()
	Game.force_input = true
	await get_tree().physics_frame
	for en in st.all:
		st.place(en, st.park_pos(en), true)
	await st.frames(30)
	await st.clear_civilians()
	var ms: Mission = Game.mission
	ms.index = m._objective_index("park_fight")
	m.world.lander.land_now()
	m.park_fight.spawn_guards()
	await st.frames(10)
	var killed := 0
	for g in m.park_fight.guards().duplicate():
		if killed < 4:
			st.kill(g)
			killed += 1
	st.player.weapons.loadout["rifle"].append(Weapons.new_weapon("sniper"))
	await st.secs(0.8)
	st.check("the story is on ESCAPE INTO THE LANES", String(ms.active()["id"]) == "escape_lanes", str(ms.active().get("id")))
	await st.chase_start_checks()
	await st.chase_tests()
	print("RESULT: %d passed, %d failed" % [st.passes, st.fails])
	get_tree().quit(1 if st.fails > 0 else 0)
