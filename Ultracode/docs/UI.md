# HALCYON BAY - UI module

Owner: UI programmer. Code in `gta/code/ui/`, thin scene wrapper `gta/scenes/ui/hud.tscn`,
generated theme `gta/resources/themes/game_theme.tres`, tests `gta/tests/ui_api.gd`,
`gta/tests/ui_shots.gd`, `gta/tests/ui3_api.gd`, `gta/tests/ui3_shots.gd`. Everything is built in
code; there are no font, icon or image files. Wave 3 additions (phone, photo mode, radio wheel,
activity results, situational HUD widgets, neighbour contracts): [section 12](#12-wave-3-additions).

- [1. Visual identity](#1-visual-identity)
- [2. The `UI` autoload](#2-the-ui-autoload)
- [3. HUD layout and data sources](#3-hud-layout-and-data-sources)
- [4. Minimap and map data](#4-minimap-and-map-data)
- [5. Screens](#5-screens)
- [6. How to add a screen](#6-how-to-add-a-screen)
- [7. Widget kit](#7-widget-kit)
- [8. Icons](#8-icons)
- [9. Tests](#9-tests)
- [10. File list](#10-file-list)
- [11. Known issues / notes](#11-known-issues--notes)
- [12. Wave 3 additions](#12-wave-3-additions)

---------------------------------------------------------------------------------------------------

## 1. Visual identity

Original look (not modelled on any existing game HUD): **deep navy translucent "glass" panels**
with rounded corners and a thin light edge, **coral / teal / sun-yellow** accents, bold condensed
caps for headings, generous spacing. Colours come from the game palette (`tools/blender/gta_bl.py`).

| constant (`UiStyle`) | use |
|---|---|
| `NAVY_DEEP`, `NAVY`, `GLASS`, `GLASS_LIGHT`, `GLASS_SOLID` | panels, ink on light fills |
| `CORAL`, `CORAL_HOT` | primary accent, health, selection bar, waypoint / route, danger |
| `TEAL`, `TEAL_LIGHT` | secondary accent, armor, sliders, section labels |
| `SUN` | money, wanted stars, focus ring, stamina |
| `CREAM`, `TEXT`, `MUTED`, `DIM` | text levels |
| `GOOD`, `BAD`, `POLICE_RED`, `POLICE_BLUE` | status colours |

**Canvas:** the project stretches `canvas_items` from a logical **1920x1080** canvas with aspect
`expand`, so every size in the UI module is in *logical* pixels (x 2/3 at 1280x720, x 2 at 4K) and
everything is laid out with anchors / containers. Type scale: `FS_TINY 17`, `FS_SMALL 20`,
`FS_BODY 24`, `FS_LARGE 29`, `FS_H3 33`, `FS_H2 42`, `FS_H1 62`, `FS_HUGE 132`; screen-safe margin
`UiStyle.MARGIN = 40`.

**Fonts:** `UiStyle.font(kind)` returns cached `FontVariation`s of the engine font - `"body"`,
`"bold"`, `"head"` (heavy + condensed + letter spacing, used for caps) and `"num"` (bold, tabular
digits for counters).

**Theme:** `UiThemeBuilder.build()` creates the one Theme in code (single source of truth); the UI
autoload puts it on its root Control so every HUD piece and screen inherits it. The same theme is
exported to `game_theme.tres` by
`tools\godot.ps1 -Mode script -Script res://gta/code/ui/tools/ui_gen_theme.gd` (re-run it after
changing the builder). Type variations (`theme_type_variation`):

- Label: `TitleLabel`, `HeaderLabel`, `SectionLabel`, `ValueLabel`, `MutedLabel`, `SmallLabel`,
  `MoneyLabel`, `AccentLabel`
- Button: `AccentButton`, `MenuEntryButton`, `GhostButton`
- PanelContainer: `GlassPanel`, `SolidPanel`, `LightPanel`, `AccentPanel`, `FlatPanel`

Sliders, check boxes, line edits, scroll bars, tabs, item lists, trees, popups and tooltips are
themed as well, so stock Godot controls look on-style inside a screen.

---------------------------------------------------------------------------------------------------

## 2. The `UI` autoload

`gta/code/ui/ui_manager.gd` (CanvasLayer 10, `process_mode = ALWAYS`).

```
UI (CanvasLayer)
 +- Nav (UiNav)            waypoint + GPS route
 +- Stats (UiStats)        free-roam statistics (saved, provider "ui_stats")
 +- Root (Control, Theme)
     +- Hud (HudRoot)      pausable
     +- Screens            open screens, stack order = child order
     +- Overlay            Toasts, Banner, Subtitle
     +- Fade, Veil (loading), Debug (F3)
```

### Contract API (unchanged signatures)

| call | behaviour |
|---|---|
| `UI.notify(text, kind = "info", duration = 3.5)` | toast, top-right. kinds: `info good warn bad money skill radio`. Identical messages merge ("x2"). Also emits `EventBus.notification`; notifications emitted on that signal by others are shown too. |
| `UI.show_prompt(text, action = "interact")` / `UI.hide_prompt()` | bottom-centre prompt with the key cap from `InputSetup.label(action)` |
| `UI.banner(text, sub = "", color, duration = 4.0)` | big centre banner ("DOWN", "ARRESTED" ...); `banner("")` hides it |
| `UI.subtitle(text, duration = 3.0)` | bottom-centre subtitle (honours the `subtitles` setting) |
| `await UI.fade_out(d)` / `await UI.fade_in(d)` | full-screen fade on real time (works while paused / in slow motion); a newer fade supersedes a running one and both awaits still return |
| `UI.open_screen(id, args = {}) -> Control` | opens a screen from `UI.SCREENS`; `null` if the file is missing |
| `UI.close_screen(id = "")` | closes that screen, or the top one |
| `UI.toggle_screen(id, args)`, `UI.close_all_screens()`, `UI.is_screen_open(id = "")` | as before |
| `UI.set_hud_visible(on)`, `UI.get_hud()` | HUD switch (screenshots, photo mode, cutaways) |

### Additions

`get_top_screen()`, `get_screen(id)`, `get_game_theme()`, `set_waypoint(pos: Vector3)`,
`clear_waypoint()`, `has_waypoint()`, `get_fade_alpha()`, `is_banner_showing()`,
`get_prompt_text()`, `set_debug_overlay(on)`, `toggle_debug_overlay()`, `sfx(id)`, `quick_save()`,
`quick_load()`, `handle_action(action, pressed = true)`, `set_loading_veil(on)`,
`is_loading_veil_visible()`; members `hud`, `game_theme`, `map_data` (UiMapData), `nav` (UiNav),
`stats` (UiStats), `toasts` (UiToasts), `mouse_capture_enabled`, `debug_overlay_visible`.

### Global actions (`_unhandled_input` -> `UI.handle_action`)

| action | effect |
|---|---|
| `pause` (Esc) / `ui_cancel` | top screen's `handle_back()`, else close the top screen, else open `pause` |
| `map` (M) | toggle the map (also on top of the pause menu) |
| `weapon_wheel` (Tab, hold) | open on press, equip + close on release (also closes if the key goes up while the window is unfocused) |
| `radio_wheel` (Y, hold) | open the radio wheel on press (only while `radio.is_listening()`; in a vehicle without a radio a toast says so), tune in + close on release |
| `admin_menu` (F1), `phone` (P), `photo_mode` (F2) | toggle `admin` / `phone` / `photo` when no other screen is open (silently nothing while those files do not exist) |
| `quick_save` (F5) / `quick_load` (F9) | `SaveSystem.save_game("quick")` / `load_game("quick")` + toast |
| `debug_overlay` (F3) | FPS / frame time / position / district / draw calls / entity counts. While the debug system exists (`UI.has_rich_debug_overlay()`), the UI's own text box stays hidden and the debug system draws its richer overlay on the same flag |

Tests that want to drive these must send real events (`Input.parse_input_event(InputEventAction)`)
or call `UI.handle_action()`; `Input.action_press()` alone does not create an input event.
`W A S D` are added to `ui_up / ui_left / ui_down / ui_right` at boot so menus navigate with the
movement keys as well as the arrows / d-pad.

### Screen stack rules

Per-screen constants (all optional): `PAUSES_GAME` (default false), `TIME_SCALE` (1.0),
`LOCKS_INPUT` (true), `SHOWS_MOUSE` (true), `HIDES_HUD` (false). The manager reference-counts
pausing (`Game.set_paused`), requests slow motion through `Game.request_time_scale("ui_<id>", s)`,
calls `Game.lock_input()` / `unlock_input()` exactly once per screen, and restores everything on
close. `EventBus.ui_screen_opened / ui_screen_closed` are emitted.

### Mouse mode

UI is the only owner of `Input.mouse_mode`: **captured** during gameplay (window focused, game
ready, no screen with `SHOWS_MOUSE`), **visible** otherwise. It is never captured in headless
runs, under the TestHarness (`--test=`), before `game_ready`, while the window has no focus, or
when `UI.mouse_capture_enabled` is false. Run with `--ui_debug` to print every mode change
(verified in a plain windowed session: `[UI] mouse mode -> captured  (screens: [])` right after
`game_ready`).

### Sessions without the bootstrap scene

When an isolated test scene runs (no `Main`, so `EventBus.game_ready` never fires) the loading
veil and the HUD hide themselves one frame after boot, so they never cover an asset showcase or
a physics test bed. Call `UI.set_hud_visible(true)` in such a scene if you do want the HUD.

---------------------------------------------------------------------------------------------------

## 3. HUD layout and data sources

`gta/code/ui/hud/hud_root.gd` (`HudRoot`). Pieces appear only when relevant.

```
+--------------------------------------------------------------------------------------+
|                          [* * * - -]  wanted strip            +$350  [ $18,600 ]     |
|                           WANTED / SEARCHING + escape bar        [ toast ]           |
|                          (pin) MIDTOWN   district / radio        [ toast ]           |
|                                                                                      |
|                                    -+-   crosshair + hit marker                      |
|                                                                                      |
| (sun) 09:30  MIDTOWN                                                  ( 87 km/h )    |
|  ( minimap )   [bolt  ------   ]        [F] Enter vehicle             ( gauge   )    |
|  (         )   [shield ----  40]                                   [ KESTREL 9    ]  |
|  (         )   [heart ------ 62]                                   [ icon  9 / 48 ]  |
+--------------------------------------------------------------------------------------+
```

| piece (class) | shows | source |
|---|---|---|
| `HudVitals` | health, armor (row hidden at 0), thin stamina / breath bars while not full, damage "ghost", low-health pulse | `EventBus.player_health_changed`; polls `player.stamina / breath / health / armor / max_*` |
| `HudMoney` | money pill with counting animation, fading `+$ / -$` deltas | `EventBus.money_changed`, `Game.money` |
| `HudWanted` | 0-5 stars, hidden at 0; PURSUIT: flashing red / blue edge; SEARCH: blinking stars, "SEARCHING" and the escape-progress bar | `Wanted.level / state / escape_progress` (polled while wanted) |
| `HudWeapon` | weapon name, class icon, mag / reserve, low-ammo colour, reload bar; hidden while unarmed | `EventBus.weapon_equipped / ammo_changed / weapon_reload_started`, Registry `weapons`, `inventory.get_ammo()` |
| `HudCrosshair` | dot when unarmed, four ticks whose gap is the real spread cone (degrees -> pixels with the camera FOV), hit marker (coral on a kill); hidden while driving unless the player aims (drive-by) | `player.inventory.get_current_spread()` (or `get_spread()`), `EventBus.hit_confirmed` |
| scope overlay | shader mask + reticle, replaces the crosshair | `EventBus.camera_mode_changed("scope")` |
| `HudVehicle` | arc speedometer, km/h, vehicle name, condition bar, `ALT n m` for helicopters / planes; slides into the weapon card's place while unarmed | `EventBus.player_entered_vehicle / player_exited_vehicle`; reads `speed_kmh`, `health`, `max_health`, `vehicle_class`, `spec_id` |
| `HudClock` | weather icon (moon on clear nights), clock, district | `EventBus.time_changed / weather_changed / day_phase_changed`, `WorldClock.get_time_string()` |
| `HudCaption` | district name on entering a district; radio station name + genre | `EventBus.player_district_changed` (+ 2 Hz poll of `Game.world.get_district`), `EventBus.radio_station_changed` + Registry `radio_stations` |
| `HudPrompt` | interaction prompt | `UI.show_prompt / hide_prompt` |
| vignette | low-health vignette (below 35 % health) and damage flash, one shader quad, hidden when idle | health, `EventBus.player_damaged` |
| `Minimap` | see section 4 | |
| toasts (`UiToasts`, in the overlay) | notifications, skill-up toasts | `UI.notify`, `EventBus.notification`, `EventBus.skill_changed` |

Notes for neighbours:

- **Skills:** a single skill gaining a level shows a toast; three or more skills changing in one
  frame (load, reset, admin "max all") update silently.
- **Radio:** the HUD caption is the station announcement, so the HUD sets
  `Game.get_system("radio").announce = false` on `game_ready` (otherwise the radio system's own
  toast would duplicate it). The caption is skipped while `radio.is_listening()` is false.
- **Hit marker:** `info.killed` (or `kill` / `lethal`) = true in `EventBus.hit_confirmed` turns the
  marker coral.
- **Vehicle names:** Registry `vehicles` -> `display_name`, else the capitalised `spec_id`.
- A 4 Hz safety poll re-syncs health, money, vehicle and weapon if a signal was missed.
- `UI.hud.get_state()` returns what the HUD currently displays (used by tests).
- Hot path: per-frame work is plain property reads; strings are rebuilt only when the displayed
  integer changes, custom-drawn pieces redraw only on change or while animating.

---------------------------------------------------------------------------------------------------

## 4. Minimap and map data

`UiMapData` (`UI.map_data`) normalises `Game.world.get_minimap_data()` into map space
(x = world X, y = world Z, north up): `roads` (by kind / width), `coast`, `lots` (zone tint,
landmarks in teal), `labels`, `water`, and the world's extras `piers`, `decks`, `transit`,
`helipads`, `bounds`. Named places come from `Game.world.get_locations()` with code-drawn glyphs
(`UiMapData.place_defs()`); names published by the world as `"location"` labels win. If the world
has no minimap data it falls back to `Game.world.roads.segments`, then to a soft read of the
`WorldLayout` script constants (so the UI can be tested with `--disable=world`), then to nothing.

`Minimap` (bottom-left, circular, heading-up):

- the static geometry lives in a `MinimapWorldLayer` (a `Node2D`) that bakes roads, coast, water,
  lots and piers **once** into a single vertex-coloured `ArrayMesh` (~23 k triangles, one draw
  call); per frame only that node's transform changes (rotation = camera yaw, scale = zoom),
  clipped by a circular `clip_children` mask. The layers are `Node2D`s on purpose: a `Control`
  layer is culled by its own rect, so the map vanished as soon as the layer origin (the island
  centre) left the screen;
- dynamic content (GPS route, search circle, place icons, waypoint, blips) is drawn in the same
  map space on a second layer, redrawn at 30 Hz, and shares the transform, so it moves at 60 fps;
- shown radius: 95 m on foot, 150-235 m in ground vehicles (by speed), 330 m in aircraft;
- police: nodes in group `police` - blue dots in range; while wanted they flash red / blue and
  stick to the rim when further away (up to 450 m); the ring flashes during a pursuit;
- SEARCH: `Wanted.search_radius` circle around `Wanted.last_known_position`;
- waypoint pin (sticks to the rim) and the route from `Game.world.roads.find_route()`
  (straight line when there is no road graph);
- **without map data it draws a plain radar** (range rings + cross) with the same blips.

Extra blips for any module: add a `Node3D` to group **`minimap_blip`**, optional metas
`blip_icon` (UiIcons id), `blip_color` (Color), `blip_clamp` (bool, stick to the rim).

`UiNav` (`UI.nav`): `set_waypoint(pos)`, `clear_waypoint()`, `has_waypoint`, `waypoint`, `route`
(PackedVector2Array, map space), `route_length`. It emits and listens to
`EventBus.waypoint_changed`, re-routes when the player moved 12 m and clears the waypoint on
arrival (14 m). There are no mission markers - the only marker is the player's own waypoint.

---------------------------------------------------------------------------------------------------

## 5. Screens

| id | file | flags | notes |
|---|---|---|---|
| `pause` | `screens/pause_screen.gd` | pauses, hides HUD | Resume, Map, Status, Settings, Save, Load, Quit. Settings tabs: Controls (mouse sensitivity, invert Y, FOV, camera shake), Audio (master / effects / music / ambience, subtitles), Display (V-Sync, max FPS 30 / 60 / 120, render scale 50-100 %, shadow quality, performance overlay), World (traffic / pedestrian density). Applied live with `Settings.set_value(key, v, false)`, written on leaving. Save uses slot `manual`; Load takes the newer of `manual` / `quick`. `open_screen("pause", {"page": "settings", "tab": 2})`. |
| `status` | `screens/status_screen.gd` | pauses, hides HUD | the 7 skills with bars (`Skills`), session info, `UiStats` statistics |
| `map` | `screens/map_screen.gd` | pauses, hides HUD | full island map, drag / WASD pan, wheel / + - zoom, Space centres on the player, hover names (places, roads), left click sets a waypoint (snaps to a place), click it again / right click clears, GPS route, legend. `open_screen("map", {"focus": "player", "zoom": 2.0})`; helpers `to_view()`, `to_map()`, `focus_on()`, `click_at()` |
| `weapon_wheel` | `screens/weapon_wheel.gd` | `TIME_SCALE 0.15`, mouse stays captured | 8 slots clockwise from the top (melee, handgun, smg, shotgun, rifle, sniper, heavy, thrown). Mouse / right stick direction or 1-8 selects, mouse wheel swaps weapons inside a slot, release Tab equips through `inventory.equip(id)`, LMB equips at once, Esc cancels. Data: `inventory.get_wheel_data()` (fallback `get_weapons()` + Registry slots), `get_ammo()`, `get_spec()`. Helpers `select_slot()`, `set_pointer()`, `get_hovered_slot()`, `get_hovered_weapon()`, `cycle()`. |
| `phone` | `screens/phone_screen.gd` | input locked, mouse | section 12.1 |
| `photo` | `screens/photo_mode.gd` | pauses, hides HUD, mouse captured | section 12.2 |
| `radio_wheel` | `screens/radio_wheel.gd` | `TIME_SCALE 0.15`, mouse captured | section 12.3 |
| `activity_result` | `screens/activity_result_screen.gd` | pauses, hides HUD | section 12.4 |

Screens owned by other modules live in the same folder: `admin` (admin_menu.gd, DEBUG), the shop
screens, `garage` / `mod_garage` / `wardrobe` / `safehouse` (ECONOMY / VEHICLE), `taxi` (TRAFFIC).

---------------------------------------------------------------------------------------------------

## 6. How to add a screen

1. Create the script at the path listed in `UI.SCREENS` for your id (the table is fixed; ask the
   lead for a new id). Extend `UiScreen` (recommended) or plain `Control`.
2. Declare the constants you need and build the layout in `_ready()` with the widget kit.
3. Fill it in `open(args)`; undo side effects in `close()`.
4. Open it from gameplay with `UI.open_screen("<id>", {...})` (e.g. from an `Interactable`).

```gdscript
extends UiScreen
## res://gta/code/ui/screens/weapon_shop_screen.gd   ->   UI.open_screen("shop_weapons", {"shop_id": "bay_arms"})

const PAUSES_GAME := false
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := false

var _list: UiList
var _header: UiHeader


func _ready() -> void:
	var margin := UiKit.margin(null, 80, 64, 80, 96)
	UiKit.fill(margin)
	add_child(margin)
	var panel := UiKit.panel(&"GlassPanel")
	panel.custom_minimum_size.x = 760.0
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(panel)
	_header = UiKit.header("Bay Arms", "Weapons and ammunition", UiStyle.money(Game.money))
	panel.add(_header)
	_list = UiList.new()
	_list.item_activated.connect(_on_buy)
	panel.add(_list)
	panel.add(UiKeyHints.new([{"keys": ["W", "S"], "text": "Navigate"}, {"key": "Enter", "text": "Buy"},
			{"action": "pause", "text": "Back"}]))


func open(_args: Dictionary) -> void:
	_list.set_items([{"text": "Pistol", "sub": "9 mm sidearm", "price": 450, "icon": &"handgun", "id": "pistol"}])
	_list.grab()                      # keyboard focus


func regain_focus() -> void:        # a screen opened on top of this one closed
	_list.grab()


func _on_buy(_index: int, item: Dictionary) -> void:
	if not Game.spend(int(item["price"])):
		UiKit.sfx("ui_error")
		return
	UiKit.sfx("ui_buy")
	_header.right_text = UiStyle.money(Game.money)
	_list.refresh()                   # prices recolour against the new balance
```

Rules: Esc is handled by the manager (`handle_back()` first, then the screen closes) - do not read
the `pause` action yourself. Never touch `Input.mouse_mode`, `get_tree().paused`,
`Engine.time_scale` or `Game.lock_input()` in a screen; the constants do it. Use real time
(`delta / Engine.time_scale`) for animations in slow-motion screens. `UiScreen` gives you
`screen_id`, `close_self()`, `confirm(title, text, ok, cancel, danger)` (one modal
`UiConfirmDialog`), a dim backdrop (`backdrop_alpha`, set it in `_init()` after `super()`), and a
short fade-in.

---------------------------------------------------------------------------------------------------

## 7. Widget kit

All in `gta/code/ui/widgets/`. Screenshot of the kit: `qa/screenshots/ui_widgets.png`.

| widget | purpose | essentials |
|---|---|---|
| `UiKit` (static) | factories and helpers | `label(text, variation)`, `paragraph()`, `button(text, callable, variation)`, `vbox()`, `hbox()`, `grid()`, `margin(child, l, t, r, b)`, `spacer()`, `separator()`, `panel()`, `header()`, `icon()`, `stat_row(name, value)` + `set_stat_value()`, `fill(control)`, `sfx(id)`, safe cross-module reads `num()`, `text_of()`, `flag()` |
| `UiScreen` | optional base class for screens | section 6 |
| `UiPanel` | glass panel with a vertical `body` | `UiPanel.new(variation, separation)`, `add(node)`, `clear()` |
| `UiHeader` | accent bar + caps title + subtitle + right value | `title`, `subtitle`, `right_text`, `accent`, `title_size` |
| `UiList` / `UiListRow` | scrolling list with selection | `set_items([...])`, `add_item()`, `update_item()`, `refresh()`, `select(i)`, `grab()`, `selected`, signals `item_selected(i, item)`, `item_activated(i, item)`. Item keys: `text, sub, icon, icon_color, right, right_color, price, owned, badge, disabled, id` |
| `UiPriceRow` | stand-alone price row | `UiPriceRow.new(name, price, owned, icon, sub)`, `set_price()`, `is_affordable()`, signal `activated`; redraws on `money_changed` |
| `UiSliderRow` | label + slider + value | `UiSliderRow.new(label, min, max, step, value, format, display_scale)`; formats `percent int float1 float2 deg` or a printf string; signal `value_changed(v)` |
| `UiOptionRow` | label + `< value >` cycler (toggles, quality lists) | `UiOptionRow.new(label, options, index)`, `wrap`, `step(dir)`, signal `changed(index)` |
| `UiTabBar` | caps tab strip, Q / E (LB / RB) | `UiTabBar.new(names, current)`, `select(i)`, `active`, signal `tab_changed(i)` |
| `UiKeyHints` | footer of key caps + text | `UiKeyHints.new([{"action": "pause", "text": "Back"}, {"key": "Enter", "text": "Select"}, {"keys": ["W", "S"], "text": "Navigate"}], align_right)` |
| `UiConfirmDialog` | modal confirm | `UiConfirmDialog.ask(parent, title, text, ok, cancel, danger)`, signals `confirmed`, `cancelled`, `closed(accepted)`; Esc cancels; or `UiScreen.confirm(...)` |
| `UiBar` | rounded progress bar + icon + value | `UiBar.new(color, icon, height)`, `value` (0..1), `value_text` |
| `UiIconRect` | a Control showing one glyph | `UiIconRect.new(id, size, color)` |
| `UiCanvas` | Control whose `_draw` is a Callable | `UiCanvas.new(func(c): c.draw_circle(...))` |

Navigation is Godot's focus system: rows and buttons are focusable, `ui_up / ui_down` (arrows,
W / S, d-pad) move, `ui_left / ui_right` change sliders and option rows, `ui_accept` (Enter,
Space, pad A) activates, the mouse focuses on hover. Call `list.grab()` / `control.grab_focus()` in
`open()`. Sounds (`ui_hover`, `ui_click`, `ui_tab`, `ui_error`, `ui_open`, `ui_close`) are played
by the widgets through `Audio` on the `UI` bus.

Custom drawing helpers in `UiStyle`: `box()`, `cached_box(key)` (`glass, glass_light, solid,
pill, track, track_dark, key, toast, select, select_dim, hover, chip`), `text()`, `text_in()`,
`text_outlined()`, `text_width()`, `draw_keycap()`, `draw_bar()`, `money(n)`, `duration(sec)`,
`kind_color(kind)`.

---------------------------------------------------------------------------------------------------

## 8. Icons

`UiIcons.draw(canvas_item, id, centre, size, colour)` inside any `_draw()`; no image files.

- HUD / status: `heart shield star bolt bubbles speed dollar stats check close info warn lock`
- weapon classes: `fists bat handgun smg shotgun rifle sniper heavy grenade`
  (`UiIcons.weapon_slot_icon(slot)`)
- map: `house hospital police gun_shop wrench shirt scissors bag drop parking plane helipad
  anchor lighthouse mountain target taxi flag umbrella tram ramp pin arrow north`
- entities / menu: `car boat heli person radio gear map save load power play`
- weather: `sun moon cloud rain storm fog` (`UiIcons.weather_icon(id, night)`)
- arrows: `chev_left chev_right chev_up chev_down`, shapes `circle ring`
- wave 3: `parachute hat glasses shoes phone call camera flame (fire) medal trophy timer note eye
  eye_off filter signal battery ambulance altimeter` (wardrobe / general store: use `hat`, `glasses`,
  `shoes`, `parachute` instead of the old `person` / `umbrella` stand-ins)

Detail strokes ("ink") are navy on light glyph colours and cream on dark ones, so a navy glyph on a
coloured tile keeps its details.

Sheet of all glyphs: right half of `qa/screenshots/ui_widgets.png`.

---------------------------------------------------------------------------------------------------

## 9. Tests

```powershell
# API + behaviour (headless, 105 checks)
tools\godot.ps1 -Mode headless -Frames 1500 -UserArgs '--test=ui_api','--no_player','--disable=world,traffic,peds,police'

# screenshots (windowed, about 12 s at 30 fps) -> qa/screenshots/ui_*.png
tools\godot.ps1 -Mode window -Frames 560 -UserArgs '--test=ui_shots','--no_player','--disable=traffic,peds,police,vehicles,pickups,props,interactions,city,emergency,wildlife,shops,garage,transit,taxi,activities,respawn,radio,ambience,debug'
#   add '--ui_only=<name>[,<name>...]' for some shots: hud_foot hud_vehicle hud_search hud_low hud_air scope debug veil banner
#   wheel pause settings status map map_zoom widgets
```

`ui_shots` installs a fake player / inventory / vehicle (plain scripted nodes) because it runs
with `--no_player`; the world system stays enabled so the minimap and the map use the real
`World.get_minimap_data()`.

```powershell
# live integration: REAL player, inventory and world (21 checks; windowed adds 4 PNGs ui_live_*)
tools\godot.ps1 -Mode headless -Frames 900 -UserArgs '--test=ui_live','--disable=traffic,peds,police'
tools\godot.ps1 -Mode window  -Frames 420 -UserArgs '--test=ui_live','--disable=traffic,peds,police'
```

`ui_live` checks HUD health / money / clock against the real player, the real minimap data and
district, a GPS route to the gun shop, the weapon card and spread crosshair with the real
`WeaponInventory`, Tab hold -> wheel in slow motion -> release equips the highlighted weapon, and
pause / map / back-out restoring pause and the input lock. Modules that are missing are skipped
with a log line instead of failing.

---------------------------------------------------------------------------------------------------

## 10. File list

```
gta/code/ui/
  ui_manager.gd            autoload "UI"
  ui_style.gd              UiStyle: palette, type scale, fonts, style boxes, draw helpers
  ui_theme_builder.gd      UiThemeBuilder.build() -> Theme
  ui_icons.gd              UiIcons: code-drawn glyphs
  ui_map_data.gd           UiMapData: normalised map data + places
  ui_nav.gd                UiNav: waypoint + GPS route
  ui_stats.gd              UiStats: free-roam statistics (saved)
  ui_toasts.gd             UiToasts: notification stack
  ui_banner.gd             UiBanner: centre banner
  hud/                     hud_root, hud_vitals, hud_money, hud_wanted, hud_weapon, hud_crosshair,
                           hud_vehicle, hud_clock, hud_caption, hud_prompt, minimap, minimap_world_layer
  screens/                 pause_screen, status_screen, map_screen, weapon_wheel
  widgets/                 ui_kit, ui_screen, ui_panel, ui_header, ui_list, ui_list_row, ui_price_row,
                           ui_slider_row, ui_option_row, ui_tab_bar, ui_key_hints, ui_confirm_dialog,
                           ui_bar, ui_icon_rect, ui_canvas, ui_canvas_2d
  shaders/                 hud_vignette.gdshader, hud_scope.gdshader
  tools/ui_gen_theme.gd    exports game_theme.tres
gta/scenes/ui/hud.tscn
gta/resources/themes/game_theme.tres   (generated)
gta/tests/ui_api.gd, gta/tests/ui_shots.gd, gta/tests/ui_live.gd
```

Reserved class names used: `Ui*`, `Hud*`, `Minimap*`.

---------------------------------------------------------------------------------------------------

## 11. Known issues / notes

- `core/settings.gd` `apply()` sets `Engine.max_fps` from the `max_fps` setting (default 60), which
  overrides the run wrapper's `--max-fps 30` in windowed test runs (they really run at ~60 fps).
  Not a UI file - reported to the lead.
- The UI never imitates another game's HUD; banners use our own wording ("DOWN", "ARRESTED").
- Weapon-wheel wedges show class glyphs (melee, handgun, smg ...), not per-weapon models; the
  centre shows the highlighted weapon's display name and ammo, the scroll wheel cycles weapons
  inside one class.

---------------------------------------------------------------------------------------------------

## 12. Wave 3 additions

Screenshots: `qa/screenshots/ui3_*.png` (phone home / contacts / call / map, photo mode + noir,
a real capture `ui3_photo_capture.png`, radio wheel, activity result, parachute HUD, dive HUD,
activity + taxi + stealth + search HUD).

### 12.1 Phone - "Shoreline" (`phone`, P / d-pad up)

An original handset sliding in on the right (status bar, sunset wallpaper, 4 x 2 app grid, a
"today" card with cash / police / waypoint). The game keeps running (input locked, mouse shown).
Arrows / WASD move the focus, Enter selects, Esc goes back (app -> home -> closed), P closes.
`UI.open_screen("phone", {"app": "contacts"})` opens straight into an app.

| app | does | talks to (soft) |
|---|---|---|
| Contacts | Bay Cabs (taxi), Torque Garage (personal vehicle delivery), Halcyon Medical (ambulance), Bay Fire Dept. A call shows a short "calling" screen (0.9 s), then the answer + a toast | taxi: `call_taxi(pos)` (or `request_taxi` / `summon_taxi`, 0 or 1 arg; `last_error` read on failure); garage: `deliver_personal_vehicle(pos)` + `last_error`, `get_personal_vehicle()`, `get_stored()`; emergency: `call_ambulance(pos)` / `request_ambulance` / `dispatch_ambulance`, `call_firetruck(pos)` / `call_fire_truck` / `request_firetruck` / `dispatch_firetruck`, else a generic `call_service(kind, pos)` / `request_service` / `dispatch_service` / `dispatch` with kind `"ambulance"` / `"firetruck"`. A missing system / method greys the row out ("Not in service") |
| Map | Open the full map, clear the waypoint, one-tap GPS to every named place (sorted by distance) | `UI.map_data.places`, `UI.set_waypoint()` |
| Camera | closes the phone, opens photo mode | |
| Radio | pick a station (off + all stations, ON AIR badge) | radio: `get_stations(true)`, `get_station()`, `set_station(id)`, `is_listening()` |
| Garage | deliver the personal vehicle, list of stored vehicles (condition, PERSONAL badge, n / capacity) | garage W2.7 API |
| Skills | status screen on top of the phone | |
| Save | quick save, load the quick save (confirm dialog, shows the save age) | `UI.quick_save()`, `UI.quick_load()`, `SaveSystem.slot_path()` |
| Settings | pause menu settings page on top of the phone | |

Test helpers: `get_page()`, `launch(app)`, `show_page(page)`, `get_list()`, `find_row(id)`,
`activate_row(i)`, `is_calling()`, `service_status(contact)`, `last_action` ("taxi:ok", ...).

### 12.2 Photo mode (`photo`, F2 or the phone camera)

Pauses the game, hides the HUD and flies its own `Camera3D` (the gameplay rig does not run while
paused) within 25 m of the player, above the terrain and stopped by walls (`Layers.CAMERA_MASK`).
WASD move, Space / C up / down, Shift fast, mouse / right stick look, Q / E roll (+-45 deg), Z / X or
the wheel zoom (FOV 15-100), F / Shift+F / Left / Right filter, T focus (depth of field: Off,
Portrait = blur behind the subject, Deep = blur near + far, `CameraAttributesPractical`), G thirds
grid, H hide the panel (and toasts), R reset, Enter / left click take a photo, Esc / F2 leave.
Filters are presets of one full-screen grade shader `shaders/photo_filter.gdshader` (saturation,
contrast, lift, tint, split toning, mono, vignette, grain): Natural, Golden Hour, Harbour Noir,
Postcard, Neon Nights, Tropic Pop, Low Tide, Old Pier.
`take_photo()` (awaitable) hides the panel for one frame, reads the viewport and writes
`user://photos/halcyon_<date>_<time>_<n>.png`, plays `camera_shutter`, flashes and toasts;
signal `photo_taken(path)`. Headless runs have no frame: the state machine runs, the path is "".
API: `set_filter(i)`, `cycle_filter(dir)`, `get_filter_name()`, `set_fov()`, `set_roll()`,
`set_dof_mode(i)`, `set_grid()`, `set_ui_visible()`, `move_camera_to(pos)`, `reset_camera()`,
`save_image(img)`, `get_camera()`, `distance_to_subject()`, `photos_taken`, `last_photo_path`.

### 12.3 Radio wheel (`radio_wheel`, hold Y)

Off + every station of the radio system on a ring clockwise from the top (station colour on the rim,
name, frequency, ON AIR dot), hub with genre + tagline + a level meter. Time slows to 0.15 like the
weapon wheel. Mouse / right stick point, 1-9 pick, wheel / `radio_next` / `radio_prev` browse,
release (or click) tunes in through `set_station(id)`, Esc cancels. Only opens while
`radio.is_listening()` (vehicles with a radio). Helpers: `get_station_ids()`, `select_index()`,
`select_station()`, `set_pointer()`, `cycle()`, `get_hovered_station()`.

### 12.4 Activity results (`activity_result`)

The UI opens it on `EventBus.activity_finished(id, result)` (deferred one frame, so an activity
system that opens it itself wins; `result["result_screen"] = false` opts out). Pauses, hides the
HUD. **Result keys** (all optional): `id, title, subtitle, passed` (or `success`, default true),
`medal` (`gold` / `silver` / `bronze` / ""), `fail_reason`, `lines: [{label, value, best: bool,
color}]` (or `score_lines`, or a `stats` Dictionary label -> value), `time` + `best_time` (seconds,
added as lines), `score`, `reward` (or `money`, shown as a chip - the activity pays it, the UI does
not), `xp: {skill: amount}` (chips; the activity grants it), `new_record`, `can_retry`, `retry`
(Callable). Retry uses `retry` if valid, else the activities system's `retry_activity(id)` /
`retry(id)` / `start_activity(id)` / `start(id)`; without any the button is hidden. The title falls
back to Registry `activities` -> `display_name` / `name`.

### 12.5 HUD additions

| piece | where | shows | source |
|---|---|---|---|
| `HudActivity` | top-left | activity title, timer (counts locally between polls, red under 10 s when counting down), CP / LAP / POS / SCORE chips (CP chip flashes on a new checkpoint), hint | `EventBus.activity_started / activity_finished`; polls `activities.get_hud_info()` at 10 Hz: `{title, subtitle, time, time_mode: "up"/"down", checkpoint, checkpoints, lap, laps, position, racers, score, target, hint, color, active}` (`{"active": false}` hides, `{"active": true, ...}` shows even without the signal, `{}` = no update) |
| `HudTaxiMeter` | top-left, under the activity card | fare (counts up), destination + distance | polls `taxi.get_fare()` at 4 Hz (number or `{fare, distance, destination}`) while `taxi.is_player_riding()` / `is_riding()`, else while the player sits in a `taxi` vehicle someone else drives; `{"active": false}` or a negative fare hides it |
| `HudAltimeter` | right edge | FREEFALL / CANOPY, metres above ground, vertical speed, square-root tape 0-1000 m, a pulsing "[Space] OPEN" cue in freefall below 140 m | player public state `freefall` / `parachute` (EventBus.player_state_changed, `player.state.public_name` or `player.animator.state`), `player.altitude_agl` (fallback: terrain / sea under the player), `player.velocity.y`; deploy key = `InputSetup.label("jump")`. The minimap switches to its aircraft range while skydiving |
| `HudDive` | right edge | breath ring (sun < 50 %, pulsing coral < 25 %), depth, SCUBA tag; replaces the thin breath bar of the vitals card | `player.is_underwater`, `breath`, `water_surface_y`, `has_scuba` |
| `HudStealth` | under the crosshair | eye (closed when hidden), STEALTH / HIDDEN, visibility bar | `player.in_stealth` or state `stealth`, `player.visibility_factor` |
| crosshair `blocked` | centre | coral "no shot" ring while drive-by aiming outside the seat's arc | `player.state.drive_by_in_arc` (PlayerStateVehicle) |
| vehicle altitude | vehicle cluster | `ALT n m` for aircraft | `vehicle.altitude_agl` (fallback height above sea level) |
| minimap / map police | minimap, map | police helicopters (a `police` node with `vehicle_class == "heli"`, or an officer seated in one) as a heli glyph with a search light, drawn once, visible up to 900 m on the rim while wanted; SEARCH circle centred on `Wanted.search_center`; during SEARCH short sight cones (24 m on foot, 34 m vehicles, max 18) in front of every unit in range | group `police`, `Wanted.search_center` / `search_radius` |
| noise ring | minimap | soft ring of `player.noise_radius` (decays smoothly) while on foot | `player.noise_radius` |

`UI.hud.get_state()` adds `activity, activity_time, taxi_fare, altimeter, altitude, pull_warning,
dive, breath, scuba, stealth, drive_by_blocked`.

### 12.6 Tests

```powershell
# API (headless): every new screen + HUD widget against fake neighbour systems
tools\godot.ps1 -Mode headless -Frames 4000 -UserArgs '--test=ui3_api','--no_player','--disable=traffic,peds,police,vehicles,pickups,props,city,interactions,shops,garage,transit,taxi,activities,radio,ambience,respawn,emergency,wildlife'
# screenshots (windowed, ~15 s) -> qa/screenshots/ui3_*.png ; --ui3_only=<names> for a subset
tools\godot.ps1 -Mode window -Frames 900 -UserArgs '--test=ui3_shots','--no_player','--disable=traffic,peds,police,vehicles,pickups,props,interactions,shops,garage,transit,taxi,activities,radio,ambience,respawn,emergency,wildlife,debug'
```
Both register small fake taxi / garage / emergency / activities / radio nodes with
`Game.register_system()` so every path runs while those modules are still being written; the real
systems are exercised only through these documented calls. In PowerShell pass several check
folders as ONE string: `-Dirs 'gta/code/ui,gta/tests'`.

New files: `screens/phone_screen.gd, photo_mode.gd, radio_wheel.gd, activity_result_screen.gd`,
`hud/hud_activity.gd, hud_taxi_meter.gd, hud_altimeter.gd, hud_dive.gd, hud_stealth.gd`,
`shaders/photo_filter.gdshader`, tests `ui3_api.gd, ui3_shots.gd`. Reserved class names used:
`HudActivity, HudTaxiMeter, HudAltimeter, HudDive, HudStealth`.
