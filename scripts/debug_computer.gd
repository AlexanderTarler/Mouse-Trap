extends StaticBody3D

## Debug Computer — Interactive debug console for manipulating game state.
## When the player looks at this and taps E, it opens a CanvasLayer UI overlay.
##
## Interaction standard: The raycast in interaction_manager.gd hits the
## CollisionShape3D child of this StaticBody3D, then walks up the parent
## chain to find a node with interact(). PhysicalGrab calls interact()
## with no arguments (quick tap E).

@export var debug_console_scene: PackedScene = preload("res://scenes/debug_console.tscn")

var _console_instance: CanvasLayer = null
var _is_open: bool = false


func _ready() -> void:


	add_to_group("debug_computer")


	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func get_interact_text() -> String:
	return "[E] Open Debug Console"


func interact() -> void:
	if _is_open:
		return
	
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	# Safety check: don't open if already in a menu
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _is_open == false:
		# Another UI might be open — check if there's an inventory open
		var inv_ui = get_tree().get_first_node_in_group("inventory_ui")
		if inv_ui and inv_ui.get("_is_open"):
			return
	
	_open_console(player)


func _open_console(player: Node) -> void:
	if _console_instance == null:
		_console_instance = debug_console_scene.instantiate()
		get_tree().current_scene.add_child(_console_instance)
	
	_console_instance.open(player)
	_is_open = true


func close_console() -> void:
	if _console_instance:
		_console_instance.close()
	_is_open = false
