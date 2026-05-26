extends Node3D
class_name CabinLight

@export var light_name: String = "Room Light"
@export var start_on: bool = false
@export var energy_drain_rate: float = 1.0 # Fuel units consumed per second

@onready var light_node: Light3D = $OmniLight3D
@onready var mesh_on: Node3D = $LightMeshOn if has_node("LightMeshOn") else null
@onready var mesh_off: Node3D = $LightMeshOff if has_node("LightMeshOff") else null

var is_switched_on: bool = false

func _ready() -> void:
	add_to_group("CabinLights")
	
	is_switched_on = start_on
	_update_light_state()
	
	# Connect to the central power grid if it exists
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_signal("generator_state_changed"):
		nm.generator_state_changed.connect(_on_generator_state_changed)

func toggle_light() -> void:
	is_switched_on = !is_switched_on
	
	if not is_generator_running():
		print("[%s] Click... Switch toggled mechanically, but house has no power." % light_name)
	else:
		print("[%s] Light state changed to: %s" % [light_name, "ON" if is_switched_on else "OFF"])
		
	_update_light_state()
	
	# Force power grid load calculation update
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()

func _update_light_state() -> void:
	var power_available = is_generator_running()
	var dynamic_on = is_switched_on and power_available
	
	# 1. Handle the physical light emitter casting shadows
	if light_node:
		light_node.visible = dynamic_on
		
	# 2. Swap mesh visibility based on power and switch state
	if mesh_on and mesh_off:
		mesh_on.visible = dynamic_on
		mesh_off.visible = !dynamic_on

func is_generator_running() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "is_generator_on" in nm:
		return nm.is_generator_on
	return true # Fallback so lights function normally during testing

func _on_generator_state_changed(_is_running: bool) -> void:
	_update_light_state()
