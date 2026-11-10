# Shops and economy (ECONOMY module, programmer A)

Shop framework, Bay Arms weapon shop + workbench, Tide Threads clothing store + wardrobe, Harbor Cuts
barber, Corner 24 general store, shop staff and the robbery hook. Contracts: ARCHITECTURE_WAVE2 W2.4
(city markers) and W2.6 (shops). Spec sections 17A, 23, 23A, 24, 25.

| file | role |
|---|---|
| `gta/code/world/shop_system.gd` | world system `shops` (use points, staff, robbery, open / closed, save providers) |
| `gta/code/world/shops/shop_catalog.gd` | static pricing + purchase logic (every purchase goes through it) |
| `gta/code/world/shops/shop_wardrobe.gd` | owned clothing set (SaveSystem provider `wardrobe`) |
| `gta/code/world/shops/shop_preview.gd` | 3D preview: SubViewport <= 512 px with its own world |
| `gta/code/world/shops/shop_stat_bars.gd`, `shop_swatches.gd` | before / after stat bars, colour chips |
| `gta/code/world/shops/shop_screen_base.gd`, `shop_appearance_base.gd` | shared screen layout / behaviour |
| `gta/code/ui/screens/weapon_shop_screen.gd` | `shop_weapons` (shop + workbench) |
| `gta/code/ui/screens/clothing_shop_screen.gd` | `shop_clothing` |
| `gta/code/ui/screens/wardrobe_screen.gd` | `wardrobe` |
| `gta/code/ui/screens/barber_screen.gd` | `shop_barber` |
| `gta/code/ui/screens/general_shop_screen.gd` | `shop_general` |
| `gta/resources/registries/shops_registry.gd` | Registry kinds `shops` and `shop_items` (all prices of this module) |
| `gta/tests/shp_api.gd`, `gta/tests/shp_shots.gd` | tests |

No `class_name` is declared by this module (the `Shop*` prefix is shared with economy programmer B, so
a name clash would break both): the files `preload` each other. The screens extend `UiScreen` and use
the UI widget kit as `docs/UI.md` prescribes; `shop_system.gd` itself only uses `Interactable` / core.

---------------------------------------------------------------------------------------------------

## 1. Shops

| id | landmark | screen | use points (markers) | staff look | robbery cash |
|---|---|---|---|---|---|
| `bay_arms` "Bay Arms" | `gun_shop` | `shop_weapons` | `Use_Counter` (shop), `Use_Workbench` (workbench page) | vest, cargo, cap, beard | 700-1500 |
| `tide_threads` "Tide Threads" | `clothing_store` | `shop_clothing` | `Use_Counter` (store), `Use_Wardrobe` = changing booth (wardrobe) | shirt, skirt, round glasses | 400-900 |
| `harbor_cuts` "Harbor Cuts" | `barber` | `shop_barber` | `Use_Chair` | staff outfit, slick hair, moustache | 150-450 |
| `corner_24` "Corner 24" | `general_store` | `shop_general` | `Use_Counter` | staff outfit, curls | 250-650 |
| (wardrobe point) | `safehouse` | `wardrobe` | `Use_Wardrobe` (dropped again if another module already has an Interactable there) | - | - |

Positions: `city.get_landmark_marker(landmark, marker)` (W2.4). When the city system has no such landmark the
use points fall back to `Game.get_location(landmark)` (spread 2.2 m apart) and the clerk stands 2 m inside the
lot; for 30 s after boot positions are re-resolved every second, so a city that finishes late still moves
everything onto the real counters. Interactables: radius 1.9 m, 0.9 m above the marker, `use_priority` 2,
meta `shop_id`.

