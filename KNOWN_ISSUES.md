# Known issues / gotchas (learned the hard way — check here before re-debugging)

## A code edit sitting un-loaded for a while, even after committing it
CLAUDE.md's "Install/deploy the mod" section already covers *why* Factorio loads
`mods\ai-companion_0.13.0.zip` instead of this working copy directly — this entry is the concrete
incident that proves it still bites people who know that in the abstract. A `control.lua` fix
(the `fuel_entity`/burner-inserter one below) was written, reviewed, and committed in one Claude
Code session, then verified live as fixed by a second, concurrent session — except the second
session initially got the *same* "No burner nearby" failure as before the fix, because the running
game was still loading the stale zip. Diagnosing that took real effort before landing on "check
whether the zip actually got regenerated." Two things made it worse than the usual case:
- The zip is **locked while Factorio is running** — you can't just re-run `Compress-Archive`, you
  have to fully close the game first (a save reload is not enough; the process has to exit).
- A stale zip fails *silently* — no error, no log line, it just keeps running the old behavior
  forever, indistinguishable from the fix genuinely not working.

Use `deploy.ps1` (repo root) instead of re-deriving the `Compress-Archive` command each time —
run it after any `control.lua`/`commands/*.lua` edit, with Factorio fully closed, then start
Factorio fresh. If a fix "isn't working" after a live verify, re-deploying and fully restarting
should be the first thing you check, before re-reading the diff for a logic bug that isn't there.

## "Total automation" means a real belt line, not repeated hand-feeding
Building a production line (e.g. automation-science-pack -> lab) via `transfer_item`/`craft_start`
calls is a **one-time bootstrap** to gather materials for construction, not the automation itself.
If you find yourself repeatedly moving items between companions/chests/furnaces to keep something
running, that's a sign the belt/inserter chain isn't actually built yet — finish the physical line
(drill -> furnace -> belt -> assembler -> belt -> lab) instead of continuing to hand-carry items.
The lab in particular has no buffer worth relying on by hand — "no manual feeding" was flagged
twice in one session because a chest/inserter hand-off was mistaken for done automation.

## `ai_companion_bridge.fuel_entity` couldn't fuel burner-inserters (fixed)
Its entity filter used to include `"burner-inserter"` as a *type*, but a burner-inserter's real
Factorio `.type` is `"inserter"`, not `"burner-inserter"` — the filter never matched and every
call returned `"No burner nearby"`. Fixed in control.lua by filtering on `type = "inserter"` and
then picking whichever candidate in range actually has a fuel inventory (`get_fuel_inventory() ~=
nil`), rather than assuming `es[1]` is fuelable — this also incidentally fixes electric
furnaces/inserters in range being picked ahead of a valid burner one.
Still watch for `fuel_entity`'s radius-3 search matching the *wrong* nearby burner when multiple
fuelable entities are clustered within 3 tiles of each other — it fuels whichever one comes first
in `find_entities_filtered`'s results, not necessarily the one you targeted.

## Placed entities can silently snap position, breaking your geometry math
`burner-mining-drill` (and possibly other entities) in this modpack do **not** always land where
you tell `place_blueprint`/`create_entity` to put them — a drill requested at (6.5, 121.5) actually
landed at (7, 122). Bounding boxes are also visibly smaller than vanilla (~1.4x1.4 for what should
be bigger footprints), inconsistent between entities that "should" be the same size. **Always
re-query the entity's actual `.position`, `.drop_position`, and `.drop_target` after placing a
mining drill** rather than trusting your planned coordinates — a furnace placed at the
*intended* drop spot may miss the *actual* one by a full tile.

## `assembling-machine-1` placement fails near "ammo-loader-hidden-inserter" test entities
There are scattered `ammo-loader-hidden-inserter` entities in the world (near the lab / current
research area — likely artifacts of testing `ammo-loader-tech-loader-chest`, possibly from the
other concurrent Claude Code session on the same save). They have degenerate zero-size bounding
boxes but still block `can_place_entity` for `assembling-machine-1` specifically — furnaces,
mining drills, belts, inserters, and poles were all unaffected placing over/near the same spots.
If an assembler placement fails with "cannot place" for no visible reason, check
`find_entities_filtered{..., name="ammo-loader-hidden-inserter"}` in the area before assuming
your coordinates are wrong.

## A running (fueled) drill with no valid target litters the ground
Once a mining drill has fuel and a `mining_target` but no `drop_target`, it keeps mining and
dropping items on the ground at its `drop_position` every cycle. This can make a furnace
placement at that exact spot flicker between placeable/not-placeable (the dropped item stack
blocks it). Destroy the `item-entity` at that position immediately before placing, in the same
`run_lua` call as the placement attempt (not a separate one — the drill can drop a new stack in
the gap between calls).

## Lab loses science packs if the research queue is empty
If the lab's research queue is empty when science packs are delivered/sitting in `lab_input`,
the packs get consumed/lost without producing research progress, instead of just waiting there
(which is what you'd expect from vanilla Factorio). **Always confirm something is actually queued
(`fac_research_progress` / `get_research_status`) before delivering a batch of packs to the lab**,
and keep the queue non-empty (queue the next tech ahead of time) once automation is running —
otherwise a belt line can silently manufacture packs into the void.

## Nothing is auto-fueled after `place_blueprint`
Drills, furnaces, and burner-inserters placed via `place_blueprint` start with empty fuel
inventories. Fueling them (generously — e.g. 50-100 coal each) is a required, one-time finishing
step, not ongoing hand-feeding, but it's easy to forget and assume the line is "done" when
everything is actually just sitting idle on `no_fuel`.

## Inserter pickup/drop direction is inverted from its label; `transport-belt` is NOT
Placing an `inserter` via `create_entity` with a given `defines.direction` does **not** make it
pick up from "behind" and drop "in front" the way vanilla Factorio intuition suggests — the two
axes are inverted from each other and from the label. Verified empirically with throwaway
`create_entity` calls and reading back `.pickup_position`/`.drop_position`:
- `direction = north` (0): pickup lands on the **smaller**-y tile, drop on the **larger**-y tile.
  Example: inserter at (-48.5,10.5) facing `north` → pickup=(-48.5,9.5), drop=(-48.5,11.7).
- `direction = south` (8): the reverse — pickup=**larger**-y, drop=**smaller**-y.
- `direction = east` (4): pickup=**larger**-x, drop=**smaller**-x (not the mirror of north/south —
  don't assume the x-axis behaves symmetrically to the y-axis; test both independently).
- `direction = west` (12) follows by elimination: pickup=smaller-x, drop=larger-x.

**`transport-belt` uses the label normally** — `direction = east` moves items toward larger x, no
inversion. This is what makes the bug so easy to miss: a belt-relay link built by reusing the same
`direction` value that correctly fed an inserter will place items into the belt fine, but they sit
dead in the first belt tile forever (visible as lane 2 having items, lane 1 empty, and the tile
after it always empty — check with `belt.get_transport_line(1)`/`(2)` counts) because the belt is
pushing them backward relative to what the inserter chain intends.
**Before wiring any multi-stage inserter+belt line, verify direction semantics empirically first**
(a throwaway inserter placement + position readback takes one `run_lua` call) rather than trusting
`defines.direction` names to mean what they mean in vanilla.
