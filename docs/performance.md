# Performance: numbers, what is slow, what was optimised
Read this before an optimisation task or when frame time changes. Tools are in [commands-and-testing.md](commands-and-testing.md).

## Where the time goes
- Recorded 2026-10-18 (i7-13620H, RTX 4060 Laptop, OpenGL; re-recorded the same day after the invasion work, see its Perf bullet): the game runs on the NVIDIA GPU; render gpu 1-9 ms, so it is CPU bound, dominated by enemy AI / animation and the 120 Hz physics.
- Rendering GPU time is small (render gpu 0.4-3 ms in the table). Enemy AI and animation dominate at battle sites; the 120 Hz physics is the second cost. People are the cost in a crowd: a civilian is 4 skinned meshes, 10-12 surfaces, 7k vertices, 79 bones.
- The `TIME_PHYSICS_PROCESS` monitor reads high and does not add up with frame ms: trust frame ms and the ablations (`perf_ablate.gd`).

## Baseline table (tests/perf_baseline.json, median ms of 3 runs, windowed 1280x720, vsync off, default quality, LETHE_SEED 12345)
The file was recorded on 2026-10-18 17:24 (full mode: war-torn city; plain mode: `LETHE_PLAIN=1`), BEFORE the later enemy optimisations, the halved soldier count (the file shows 58 enemies) and the narrow-street change, so its soldier-heavy spots are now too high; re-run `tests/perf_baseline.ps1` for current numbers and compare only runs from the same session.

| spot | full median | full p95 | full draws | full gpu ms | plain median | plain draws |
|---|---|---|---|---|---|---|
| lobby | 5.89 | 7.76 | 989 | 1.45 | 5.18 | 832 |
| avenue | 3.09 | 4.93 | 474 | 0.60 | 2.71 | 365 |
| site70 | 14.18 | 16.31 | 932 | 3.22 | 9.08 | 872 |
| fire | 13.88 | 16.23 | 512 | 2.89 | 8.35 | 369 |
| roof | 7.92 | 9.65 | 756 | 1.66 | 6.73 | 576 |
| cellar | 8.75 | 13.61 | 485 | 1.95 | 7.96 | 404 |
| sky | 7.34 | 8.84 | 130 | 1.08 | 7.18 | 90 |

## What was optimised
- Static scenery is MultiMesh, chunked in 96 m cells (`WorldWar._mm`); buildings = 1 MultiMesh, each site = 2, cars = 2.
- Site LOD (`Site.lod_for`, see [city-and-world.md](city-and-world.md)), enemy LOD (`Enemy.LOD_DIST` 150 m), civilian LOD and crowd costs (see [civilians.md](civilians.md)), fires only near the player (`Fires`).
- `AiBudget` caps AI rays and A* requests per tick; idle soldiers skip `move_and_slide`, re-pose rarely, sense every 0.05 s (details in the Lander part-one perf bullet below).

## Measurement history (verbatim from the old CLAUDE.md)
- **Perf (windowed 1280x720, vsync off, calm=1, LETHE_SEED 12345, median of 3 runs; `.shots/perf_ab`).** Veil on vs `LETHE_NOVEIL=1`: frame median equal within noise at every spot (avenue 2.27 vs 2.34 ms, lobby 3.79 vs 3.89, roof 4.20 vs 4.29, sky spot looking straight up the avenue 1.36 vs 1.34 ms), +5 draw calls (hull, shimmer, pillars, ...), sky spot render gpu 0.38 vs 0.29 ms (+0.09), render cpu +0.06 ms: the whole sky costs under 0.15 ms. `Veil._update_landers` 0.01 ms per call, 4 calls a second. People are the cost: a civilian is 4 skinned meshes, 10-12 surfaces (draw calls), 7k vertices, 79 bones. Same-session A/B, not calm (lobby / avenue / roof medians of 3 runs, final code): the old crowd (40 civilians, no route dead: `LETHE_CIVILIANS=40 LETHE_NOROUTEDEAD=1`) 4.19 / 2.72 / 6.55 ms vs the invasion content (50 civilians + 10 route bodies + tram + stalls + sky) 5.04 / 3.35 / 6.74 ms = +0.56 ms on average (about +0.45 for the 20 extra people, +0.1 for sky and dressing), i.e. at the 0.5 ms budget; lower `CIVILIAN_COUNT` / `BODY_COUNT` to buy it back. The first version (56 civilians, 12 bodies, the old per-civilian code) cost +1.2 ms at the lobby; `_update_lod`, the cached separation, `REPATH_TIME`, `FAR_DETAIL` and `BODY_VIS` brought the whole crowd down (the old 40-person crowd itself got about 20% cheaper). `tests/perf_baseline.json` was re-recorded after all of this (full, median ms: lobby 5.9, avenue 3.1, site70 14.2, fire 13.9, roof 7.9, cellar 8.8, sky 7.3); the file's earlier numbers (lobby 7.1, avenue 5.2, site70 42.7, fire 39.9, roof 12.8, cellar 15.7) were taken in a much busier machine state, so compare only runs from the same session. (`perf_baseline.ps1` had a precedence bug that wrote an empty file: fixed.)

