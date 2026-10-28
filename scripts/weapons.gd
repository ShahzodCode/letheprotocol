class_name Weapons
extends Node3D
## Pistol + rifle: hitscan with spread/bloom/recoil/falloff, magazines, reload, ADS, viewmodels, tracers, casings.
## Sits under the player's camera. Logic runs in _physics_process, visuals in _process.

signal hit_marker(headshot: bool, killed: bool)
signal fired(id: String)

const HIP_POS := Vector3(0.2, -0.2, -0.5)
const SIGHT_H := 0.02          # height of the iron-sight posts on the weapons without a .glb
const MAX_CASINGS := 40

var player: Player
var camera: Camera3D
var holder: Node3D
var models := {}              # id -> Node3D viewmodel (children of holder)
var muzzles := {}             # id -> Marker3D
var state := {}               # {current id: the ACTIVE weapon instance {"id", "ammo": int, "spare": Array[int]}}
var current := "pistol"       # id of the weapon in hand

# Loadout: two weapons per slot at most. Each weapon instance owns its rounds and its (finite) spare magazines.
const MAX_PER_SLOT := 2
const MAX_SPARE_MAGS := 6
const PICKUP_RANGE := 2.0      # stand this close (horizontally) to a lying weapon to take it with Q
const AMMO_RANGE := 1.8        # loose magazines are collected automatically inside this range
var loadout := {"pistol": [], "rifle": [], "melee": []}
var active_slot := "pistol"
var active_idx := 0
var last_idx := {"pistol": 0, "rifle": 0, "melee": 0}
var hover: Pickup = null      # the weapon lying under the player's feet (HUD shows it)
var notice := ""              # short toast for the HUD ("+1 MAG ...")
var notice_t := 0.0
var melee_t := 0.0            # swing animation time left
var _melee_hit_pending := false
var _stroke := 0              # index into STROKES of the swing in progress
var _stroke_k := 1.0          # this swing's size (a little different every time)
var _last_slash := 1          # forehand and backhand take turns
var _last_swing_ms := 0
var _melee_stop := 0.0        # hit-stop: the blade sticks for a moment when it connects
# frag grenades: hold G for the arc preview, release (or just tap) to throw
const THROW_TIME := 0.45           # throw animation
const PREVIEW_DELAY := 0.18        # held longer than this: the arc shows; a quick tap throws at once
const ARC_DOTS := 70
var g_down_t := -1.0               # seconds G has been held (-1 = not held)
var throw_t := 0.0
var grenade_k := 0.0               # 0 .. 1: the weapon is lowered and the arm is up
var throw_arm: Node3D
var grab_arm: Node3D
var wound_arm_node: Node3D
var _arc_dots: MultiMeshInstance3D
var _arc_ring: MeshInstance3D
var takedown_t := 0.0         # stab animation time left
var _td_jolted := false       # the takedown's blade has gone in (camera jolt and stab sound played)
var takedown_target: Enemy = null     # an unaware enemy in reach and from behind: E / LMB kills him silently

var cooldown := 0.0
var reloading := false
var reload_t := 0.0
var _reload_sound_stage := 0
var switching := 0.0
var pending_slot := ""
var pending_idx := 0
var ads_k := 0.0
var bloom := 0.0              # extra spread (deg) from firing, decays fast
var kick := 0.0               # viewmodel push-back
var kick_pitch := 0.0
var sway := Vector2.ZERO
var bob_t := 0.0
var empty_click_cd := 0.0
var _trigger_was_down := false

const HEAVY_DROP_RANGE := 16.0     # switching away from a heavy weapon (LR-9) with a hunter this close drops it where you stand
const HEAVY_DROP := false         # off: switching away from the LR-9 used to drop it when a hunter was near, which looked like a bug
const SHELL_G := 9.8               # slow shells (DB "bullet_speed") fall with this gravity
const SHELL_STEP := 10.0           # ...traced in straight pieces of this length
const BREATH_REGAIN := 4.0         # seconds to get a held breath back
var sway_view := Vector2.ZERO      # (pitch, yaw) in radians added to the player's view while scoped with a long rifle
var breath := 1.0                  # 0..1: breath left for holding the scope steady (Shift or Ctrl)
var breath_held := false
var gasp_t := 0.0                  # > 0: out of air, the view swings wide
var shell_end := Vector3.ZERO      # where the last traced shell ended (hit or maximum range)
var _sway_t := 0.0

var hum: AudioStreamPlayer          # the pulse rifle's charge hum while it is in hand
var flash_light: OmniLight3D
var flash_node: Node3D
var flash_t := 0.0
var _casings: Array = []
var _rng := RandomNumberGenerator.new()


func setup(p: Player, cam: Camera3D) -> void:
	player = p
	camera = cam
	_rng.randomize()
	holder = Node3D.new()
	holder.position = HIP_POS
	camera.add_child(holder)
	hum = AudioStreamPlayer.new()
	hum.stream = Sfx.get_sound("hum")
	hum.volume_db = -27.0
	add_child(hum)
	# the throwing arm (a sleeve and the grenade in the hand), only shown while winding up / throwing
	throw_arm = Node3D.new()
	var sleeve := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.09, 0.09, 0.4)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.2, 0.22, 0.16)
	sb.material = smat
	sleeve.mesh = sb
	sleeve.position = Vector3(0, 0, 0.18)
	throw_arm.add_child(sleeve)
	var hand := Grenade.build_model()
	hand.position = Vector3(0, 0.0, -0.08)
	hand.scale = Vector3.ONE * 1.3
	throw_arm.add_child(hand)
	throw_arm.visible = false
	camera.add_child(throw_arm)
	# the grabbing arm of a takedown (left sleeve and glove): clamps over the victim's mouth while the blade goes in
	grab_arm = Node3D.new()
	var gsleeve := MeshInstance3D.new()
	var gsb := BoxMesh.new()
	gsb.size = Vector3(0.09, 0.09, 0.4)
	gsb.material = smat
	gsleeve.mesh = gsb
	gsleeve.position = Vector3(0, 0, 0.18)
	grab_arm.add_child(gsleeve)
	var glove := MeshInstance3D.new()
	var glb := BoxMesh.new()
	glb.size = Vector3(0.1, 0.07, 0.12)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.1, 0.1, 0.1)
	glb.material = gmat
	glove.mesh = glb
	glove.position = Vector3(0, 0, -0.07)
	grab_arm.add_child(glove)
	grab_arm.visible = false
	camera.add_child(grab_arm)
	# the wounded right arm: a limp sleeve hanging at the bottom right edge of the view, dark with blood
	wound_arm_node = Node3D.new()
	var sl := MeshInstance3D.new()
	var slm := BoxMesh.new()
	slm.size = Vector3(0.1, 0.1, 0.42)
	var slmat := StandardMaterial3D.new()
	slmat.albedo_color = Color(0.2, 0.22, 0.16)
	slm.material = slmat
	sl.mesh = slm
	wound_arm_node.add_child(sl)
	var stain := MeshInstance3D.new()
	var stm := BoxMesh.new()
	stm.size = Vector3(0.104, 0.104, 0.16)
	var stmat := StandardMaterial3D.new()
	stmat.albedo_color = Color(0.4, 0.04, 0.04)
	stm.material = stmat
	stain.mesh = stm
	stain.position = Vector3(0, 0, -0.12)
	wound_arm_node.add_child(stain)
	wound_arm_node.position = Vector3(0.3, -0.26, -0.4)
	wound_arm_node.rotation = Vector3(-0.5, 0.25, 0.0)
	wound_arm_node.visible = false
	camera.add_child(wound_arm_node)

	# start loadout: just a pistol and a knife (everything else has to be taken from fallen soldiers)
	loadout["pistol"].append(new_weapon("pistol"))
	loadout["melee"].append(new_weapon("knife"))
	_equip("pistol", 0)

	for id in WeaponsDB.ORDER:
		var w: Dictionary = WeaponsDB.WEAPONS[id]
		var model := _build_model(id, w)
		model.visible = false
		holder.add_child(model)
		models[id] = model
		var m := Marker3D.new()
		m.position = Vector3(0, float(w["top_y"]) - 0.03, float(w["center_z"]) - float(w["length"]) * 0.5 - 0.02)
		model.add_child(m)
		muzzles[id] = m

	# one muzzle flash for everything, re-parented to the active muzzle
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.75, 0.4)
	flash_light.light_energy = 4.0
	flash_light.omni_range = 9.0
	flash_light.shadow_enabled = false
	flash_light.visible = false
	flash_node = Node3D.new()
	flash_node.visible = false
	flash_node.add_child(flash_light)
	var fm := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var glow := Gradient.new()
	glow.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	glow.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = glow
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 64
	gtex.height = 64
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_texture = gtex
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.no_depth_test = true
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.material = fmat
	fm.mesh = quad
	flash_node.add_child(fm)
	muzzles[current].add_child(flash_node)
	_show_only(current)


