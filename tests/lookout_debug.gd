extends Node
## Why does (or doesn't) the lookout fire escape fit? `-- --script res://tests/lookout_debug.gd`
func run(m) -> void:
	await get_tree().physics_frame
	var b: Dictionary = {}
	for o in City.buildings:
		if o.has("lookout_plot"):
			b = o
	var r: Rect2 = b["rect"]
	print("old block ", r, " access ", b.get("access"), " special ", b.get("special"), " lookout ", b.get("lookout"))
	for sd in CityBuildings.street_sides(r):
		print("  side ", sd[1], " street width ", sd[0], " len ", CityBuildings._side_len(r, int(sd[1])))
	for s in [3]:
		var len := CityBuildings._side_len(r, s)
		var u := 2.2
		while u <= len - CityClimb.ESCAPE_RUN - CityClimb.ESCAPE_LANDING - 0.6:
			var foot := CityClimb._escape_footprint(r, s, u)
			print("  u ", u, " foot ", foot, " occ ", CityWar.occ.hits(foot, 0.3), " bld ", CityClimb._building_at_rect(foot, b))
			u += 0.8
	for c in City.cars:
		var cr: Variant = c.get("rect")
		if cr != null and (cr as Rect2).grow(3.0).intersects(Rect2(44.0, -50.0, 10.0, 20.0)):
			print("  car ", cr)
	for t in City.trees:
		var tp: Vector2 = t["pos"]
		if Rect2(44.0, -50.0, 10.0, 20.0).has_point(tp):
			print("  tree ", tp)
	for e in CityWar.extra_clear:
		print("  extra_clear ", e)
	get_tree().quit()
