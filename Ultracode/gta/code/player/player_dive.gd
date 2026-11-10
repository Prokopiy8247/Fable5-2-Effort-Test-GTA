extends Node
## Underwater exploration layer of the player (spec 29A "underwater / diving", docs/PLAYER.md section 15).
## Breath, lung skill and scuba live in PlayerStateSwim; the environment owns the underwater fog /
## colour (gta_underwater) and the ambience the underwater_loop. This helper adds:
##   * the one-time treasure of the shipwreck: an Interactable at the wreck's "Treasure" marker (the
##     props catalogue's marker of the placed "shipwreck" set piece, else the manifest value). Opening
##     the sea chest pays TREASURES[id].cash once per save - Player.treasures_found is saved with the
##     player; a found chest offers nothing any more;
##   * breath bubbles while the head is under water (exhales every few seconds, a steady stream with
##     scuba): Fx.bubbles(pos, scale) when the FX module has it, else a small steam puff;
##   * a short "surfaced" gasp / lung XP stay in the swim state.

const TREASURES := {
	"wreck_chest": {
		"location": "shipwreck",          ## named location of the set piece (WORLD)
		"prop": "shipwreck",              ## dressing asset id
		"marker": "Treasure",             ## marker in the asset (models/misc/manifest_misc.json)
		"fallback": Vector3(0.55, 0.35, -1.15),
		"cash": 2500,
		"prompt": "Open the sea chest",
		"title": "SUNKEN STRONGBOX",
		"sub": "Old coins from the wreck of the Gull's Wager",
	},
}
const USE_RADIUS := 2.6
const SETUP_RETRY := 1.0            ## s between attempts while the world / props are not built yet
const SETUP_TRIES := 30
const BREATH_INTERVAL := 3.2        ## s between exhales (free diving)
const SCUBA_INTERVAL := 1.1         ## s between regulator bursts (scuba)

var player: Node3D = null
var interactables: Dictionary = {}  ## treasure id -> Interactable
var treasure_positions: Dictionary = {}   ## treasure id -> world position (tests / debug)
var bubbles_emitted: int = 0

var _setup_t: float = 0.0
var _tries: int = 0
var _bubble_t: float = 0.0


func setup(p: Node3D) -> void:
	player = p
	_setup_t = 0.5


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# --- treasure set-up once the world (and the wreck) exist
	if interactables.is_empty() and _tries < SETUP_TRIES:
		_setup_t -= delta
		if _setup_t <= 0.0 and Game.is_ready:
			_setup_t = SETUP_RETRY
			_tries += 1
			_build_treasures()
	# --- bubbles
	if player.get("is_underwater") == true and player.get("is_dead") != true:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			var scuba: bool = player.get("has_scuba") == true
			_bubble_t = (SCUBA_INTERVAL if scuba else BREATH_INTERVAL) * randf_range(0.8, 1.2)
			_emit_bubbles(1.0 if scuba else 0.7)
	else:
		_bubble_t = 0.6


## Re-reads Player.treasures_found (after a load): found chests offer nothing.
func refresh_treasures() -> void:
	for id: String in interactables:
		var it: Variant = interactables[id]
		if it is Interactable and is_instance_valid(it):
			(it as Interactable).enabled = not _found(id)


func is_found(id: String) -> bool:
	return _found(id)


func _found(id: String) -> bool:
	var tf: Variant = player.get("treasures_found")
	return tf is PackedStringArray and (tf as PackedStringArray).has(id)


func _build_treasures() -> void:
	if Game.world == null:
		return
	for id: String in TREASURES:
		if interactables.has(id):
			continue
		var def: Dictionary = TREASURES[id]
		var pos := _treasure_position(def)
		if not pos.is_finite():
			continue
		var it := Interactable.create(str(def["prompt"]), USE_RADIUS, "interact")
		it.name = "Treasure_" + id
		it.on_foot_only = true
		it.use_priority = 5
		it.condition = func(pl: Node3D) -> bool: return not _found(id) and pl.get("is_swimming") == true
		var root := Game.get_entities_root()
		if root == null:
			return
		root.add_child(it)
		it.global_position = pos
		it.enabled = not _found(id)
		it.interacted.connect(_on_treasure.bind(id))
		interactables[id] = it
		treasure_positions[id] = pos