func _show_only(id: String) -> void:
	for k in models:
		models[k].visible = (k == id)
	if flash_node.get_parent() != muzzles[id]:
		flash_node.get_parent().remove_child(flash_node)
		muzzles[id].add_child(flash_node)
		flash_node.position = Vector3.ZERO


# ---------------------------------------------------------------- viewmodel loading

static func _collect_aabb(node: Node, xf: Transform3D, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var a: AABB = xf * mi.mesh.get_aabb() if mi.mesh else AABB()
		if mi.mesh:
			out.append(a)
	for c in node.get_children():
		if c is Node3D:
			_collect_aabb(c, xf * (c as Node3D).transform, out)


static func _aabb_of(node: Node3D) -> AABB:
	var list: Array = []
	_collect_aabb(node, Transform3D.IDENTITY, list)
	if list.is_empty():
		return AABB()
	var box: AABB = list[0]
	for i in range(1, list.size()):
		box = box.merge(list[i])
	return box


func _build_model(id: String, w: Dictionary) -> Node3D:
	var root := Node3D.new()
	var scene: PackedScene = null
	if ResourceLoader.exists(String(w["model"])):
		scene = load(String(w["model"])) as PackedScene
	if scene == null:
		# no imported model: the procedural one (detailed version), placed so its top sits at top_y and it is centred on center_z
		var gm := GunModels.build(id, 2)
		if bool(w.get("melee", false)):
			gm.position = Vector3(0, float(w["top_y"]) - 0.02, -0.01)
			gm.rotation.x = 0.35                  # tip up, the way a blade is held
		else:
			gm.position = Vector3(0, float(w["top_y"]), float(w["center_z"]))
		root.add_child(gm)
		return root
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	if float(w["mirror_z"]) != 0.0:
		# half-models (the pistol) are built on one side of a plane: add a mirrored twin so it is solid
		# (the mirror is baked into the vertices: a negative node scale flips the winding and shades that half differently)
		var twin := Node3D.new()
		model.add_child(twin)
		var src := scene.instantiate() as Node3D
		_mirror_meshes(src, Transform3D.IDENTITY, twin, float(w["mirror_z"]))
		src.free()
	model.rotation.y = deg_to_rad(float(w["rot_y"]))
	var size := _aabb_of(root).size
	var s := float(w["length"]) / maxf(size.x, size.z)
	model.scale = Vector3.ONE * s
	var box := _aabb_of(root)
	var c := box.get_center()
	model.position = Vector3(-c.x, float(w["top_y"]) - box.end.y, float(w["center_z"]) - c.z)
	_tone_materials(root)
	return root


## Copies every mesh under `src` into `dest`, reflected across the plane z = plane_z (winding and normals corrected).
static func _mirror_meshes(src: Node, xf: Transform3D, dest: Node3D, plane_z: float) -> void:
	if src is MeshInstance3D and (src as MeshInstance3D).mesh:
		var mi := src as MeshInstance3D
		var out := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var mv := PackedVector3Array()
			mv.resize(verts.size())
			for i in verts.size():
				var p := xf * verts[i]
				mv[i] = Vector3(p.x, p.y, 2.0 * plane_z - p.z)
			arrays[Mesh.ARRAY_VERTEX] = mv
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var mn := PackedVector3Array()
				mn.resize(nrm.size())
				for i in nrm.size():
					var n := (xf.basis * nrm[i]).normalized()
					mn[i] = Vector3(n.x, n.y, -n.z)
				arrays[Mesh.ARRAY_NORMAL] = mn
			arrays[Mesh.ARRAY_TANGENT] = null
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx != null:
				var flipped := PackedInt32Array()
				flipped.resize(idx.size())
				for i in range(0, idx.size(), 3):
					flipped[i] = idx[i]
					flipped[i + 1] = idx[i + 2]
					flipped[i + 2] = idx[i + 1]
				arrays[Mesh.ARRAY_INDEX] = flipped
			else:
				var fv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in range(0, fv.size(), 3):
					var t := fv[i + 1]
					fv[i + 1] = fv[i + 2]
					fv[i + 2] = t
				arrays[Mesh.ARRAY_VERTEX] = fv
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(s, mi.get_active_material(s))
		var copy := MeshInstance3D.new()
		copy.mesh = out
		dest.add_child(copy)
	for c in src.get_children():
		if c is Node3D:
			_mirror_meshes(c, xf * (c as Node3D).transform, dest, plane_z)


## The imported models carry very shiny, bright materials that reflect the sky and look pale blue: make them matte-ish metal.
func _tone_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m is StandardMaterial3D:
					var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.metallic = minf(dup.metallic, 0.25)
					dup.metallic_specular = 0.35
					dup.roughness = maxf(dup.roughness, 0.7)
					dup.albedo_color = dup.albedo_color.darkened(0.15)
					mi.set_surface_override_material(i, dup)
	for c in node.get_children():
		_tone_materials(c)


# ---------------------------------------------------------------- queries used by the player / HUD

func stats() -> Dictionary:
	return WeaponsDB.WEAPONS[current]


func ammo() -> int:
	return state[current]["ammo"]


func reserve() -> int:
	var total := 0
	for m in state[current]["spare"]:
		total += int(m)
	return total


func spare_mags() -> int:
	return (state[current]["spare"] as Array).size()


func move_mult() -> float:
	return lerpf(1.0, float(stats()["ads_move"]), ads_k) * float(stats().get("carry", 1.0))


func current_spread() -> float:
	var s := stats()
	var spread := lerpf(float(s["spread_hip"]), float(s["spread_ads"]), ads_k)
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	spread += float(s["spread_move"]) * clampf(hspeed / Game.WALK_SPEED, 0.0, 1.5) * lerpf(1.0, 0.35, ads_k)
	if not player.is_on_floor():
		spread += 3.0
	if player.crouch_k > 0.5:
		spread *= 0.75
	spread += bloom
	if Game.arm_injured:
		spread = spread * WOUND_SPREAD_MULT + WOUND_SPREAD_ADD          # the off hand: wide and shaky
	return spread


## "The Lander" part two: the right arm is wounded. No rifle, no knife (both slots are locked), the pistol is held in the left hand
## (the viewmodel is mirrored), wide spread and bloom, a slow reload.
const WOUND_SPREAD_MULT := 2.0
const WOUND_SPREAD_ADD := 1.2
const WOUND_BLOOM_MULT := 1.8
const WOUND_RELOAD_MULT := 1.7
const WOUND_MOVE := 0.93


func slot_locked(slot: String) -> bool:
	return Game.arm_injured and slot != "pistol"


## The reload takes this long (seconds): the DB value, longer with the wounded arm.
func reload_total() -> float:
	return float(stats()["reload_time"]) * (WOUND_RELOAD_MULT if Game.arm_injured else 1.0)


func _lock_notice(slot: String) -> void:
	notice = "CAN'T HOLD A RIFLE" if slot == "rifle" else "CAN'T USE THE KNIFE"
	notice_t = 2.2
	Sfx.play(self, "click", -8.0)


## The story wound happened: every rifle on the player falls to the ground, the pistol comes into the (left) hand.
func wound_arm() -> void:
	Game.arm_injured = true
	var scene := get_tree().current_scene
	var arr: Array = loadout["rifle"]
	var i := 0
	for inst in arr:
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		var side := player.global_transform.basis.x
		Pickup.spawn_weapon(scene, player.global_position + fwd.normalized() * 0.8 + side * (0.5 + 0.5 * i), inst["id"], int(inst["ammo"]), inst["spare"])
		i += 1
	arr.clear()
	last_idx["rifle"] = 0
	if active_slot != "pistol" and not (loadout["pistol"] as Array).is_empty():
		_equip("pistol", 0)
		_show_only(current)
	pending_slot = ""
	switching = 0.0
	reloading = false
	reload_t = 0.0
	ads_k = 0.0
	g_down_t = -1.0
	_hide_preview()
	notice = "RIGHT ARM HIT - THE RIFLE FALLS"
	notice_t = 3.5


func can_aim() -> bool:
	return not is_melee() and not reloading and switching <= 0.0 and not player.is_sprinting() and not Game.dead


func is_melee() -> bool:
	return bool(stats().get("melee", false))


## A weapon as the loadout stores it. `rounds` < 0 = a full magazine, `spare_mags` null = a full set of full magazines.
static func new_weapon(id: String, rounds: int = -1, spare_mags = null) -> Dictionary:
	var w: Dictionary = WeaponsDB.WEAPONS[id]
	var sp: Array[int] = []
	if spare_mags == null:
		for i in int(w["spare_mags"]):
			sp.append(int(w["mag"]))
	else:
		for m in spare_mags:
			sp.append(int(m))
	return {"id": id, "ammo": int(w["mag"]) if rounds < 0 else rounds, "spare": sp}


## Every carried weapon as [slot, index], in slot order.
func carried() -> Array:
	var out: Array = []
	for slot in ["pistol", "rifle", "melee"]:
		for i in (loadout[slot] as Array).size():
			out.append([slot, i])
	return out


func _equip(slot: String, idx: int) -> void:
	active_slot = slot
	active_idx = idx
	last_idx[slot] = idx
	var inst: Dictionary = loadout[slot][idx]
	current = inst["id"]
	state = {current: inst}


# ---------------------------------------------------------------- logic

func _physics_process(delta: float) -> void:
	if Game.dead:
		return
	cooldown = maxf(0.0, cooldown - delta)
	empty_click_cd = maxf(0.0, empty_click_cd - delta)
	bloom = move_toward(bloom, 0.0, delta * 6.0)

	# ADS
	var want_ads := HoldInput.held("aim") and can_aim() and not player.climbing
	var rate := 1.0 / maxf(0.05, float(stats()["ads_time"]))
	ads_k = move_toward(ads_k, 1.0 if want_ads else 0.0, rate * delta)
	_update_sway(delta)

	# weapon switching
	if switching > 0.0:
		var before := switching
		switching -= delta
		if before > 0.15 and switching <= 0.15 and pending_slot != "":
			_equip(pending_slot, pending_idx)
			pending_slot = ""
			_show_only(current)
			Sfx.play(self, "bolt", -14.0, 0.9)
	else:
		if Input.is_action_just_pressed("slot_1"):
			_slot_key("pistol")
		elif Input.is_action_just_pressed("slot_2"):
			_slot_key("rifle")
		elif Input.is_action_just_pressed("slot_3"):
			_slot_key("melee")
		elif Input.is_action_just_pressed("cycle_weapon") or Input.is_action_just_pressed("wheel_down"):
			_cycle(1)
		elif Input.is_action_just_pressed("wheel_up"):
			_cycle(-1)

	_update_pickups()
	notice_t = maxf(0.0, notice_t - delta)
	_grenade_input(delta)

	# reload
	if reloading:
		reload_t += delta
		var total := reload_total()
		var k := reload_t / total
		if _reload_sound_stage == 0 and k > 0.25:
			_reload_sound_stage = 1
			Sfx.play(self, "mag_out", -8.0)
		elif _reload_sound_stage == 1 and k > 0.62:
			_reload_sound_stage = 2
			Sfx.play(self, "mag_in", -6.0)
		if reload_t >= total:
			_finish_reload()
	elif Input.is_action_just_pressed("reload") and not player.climbing:
		start_reload()

	# firing
	var s := stats()
	var down := Input.is_action_pressed("fire")
	var pressed := down and not _trigger_was_down
	_trigger_was_down = down
	if _melee_stop > 0.0:
		_melee_stop -= delta
	else:
		melee_t = maxf(0.0, melee_t - delta)
	if _melee_hit_pending and melee_t <= MELEE_SWING_TIME * (1.0 - MELEE_HIT_AT):
		_melee_hit_pending = false
		var kick_dir := [1.0, -1.0, 0.0][_stroke] as float      # the view is tugged along the stroke
		player.add_recoil(-0.5 if _stroke == 2 else -0.15, 0.7 * kick_dir, 9.0)
		_melee_strike()
	takedown_t = maxf(0.0, takedown_t - delta)
	takedown_target = find_takedown()
	if takedown_target != null and cooldown <= 0.0 and Game.has_focus() and not player.climbing and Input.is_action_just_pressed("interact"):
		_do_takedown(takedown_target)
	elif is_melee():
		if pressed and switching <= 0.0 and cooldown <= 0.0 and Game.has_focus() and not player.climbing and not player.is_sprinting():
			if takedown_target != null:
				_do_takedown(takedown_target)
			else:
				_melee_swing()
	elif down and switching <= 0.0 and not reloading and not player.is_sprinting() and Game.has_focus() and not player.climbing:
		if bool(s["auto"]) or pressed:
			if cooldown <= 0.0:
				if int(state[current]["ammo"]) > 0:
					_fire_shot()
				elif empty_click_cd <= 0.0:
					Sfx.play(self, "click", -6.0)
					empty_click_cd = 0.3
					if pressed:
						start_reload()


## Take the first carried weapon with this id into the hands.
func switch_to(id: String) -> void:
	for e in carried():
		if (loadout[e[0]][e[1]] as Dictionary)["id"] == id:
			_start_switch(e[0], e[1])
			return


func _start_switch(slot: String, idx: int) -> void:
	if switching > 0.0 or Game.dead or (slot == active_slot and idx == active_idx):
		return
	if slot_locked(slot):
		_lock_notice(slot)
		return
	if HEAVY_DROP and bool(stats().get("heavy", false)) and hunter_near(HEAVY_DROP_RANGE):
		# the long rifle is too heavy to run with: it stays where you stand (the pistol is the safe choice up close)
		var target: Dictionary = loadout[slot][idx]
		_drop_heavy()
		idx = 0
		for i in (loadout[slot] as Array).size():
			if is_same(loadout[slot][i], target):
				idx = i
	reloading = false
	reload_t = 0.0
	ads_k = 0.0
	pending_slot = slot
	pending_idx = idx
	switching = 0.32


## Is anyone who hunts the player (alerted, chasing, attacking, shooting, holding) within `radius` metres?
func hunter_near(radius: float) -> bool:
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state in [Enemy.State.ALERT, Enemy.State.CHASE, Enemy.State.ATTACK, Enemy.State.SHOOT, Enemy.State.HOLD] \
				and en.global_position.distance_to(player.global_position) < radius:
			return true
	return false


## The weapon in hand falls to the ground in front of the player with its rounds and spare magazines (a pick-up again).
func _drop_heavy() -> void:
	var arr: Array = loadout[active_slot]
	if active_idx >= arr.size():
		return
	var inst: Dictionary = arr[active_idx]
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	var at := player.global_position + fwd.normalized() * 0.9
	Pickup.spawn_weapon(get_tree().current_scene, at, inst["id"], int(inst["ammo"]), inst["spare"])
	arr.remove_at(active_idx)
	last_idx[active_slot] = 0
	notice = "DROPPED  %s" % String(WeaponsDB.WEAPONS[inst["id"]]["short"])
	notice_t = 2.5
	Sfx.play(self, "thump", -6.0, 0.8)
	Game.mark("heavy_drop")


## Scoped with a long rifle the view drifts (`scope_sway` degrees); Shift or Ctrl holds the breath for `breath_time` seconds
## (a tenth of the drift), then the lungs give out: the view swings wide for a moment while the breath comes back.
func _update_sway(delta: float) -> void:
	var s := stats()
	var amp := float(s.get("scope_sway", 0.0))
	if amp <= 0.0 or ads_k < 0.2:
		breath_held = false
		gasp_t = maxf(0.0, gasp_t - delta)
		breath = minf(1.0, breath + delta / BREATH_REGAIN)
		sway_view = sway_view.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))
		return
	var want_hold := (Input.is_action_pressed("sprint") or Input.is_action_pressed("crouch")) and gasp_t <= 0.0 and breath > 0.0
	breath_held = want_hold
	if want_hold:
		breath = maxf(0.0, breath - delta / maxf(0.1, float(s.get("breath_time", 3.0))))
		if breath <= 0.0:
			gasp_t = 1.3
			breath_held = false
	else:
		gasp_t = maxf(0.0, gasp_t - delta)
		breath = minf(1.0, breath + delta / BREATH_REGAIN)
	var k := 0.1 if breath_held else (2.2 if gasp_t > 0.0 else 1.0)
	if player.crouch_k > 0.5:
		k *= 0.7
	k *= 1.0 + clampf(Vector2(player.velocity.x, player.velocity.z).length() / Game.WALK_SPEED, 0.0, 1.5)
	_sway_t += delta
	var a := deg_to_rad(amp) * k * ads_k
	var target := Vector2(sin(_sway_t * 1.1) + 0.5 * sin(_sway_t * 2.3 + 1.0), cos(_sway_t * 0.8) + 0.5 * sin(_sway_t * 1.9 + 2.0)) * a * 0.7
	sway_view = sway_view.lerp(target, 1.0 - exp(-14.0 * delta))


