extends Node

## Entity Sensory System — Vision cone (lighting-scaled), flashlight detection,
## and audio hearing. Receives a reference to the parent entity_controller to
## read/write shared state.
##
## VISION SCALING:
##   The Entity's vision range scales dynamically based on lighting conditions.
##   - If the player's flashlight is ON → full vision range (30m)
##   - If the environment is dark AND flashlight is OFF → reduced range (4m)
##   - If the environment is lit (room lights on) → moderate range (15m)
##
## ACOUSTIC DETECTION:
##   The Entity can hear player noises via hear_noise(). The player emits noise
##   based on movement state (sprint=20m, walk=10m, crouch=silent). If the Entity
##   is within the noise radius, it updates last_known_position instantly.
##
## ROOM-LEVEL TRACKING:
##   When noise is detected, the sensory system resolves the noise position to a
##   room name using RoomLightDetector.get_room_name_at(). This gives the Entity
##   room-level awareness without exact position — it knows which room the player
##   is in, but not the precise coordinates. The Entity then pathfinds to the
##   room's center node (global_position of the CabinRoom node) instead of the
##   player's exact coordinates.

var entity: CharacterBody3D = null

## The name of the room the Entity last heard the player in.
## Updated by hear_noise() when the Entity is in INDOOR_SEARCH state.
## Used by entity_ai.gd's _indoor_search_state() to pathfind toward the
## room center instead of the player's exact coordinates.
var last_heard_room: String = ""

# ─── VISION CONFIGURATION ───────────────────────────────────────────────────
## Maximum vision range when the player's flashlight is ON (full visibility).
const VISION_RANGE_FLASHLIGHT_ON: float = 30.0

## Maximum vision range when the environment is lit (room lights on).
const VISION_RANGE_LIT_ENVIRONMENT: float = 15.0

## Maximum vision range when it's dark and flashlight is OFF (severely limited).
const VISION_RANGE_DARK: float = 10.0

## The current effective vision range, recalculated each frame.
var _current_vision_range: float = VISION_RANGE_DARK

## ─── CONFIGURABLE VISION CONE ────────────────────────────────────────────────
## The Entity's peripheral vision angle in degrees. The Entity can see the player
## if the player is within this angle of the Entity's forward direction.
## Default: 45.0 degrees (90-degree total FOV, left + right).
## Lower values = narrower cone (easier to flank), higher = wider (harder to sneak).
@export var vision_angle_degrees: float = 45.0

## Pre-computed dot-product threshold for the vision cone.
## Calculated once from vision_angle_degrees to avoid calling cos() every frame.
## The Entity's forward vector dot to_player must be >= this value for the
## player to be within the vision cone.
var _vision_dot_threshold: float = cos(deg_to_rad(vision_angle_degrees))

# ─── REUSABLE RAYCAST QUERY ──────────────────────────────────────────────────
## Single reusable PhysicsRayQueryParameters3D instance to avoid GC churn.
## Created once in setup(), then .from and .to are updated per check.
var _ray_query: PhysicsRayQueryParameters3D = null

## Collision mask for line-of-sight (LOS) raycasts in is_point_visible().
## This MUST include all physics layers that can block vision — most importantly
## Layer 1 (Cabin walls, windows, doors). Without explicitly setting this mask
## before each LOS raycast, the reused _ray_query instance can leak a narrower
## mask from _is_player_spotting_entity_impl() (mask=18, bodies only), causing
## the Entity to see through cabin walls ("X-Ray Vision").
## 0xFFFFFFFF (all layers) is the safest default — walls/glass/doors all block vision.
const LOS_COLLISION_MASK: int = 0xFFFFFFFF

# ─── CACHED CAMERA REFERENCE ────────────────────────────────────────────────
## Cached reference to the active 3D camera. Updated only when a camera switch
## event occurs, avoiding expensive get_viewport().get_camera_3d() polling.
var _cached_camera: Camera3D = null

# ─── VISION UPDATE COOLDOWN ──────────────────────────────────────────────────
## Timer that prevents can_entity_see_player() from updating last_known_position
## or returning true for 1.0 seconds after a sighting. This creates a "blink"
## in the Entity's vision — the player has a 1-second window to crouch, hide
## behind a tree, and break the pathfinding target.
##
## Without this cooldown, the Entity updates last_known_position every single
## frame, making it impossible to lose the Entity once spotted. The 1-second
## gap is exactly what the player needs to break line-of-sight and escape.
var _vision_update_cooldown: float = 0.0

