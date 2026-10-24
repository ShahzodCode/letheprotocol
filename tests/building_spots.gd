extends Node
## Lots for the model buildings (CityModels.LOT_SPOTS): `-- --script res://tests/building_spots.gd [id=<model>] [n=<count>]` (headless, seconds).
## For every lot model, the plain generated lots it fits (CityModels.fit_lot) nearest the walk home (Institute doorway -> x = 0 -> home),
## with how much of the lot it fills and the distance to the nearest battle site (lots far from the sites stay intact). Spots already in
## LOT_SPOTS are taken and reported first.

const ROUTE := [Vector2(-30.0, 240.0), Vector2(0.0, 235.0), Vector2(0.0, -30.0), Vector2(16.0, -30.0)]


func run(_m) -> void:
	await get_tree().physics_frame
	var only := ""
	var count := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("id="):
			only = a.substr(3)
		elif a.begins_with("n="):
			count = int(a.substr(2))
	for p in CityModels.placed:
		print("PLACED %s at (%.0f, %.0f) %.0f x %.0f scale %.2f ring '%s'" % [p["id"], (p["rect"] as Rect2).get_center().x,
			(p["rect"] as Rect2).get_center().y, (p["rect"] as Rect2).size.x, (p["rect"] as Rect2).size.y, p["scale"], p["ring"]])
	for id in CityModels.MODELS:
		if CityModels.MODELS[id].has("scale") or (only != "" and id != only):
			continue
		var rows: Array = []
		for b in City.buildings:
			if not _plain(b):
				continue
			var f := CityModels.fit_lot(b, id)
			if f.is_empty():
				continue
			var fp: Rect2 = b["rect"]
			var c := fp.get_center()
			var fill := (f["rect"] as Rect2).get_area() / fp.get_area()
			var site := INF
			for s in City.sites:
				site = minf(site, c.distance_to(Vector2((s["center"] as Vector3).x, (s["center"] as Vector3).z)))
			rows.append([_route_dist(c), "  [\"%s\", %.1f, %.1f],   # lot %.0f x %.0f, scale %.2f, fill %.0f%%, h %.0f, side %d, route %.0f m, site %.0f m" % [
				id, c.x, c.y, fp.size.x, fp.size.y, f["scale"], fill * 100.0, f["h"], f["side"], _route_dist(c), site]])
		rows.sort_custom(func(a, b): return a[0] < b[0])
		print("FIT %s: %d lots" % [id, rows.size()])
		for i in mini(count, rows.size()):
			print(rows[i][1])
	get_tree().quit()


## A plain lot building as CityModels._plain_lot_at sees it during generation: by now CityBuildings / CityClimb have added their own keys.
func _plain(b: Dictionary) -> bool:
	for k in b:
		if not String(k) in ["rect", "boxes", "style", "color", "h", "damage", "burning", "seed", "arch", "access", "bid", "one_box", "ground_box", "flat_top", "balconies", "roof_pitched"]:
			return false
	return not bool(b.get("access", false))


func _route_dist(p: Vector2) -> float:
	var best := INF
	for i in ROUTE.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ROUTE[i], ROUTE[i + 1])))
	return best
