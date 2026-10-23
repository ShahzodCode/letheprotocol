extends Node
## Smoke check: `-- --script res://tests/smoke.gd`. The city, player, HUD and enemies were built by Main; wait about 3 s of game time and
## fail if something basic is missing. Script errors are caught by tests/smoke.ps1 (it greps the engine's error output).


func run(m) -> void:
	Game.force_input = true
	for i in 300:
		await get_tree().physics_frame
	var problems: Array = []
	if m.player == null or not is_instance_valid(m.player):
		problems.append("no player")
	if Game.enemies.is_empty():
		problems.append("no enemies")
	if m.mission == null:
		problems.append("no mission")
	if City.buildings.is_empty():
		problems.append("no buildings")
	if City.reachable_fraction(City.START_POS) < 0.95:
		problems.append("city is not connected (reachable fraction %.3f)" % City.reachable_fraction(City.START_POS))
	if problems.is_empty():
		print("SMOKE OK: %d enemies, %d buildings" % [Game.enemies.size(), City.buildings.size()])
	else:
		print("SMOKE FAIL: ", ", ".join(problems))
	get_tree().quit(1 if not problems.is_empty() else 0)
