# Lethe Protocol

First-person shooter prototype in Godot 4.7 (GDScript, GL Compatibility). One man fights a war against an army; Chapter One: Noah survives the invasion of Verdance. Current slice: walk from the Institute lobby through a war-torn city strip (about 300 x 580 m) to the family apartment and cellar, then a lookout, a landing-craft fight and a chase to the lander's ramp. Claude is in charge of the project; the user directs it step by step.

## Rules for EVERY task
1. Scenes are built in code (`scenes/main.tscn` is a bare Node3D); no scene editing. Tunables are `const`s at the top of each file / in `Game`.
2. Spawn physics bodies with the position set BEFORE `add_child`.
3. Spawn enemies only through `Main._spawn_enemy_at` (gives the uid checkpoints need).
4. Physics layers (`Game`): 1 world, 2 player, 4 enemy, 8 hitbox, 16 civilian, 32 kerb.
5. Vertex colours are sRGB (`vertex_color_is_srgb = true`); fog is DEPTH fog (Compatibility renderer).
6. Checking is a few seconds at the START and at the END of a task, nothing else: run `powershell -ExecutionPolicy Bypass -File tests/smoke.ps1` (headless start, about 10 s, fails on any script error). Do NOT run the full selftest, single test functions, perf baselines or screenshots unless the user asks for them by name. The user plays the game to judge the result.
7. Do NOT update the `docs/` files after a change, and do not write test or results reports; just build what was asked. (Read the docs in the table below when they help you understand the code.)

## Commands
- Run: `godot --path .` (add `-- --sandbox` for the sandbox mission)
- Smoke check (start and end of a task): `powershell -ExecutionPolicy Bypass -File tests/smoke.ps1`
- Only on request: full selftest `godot --headless --fixed-fps 120 --path . -- --selftest`, one function `-- --script res://tests/one.gd <function>`, tool scripts in tests/ (see docs/commands-and-testing.md).
- On Windows `Godot.exe` captures no shell output: tests/smoke.ps1 handles it.

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