Registry kind `shops` (W2.6 keys + framework keys): `id, landmark, kind, display_name, screen, stock` and
`tagline, map_icon, uses [{marker, prompt, screen, args}], staff, staff_marker, staff_look, robbable,
robbery_cash [min, max], closed_hours, items`. **A def without `uses` is not managed** (only listed by
`get_shop_locations()`), so another module (mod garage, gas station) can register a shop and build its own use
points; a def *with* `uses` gets interactables, staff and robbery for free (e.g. a gas-station kiosk:
`{"id": "fuel_mart", "landmark": "gas_station", "kind": "gas", "screen": "shop_general", "uses":
[{"marker": "Use_Kiosk", "prompt": "Shop at Halcyon Fuel", "screen": "shop_general"}], "stock": [...item ids]}`).

## 2. `shops` system API (`Game.get_system("shops")`)

```gdscript
signal shop_robbed(shop_id: String, cash: int)
signal shop_closed(shop_id: String, reason: String)       # "robbed", "staff_killed", admin reasons
signal shop_reopened(shop_id: String)
var wardrobe: RefCounted                 # owned clothing (provider "wardrobe")
var unlocked_attachments: Dictionary     # weapon id -> {attachment id: true} (provider "shops")
var debug_force_threat: Dictionary       # shop id -> true: the robbery check passes (tests / admin)
var robbery_count: int
func get_shop_ids() -> Array
func get_shop_locations() -> Array[Dictionary]   # {id, display_name, kind, landmark, position, icon, open, screen, source}
func get_shop_state(shop_id) -> Dictionary       # open, closed_until, threat, robbery_progress, source, has_staff, staff_position, uses
func get_interactables(shop_id := "") -> Array
func is_open(shop_id) -> bool;  close_shop(shop_id, hours := 6.0, reason := "closed");  reopen_shop(shop_id)
func open_shop(shop_id, use_index := 0) -> Control      # as if the use point was used (admin / phone)
func get_staff(shop_id) -> Node3D;  register_staff(shop_id, node) -> bool;  unregister_staff(shop_id)
func get_robbery_progress(shop_id) -> float              # 0..1 while holding up the clerk
func is_attachment_unlocked(weapon_id, att_id) -> bool;  unlock_attachment(weapon_id, att_id)
func set_enabled(on);  reset_for_respawn();  get_save_data() / load_save_data(d)
```

## 3. Staff and robbery

- Clerk = `Game.spawn_npc("shop_staff", Staff marker, {"yaw", "persistent": true, "appearance": staff_look,
  "role": "shop_staff", "shop_id"})` (W2.2), only when the `peds` system exists and only while the player is
  within 90 m (freed beyond 130 m: idle shops cost nothing). Group `shop_staff`, meta `shop_id`. Using the
  counter calls `face_position(player)` on the clerk when it has that method.
- **Robbery (W2.6):** the player, on foot, aims a firearm (`inventory.get_current_spec().is_firearm()`,
  `player.is_aiming`) at the clerk's chest (`get_target_position()`) from <= 10 m (aim ray within
  max(0.85 m, 20 % of the distance)) -> the clerk `surrender()`s (+ brain `on_event("threatened")`), threat
  builds for 3 s (decays at 0.75/s while not aiming) -> a cash pickup (`pickups.spawn_pickup("cash", "",
  amount, counter)`, or `Game.add_money` without a pickups system) lands at the counter,
  `Wanted.report_crime("robbery", clerk position, {"instigator": player, "victim": clerk})`, the clerk
  `cower()`s, the shop closes for `closed_hours` (6 in-game hours) with "(closed)" prompts.
