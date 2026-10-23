extends Node
## What the city is made of: `-- --script res://tests/scene_counts.gd` (headless, a few seconds). Scenery parts by mesh type, balconies and
## roof dressing, buildings by design, colliders. Handy before / after a trim of the decoration.
func run(_m) -> void:
	await get_tree().physics_frame
	var tri := {"box": 12, "cyl": 28, "sphere": 96, "cone": 28, "col": 20, "fire": 96, "glow": 12, "glass": 12}
	var total := 0
	for k in Scn.parts:
		var n: int = (Scn.parts[k] as Array).size()
		total += n * int(tri.get(k, 12))
		print("parts %-7s %5d  (~%d tris)" % [k, n, n * int(tri.get(k, 12))])
	print("scenery triangles ~%d; colliders %d box + %d cyl" % [total, Scn.colliders.size(), Scn.cyl_colliders.size()])
	var designs := {}
	var boxes := 0
	for b in City.buildings:
		designs[String(b.get("arch", "?"))] = int(designs.get(String(b.get("arch", "?")), 0)) + 1
		boxes += (b["boxes"] as Array).size()
	print("buildings %d, boxes %d, by design %s" % [City.buildings.size(), boxes, str(designs)])
	get_tree().quit()