## Number key: bring up the slot's weapon; pressing it again flips to the slot's other weapon.
func _slot_key(slot: String) -> void:
	var arr: Array = loadout[slot]
	if slot_locked(slot):
		_lock_notice(slot)          # even with no rifle in the hands: the key says why
		return
	if arr.is_empty():
		return
	if active_slot == slot:
		if arr.size() > 1:
			_start_switch(slot, 1 - active_idx)
	else:
		_start_switch(slot, mini(int(last_idx[slot]), arr.size() - 1))


func _cycle(dir: int) -> void:
	var list := carried().filter(func(e): return not slot_locked(e[0]))
	if list.size() < 2:
		return
	return _cycle_in(list, dir)


func _cycle_in(list: Array, dir: int) -> void:
	if list.size() < 2:
		return
	var at := 0
	for i in list.size():
		if list[i][0] == active_slot and list[i][1] == active_idx:
			at = i
	var nxt: Array = list[posmod(at + dir, list.size())]
	_start_switch(nxt[0], nxt[1])


# ---------------------------------------------------------------- grenades

## Where a grenade thrown right now starts and how fast it goes: 16 m/s along the aim plus the player's own velocity.
func throw_start() -> Vector3:
	var fwd := -camera.global_transform.basis.z
	var from := camera.global_position + fwd * 0.5 + Vector3(0, -0.1, 0)
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, from, Game.L_WORLD)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		from = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.15      # a wall right in front: it drops at the foot of it
	return from


