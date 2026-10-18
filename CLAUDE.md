# Lethe Protocol

First-person shooter prototype in Godot 4.7 (GDScript, GL Compatibility). One man fights a war against an army; Chapter One: Noah survives the invasion of Verdance. Current slice: walk from the Institute lobby through a war-torn city strip (about 300 x 580 m) to the family apartment and cellar, then a lookout, a landing-craft fight and a chase to the lander's ramp. Claude is in charge of the project; the user directs it step by step.

## Rules for EVERY task
1. Scenes are built in code (`scenes/main.tscn` is a bare Node3D); no scene editing. Tunables are `const`s at the top of each file / in `Game`.
2. Spawn physics bodies with the position set BEFORE `add_child`.
3. Spawn enemies only through `Main._spawn_enemy_at` (gives the uid checkpoints need).
4. Physics layers (`Game`): 1 world, 2 player, 4 enemy, 8 hitbox, 16 civilian, 32 kerb.
5. Vertex colours are sRGB (`vertex_color_is_srgb = true`); fog is DEPTH fog (Compatibility renderer).
6. Headless tests: wait a frame after teleports (`await frames(n)`); set `Game.force_input = true`.
7. While working run ONE test function; run the full selftest (8-15 min, nothing else heavy running) once at the end.
8. When behaviour changes, update the matching `docs/` file in the same task.

## Commands
- Run: `godot --path .` (add `-- --sandbox` for the sandbox mission)
- One test function: `godot --headless --fixed-fps 120 --path . -- --script res://tests/one.gd <function>`
- Full selftest: `godot --headless --fixed-fps 120 --path . -- --selftest`
- On Windows `Godot.exe` captures no shell output: see docs/commands-and-testing.md.

## If your task touches X, read docs/Y.md first
Do not read docs files that are not related to the task.

| Task touches | Read |
|---|---|
| running, tests, screenshots, perf tools, F3 overlay, hitch log | docs/commands-and-testing.md |
| file layout, conventions, spawning, rendering rules | docs/architecture.md |
| player, controls, weapons, loadout, loot, grenades, gun models | docs/player-and-weapons.md |
| enemies, AI, senses, stealth, squads, character models | docs/enemies-and-ai.md |
| civilians, crowd | docs/civilians.md |
| city generation, map, sites, navigation, buildings, fires, LOD, sky | docs/city-and-world.md |
| missions, checkpoints, Chapter One places, story status | docs/missions-and-story.md |
| scripted story: invasion morning, lander, park fight, chase, LR-9 | docs/story-chapter-one-details.md |
| frame time, optimising, baseline numbers | docs/performance.md |
| ideas, what to build next (PROMPTS.md is the owner's library: do not read) | docs/roadmap.md |

## Status
Playable prototype: generated war-torn city, Chapter One places, mission system with checkpoints, 5 enemy types, loot and loadout, grenades, about 570 headless checks passing. Everything was verified headless and with screenshots only; nothing has been hand-played, so feel (recoil, speeds, enemy aggression) is untested. Docs were reorganised on 2026-10-19; the old CLAUDE.md is in docs_backup/ (do not read).
