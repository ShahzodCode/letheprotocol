# Lethe Protocol

First-person shooter prototype in **Godot 4.3 (GDScript, GL Compatibility renderer)**. Lore: one man fights a war against an army. Current slice: the player spawns on an empty open field with a modern pistol and rifle; a few soldiers wander far away and run at him when he gets close or shoots. Successor of the Bot Shooter prototype (Three.js, repo `game`); movement, weapon and AI rules were carried over from it. Claude is in charge of the project; the user directs it step by step.

## Commands
- Run the game: open the folder in the Godot 4.3 editor and press F5, or `godot --path .`
- Headless checks (fast, ~5 s, exit code 1 on failure): `godot --headless --fixed-fps 120 --path . -- --selftest`
- Screenshots under a virtual display (needs `xvfb-run`): `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 -- --shots /tmp/shots`
- First run after adding assets: `godot --headless --path . --import`
- Godot 4.3 is not installed by default in the cloud container: download `Godot_v4.3-stable_linux.x86_64.zip` from github.com/godotengine/godot-builds releases.

## Layout
```
project.godot            autoload Game, GL Compatibility, 120 physics ticks, layer names
scenes/main.tscn         a bare Node3D with scripts/main.gd; EVERYTHING else is built in code
scripts/
  game_state.gd          autoload `Game`: tunables (consts), shared state (kills, dead, enemies), signals, input map (registered in code), `has_focus()`
  main.gd                builds world + player + HUD + enemies, respawns killed enemies after 25 s; test hooks (--selftest / --shots)
  world.gd               noise terrain (flat-shaded, own trimesh collision), trees / rocks / grass tufts (MultiMesh), sky, sun, depth fog, boundary walls; `World.height_at(x, z)`
  player.gd              CharacterBody3D: look, movement physics, crouch/slide, fall damage, footsteps, camera (FOV, bob, recoil), health
  weapons.gd             Weapons node under the camera: hitscan fire, spread/bloom, recoil, falloff, magazines, reload, ADS, switching, viewmodels (.glb), tracers, casings, muzzle flash
  weapons_db.gd          WeaponsDB.WEAPONS: the ONLY place weapons are tuned (pistol, rifle)
  enemy.gd               Enemy soldier: procedural low-poly model, hit boxes, AI state machine, melee, knockback, death
  hud.gd                 flat dark HUD (health blocks, ammo box, spread crosshair, hit marker, vignette, death + pause screens)
  sfx.gd                 all sounds synthesised in code (no audio files), cached AudioStreamWAV
models/                  pistol.glb, rifle.glb (copied from the `game` repo)
tests/selftest.gd        47 scripted checks (physics, shooting, AI); tests/screenshots.gd renders views for visual review
```

## Conventions
- No scene editing needed: scenes are built in code, scripts use `class_name` (World, Player, Weapons, Enemy, HUD, WeaponsDB, Sfx). Tunables are `const`s at the top of each file / in `Game`.
- Physics layers (bit values in `Game`): 1 world, 2 player, 4 enemy bodies, 8 hitboxes. Bullets are rays against world + hitboxes only; enemy hit boxes are `Area3D`s (`part` meta = head / body / legs, `enemy` meta) that never overlap each other.
- Spawn a physics body with its position set BEFORE `add_child` (`Enemy.setup()` then `add_child`). Setting `global_position` after `add_child` reaches the physics server a frame late: bodies sat at the origin for the first physics step and threw the player 30+ m.
- Terrain triangles must be wound clockwise (Godot front faces); `world.gd::_tri` emits (a, c, b). The trimesh shape uses `backface_collision = true`. Build collision from your own triangle list, not `mesh.create_trimesh_shape()` (needs the render server, breaks headless).
- Vertex colours / instance colours are authored in sRGB: materials set `vertex_color_is_srgb = true`. Use DEPTH fog (`FOG_MODE_DEPTH`), the default exponential fog washed every colour out in the Compatibility renderer.
- Never rely on `global_position` writes for gameplay teleports without waiting a frame (tests wait `await frames(n)`).
- Headless has no mouse capture: `Game.has_focus()` is `force_input or mouse captured`; tests set `Game.force_input = true`.
- Models: viewmodels are fitted at load from the .glb bounds (`Weapons._build_model`: `rot_y`, `length`, `top_y`, `center_z`; `mirror_z` adds a mirrored twin for half-models like the pistol). To add a gun: put the .glb in `models/`, run `--import`, add a `WEAPONS` entry (+ `ads_pos`, calibrate it with the screenshot script holding `Input.action_press("aim")`), add the id to `ORDER`, add a sound in `sfx.gd`.
- Enemies / models should stay simple and low-poly (the user wants unsophisticated models): boxes + a few low-res spheres.