func throw_velocity() -> Vector3:
	return -camera.global_transform.basis.z * Grenade.THROW_SPEED + player.velocity


func _grenade_input(delta: float) -> void:
	throw_t = maxf(0.0, throw_t - delta)
	var usable := Game.has_focus() and not Game.dead and not player.climbing and Game.grenades > 0 and switching <= 0.0
	if g_down_t < 0.0:
		if usable and throw_t <= 0.0 and Input.is_action_just_pressed("grenade"):
			g_down_t = 0.0
	elif not usable:
		g_down_t = -1.0
		_hide_preview()
	elif Input.is_action_pressed("grenade"):
		g_down_t += delta
		if g_down_t >= PREVIEW_DELAY:
			_show_preview()
	else:
		g_down_t = -1.0
		_hide_preview()
		throw_grenade()
	grenade_k = move_toward(grenade_k, 1.0 if (g_down_t >= 0.0 or throw_t > 0.0) else 0.0, delta * 7.0)
	if throw_arm != null:
		throw_arm.visible = grenade_k > 0.05


## Throw one grenade now (also what releasing G does). Returns it, or null if there is none.
func throw_grenade() -> Grenade:
	if Game.grenades <= 0 or Game.dead:
		return null
	Game.grenades -= 1
	var g := Grenade.new()
	g.setup(throw_start(), throw_velocity())
	get_tree().current_scene.add_child(g)
	throw_t = THROW_TIME
	ads_k = 0.0
	Sfx.play(self, "swing", -2.0, 0.7)
	return g


func _ensure_preview() -> void:
	if _arc_dots != null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 0.07)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.85, 0.3)
	dm.no_depth_test = true
	bm.material = dm
	mm.mesh = bm
	mm.instance_count = ARC_DOTS
	mm.visible_instance_count = 0
	_arc_dots = MultiMeshInstance3D.new()
	_arc_dots.multimesh = mm
	_arc_dots.top_level = true
	_arc_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc_dots)
	var tm := TorusMesh.new()
	tm.inner_radius = Grenade.RADIUS - 0.12
	tm.outer_radius = Grenade.RADIUS
	tm.rings = 32
	tm.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.4, 0.15, 0.8)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = rm
	_arc_ring = MeshInstance3D.new()
	_arc_ring.mesh = tm
	_arc_ring.top_level = true
	_arc_ring.scale = Vector3(1.0, 0.03, 1.0)
	_arc_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc_ring)
	_arc_ring.visible = false


## While G is held: the simulated trajectory as dots and a ring on the ground where it will come to rest (the ring is the
## blast radius, so you see what the explosion will reach).
func _show_preview() -> void:
	_ensure_preview()
	var r := Grenade.predict(player.get_world_3d().direct_space_state, throw_start(), throw_velocity())
	var pts: PackedVector3Array = r["points"]
	var n := mini(pts.size(), ARC_DOTS)
	_arc_dots.multimesh.visible_instance_count = n
	for i in n:
		_arc_dots.multimesh.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	_arc_ring.global_position = (r["rest"] as Vector3) + Vector3(0, 0.02, 0)
	_arc_ring.visible = true


func _hide_preview() -> void:
	if _arc_dots != null:
		_arc_dots.multimesh.visible_instance_count = 0
		_arc_ring.visible = false


# ---------------------------------------------------------------- melee

