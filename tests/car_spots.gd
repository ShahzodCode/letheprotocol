extends Node
## Parking spots for the parked cars (ParkedCars.SPOTS): `-- --script res://tests/car_spots.gd [max=<n>]` (headless, seconds).
## Walks every 'street' (not the avenues, plazas, alleys) along both kerbs and keeps a spot every SPACING metres where the whole car
## footprint (FOOT_HALF, grown by CLEAR on every side) is clear of buildings, props, trees, barricades, the story places and earlier spots.
## Prints the finished SPOTS list, ready to paste into scripts/parked_cars.gd; the spots already in it are re-checked first.
const FOOT_HALF := Vector2(1.25, 2.7)        # half width and half length of the biggest car (x = across, y = along)
const CLEAR := 0.9
const SPACING := 22.0
const MAX_CARS := 64
const KEEP_AWAY := [[Vector3(-30.0, 0.0, 240.5), 9.0], [Vector3(-30.0, 0.0, 254.6), 10.0], [Vector3(83.0, 0.0, -53.0), 20.0], [Vector3(66.8, 0.0, -30.3), 8.0], [Vector3(20.2, 0.0, -29.5), 10.0], [Vector3(19.0, 0.0, -30.0), 14.0]]


func run(_m) -> void:
	await get_tree().physics_frame
	var maxn := MAX_CARS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("max="):
			maxn = int(a.substr(4))
	var taken: Array = []
	var bad := 0
	for s in ParkedCars.SPOTS:
		if not _free(Vector2(s[1], s[2]), float(s[3]), []):
			bad += 1
			print("blocked: ", s)
	print("existing spots: %d, blocked: %d" % [ParkedCars.SPOTS.size(), bad])
	var out: Array = []
	var solids := _solids()
	for st in City.streets:
		if String(st["cls"]) != "street":
			continue
		var r: Rect2 = st["rect"]
		if minf(r.size.x, r.size.y) < 10.0:
			continue
		var along_z := r.size.y > r.size.x
		var base_yaw := 0.0 if along_z else PI * 0.5
		var len := r.size.y if along_z else r.size.x
		var half_w := (r.size.x if along_z else r.size.y) * 0.5
		var c := r.get_center()
		for side in [1.0, -1.0]:
			var off: float = side * (half_w - 2.7)
			var t := -len * 0.5 + 6.0 + fposmod(c.x * 0.37 + c.y * 0.61 + side * 5.0, 9.0)      # a fixed stagger per street and kerb
			while t <= len * 0.5 - 6.0:
				var p := Vector2(c.x + off, c.y + t) if along_z else Vector2(c.x + t, c.y + off)
				var yaw := base_yaw + (PI if side < 0.0 else 0.0)        # the two kerbs face opposite ways
				if _free(p, yaw, taken, solids):
					taken.append([p, yaw])
					out.append([p, yaw])
					t += SPACING
				else:
					t += 2.0
	# keep the cars that already stand, then fill up, spread over the whole map: every n-th spot of the sweep
	var final: Array = []
	for s in ParkedCars.SPOTS:
		final.append([int(s[0]), snappedf(s[1], 0.1), snappedf(s[2], 0.1), snappedf(s[3], 0.001)])
	var stride := 1
	var i := 0
	var k := 0
	while i < out.size() and final.size() < maxn:
		var o: Array = out[i]
		var near := false
		for f in final:
			if Vector2(f[1], f[2]).distance_to(o[0]) < 12.0:
				near = true
		if not near:
			final.append([(k * 2 + int(absf(o[0].x + o[0].y)) % 3) % 3, snappedf(o[0].x, 0.1), snappedf(o[0].y, 0.1), snappedf(o[1], 0.001)])
			k += 1
		i += stride
	# models: the three common ones go to the spot where the same model is farthest away; the Cybertruck (4) and the EV (10) are rare and
	# only where none stands within RARE_GAP
	var counts := [0, 0, 0, 0, 0]
	var every := [0, 0, 0, 16, 6]
	var cap := [999, 999, 999, 4, 10]
	var gap := [0.0, 0.0, 0.0, 150.0, 70.0]
	for j in final.size():
		var pj := Vector2(final[j][1], final[j][2])
		var dmin := []
		for mdl in 5:
			var dd := 1e9
			for q in j:
				if int(final[q][0]) == mdl:
					dd = minf(dd, pj.distance_to(Vector2(final[q][1], final[q][2])))
			dmin.append(dd)
		var pick := -1
		for mdl in [3, 4]:
			if pick < 0 and counts[mdl] < cap[mdl] and j % int(every[mdl]) == 2 and float(dmin[mdl]) >= float(gap[mdl]):
				pick = mdl
		if pick < 0:
			var bd := -1.0
			for mdl in 3:
				if float(dmin[mdl]) > bd:
					bd = float(dmin[mdl])
					pick = mdl
		final[j][0] = pick
		counts[pick] += 1
	# then swap models between spots (counts stay the same) while that moves same-model cars apart: cost = squared shortfall below 70 m
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for it in 6000:
		var a := rng.randi_range(0, final.size() - 1)
		var b := rng.randi_range(0, final.size() - 1)
		if final[a][0] == final[b][0]:
			continue
		var before := _near_cost(final, a) + _near_cost(final, b)
		var t: int = final[a][0]
		final[a][0] = final[b][0]
		final[b][0] = t
		if _near_cost(final, a) + _near_cost(final, b) > before:
			final[b][0] = final[a][0]
			final[a][0] = t
	var worst := 1e9
	for j in final.size():
		for q in j:
			if final[q][0] == final[j][0]:
				worst = minf(worst, Vector2(final[j][1], final[j][2]).distance_to(Vector2(final[q][1], final[q][2])))
	print("models per type ", counts, ", closest pair of the same model: %.0f m" % worst)
	print("candidates %d, written %d" % [out.size(), final.size()])
	var txt := "const SPOTS := [\n"
	for j in final.size():
		txt += "\t[%d, %s, %s, %s]%s\n" % [final[j][0], str(final[j][1]), str(final[j][2]), str(final[j][3]), "," if j < final.size() - 1 else "]"]
	var fa := FileAccess.open(ProjectSettings.globalize_path("res://.shots/spots.txt"), FileAccess.WRITE)
	fa.store_string(txt)
	fa.close()
	get_tree().quit()