## Game design notes
- Controls: WASD, Space jump (hold = higher), Shift sprint (forward only, cancels ADS), Ctrl crouch (Shift-sprint then Ctrl = slide), LMB fire, RMB aim, R reload, 1 / 2 / Q / wheel switch weapon, Esc pause (click to resume), R on the death screen restarts.
- Player (`player.gd`, values in `Game`): 100 HP, no regeneration. Walk 5, sprint 8, crouch 2.4 m/s; jump 7 m/s (variable height), gravity 24 (x1.25 falling), coyote 0.12 s, jump buffer 0.12 s, step-up over ledges <= 0.55 m (camera eases), uphill slower / downhill faster, slides on slopes > 50 degrees, fall damage above 15 m/s impact (5 per m/s, max 70), crouch-slide 0.85 s, footsteps, landing dip. Solid against enemies.
- Weapons (`weapons_db.gd`): PISTOL (semi-auto 420 rpm, 28 dmg, head x2.5, 15 round mag, 4 spare, 1.6 s reload) and RIFLE (auto 720 rpm, 24 dmg, head x2.2, 30 rounds, 4 spare, 2.5 s reload). Hitscan; direction = camera forward + random cone: hip / ADS spread + movement + airborne + bloom per shot (crouching x0.75); damage falls off with distance (full to `falloff_start`, `falloff_min` at `falloff_end`); legs do 75%. Recoil climbs the view itself (pitch + random yaw) and settles back (`recoil_recover`), ADS x0.7. Ammo is magazine based: a tactical reload keeps the partly used magazine in the pouch and leaves a round chambered (+1); empty trigger pull clicks and starts the reload. Shots hit trees / rocks / terrain (impact sparks), hits push enemies (`impulse`), tracers, ejected brass (RigidBody3D, max 40 alive), muzzle flash light + glow quad, sway / bob / reload / switch animations. Gunshots (`Game.gunshot`) alert wanderers within `loudness * 0.45` m.
- Enemy soldier (`enemy.gd`, tunables at the top): 100 HP, WANDER (1.5 m/s, roams 22 m around its spawn) -> ALERT (0.45 s, shouts) -> CHASE (6.4 m/s, separation from friends, sidesteps when stuck, slope speed) -> ATTACK (0.5 s wind-up, rifle-butt strike 16 dmg, 0.9 s cooldown) -> DEAD (falls backwards / forwards, knockback slide, shrinks away after 12 s). Notices the player in a 130 degree cone up to 34 m (60% if crouching) with a line-of-sight ray, or by hearing: walking 11 m, sprinting 20 m, crouching 5 m, standing still 6 m. Being shot wakes it and everyone within 22 m. Gives up after 6 s farther than 75 m. 4 enemies start 75-115 m from the player; each killed one is replaced 25 s later at the edge.
- World: 600 x 600 m noise terrain, flat 22 m around the start, hills up to ~20 m, ~260 trees (clustered), ~90 rocks, 5000 grass tufts, invisible boundary walls, depth fog. Everything static is merged / MultiMesh.
- HUD: top-left kills, bottom-left health blocks, bottom-right ammo box (loaded / reserve / mags / reload bar), crosshair gaps open with the real spread (a red dot while aiming), hit marker (white hit, yellow headshot, red kill), red vignette when hurt, death screen with accuracy, pause screen.

## Status
Playable prototype: open field, pistol + rifle, 4 wandering soldiers that chase and melee, 47 headless checks passing. Everything was verified headless and with screenshots only; **nothing has been hand-played**, so feel (recoil, speeds, enemy aggression, sensitivity 0.0022 rad/px) is untested.

## Ideas / next steps (the user decides priority)
1. Playtest and tune: enemy speed / sight / damage, recoil, spread, movement.
2. Enemy ranged attacks (they currently only melee), cover use, groups with a leader.
3. More weapons (shotgun, sniper, grenades) and pickups / ammo drops; health items.
4. Real open world: chunked terrain streaming, towns, vehicles, objectives for the "one man against an army" story.
5. Proper character models and animations (the Bot Shooter repo has downloaded zombie / knight .glb files, not used here because the enemies are soldiers).
6. Settings menu (sensitivity, volume, FOV), saved progress.

## Testing
`tests/selftest.gd` runs in the real scene tree under `--headless --fixed-fps 120` and prints PASS / FAIL for: spawn (player grounded, 4 enemies far, wandering), jump height + variable jump, fall damage, walking speed, step-up (0.4 m ledge) and a 2 m wall, shot damage numbers (28 body, 70 head, falloff at 80 m), accuracy (ADS vs moving hip), recoil kick + recovery, tactical reload, weapon switching, rifle damage + climbing recoil, enemy notice -> alert -> chase -> melee damage, kill + corpse, gunshot alert (near vs far), line of sight blocked by a wall, player death. The headless renderer is a dummy: it prints harmless `mesh_get_surface_count` errors; use the screenshot script for anything visual.