- **Perf (windowed 1280x720, vsync off, `LETHE_SEED` 12345, median of 3 runs of 600 frames; `perf_probe.gd` spot "balcony" = the west end of the ledge looking at the landed craft, `LETHE_NOLANDER=1` / `LETHE_NOGUARDS=1` / `LETHE_BSTAND=1` for the A/B; `.shots/perf_lander`).** The craft and its effects cost nothing measurable: calm (AI frozen) 2.22 ms with the craft alone vs 2.24 without it (draw calls 388 vs 381: hull, ground patch, two shimmer quads and their shadow passes; render gpu about +0.1 ms; the spark light is invisible until a shell hits the hull, `Lander._process` sleeps). The ten guards are ordinary soldiers: calm they add 0.3 ms (about 110 draw calls), with their AI on and the sniper lying low (crouched: they do not see him past 25 m) 8.5 vs 6.8 ms without craft and guards (+1.7 ms: the one number above 0.5 ms, ten more soldiers in view at 20-40 m), standing in plain view (they all shoot) 9.3 ms. The first measurement of that standing case was +7 ms (14.8 vs 7.7) and led to four changes in `Enemy`, which also made every idle soldier in the city cheaper (the same view without the craft went from 8.5 to 6.8 ms; avenue 3.5 and lobby 5.4 ms unchanged within noise): a calm soldier standing still on the ground skips `move_and_slide` (two calls a tick against the whole city's colliders: `idle_body` in `_physics_process`), is re-posed (IK and bones) only every `IDLE_POSE_STEP` 0.25 s (sitting 0.1 s; `_pose_is_idle`), looks and listens `SENSE_STEP` 0.05 s apart with a per-uid offset (`_sense_due`), and `_face` no longer writes the rig's transform when he already looks there. `tests/perf_baseline.json` is from before these changes (so its soldier-heavy spots are now a little too high).

- **Perf (windowed 1280x720, vsync off, `LETHE_SEED` 12345, median of 3 runs of 600 frames; `perf_probe.gd` spot "court" = the low roof 3 m back from the edge looking down at the four soldiers back to back, `LETHE_NOCOURT=1` the empty courtyard; `.shots/perf_court`).** With the circle 3.27 ms, without 2.91 ms (+0.36 ms for four soldiers in view, 330 vs 327 draw calls; below the 0.5 ms line); avenue 3.10 / 3.21 and lobby 5.02 / 4.58 ms are noise-level order effects. The chase itself costs a 4 Hz tick (six soldiers: one street lookup each, a few distance checks; `_los_to_player` per wounded man) and nothing per frame: `Enemy` got seven plain fields and two multiplications in the chase branch, the blood trail is twelve reused quads, the viewmodel mirror is arithmetic. The halved soldier count (35 enemies instead of about 42 at the start) made the walk lighter. `tests/perf_baseline.json` was not re-recorded (the city layout changed with the narrow streets, so its numbers belong to the old map).

## Open optimisation ideas
- Re-record `tests/perf_baseline.json` after the narrow-street and soldier-count changes.
- Lower `CIVILIAN_COUNT` / `BODY_COUNT` to buy back about 0.5 ms (see the invasion perf bullet).
- Batch or cut the skinned-mesh cost of people (4 meshes, 79 bones each) and of soldiers in view at 20-40 m.
- Add a `Game.mark` wherever a first-use or burst cost could land (hitch detector).
