extends Node3D
class_name PerceptionManager

@export var intensity_rise_rate: float = 0.3
@export var intensity_fall_rate: float = 0.1
@export var fov_cos_threshold: float = 0.5
@export var max_detection_distance: float = 40.0

# Frame-skip throttling — perception (watched intensity) only needs ~10Hz.
# The _process() loop runs every rendering frame (~60Hz), but we only
# perform the expensive occlusion raycast every 6 frames (~10Hz).
var _perception_tick_counter: int = 0
const PERCEPTION_TICK_INTERVAL: int = 6

# Cached result of the last occlusion raycast, reused on skip frames.
var _cached_in_fov: bool = false
var _cached_is_occluded: bool = true
var _cached_dist_to_entity: float = 99999.0

@onready var _camera: Camera3D = get_viewport().get_camera_3d()
@onready var _raycast: RayCast3D = $OcclusionRayCast

var _entity: Node3D = null
var watched_intensity: float = 0.0
var is_blind: bool = false

signal watched_intensity_changed(intensity: float)
signal blindness_started()
signal blindness_ended()


## Found by its group (not by a path in the level).
func _enter_tree() -> void:
	add_to_group("perception_manager")


func _ready() -> void:
	if _raycast:
		_raycast.hit_from_inside = true
		_raycast.collide_with_areas = false
		_raycast.collide_with_bodies = true
		_raycast.exclude_parent = true
		# Scan for Entity body (Layer 5) — default mask only hits Layer 1
		_raycast.collision_mask = 18  # Layer 2 (Player) | Layer 5 (Entity)
	
	_find_entity()


func _find_entity() -> void:
	var entities = get_tree().get_nodes_in_group("entity")
	if entities.size() > 0:
		_entity = entities[0] as Node3D
		print("PerceptionManager: Found entity: ", _entity.name)


func _process(delta: float) -> void:
	if not _entity or not _camera:
		return
	
	# ─── THROTTLED PERCEPTION CHECK (~10Hz) ───────────────────────────────
	# The expensive occlusion raycast only runs every PERCEPTION_TICK_INTERVAL
	# frames. Between ticks, the cached FOV/occlusion result is reused.
	_perception_tick_counter += 1
	if _perception_tick_counter >= PERCEPTION_TICK_INTERVAL:
		_perception_tick_counter = 0
		_perform_perception_check()
	
	# ─── INTENSITY UPDATE (runs every frame regardless of tick) ───────────
	# Uses the cached perception result to smoothly fade intensity.
	if _cached_in_fov and not _cached_is_occluded:
		_increase_intensity(delta)
	else:
		_decrease_intensity(delta)
	
	# ─── BLINDNESS STATE MACHINE ─────────────────────────────────────────
	if watched_intensity >= 1.0 and not is_blind:
		_trigger_blindness()
	elif watched_intensity < 1.0 and is_blind:
		# Release blindness when the player looks away (intensity drops below 1.0)
		is_blind = false
		blindness_ended.emit()


## Performs the full FOV + occlusion raycast check.
## Called only every PERCEPTION_TICK_INTERVAL frames by _process().
func _perform_perception_check() -> void:
	if _entity.has_method("is_active") and not _entity.is_active():
		_cached_in_fov = false
		_cached_is_occluded = true
		_cached_dist_to_entity = 99999.0
		return
	
	# ─── OVERCHARGE GATE ─────────────────────────────────────────
	# While the player holds the OVERCHARGE flashlight beam on the Entity,
	# suppress the "watched" distortion / blindness effects. Overcharge is
	# the player's strongest defensive mechanic — it should NOT make them
	# MORE vulnerable via perception-based hallucinations. The watched
	# intensity fades naturally while the beam is held.
	if _entity.get("is_overcharged") == true:
		_cached_in_fov = false
		_cached_is_occluded = true
		_cached_dist_to_entity = 99999.0
		return
	
	var cam_pos = _camera.global_position
	var cam_forward = -_camera.global_transform.basis.z
	var entity_pos = _entity.global_position
	var dir_to_entity = (entity_pos - cam_pos).normalized()
	_cached_dist_to_entity = cam_pos.distance_to(entity_pos)
	
	if _cached_dist_to_entity > max_detection_distance:
		_cached_in_fov = false
		_cached_is_occluded = true
		return
	
	var dot = cam_forward.dot(dir_to_entity)
	_cached_in_fov = dot > fov_cos_threshold
	
	_cached_is_occluded = true
	if _cached_in_fov:
		_cached_is_occluded = _check_occlusion(cam_pos, entity_pos)


func _check_occlusion(from: Vector3, to: Vector3) -> bool:
	if not _raycast:
		return true
	
	_raycast.global_position = from
	_raycast.target_position = to - from
	_raycast.force_raycast_update()
	
	if _raycast.is_colliding():
		var collider = _raycast.get_collider()
		if collider == _entity:
			return false
		return true
	
	return false


func _increase_intensity(delta: float) -> void:
	var old = watched_intensity
	watched_intensity = min(1.0, watched_intensity + intensity_rise_rate * delta)
	if old != watched_intensity:
		watched_intensity_changed.emit(watched_intensity)


func _decrease_intensity(delta: float) -> void:
	var old = watched_intensity
	watched_intensity = max(0.0, watched_intensity - intensity_fall_rate * delta)
	if old != watched_intensity:
		watched_intensity_changed.emit(watched_intensity)


func _trigger_blindness() -> void:
	is_blind = true
	blindness_started.emit()
	print("PerceptionManager: Blindness triggered!")
	# NOTE: watched_intensity is NOT reset to 0.0 here, so the shader
	# distortion effects and whispers audio continue while the player
	# stares. Blindness is continuous until the player looks away.