## Cooldown duration in seconds. After spotting the player, the Entity's vision
## "blinks" for this duration — it cannot re-acquire the player or update
## last_known_position via sight during this window.
const VISION_UPDATE_COOLDOWN_DURATION: float = 1.0

# ─── RAYCAST THROTTLING ──────────────────────────────────────────────────
## Frame counter for vision tick throttling. The Entity doesn't need to
## re-evaluate whether it can see the player every single physics frame.
## Running at ~20Hz (every 3rd frame) instead of 60Hz cuts vision raycast
## cost by 66% without meaningfully affecting gameplay.
var _vision_tick_counter: int = 0

## How many physics frames between vision checks.
const VISION_TICK_INTERVAL: int = 3

## Cached result of the last can_entity_see_player() check.
## Updated when the vision tick counter rolls over.
var _cached_can_see_player: bool = false

## Frame counter for player spotting check (is_player_spotting_entity).
## This is checked even less frequently — 10Hz instead of 60Hz.
var _spotting_tick_counter: int = 0

## How many physics frames between spotting checks.
const SPOTTING_TICK_INTERVAL: int = 6  # 10Hz at 60fps

## Cached result of the last is_player_spotting_entity() check.
var _cached_is_spotting: bool = false

## Accumulator for RoomLightDetector cache (seconds).
## Room lighting state doesn't change frame-to-frame — caching for 0.5s
## eliminates redundant queries in _calculate_vision_range().
var _room_light_cache_timer: float = 0.0

## Cached result of the Entity's own room light status.
var _cached_entity_in_lit_room: bool = false

## Cached result of the player's room light status.
var _cached_player_in_lit_room: bool = false

## How long to cache RoomLightDetector results (seconds).
## Extended from 0.5 to 1.0 — room lighting state changes rarely (only when
## the player flips a light switch), so there's no need to refresh every 0.5s.
## This reduces RoomLightDetector Area3D traversal overhead by 50%.
const ROOM_LIGHT_CACHE_DURATION: float = 1.0

# Frame-skip counter for staggering expensive RayCast3D LOS checks across frames.
var _sense_tick_counter: int = 0
## Cached result of the last full raycast LOS check, reused on skip frames.
var _cached_player_in_sight: bool = false


func _ready() -> void:
	# Cache the camera reference once the tree is fully loaded.
	# Using call_deferred ensures all nodes are initialized before we try
	# to find the Camera3D node on the player.
	_cache_camera.call_deferred()


func setup(parent: CharacterBody3D) -> void:

	entity = parent
	
	# Create reusable ray query once to avoid GC churn
	_ray_query = PhysicsRayQueryParameters3D.new()
	
	# Listen for camera switch events to update the cached reference
	if entity.get_tree().current_scene:
		var cam_hud = entity.get_tree().current_scene.get_node_or_null("CameraHUD")
		if cam_hud and cam_hud.has_signal("camera_switched"):
			cam_hud.camera_switched.connect(_on_camera_switched)


## Caches the current active 3D camera.
func _cache_camera() -> void:
	var player = entity.get_player() if entity else null
	if player:
		_cached_camera = player.get_node_or_null("CameraHolder/Camera3D") as Camera3D
	if not _cached_camera and entity and entity.get_viewport():
		_cached_camera = entity.get_viewport().get_camera_3d()


## Called when the player switches cameras (e.g., photo camera mode).
## Updates the cached camera reference to avoid polling every frame.
func _on_camera_switched() -> void:
	_cache_camera()


