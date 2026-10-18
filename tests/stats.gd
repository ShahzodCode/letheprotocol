extends Node
## Prints how much the generated city holds and where the interesting buildings stand:  `-- --script res://tests/stats.gd`
## Each "view" line can be pasted into tests/view_at.gd as `from>look`.
func run(m) -> void:
	var t0 := Time.get_ticks_msec()
	City.generate()
	print("City.generate: ", Time.get_ticks_msec() - t0, " ms (the whole data pass: streets, buildings, damage, trees, cars, obstacles, roads, climbing, navigation)")
	for k in Scn.parts:
		print("parts ", k, " ", (Scn.parts[k] as Array).size())
	for k in Scn.decals:
		print("decals ", k, " ", (Scn.decals[k] as Array).size())
	print("colliders ", Scn.colliders.size(), " cyl ", Scn.cyl_colliders.size(), " kerbs ", Scn.kerbs.size(), " blocks ", Scn.blocks.size(), " fires ", Scn.fires.size())
	print("buildings ", City.buildings.size(), " cars ", City.cars.size(), " trees ", City.trees.size(), " war obstacles ", CityWar.war_obstacles.size())
	print("trees burning ", CityWar.burning_trees, " fallen ", CityWar.fallen_trees, " stumps ", CityWar.stump_trees, " damaged cars ", CityWar.damaged_cars)
	print("buildings heavy ", CityBuildings.heavy_count, " light ", CityBuildings.light_count, " intact ", CityBuildings.intact_count, " burning ", CityBuildings.burning_count, " access ", CityBuildings.access_count)
	print("reachable ", City.reachable_fraction(City.START_POS))
	var cls := {}
	for st in City.streets:
		cls[st["cls"]] = int(cls.get(st["cls"], 0)) + 1
	print("streets by class ", cls)
	var counts := {}
	for c in City.cars:
		counts[c["dmg"]] = int(counts.get(c["dmg"], 0)) + 1
	print("car damage ", counts)
	var seen := {}
	for b in City.buildings:
		var key := String(b.get("arch_damage", "")) + ("/burn" if b.get("burning", false) else "") + "/" + String(b.get("arch", ""))
		if b.get("border", false) or not b.has("arch") or seen.has(key):
			continue
		seen[key] = true
		var r: Rect2 = b["rect"]
		var sides := CityBuildings.street_sides(r)
		var s: int = sides[0][1]
		var from := CityBuildings.facade_pt(r, s, CityBuildings._side_len(r, s) * 0.5, 0.1, clampf(float(sides[0][0]) - 1.5, 6.0, 30.0))
		var look := CityBuildings.facade_pt(r, s, CityBuildings._side_len(r, s) * 0.5, minf(float(b["h"]) * 0.55, 18.0), 0.0)
		print("view ", key, " h=", snappedf(float(b["h"]), 0.1), " dmg=", snappedf(float(b["damage"]), 0.01), "  ", "%.1f,0.1,%.1f>%.1f,%.1f,%.1f" % [from.x, from.z, look.x, look.y, look.z])
	for ob in CityWar.war_obstacles:
		pass
	print("tunnels ", City.tunnels.size(), " bridges ", City.bridges.size(), " passages ", City.crouch_passages.size(), " ladders ", City.ladders.size(), " escapes ", City.escapes.size())
	for t in City.tunnels:
		print("tunnel ", t["a"], " -> ", t["b"], " length ", t["length"])
	for br in City.bridges:
		print("bridge ", br["p0"], " -> ", br["p1"], " y ", br["y"], " ", br["kind"], " broken ", br["broken"])
	for p in City.crouch_passages:
		print("passage ", p["kind"], " ", p["pos"], " width ", p["width"], " along_x ", p["along_x"])
	for l in City.ladders:
		print("ladder ", l["kind"], " ", l["pos"], " n ", l["n"], " top ", l["top"])
	for e in City.escapes:
		print("escape ", e["start"], " side ", e["side"], " top ", e["top"])
	get_tree().quit()
