extends Node
## Global signal hub (autoload "EventBus").
## Systems talk to each other through these signals instead of hard references.
## RULE: signatures here are a frozen contract. You may ADD new signals at the bottom of the
## matching block; never rename/remove/re-order parameters of existing ones.

# --- lifecycle -------------------------------------------------------------------------------
signal game_ready()                                   ## world built + player spawned; free roam starts
signal game_paused(paused: bool)
signal system_toggled(system_name: String, enabled: bool)   ## admin menu toggles (traffic, peds, wildlife ...)

# --- player ----------------------------------------------------------------------------------
signal player_spawned(player: Node3D)
signal player_died(cause: String)
signal player_respawned(position: Vector3)
signal player_busted()
signal player_damaged(amount: float, info: Dictionary)
signal player_health_changed(health: float, armor: float)
signal player_entered_vehicle(vehicle: Node3D, seat: int)
signal player_exited_vehicle(vehicle: Node3D)
signal player_entered_water()
signal player_exited_water()
signal player_submerged(underwater: bool)
signal player_district_changed(district: String)
signal player_appearance_changed(appearance: Dictionary)
signal player_state_changed(state: String)            ## "on_foot","in_vehicle","swimming","parachute","cover","ragdoll","dead" ...

# --- economy ---------------------------------------------------------------------------------
signal money_changed(amount: int, delta: int)
signal item_purchased(kind: String, id: String, price: int)

# --- weapons / combat ------------------------------------------------------------------------
signal weapon_equipped(weapon_id: String)
signal weapon_fired(weapon_id: String, shooter: Node, origin: Vector3, direction: Vector3)
signal ammo_changed(weapon_id: String, in_mag: int, reserve: int)
signal weapon_reload_started(weapon_id: String, duration: float)
signal weapon_inventory_changed()
signal hit_confirmed(target: Node, info: Dictionary)   ## a player shot damaged something (hit marker)
signal explosion(position: Vector3, radius: float, instigator: Node)
signal fire_started(position: Vector3, source: Node)

# --- AI stimuli ------------------------------------------------------------------------------
## kind: "gunshot","suppressed_gunshot","explosion","footstep","horn","scream","crash","siren","engine","melee"
signal noise_emitted(position: Vector3, radius: float, kind: String, instigator: Node)
## Raw crime event (before witness logic). Wanted listens to this through Wanted.report_crime().
signal crime_committed(crime_id: String, position: Vector3, instigator: Node)
signal crime_witnessed(crime_id: String, position: Vector3, witness: Node)
signal crime_reported(crime_id: String, position: Vector3)

# --- wanted / police -------------------------------------------------------------------------
signal wanted_level_changed(level: int, previous: int)
signal wanted_state_changed(state: int)                ## Wanted.State: 0 NONE, 1 PURSUIT, 2 SEARCH
signal wanted_cleared(reason: String)                  ## "escaped","busted","died","cheat"
signal police_unit_spawned(unit: Node3D, kind: String) ## "officer","cruiser","swat","heli","roadblock"

# --- npc / vehicles --------------------------------------------------------------------------
signal npc_spawned(npc: Node3D)
signal npc_died(npc: Node3D, killer: Node, info: Dictionary)
signal npc_injured(npc: Node3D, attacker: Node, info: Dictionary)
signal vehicle_spawned(vehicle: Node3D)
signal vehicle_destroyed(vehicle: Node3D, instigator: Node)
signal vehicle_damaged(vehicle: Node3D, amount: float, info: Dictionary)
signal vehicle_collision(vehicle: Node3D, other: Node, impulse: float, position: Vector3)
signal vehicle_stolen(vehicle: Node3D, thief: Node, had_driver: bool)
signal vehicle_modified(vehicle: Node3D)

# --- world -----------------------------------------------------------------------------------
signal time_changed(hour: float)                       ## emitted about once per in-game minute
signal day_phase_changed(phase: String)                ## "dawn","day","dusk","night"
signal weather_changed(weather_id: String, previous: String)
signal waypoint_changed(has_waypoint: bool, position: Vector3)
signal interactable_focus_changed(interactable: Node)  ## null when nothing is in reach
signal prop_broken(prop: Node3D, instigator: Node)

# --- ui / meta -------------------------------------------------------------------------------
signal notification(text: String, kind: String)        ## kind: "info","good","warn","bad","money"
signal ui_screen_opened(id: String)
signal ui_screen_closed(id: String)
signal skill_changed(skill: String, value: float)
signal activity_started(id: String)
signal activity_finished(id: String, result: Dictionary)
signal save_completed(slot: String)
signal load_completed(slot: String)
signal settings_changed()
signal radio_station_changed(station_id: String)
signal camera_mode_changed(mode: String)               ## "third","first","vehicle","aim","scope","photo"

# --- additions (append below) ----------------------------------------------------------------
