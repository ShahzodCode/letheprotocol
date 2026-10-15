class_name WeaponsDB
## The ONLY place weapons are tuned. Angles in degrees, distances in metres, times in seconds.

const WEAPONS := {
	"pistol": {
		"name": "M9 PISTOL",
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
		"name": "M4 RIFLE",
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
		"model": "res://models/rifle.glb",
		"rot_y": 0.0, "length": 0.95, "top_y": 0.07, "center_z": -0.05, "mirror_z": 0.0,
		"ads_pos": Vector3(0.0, -0.062, -0.46),
		"color": Color(0.1, 0.1, 0.11),
	},
}

const ORDER := ["pistol", "rifle"]
