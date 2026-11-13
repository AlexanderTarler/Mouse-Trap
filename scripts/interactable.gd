class_name Interactable
extends RefCounted
## Collision layers for things the player can use.
##
## The interaction ray (InteractionManager) only sees layer 2, so invisible
## level geometry on layer 1 (the porch roof, cabin bounding boxes) can never
## swallow it before it reaches a door, a key or a switch. Usable bodies stay
## on layer 1 as well, so the player and the Entity still collide with them.

const LAYER := 2
const LAYER_MASK := 1 << (LAYER - 1)


## Puts `body` on the interaction layer, keeping it solid. Call it last in
## _ready(), after anything that assigns collision_layer outright.
static func make_reachable(body: CollisionObject3D) -> void:
	body.set_collision_layer_value(1, true)
	body.set_collision_layer_value(LAYER, true)
