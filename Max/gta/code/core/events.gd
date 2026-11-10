extends Node
## Global signal bus. Systems talk to each other through these signals instead of
## holding hard references, so any subsystem can be disabled (debug toggles) safely.

## HUD toast. kind: "info" | "good" | "bad" | "money" | "wanted"
signal notify(text: String, kind: String)
## Big centre-screen banner (WASTED-style, district names, activity results).
signal banner(title: String, subtitle: String, color: Color, seconds: float)
## A crime happened. Witness/police logic decides whether it becomes known.
## type: StringName from Crimes (see wanted_system.gd). data may contain victim, vehicle...
signal crime(type: StringName, position: Vector3, data: Dictionary)
## Audible event for AI hearing. kind: &"gunshot" | &"explosion" | &"footstep" | &"horn" | &"impact" | &"scream" | &"siren"
signal noise(position: Vector3, radius: float, kind: StringName, source: Node)
signal explosion(position: Vector3, radius: float, damage: float, source: Node)
signal wanted_changed(level: int)
signal wanted_state_changed(state: int)
signal player_died(cause: String)
signal player_busted()
signal player_respawned()
signal player_entered_vehicle(vehicle: Node3D, seat: int)
signal player_exited_vehicle(vehicle: Node3D)
signal npc_died(npc: Node3D, killer: Node)
signal npc_hurt(npc: Node3D, attacker: Node, amount: float)
signal vehicle_destroyed(vehicle: Node3D, by: Node)
signal cash_changed(total: int, delta: int)
signal hour_changed(hour: int)
signal weather_changed(kind: StringName)
signal district_changed(name: String)
signal weapon_changed(weapon_id: StringName)
signal world_ready()
signal game_loaded()
signal skill_changed(skill: StringName, value: float)
signal fire_started(position: Vector3, source: Node)
signal bullet_impact(position: Vector3, normal: Vector3, surface: StringName)
signal menu_closed()
signal shop_purchase(shop: String, item: String, price: int)
