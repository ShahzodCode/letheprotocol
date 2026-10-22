extends Node
## Which pass-through buildings does the navigation grid not lead through? `-- --script res://tests/tunnel_debug.gd`
func run(m) -> void:
	await get_tree().physics_frame
	for t in City.tunnels:
		var ta: Vector3 = t["a"]
		var tb: Vector3 = t["b"]
		var tr: Rect2 = t["rect"]
		var route := City.path(ta, tb)
		var len := 0.0
		var prev := ta
		var through := false
		for wp in route:
			len += prev.distance_to(wp)
			for k in 24:
				var q := prev.lerp(wp, float(k) / 23.0)
				if tr.has_point(Vector2(q.x, q.z)):
					through = true
			prev = wp
		if not City.is_free(tb):
			for b in City.buildings:
				if (b["rect"] as Rect2).grow(1.2).has_point(Vector2(tb.x, tb.z)):
					print("   building near b ", b["rect"], " h ", b["h"])
			for c in City.cars:
				if (c["rect"] as Rect2).grow(1.5).has_point(Vector2(tb.x, tb.z)):
					print("   car ", c["rect"])
			for tr2 in City.trees:
				if (tr2["pos"] as Vector2).distance_to(Vector2(tb.x, tb.z)) < 2.5:
					print("   tree ", tr2["pos"])
			for st in City.streets:
				if (st["rect"] as Rect2).has_point(Vector2(tb.x, tb.z)):
					print("   street ", st["rect"], " ", st["cls"])
		print("tunnel ", tr, " a ", ta, " b ", tb, " direct ", snappedf(ta.distance_to(tb), 0.1), " route ", snappedf(len, 0.1), " through ", through, " free a/b ", City.is_free(ta), City.is_free(tb))
	get_tree().quit()