## World position of a treasure: the placed set piece's marker (dressing catalogue), else the manifest
## marker, else the fallback; the set piece stands on the terrain at its named location (the dressing
## placer's own rule). INF when the location does not exist.
func _treasure_position(def: Dictionary) -> Vector3:
	var w := Game.world
	var loc_name := str(def["location"])
	if w.has_method("has_location") and not bool(w.call("has_location", loc_name)):
		return Vector3.INF
	var loc: Transform3D = Game.get_location(loc_name)
	if not loc.origin.is_finite():
		return Vector3.INF
	var p := loc.origin
	var wreck := Transform3D(loc.basis.orthonormalized(), Vector3(p.x, Game.ground_height(p.x, p.z), p.z))
	var marker := Transform3D(Basis.IDENTITY, def["fallback"] as Vector3)
	var props := Game.get_system("props")
	if props != null:
		var cat: Variant = props.get("catalog")
		if cat is Object and is_instance_valid(cat) and (cat as Object).has_method("marker"):
			var m: Variant = (cat as Object).call("marker", str(def["prop"]), str(def["marker"]))
			if m is Transform3D:
				marker = m as Transform3D
		elif props.has_method("get_prop_def"):
			var d: Variant = props.call("get_prop_def", str(def["prop"]))
			if d is Dictionary:
				var mk: Variant = ((d as Dictionary).get("markers", {}) as Dictionary).get(str(def["marker"]), null)
				if mk is Array and (mk as Array).size() >= 3:
					marker = Transform3D(Basis.IDENTITY, Vector3(float(mk[0]), float(mk[1]), float(mk[2])))
	return wreck * marker.origin


func _on_treasure(pl: Node3D, id: String) -> void:
	if _found(id) or pl != player:
		return
	var def: Dictionary = TREASURES[id]
	var tf: PackedStringArray = player.get("treasures_found")
	tf.append(id)
	player.set("treasures_found", tf)
	var cash := int(def["cash"])
	Game.add_money(cash)
	var it: Variant = interactables.get(id, null)
	var pos: Vector3 = (it as Node3D).global_position if it is Node3D and is_instance_valid(it) else player.global_position
	if it is Interactable and is_instance_valid(it):
		(it as Interactable).enabled = false
	Audio.play("pickup_cash", -2.0)
	if Fx.has_method("money_burst"):
		Fx.money_burst(pos)
	_emit_bubbles(1.6, pos + Vector3(0.0, 0.4, 0.0))
	UI.banner(str(def["title"]), "%s  +$%d" % [str(def["sub"]), cash], Color(1.0, 0.82, 0.30), 3.5)
	if player.has_method("play_action"):
		player.call("play_action", "pickup", 0.6)


func _emit_bubbles(scale: float, at: Vector3 = Vector3.INF) -> void:
	var pos := at
	if not pos.is_finite():
		pos = player.global_position + Vector3(0.0, 1.62, 0.0) - player.global_basis.z * 0.12
		var anim: Variant = player.get("animator")
		if anim is HumanoidAnimator and (anim as HumanoidAnimator).is_ready():
			var a := anim as HumanoidAnimator
			if a.skeleton != null and a.skeleton.is_inside_tree():
				pos = a.skeleton.global_transform * a.get_eye_position() - player.global_basis.z * 0.08
	# only under the surface (a bubble above it would hang in the air)
	var surf: Variant = player.get("water_surface_y")
	if surf is float and pos.y > float(surf) - 0.15:
		return
	bubbles_emitted += 1
	if Fx.has_method("bubbles"):
		Fx.call("bubbles", pos, scale)
	else:
		Fx.smoke_puff(pos, "steam", 0.22 * scale)
