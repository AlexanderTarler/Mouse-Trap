extends Node3D

## Lamp flickering effect for the horror game.
## Makes the lamp flicker based on NightManager events and entity proximity.

@export var light_node_path: NodePath = NodePath("OmniLight3D")
@export var normal_energy: float = 3.0
@export var flicker_min_energy: float = 0.5
@export var flicker_max_energy: float = 4.0
@export var flicker_duration: float = 0.1

var _light: OmniLight3D = null
var _is_flickering: bool = false
var _original_energy: float = 3.0
var _flicker_timer: float = 0.0
var _entity_proximity: float = 0.0

func _ready() -> void:
	if light_node_path:
		_light = get_node(light_node_path) as OmniLight3D
	if _light:
		_original_energy = _light.light_energy
	
	_connect_signals()

func _connect_signals() -> void:
	if Engine.has_singleton("NightManager"):
		var nm = Engine.get_singleton("NightManager")
		nm.horror_event.connect(_on_horror_event)
		nm.night_started.connect(_on_night_started)
	
	# Connect to entity manager if it exists
	var em = get_node_or_null("/root/EntityManager")
	if em:
		em.player_watched.connect(_on_player_watched)

func _on_night_started(night: int) -> void:
	# Lamp gets dimmer each night
	if _light:
		_original_energy = max(1.0, normal_energy - night * 0.3)
		_light.light_energy = _original_energy

func _on_horror_event(event_name: String) -> void:
	match event_name:
		"lights_flicker":
			_start_flicker(3.0)
		"entity_appears":
			_start_flicker(1.0)
		"entity_charge":
			_start_flicker(2.0)
		"final_confrontation":
			_start_flicker(5.0)
			_original_energy = 0.5  # Almost out

func _on_player_watched(intensity: float) -> void:
	_entity_proximity = intensity
	# Subtle flicker when entity is near
	if intensity > 0.7 and randf() < 0.1:
		_single_flicker()

func _process(delta: float) -> void:
	if not _is_flickering or not _light:
		return
	
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_stop_flicker()
		return
	
	# Random flicker
	_light.light_energy = _original_energy * randf_range(0.2, 1.5)

func _start_flicker(duration: float) -> void:
	if not _light:
		return
	_is_flickering = true
	_flicker_timer = duration

func _stop_flicker() -> void:
	if not _light:
		return
	_is_flickering = false
	_light.light_energy = _original_energy

func _single_flicker() -> void:
	if not _light or _is_flickering:
		return
	_light.light_energy = flicker_min_energy
	await get_tree().create_timer(flicker_duration).timeout
	if _light and not _is_flickering:
		_light.light_energy = _original_energy
