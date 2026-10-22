extends Node
## Can the player hide in the back streets? Measures the city layout and prints numbers (no gameplay change):
## `-- --script res://tests/stealth_audit.gd [out=<png>]`   (the png colours every walkable cell: pockets, wide streets, exits)
## Narrow = streets up to NARROW_MAX wide (alleys 3, footpaths 6, lanes 8); wide = WIDE_MIN and more (12 m streets, avenues, plazas).
## A POCKET is a connected set of narrow cells; an EXIT is where it opens onto a wide street; a CROSSING is a straight dash over wide
## cells (at most CROSS_MAX m) from one pocket to another. See docs/stealth-layout-plan.md.

const NARROW_MAX := 8.5
const WIDE_MIN := 9.5
const CROSS_MAX := 13
const MIN_POCKET := 40            # smaller sets of narrow cells are corners and nooks, not pockets
const EXIT_MERGE := 2             # boundary cells this close (Chebyshev) are one exit
const SOLDIER_NEAR := 30.0

var nx := 0
var nz := 0
var ox := 0.0
var oz := 0.0
var free := PackedByteArray()
var width := PackedFloat32Array()
var pocket := PackedInt32Array()


func _cell(p: Vector3) -> int:
	var x := floori(p.x - ox)
	var z := floori(p.z - oz)
	if x < 0 or z < 0 or x >= nx or z >= nz:
		return -1
	return z * nx + x


func _pos(i: int) -> Vector3:
	return Vector3(ox + float(i % nx) + 0.5, 0.0, oz + float(i / nx) + 0.5)


func _is_narrow(i: int) -> bool:
	return free[i] == 1 and width[i] <= NARROW_MAX


func _is_wide(i: int) -> bool:
	return free[i] == 1 and width[i] >= WIDE_MIN


