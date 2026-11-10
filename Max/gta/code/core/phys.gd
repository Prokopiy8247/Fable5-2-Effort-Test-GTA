class_name Phys
extends RefCounted
## Physics layer bit masks (names mirror project.godot [layer_names]).

const WORLD := 1 << 0        # static geometry: terrain, buildings, static props
const VEHICLE := 1 << 1      # vehicle rigid bodies
const CHARACTER := 1 << 2    # player + NPC capsules
const PROP := 1 << 3         # dynamic / breakable props, debris
const RAGDOLL := 1 << 4      # physical bones
const TRIGGER := 1 << 5      # interaction + zone areas
const GLASS := 1 << 6        # breakable panes
const VEH_SENSOR := 1 << 7   # vehicle proximity sensors
const PICKUP := 1 << 8       # pickups
const PROJECTILE := 1 << 9   # rockets, grenades
const BOUNDS := 1 << 10      # invisible map limits (ground vehicles + characters only)

## What bullets can hit.
const SHOOTABLE := WORLD | VEHICLE | CHARACTER | PROP | RAGDOLL | GLASS
## Solid things a walking character collides with.
const WALK_SOLID := WORLD | VEHICLE | PROP | CHARACTER | GLASS | BOUNDS
## Things that block line of sight for AI.
const SIGHT_BLOCK := WORLD | VEHICLE
## Things the camera should not clip through.
const CAMERA_BLOCK := WORLD
