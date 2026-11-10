class_name Layers
extends RefCounted
## Physics layer bit constants. Names mirror project.godot [layer_names].
## Always build collision_layer / collision_mask from these constants - never magic numbers.

const WORLD := 1 << 0       ## static terrain, roads, buildings, static props
const PLAYER := 1 << 1      ## the player CharacterBody3D
const NPC := 1 << 2         ## pedestrians, police, animals (character bodies)
const VEHICLE := 1 << 3     ## every drivable/flyable/floatable RigidBody3D vehicle
const PROP := 1 << 4        ## dynamic physics props (cones, bins, crates, breakable furniture)
const TRIGGER := 1 << 5     ## Area3D interactables / shop zones / activity zones
const PROJECTILE := 1 << 6  ## grenades, rockets
const WATER := 1 << 7       ## water volumes (Area3D), if used
const HITBOX := 1 << 8      ## optional precise damage areas
const RAGDOLL := 1 << 9     ## ragdoll bones
const COVER := 1 << 10      ## cover helper areas / markers
const CLIMB := 1 << 11      ## ladders, vault helpers
const SENSOR := 1 << 12     ## AI / traffic sensor areas
const PICKUP := 1 << 13     ## pickups (Area3D)
const GLASS := 1 << 14      ## breakable glass panes
const DEBRIS := 1 << 15     ## cosmetic debris that must not block characters

## What characters and vehicles physically collide with.
const SOLID := WORLD | VEHICLE | PROP | GLASS
## Mask for the player body.
const PLAYER_MASK := WORLD | VEHICLE | PROP | NPC | GLASS
## Mask for NPC bodies.
const NPC_MASK := WORLD | VEHICLE | PROP | PLAYER | NPC | GLASS
## Mask for vehicles.
const VEHICLE_MASK := WORLD | VEHICLE | PROP | PLAYER | NPC | GLASS | RAGDOLL
## Mask for dynamic props.
const PROP_MASK := WORLD | VEHICLE | PROP | PLAYER | NPC
## Hitscan bullets fired by the player (exclude the shooter's own RID in the query).
const BULLET_MASK := WORLD | PLAYER | NPC | VEHICLE | PROP | GLASS | RAGDOLL
## Line-of-sight checks (AI vision, witness checks, camera): only opaque things block.
const SIGHT_MASK := WORLD | VEHICLE
## Camera collision probes.
const CAMERA_MASK := WORLD
## Ground probes for characters/vehicle wheels.
const GROUND_MASK := WORLD | VEHICLE | PROP
