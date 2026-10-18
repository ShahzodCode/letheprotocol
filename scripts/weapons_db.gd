class_name WeaponsDB
## The ONLY place weapons are tuned. Angles in degrees, distances in metres, times in seconds.

const WEAPONS := {
	"pistol": {
		"name": "M9 PISTOL", "short": "M9", "slot": "pistol",
		"damage": 28.0,
		"head_mult": 2.5,
		"rpm": 420.0,
		"auto": false,
		"mag": 15,
		"spare_mags": 4,
		"reload_time": 1.6,
		"pellets": 1,
		"spread_hip": 1.4,        # cone half-angle when standing still, hip fire
		"spread_ads": 0.25,
		"spread_move": 1.6,       # added while moving (scaled by speed)
		"spread_per_shot": 0.5,   # bloom added per shot, decays quickly
		"spread_max_bloom": 2.5,
		"recoil_pitch": 1.7,      # kick up per shot
		"recoil_yaw": 0.35,       # random sideways kick
		"recoil_recover": 9.0,    # how fast the kick settles (1/s)
		"falloff_start": 25.0,    # full damage up to here
		"falloff_end": 90.0,
		"falloff_min": 0.45,      # damage fraction at falloff_end
		"impulse": 3.0,           # knockback in m/s at full damage
		"ads_fov": 60.0,
		"ads_time": 0.14,
		"ads_move": 0.8,
		"loudness": 55.0,         # how far enemies hear a shot
		"model": "res://models/pistol.glb",
		"rot_y": 90.0, "length": 0.3, "top_y": 0.05, "center_z": 0.0, "mirror_z": 3.7678,
		"ads_pos": Vector3(0.0, -0.057, -0.4),
		"color": Color(0.12, 0.12, 0.14),
	},
	"rifle": {
		"name": "PR-1 PULSE RIFLE", "short": "PR-1", "slot": "rifle",
		"damage": 24.0,
		"head_mult": 2.2,
		"rpm": 720.0,
		"auto": true,
		"mag": 30,
		"spare_mags": 4,
		"reload_time": 2.5,
		"pellets": 1,
		"spread_hip": 2.6,
		"spread_ads": 0.35,
		"spread_move": 2.2,
		"spread_per_shot": 0.35,
		"spread_max_bloom": 3.0,
		"recoil_pitch": 0.95,
		"recoil_yaw": 0.4,
		"recoil_recover": 7.0,
		"falloff_start": 45.0,
		"falloff_end": 180.0,
		"falloff_min": 0.5,
		"impulse": 3.5,
		"ads_fov": 48.0,
		"ads_time": 0.18,
		"ads_move": 0.65,
		"loudness": 90.0,
		"model": "",           # the invaders' pulse rifle: procedural (GunModels._rifle), white bolt, whip-crack
		"rot_y": 0.0, "length": 0.95, "top_y": 0.07, "center_z": -0.2, "mirror_z": 0.0,
		"ads_pos": Vector3(0.0, -0.062, -0.46), "glow": Color(0.92, 0.96, 1.0), "sound": "whip", "sound_pitch": 1.0, "casing": false, "tracer_w": 0.012,
		"color": Color(0.1, 0.1, 0.11),
	},
	# ---- weapons carried by enemies (blocky viewmodels, energy weapons: no brass, own sounds) ----
	"carbine": {   # rifleman
		"name": "PC-24 PULSE CARBINE", "short": "PC-24", "slot": "rifle",
		"damage": 20.0, "head_mult": 2.0, "rpm": 600.0, "auto": true, "mag": 24, "spare_mags": 4, "reload_time": 2.0, "pellets": 1,
		"spread_hip": 2.4, "spread_ads": 0.35, "spread_move": 2.0, "spread_per_shot": 0.3, "spread_max_bloom": 2.6,
		"recoil_pitch": 0.7, "recoil_yaw": 0.35, "recoil_recover": 8.0,
		"falloff_start": 40.0, "falloff_end": 150.0, "falloff_min": 0.5, "impulse": 3.0,
		"ads_fov": 52.0, "ads_time": 0.15, "ads_move": 0.75, "loudness": 70.0,
		"model": "", "rot_y": 0.0, "length": 0.75, "top_y": 0.07, "center_z": -0.14, "mirror_z": 0.0,
		"ads_pos": Vector3(0.0, -0.06, -0.4), "color": Color(0.16, 0.18, 0.22), "glow": Color(0.25, 0.9, 1.0),
		"sound": "pulse", "sound_pitch": 1.0, "casing": false,
	},
	"hmg": {   # gunner
		"name": "HG-60 HEAVY PULSE GUN", "short": "HG-60", "slot": "rifle",
		"damage": 17.0, "head_mult": 1.8, "rpm": 800.0, "auto": true, "mag": 60, "spare_mags": 3, "reload_time": 4.0, "pellets": 1,
		"spread_hip": 3.4, "spread_ads": 0.8, "spread_move": 3.0, "spread_per_shot": 0.3, "spread_max_bloom": 4.0,
		"recoil_pitch": 0.75, "recoil_yaw": 0.6, "recoil_recover": 6.0,
		"falloff_start": 40.0, "falloff_end": 140.0, "falloff_min": 0.45, "impulse": 3.0,
		"ads_fov": 55.0, "ads_time": 0.3, "ads_move": 0.45, "loudness": 100.0,
		"model": "", "rot_y": 0.0, "length": 0.95, "top_y": 0.08, "center_z": -0.2, "mirror_z": 0.0,
		"ads_pos": Vector3(0.0, -0.066, -0.42), "color": Color(0.2, 0.2, 0.21), "glow": Color(1.0, 0.55, 0.12),
		"sound": "pulse", "sound_pitch": 0.7, "casing": false,
	},
	"railgun": {   # marksman
		"name": "RG-5 RAIL RIFLE", "short": "RG-5", "slot": "rifle",
		"damage": 85.0, "head_mult": 2.5, "rpm": 70.0, "auto": false, "mag": 5, "spare_mags": 3, "reload_time": 3.2, "pellets": 1,
		"spread_hip": 3.5, "spread_ads": 0.05, "spread_move": 3.0, "spread_per_shot": 1.5, "spread_max_bloom": 3.0,
		"recoil_pitch": 3.5, "recoil_yaw": 0.3, "recoil_recover": 5.0,
		"falloff_start": 120.0, "falloff_end": 400.0, "falloff_min": 0.8, "impulse": 6.0,
		"ads_fov": 22.0, "ads_time": 0.3, "ads_move": 0.5, "loudness": 110.0,
		"model": "", "rot_y": 0.0, "length": 1.15, "top_y": 0.08, "center_z": -0.26, "mirror_z": 0.0,
		"ads_pos": Vector3(0.0, -0.068, -0.4), "color": Color(0.62, 0.64, 0.68), "glow": Color(1.0, 0.15, 0.12),
		"sound": "snipe", "sound_pitch": 1.0, "casing": false,
	},
	"sniper": {   # the marksman on the balcony (Chapter One, "The Lander"): heavy bolt-action long rifle, slow shells that drop
		"name": "LR-9 LONG RIFLE", "short": "LR-9", "slot": "rifle",
		"damage": 120.0, "head_mult": 2.5, "rpm": 40.0, "auto": false, "mag": 5, "spare_mags": 3, "reload_time": 3.6, "pellets": 1,
		"spread_hip": 4.5, "spread_ads": 0.02, "spread_move": 4.0, "spread_per_shot": 1.0, "spread_max_bloom": 2.0,
		"recoil_pitch": 4.2, "recoil_yaw": 0.4, "recoil_recover": 4.0,
		"falloff_start": 150.0, "falloff_end": 400.0, "falloff_min": 0.8, "impulse": 7.0,
		"ads_fov": 12.0, "ads_time": 0.38, "ads_move": 0.35, "loudness": 170.0,
		"model": "", "rot_y": 0.0, "length": 1.3, "top_y": 0.08, "center_z": -0.3, "mirror_z": 0.0,
		"ads_pos": Vector3(0.0, -0.07, -0.4), "color": Color(0.18, 0.17, 0.16), "glow": Color(1.0, 0.72, 0.4),
		"sound": "longshot", "sound_pitch": 1.0, "casing": true, "tracer_w": 0.02,
		"bolt": true,             # a bolt is worked after every shot (sound; the rpm is the cycle time)
		"heavy": true,            # too heavy to run with: switching away with a hunter close by drops it (see Weapons.HEAVY_DROP_RANGE)
		"scope_sway": 0.5,        # degrees of drift of the scoped view (see Weapons._update_sway); Shift / Ctrl holds the breath
		"breath_time": 3.0,       # seconds the breath can be held before the view jumps
		"bullet_speed": 200.0,    # m/s: the shell falls 0.5 * g * (d / v)^2 on its way (about 0.2 m at 40 m, 0.8 m at 80 m)
	},
	# ---- melee: LMB swings, no ammo ----
	"knife": {
		"name": "ARC KNIFE", "short": "KNIFE", "slot": "melee", "melee": true,
		"damage": 45.0, "head_mult": 1.0, "rpm": 130.0, "auto": false, "reach": 2.0, "reload_time": 1.0, "mag": 0, "spare_mags": 0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "spread_per_shot": 0.0, "spread_max_bloom": 0.0,
		"recoil_pitch": 0.0, "recoil_yaw": 0.0, "recoil_recover": 8.0,
		"falloff_start": 1.0, "falloff_end": 2.0, "falloff_min": 1.0, "impulse": 2.0,
		"ads_fov": 75.0, "ads_time": 0.2, "ads_move": 1.0, "loudness": 0.0,
		"model": "", "rot_y": 0.0, "length": 0.4, "top_y": 0.05, "center_z": 0.0, "mirror_z": 0.0,
		"ads_pos": Vector3(0.2, -0.2, -0.5), "color": Color(0.1, 0.1, 0.12), "glow": Color(0.6, 0.9, 1.0),
		"sound": "swing", "sound_pitch": 1.4, "casing": false,
	},
	"blade": {   # blade fighter
		"name": "PLASMA BLADE", "short": "BLADE", "slot": "melee", "melee": true,
		"damage": 85.0, "head_mult": 1.0, "rpm": 85.0, "auto": false, "reach": 2.6, "reload_time": 1.0, "mag": 0, "spare_mags": 0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "spread_per_shot": 0.0, "spread_max_bloom": 0.0,
		"recoil_pitch": 0.0, "recoil_yaw": 0.0, "recoil_recover": 8.0,
		"falloff_start": 1.0, "falloff_end": 2.0, "falloff_min": 1.0, "impulse": 4.0,
		"ads_fov": 75.0, "ads_time": 0.2, "ads_move": 1.0, "loudness": 0.0,
		"model": "", "rot_y": 0.0, "length": 1.0, "top_y": 0.05, "center_z": 0.0, "mirror_z": 0.0,
		"ads_pos": Vector3(0.2, -0.2, -0.5), "color": Color(0.1, 0.1, 0.12), "glow": Color(0.78, 0.35, 1.0),
		"sound": "swing", "sound_pitch": 1.0, "casing": false,
	},
}

const ORDER := ["pistol", "rifle", "carbine", "hmg", "railgun", "sniper", "knife", "blade"]
const SLOT_NAMES := {"pistol": "PISTOL", "rifle": "RIFLE", "melee": "MELEE"}