## ─── REUSABLE RAYCAST HELPER ────────────────────────────────────────────────
## Checks whether a target world-space position is visible from the Entity's
## head position (eyes at Y+2.5). Returns true if nothing blocks the line of
## sight between the Entity and the target.
##
## This replaces all manual space.intersect_ray() boilerplate with a single
## reusable helper that handles physics state setup, ray query reuse, and
## collision exclusion automatically.
##
## Parameters:
##   target_pos: The world-space position to check visibility for.
##   max_dist:   Maximum distance the Entity can see. If the target is beyond
##               this range, the function returns false without raycasting.
##
## Returns:
##   true if the target is within max_dist AND nothing blocks the line of sight.
func is_point_visible(target_pos: Vector3, max_dist: float) -> bool:
	if not entity:
		return false
	
	# Early-out distance check — skip raycasting if target is too far
	var dist_sq = entity.global_position.distance_squared_to(target_pos)
	if dist_sq > max_dist * max_dist:
		return false
	
	var space = entity.get_world_3d().direct_space_state
	var head_pos = entity.global_position + Vector3(0, 2.5, 0)
	
	# Reuse the single _ray_query instance — just update from/to/exclude/mask
	_ray_query.from = head_pos
	_ray_query.to = target_pos
	_ray_query.exclude = [entity]
	# CRITICAL FIX (H1): Explicitly reset the collision mask before each LOS raycast.
	# _is_player_spotting_entity_impl() sets _ray_query.collision_mask = 18 (bodies
	# only) for the flashlight beam check. Because _ray_query is a single reused
	# instance, that narrow mask leaks into this LOS check if we don't reset it,
	# causing the Entity to see through cabin walls ("X-Ray Vision").
	# LOS_COLLISION_MASK (0xFFFFFFFF) ensures walls/glass/doors all block vision.
	_ray_query.collision_mask = LOS_COLLISION_MASK
	
	var result = space.intersect_ray(_ray_query)
	# Returns true if nothing is blocking the view (result is empty)
	return result.is_empty()


## Calculates the effective vision range for the current frame based on
## lighting conditions and flashlight state.
##
## Rules:
##   - Player flashlight ON → full range (30m) — they're a beacon in the dark
##   - Player is in a lit room (room lights on) → moderate range (15m)
##   - Dark environment + flashlight OFF → severely reduced range (4m)
##   - Entity is in OBSERVE_FROM_TREELINE or WINDOW_PEEK → extended range (35m)
##     The Entity has a clear, unobstructed view of the cabin from the treeline
##     or through a window. The 4m dark range is for ground-level patrol, not
##     for when the Entity is specifically positioned to observe the cabin.
func _calculate_vision_range() -> float:
	var player = entity.get_player()
	if not player or not is_instance_valid(player):
		return VISION_RANGE_DARK
	
	# If the player's flashlight is ON, they are instantly visible at max range
	if player.has_method("is_flashlight_on") and player.is_flashlight_on():
		return VISION_RANGE_FLASHLIGHT_ON
	
	# ─── STATE-BASED VISION EXTENSION ──────────────────────────────────
	# When the Entity is in OBSERVE_FROM_TREELINE or WINDOW_PEEK, it has
	# a clear, unobstructed view of the cabin. The Entity is specifically
	# positioned to observe the cabin from the treeline or through a window.
	# In these states, the Entity can see much further than ground-level patrol.
	#
	# This fixes the "blind Entity" bug where the Entity couldn't see the
	# player through windows because the vision range was capped at 4m (dark)
	# or 15m (lit environment). The Entity needs at least 35m to see from
	# the treeline vantage points to the cabin windows.
	var entity_state = entity.get_state()
	var is_observing = (entity_state == EntityAI.State.OBSERVE_FROM_TREELINE or entity_state == EntityAI.State.WINDOW_PEEK)
	if is_observing:
		return 35.0  # Extended range for treeline/window observation
	
	# ─── ROOM LIGHT CACHE ───────────────────────────────────────────
	# RoomLightDetector.is_position_in_lit_room() traverses cabin interior
	# Area3D nodes. Room lighting doesn't change frame-to-frame, so we
	# cache results for 0.5s to avoid redundant traversal every frame.
	if _room_light_cache_timer <= 0.0:
		_cached_entity_in_lit_room = RoomLightDetector.is_position_in_lit_room(entity.global_position)
		_cached_player_in_lit_room = RoomLightDetector.is_position_in_lit_room(player.global_position)
		_room_light_cache_timer = ROOM_LIGHT_CACHE_DURATION
	
	# Check if the Entity is in a lit environment using cached result
	if _cached_entity_in_lit_room:
		return VISION_RANGE_LIT_ENVIRONMENT
	
	# Also check if the player is in a lit room — if so, the Entity can see
	# them from the darkness at moderate range (player silhouette against light)
	if _cached_player_in_lit_room:
		return VISION_RANGE_LIT_ENVIRONMENT
	
	# ─── CROUCH VISIBILITY MULTIPLIER ────────────────────────────────────
	# If the player is crouching, their profile is much smaller and they
	# blend into the darkness better. Shrink the effective vision range
	# to 20% of the calculated value (e.g., 30m → 6m, 15m → 3m, 4m → 0.8m).
	# This allows skilled players to actually sneak past the Entity in the
	# dark by staying low and moving slowly.
	if player.has_method("is_crouching") and player.is_crouching():
		return VISION_RANGE_DARK * 0.2
	
	# Dark environment + no flashlight → severely limited vision
	return VISION_RANGE_DARK


