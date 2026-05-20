extends Node3D
class_name PerceptionManager

@export var intensity_rise_rate: float = 0.3
@export var intensity_fall_rate: float = 0.1
@export var fov_cos_threshold: float = 0.5
@export var max_detection_distance: float = 40.0
@export var blindness_duration: float = 2.0

@onready var _camera: Camera3D = get_viewport().get_camera_3d()
@onready var _raycast: RayCast3D = $OcclusionRayCast

var _entity: Node3D = null
var watched_intensity: float = 0.0
var is_blind: bool = false

signal watched_intensity_changed(intensity: float)
signal blindness_started()
signal blindness_ended()


func _ready() -> void:
	if _raycast:
		_raycast.hit_from_inside = true
		_raycast.collide_with_areas = false
		_raycast.collide_with_bodies = true
		_raycast.exclude_parent = true
	
	_find_entity()


func _find_entity() -> void:
	var entities = get_tree().get_nodes_in_group("entity")
	if entities.size() > 0:
		_entity = entities[0] as Node3D
		print("PerceptionManager: Found entity: ", _entity.name)


func _process(delta: float) -> void:
	if not _entity or not _camera:
		return
	
	var cam_pos = _camera.global_position
	var cam_forward = -_camera.global_transform.basis.z
	var entity_pos = _entity.global_position
	var dir_to_entity = (entity_pos - cam_pos).normalized()
	var dist_to_entity = cam_pos.distance_to(entity_pos)
	
	if dist_to_entity > max_detection_distance:
		_decrease_intensity(delta)
		return
	
	var dot = cam_forward.dot(dir_to_entity)
	var in_fov = dot > fov_cos_threshold
	
	var is_occluded = true
	if in_fov:
		is_occluded = _check_occlusion(cam_pos, entity_pos)
	
	if in_fov and not is_occluded:
		_increase_intensity(delta)
	else:
		_decrease_intensity(delta)
	
	if watched_intensity >= 1.0 and not is_blind:
		_trigger_blindness()


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
	watched_intensity = 0.0
	blindness_started.emit()
	print("PerceptionManager: Blindness triggered!")
	
	await get_tree().create_timer(blindness_duration).timeout
	is_blind = false
	blindness_ended.emit()
	print("PerceptionManager: Blindness ended.")