const MELEE_SWING_TIME := 0.34
const MELEE_HIT_AT := 0.39          # the blow lands this far into the swing: the middle of the fast arc
const MELEE_HITSTOP := 0.055        # the blade sticks in for a moment when it connects
const TAKEDOWN_TIME := 0.6          # grab, stab, lower him: lasts as long as the victim's struggle (Enemy.TAKEDOWN_STRUGGLE)
# phases of a swing as fractions of MELEE_SWING_TIME: wind up (cock the blade), the fast arc, follow-through, then recovery
const SW_WIND := 0.28
const SW_ARC := 0.5
const SW_THROUGH := 0.64
# strokes, offsets from the resting pose: [cocked pos, cocked rot, mid-arc pos, mid-arc rot, follow-through pos, rot]
# (rot: x = tip up, y = tip to the left, z = roll)
const STROKES := [
	# forehand: cocked out to the right with the tip back, snaps across and down to the left
	[Vector3(0.13, 0.06, 0.07), Vector3(0.25, -0.95, 0.7), Vector3(0.0, 0.0, -0.16), Vector3(-0.05, 0.15, 0.55),
		Vector3(-0.3, -0.08, -0.03), Vector3(-0.2, 1.05, 0.35)],
	# backhand: the hand crosses to the left, the edge comes back across to the right
	[Vector3(-0.17, 0.05, 0.05), Vector3(0.2, 0.85, -0.75), Vector3(0.02, 0.0, -0.16), Vector3(-0.05, -0.1, -0.6),
		Vector3(0.2, -0.07, -0.02), Vector3(-0.15, -1.0, -0.35)],
	# stab: drawn back and up beside the cheek, driven straight in
	[Vector3(0.04, 0.07, 0.16), Vector3(0.45, -0.12, 0.15), Vector3(-0.06, -0.03, -0.32), Vector3(-0.2, 0.08, 0.0),
		Vector3(-0.07, -0.05, -0.37), Vector3(-0.3, 0.1, 0.05)],
]


func _melee_swing() -> void:
	cooldown = 60.0 / float(stats()["rpm"])
	melee_t = MELEE_SWING_TIME
	_melee_hit_pending = true
	_melee_stop = 0.0
	if Time.get_ticks_msec() - _last_swing_ms > 1200:
		_last_slash = 1                 # a fresh attack opens with the forehand
	_last_swing_ms = Time.get_ticks_msec()
	if _stroke != 2 and _rng.randf() < 0.22:
		_stroke = 2
	else:
		_last_slash = 1 - _last_slash
		_stroke = _last_slash
	_stroke_k = _rng.randf_range(0.88, 1.12)
	ads_k = 0.0
	Sfx.play(self, "swing", -4.0, float(stats().get("sound_pitch", 1.0)))


## An enemy who has not noticed the player, is in reach and in front of the knife, with a clear line, and has his back to the
## player (more than 120 degrees off his facing). Only while a melee weapon is in hand.
func find_takedown() -> Enemy:
	if not is_melee() or switching > 0.0 or Game.dead or player.is_sprinting() or Game.arm_injured:
		return null
	var reach := float(stats()["reach"])
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var best: Enemy = null
	var best_d := 1.0e9
	for e in Game.enemies:
		var en := e as Enemy
		if not is_instance_valid(en) or not en.can_be_taken_down(player.global_position):
			continue
		var chest := en.takedown_point()
		var to := chest - from
		var d := to.length()
		if d > reach + 0.3 or d < 0.01 or fwd.dot(to / d) < 0.72:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, chest, Game.L_WORLD)
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = en
	return best


## Silent takedown: instant kill, stab animation and sound, no Game.gunshot (nobody hears it).
func _do_takedown(en: Enemy) -> void:
	cooldown = 0.7
	takedown_t = TAKEDOWN_TIME
	_td_jolted = false
	melee_t = 0.0
	_melee_hit_pending = false
	ads_k = 0.0
	Game.takedowns += 1
	en.takedown(player.global_position)
	takedown_target = null
	hit_marker.emit(false, true)
	player.add_recoil(-0.6, 0.0, 6.0)          # lunging in for the grab: the view dips (the stab sound plays when the blade goes in)


## Mid-swing: the nearest enemy in front, inside reach, with a clear line takes the blow.
func _melee_strike() -> void:
	var s := stats()
	var reach := float(s["reach"])
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var best: Enemy = null
	var best_d := 1.0e9
	for e in Game.enemies:
		var en := e as Enemy
		if en.state == Enemy.State.DEAD:
			continue
		var chest := en.takedown_point()
		var to := chest - from
		var d := to.length()
		if d > reach + 0.5 or d < 0.01 or fwd.dot(to / d) < 0.72:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, chest, Game.L_WORLD)
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = en
	if best == null:
		_melee_civilian(from, fwd, reach, s)
		return
	var dir := fwd
	dir.y = 0.0
	dir = dir.normalized()
	var chest_pt := best.global_position + Vector3(0, 1.1 * best.body_scale, 0)
	Game.shots_fired += 1
	Game.shots_hit += 1
	var killed := best.take_hit(float(s["damage"]), "body", dir * float(s["impulse"]) * 1.5, chest_pt)
	hit_marker.emit(false, killed)
	_melee_stop = MELEE_HITSTOP
	player.add_recoil(-0.4, 0.5 * ([1.0, -1.0, 0.0][_stroke] as float), 9.0)
	Sfx.play(self, "hit", -4.0)
	Sfx.play_at(get_tree().current_scene, chest_pt, "thump", 0.0)


## A blade that finds no soldier may find a civilian in front of it.
func _melee_civilian(from: Vector3, fwd: Vector3, reach: float, s: Dictionary) -> void:
	var best: Civilian = null
	var best_d := 1.0e9
	for c in Game.civilians:
		var cv := c as Civilian
		if not is_instance_valid(cv) or cv.state == Civilian.State.DEAD:
			continue
		var to := cv.chest_pos() - from
		var d := to.length()
		if d > reach + 0.5 or d < 0.01 or fwd.dot(to / d) < 0.72 or d >= best_d:
			continue
		if not player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, cv.chest_pos(), Game.L_WORLD)).is_empty():
			continue
		best_d = d
		best = cv
	if best == null:
		return
	var flat := fwd
	flat.y = 0.0
	var killed := best.take_hit(float(s["damage"]), "body", flat.normalized() * float(s["impulse"]), best.chest_pos())
	hit_marker.emit(false, killed)
	notice = "CIVILIAN HIT"
	notice_t = 2.5
	Sfx.play(self, "hit", -4.0)


# ---------------------------------------------------------------- picking things up

func _update_pickups() -> void:
	hover = null
	if Game.dead:
		return
	var best := PICKUP_RANGE
	var pp := player.global_position
	for p in Game.pickups.duplicate():
		if not is_instance_valid(p):
			continue
		var pk := p as Pickup
		var d := pp - pk.global_position
		if absf(d.y) > 2.2:
			continue
		var h := Vector2(d.x, d.z).length()
		if pk.is_grenade:
			if h < AMMO_RANGE and Game.grenades < Game.MAX_GRENADES:
				Game.grenades += 1
				notice = "+1 GRENADE"
				notice_t = 2.0
				pk.take()
		elif pk.is_medkit:
			if h < AMMO_RANGE and player.can_heal():
				player.start_heal()
				pk.take()
		elif pk.is_ammo:
			if h < AMMO_RANGE and _take_ammo(pk):
				pk.take()
		elif h < best:
			best = h
			hover = pk
	if hover != null and Input.is_action_just_pressed("pickup") and Game.has_focus() and switching <= 0.0:
		pick_up(hover)


