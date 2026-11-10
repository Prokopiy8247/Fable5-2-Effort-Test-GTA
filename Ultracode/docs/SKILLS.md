# SKILLS (spec 46A) - audit and API

Autoload `Skills` (`gta/code/player/skills.gd`). Seven use-based stats 0..100, start at 20
(`START_LEVEL`). XP is awarded where the activity happens; benefits are read with
`get_multiplier(skill, at_0, at_100)` / `get_factor()` / `get_progress()`. Gains diminish near the top
(`gain = amount * lerp(1.0, 0.35, level / 100)`). Levels are saved (provider `skills`), shown on the
status screen (UI `status_screen.gd`), the HUD toasts a level-up (`EventBus.skill_changed`), the admin
menu can max / reset them.

## Audit (Wave 3) - every skill has an XP source AND a real, modest effect

Grep of every module for `Skills.add_xp` / `get_multiplier` / `get_factor` / `get_level` (file:line at
the time of the audit):

| skill | gains XP from | effect (at skill 0 -> 100) |
|---|---|---|
| Stamina | sprinting `player.gd:1004` (0.02/s), fast swimming via `update_stamina`, swimming `player_state_swim.gd:147`, ladder climbing `player_state_ladder.gd:233`, pedalling a bicycle `bike.gd:423` | sprint / fast-swim stamina bar lasts x0.75 -> x1.9 (`player.gd:1002`, 13 s base); bicycle pedal power x1.0 -> x1.15 (`bike.gd:813`) |
| Shooting | hits on living targets `combat.gd:211` (0.05, head 0.12; corpses give none), shooting range results `activity_system.gd:359` | recoil x1.1 -> x0.75 (`weapon_inventory.gd:1067`), reload time x1.08 -> x0.8 (`weapon_inventory.gd:537`) |
| Strength | melee hits `player_state_melee.gd:273/407`, `combat.gd:354` | melee damage x0.9 -> x1.35 (`player_state_melee.gd:399`, `weapon_inventory.gd:621`); **new (this audit): physical resilience - max health 100 -> 115 hp** above the start level (`skills.gd _apply_strength_health`, through the player's public `max_health`, HUD reads it) |
| Stealth | sneaking unseen near NPCs `player_stealth.gd:192`, takedowns `player_state_takedown.gd:200` | sneak / crouch footstep noise radius 1.5 m -> 0.9 m from the start level (`player.gd:956`), detection posture multiplier (`player_stealth.gd:121`) |
| Driving | driving at speed `vehicle_base.gd:1458` (0.012/s at 25 m/s), races / stunt jumps `activity_system.gd:403/446/451` | tyre grip x0.97 -> x1.05 on cars (`car.gd:371`) and motorbikes (`bike.gd:483`) - steadier in difficult driving and slide recovery |
| Flying | helicopter `helicopter.gd:413`, plane `plane.gd:414` (airspeed-scaled) | helicopter: turbulence 0.22 -> 0 and stability assist (`helicopter.gd:579/590/614`); plane: control authority x0.94 -> x1.05, roll response, turbulence 0.12 -> 0 (`plane.gd:672/688/700`) |
| Lung capacity | time under water `player_state_swim.gd:125` (0.05/s) | breath 28 s x0.8 -> x2.2 = 22 s -> 62 s (`player_state_swim.gd:121`); scuba x12 on top |

Typical pace near the start level (diminishing gains included): sprinting 1 level per ~1 min, driving
1 level per ~1.5 min at full speed, ~23 hits per shooting level, ~10 melee hits per strength level - noticeable within a session,
never a requirement (no content is locked behind skills).

## Gaps found and how they were filled

1. **Strength had no resilience effect** -> added the max-health bonus (public API only: `max_health` is a
   contract member of the player and the HUD already draws `health / max_health`). Applied on
   `player_spawned`, `player_respawned`, strength level changes and after loading. Verified in
   `sav_roundtrip` (strength 46 -> 104.9 hp).
2. **Vehicle XP picks the skill in the wrong place** (open item from INTEGRATION_WAVE2): `VehicleBase`
   gives *driving* XP to every class, the helicopter / plane suppress it by zeroing a private timer, and
   the bicycle earns driving AND stamina. Added one entry point in Skills:
   `Skills.award_vehicle_xp(vehicle, seconds, pace)` with the class -> skill map `VEHICLE_SKILL`
   (car / bike / boat -> driving, bicycle -> stamina, heli / plane -> flying) and rates `VEHICLE_XP_RATE`.
   The vehicle files are not mine: **request to the VEHICLE owner** - replace the add_xp line in
   `vehicle_base.gd:_physics_process` with `Skills.award_vehicle_xp(self, 1.0, clampf(absf(_fwd_speed) / 25.0, 0.2, 1.0))`
   and drop `bike.gd:423` plus the aircraft `_xp_t = 0.0` workaround (their own flying XP lines can stay
   or move to the hook with pace = airspeed / cruise). Until then behaviour is unchanged.

## API

```gdscript
const SKILLS, DISPLAY_NAMES, START_LEVEL                       # stub contract
var levels: Dictionary
get_level(s), get_factor(s), get_multiplier(s, at0, at100), add_xp(s, amount), reset(), set_all(v)
get_save_data() / load_save_data(d)                            # NaN / string safe
# additions
const STRENGTH_HEALTH_BONUS := 0.15, VEHICLE_SKILL, VEHICLE_XP_RATE, BENEFITS
var xp_log: Dictionary                                         # points gained this session per skill
set_level(s, v)                                                # admin / tests
get_progress(s) -> float                                       # 0 at START_LEVEL .. 1 at 100
vehicle_skill(vehicle_class) -> String
award_vehicle_xp(vehicle, seconds, pace := 1.0)
get_strength_max_health(base := 100.0) -> float
get_benefit_text(s) -> String                                  # one-line description for the status screen
```
