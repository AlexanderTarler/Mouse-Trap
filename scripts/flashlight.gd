extends SpotLight3D

## Flashlight with battery drain system.
## Attached to the SpotLight3D child of Camera3D.

signal battery_changed(level: float)
signal flashlight_turned_off
signal flashlight_turned_on

@export var max_battery: float = 100.0
@export var drain_rate: float = 1.0  # per second when on (50% slower)
@export var low_battery_threshold: float = 15.0

var battery_level: float = 100.0
var is_on: bool = false

# Flicker state
var _base_energy: float = 1.0
var _flicker_timer: float = 0.0
var _is_flickering: bool = false


func _ready() -> void:
	battery_level = max_battery
	visible = is_on
	_base_energy = light_energy


func _process(delta: float) -> void:
	if is_on and battery_level > 0.0:
		battery_level -= drain_rate * delta
		battery_level = maxf(battery_level, 0.0)
		battery_changed.emit(battery_level)
		
		if battery_level <= 0.0:
			_turn_off()
			return
		
		# Handle low-battery flicker
		if battery_level <= low_battery_threshold:
			_update_flicker(delta)
		elif _is_flickering:
			# Stop flickering if battery recovered above threshold
			_is_flickering = false
			light_energy = _base_energy


func _update_flicker(delta: float) -> void:
	_is_flickering = true
	_flicker_timer -= delta
	
	if _flicker_timer <= 0.0:
		# Random flicker interval (0.05 to 0.3 seconds)
		_flicker_timer = randf_range(0.05, 0.3)
		
		# Random energy between 0.1 and base_energy
		# Lower battery = more severe flicker (lower minimum)
		var battery_ratio = battery_level / low_battery_threshold
		var min_energy = 0.1 * (1.0 - battery_ratio * 0.7)  # 0.1 to ~0.03
		light_energy = randf_range(min_energy, _base_energy)


func toggle() -> void:
	if battery_level <= 0.0:
		return  # Can't turn on if battery is dead
	if is_on:
		_turn_off()
	else:
		_turn_on()


func _turn_on() -> void:
	is_on = true
	visible = true
	light_energy = _base_energy
	_is_flickering = false
	flashlight_turned_on.emit()


func _turn_off() -> void:
	is_on = false
	visible = false
	_is_flickering = false
	flashlight_turned_off.emit()


func refill(amount: float) -> void:
	battery_level = minf(battery_level + amount, max_battery)
	battery_changed.emit(battery_level)
	# If battery was dead and now has charge, the player can toggle it back on
	if battery_level > 0.0 and not is_on:
		pass  # Don't auto-turn on, let player decide


## Alias for refill, called by inventory when using a battery item.
func refill_battery(amount: float) -> void:
	refill(amount)


func set_battery_level(level: float) -> void:
	battery_level = clampf(level, 0.0, max_battery)
	battery_changed.emit(battery_level)


func get_battery_percent() -> float:
	return (battery_level / max_battery) * 100.0


func is_low_battery() -> bool:
	return battery_level <= low_battery_threshold