## Loose magazine: goes to a carried weapon of that type that has room (finite: MAX_SPARE_MAGS each).
func _take_ammo(pk: Pickup) -> bool:
	var target: Dictionary = {}
	for e in carried():
		var inst: Dictionary = loadout[e[0]][e[1]]
		if inst["id"] != pk.weapon_id:
			continue
		var n := (inst["spare"] as Array).size()
		if n < MAX_SPARE_MAGS and (target.is_empty() or n < (target["spare"] as Array).size()):
			target = inst
	if target.is_empty():
		return false
	var cap := int(WeaponsDB.WEAPONS[pk.weapon_id]["mag"])
	(target["spare"] as Array).append(mini(pk.ammo, cap))
	Sfx.play(self, "mag_in", -8.0, 1.2)
	notice = "+ MAGAZINE  %s  (%d rds)" % [String(WeaponsDB.WEAPONS[pk.weapon_id]["short"]), mini(pk.ammo, cap)]
	notice_t = 2.2
	return true


## Take a lying weapon. Free slot: it goes in. Full slot (2): it replaces the one in hand (or last used) and that one is dropped.
func pick_up(pk: Pickup) -> void:
	if switching > 0.0 or Game.dead:
		return
	var inst := pk.make_instance()
	var slot := String(WeaponsDB.WEAPONS[pk.weapon_id]["slot"])
	if slot_locked(slot):
		_lock_notice(slot)
		return
	var arr: Array = loadout[slot]
	var idx := 0
	if arr.size() < MAX_PER_SLOT:
		arr.append(inst)
		idx = arr.size() - 1
	else:
		idx = active_idx if active_slot == slot else mini(int(last_idx[slot]), arr.size() - 1)
		var old: Dictionary = arr[idx]
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		var at := player.global_position + fwd.normalized() * 1.0
		Pickup.spawn_weapon(get_tree().current_scene, at, old["id"], int(old["ammo"]), old["spare"])
		arr[idx] = inst
	pk.take()
	hover = null
	Sfx.play(self, "bolt", -8.0, 1.1)
	notice = "PICKED UP  %s" % String(WeaponsDB.WEAPONS[inst["id"]]["name"])
	notice_t = 2.2
	if slot == active_slot and idx == active_idx:
		# replaced the weapon in hand: swap models right away
		reloading = false
		reload_t = 0.0
		ads_k = 0.0
		_equip(slot, idx)
		_show_only(current)
	else:
		_start_switch(slot, idx)


func start_reload() -> void:
	if reloading or switching > 0.0 or is_melee():
		return
	var st: Dictionary = state[current]
	if int(st["ammo"]) >= int(stats()["mag"]):
		return
	var has_ammo := false
	for m in st["spare"]:
		if int(m) > 0:
			has_ammo = true
	if not has_ammo:
		return
	reloading = true
	reload_t = 0.0
	_reload_sound_stage = 0
	ads_k = 0.0


func _finish_reload() -> void:
	reloading = false
	reload_t = 0.0
	var st: Dictionary = state[current]
	var spare: Array = st["spare"]
	var best := -1
	for i in spare.size():
		if best < 0 or int(spare[i]) > int(spare[best]):
			best = i
	if best < 0:
		return
	var fresh := int(spare[best])
	spare.remove_at(best)
	st["ammo"] = fresh
	st["ammo"] = fresh


func add_ammo_mags(n: int) -> void:
	for e in carried():
		var inst: Dictionary = loadout[e[0]][e[1]]
		for i in n:
			if int(WeaponsDB.WEAPONS[inst["id"]]["mag"]) > 0 and (inst["spare"] as Array).size() < MAX_SPARE_MAGS:
				(inst["spare"] as Array).append(int(WeaponsDB.WEAPONS[inst["id"]]["mag"]))


func _fire_shot() -> void:
	var s := stats()
	var st: Dictionary = state[current]
	st["ammo"] = int(st["ammo"]) - 1
	cooldown = 60.0 / float(s["rpm"])
	Game.shots_fired += 1
	Game.mark("shot")

	var spread_deg := current_spread()
	bloom = minf(bloom + float(s["spread_per_shot"]) * (WOUND_BLOOM_MULT if Game.arm_injured else 1.0), float(s["spread_max_bloom"]) * (WOUND_BLOOM_MULT if Game.arm_injured else 1.0))

	var cam_xf := camera.global_transform
	var origin := cam_xf.origin
	var dir := _spread_dir(cam_xf.basis, spread_deg)
	var to := origin + dir * 400.0
	var space := player.get_world_3d().direct_space_state
	var hit: Dictionary
	var shell_v := float(s.get("bullet_speed", 0.0))
	if shell_v > 0.0:         # a slow shell: it falls on its way, so a shot at a far target must be aimed high
		hit = shell_trace(space, origin, dir, shell_v, 400.0)
		to = shell_end
	else:
		var q := PhysicsRayQueryParameters3D.create(origin, to, Game.L_WORLD | Game.L_HITBOX)
		q.collide_with_areas = true
		q.collide_with_bodies = true
		hit = space.intersect_ray(q)

	var muzzle_pos: Vector3 = (muzzles[current] as Node3D).global_position
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var dist := origin.distance_to(end)
		var collider: Object = hit["collider"]
		if collider is Area3D and (collider as Area3D).has_meta("civilian"):
			# a civilian: he takes the damage like anyone, you get the toast (the mission goes on)
			var cpart: String = (collider as Area3D).get_meta("part")
			var victim: Civilian = (collider as Area3D).get_meta("owner_civ")
			var cdmg := float(s["damage"]) * (float(s["head_mult"]) if cpart == "head" else 1.0)
			Game.shots_hit += 1
			var ckilled := victim.take_hit(cdmg, cpart, dir * float(s["impulse"]), end)
			hit_marker.emit(cpart == "head", ckilled)
			notice = "CIVILIAN HIT"
			notice_t = 2.5
			Sfx.play_at(get_tree().current_scene, end, "thump", -2.0)
		elif collider is Area3D and (collider as Area3D).has_meta("part"):
			var part: String = (collider as Area3D).get_meta("part")
			var enemy: Enemy = (collider as Area3D).get_meta("enemy")
			var f := 1.0
			if dist > float(s["falloff_start"]):
				f = lerpf(1.0, float(s["falloff_min"]), clampf((dist - float(s["falloff_start"])) / (float(s["falloff_end"]) - float(s["falloff_start"])), 0.0, 1.0))
			var dmg := float(s["damage"]) * f * (float(s["head_mult"]) if part == "head" else 1.0)
			if part == "legs":
				dmg *= 0.75
			Game.shots_hit += 1
			var killed := enemy.take_hit(dmg, part, dir * float(s["impulse"]), end)
			hit_marker.emit(part == "head", killed)
			Sfx.play(self, "headshot" if part == "head" else "hit", -4.0)
			Sfx.play_at(get_tree().current_scene, end, "thump", -2.0)
		elif collider.has_meta("hull"):
			# the landing craft: a bright spark and a ringing hit
			(collider.get_meta("hull") as Object).call("spark", end, hit["normal"])
			Sfx.play_at(get_tree().current_scene, end, "hit", 2.0, 0.55, 140.0, 12.0)
		else:
			_spawn_impact(end, hit["normal"])
			Sfx.play_at(get_tree().current_scene, end, "impact", -4.0, randf_range(0.9, 1.1))

	_tracer(muzzle_pos, end, s.get("glow", Color(1.0, 0.85, 0.45)), float(s.get("tracer_w", 0.004)))
	if bool(s.get("casing", true)):
		_eject_casing()
	_muzzle_flash()
	Sfx.play(self, String(s.get("sound", current)), -2.0, float(s.get("sound_pitch", 1.0)) * randf_range(0.97, 1.03))
	Game.gunshot.emit(origin, float(s["loudness"]))
	fired.emit(current)
	if bool(s.get("bolt", false)):          # the bolt is worked: ejects the brass and chambers the next round
		get_tree().create_timer(0.55).timeout.connect(func() -> void:
			if not Game.dead:
				Sfx.play(self, "bolt", -5.0, 0.7))

	# recoil: the view itself climbs and has to be pulled back down; ADS tames it
	var tame := lerpf(1.0, 0.7, ads_k)
	player.add_recoil(float(s["recoil_pitch"]) * tame * _rng.randf_range(0.85, 1.15), _rng.randf_range(-1.0, 1.0) * float(s["recoil_yaw"]) * tame, float(s["recoil_recover"]))
	kick = minf(kick + 0.035 * (1.0 - ads_k * 0.5), 0.08)
	kick_pitch = minf(kick_pitch + 0.07 * (1.0 - ads_k * 0.4), 0.2)

	if int(st["ammo"]) <= 0 and reserve() > 0:
		# empty: ready to reload on the next trigger pull (the click will start it)
		pass


