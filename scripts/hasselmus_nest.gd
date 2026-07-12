extends StaticBody3D

## HasselmusNest - An interactable hazel mouse nest.
##
## The player presses E to document the nest (handled by InteractionManager
## via PhysicalGrab's quick-tap mechanism).
## Each nest can only be documented once. When all 3 nests are
## documented, the routine advances to Step 1 ("Upload nest data on
## the computer") and the eco-survey data becomes available for
## correlation at the FIELD_LOG.EXE terminal.

signal nest_documented(nest_id: String)

## Unique string ID for this nest (e.g., "nest_01", "nest_02", "nest_03")
@export var nest_id: String = "nest_01"

## Display name for this nest
@export var nest_name: String = "Hasselmus Nest"

## Notebook label used to look up lore in NotebookUI.NEST_LORE.
## Must match one of: "Nest Alpha", "Nest Beta", "Nest Gamma"
@export var nest_label: String = "Nest Alpha"

## Whether this nest has been documented
var is_documented: bool = false


func _ready() -> void:
	# Add to groups for easy finding
	add_to_group("hasselmus_nests")
	add_to_group("NestNodes")
	add_to_group("interactable_nests")


## Called when the player presses E on this nest.
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
	
	# Add documentation entry to the NotebookUI
	_add_to_notebook()
	
	# Show a confirmation message
	_show_documented_message()


func _add_to_notebook() -> void:
	# Find the NotebookUI via multiple methods for robust lookup
	var notebook: Node = null
	
	# Method 1: Try RoutineManager's cached reference (set in NotebookUI._connect_to_managers)
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and "_notebook_ui" in rm and rm._notebook_ui:
		notebook = rm._notebook_ui
	
	# Method 2: Try the dynamic NotebookUI via the player (NotebookLayer is instantiated at runtime)
	if not notebook:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			notebook = player.get_node_or_null("NotebookLayer/NotebookUI")
	
	# Method 3: Fall back to hardcoded paths
	if not notebook:
		notebook = get_node_or_null("/root/CottageHorror/Player/NotebookLayer/NotebookUI")
	if not notebook:
		notebook = get_node_or_null("/root/Main/Player/NotebookLayer/NotebookUI")
	
	if notebook and notebook.has_method("add_documentation"):
		notebook.add_documentation(nest_label)
		print("[HasselmusNest] Added '%s' to NotebookUI documentation." % nest_label)
	else:
		push_warning("[HasselmusNest] NotebookUI not found — documentation not recorded.")


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
