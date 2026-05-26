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
	
	var flashlight_on := false
	if entity._player.has_method("_toggle_flashlight"):
		var fl = entity._player.get("_flashlight")
		if fl and is_instance_valid(fl):
			flashlight_on = fl.is_on if "is_on" in fl else fl.visible
	
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
	var hit = space.intersect_ray(query)
	# If the ray hit something (wall, tree, etc.), line of sight is blocked.
	# The entity is excluded from the query, so any hit means an obstruction.
	if not hit.is_empty():
		return false
	
	return true