- Killing the clerk (`EventBus.npc_died`) closes the shop the same way (the murder report is NpcBase's job).
- Closed / reopened state persists (provider `shops`, hours left). On reopening a fresh clerk is spawned.
- Checks run at 10 Hz and only for shops within 14 m of the player; staff tiers / reopening at 2 Hz.

## 4. Economy and prices

`Game.START_MONEY` = 5000. All purchases go through `charge()` in `shop_catalog.gd` = `Game.spend(price)` +
`EventBus.item_purchased(kind, id, price)` with kinds `weapon, ammo, attachment, item, clothing, haircut`
(id of an attachment purchase: `"<weapon>:<attachment>"`). `Game.flags["free_shopping"]` (admin "unlock all",
or `--free_shopping` on the command line) makes every price 0 ("FREE" in the lists, "FREE SHOPPING" in the
header). Nothing is charged when the purchase would have no effect (owned weapon, ammo full, armour full, full
health, parachute / scuba already owned, same look at the barber).

| what | price | source |
|---|---|---|
| melee 180-300, pistol 550, heavy pistol 1450, SMG 1900, shotguns 1600 / 3300, rifles 2900-5200, sniper 7500, launchers 7200 / 9500, grenade 300, fire bottle 200 | | `WeaponSpec.price` |
| ammo pack (pistol 24 rds 60, SMG 60 rds 90, shells 12 for 80, rifle 60 rds 120, sniper 10 for 150, rockets 2 for 600 ...) | | `WeaponSpec.ammo_price / ammo_pack` |
| suppressor 450, optic 600, light 200, grip 380, extended magazine 420, finishes 150-900 | | `AttachmentSpec.price` |
| Patrol Vest +50 armour 500, Plate Carrier +100 armour 1000 (Bay Arms) | | `shop_items` |
| snacks 6-16 (+12..35 hp), drinks 3-8 (+5..10 hp, stamina refill), bandage 45 (+40), first aid kit 120 (full), Light Vest +40 armour 350, Glide Pack parachute 300, Scuba Kit 650 (Corner 24) | | `shop_items` |
| clothing 20-450 (hats / glasses "none" free) | | Registry `clothing` (appearance_registry.gd) |
| haircut 15-45, beard 10-22, colour-only change 12 | | Registry `hair` + `COLOUR_FEE` (shop_catalog.gd) |

With the starting 5000 the player can buy an SMG or a shotgun plus armour and ammo, or a rifle and a vest;
the sniper / launchers need cash pickups, NPC drops or a robbery. Money is never a gate for testing
(`free_shopping`, admin money).

## 5. Screens

All screens: header with the shop name and the live balance, Q / E (or click) categories, W / S (arrows,
mouse hover) to move, Enter / Space / click to buy, Esc backs out (sub-page first), feedback line in
green / red, `ui_buy` on purchases and `ui_error` on refusals (the widgets add `ui_click`, `ui_hover`,
`ui_tab`). They lock gameplay input and hide the HUD but do not pause the world; getting hurt closes them.
Test helpers on every screen: `get_items()`, `select_tab(i)`, `select_index(i)`, `activate_index(i)`,
`find_index(key, value)`, `get_selected_item()`.

- **`shop_weapons`** (`{"shop_id", "page": "shop" | "workbench", "tab"}`): tabs MELEE, PISTOLS, SMG,
  SHOTGUNS, RIFLES, SNIPER, HEAVY, THROWN (wheel slots), ARMOUR, WORKBENCH. Unowned weapons are bought; owned
  weapons turn into ammo rows (Enter = one pack, R = fill the reserve, also buttons "Fill ammo" / "Equip").
  Right side: 3D preview of the weapon GLB (with your fitted attachments), stat bars (damage, fire rate,
  range, accuracy, control, magazine). **Workbench**: your firearms -> their compatible parts in the order
  suppressor, optic, light, grip, extended magazine, finishes (+ "Factory Finish"); highlighting a part shows
  it on the model and the stat bars before -> after (green gain / red loss, plus stealth and zoom rows);
  Enter fits (paid once - removed parts stay unlocked and refit for free) or removes a fitted part.
- **`shop_clothing`**: tabs TOPS, BOTTOMS, SHOES, HATS, GLASSES (items that fit the player's body and exist
  on the model), colour swatches (A / D, arrows or click), live preview on a dressed clone. Enter buys and
  wears (owned items are worn for free in any colour).
- **`wardrobe`**: the same for owned items only, always free. Opened at the changing booth and the
  safehouse.
- **`shop_barber`**: HAIR (styles that exist on the model + hair colours) and BEARD (M body); head close-up
  preview; price = style price on a new cut + 12 for a new colour.
- **`shop_general`**: FOOD, DRINKS, HEALTH, GEAR; preview of the pickup GLBs (first aid kit, armour vest,
  parachute pack, scuba tank), a large code-drawn glyph for food and drinks (they have no Blender model);
  bars for health / armour / stamina / parachute / scuba before -> after.

Appearance changes go through `apply_player_appearance()` in `shop_catalog.gd`: `Player.set_appearance()` (=
`CharacterVisual.apply_appearance()` + `EventBus.player_appearance_changed`) and
`Wanted.note_appearance_change()` when the wanted system has it.

## 6. Save data

| provider | data |
|---|---|
| `wardrobe` | `{"owned": [clothing ids], "seeded": bool, "appearance": {...}}` (the appearance is re-applied only if the player provider did not restore it) |
| `shops` | `{"closed": {shop_id: {"hours_left", "reason"}}, "unlocked": {weapon_id: [attachment ids]}, "robberies": n}` |

The player's own provider stores the appearance, health, armour, parachute and scuba flags; the weapons
provider stores weapons, ammo and fitted attachments.

## 7. Tests

```powershell
# API + behaviour, headless (92 checks with peds enabled; the real-clerk part is skipped without peds)
tools\godot.ps1 -Mode headless -Frames 4000 -TimeoutSec 260 -UserArgs '--test=shp_api','--test-timeout=220','--disable=traffic,police,emergency,wildlife,vehicles,props,radio,ambience,garage,transit,taxi,activities,respawn,debug'
#   '--shp_real_only' runs only the real-clerk hold-up
# screenshots, windowed (~15 s); '--shp_only=counter,weapons,armour,workbench,clothing,wardrobe,barber,general'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 120 -UserArgs '--test=shp_shots','--disable=traffic,peds,police,emergency,wildlife,vehicles,props,radio,ambience,garage,transit,taxi,activities,respawn,debug'
```

`shp_api` (real player / inventory / world / city / pickups / peds / UI): shop defs, interactables in the tree
at valid positions near their landmarks (all four resolve from city markers), `get_shop_locations()`,
Interactable -> screen -> input lock, weapon / ammo / fill / armour / attachment purchases (money, inventory,
spec stats, free refit, finishes), weapon shop + workbench screens through their rows (3D preview has the
model), clothing / wardrobe / barber purchases (appearance, `player_appearance_changed`, owned set),
SaveSystem round trip (appearance, wardrobe, workbench unlocks), healing items, parachute / scuba, real key
events (E = next tab, ui_down, Enter buys, Esc closes), free_shopping, the robbery flow with a dummy clerk
through the real aim path (Input "aim" + camera turned onto the clerk: surrender -> 3 s -> cash -> report ->
closed -> no screen -> reopen) and, with peds, the real `shop_staff` clerk spawning at the `Staff` marker and
being held up the same way (clerk states seen: surrender / hands_up / cower).
`shp_shots` (windowed): `qa/screenshots/shp_counter.png` (Bay Arms counter in the world with the prompt),
`shp_weapons`, `shp_armour`, `shp_workbench`, `shp_clothing`, `shp_wardrobe`, `shp_barber`, `shp_general`,
`shp_general_food`.

## 8. Known limits

- Mouse input (hover / click on rows, tabs, swatches, buttons, drag on the preview) comes from the UI widget
  kit and was not driven by a test; keyboard input was (general store).
- The clerk's behaviour between "surrender" and "cower" is the AI module's (`shop_staff` brain); without a
  peds system there is no clerk and therefore no robbery (shops still work).
- Food and drinks have no 3D model (icons in the preview); every other preview is a Blender GLB.
- The preview clone shows the relaxed static pose (no idle animation).
