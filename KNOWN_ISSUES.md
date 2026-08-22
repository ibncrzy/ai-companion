# Known issues / gotchas (learned the hard way — check here before re-debugging)

## "Total automation" means a real belt line, not repeated hand-feeding
Building a production line (e.g. automation-science-pack -> lab) via `transfer_item`/`craft_start`
calls is a **one-time bootstrap** to gather materials for construction, not the automation itself.
If you find yourself repeatedly moving items between companions/chests/furnaces to keep something
running, that's a sign the belt/inserter chain isn't actually built yet — finish the physical line
(drill -> furnace -> belt -> assembler -> belt -> lab) instead of continuing to hand-carry items.
The lab in particular has no buffer worth relying on by hand — "no manual feeding" was flagged
twice in one session because a chest/inserter hand-off was mistaken for done automation.

## `ai_companion_bridge.fuel_entity` can't fuel burner-inserters
Its entity filter is `type = {"furnace", "boiler", "burner-inserter", "car", "locomotive",
"mining-drill"}` (control.lua), but a burner-inserter's real Factorio `.type` is `"inserter"`,
not `"burner-inserter"` — so the filter never matches and every call returns `"No burner nearby"`.
Workaround: fuel burner-inserters directly via `run_lua`, locating the companion's character
entity (`find_entities_filtered{type="character", position=..., radius=2}` near the companion's
`companion_status` position) and inserting into `entity.get_fuel_inventory()` by hand.
Also watch for `fuel_entity`'s radius-3 search matching the *wrong* nearby burner when a drill,
furnace, and inserter are clustered within 3 tiles of each other — it silently fuels whichever
one `find_entities_filtered` returns first, not necessarily the one you targeted.

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
