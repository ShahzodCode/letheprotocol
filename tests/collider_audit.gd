extends Node
## Lists scenery meshes a walking player could reach (low enough, big enough) that no collider covers:
## `-- --script res://tests/collider_audit.gd` (prints counts per kind and the 40 biggest misses)
func _covered(p: Vector3) -> bool:
	for c in Scn.colliders:
		var q: Vector3 = (c["xf"] as Transform3D).affine_inverse() * p
		var h: Vector3 = (c["size"] as Vector3) * 0.5 + Vector3(0.15, 0.15, 0.15)
		if absf(q.x) <= h.x and absf(q.y) <= h.y and absf(q.z) <= h.z:
			return true
	for c in Scn.cyl_colliders:
		var b: Vector3 = c["pos"]
		if Vector2(p.x - b.x, p.z - b.z).length() <= float(c["r"]) + 0.15 and p.y >= b.y - 0.15 and p.y <= b.y + float(c["h"]) + 0.15:
			return true
	return false


func run(m) -> void:
	await get_tree().physics_frame
	var misses: Array = []
	var total := {}
	for kind in ["box", "cyl"]:
		for part in Scn.parts[kind]:
			var xf: Transform3D = part[0]
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := Vector3(-1e9, -1e9, -1e9)
			for cx in [-0.5, 0.5]:
				for cy in [-0.5, 0.5]:
					for cz in [-0.5, 0.5]:
						var v: Vector3 = xf * Vector3(cx, cy, cz)
						lo = lo.min(v)
						hi = hi.max(v)
			var sz := hi - lo
			var sc := xf.basis.get_scale()
			var dims := [absf(sc.x), absf(sc.y), absf(sc.z)]
			dims.sort()
			# reachable by a walker: starts below head height, rises above ankle height, and is not a rod / sheet / sliver
			if lo.y > 1.7 or hi.y < 0.3 or maxf(sz.x, sz.z) < 0.35 or float(dims[1]) < 0.25 or float(dims[0]) < 0.1:
				continue
			total[kind] = int(total.get(kind, 0)) + 1
			var mid := (lo + hi) * 0.5
			if not _covered(mid) and not _covered(Vector3(mid.x, clampf(mid.y, 0.3, 1.5), mid.z)):
				misses.append([sz.x * sz.y * sz.z, kind, mid, sz])
	misses.sort_custom(func(a, b): return a[0] > b[0])
	print("reachable parts ", total, " uncovered ", misses.size())
	for i in mini(120, misses.size()):
		var e: Array = misses[i]
		print("  ", e[1], " at ", e[2], " size ", e[3])
	get_tree().quit()
