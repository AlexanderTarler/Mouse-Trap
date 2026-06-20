extends Node

## Inventory autoload singleton.
## Manages the player's items and provides methods for add/remove/use/drop.
##
## NOTE: Uses untyped Array instead of Array[ItemData] because autoloads
## are initialized before global script classes (class_name) are registered.
## Using typed arrays with class_name types at the class level would cause
## the autoload to silently fail to compile.

signal item_added(item)
signal item_removed(item)
signal inventory_changed

var items: Array = []

const MAX_ITEMS: int = 10


## Adds an item to the inventory.
## Returns true if the item was added, false if the inventory is full.
func add_item(item) -> bool:
	print("[Inventory] add_item called: ", item.item_name if item else "null")
	if not item:
		print("[Inventory] ERROR: item is null!")
		return false
	if items.size() >= MAX_ITEMS:
		print("[Inventory] Inventory is full! Cannot add: ", item.item_name if item else "unknown")
		return false
	items.append(item)
	print("[Inventory] Item added. Total items: ", items.size())
	item_added.emit(item)
	inventory_changed.emit()
	
	# ─── DAY 1 ONBOARDING: PHASE 1 — KEY PICKED UP ──────────────────────
	# If the player picked up the Cabin Key, notify RoutineManager.
	if item.item_name == "Cabin Key":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_key_picked_up"):
			rm.on_key_picked_up()
	
	# ─── DAY 1 ONBOARDING: PHASE 2 — FUSE PICKED UP ─────────────────────
	# If the player picked up a Fuse, notify RoutineManager.
	if item.item_name == "Fuse":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_fuse_picked_up"):
			rm.on_fuse_picked_up()
	
	# ─── DAY 1 ONBOARDING: PHASE 2 — FUEL CAN PICKED UP ─────────────────
	# If the player picked up a Fuel Can, notify RoutineManager.
	if item.item_name == "Fuel Can":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_fuel_can_picked_up"):
			rm.on_fuel_can_picked_up()
	
	# ─── DAY 1 ONBOARDING: PHASE 2B — PLANK PICKED UP ───────────────────
	# If the player picked up a Wooden Plank, notify RoutineManager.
	if item.item_name == "Wooden Plank":
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_plank_picked_up"):
			rm.on_plank_picked_up()
	
	return true



func remove_item(item) -> void:
	var idx = items.find(item)
	if idx >= 0:
		items.remove_at(idx)
		item_removed.emit(item)
		inventory_changed.emit()


func remove_at(index: int) -> void:
	if index >= 0 and index < items.size():
		var item = items[index]
		items.remove_at(index)
		item_removed.emit(item)
		inventory_changed.emit()


func has_item(item) -> bool:
	return items.find(item) >= 0


func has_item_of_type(type) -> bool:
	for item in items:
		if item != null and item.item_type == type:
			return true
	return false


func get_items_of_type(type) -> Array:
	var result: Array = []
	for item in items:
		if item != null and item.item_type == type:
			result.append(item)
	return result


func get_item_count() -> int:
	return items.size()


func clear() -> void:
	items.clear()
	inventory_changed.emit()
