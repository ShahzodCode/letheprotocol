class_name WorldCars
## Draws City.cars: every vehicle is a handful of boxes (body paint, dark glass, wheels, lights) merged into two MultiMeshes (lit and
## glowing), with one box collider each. Damaged cars (City cars with "dmg"): burnt-out shells (charred, no glass, no wheels or black
## wheels, sitting low, no lights), flipped onto the side or roof (the car's basis is rolled in CityWar.finish_car), crushed roofs,
## doors hanging open. Fires on the burning ones come from Scn.fires.


static func build(world: World) -> void:
	var lit: Array = []        # [Transform3D, Color]
	var glow: Array = []
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	world.add_child(body)
	for c in City.cars:
		var sz: Vector3 = c["size"]
		var basis: Basis = c["basis"]
		var origin: Vector3 = c["origin"]
		var burnt: bool = c["burnt"]
		var crush: float = c["crush"]
		var paint: Color = c["color"]
		var accent: Color = c["accent"]
		var glass := Color(0.02, 0.016, 0.014) if burnt else Color(0.07, 0.1, 0.13)
		var tyre := Color(0.02, 0.02, 0.02) if burnt else Color(0.05, 0.05, 0.06)
		var wr := 0.35 if sz.y < 2.0 else 0.5
		var seed_k := int(absf(origin.x * 7.0 + origin.z * 3.0))
		var wheels := not burnt or seed_k % 2 == 0
		var drop := 0.0 if wheels else wr * 0.8
		var parts: Array = []       # [local centre, size, colour, glows, local basis]
		var shapes: Array = []      # the solid pieces, [local centre, size, local basis]: a box for body, cabin / cab, cargo, each open door
		var top := 0.0
		var cab_squash := 1.0 - crush * 0.6
		match String(c["type"]):
			"van", "bus":
				var h: float = (sz.y - wr) * (1.0 - crush * 0.35)
				parts.append([Vector3(0, wr + h * 0.5, 0), Vector3(sz.x, h, sz.z), paint, false, Basis.IDENTITY])
				parts.append([Vector3(0, wr + h * 0.62, -sz.z * 0.5 + 0.04), Vector3(sz.x * 0.94, h * 0.3, 0.1), glass, false, Basis.IDENTITY])
				var band := 0.85 if c["type"] == "bus" else 0.3
				parts.append([Vector3(0, wr + h * 0.62, -sz.z * (0.5 - band * 0.5) + (0.0 if c["type"] == "bus" else 0.35)), Vector3(sz.x + 0.02, h * 0.28, sz.z * band), glass, false, Basis.IDENTITY])
				if c["two_tone"] and not burnt:
					parts.append([Vector3(0, wr + h * 0.9, 0), Vector3(sz.x + 0.01, h * 0.2, sz.z + 0.01), accent, false, Basis.IDENTITY])
				top = wr + h
				shapes.append([Vector3(0, (wr + h - drop) * 0.5, 0), Vector3(sz.x, wr + h - drop, sz.z), Basis.IDENTITY])
			"truck":
				var h2: float = sz.y - wr
				var cab_l := sz.z * 0.26
				parts.append([Vector3(0, wr + h2 * 0.35, -sz.z * 0.5 + cab_l * 0.5), Vector3(sz.x, h2 * 0.7, cab_l), paint, false, Basis.IDENTITY])
				parts.append([Vector3(0, wr + h2 * 0.5, -sz.z * 0.5 + 0.04), Vector3(sz.x * 0.94, h2 * 0.28, 0.1), glass, false, Basis.IDENTITY])
				parts.append([Vector3(0, wr + h2 * 0.5, -sz.z * 0.5 + cab_l * 0.5), Vector3(sz.x + 0.02, h2 * 0.26, cab_l * 0.55), glass, false, Basis.IDENTITY])
				var cargo: Color = c["cargo"]
				if burnt:
					cargo = paint.lightened(0.05)
				parts.append([Vector3(0, wr + h2 * 0.5, sz.z * 0.5 - sz.z * 0.36), Vector3(sz.x, h2, sz.z * 0.72), cargo, false, Basis.IDENTITY])
				top = wr + h2
				var cab_top := wr + h2 * 0.7 - drop
				shapes.append([Vector3(0, cab_top * 0.5, -sz.z * 0.5 + cab_l * 0.5), Vector3(sz.x, cab_top, cab_l), Basis.IDENTITY])
				shapes.append([Vector3(0, (top - drop) * 0.5, sz.z * 0.14), Vector3(sz.x, top - drop, sz.z * 0.72), Basis.IDENTITY])
			_:
				var bh := (sz.y - wr) * 0.5
				var ch := (sz.y - wr) * 0.5 * cab_squash
				var cab_len := 0.62 if c["type"] == "suv" else 0.52
				parts.append([Vector3(0, wr + bh * 0.5, 0), Vector3(sz.x, bh, sz.z), paint, false, Basis.IDENTITY])                                        # lower body
				parts.append([Vector3(0, wr + bh + ch * 0.5, sz.z * 0.04), Vector3(sz.x * 0.92, ch, sz.z * cab_len), glass, false, Basis.IDENTITY])        # glass cabin
				var roof: Color = accent if c["two_tone"] else paint
				var roof_tilt := Basis(Vector3(0, 0, 1), crush * 0.12 * (1.0 if seed_k % 2 == 0 else -1.0)) * Basis(Vector3(1, 0, 0), crush * 0.1)
				parts.append([Vector3(0, wr + bh + ch, sz.z * 0.04), Vector3(sz.x * 0.94, 0.07, sz.z * cab_len + 0.04), roof, false, roof_tilt])          # roof
				top = wr + bh + ch + 0.04
				shapes.append([Vector3(0, (wr + bh - drop) * 0.5, 0), Vector3(sz.x, wr + bh - drop, sz.z), Basis.IDENTITY])              # lower body, down to the ground
				shapes.append([Vector3(0, wr + bh - drop + (ch + 0.04) * 0.5, sz.z * 0.04), Vector3(sz.x * 0.94, ch + 0.04, sz.z * cab_len + 0.04), Basis.IDENTITY])   # the cabin is narrower and shorter
				if crush > 0.0:
					parts.append([Vector3(0, wr + bh + 0.04, -sz.z * 0.3), Vector3(sz.x * 0.9, 0.08, sz.z * 0.28), paint.darkened(0.3), false, Basis(Vector3(1, 0, 0), 0.25)])   # crumpled bonnet
		if c["stripe"] and c["type"] != "bus" and not burnt:
			parts.append([Vector3(0, top + 0.015, 0), Vector3(0.28, 0.02, sz.z * 0.98), accent, false, Basis.IDENTITY])                                # racing stripe
		if c["doors"]:
			var dh := (top - wr) * 0.8
			for sx in [-1.0, 1.0]:
				var ang: float = 1.15 * sx
				var hinge := Vector3(sx * sz.x * 0.5, wr + dh * 0.55, -sz.z * 0.08)
				var db := Basis(Vector3.UP, ang)
				parts.append([hinge + db * Vector3(0.0, 0.0, 0.5), Vector3(0.06, dh, 1.0), paint, false, db])
				shapes.append([hinge + db * Vector3(0.0, 0.0, 0.5) - Vector3(0, drop, 0), Vector3(0.06, dh, 1.0), db])
		if wheels:
			var axles: Array = [-0.32, 0.32]
			if c["type"] == "truck" or c["type"] == "bus":
				axles = [-0.34, 0.2, 0.36]
			for az in axles:
				for sx in [-1.0, 1.0]:
					parts.append([Vector3(sx * (sz.x * 0.5 - 0.08), wr, float(az) * sz.z), Vector3(0.26, wr * 2.0, wr * 2.0), tyre, false, Basis.IDENTITY])
		if not burnt:
			# lights: white at the front (-z), red at the back
			var ly := wr + 0.35
			for sx in [-1.0, 1.0]:
				parts.append([Vector3(sx * sz.x * 0.32, ly, -sz.z * 0.5), Vector3(0.3, 0.14, 0.06), Color(1.0, 0.95, 0.7), true, Basis.IDENTITY])
				parts.append([Vector3(sx * sz.x * 0.32, ly, sz.z * 0.5), Vector3(0.3, 0.12, 0.06), Color(0.9, 0.1, 0.08), true, Basis.IDENTITY])
		for pt in parts:
			var lc: Vector3 = pt[0]
			if pt[3] == false and drop > 0.0:
				lc.y -= drop
			var xf := Transform3D(basis * (pt[4] as Basis) * Basis.from_scale(pt[1]), origin + basis * lc)
			(glow if pt[3] else lit).append([xf, pt[2]])
		for sh in shapes:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = sh[1]
			cs.shape = shape
			cs.transform = Transform3D(basis * (sh[2] as Basis), origin + basis * (sh[0] as Vector3))
			body.add_child(cs)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var lit_mat := world._flat_mat(Color.WHITE, true)
	var glow_mat := world._flat_mat(Color.WHITE, true)
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	WorldWar._mm(world, box, lit, lit_mat, false, 320.0)
	WorldWar._mm(world, box, glow, glow_mat, false, 220.0)
