extends Node

## Entity Sensory System — Vision cone, flashlight detection, and audio hearing.
## Receives a reference to the parent entity_controller to read/write shared state.

var entity: CharacterBody3D = null


func setup(parent: CharacterBody3D) -> void:
	entity = parent


## Checks if the Entity can see the player via vision cone + line-of-sight raycast.
func can_entity_see_player() -> bool:
	if not entity._player or not is_instance_valid(entity._player):
		return false
	
	# 1. Are they within the Field of View cone?
	var to_player = (entity._player.global_position - entity.global_position).normalized()
	var forward = -entity.global_transform.basis.z
	
	if forward.dot(to_player) < cos(entity._vision_cone_angle):
		return false
	
	# 2. Is there a wall/tree in the way? (Raycast check)
	var space = entity.get_world_3d().direct_space_state
	var head_pos = entity.global_position + Vector3(0, 2.5, 0)
	var player_chest = entity._player.global_position + Vector3(0, 1.0, 0)
	
	var query = PhysicsRayQueryParameters3D.create(head_pos, player_chest)
	# Exclude both the entity AND the player from the raycast.
	# If the player is not excluded, the ray may hit the player's own collision
	# body and register a false sighting. We only want to detect if something
	# OTHER than the entity or player is blocking line-of-sight.
	query.exclude = [entity, entity._player]
	
	var hit = space.intersect_ray(query)
	# If the raycast hits nothing, or hits the player (which is excluded so it
	# won't be returned), then line-of-sight is clear.
	if hit.is_empty():
		if not entity._has_logged_sight:
			print("[Entity Senses] Player spotted in vision cone!")
			entity._has_logged_sight = true
		entity._last_known_position = entity._player.global_position
		entity._is_hunting = true
		entity._current_interest_level = 100.0
		return true
	
	entity._has_logged_sight = false
	return false


## Checks if the player is currently shining their flashlight on the Entity.
func is_player_spotting_entity() -> bool:
	if not entity._player or not is_instance_valid(entity._player):
		return false
	var cam = entity.get_viewport().get_camera_3d()
	if not cam:
		return false
	
	# Use the typed public API on the player controller instead of string-based
	# property access. is_flashlight_on() returns true only when the player has
	# picked up the flashlight AND it is currently switched on.
	var flashlight_on := false
	if entity._player.has_method("is_flashlight_on"):
		flashlight_on = entity._player.is_flashlight_on()
	
	if not flashlight_on:
		return false
	
	var cam_forward = -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	
	var to_entity = (entity.global_position - cam.global_position)
	to_entity.y = 0.0
	to_entity = to_entity.normalized()
	
	if cam_forward.dot(to_entity) <= 0.55:
		return false
	
	var space = entity.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(cam.global_position, entity.global_position + Vector3(0, 1, 0))
	query.exclude = [entity, entity._player]
	
	# ─── FLASHLIGHT RAYCAST COLLISION MASK ──────────────────────────────
	# The default collision mask scans ALL physics layers, which causes the
	# flashlight beam to hit window glass colliders (Layer 1: Cabin walls/
	# glass windows). This creates rapid on/off oscillation as the Entity
	# moves behind window frames, resetting the STANDOFF charge countdown
	# every frame and causing unfair CHARGE transitions through walls.
	#
	# FIX: Restrict the collision mask to ONLY scan for the Entity's own
	# body collision layer. The Entity is assumed to be on Layer 2 (Player
	# layer) or Layer 5 (Entity layer). We scan Layer 2 exclusively so the
	# flashlight tracing ray passes seamlessly through transparent glass
	# windows, window frames, trees, and rocks — only the Entity's capsule
	# collider can register a hit.
	#
	# Layer bit calculation:
	#   Layer 2 = 1 << (2-1) = 1 << 1 = 2
	query.collision_mask = 2
	
	var hit = space.intersect_ray(query)
	# If the ray hit something (tree, rock, etc.), line of sight is blocked.
	# The entity is excluded from the query, so any hit means an obstruction.
	if not hit.is_empty():
		return false
	
	return true


## Checks if the player's camera forward vector is looking within a 15-to-20
## degree cone of the target window position.
##
## This is the "RLOS" (Reverse Line of Sight) check used by the HARASS state
## to determine if the player is watching the Entity's harassment probe.
##
## Parameters:
##   window_pos: The world-space position of the window being harassed.
##
## Returns true if the player's camera is pointed within 20 degrees of the
## window position AND there is no obstruction between the camera and the window.
##
## Used by: _harass_state() in entity_ai.gd to evaluate player reaction.
func is_player_looking_at_window(window_pos: Vector3) -> bool:
	if not entity._player or not is_instance_valid(entity._player):
		return false
	var cam = entity.get_viewport().get_camera_3d()
	if not cam:
		return false
	
	# Calculate the angle between the camera's forward vector and the
	# direction from the camera to the window position.
	var cam_forward: Vector3 = -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	
	var to_window: Vector3 = window_pos - cam.global_position
	to_window.y = 0.0
	to_window = to_window.normalized()
	
	# 20-degree cone (cos(20°) ≈ 0.94)
	var dot_product: float = cam_forward.dot(to_window)
	if dot_product < 0.94:
		return false
	
	# Line-of-sight raycast: check if anything blocks the view to the window
	var space = entity.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(cam.global_position, window_pos)
	query.exclude = [entity, entity._player]
	
	var hit = space.intersect_ray(query)
	# If the ray hits nothing, the player has a clear view of the window.
	return hit.is_empty()
