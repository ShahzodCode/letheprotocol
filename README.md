# Lethe Protocol

A first-person shooter prototype in Godot 4.3. One man, a pistol and a rifle, an open field, and enemy soldiers who run at you when you get close.

## Run

1. Install [Godot 4.3](https://godotengine.org/download) (standard build, GDScript).
2. Open this folder in the editor (the first open imports the weapon models) and press **F5**.

## Controls

| Key | Action |
| --- | --- |
| W A S D | move |
| Shift | sprint (forward only) |
| Ctrl | crouch; sprint then Ctrl = slide |
| Space | jump (hold for higher) |
| Left mouse | fire |
| Right mouse | aim down sights |
| R | reload (restart on the death screen) |
| 1 / 2 / Q / wheel | pistol / rifle / switch |
| Esc | pause (click to resume) |

## What is in it

- Open noise terrain with hills, trees, rocks and grass.
- Pistol and rifle with spread, bloom, recoil, damage falloff, headshots, magazines, tactical reloads, ADS, tracers and ejected casings.
- Four low-poly soldiers that wander far away, notice you by sight or sound, then chase and strike you in melee. They take knockback and fall when killed.
- Player physics: step-up, slopes, coyote time, jump buffer, variable jump, crouch-slide, fall damage.

See `CLAUDE.md` for the code layout, tuning values and the headless test commands.