## A shell flying at `speed` m/s that starts along `dir` and falls under SHELL_G: traced in straight pieces of SHELL_STEP metres.
## Returns the first hit (world or hit boxes) or an empty dictionary; `shell_end` is the hit point or the end of the path.
func shell_trace(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, speed: float, max_dist: float) -> Dictionary:
	var s0 := 0.0
	var p0 := origin
	while s0 < max_dist:
		var s1 := minf(s0 + SHELL_STEP, max_dist)
		var t1 := s1 / speed
		var p1 := origin + dir * s1 + Vector3(0.0, -0.5 * SHELL_G * t1 * t1, 0.0)
		var q := PhysicsRayQueryParameters3D.create(p0, p1, Game.L_WORLD | Game.L_HITBOX)
		q.collide_with_areas = true
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			shell_end = hit["position"]
			return hit
		s0 = s1
		p0 = p1
	shell_end = p0
	return {}


func _spread_dir(basis: Basis, spread_deg: float) -> Vector3:
	var ang := deg_to_rad(spread_deg) * sqrt(_rng.randf())
	var rot := _rng.randf() * TAU
	var d := -basis.z
	d = d.rotated(basis.x, sin(rot) * ang)
	d = d.rotated(basis.y, cos(rot) * ang)
	return d.normalized()


func _tracer(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.85, 0.45), width: float = 0.004) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, minf(len, 3.0))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var scene := get_tree().current_scene
	scene.add_child(mi)
	# the streak is a short segment that flies from the muzzle to the target
	var dir := (to - from).normalized()
	var seg := minf(len, 3.0)
	mi.global_position = from + dir * seg * 0.5
	mi.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var travel := maxf(0.0, len - seg)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", from + dir * (travel + seg * 0.5), clampf(len / 420.0, 0.03, 0.2))
	tw.tween_callback(mi.queue_free)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.36, 0.25)
	m.material = mat
	p.mesh = m
	p.finished.connect(p.queue_free)
	get_tree().current_scene.add_child(p)
	p.global_position = pos + normal * 0.03


func _muzzle_flash() -> void:
	flash_t = 0.045
	flash_node.visible = true
	flash_light.visible = true
	flash_node.rotation.z = _rng.randf() * TAU