func run(_m) -> void:
	await get_tree().physics_frame
	var args := OS.get_cmdline_user_args()
	var out_png := "user://stealth_map.png"
	for a in args:
		if String(a).begins_with("out="):
			out_png = String(a).substr(4)
	nx = int(City.OUT_X * 2.0)
	nz = int(City.OUT_Z * 2.0)
	ox = -City.OUT_X
	oz = -City.OUT_Z
	free.resize(nx * nz)
	width.resize(nx * nz)
	pocket.resize(nx * nz)
	for i in nx * nz:
		free[i] = 1 if City.is_free(_pos(i)) else 0
		width[i] = 0.0
		pocket[i] = -1
	# the width of the street each cell belongs to: the narrowest street rectangle that covers it
	for st in City.streets:
		var r: Rect2 = st["rect"]
		var w := minf(r.size.x, r.size.y)
		for z in range(maxi(0, floori(r.position.y - oz)), mini(nz, ceili(r.end.y - oz))):
			for x in range(maxi(0, floori(r.position.x - ox)), mini(nx, ceili(r.end.x - ox))):
				var i := z * nx + x
				if width[i] == 0.0 or w < width[i]:
					width[i] = w
	var unpainted := 0   # cells in no generated street rectangle
	var free_cells := 0
	for i in nx * nz:
		if free[i] == 1:
			free_cells += 1
			if width[i] == 0.0:
				unpainted += 1
				width[i] = 9.0          # hand-built places (park, home, Institute, tunnels): neither narrow nor wide
	# ---- pockets
	var sizes: Array = []
	var narrow_total := 0
	var wide_total := 0
	for i in nx * nz:
		if _is_narrow(i):
			narrow_total += 1
		elif _is_wide(i):
			wide_total += 1
	for i in nx * nz:
		if not _is_narrow(i) or pocket[i] != -1:
			continue
		var id := sizes.size()
		var n := 0
		var stack: Array[int] = [i]
		pocket[i] = id
		while not stack.is_empty():
			var c: int = stack.pop_back()
			n += 1
			for nb in _nbrs(c):
				if pocket[nb] == -1 and _is_narrow(nb):
					pocket[nb] = id
					stack.append(nb)
		sizes.append(n)
	# ---- exits and crossings
	var soldiers: Array = []
	for e in Game.enemies:
		if is_instance_valid(e):
			soldiers.append((e as Node3D).global_position)
	var exits_of: Dictionary = {}          # pocket id -> Array of {pos, width, soldiers}
	var links: Dictionary = {}             # "a:b" -> shortest crossing (m)
	var boundary: Dictionary = {}          # pocket id -> Array of cell indices touching a wide cell
	for i in nx * nz:
		if pocket[i] < 0 or sizes[pocket[i]] < MIN_POCKET:
			continue
		var touches := false
		for nb in _nbrs(i):
			if _is_wide(nb):
				touches = true
				break
		if touches:
			if not boundary.has(pocket[i]):
				boundary[pocket[i]] = []
			boundary[pocket[i]].append(i)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var cx: int = i % nx
				var cz: int = i / nx
				var len := 0
				var hit := -1
				for s in range(1, CROSS_MAX + 1):
					var qx: int = cx + d.x * s
					var qz: int = cz + d.y * s
					if qx < 0 or qz < 0 or qx >= nx or qz >= nz:
						break
					var q := qz * nx + qx
					if free[q] == 0:
						break
					if _is_narrow(q):
						if pocket[q] != pocket[i] and pocket[q] >= 0 and sizes[pocket[q]] >= MIN_POCKET:
							hit = pocket[q]
							len = s - 1
						break
				if hit >= 0:
					var key := "%d:%d" % [mini(hit, pocket[i]), maxi(hit, pocket[i])]
					if not links.has(key) or len < int(links[key]):
						links[key] = len
	for pid in boundary:
		var cells: Array = boundary[pid]
		var done: Dictionary = {}
		for c in cells:
			if done.has(c):
				continue
			var group: Array = [c]
			done[c] = true
			var qi := 0
			while qi < group.size():
				var g: int = group[qi]
				qi += 1
				for o in cells:
					if not done.has(o) and absi(o % nx - g % nx) <= EXIT_MERGE and absi(o / nx - g / nx) <= EXIT_MERGE:
						done[o] = true
						group.append(o)
			var centre := Vector3.ZERO
			var wsum := 0.0
			var wn := 0
			for g in group:
				centre += _pos(g)
				for nb in _nbrs(g):
					if _is_wide(nb):
						wsum += width[nb]
						wn += 1
			centre /= float(group.size())
			var near := 0
			for sp in soldiers:
				if Vector2(sp.x - centre.x, sp.z - centre.z).length() < SOLDIER_NEAR:
					near += 1
			if not exits_of.has(pid):
				exits_of[pid] = []
			exits_of[pid].append({"pos": centre, "width": wsum / maxf(1.0, float(wn)), "soldiers": near, "mouth": group.size()})
	# ---- pocket graph
	var big: Array = []
	for pid in sizes.size():
		if sizes[pid] >= MIN_POCKET:
			big.append(pid)
	var adj: Dictionary = {}
	for key in links:
		var ab: PackedStringArray = String(key).split(":")
		var a := int(ab[0])
		var b := int(ab[1])
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		adj[a].append(b)
		adj[b].append(a)
	var comp: Dictionary = {}
	var comp_cells: Array = []
	for pid in big:
		if comp.has(pid):
			continue
		var cid := comp_cells.size()
		var cs := 0
		var st2: Array = [pid]
		comp[pid] = cid
		while not st2.is_empty():
			var p2: int = st2.pop_back()
			cs += int(sizes[p2])
			for nb2 in adj.get(p2, []):
				if not comp.has(nb2):
					comp[nb2] = cid
					st2.append(nb2)
		comp_cells.append(cs)
	# ---- report
	print("=== STEALTH AUDIT (seed city, %d walkable cells, %d hand-built-place cells counted as neither) ===" % [free_cells, unpainted])
	print("passages cut by CityLinks: ", CityLinks.done)
	print("narrow cells %d (%.0f%%), wide cells %d (%.0f%%), other (%d-%d m) %d" % [narrow_total, 100.0 * narrow_total / free_cells, wide_total, 100.0 * wide_total / free_cells, int(NARROW_MAX), int(WIDE_MIN), free_cells - narrow_total - wide_total])
	print("pockets (>= %d cells): %d, of %d narrow sets in all" % [MIN_POCKET, big.size(), sizes.size()])
	var hist: Dictionary = {}
	var exit_total := 0
	var hot_exits := 0
	var onto_avenue := 0
	var rows: Array = []
	for pid in big:
		var ex: Array = exits_of.get(pid, [])
		var nex := ex.size()
		hist[nex] = int(hist.get(nex, 0)) + 1
		var hot := 0
		var wsum2 := 0.0
		var lk: Array = adj.get(pid, [])
		for e2 in ex:
			exit_total += 1
			wsum2 += float(e2["width"])
			if int(e2["soldiers"]) >= 2:
				hot_exits += 1
				hot += 1
			if float(e2["width"]) >= 18.0:
				onto_avenue += 1
		rows.append({"pid": pid, "cells": sizes[pid], "exits": nex, "links": lk.size(), "hot": hot, "open_w": wsum2 / maxf(1.0, float(nex)), "at": _centre_of(pid)})
	var keys := hist.keys()
	keys.sort()
	var hs := ""
	for k in keys:
		hs += "%d exits: %d pockets   " % [k, hist[k]]
	print("exit count per pocket -> ", hs)
	print("exits in all: %d; with 2+ soldiers within %d m at spawn: %d (%.0f%%); opening onto 18 m+ avenues/plazas: %d (%.0f%%)" % [exit_total, int(SOLDIER_NEAR), hot_exits, 100.0 * hot_exits / maxf(1.0, exit_total), onto_avenue, 100.0 * onto_avenue / maxf(1.0, exit_total)])
	var linked_pockets := 0
	for pid in big:
		if adj.has(pid):
			linked_pockets += 1
	print("pockets with at least one crossing (<= %d m dash) to another pocket: %d of %d; crossing links in all: %d" % [CROSS_MAX, linked_pockets, big.size(), links.size()])
	var best_comp := 0
	for c3 in comp_cells:
		best_comp = maxi(best_comp, int(c3))
	var pocket_cells := 0
	for pid in big:
		pocket_cells += int(sizes[pid])
	comp_cells.sort()
	comp_cells.reverse()
	print("pocket groups joined by crossings: %d; the biggest holds %d of %d pocket cells (%.0f%%); next biggest: %s" % [comp_cells.size(), best_comp, pocket_cells, 100.0 * best_comp / maxf(1.0, pocket_cells), str(comp_cells.slice(1, 6))])
	rows.sort_custom(func(a, b): return a["exits"] < b["exits"] or (a["exits"] == b["exits"] and a["cells"] > b["cells"]))
	print("--- the 15 worst pockets (fewest exits, then biggest): id, cells, exits, crossings, hot exits, mean width of the street at the exits, centre")
	for r in rows.slice(0, 15):
		print("  #%d  %4d cells  exits %d  crossings %d  hot %d  opens on %.0f m  at (%.0f, %.0f)" % [r["pid"], r["cells"], r["exits"], r["links"], r["hot"], r["open_w"], (r["at"] as Vector3).x, (r["at"] as Vector3).z])
	# ---- blocks with no back street at all (a solid mass of buildings)
	var xe: Array = City._intervals(City.AVENUE_X, City.BX)
	var ze: Array = City._intervals(City.AVENUE_Z, City.BZ)
	var solid_blocks := 0
	var block_total := 0
	var solid_list := ""
	for ix in xe.size():
		for iz in ze.size():
			block_total += 1
			var inside := 0
			for z in range(floori(ze[iz][0] - oz) + 1, ceili(ze[iz][1] - oz) - 1):
				for x in range(floori(xe[ix][0] - ox) + 1, ceili(xe[ix][1] - ox) - 1):
					if free[z * nx + x] == 1:
						inside += 1
			if inside < 30:
				solid_blocks += 1
				solid_list += "(%.0f,%.0f) " % [(xe[ix][0] + xe[ix][1]) * 0.5, (ze[iz][0] + ze[iz][1]) * 0.5]
	print("blocks with no street inside at all: %d of %d  centres: %s" % [solid_blocks, block_total, solid_list])
	# ---- the walk home
	_route_report(City.INSTITUTE_EXIT, City.HOME_POS)
	# ---- the picture
	var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.06))
	for i in nx * nz:
		if free[i] == 0:
			continue
		var col := Color(0.55, 0.55, 0.58)                     # wide street: grey
		if _is_narrow(i):
			var pid2: int = pocket[i]
			var h := fmod(float(pid2) * 0.137, 1.0)
			col = Color.from_hsv(h, 0.55, 0.95) if pid2 >= 0 and sizes[pid2] >= MIN_POCKET else Color(0.4, 0.3, 0.3)
		elif not _is_wide(i):
			col = Color(0.75, 0.75, 0.5)
		img.set_pixel(i % nx, i / nx, col)
	for pid in exits_of:
		for e3 in exits_of[pid]:
			var c4 := _cell(e3["pos"])
			if c4 >= 0:
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var px: int = c4 % nx + dx
						var pz: int = c4 / nx + dz
						if px >= 0 and pz >= 0 and px < nx and pz < nz:
							img.set_pixel(px, pz, Color(1, 0, 0) if int(e3["soldiers"]) >= 2 else Color(1, 1, 1))
	for sp in soldiers:
		var sc := _cell(sp)
		if sc >= 0:
			img.set_pixel(sc % nx, sc / nx, Color(0, 0, 0))
	img.save_png(out_png)
	print("map written to ", ProjectSettings.globalize_path(out_png) if out_png.begins_with("user://") else out_png, "  (pockets coloured, wide streets grey, exits white, exits with 2+ soldiers near red, soldiers black)")
	get_tree().quit()


