# Lethe Protocol

A first-person shooter prototype in Godot 4.7 (GDScript, GL Compatibility renderer). One man fights a war against an army. Chapter One: Noah, a teenager, survives the invasion of Verdance, a modern capital built inside a forest. You start in the lobby of the Institute tower, walk about 280 m through the war-torn city with a pistol and a knife to your family's apartment and cellar, then climb to a lookout, fight at a landed ship and flee through the alleys. Nothing has been hand-played yet, so the feel is untuned.

## Run

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, GDScript; developed with 4.7.2).
2. Open this folder in the editor (the first open imports the models) and press **F5**, or run `godot --path .` (add `-- --sandbox` for the sandbox mission where enemies respawn).

## Controls

| Key | Action |
| --- | --- |
| W A S D | move |
| Shift | sprint (forward only) |
| Ctrl | crouch; sprint then Ctrl = slide |
| Space | jump (hold for higher) |
| W at a ladder / pipe | climb (Space = jump off) |
| Left mouse | fire / knife swing |
| Right mouse | aim down sights |
| R | reload (restart from the last checkpoint on the death screen, Shift+R = whole mission) |
| 1 / 2 / 3 | pistol / rifle / melee slot (press again = the slot's other weapon) |
| Tab / mouse wheel | cycle weapons |
| Q | pick up a weapon |
| E | interact, silent takedown from behind with a melee weapon |
| G | hold = grenade arc, release = throw (tap = throw at once) |
| Esc | pause (click to resume) |
| F3 | debug overlay |

## What is in it

- A generated city strip (about 300 x 580 m) with hand-built places: the Institute lobby, the home with a cellar, a park with a balcony building, Noah's alley neighbourhood and courtyard.
- The morning of the invasion: burning trees and buildings, wrecks, barricades, fire escapes, ladders, bridges, an alien sky with landers, civilians running, soldiers patrolling and holding battle sites.
- Objectives with checkpoints, five enemy types with senses, stealth and takedowns, squads that regroup, loot and a loadout (pistol, pulse rifles, long rifle, knife), grenades.
- All sounds are synthesised in code. About 570 headless checks (`tests/selftest.gd`).

## Developer docs

`CLAUDE.md` is the short index for Claude Code; the detailed notes are in `docs/` (one file per topic, start with `docs/commands-and-testing.md` for the headless test commands).
## Which GPU is the game using?

Laptops with an NVIDIA card also have a weak integrated GPU, and Windows often starts a game on the integrated one. Check it in the game: press **F3** (debug overlay, first lines = adapter name and type) or read the `[gpu]` line printed at startup. If the pause menu shows an orange "not on the NVIDIA GPU" warning (shown once per adapter), fix it like this:

1. **Windows Settings > System > Display > Graphics**: *Add desktop app*, pick `Godot.exe` (and the exported game `.exe`), click it, **Options > High performance**, Save.
2. **NVIDIA Control Panel > Manage 3D settings > Program Settings**: add the same exe, set *Preferred graphics processor* = **High-performance NVIDIA processor** (or set it globally in *Global Settings*).
3. Windows power plan **Best performance** (Control Panel > Power Options; on Windows 11 also Settings > System > Power > Power mode > Best performance) and **plug in the charger**. On battery the laptop clocks the CPU and GPU down hard.
4. Restart the game and check F3 again.

The command line option `--gpu-index <n>` does NOT apply here: Godot only supports it on the Forward+ / Mobile renderers (Vulkan / D3D12 devices), and this project uses the GL Compatibility renderer (OpenGL), where the driver / Windows picks the GPU. The renderer driver can be forced with `--rendering-driver opengl3` (the default here).

## Debug overlay (F3) and performance measuring

- **F3** toggles the overlay: adapter, driver, OS, Godot version, FPS, frame ms (average and worst), process / physics ms, render cpu / gpu ms, draw calls, primitives, objects, video memory, enemies and civilians, active lights, particle systems, active physics bodies, last hitch. Hidden it does not run at all.
- Every frame longer than 25 ms is printed as `[hitch] ...` with tags of what happened that frame (first shot, first explosion, enemy spawn, group wake-up, checkpoint, ...) and appended to `user://hitches.log` (`%APPDATA%\Godot\app_userdata\Lethe Protocol\hitches.log`).
- Baseline: `powershell -File tests/perf_baseline.ps1` records seven fixed spots (3 runs with the war-torn city, 3 plain) into `tests/perf_baseline.json` and prints the table.