## ─── THROTTLED PUBLIC API ───────────────────────────────────────────────
## This is the public entry point called by entity_controller.gd, entity_ai.gd,
## entity_director.gd, and entity_confidence.gd — potentially multiple
## times per frame. The internal raycast is only performed every
## VISION_TICK_INTERVAL frames (~20Hz). Between ticks, the cached
## result is returned. This cuts vision raycast cost by 66%.
func can_entity_see_player() -> bool:
	# ─── VISION TICK THROTTLE ──────────────────────────────────────
	_vision_tick_counter += 1
	if _vision_tick_counter >= VISION_TICK_INTERVAL:
		_vision_tick_counter = 0
		_cached_can_see_player = _can_entity_see_player_impl()
	
	# ─── DECREMENT ROOM LIGHT CACHE TIMER ───────────────────────────
	# The cache is set by _calculate_vision_range() inside _impl().
	# Decrement it here so it counts down every frame regardless of
	# whether the vision check runs.
	if _room_light_cache_timer > 0.0:
		_room_light_cache_timer -= entity.get_physics_process_delta_time()
	
	return _cached_can_see_player


## Internal implementation of the vision check — the actual heavy lifting.
## Called only every VISION_TICK_INTERVAL frames by can_entity_see_player().
func _can_entity_see_player_impl() -> bool:
	var player = entity.get_player()
	if not player or not is_instance_valid(player):
		return false
	
	# ─── BREACH LOCK GUARD ──────────────────────────────────────────────
	# If the Entity is mid-breach (walking through the doorway), skip all
	# sensory updates. The Entity is committed to entering the cabin and
	# should NOT be distracted by seeing the player outside during Door
	# Phase A. This prevents the "Sensory Interference" bug where the
	# Entity sees the player outside, flips thinks_player_is_inside=false,
	# and aborts the INDOOR_SEARCH state.
	#
	# The is_breach_locked flag is set by entity_ai.gd's _indoor_search_state()
	# Door Phase A and cleared when the breach completes or the 5-second
	# timeout fires.
	if entity.is_breach_locked:
		return false
	
	# ─── 0. DECREMENT VISION UPDATE COOLDOWN ────────────────────────────
	# The cooldown counts down each frame regardless of whether the player
	# is visible. This ensures the 1-second "blink" always progresses.
	if _vision_update_cooldown > 0.0:
		_vision_update_cooldown -= entity.get_physics_process_delta_time()

	
	# ─── 1. CALCULATE EFFECTIVE VISION RANGE ─────────────────────────────
	# Recalculate vision range based on current lighting conditions.
	# This is cheap — just a few boolean checks and a RoomLightDetector query.
	_current_vision_range = _calculate_vision_range()
	
	# ─── 2. DISTANCE CHECK ───────────────────────────────────────────────
	# If the player is beyond the effective vision range, they are invisible
	# regardless of FOV or line-of-sight. This is the core stealth mechanic:
	# in the dark, the Entity can only see 4m ahead.
	var dist_to_player = entity.global_position.distance_to(player.global_position)
	if dist_to_player > _current_vision_range:
		entity.set_has_logged_sight(false)
		return false
	
	# ─── 3. FIELD OF VIEW CONE CHECK ─────────────────────────────────────
	var to_player = (player.global_position - entity.global_position).normalized()
	var forward = -entity.global_transform.basis.z
	
	# Use the pre-computed _vision_dot_threshold instead of calling cos() every frame.
	# _vision_dot_threshold is calculated once from vision_angle_degrees in the
	# variable declaration, avoiding redundant trig math on every vision check.
	if forward.dot(to_player) < _vision_dot_threshold:
		return false
	
	# ─── 4. LINE-OF-SIGHT RAYCAST ────────────────────────────────────────
	# Use the reusable is_point_visible() helper which handles physics state
	# setup, ray query reuse, and collision exclusion automatically.
	var player_chest = player.global_position + Vector3(0, 1.0, 0)
	if is_point_visible(player_chest, _current_vision_range):
		# ─── VISION UPDATE COOLDOWN CHECK ────────────────────────────────
		# If the cooldown is still active, the Entity's vision is "blinking"
		# — it cannot re-acquire the player or update last_known_position.
		# This gives the player a 1-second window to break line-of-sight.
		if _vision_update_cooldown > 0.0:
			return false
		
		if not entity.has_logged_sight():
			print("[Entity Senses] Player spotted in vision cone! (range=%.1fm, dist=%.1fm)" % [_current_vision_range, dist_to_player])
			entity.set_has_logged_sight(true)
		
		# ─── UPDATE MEMORY ───────────────────────────────────────────────
		# Store the player's current position as the last known position.
		# This is the ONLY place vision updates memory — acoustic detection
		# updates it separately via hear_noise().
		entity.set_last_known_position(player.global_position)
		entity.set_is_hunting(true)
		entity.set_current_interest_level(100.0)
		
		# ─── BELIEF SYSTEM: Sight-Based Player Location Deduction ──────
		# If the Entity sees the player indoors, reset the miss counter
		# (the player is confirmed inside). If the Entity sees the player
		# outdoors, immediately update the belief that the player escaped.
		var is_player_inside = RoomLightDetector.is_position_in_lit_room(player.global_position) or \
			RoomLightDetector.get_room_name_at(player.global_position) != "Outside"
		if is_player_inside:
			entity.reset_consecutive_vantage_misses()
		else:
			entity.set_thinks_player_is_inside(false)
			# ─── RESET MISS COUNTER ON OUTDOOR SIGHT ─────────────────────
			# When the Entity visually confirms the player is outside, reset
			# the consecutive miss counter to prevent stale misses from
			# accumulating. Without this, if the Entity had 2 misses before
			# spotting the player outside, those misses would persist and
			# the next vantage point cycle would trigger the 3-miss impatience
			# boost even though the Entity already knows the player escaped.
			entity.reset_consecutive_vantage_misses()
		
		# ─── TRIGGER VISION COOLDOWN ─────────────────────────────────────
		# After a successful sighting, trigger the 1-second "blink" so the
		# Entity cannot continuously track the player frame-by-frame.
		_vision_update_cooldown = VISION_UPDATE_COOLDOWN_DURATION
		
		return true
	
	entity.set_has_logged_sight(false)
	return false


