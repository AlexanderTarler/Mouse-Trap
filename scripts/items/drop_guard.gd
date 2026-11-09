class_name DropGuard
extends Node
## Keeps a carried or dropped item in the world: nothing (the cabin key above
## all) may end up through a wall, a door or the floor.
##
##   - DropGuard.sweep(...) limits a move to what is clear: an item carried
##     or dropped stops at the first thing in its way instead of passing
##     through it (the held item used to be teleported toward the hold point,
##     through the door, and was let go on the other side).
##   - As a child of a RigidBody3D, it turns on continuous collision (thin
##     door and floor shapes) and puts the item back where it last rested if
##     it ever falls out of the world.

## Layer 1: the level (walls, floors, doors, the terrain) and the props.
const WORLD_MASK := 1
## Standing off a surface it was stopped by (m).
const MARGIN := 0.12
## Below this height (m) nothing is in the world any more.
const FALL_LIMIT := -4.0
## Or this far below where it last rested.
const FALL_DISTANCE := 6.0

var _body: RigidBody3D
var _safe := Vector3.ZERO


## The point nearest `to` that is clear from `from`: `to` itself, or just
## in front of what stands in the way. `exclude` are RIDs to ignore (the
## player, the item).
static func sweep(world: World3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Vector3:
	if world == null or from.is_equal_approx(to):
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = WORLD_MASK
	query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit.position + hit.normal * MARGIN


## Puts a guard on `body` (once).
static func watch(body: RigidBody3D) -> void:
	if body == null or body.has_node("DropGuard"):
		return
	var guard := DropGuard.new()
	guard.name = "DropGuard"
	body.add_child(guard)


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		queue_free()
		return
	_body.continuous_cd = true
	_safe = _body.global_position


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_body):
		return
	var at := _body.global_position
	# At rest somewhere in the world: that is where it goes back to.
	if _body.sleeping or _body.linear_velocity.length() < 0.15:
		if at.y > FALL_LIMIT and at.y > _safe.y - FALL_DISTANCE:
			_safe = at
	elif at.y < FALL_LIMIT or at.y < _safe.y - FALL_DISTANCE:
		_body.linear_velocity = Vector3.ZERO
		_body.angular_velocity = Vector3.ZERO
		_body.global_position = _safe + Vector3.UP * 0.3
		print("[DropGuard] %s fell out of the world: put back at %s." % [_body.name, _safe])
