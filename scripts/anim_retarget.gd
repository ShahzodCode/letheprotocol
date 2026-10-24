class_name AnimRetarget
## Copies a clip made for one humanoid skeleton onto another (models/anims clips onto the soldiers' rigs). Bones are paired by role (the Mixamo
## name without prefix and number: "mixamorig_LeftArm_9" and "Bind_LeftArm_016_017" are both "LeftArm"; the M4 soldier through M4_ROLES).
## Each paired bone takes the same turn away from its own rest pose in the world (the clip is sampled at 30 Hz, the chain of the target is
## rebuilt from it, so differing rest poses and bone axes do not matter); the hips' travel is scaled by the ratio of the two hip heights.
## Run once per rig and clip (the result is stored in the rig's animation library), never while playing.

const STEP := 1.0 / 30.0

## The M4 soldier's bones (name without the trailing "_NN") and the Mixamo role each one takes its motion from. Its chest takes the top spine
## bone's turn (it has two spine bones, Mixamo three); fingers stay as they are.
const M4_ROLES := {"hips": "Hips", "spine": "Spine", "chest": "Spine2", "neck": "Neck", "head": "Head", "head_end": "HeadTop",
	"shoulder.L": "LeftShoulder", "arm.L": "LeftArm", "forearm.L": "LeftForeArm", "hand.L": "LeftHand",
	"shoulder.R": "RightShoulder", "arm.R": "RightArm", "forearm.R": "RightForeArm", "hand.R": "RightHand",
	"upleg.L": "LeftUpLeg", "leg.L": "LeftLeg", "foot.L": "LeftFoot", "toe.L": "LeftToeBase",
	"upleg.R": "RightUpLeg", "leg.R": "RightLeg", "foot.R": "RightFoot", "toe.R": "RightToeBase",
	"index.L": "LeftHandIndex1", "pinky.L": "LeftHandPinky1", "index.R": "RightHandIndex1", "pinky.R": "RightHandPinky1"}

## Two bones across the hand (index to little finger): they give the hand's roll, which the bone direction alone does not (used for the M4 soldier).
const LATERAL := {"LeftHand": ["LeftHandIndex1", "LeftHandPinky1"], "RightHand": ["RightHandIndex1", "RightHandPinky1"]}


## The bone each role points at (its direction in the rest pose), where both rigs have both.
const CHILD := {"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head", "Head": "HeadTop",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandIndex1",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandIndex1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase"}


static func role_of(bone: String, m4: bool) -> String:
	if m4:
		return String(M4_ROLES.get(bone.rsplit("_", true, 1)[0], ""))
	var parts := bone.split("_")
	return parts[1] if parts.size() > 1 else ""


