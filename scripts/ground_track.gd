extends StaticBody3D
class_name GroundTrack

## GroundTrack — An interactable set of bipedal compressions stamped into
## the mud or broken branches along the treeline (Post-Night 1).
##
## The player must use a SpatialScanner from their inventory to scan the
## tracks. Once scanned, the track is consumed and the evidence is logged
## in EvidenceManager for the FIELD_LOG.EXE terminal.

signal track_scanned()

## Display name for this track
@export var track_name: String = "Bipedal Impact Trail"

## Whether this track has already been scanned
var is_scanned: bool = false


func _ready() -> void:
	add_to_group("ground_tracks")


func interact() -> void:
	if is_scanned:
		print("[GroundTrack] Already scanned!")
		return
	
	# Check if the player has a SpatialScanner in their inventory
	var inv = get_node_or_null("/root/Inventory")
	if not inv:
		print("[GroundTrack] ERROR: Inventory not found!")
		return
	
	if not _has_item_named(inv, "Spatial Scanner"):
		print("[GroundTrack] Player needs a Spatial Scanner to scan these tracks!")
		_show_message("You need a Spatial Scanner to analyze these tracks.")
		return
	
	# Consume the spatial scanner
	_remove_item_named(inv, "Spatial Scanner")
	
	# Mark as scanned
	is_scanned = true
	
	# Log the evidence
	var em = get_node_or_null("/root/EvidenceManager")
	if em:
		em.collect_evidence("track_scan")
	
	track_scanned.emit()
	
	print("[GroundTrack] Track scan complete!")
	_show_message("Track scan complete! Analyze it on the computer.")


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
	if is_scanned:
		return "[E] %s - Already Scanned" % track_name
	return "[E] Scan %s (requires SpatialScanner)" % track_name
