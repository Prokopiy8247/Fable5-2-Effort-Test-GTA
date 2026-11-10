# WANTED — heat, witnesses, pursuit / search / escape, arrest

Owner: Wanted-system programmer (Wave 2). Files: `gta/code/police/wanted_system.gd` (autoload
`Wanted`), `gta/code/police/wanted_config.gd` (all tuning tables), tests `gta/tests/wnt_core.gd`,
`gta/tests/wnt_ingame.gd`. Contracts: ARCHITECTURE 6.9, ARCHITECTURE_WAVE2 W2.3, spec §18 / §18A.
Everything else under `gta/code/police/` belongs to the POLICE module (dispatcher, units, brains),
which builds on the API below.

## 1. Model in one paragraph

Crimes add **heat**; heat thresholds (`HEAT_THRESHOLDS` 0.25 / 1.6 / 3.6 / 6.5 / 10) give 1–5 stars,
and some crimes guarantee a minimum (`min_level`: murder 2★, cop murder 3★ …). A crime only adds heat
once the police **know** about it. Being wanted runs a state machine **NONE → PURSUIT → SEARCH →
cleared**. PURSUIT lasts while officers keep calling `police_sighting()`. After the level's grace
without sightings the stars flash (SEARCH). A search circle grows around `last_known_position`, and
`escape_progress` fills only while the player stays unseen. Any sighting resumes PURSUIT and resets the
progress. It is not a plain timer.

## 2. When does a crime become known?

`Wanted.report_crime(id, pos, opts)` (gameplay modules: Combat gunfire, Fx explosion, projectile
molotov, VehicleCrime, NpcBase damage, player carjacking, shop robbery …). `EventBus.crime_committed`
is always emitted first. The crime is known **immediately** when:

| source | condition |
|---|---|
| `forced` | `opts.force` |
| `police` | `opts.direct_police_witness`, or `opts.victim` is a living node in group `police`, or a `police_sighting()` happened ≤ `SIGHTING_WINDOW` (1.1 s) before |
| `auto` | crime row `auto_known`: `cop_assault`, `cop_murder` (officer down on the radio), `police_vehicle_theft` (transponder), internal `resisting` |

Otherwise it is stored as **pending** (record with position, time, heat, victim) and becomes known when:

- **police see the player within 1.1 s after it**: `police_sighting()` promotes pending crimes ≤ 1.1 s old;
- **a civilian finishes calling it in**: AI calls `Wanted.report_witnessed(id, pos, witness)`. It matches
  the most recent record of the same id within 40 m. A pending record becomes known. A known record is
  a duplicate and is ignored. An expired record means the call came too late and is ignored. A dead
  witness (`is_dead == true`) is ignored. A call that matches no record at all is accepted as an
  independent observation;