func _eject_casing() -> void:
	var w := stats()
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = Game.L_WORLD
	rb.continuous_cd = true
	rb.mass = 0.02
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.6
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.012, 0.012, 0.04)
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.35
	bm.material = mat
	mi.mesh = bm
	rb.add_child(mi)
	get_tree().current_scene.add_child(rb)
	var port: Vector3 = holder.global_transform * Vector3(0.04, float(w["top_y"]) - 0.02, float(w["center_z"]) - 0.02)
	rb.global_position = port
	var b := camera.global_transform.basis
	rb.linear_velocity = player.velocity * 0.6 + b.x * _rng.randf_range(1.8, 3.0) + b.y * _rng.randf_range(1.0, 2.2) + b.z * _rng.randf_range(-0.3, 0.6)
	rb.angular_velocity = Vector3(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30), _rng.randf_range(-30, 30))
	_casings.append(rb)
	if _casings.size() > MAX_CASINGS:
		var old = _casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var life := Timer.new()
	life.wait_time = 5.0
	life.one_shot = true
	life.autostart = true
	life.timeout.connect(rb.queue_free)
	rb.add_child(life)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	var want_hum := current == "rifle" and not Game.dead      # the pulse rifle hums softly while it is in hand
	if hum != null and want_hum != hum.playing:
		if want_hum:
			hum.play()
		else:
			hum.stop()
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			flash_node.visible = false
			flash_light.visible = false

	var s := stats()
	kick = move_toward(kick, 0.0, delta * 0.5)
	kick_pitch = lerpf(kick_pitch, 0.0, 1.0 - exp(-12.0 * delta))
	sway = sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	sway += player.consume_look_delta() * Vector2(-0.0007, -0.0007)
	sway = sway.limit_length(0.05)

	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := player.is_on_floor() and hspeed > 0.5
	bob_t += delta * (hspeed * 1.5 if moving else 0.0)
	var bob_amt := (0.006 + 0.004 * clampf(hspeed / Game.SPRINT_SPEED, 0.0, 1.0)) * (1.0 - ads_k * 0.85)
	var bob := Vector3(sin(bob_t) * bob_amt, absf(cos(bob_t)) * bob_amt * 0.8, 0.0)

	var ads_pos := _ads_pos(s)
	var pos := HIP_POS.lerp(ads_pos, ads_k) + bob + Vector3(sway.x, sway.y, 0.0) + Vector3(0, 0, kick)
	var rot := Vector3(kick_pitch, 0, 0)

	if player.is_sprinting():
		pos += Vector3(0.05, -0.06, 0.02)
		rot += Vector3(0.0, 0.45, 0.15)

	if reloading:
		var k := clampf(reload_t / reload_total(), 0.0, 1.0)
		var dip := sin(PI * k)
		pos += Vector3(-0.04 * dip, -0.16 * dip, 0.03 * dip)
		rot += Vector3(-0.55 * dip, 0.15 * dip, 0.5 * dip)
	var snap := false               # the fast part of a stroke: the viewmodel follows its pose without smoothing
	if is_melee() and melee_t <= 0.0 and takedown_t <= 0.0:
		# at rest the blade breathes a little in the hand
		var tt := Time.get_ticks_msec() * 0.001
		pos += Vector3(0.003 * sin(tt * 0.7), 0.004 * sin(tt * 1.4), 0.0)
		rot += Vector3(0.015 * sin(tt * 1.4 + 0.5), 0.0, 0.03 * sin(tt * 0.7))
	if melee_t > 0.0:
		var mk := 1.0 - melee_t / MELEE_SWING_TIME           # 0 -> 1
		var pr := _stroke_pose(mk)
		pos += pr[0]
		rot += pr[1]
		snap = mk > SW_WIND - 0.04 and mk < SW_THROUGH
	if grenade_k > 0.0:
		# the weapon dips while the other arm winds up and throws
		pos += Vector3(0.08, -0.22, 0.06) * grenade_k
		rot += Vector3(-0.45, 0.0, 0.25) * grenade_k
	if takedown_t > 0.0:
		# takedown, the attacker's half (the victim's half is Enemy.takedown): the left hand clamps over his mouth while the
		# blade is cocked back; it drives in hard, shudders, twists; both arms lower him, then the knife pulls free
		var tk := 1.0 - takedown_t / TAKEDOWN_TIME
		var cock := smoothstep(0.0, 0.16, tk) * (1.0 - smoothstep(0.16, 0.26, tk))
		var drive := smoothstep(0.16, 0.26, tk) * (1.0 - smoothstep(0.8, 0.97, tk))
		var twist := smoothstep(0.32, 0.46, tk) * (1.0 - smoothstep(0.78, 0.92, tk))
		var lower := smoothstep(0.45, 0.75, tk) * (1.0 - smoothstep(0.84, 1.0, tk))
		var shudder := sin(tk * 110.0) * smoothstep(0.24, 0.27, tk) * (1.0 - smoothstep(0.27, 0.45, tk))
		pos += Vector3(0.05, 0.07, 0.14) * cock + Vector3(-0.12, -0.05, -0.4) * drive + Vector3(0.0, -0.11, 0.04) * lower \
			+ Vector3(0.006, 0.004, 0.0) * shudder
		rot += Vector3(0.55, -0.1, 0.3) * cock + Vector3(-0.85, 0.2, -0.1) * drive + Vector3(0.0, 0.0, 0.55) * twist \
			+ Vector3(-0.25, 0.0, 0.0) * lower + Vector3(0.0, 0.0, 0.05) * shudder
		snap = tk > 0.14 and tk < 0.5
		if not _td_jolted and tk >= 0.24:
			_td_jolted = true                        # the blade is in: the view jolts and the stab is heard now
			player.add_recoil(-1.3, 0.4, 7.0)
			Sfx.play(self, "stab", -2.0)
	if grab_arm != null:
		var gk := 0.0
		if takedown_t > 0.0:
			var tg := 1.0 - takedown_t / TAKEDOWN_TIME
			var reach_k := clampf(tg / 0.14, 0.0, 1.0)
			gk = (1.0 - pow(1.0 - reach_k, 3.0)) * (1.0 - smoothstep(0.82, 1.0, tg))      # shoots out and clamps, lets go at the end
			var yank := smoothstep(0.2, 0.28, tg) * (1.0 - smoothstep(0.5, 0.7, tg))      # pulls him back onto the blade
			var lower_g := smoothstep(0.45, 0.75, tg)
			grab_arm.position = Vector3(-0.22 + 0.19 * gk, -0.36 + 0.16 * gk - 0.1 * lower_g, -0.18 - 0.34 * gk + 0.07 * yank)
			grab_arm.rotation = Vector3(0.9 - 1.15 * gk - 0.2 * lower_g + 0.15 * yank, 0.25 * gk, 0.15 * gk)
		grab_arm.visible = gk > 0.02 and not is_scoped()
	if switching > 0.0:
		var k2 := 1.0 - absf(switching / 0.32 * 2.0 - 1.0)   # 0 -> 1 -> 0
		pos += Vector3(0.0, -0.45 * k2, 0.1 * k2)
		rot += Vector3(-0.7 * k2, 0.0, 0.0)

	if Game.arm_injured:
		pos.x = -pos.x                        # the pistol is in the LEFT hand now: the viewmodel sits on the left side
		rot.y = -rot.y
		rot.z = -rot.z
	if wound_arm_node != null:
		wound_arm_node.visible = Game.arm_injured and not is_scoped()
	if throw_arm != null:
		var swing := 0.0 if throw_t <= 0.0 else 1.0 - throw_t / THROW_TIME       # 0 wind-up pose .. 1 follow-through
		var s2 := sin(PI * 0.5 * minf(swing * 1.6, 1.0))
		throw_arm.position = Vector3((0.24 - 0.12 * s2) * (-1.0 if Game.arm_injured else 1.0), -0.34 + 0.2 * s2 - 0.1 * (1.0 - grenade_k), -0.28 - 0.3 * s2)
		throw_arm.rotation = Vector3(lerpf(0.9, -0.7, s2), 0.0, 0.0)
		throw_arm.visible = grenade_k > 0.05 and not (swing > 0.7)
	# drawing a blade: it flips once end over end in the hand as it comes up
	if models.has(current):
		var flip := 0.0
		if is_melee() and switching > 0.0 and switching < 0.15:
			flip = -TAU * (1.0 - pow(switching / 0.15, 3.0))
		(models[current] as Node3D).rotation.x = flip
	holder.visible = not is_scoped()
	holder.position = holder.position.lerp(pos, 1.0 - exp(-(140.0 if snap else 30.0) * delta))
	holder.rotation = holder.rotation.lerp(rot, 1.0 - exp(-(140.0 if snap else 24.0) * delta))


## The viewmodel offset [pos, rot] of the swing in progress at `mk` (0 -> 1): ease into the cocked pose, a fast arc through
## the middle pose (fastest where the blow lands), drift a little further, then ease back to rest.
func _stroke_pose(mk: float) -> Array:
	var st: Array = STROKES[_stroke]
	var cp: Vector3 = st[0] * _stroke_k
	var cr: Vector3 = st[1] * _stroke_k
	var tp: Vector3 = st[4] * _stroke_k
	var tr: Vector3 = st[5] * _stroke_k
	if mk < SW_WIND:
		var e := smoothstep(0.0, SW_WIND, mk)
		return [cp * e, cr * e]
	if mk < SW_ARC:
		# quadratic curve from the cocked pose through the mid-arc pose to the follow-through pose
		var a := smoothstep(SW_WIND, SW_ARC, mk)
		var mp: Vector3 = st[2] * _stroke_k
		var mr: Vector3 = st[3] * _stroke_k
		var ctl_p := 2.0 * mp - 0.5 * (cp + tp)
		var ctl_r := 2.0 * mr - 0.5 * (cr + tr)
		var b0 := (1.0 - a) * (1.0 - a)
		var b1 := 2.0 * a * (1.0 - a)
		var b2 := a * a
		return [cp * b0 + ctl_p * b1 + tp * b2, cr * b0 + ctl_r * b1 + tr * b2]
	var over := 1.0 + 0.1 * smoothstep(SW_ARC, SW_THROUGH, mk)       # carries on a little past the end of the arc
	var back := 1.0 - smoothstep(SW_THROUGH, 1.0, mk)
	return [tp * over * back, tr * over * back]


## Where the viewmodel sits when aiming. Weapons with a .glb carry a hand-calibrated `ads_pos`; the box-built ones
## are placed so the tips of their iron sights sit on the line of sight, a rear-sight's distance from the eye.
func _ads_pos(s: Dictionary) -> Vector3:
	if s.has("glow") and not bool(s.get("melee", false)):
		return Vector3(0.0, -(float(s["top_y"]) + SIGHT_H), -0.3 - (float(s["center_z"]) + float(s["length"]) * 0.25))
	return s["ads_pos"]


## High-zoom weapons (rail rifle) look through a scope: the gun is hidden and the HUD draws the scope mask.
func is_scoped() -> bool:
	return float(stats()["ads_fov"]) < 40.0 and ads_k > 0.8


## Menu button: the LR-9 long rifle and the HG-60 heavy gun, both full with the most spare magazines, in the two rifle slots; the LR-9 in hand.
func give_heavy_set() -> void:
	var set: Array = []
	for id in ["sniper", "hmg"]:
		var mag := int(WeaponsDB.WEAPONS[id]["mag"])
		var spare: Array = []
		for i in MAX_SPARE_MAGS:
			spare.append(mag)
		set.append(new_weapon(id, mag, spare))
	loadout["rifle"] = set
	last_idx["rifle"] = 0
	reloading = false
	reload_t = 0.0
	ads_k = 0.0
	if active_slot == "rifle":
		_equip("rifle", 0)
		_show_only(current)
	else:
		_start_switch("rifle", 0)
	notice = "LR-9 + HG-60  FULL AMMO"
	notice_t = 2.5
