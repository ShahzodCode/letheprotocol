# Architecture, conventions, rendering rules
Read this before adding a script, a node, a physics body or a material. The autoload is `Game`; the main scene is a bare Node3D with scripts/main.gd.

## Layout (scripts/ and friends)
```
project.godot            autoload Game, GL Compatibility, 120 physics ticks, layer names
scenes/main.tscn         a bare Node3D with scripts/main.gd; EVERYTHING else is built in code
scripts/
  game_state.gd          autoload `Game`: tunables (consts), shared state (kills, dead, enemies), signals, input map (registered in code), `has_focus()`
  main.gd                builds city + player (at `City.START_POS`) + HUD + enemies (battle-site groups + roaming groups by street class), runs the Mission (`mission.update`), saves / restores checkpoints, drives the sites' level of detail by distance, respawns killed enemies after 25 s ONLY if `mission.respawn_enemies`; test hooks (--selftest / --shots)
  mission.gd             Mission: ordered objectives (reach / kill_group / interact / script), hooks, HUD text, marker spot; `Mission.complete(id)`, `Mission.sandbox()`, `Mission.story()`
  missions/chapter_one.gd ChapterOne.build(): LEAVE THE INSTITUTE, GET HOME, GO TO THE CELLAR, then (The Lander, part one) CLIMB TO THE ROOF, LOOK OUT OVER THE CITY, TAKE OUT THE MARKSMAN, TAKE HIS RIFLE, THIN OUT THE GUARDS, then (part two) ESCAPE INTO THE LANES, TAKE THE STRAGGLERS' GRENADES, CLEAR THE COURTYARD, FINISH THEM, REACH THE OPEN RAMP (no respawn); `on_start` hooks say short subtitle lines (`Game.radio_line`) and start the landing (`Main.begin_lookout`)
  grenade.gd             Grenade (frozen RigidBody3D moved by `sim_step`, the same step `predict()` uses for the aiming arc) + `detonate()` (blast damage with falloff / wall check, shake, flash, fireball, smoke, debris, scorch, `Game.gunshot`)
  char_model.gd          CharModel: a skinned character from models/chars (people pack, marksman, agile, M4 soldier): fitting, outfits, logical animation names, hand attachment of weapons, soldier pose helpers (IK)
  civilian.gd            Civilian: people running from the soldiers (PANIC / HIDE / FOLLOW / DEAD), distance LOD, thins out over 5 minutes
  squads.gd              Squads: back-to-back regrouping of alerted groups that lost 40%, radio subtitles
  checkpoint.gd          Checkpoint: snapshot taken when an objective starts (player, full loadout, counters, living / dead enemies, loot) and `restore()`
  city_places.gd         CityPlaces: the hand-built Institute, home + cellar, park + balcony building, street trees; `cut(rect, holes)` helper
  city_story.gd          CityStory: the invasion-morning dressing of the walk home: tram on its side, overturned stalls (`dress()` inside `City.generate`), and on demand (needs the nav grid) `first_lane()`, `lone_soldier_spot()`, `body_spots(rng)`
  city.gd                City: static city data from a seed (avenues, BSP-cut blocks, buildings with tiers, border ring, battle sites, cars, decor, props, ramps, trees, lights), A* navigation: a 1 m main grid plus finer LAYERS (apartment, cellar, balcony) joined by `City.path`; `is_free`, `random_spawn`, `layer_of`
  site.gd                Site: a battle site (mud, craters, cracks, rubble as 2 MultiMeshes; fires with particles + light) with `set_lod()` by distance
  scenery.gd             Scn: collector for the small scenery of the war-torn city (static arrays: MultiMesh parts per mesh type, road decals, box / cylinder colliders, kerbs, nav blocks, fires); `Scn.Occ` = spatial hash of taken rectangles
  city_war.gd            CityWar: city trees in planters (15% burning, 10% fallen, 10% stumps), wrecked / abandoned / rammed cars (`finish_car` = basis, origin, footprint), war obstacles (jersey barriers, sandbags, furniture barricades, tank traps, fallen lamps / poles with sparks, rubble, shipping containers), standing street lamps; keeps the 7 m band along x = 0 / z = 0 clear (`KEEP_CLEAR`)
  city_roads.gd          CityRoads: road paint (edge / centre / lane lines, stop lines, zebra crossings), manholes, drains, cracks, potholes, scorch, skids, glass, debris as flat decals, denser near battle sites
  city_buildings.gd      CityBuildings: building designs (apartments with balconies, shops with awnings, old houses with pitched roofs, offices, roof gardens, rooftop units), the damage value per building (20% heavy / 40% light / rest intact; border ring too) and the damage geometry (missing corner, collapsed top, hole through the facade, rubble, burning buildings)
  city_climb.gd          CityClimb: pass-through buildings (3 m corridors), reachable roofs (fire escapes / concrete stairs / ladders, parapets, solid roof units), bridges between roofs (open footbridge / glass walkway, some broken), crouch passages (pipe, fallen ladder, slab, low gap), container ladders; `plan()` before `CityBuildings.dress()`, `build()` after
  building_shader.gd     BuildingShader.CODE: the window shader (styles: punched, shop front, old house, ribbon, curtain wall, office piers, plain) + damage (black windows, soot, burnt floors, fire glow) from the instance custom data
  veil.gd                Veil (node under World): the invasion sky (shader sky with the Veil, the wound and silent flashes), 8 landers (MultiMesh hulls + heat-shimmer quads), smoke pillars of the power stations; `Veil.lander_pos(i, t)` is the analytic lander path
  ship_models.gd         ShipModels: the landing craft as ONE cached two-surface mesh per detail level (blunt grey hull, engine pods, lowered rear ramp, doorway alcove behind a lit loading threshold) + its collision box set + the scorched / crushed ground patch; `ShipModels.Lander` is the node (mesh LOD, colliders with meta "hull", threshold Area3D, heat-shimmer quads, spark, 9 s descent)
  park_fight.gd          ParkFight (node `Main.park_fight`): the ten guards at the lander's ramp: CALM -> SEARCH (first shot: scatter, confused circle = a persistent Squads record) -> CHARGE (muzzle flash seen / 20 s / a guard found him)
  chase_fight.gd         ChaseFight (node `Main.chase`): "The Lander" part two: six chasers (two stragglers) through the alleys of Noah's neighbourhood, the four who gather BACK TO BACK in the courtyard, the arm wound and the last grenade (see "The Lander, part two")
  world_war.gd           WorldWar: turns Scn into MultiMeshes (chunked: `_mm(..., cell = 96.0)` splits a MultiMesh into 96 m cells, `range_end` > 0 hides a chunk beyond that distance; a city-wide one would be drawn and shadow-rendered in full from everywhere) (decals, scenery boxes / cylinders / spheres / cones, burning canopies with a fire shader, glow signs, glass, smoke columns) and colliders (kerbs on their own physics layer)
  world_cars.gd          WorldCars: draws City.cars (boxes) with the damage variants: burnt shell, flipped, crushed, doors open
  fires.gd               Fires: flames + smoke + a few lights (trees 4, buildings 3, cars 2, corridors 2) only near the player; far away burning things are canopies, glowing windows and smoke columns
  world.gd               turns City into geometry: ground (cut open above the cellar stairs, 3 collider layers), ALL buildings + props in one MultiMesh with the window shader (per-box colour + style, damage as custom data) + one collision box each, ramp colliders, pavements with kerbs, indoor omni lights, backdrop towers, sky (about 11:30 on a March morning, sun 53 degrees) / hazy grey-brown fog; `World.height_at` is 0; `set_marker_target()` moves the objective marker; the rest is WorldWar / WorldCars
  player.gd              CharacterBody3D: look, movement physics, crouch/slide, ladders (CLIMB state), fall damage (`Player.fall_damage`), footsteps, camera (FOV, bob, recoil), health, `context_hint()` for the HUD
  weapons.gd             Weapons node under the camera: hitscan fire, spread/bloom, recoil, falloff, magazines, reload, ADS, switching, viewmodels (.glb), tracers, casings, muzzle flash
  weapons_db.gd          WeaponsDB.WEAPONS: the ONLY place weapons are tuned (pistol, rifle, carbine, hmg, railgun, sniper, knife, blade); each has a `slot` (pistol / rifle / melee)
  gun_models.gd          GunModels: procedural weapon models (boxes + cylinders merged into one cached two-surface mesh per weapon and detail level), used for viewmodels, soldiers' hands, ground pickups and the HUD side-profile icons
  pickup.gd              Pickup: weapon or loose magazine lying on the ground (dropped by dead enemies or by the player)
  enemy.gd               Enemy (5 kinds in KINDS: soldier, blade, rifleman, gunner, marksman): procedural low-poly model, hit boxes, AI state machine (melee + ranged SHOOT), knockback, death
  hud.gd                 flat dark HUD (health blocks, ammo box, spread crosshair, hit marker, vignette, death + pause screens)
  settings.gd            Settings: fullscreen / vsync / shadows / MSAA / render scale / view distance / mouse sensitivity, saved in user://settings.cfg, applied by `Settings.apply` (the pause menu in hud.gd edits them; the project starts fullscreen)
  perf_overlay.gd        PerfOverlay: F3 debug overlay (adapter, FPS, frame / process / physics / render ms, draw calls, primitives, video memory, enemies, lights, particles, last hitch); hidden = not processing; owned by HUD (`hud.debug_overlay`)
  sfx.gd                 all sounds synthesised in code (no audio files), cached AudioStreamWAV
  ai_budget.gd           AiBudget: per-tick budget of AI physics rays (12) and A* requests (1), called by Main each tick (added since the old layout list)
  prof.gd                Prof: section timer for the perf scripts, off in the game (added since the old layout list)
models/                  pistol.glb (the M9 viewmodel, in use) + its .webp textures (the old rifle.glb was deleted: unused)
models/chars/           people.fbx (11 outfits, 24 clips), marksman.glb, agile.glb, soldier.glb (rigged soldiers), hedgehog.glb (anti-tank barricade); see CREDITS.md
tests/selftest.gd        about 570 scripted checks in 15 sections (physics, shooting, AI, city, story); tests/screenshots.gd renders views for visual review; the other tool scripts are listed in docs/commands-and-testing.md
tests/perf_*.gd|ps1|json perf probe, ablate, baseline, merge, battle, renderers (see docs/commands-and-testing.md)
The Story/             the chapter documents (.docx), see docs/missions-and-story.md
x                      a stray 113 KB PNG at the project root, not referenced anywhere (found while reorganising; delete it if you do not need it)
```

