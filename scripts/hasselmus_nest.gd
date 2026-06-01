extends StaticBody3D

## HasselmusNest - An interactable hazel mouse nest that requires exactly
## ONE unique photograph using the Floppy Disk Camera (PhotoCamera).
##
## The player must equip the camera, hold RMB to enter viewfinder mode,
## aim at the nest, and hold LMB for 2.0 seconds to focus. When focus
## completes, the camera snaps a photo and writes the data to the virtual
## floppy disk.
##
## Each nest can only be photographed once. When all 3 nests are
## photographed, the routine advances to Step 1 ("Upload nest data on
## the computer") and the eco-survey data becomes available for
## correlation at the FIELD_LOG.EXE terminal.

signal nest_documented(nest_id: String)

## Unique string ID for this nest (e.g., "nest_01", "nest_02", "nest_03")
@export var nest_id: String = "nest_01"

## Display name for this nest
@export var nest_name: String = "Hasselmus Nest"

## Whether this nest has been photographed (the only valid documentation method)
var is_photographed: bool = false

## Whether this nest has been documented via the old direct-interact method
## (kept for backward compatibility)
var is_documented: bool = false


func _ready() -> void:
	# Add to groups for easy finding
	add_to_group("hasselmus_nests")
	add_to_group("NestNodes")
	add_to_group("photographable_nests")


## Called by PhotoCamera when the player takes a photo of this nest.
## Returns true if the photo was successful (first time), false if already done.
func photograph() -> bool:
	if is_photographed:
		print("[HasselmusNest] Nest ", nest_id, " already photographed!")
		return false
	
	# Mark as photographed
	is_photographed = true
	is_documented = true
	
	print("[HasselmusNest] Nest ", nest_id, " photographed!")
	
	# Emit signal
	nest_documented.emit(nest_id)
	
	# Notify RoutineManager
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("document_nest"):
		rm.document_nest(nest_id)
	
	# Show a confirmation message
	_show_documented_message()
	
	return true


## Legacy direct-interact method (E key).
## Kept for backward compatibility — still works but the preferred method
## is now the camera photograph.
func interact() -> void:
	if is_documented:
		print("[HasselmusNest] Nest ", nest_id, " already documented!")
		return
	
	# Mark as documented
	is_documented = true
	is_photographed = true
	
	print("[HasselmusNest] Nest ", nest_id, " documented via direct interact!")
	
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
		hud._show_event("Nest %s documented! (%d/3)" % [nest_id, count])


func get_interact_text() -> String:
	if is_documented:
		return "[E] Nest %s - Already Documented" % nest_name
	return "[E] Document %s" % nest_name
