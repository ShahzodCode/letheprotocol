extends Node
## What occupies the lookout fire escape's ground? `-- --script res://tests/lookout_occ.gd`
func run(m) -> void:
	await get_tree().physics_frame
	var area := Rect2(44.0, -50.0, 8.0, 16.0)
	var seen := {}
	for k in CityWar.occ.cells:
		for o in CityWar.occ.cells[k]:
			if (o as Rect2).intersects(area) and not seen.has(o):
				seen[o] = true
				print("occ ", o)
	for ob in City.obstacles:
		if (ob["rect"] as Rect2).intersects(area):
			print("obstacle ", ob.get("kind"), " ", ob["rect"])
	for s in City.streets:
		if (s["rect"] as Rect2).intersects(area):
			print("street ", s["rect"], " ", s["cls"])
	get_tree().quit()