func _solids() -> Array:
	var solids: Array = []
	for b in City.buildings:
		solids.append(b["rect"])
		for bx in b["boxes"]:
			if float(bx["y0"]) < 4.0:
				solids.append(bx["rect"])
	for pr in City.props:
		if float(pr["y0"]) < 2.0:
			solids.append(pr["rect"])
	for c in City.cars:
		solids.append(c["rect"])
	for ob in City.obstacles:
		solids.append(ob["rect"])
	for t in City.trees:
		var tp: Vector2 = t["pos"]
		solids.append(Rect2(tp.x - float(t["r"]), tp.y - float(t["r"]), float(t["r"]) * 2.0, float(t["r"]) * 2.0))
	return solids


func _free(p: Vector2, yaw: float, taken: Array, solids: Array = []) -> bool:
	if City.street_width_at(Vector3(p.x, 0.0, p.y)) < 10.0:
		return false
	for st in City.streets:
		if String(st["cls"]) in ["avenue", "plaza"] and (st["rect"] as Rect2).grow(3.5).has_point(p):
			return false      # the avenues and plazas stay clear
	for k in KEEP_AWAY:
		if p.distance_to(Vector2((k[0] as Vector3).x, (k[0] as Vector3).z)) < float(k[1]):
			return false
	for o in taken:
		if p.distance_to(o[0]) < 9.0:
			return false
	if solids.is_empty():
		solids = _solids()
	var ax := Vector2(cos(yaw), -sin(yaw))                 # the car's local x in the plan
	var az := Vector2(sin(yaw), cos(yaw))                  # local z in the plan
	var half := FOOT_HALF + Vector2(CLEAR, CLEAR)
	var foot := PackedVector2Array()
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			foot.append(p + ax * sx * half.x + az * sz * half.y)
	for s in solids:
		var rr := s as Rect2
		for q in foot:
			if rr.has_point(q):
				return false
		for q in [rr.position, rr.end, Vector2(rr.position.x, rr.end.y), Vector2(rr.end.x, rr.position.y), rr.get_center()]:
			var d: Vector2 = (q as Vector2) - p
			if absf(d.dot(ax)) <= half.x and absf(d.dot(az)) <= half.y:
				return false
	return true


func _near_cost(list: Array, i: int) -> float:
	var c := 0.0
	var pi := Vector2(list[i][1], list[i][2])
	for q in list.size():
		if q != i and list[q][0] == list[i][0]:
			c += pow(maxf(0.0, 70.0 - pi.distance_to(Vector2(list[q][1], list[q][2]))), 2.0)
	return c
