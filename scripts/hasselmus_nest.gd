extends StaticBody3D

## HasselmusNest - An interactable nest that tracks documentation progress.
## When the player interacts with a nest, it calls RoutineManager.document_nest().
## When all 3 nests are documented, the routine advances to Step 1
## ("Upload nest data on the computer").

signal nest_documented(nest_id: int)

## Unique ID for this nest (1, 2, or 3)
@export var nest_id: int = 1

## Display name for this nest
@export var nest_name: String = "Hasselmus Nest"

## Whether this nest has already been documented
var is_documented: bool = false


func _ready() -> void:
	# Add to a group for easy finding
	add_to_group("hasselmus_nests")


func interact() -> void:
	if is_documented:
		print("[HasselmusNest] Nest ", nest_id, " already documented!")
		return
	
	# Mark as documented
	is_documented = true
	
	print("[HasselmusNest] Nest ", nest_id, " documented!")
	
	# Emit signal
	nest_documented.emit(nest_id)
	
	# Notify RoutineManager
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("document_nest"):
		rm.document_nest(nest_id)
	
	# Show a confirmation message
	_show_documented_message()


func _show_documented_message() -> void:
	# Find the HUD to show a message
	var hud = get_node_or_null("/root/CottageHorror/HUD")
	if not hud:
		hud = get_node_or_null("/root/Main/HUD")
	
	if hud and hud.has_method("_show_event"):
		var rm = get_node_or_null("/root/RoutineManager")
		var count = rm.nests_documented if rm else 0
		hud._show_event("Nest %d documented! (%d/3)" % [nest_id, count])


func get_interact_text() -> String:
	if is_documented:
		return "[E] Nest %s - Already Documented" % nest_name
	return "[E] Document %s" % nest_name
