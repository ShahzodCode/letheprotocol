# Plan: a city layout the player can hide in (proposal, nothing built yet)
Read this when you rework the street layout, soldier placement or the lose-the-hunter rules. Generator facts are in [city-and-world.md](city-and-world.md), AI facts in [enemies-and-ai.md](enemies-and-ai.md).

## The goal (the owner's concept)
The player lures ONE soldier into the back streets, the soldier follows, loses him and is killed. The player can dodge soldiers by running and hiding, and can always leave the pocket he hides in without crossing an open street full of soldiers.

## Why the map does not allow it now (from `City._subdivide`, `_street_width`, `Main` spawning)
1. **Tree-shaped back streets.** Each block is cut by guillotine cuts: every sub-street runs from one side of its (sub-)rectangle to the other and stops at the parent cut or at the block edge. So the alleys of a block form a tree whose only exits are the 12-24 m through streets around it. There are almost no loops, so a pocket has one or two mouths and both open onto a wide street.
2. **Exits are the dangerous places.** Soldiers are weighted to the wide streets (`City.WEIGHTS` avenue 1.6, street 0.5, alley 0.15; groups of 1-3 on avenues), so every mouth of a pocket looks onto an avenue with a patrol. `GROUP_ALERT_COUNT` 3 and a shout pass the alarm on, so two soldiers are enough to pull the rest.
3. **No way to cross.** The through streets (x = -108 / -54 / 0 / 54 / 108, z = ...) are never crossed by an alley, so going from one block pocket to the next means walking along a 12 m street in the open.
4. **No cover on the wide streets** (rubble and cars exist, but nothing that breaks the line of sight over 12 m for 20+ m) and **hunters lose the player too slowly**: `LOSE_TIME` 4 s, `SEEN_MULT` 1.6 (an alerted soldier keeps seeing up to 1.6 x sight range in any direction), a straight run at the player under 14 m.

## Suggestions (what to change, in the order I would do it)
**A. Measure first (no gameplay change).** A tool script `tests/stealth_audit.gd` that for the fixed seed prints, per block pocket: number of exits, widths of the streets the exits open on, shortest alley route to the next pocket that does not touch a street 12 m or wider, and soldiers spawned within 30 m of each exit. Also a flood fill of "narrow-only" connectivity (alley / walk cells, plus 12 m streets crossed in the shortest possible way). This gives numbers for the targets below and a pass/fail check for the selftest.

**B. Make the back streets a network, not a tree.**
 - Cross-links: after the cuts, add 3 m "cut-throughs" (a thin passage between two lots, or a pass-through building: `City.tunnels` already exists) that join two sibling alleys of a block, so every pocket has at least 3 exits, 2 of them onto different sides of the block.
 - Alley continuation across 12 m streets: where an alley of block A meets a 12 m street and an alley of the facing block B is within 8 m, shift one so they line up. The crossing is then a 12 m dash, not a walk along the street.
 - Rule for the tests: from any narrow-street cell there is a narrow-only route (crossings of at most 12 m) to at least 3 other pockets.
 Where: `_subdivide` (bias the second-level cut positions of neighbouring blocks to match), a new `City._link_pockets(rng)` after `_make_lanes`, `CityClimb` for the pass-through / bridge variants. Keep avenues x = 0 and z = 0 and the story places untouched.

**C. Cover on the wide streets.** Break up the open 12 m streets with a staggered chain of cover (parked cars already; add a tram or bus wreck, container pairs, fallen facade) so that along any 40 m of a 12 m street there is a place to be out of the line of a soldier at the far end. `CityWar.obstacles` already places barricades in rings round sites: add a "street cover" pass for the non-site streets. Never block the 7 m keep-clear band of x = 0 / z = 0.

**D. Soldier placement that supports luring.** Move the "weight" from the mouths of the back streets: no soldier spawns or roams (`ROAM_RADIUS` 22 m) within 15 m of an alley mouth unless he is a battle-site soldier; at most one patrol per 12 m street segment between two avenues; patrols of two or more only on the 20-24 m avenues. Add a few lone soldiers (group -1) walking a loop through the back streets: these are the ones the player lures.

