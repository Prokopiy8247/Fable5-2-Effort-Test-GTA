extends Node3D
## Handle returned by Fx.spawn_fire / Fx.attach_smoke / Fx.attach_trail.
##
## The handle is a plain, cheap Node3D that the CALLER owns: parent it where you like (Fx already
## parents it for you), move it, and `queue_free()` it (or call stop()) to end the effect.
## The pooled particle emitters are NOT children of the handle - they live in the Fx pool and
## follow the handle every frame, so freeing the handle (or its parent vehicle) never destroys
## pooled nodes; Fx gets the slot back through NOTIFICATION_EXIT_TREE.
##
## Fires burn things: every Fx.FIRE_TICK seconds the Fx autoload applies
## `damage_per_second` (type "fire") to every damageable inside `radius`. Callers may tune the
## public fields right after spawning (for example `fire.instigator = player`).

var fx_kind: String = ""            ## "fire" | "smoke" | "trail"
var variant: String = ""            ## smoke: light/heavy/black, trail: rocket/tyre/wake/dust/exhaust
var fx_scale: float = 1.0
var strength: float = 1.0           ## 0..1 emission strength; change it any time (tyre slip, boat speed)
var time_left: float = -1.0         ## seconds until Fx frees the handle; < 0 = until the caller frees it

# --- fire only -----------------------------------------------------------------------------------
var deals_damage: bool = false      ## true for fires (the molotov code checks this)
var damage_per_second: float = 20.0     ## characters / props inside the radius
var vehicle_damage_per_second: float = 30.0
var radius: float = 1.5
var instigator: Node = null         ## who gets the blame for burn damage (may be null)
var weapon_id: String = ""
var ignore: Array = []              ## damageables this fire never burns (its own burning vehicle)

# --- owned by Fx (do not touch) ------------------------------------------------------------------
var fx_owner: Node = null
var emitters: PackedInt32Array = PackedInt32Array()
var base_ratio: PackedFloat32Array = PackedFloat32Array()
var offsets: PackedVector3Array = PackedVector3Array()
var applied_strength: float = -1.0
var burn_tick: float = 0.0
var light_index: int = -1
var audio_index: int = -1
var phase: float = 0.0
var released: bool = false


func set_strength(value: float) -> void:
	strength = clampf(value, 0.0, 1.0)


## Ends the effect (same as queue_free()).
func stop() -> void:
	if not is_queued_for_deletion():
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		if not released and fx_owner != null and is_instance_valid(fx_owner):
			fx_owner.call("_on_handle_gone", self)
