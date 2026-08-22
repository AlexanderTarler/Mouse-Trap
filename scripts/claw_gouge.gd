extends StaticBody3D
class_name ClawGouge

## ClawGouge — An interactable set of gouge marks left on trees, abandoned
## logging equipment, or the tractor scrap heap (Post-Night 1).
##
## The player must use a ScrapingTool from their inventory to collect a
## physical material sample. Once collected, the gouge is consumed and the
## evidence is logged in EvidenceManager for the FIELD_LOG.EXE terminal.

signal gouge_collected()

## Display name for this gouge mark
@export var gouge_name: String = "Morphological Claw Gouge"

## Whether this gouge has already been collected
var is_collected: bool = false


func _ready() -> void:


	add_to_group("claw_gouges")


	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func interact() -> void:
	if is_collected:
		print("[ClawGouge] Already collected!")
		return
	
	# Check if the player has a ScrapingTool in their inventory
	var inv = get_node_or_null("/root/Inventory")
	if not inv:
		print("[ClawGouge] ERROR: Inventory not found!")
		return
	
	if not _has_item_named(inv, "Scraping Tool"):
		print("[ClawGouge] Player needs a Scraping Tool to collect this sample!")
		_show_message("You need a Scraping Tool to collect this gouge sample.")
		return
	
	# Consume the scraping tool
	_remove_item_named(inv, "Scraping Tool")
	
	# Mark as collected
	is_collected = true
	
	# Log the evidence
	var em = get_node_or_null("/root/EvidenceManager")
	if em:
		em.collect_evidence("claw_sample")
	
	gouge_collected.emit()
	
	print("[ClawGouge] Gouge sample collected!")
	_show_message("Gouge sample collected! Analyze it on the computer.")


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
		return "[E] %s - Already Collected" % gouge_name
	return "[E] Collect %s (requires ScrapingTool)" % gouge_name
