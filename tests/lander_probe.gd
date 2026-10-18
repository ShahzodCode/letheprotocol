extends Node
## Prints the Chapter One "Lander" set piece: the lookout roof and its way up, the park, the lander, the balcony and its stair, the exhausted pair's
## spot: `-- --script res://tests/lander_probe.gd`
func run(m) -> void:
	Game.force_input = true
	await get_tree().physics_frame
	var lk := CityStory.lookout
	print("lookout ", {} if lk.is_empty() else {"kind": lk["kind"], "side": lk["side"], "top": lk["top"], "foot": lk["foot"], "roof": lk["roof"], "rect": (lk["building"] as Dictionary)["rect"]})
	print("lander at ", City.LANDER_POS, " visible ", m.world.lander.visible, " landed ", m.world.lander.landed)
	var way := City.path(City.HOME_POS, lk["foot"]) if not lk.is_empty() else PackedVector3Array()
	print("path home -> lookout foot points ", way.size())
	get_tree().quit()
