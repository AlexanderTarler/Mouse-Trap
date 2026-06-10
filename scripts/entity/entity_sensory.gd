extends Node

## Entity Sensory System — Vision cone, flashlight detection, and audio hearing.
## Receives a reference to the parent entity_controller to read/write shared state.

var entity: CharacterBody3D = null

# ─── REUSABLE RAYCAST QUERY ──────────────────────────────────────────────────
## Single reusable PhysicsRayQueryParameters3D instance to avoid GC churn.
## Created once in setup(), then .from and .to are updated per check.
var _ray_query: PhysicsRayQueryParameters3D = null

# ─── CACHED CAMERA REFERENCE ────────────────────────────────────────────────
## Cached reference to the active 3D camera. Updated only when a camera switch
## event occurs, avoiding expensive get_viewport().get_camera_3d() polling.
var _cached_camera: Camera3D = null


func setup(parent: CharacterBody3D) -> void:
	entity = parent
	
	# Create reusable ray query once to avoid GC churn
	_ray_query = PhysicsRayQueryParameters3D.new()
	
	# Cache the active camera reference
	_cache_camera()
	
	# Listen for camera switch events to update the cached reference
	if entity.get_tree().current_scene:
		var cam_hud = entity.get_tree().current_scene.get_node_or_null("CameraHUD")
		if cam_hud and cam_hud.has_signal("camera_switched"):
			cam_hud.camera_switched.connect(_on_camera_switched)


## Caches the current active 3D camera.
func _cache_camera() -> void:
	if entity and entity.get_viewport():
		_cached_camera = entity.get_viewport().get_camera_3d()


## Called when the player switches cameras (e.g., photo camera mode).
## Updates the cached camera reference to avoid polling every frame.
func _on_camera_switched() -> void:
	_cache_camera()


## Checks if the Entity can see the player via vision cone + line-of-sight raycast.
func can_entity_see_player() -> bool:
	var player = entity.get_player()
	if not player or not is_instance_valid(player):
		return false
	
	# 1. Are they within the Field of View cone?
	var to_player = (player.global_position - entity.global_position).normalized()
	var forward = -entity.global_transform.basis.z
	
	if forward.dot(to_player) < cos(entity.get_vision_cone_angle()):
		return false
	
	# 2. Is there a wall/tree in the way? (Raycast check using reusable query)
	var space = entity.get_world_3d().direct_space_state
	var head_pos = entity.global_position + Vector3(0, 2.5, 0)
	var player_chest = player.global_position + Vector3(0, 1.0, 0)
	
	# Reuse the single _ray_query instance — just update from/to
	_ray_query.from = head_pos
	_ray_query.to = player_chest
	_ray_query.exclude = [entity, player]
	
	var hit = space.intersect_ray(_ray_query)
	# If the raycast hits nothing, or hits the player (which is excluded so it
	# won't be returned), then line-of-sight is clear.
	if hit.is_empty():
		if not entity.has_logged_sight():
			print("[Entity Senses] Player spotted in vision cone!")
			entity.set_has_logged_sight(true)
		entity.set_last_known_position(player.global_position)
		entity.set_is_hunting(true)
		entity.set_current_interest_level(100.0)
		return true
	
	entity.set_has_logged_sight(false)
	return false



## Checks if the player is currently shining their flashlight on the Entity.
func is_player_spotting_entity() -> bool:
	var player = entity.get_player()
	if not player or not is_instance_valid(player):
		return false
	
	# Use cached camera reference instead of polling get_viewport().get_camera_3d()
	var cam = _cached_camera
	if not cam:
		# Fallback: try to refresh the cache once
		_cache_camera()
		cam = _cached_camera
		if not cam:
			return false
	
	# Use the typed public API on the player controller instead of string-based
	# property access. is_flashlight_on() returns true only when the player has
	# picked up the flashlight AND it is currently switched on.
	var flashlight_on := false
	if player.has_method("is_flashlight_on"):
		flashlight_on = player.is_flashlight_on()
	
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
	
	# Reuse the single _ray_query instance — just update from/to and mask
	_ray_query.from = cam.global_position
	_ray_query.to = entity.global_position + Vector3(0, 1, 0)
	_ray_query.exclude = [entity, player]
	
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
	_ray_query.collision_mask = 2
	
	var hit = space.intersect_ray(_ray_query)
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
	var player = entity.get_player()
	if not player or not is_instance_valid(player):
		return false
	
	# Use cached camera reference instead of polling get_viewport().get_camera_3d()
	var cam = _cached_camera
	if not cam:
		_cache_camera()
		cam = _cached_camera
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
	
	# Reuse the single _ray_query instance — just update from/to
	_ray_query.from = cam.global_position
	_ray_query.to = window_pos
	_ray_query.exclude = [entity, player]
	
	var hit = space.intersect_ray(_ray_query)
	# If the ray hits nothing, the player has a clear view of the window.
	return hit.is_empty()

