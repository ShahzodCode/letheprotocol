# Credits for third-party models

Filled in 2026-10-23. The four Sketchfab models carry their author, licence and source URL inside the file itself (glTF
`asset.extras`, written by the Sketchfab exporter), so those rows are read from the files, not guessed. Entries marked
**TO LOOK UP** have no author or licence data anywhere in the project or in the files; check the original download page
before the game is shared or published.

## Models in `models/chars/`

| File | Title | Author | Source | Licence |
|---|---|---|---|---|
| `agile.glb` | Futuristic soldier (Free), 18 animations | Pipo Game in My Notebook (https://sketchfab.com/pipogamepc18) | https://sketchfab.com/3d-models/futuristic-soldier-free-6515eed4b6114d159de3e9f452c31571 | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| `marksman.glb` | Futuristic soldier (lowpoly), Mixamo rig, 7 animations | SlagPerch 3D (https://sketchfab.com/slagperch3d) | https://sketchfab.com/3d-models/futuristic-soldier-lowpoly-5ebade1ccbff4adb91ddd3a4d1fcd541 | CC-BY-4.0 |
| `soldier.glb` | low poly soldier (M4) | Kolos Studios (https://sketchfab.com/KolosStudios) | https://sketchfab.com/3d-models/low-poly-soldier-daf5de38902e458aa57ff5ba9460ca02 | CC-BY-4.0 |
| `hedgehog.glb` | military obstacle (steel anti-tank hedgehogs) | _SeF_ (https://sketchfab.com/_SeF_) | https://sketchfab.com/3d-models/military-obstacle-3e039dcb7664462790079542b8206f3f | CC-BY-4.0 |
| `people.fbx` | Modular people pack: 11 outfits on one rig, 24 animations (`All together/FBX/Humans_Master.fbx`) | **TO LOOK UP** | **TO LOOK UP** (it came in `Downloads/All together-20261017T213904Z-1-001.zip`, a Google Drive download, so the zip says nothing about where it was published) | **TO LOOK UP** |

CC-BY-4.0 requires the credit above to stay with the game and a note when the work was changed. We changed them: scaled,
outfits and props removed (`people`), clips renamed and looped, procedural pose layer on top (see
`docs/enemies-and-ai.md`). Say so in the in-game or store credits, for example "adapted for Lethe Protocol".

## Models in `models/`

| File | What it is | Author / source | Licence |
|---|---|---|---|
| `pistol.glb` (+ 8 `pistol_*.webp` textures) | Pistol viewmodel / pickup | **TO LOOK UP** (file says only `glTF-Transform v4.5.1`, an optimiser, not the author) | **TO LOOK UP** |
| `rifle.glb` (+ 3 `rifle_*.webp` textures) | Rifle (material names `Material`, `Material.002`) | **TO LOOK UP** (same: only `glTF-Transform v4.5.1`) | **TO LOOK UP** |

Both arrived in the first project zip (`letheprotocol-claude-magical-clarke-7i3428.zip`, 2026-10-15). The typo
"rougfness" in the pistol texture names is from the original artist's file and may help when you search for the page.

## What I found and could not find

- Searched `Downloads`, `Desktop` and `Documents` for licence / readme / credit files, `.url` shortcuts and other zips:
  none that name a source. The only related archive is the people-pack zip above (two files: the `.fbx` and a `.blend`,
  no readme).
- `people.fbx` header: exported by Blender 2.79 (stable FBX IO), file name `/foobar.fbx`; the Title, Author, Comment
  fields are empty.
- `aerovision-main.zip` in Downloads is unrelated to the game models and was not used.

## Notes

- `marksman.glb` uses the Mixamo skeleton and clips. Mixamo animations are free for use in projects under Adobe's terms
  (not CC): read Adobe's current Mixamo FAQ if the game is sold. The CC-BY credit for the mesh still applies.
- The project has no audio or other image files besides the textures that belong to the models above; the city, buildings
  and sky are built in code.
