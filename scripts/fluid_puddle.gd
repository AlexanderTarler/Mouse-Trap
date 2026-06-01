extends StaticBody3D
class_name FluidPuddle

## FluidPuddle — An interactable puddle of Corrosive Black Fluid left behind
## when the Entity shatters a window glass pane (Post-Night 1).
##
## The player must use a SwabKit from their inventory to collect a chemical
## sample. Once collected, the puddle is consumed and the evidence is logged
## in EvidenceManager for the FIELD_LOG.EXE terminal.

signal fluid_collected()

## Display name for this puddle
@export var puddle_name: String = "Corrosive Black Fluid"

## Whether this puddle has already been collected
var is_collected: bool = false


func _ready() -> void:
	add_to_group("fluid_puddles")


func interact() -> void:
	if is_collected:
		print("[FluidPuddle] Already collected!")
		return
	
	# Check if the player has a SwabKit in their inventory
	var inv = get_node_or_null("/root/Inventory")
	if not inv:
		print("[FluidPuddle] ERROR: Inventory not found!")
		return
	
	if not _has_item_named(inv, "Swab Kit"):
		print("[FluidPuddle] Player needs a Swab Kit to collect this sample!")
		_show_message("You need a Swab Kit to collect this fluid sample.")
		return
	
	# Consume the swab kit
	_remove_item_named(inv, "Swab Kit")
	
	# Mark as collected
	is_collected = true
	
	# Log the evidence
	var em = get_node_or_null("/root/EvidenceManager")
	if em:
		em.collect_evidence("fluid_sample")
	
	fluid_collected.emit()
	
	print("[FluidPuddle] Fluid sample collected!")
	_show_message("Fluid sample collected! Analyze it on the computer.")


## Checks if the inventory contains an item with the given name.
func _has_item_named(inv: Node, name: String) -> bool:
	for item in inv.items:
		if item != null and item.item_name == name:
			return true
	return false


## Removes the first item with the given name from the inventory.
func _remove_item_named(inv: Node, name: String) -> void:
	for i in range(inv.items.size()):
		var item = inv.items[i]
		if item != null and item.item_name == name:
			inv.remove_at(i)
			return


func _show_message(text: String) -> void:
	var hud = get_node_or_null("/root/CottageHorror/HUD")
	if not hud:
		hud = get_node_or_null("/root/Main/HUD")
	if hud and hud.has_method("_show_event"):
		hud._show_event(text)


func get_interact_text() -> String:
	if is_collected:
		return "[E] %s - Already Collected" % puddle_name
	return "[E] Collect %s (requires SwabKit)" % puddle_name
