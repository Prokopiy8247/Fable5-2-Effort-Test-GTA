# QA backlog (collected by the lead for Wave 4)

Items reported by Wave 2 reviewers / implementers that no Wave 3 owner covers. Wave 4 fixers own
the files named here. Tick items off (with the verifying test) when fixed.

## Errors at boot / runtime
- [ ] `gta/code/world/shops/garage_vehicle_access.gd:84` (`_make_terminal_model`, from `setup_site`):
  RID errors on every boot with the garage system ("Initializing already initialized RID",
  "Attempting to initialize the wrong RID", "Parameter m / mem / material is null").
- [ ] `gta/code/vehicles/vehicle_manager.gd:139` (`spawn_vehicle`): "unimplemented base type
  encountered in renderer scene cull" during boot.
- [ ] ~40 places use `bool(x.get("is_dead"))`; any node without the property raises
  "Nonexistent bool constructor". Replace with `x.get("is_dead") == true` where `x` may be any node.

## Gameplay
- [ ] WORLD data: the `gang` spawn point at about (62, 3, −60) is on the carriageway beside
  downtown_plaza (lanes at x = 58.6 / 61.4). Move gang spawn points onto sidewalks / plazas / yards.
- [ ] AI `ai_brain_gang.gd` (`on_event` noise / damaged): gangs are provoked by any gunshot within
  28 m and by any damage incl. police cars bumping them → three-way shoot-outs at the plaza. Only
  provoke on harm / threats by the player (or by someone attacking the gang directly).
- [ ] VEHICLE `vehicle_crime.gd` `collision()`: a police PIT / box-in charges the player with
  `collision_major` when his speed was ≥ 0.8 of the cruiser's. Skip the report when the other
  vehicle is police (or AI-at-fault).
- [ ] Props ladder `Ladder_0` at about (104.6, 1.4, 253.7): no walkable top (solid collider fills the
  platform).
- [ ] Debug: `set_density` writes Settings AND calls `system.set_density()` with the same value
  (double application). Add "repair street furniture" → `props.respawn_all()`.
- [ ] Drive-by in-cabin camera unsupported for van, box_truck, sports; ambulance / firetruck /
  swat_van unchecked (fall back to the orbit view that hides the gun).
- [ ] Police officers never commandeer civilian cars (spec stretch; optional).

## Tests that are flaky / thin
- [ ] `pol_ambient` adopt_patrol failed once in three runs (cause unknown, diagnostics added).
- [ ] Chases and roadblocks only tested with traffic disabled.
