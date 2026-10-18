extends Node
## Runs one selftest function alone: -- --script res://tests/one.gd <function name>[,<another>,...]
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
	for fn in String(OS.get_cmdline_user_args()[-1]).split(","):       # one name, or several in a row: `mission_and_map_tests,lander_tests`
		await st.call(fn)
	print("RESULT: %d passed, %d failed" % [st.passes, st.fails])
	get_tree().quit(1 if st.fails > 0 else 0)