## Bone indices parents first.
static func _order(sk: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	var done := {}
	while out.size() < sk.get_bone_count():
		var progressed := false
		for i in sk.get_bone_count():
			if done.has(i):
				continue
			var p := sk.get_bone_parent(i)
			if p < 0 or done.has(p):
				out.append(i)
				done[i] = true
				progressed = true
		if not progressed:
			break
	return out


## The skeleton's transform inside its model root (the nodes between them, not the root itself).
static func _body_xf(sk: Skeleton3D, body: Node3D) -> Transform3D:
	var xf := sk.transform
	var p := sk.get_parent()
	while p != null and p != body:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _rest_globals(sk: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for i in sk.get_bone_count():
		out.append(Quaternion(sk.get_bone_global_rest(i).basis.orthonormalized()))
	return out


static func _rest_locals(sk: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for i in sk.get_bone_count():
		out.append(Quaternion(sk.get_bone_rest(i).basis.orthonormalized()))
	return out


## The bone that carries the whole body: the hips, or - when the spine hangs on a bone above them (a root bone) - that bone.
static func _carrier(sk: Skeleton3D, hips: int, spine: int) -> int:
	var anc := {}
	var b := hips
	while b >= 0:
		anc[b] = true
		b = sk.get_bone_parent(b)
	var c := spine
	while c >= 0 and not anc.has(c):
		c = sk.get_bone_parent(c)
	return c if c >= 0 else hips


static func _roles_of(sk: Skeleton3D, m4: bool) -> Dictionary:
	var d := {}
	for i in sk.get_bone_count():
		var r := role_of(sk.get_bone_name(i), m4)
		if r != "" and not d.has(r):
			d[r] = i
	return d


static func _dir(sk: Skeleton3D, xf: Transform3D, a: int, b: int) -> Vector3:
	return ((xf * sk.get_bone_global_rest(b)).origin - (xf * sk.get_bone_global_rest(a)).origin).normalized()


## The turn (in model space) that takes the target bone's rest orientation to the one that points the way the source bone points in the source's
## rest pose; with `lateral`, also the roll about the bone from the bones across the hand.
static func _role_fix(role: String, src_sk: Skeleton3D, xs: Transform3D, s_roles: Dictionary, tgt_sk: Skeleton3D, xt: Transform3D, t_roles: Dictionary,
		lateral: bool) -> Quaternion:
	var child: String = CHILD.get(role, "")
	if child == "" or not (s_roles.has(role) and s_roles.has(child) and t_roles.has(role) and t_roles.has(child)):
		return Quaternion.IDENTITY
	var dir_s := _dir(src_sk, xs, s_roles[role], s_roles[child])
	var dir_t := _dir(tgt_sk, xt, t_roles[role], t_roles[child])
	if dir_s.length() < 0.5 or dir_t.length() < 0.5 or dir_s.dot(dir_t) < -0.99:
		return Quaternion.IDENTITY
	var aim := Quaternion(dir_t, dir_s)
	if lateral and LATERAL.has(role):
		var lat: Array = LATERAL[role]
		if s_roles.has(lat[0]) and s_roles.has(lat[1]) and t_roles.has(lat[0]) and t_roles.has(lat[1]):
			var lat_s := _dir(src_sk, xs, s_roles[lat[0]], s_roles[lat[1]])
			var lat_t := aim * _dir(tgt_sk, xt, t_roles[lat[0]], t_roles[lat[1]])
			var a := lat_t - dir_s * lat_t.dot(dir_s)
			var b := lat_s - dir_s * lat_s.dot(dir_s)
			if a.length() > 0.1 and b.length() > 0.1:
				return Quaternion(dir_s, a.signed_angle_to(b, dir_s)) * aim
	return aim


## How the target bone's frame sits against the source bone's frame once a clip is carried over by `retarget` (the target bone's frame is the
## source bone's frame turned by this): what is fixed in the source's hand (a rifle) is turned by its inverse to sit right in the target's.
static func frame_turn(src_sk: Skeleton3D, src_body: Node3D, tgt_sk: Skeleton3D, tgt_body: Node3D, role: String, tgt_m4: bool) -> Quaternion:
	var s_roles := _roles_of(src_sk, false)
	var t_roles := _roles_of(tgt_sk, tgt_m4)
	var si: int = s_roles.get(role, -1)
	var tj: int = t_roles.get(role, -1)
	if si < 0 or tj < 0:
		return Quaternion.IDENTITY
	var xs := _body_xf(src_sk, src_body)
	var xt := _body_xf(tgt_sk, tgt_body)
	var rs := Quaternion(xs.basis.orthonormalized())
	var rt := Quaternion(xt.basis.orthonormalized())
	var fixq := _role_fix(role, src_sk, xs, s_roles, tgt_sk, xt, t_roles, tgt_m4)
	var gs := Quaternion(src_sk.get_bone_global_rest(si).basis.orthonormalized())
	var gt := Quaternion(tgt_sk.get_bone_global_rest(tj).basis.orthonormalized())
	return (rs * gs).inverse() * fixq * (rt * gt)


## `src`: the clip on `src_sk` (inside `src_body`); the result animates `tgt_sk` (inside `tgt_body`), its track paths start with `prefix`
## (the skeleton's path from the AnimationPlayer's root). `flatten`: the hips stay over the feet's start (no travel along the ground).
static func retarget(src: Animation, src_sk: Skeleton3D, src_body: Node3D, tgt_sk: Skeleton3D, tgt_body: Node3D, prefix: String,
		tgt_m4: bool, src_m4: bool, flatten: bool) -> Animation:
	var xs := _body_xf(src_sk, src_body)
	var xt := _body_xf(tgt_sk, tgt_body)
	var rs := Quaternion(xs.basis.orthonormalized())
	var rt := Quaternion(xt.basis.orthonormalized())
	var n_s := src_sk.get_bone_count()
	var n_t := tgt_sk.get_bone_count()
	var s_roles := {}
	for i in n_s:
		var r := role_of(src_sk.get_bone_name(i), src_m4)
		if r != "" and not s_roles.has(r):
			s_roles[r] = i
	var t_map := {}                 # target bone -> source bone
	var used := {}
	for j in n_t:
		var r2 := role_of(tgt_sk.get_bone_name(j), tgt_m4)
		if r2 != "" and s_roles.has(r2) and not used.has(r2):
			t_map[j] = s_roles[r2]
			used[r2] = true
	var rot_track := {}             # source bone -> its rotation track
	var pos_track := -1
	var hips_s: int = s_roles.get("Hips", -1)
	var move_s := hips_s                # the source bone whose position carries the whole body (the hips, or a root bone above them)
	if hips_s >= 0 and s_roles.has("Spine"):
		move_s = _carrier(src_sk, hips_s, s_roles["Spine"])
	for t in src.get_track_count():
		var bi := src_sk.find_bone(src.track_get_path(t).get_concatenated_subnames())
		if bi < 0:
			continue
		var ty := src.track_get_type(t)
		if ty == Animation.TYPE_ROTATION_3D:
			rot_track[bi] = t
		elif ty == Animation.TYPE_POSITION_3D and bi == move_s:
			pos_track = t
	var hips_t := -1
	for j in t_map:
		if int(t_map[j]) == hips_s:
			hips_t = j
	var gs := _rest_globals(src_sk)
	var ls := _rest_locals(src_sk)
	var gt := _rest_globals(tgt_sk)
	var lt := _rest_locals(tgt_sk)
	# Rest poses differ (a T-pose clip, a rig resting with its arms down): `fix[j]` turns the target bone's rest orientation so that its bone
	# points the way the source bone points in the source's rest pose (the shortest turn, in model space); the clip's turn is then applied on that.
	var fix: Array[Quaternion] = []
	fix.resize(n_t)
	fix.fill(Quaternion.IDENTITY)
	var role_of_t := {}
	for j in t_map:
		role_of_t[role_of(tgt_sk.get_bone_name(j), tgt_m4)] = j
	for r3 in CHILD:
		if role_of_t.has(r3):
			fix[role_of_t[r3]] = _role_fix(r3, src_sk, xs, s_roles, tgt_sk, xt, role_of_t, tgt_m4)
	var out := Animation.new()
	out.length = src.length
	var tracks := {}
	for j in t_map:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath("%s:%s" % [prefix, tgt_sk.get_bone_name(j)]))
		tracks[j] = tr
	var hips_track := -1
	var k := 1.0
	var s_rest_o := Vector3.ZERO
	var t_rest_o := Vector3.ZERO
	var hips_s_parent := -1
	var hips_t_parent := -1
	var t_scale := Basis.IDENTITY               # the target hips' parent's scale (its rest rotation taken out)
	if hips_t >= 0 and hips_s >= 0:
		# the bone that carries the whole body: the hips, or - when the spine hangs on a bone above them (a root bone) - that bone
		var move_t := hips_t
		if role_of_t.has("Spine"):
			move_t = _carrier(tgt_sk, hips_t, role_of_t["Spine"])
		hips_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath("%s:%s" % [prefix, tgt_sk.get_bone_name(move_t)]))
		var th := (xt * tgt_sk.get_bone_global_rest(hips_t)).origin.y
		var sh := (xs * src_sk.get_bone_global_rest(hips_s)).origin.y
		if sh > 0.0001:
			k = th / sh
		s_rest_o = src_sk.get_bone_rest(move_s).origin
		t_rest_o = tgt_sk.get_bone_rest(move_t).origin
		hips_s_parent = src_sk.get_bone_parent(move_s)
		hips_t_parent = tgt_sk.get_bone_parent(move_t)
		if hips_t_parent >= 0:
			var pb := tgt_sk.get_bone_global_rest(hips_t_parent).basis
			t_scale = Basis(Quaternion(pb.orthonormalized()).inverse()) * pb
	var order_s := _order(src_sk)
	var order_t := _order(tgt_sk)
	var a_s: Array[Quaternion] = []
	a_s.resize(n_s)
	var a_t: Array[Quaternion] = []
	a_t.resize(n_t)
	var prev := {}
	var steps := int(ceil(src.length / STEP))
	for step in steps + 1:
		var time := minf(float(step) * STEP, src.length)
		for i in order_s:
			var q := ls[i]
			if rot_track.has(i):
				q = src.rotation_track_interpolate(rot_track[i], time)
			var p := src_sk.get_bone_parent(i)
			a_s[i] = (a_s[p] if p >= 0 else Quaternion.IDENTITY) * q
		for j in order_t:
			var tp := tgt_sk.get_bone_parent(j)
			var pg := a_t[tp] if tp >= 0 else Quaternion.IDENTITY
			if t_map.has(j):
				var si: int = t_map[j]
				var d := (rs * a_s[si]) * (rs * gs[si]).inverse()          # the turn from the rest pose, in model space
				a_t[j] = (rt.inverse() * (d * (fix[j] * (rt * gt[j])))).normalized()
				var local := (pg.inverse() * a_t[j]).normalized()
				if prev.has(j) and (prev[j] as Quaternion).dot(local) < 0.0:
					local = Quaternion(-local.x, -local.y, -local.z, -local.w)
				prev[j] = local
				out.rotation_track_insert_key(tracks[j], time, local)
			else:
				a_t[j] = pg * lt[j]
		if hips_track >= 0:
			var pos := src.position_track_interpolate(pos_track, time) if pos_track >= 0 else s_rest_o
			var off := pos - s_rest_o
			var off_skel := (a_s[hips_s_parent] if hips_s_parent >= 0 else Quaternion.IDENTITY) * off
			var off_body := xs.basis * off_skel * k
			if flatten:
				off_body.x = 0.0
				off_body.z = 0.0
			var off_t := xt.basis.inverse() * off_body
			var pg2 := a_t[hips_t_parent] if hips_t_parent >= 0 else Quaternion.IDENTITY
			var loc := t_scale.inverse() * (pg2.inverse() * off_t)
			out.position_track_insert_key(hips_track, time, t_rest_o + loc)
	return out