- **a loud crime is heard** (`gunfire` 70 m, `explosion` 120 m, the row's `loud` radius): when
  the player's own `EventBus.noise_emitted` arrived ≤ 0.35 s / 4 m from the crime, its radius is used
  instead, so a suppressed shot (12 m) is heard by almost nobody. If anybody is within earshot (see
  §6), an **indirect report** arrives after 6–10 s (more listeners → faster). It carries a ±12 m
  position error. Nobody within earshot (a deserted place) → nothing happens. Repeated shots within
  35 m merge into one pending report (+25 % heat per extra burst, max ×2).

Pending crimes **expire** after `PENDING_TTL` = 15 s (`Wanted.crime_expired` signal). If AI emits
`EventBus.crime_witnessed(id, pos, witness)` when a civilian *starts* calling, the record lives
`WITNESS_CALL_GRACE` (+12 s) longer, once. Killing / interrupting the caller (AI side) therefore
prevents the report. When a crime becomes known, Wanted emits `EventBus.crime_reported(id, pos)`
and `Wanted.crime_became_known(id, pos, source)`.

**Once wanted, anything the police see counts immediately.** During PURSUIT the sightings are
continuous, so every crime falls inside the sighting window.

## 3. Heat table (`wanted_config.gd`)

| crime | heat | min ★ | violent | loud m | notes |
|---|---|---|---|---|---|
| disturbance | 0.25 | 1 | – | – | damped (spam) |
| property_damage | 0.3 | 1 | – | – | damped |
| collision_major | 0.4 | 1 | – | – | damped |
| resisting | 0.5 | 0 | – | – | internal escalation (heat per level in `resist_heat`) |
| assault | 0.6 | 1 | yes | – | |
| hit_and_run | 0.7 | 1 | yes | – | |
| vehicle_theft | 0.8 | 1 | – | – | occupied vehicles only (W2.1) |
| gunfire | 0.8 | 1 | – | 70 | damped |
| aircraft_violation | 1.0 | 1 | – | – | damped |
| robbery | 1.2 | 1 | – | – | |
| murder | 1.4 | 2 | yes | – | |
| explosion | 1.6 | 2 | yes | 120 | |
| cop_assault | 1.6 | 2 | yes | – | auto-known |
| police_vehicle_theft | 2.0 | 2 | – | – | auto-known |
| police_vehicle_destroyed | 2.2 | 2 | yes | – | |
| cop_murder | 2.6 | 3 | yes | – | auto-known |

Unknown ids use heat 0.3 / min 1★ (never crash on a neighbour's new id). `opts.severity` scales
the heat. **Damped** crimes repeated within 20 s give `1 / (1 + 0.5·n)` of their heat.
**Non-violent cap:** until a violent crime is known in the current episode (`episode_violent`),
heat-driven stars stop at 3★. Heat is clamped just under the next threshold, so a later assault
lifts the level by one star, not by several. `set_level()` (admin) ignores the cap.

## 4. Levels (`LEVELS`, `get_level_config(lvl)`)

| ★ | officers | cruisers | swat_vans | heli | roadblocks | lethal | respawn s | search r / growth / max | escape s | grace s | resist every / heat |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2 | 1 | 0 | 0 | 0 | no* | 20 | 45 / 1.6 / 110 | 20 | 3.0 | 25 s / 0.5 |
| 2 | 4 | 2 | 0 | 0 | 0 | yes | 15 | 60 / 2.0 / 150 | 30 | 3.5 | 30 s / 0.7 |
| 3 | 8 | 4 | 0 | 1 | 1 | yes | 12 | 80 / 2.6 / 190 | 45 | 4.0 | 35 s / 0.9 |
| 4 | 12 | 5 | 1 | 1 | 2 | yes | 10 | 100 / 3.2 / 230 | 60 | 4.5 | 40 s / 1.0 |
| 5 | 16 | 6 | 2 | 1 | 3 | yes | 8 | 120 / 4.0 / 270 | 80 | 5.0 | 45 s / 1.2 |

\* 1★: `is_lethal_force_authorized()` is still true while the player is armed + aiming or attacked
within 10 s. Extra keys: `arrest_first` (1–3★ officers try to cuff first), `roadblock_spikes` (4–5★),
`level`. The returned dictionary is shared: read it, never modify it.

## 5. States

- **PURSUIT**: entered by a sighting, a police-witnessed crime, `set_level()` or `force_pursuit()`.
  `player_visible_to_police` stays true for 0.6 s after each sighting. After the level's
  `lost_contact_grace` without sightings the state becomes SEARCH, with
  `search_center = last_known_position + last_known_velocity × 4 s` (capped at 30 m).
  **Resisting**: every `resist_interval` seconds of PURSUIT adds `resist_heat` ("resisting" crime).
  It is slow (1★ → 2★ after ~50 s, → 3★ after ~140 s) and stops at 3★ without violence.
- **SEARCH**: `search_radius = base + growth × t` (capped). `escape_progress` +=
  `dt / escape_seconds × rate`, where rate is 1.0 outside the search circle, 0.55 inside (hiding nearby
  works, but more slowly) and ×0.6 more while a `police` group node is within 30 m. At 1.0 →
  `clear("escaped")`. A report of a new crime (witness / indirect) while searching moves the search
  to the report and costs 50 % of the progress. A crime the police see resumes PURSUIT.
- A wanted episode **started by a report** (witness, indirect, auto) begins directly in SEARCH at the
  reported position: the police know about the crime but have not seen the player yet.
- While the player is dead (`Game.player.is_dead`) the state machine is frozen. The respawn flow
  clears the level, and pending crimes are dropped on `EventBus.player_died`.

Signals: `EventBus.wanted_level_changed(level, prev)`, `wanted_state_changed(state)`,
`wanted_cleared(reason)` (`escaped`, `busted`, `died`, `cheat`, `load`). Each change is emitted
exactly once, with the level first. All fields are already updated when a listener runs.

## 6. Who hears a loud crime (`count_listeners_near(pos, radius)`)

1. `Game.get_system("peds").count_near(pos, radius) -> int` if the peds system offers it
   (`count_peds_near` is accepted too). Otherwise a scan of group `ped` (living, not the player).
2. Plus living group `police` nodes within the radius.
3. Plus `vehicle` group nodes with an AI `driver` (not player-driven, not destroyed).

This runs only when a loud crime is reported (and at 2 Hz for the "police near" check during
SEARCH), never per frame per object.

## 7. Disguise: vehicle / appearance change while unseen (§18A)

Counts only while wanted, not visible, and unseen for ≥ 1.5 s:
- `note_vehicle_change(vehicle)`: called automatically from `EventBus.player_entered_vehicle`.
  Leaving the vehicle the police identified (`player_exited_vehicle`) counts as a change to "on foot"
  (`null`). Each distinct vehicle counts once, at most 2 credits per unseen episode. Each credit
  removes 25 % of the **remaining** escape time and adds +1.0 s of recognition delay.
- `note_appearance_change()`: called automatically from `EventBus.player_appearance_changed`. One
  credit per episode, −30 % of the remaining time, +1.4 s recognition delay.
- Escape progress from disguises is capped at 0.85, so a disguise is never an instant clear. The next
  sighting resets all credits ("the disguise is blown").
- `get_recognition_delay()`: 0 while visible or not wanted. In SEARCH it is 0.35 s plus the bonuses,
  max 3 s. **Officer brains apply it**: keep the player in continuous sight that long before calling
  `police_sighting()`. Wanted does not delay sightings itself.
- `identified_vehicle` = the vehicle the police last saw the player in (null = on foot).

## 8. Arrest

- `is_player_arrestable()`: wanted, player alive, not swimming, on foot or vehicle speed ≤ 1.5 m/s,
  not aiming a weapon (`is_aiming && is_armed()`), and no attack for 3 s. An attack is
  `EventBus.weapon_fired` by the player, `hit_confirmed`, `npc_injured` by the player, any violent
  crime, or `Wanted.note_player_attack()`.
- `bust()`: emits `EventBus.player_busted`, then `clear("busted")`. It is ignored when not wanted or
  re-entered. The respawn system (W2.5) handles the banner, fine and respawn.

## 9. Audio

The `Audio` autoload's event glue already plays `wanted_up` / `wanted_down` on
`wanted_level_changed` and `wanted_clear` / `arrested` on `wanted_cleared`. Wanted plays the same
stingers itself **only** when `Audio.auto_event_sounds` is false, so a stinger is never doubled.
`Wanted.stingers_enabled = false` silences Wanted's own path.

## 10. Full API (stub names kept; additions marked +)

```gdscript
enum State { NONE, PURSUIT, SEARCH }
const CRIME_HEAT; const HEAT_THRESHOLDS; const ESCAPE_SECONDS; const Config (+ wanted_config.gd)
var level, state, heat, last_known_position, last_known_velocity, seconds_since_seen,
    search_radius, escape_progress, player_visible_to_police, identified_vehicle, enabled
var time_in_state, time_since_last_crime                       # W2.3
var + time_since_player_attack, debug_time_scale, search_center, episode_violent,
    stingers_enabled, last_clear_reason, crimes_known_total
signal + crime_became_known(crime_id, position, source); crime_expired(crime_id, position)
signal + disguise_applied(kind, escape_progress, recognition_delay)
func is_wanted() / + is_in_pursuit() / + is_searching()
func report_crime(crime_id, position, opts := {})              # opts: instigator, victim, direct_police_witness, severity, force
func report_witnessed(crime_id, position, witness)             # W2.3
func police_sighting(observer, position)
func force_pursuit(position)                                   # W2.3 (gives 1★ when not wanted)
func set_level(n, reason := "cheat"); add_stars(n); clear(reason := "cheat")   # set_level(0) == clear
func bust(); is_player_arrestable()                            # W2.3
func + is_lethal_force_authorized(); + note_player_attack()
func note_vehicle_change(vehicle); note_appearance_change(); + get_recognition_delay()
func get_level_config(lvl); + get_crime_def(id); get_escape_time_required(); + get_escape_time_remaining()
func + get_search_center(); + count_listeners_near(pos, r); + get_pending_count(); + get_crime_records()
func + get_debug_info(); + set_enabled(on); + reset_for_respawn(); get_save_data() -> {}; load_save_data(d)
```

`enabled = false` ("never wanted") clears the level and drops pending crimes. While it is false,
crimes, sightings, `set_level` and `force_pursuit` are ignored. `debug_time_scale` multiplies every
Wanted timer (tests, admin "fast escape"). Timers otherwise use game time: they pause with the tree
and follow `Engine.time_scale`. Nothing is saved (`get_save_data()` returns `{}`).

## 11. Integration notes for the POLICE module

- Call `Wanted.police_sighting(officer, player_pos)` on every brain tick in which an officer (or the
  heli) has confirmed LOS on the player, **also when the player is not wanted**: that is how crimes
  committed in front of police become known. During SEARCH, first wait
  `Wanted.get_recognition_delay()` seconds of continuous sight.
- Dispatch from `wanted_level_changed` / `wanted_state_changed` and `get_level_config(level)`. Search
  around `Wanted.search_center` within `Wanted.search_radius`, and send units to
  `EventBus.crime_reported` positions.
- Use `is_player_arrestable()` before an arrest attempt, then `bust()`. Use
  `is_lethal_force_authorized()` for weapons-free. If the player flees an arrest attempt, report
  `Wanted.report_crime("resisting", pos, {"direct_police_witness": true})`.
- Report `police_vehicle_destroyed` from `EventBus.vehicle_destroyed` when the instigator is the
  player (VehicleCrime notes say POLICE owns it).
- Never set `level` / `state` directly. Use `set_level`, `force_pursuit`, `clear`, `bust`.

## 12. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 300 -UserArgs '--test=wnt_core','--no_player','--disable=world,environment,city,props,interactions,vehicles,pickups,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug','--test-timeout=200','--seed=7'
tools\godot.ps1 -Mode headless -Frames 4000 -TimeoutSec 240 -UserArgs '--test=wnt_ingame','--disable=traffic,peds,police,emergency,wildlife,radio,ambience,debug','--test-timeout=150'
tools\godot.ps1 -Mode window   -Frames 600  -TimeoutSec 120 -UserArgs '--test=wnt_ingame','--disable=traffic,peds,police,emergency,wildlife,radio,ambience,debug','--test-timeout=60'
```

`wnt_core` (99 checks, a dummy player) covers: the tables, unwitnessed crimes in a deserted place,
direct-witness stars per the table, the non-violent cap, the witness path (duplicate, dead witness,
late call, call grace, independent observation), the sighting window both ways, loud indirect
reports (merge, 6–10 s, suppressed radius, re-centring during SEARCH), PURSUIT → SEARCH → escape
timing for 1–5★, the inside-circle rate, sighting resumes pursuit, vehicle / appearance credits and
caps, arrestability and bust, set_level / clear / enabled, resisting escalation capped at 3★,
force_pursuit, stinger routing, and every signal fired exactly once.

`wnt_ingame` (real player, world, Combat, vehicles, HUD) covers: real pistol gunfire reported by
Combat with the noise radius used; deserted → expires; three listeners → indirect report → SEARCH; the
HUD shows the state; a sighting → PURSUIT; entering a spawned sedan while unseen → one vehicle credit;
stopped car → arrestable → bust. Screenshots: `qa/screenshots/wnt_search.png`, `wnt_pursuit.png`.