func _nbrs(i: int) -> Array[int]:
	var out: Array[int] = []
	var x := i % nx
	var z := i / nx
	if x > 0:
		out.append(i - 1)
	if x < nx - 1:
		out.append(i + 1)
	if z > 0:
		out.append(i - nx)
	if z < nz - 1:
		out.append(i + nx)
	return out


func _nearest_free(i: int) -> int:
	var x := i % nx
	var z := i / nx
	for r in range(0, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var qx := x + dx
				var qz := z + dz
				if qx >= 0 and qz >= 0 and qx < nx and qz < nz and free[qz * nx + qx] == 1:
					return qz * nx + qx
	return i


func _centre_of(pid: int) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for i in nx * nz:
		if pocket[i] == pid:
			s += _pos(i)
			n += 1
	return s / maxf(1.0, float(n))


## How much of the way from `a` to `b` must be walked in the open? Two routes: the shortest, and the one that avoids wide streets
## (cost 6 per wide cell).
func _route_report(a: Vector3, b: Vector3) -> void:
	for mode in ["shortest", "hide-friendly (wide cells cost 6)"]:
		var g := AStarGrid2D.new()
		g.region = Rect2i(0, 0, nx, nz)
		g.cell_size = Vector2.ONE
		g.offset = Vector2(ox + 0.5, oz + 0.5)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		g.update()
		for i in nx * nz:
			if free[i] == 0:
				g.set_point_solid(Vector2i(i % nx, i / nx), true)
			elif mode != "shortest" and _is_wide(i):
				g.set_point_weight_scale(Vector2i(i % nx, i / nx), 6.0)
			elif mode != "shortest" and not _is_narrow(i):
				g.set_point_weight_scale(Vector2i(i % nx, i / nx), 3.0)
		var ia := _nearest_free(_cell(a))
		var ib := _nearest_free(_cell(b))
		var path := g.get_id_path(Vector2i(ia % nx, ia / nx), Vector2i(ib % nx, ib / nx))
		var narrow := 0
		var wide := 0
		var run := 0
		var longest := 0
		for id in path:
			var ci: int = id.y * nx + id.x
			if _is_wide(ci):
				wide += 1
				run += 1
				longest = maxi(longest, run)
			else:
				run = 0
				if _is_narrow(ci):
					narrow += 1
		print("walk home, %s: %d m, %d m on narrow streets, %d m in the open (%.0f%%), longest open stretch %d m" % [mode, path.size(), narrow, wide, 100.0 * wide / maxf(1.0, path.size()), longest])