## ─── THROTTLED SPOTTING CHECK ───────────────────────────────────────────────
## Public entry point for is_player_spotting_entity(). The internal raycast
## is only performed every SPOTTING_TICK_INTERVAL frames (~10Hz).
## Between ticks, the cached result is returned.
func is_player_spotting_entity() -> bool:
	# ─── SPOTTING TICK THROTTLE ────────────────────────────────────
	_spotting_tick_counter += 1
	if _spotting_tick_counter >= SPOTTING_TICK_INTERVAL:
		_spotting_tick_counter = 0
		_cached_is_spotting = _is_player_spotting_entity_impl()
	return _cached_is_spotting


## Internal implementation of the player spotting check.
## Called only every SPOTTING_TICK_INTERVAL frames.
func _is_player_spotting_entity_impl() -> bool:
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
	#   Layer 2 (Player body) + Layer 5 (Entity body)
	#   = (1 << 1) | (1 << 4) = 2 | 16 = 18
	_ray_query.collision_mask = 18
	
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
	
	# Use the pre-computed _vision_dot_threshold for the cone check.
	# With the default 45-degree vision angle, cos(45°) ≈ 0.707, which gives
	# a 90-degree total FOV (left + right). This is wider than the original
	# hardcoded 20-degree cone (cos(20°) ≈ 0.94), making the HARASS state
	# more responsive to the player's gaze.
	var dot_product: float = cam_forward.dot(to_window)
	if dot_product < _vision_dot_threshold:
		return false
	
	# Line-of-sight raycast: check if anything blocks the view to the window
	# Use the reusable is_point_visible() helper which handles physics state
	# setup, ray query reuse, and collision exclusion automatically.
	return is_point_visible(window_pos, 35.0)