**E. Lose-the-hunter tuning (AI, small).** In a 3-6 m street a hunter that loses sight goes to the last known spot and gives up faster (like the chase's alley `sight_scale` 0.55 and `seen_delay` 0.7 s, already in `ChaseFight._tick_chase`); `LOSE_TIME` 4 s becomes about 2.5 s there. A lone hunter does not call the others (`_alert_group` needs 3 aware members already; add: a shout reaches only soldiers within 25 m with a line or a short hearing path).

**F. A hide spot or two per pocket (optional).** Dumpsters, a crouch passage, a door nook: places where a crouched player (`HEAR_CROUCH` 0) in shadow is not found at 3 m unless the soldier walks into him.

## Targets (checked by the audit and by selftest)
- Every pocket: at least 3 exits, at least 2 of them onto narrow streets (6 m or less) or crossings of at most 12 m.
- From the start of the walk home, a narrow-only (or short-crossing) route exists for at least 80% of the distance to the home block.
- At most 1 soldier within 25 m of any pocket exit at spawn time, outside battle sites.
- `City.reachable_fraction()` stays about 1; no new dead ends (the generator comment "every lane section ends at a street" still holds); frame time and the Chapter One route unchanged (home at (15..30, ...), lookout, park and court block are hand-built and stay as they are).

## Baseline numbers (step 1, `tests/stealth_audit.gd`, the default seed, measured 2026-10-22)
Narrow = streets up to 8.5 m wide (alleys 3, footpaths 6, lanes 8); wide = 9.5 m and more. Pocket = connected narrow cells (40 or more).
- Walkable area: 26% narrow, 67% wide, 7% hand-built places (park, home, Institute). 41 pockets in all.
- 10 of 60 blocks have no street inside at all (solid buildings): (-128,-273) (-128,208) (-128,264) (-82,208) (-30,-273) (30,-111) (30,101) (30,157) (128,-273) (128,-230).
- Exits per pocket: 1 exit 5 pockets, 2 exits 12, 3 exits 11, 4 exits 7, 5 exits 4, plus two big networks (23 and 30 exits: the two long east-west chains of narrow streets, the purple and orange lines on the map). So 17 of 41 pockets have 1-2 exits.
- 163 exits in all; 36 (22%) open onto an avenue or plaza of 18 m or more; 19 (12%) have 2+ soldiers within 30 m at spawn.
- Crossings (a dash of at most 13 m over a wide street from one pocket to another): only 13 links in the whole city; just 21 of 41 pockets have any; the pockets join into 28 separate groups, the biggest holds 34% of the narrow cells.
- Walk Institute -> home: shortest 318 m, 181 m of it (57%) in the open, longest open stretch 153 m. The best hide-friendly route (open cells cost 6) is 392 m with 130 m (33%) in the open, longest stretch 78 m.
Reading: the back streets exist but are islands. Few crossings and many one- or two-exit pockets are the main problem (suggestion B); soldiers at exits are a smaller problem than the layout itself (12% of exits), so step 2 matters more than step 3.
Targets for step 2 (to be tuned): at least 3 exits for 90% of pockets, no solid block next to a through street without a cut-through, crossings 13 -> 40 or more, the biggest group of joined pockets over 80% of narrow cells, the walk home in the open at most 35% on the shortest route and at most 20% on the hide-friendly one (longest stretch 40 m).

## Step 2 result (`CityLinks`, cut-throughs and aligned crossings; same seed, same audit)
| | before | after |
|---|---|---|
| passages cut | 0 | 55 (3 merge, 17 cross, 11 pair, 5 exit, 5 split, 14 loop) |
| pockets with 2 or fewer exits | 17 of 41 | 10 of 43 (mostly small corner bits; 33 have 3 or more) |
| blocks with no street at all | 10 of 60 | 4 of 60 (the outer corner blocks, too narrow to cut) |
| crossings (a dash of 13 m or less) | 13 links | 30 links, 34 of 43 pockets have one |
| pocket groups joined by crossings | 28, biggest 34% | 13; the two biggest hold 45% and 41% (the central avenue, 24 m, splits them: no crossing is cut over it on purpose) |
| walk home, shortest route in the open | 57%, longest stretch 153 m | 57%, 153 m (the shortest route runs down the wide avenues, as before) |
| walk home, hide-friendly route in the open | 33%, longest stretch 78 m | 18%, longest stretch 24 m |
| exits with 2+ soldiers near at spawn | 12% | 12% |
Targets met: the hide-friendly walk (at most 20% in the open, longest stretch at most 40 m). Not met: 3 exits for 90% of the pockets (77%, the rest are small corner bits), 40 or more crossing links (30), and one group of pockets holding 80% (86% in two halves split by the central avenue, accepted). Step 3 (soldiers) is still open.

## Plan of work (each step is a separate task, one test group at a time)
1. `tests/stealth_audit.gd` plus the numbers (A). Report the pockets and the worst exits.
2. Cross-links and aligned crossings in the generator (B), with audit targets as selftest checks; screenshots of two pockets.
3. Soldier placement rules (D) and lone back-street patrollers.
4. Street cover pass (C).
5. Lose-the-hunter tuning in narrow streets (E), then a scripted headless "lure" test: one soldier alerted in an alley, the player turns two corners, the soldier gives up or gets knifed; two soldiers on an avenue do NOT pull the pocket's soldiers.
6. Hide spots (F) if the owner still wants them.
Each step: docs updated in the same task, full selftest once at the end.

## Open questions for the owner
- How much of the city must be hide-able: the whole walk from the Institute to the home, or the first blocks only?
- Should the lone soldier you lure be placed on purpose (like `lone_soldier`) or can any patrol do?