## Conventions
- No scene editing needed: scenes are built in code, scripts use `class_name` (World, Player, Weapons, Enemy, HUD, WeaponsDB, Sfx). Tunables are `const`s at the top of each file / in `Game`.
- Physics layers (bit values in `Game`): 1 world, 2 player, 4 enemy bodies, 8 hitboxes, 16 civilians, 32 kerbs (raised pavement edges: ONLY the player collides with them, so soldiers and civilians walk flat). Bullets are rays against world + hitboxes only; enemy hit boxes are `Area3D`s (`part` meta = head / body / legs, `enemy` meta) that never overlap each other.
- Spawn a physics body with its position set BEFORE `add_child` (`Enemy.setup()` then `add_child`). Setting `global_position` after `add_child` reaches the physics server a frame late: bodies sat at the origin for the first physics step and threw the player 30+ m.
- Vertex colours / instance colours are authored in sRGB: materials set `vertex_color_is_srgb = true`. Use DEPTH fog (`FOG_MODE_DEPTH`), the default exponential fog washed every colour out in the Compatibility renderer.
- Never rely on `global_position` writes for gameplay teleports without waiting a frame (tests wait `await frames(n)`).
- Headless has no mouse capture: `Game.has_focus()` is `force_input or mouse captured`; tests set `Game.force_input = true`.
- Characters are skinned models (see "Characters" in [enemies-and-ai.md](enemies-and-ai.md)); weapons, pick-ups and the world props are still simple low-poly procedural boxes.
- Spawn rule for enemies: spawn through `Main._spawn_enemy_at(pos, kind, weapon)` (gives them a `uid`, needed by checkpoints; hooks that spawn enemies must use it). See [enemies-and-ai.md](enemies-and-ai.md).
- Rendering rules in short: sRGB vertex colours + `vertex_color_is_srgb = true`, DEPTH fog, MultiMesh for static scenery in 96 m chunks (see the layout entry of `world_war.gd`), one draw call per mesh type through `Scn`; details of the world in [city-and-world.md](city-and-world.md).
