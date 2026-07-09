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

## NightManager clears the inventory during normal-mode setup. The inventory
## tutorial should only fire for items added AFTER that clear, not for the
## starting items that get immediately removed.
var _initialization_done: bool = false

const MAX_ITEMS: int = 10


## Adds an item to the inventory.
## Returns true if the item was added, false if the inventory is full.
func add_item(item) -> bool:
	
	if not item:
		
		return false
	if items.size() >= MAX_ITEMS:
		
		return false
	items.append(item)
	
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
	
	# ─── TUTORIAL: Inventory prompt on first real pickup ──────────────────
	# Skip during startup — NightManager clears the inventory right after
	# player_controller adds the starting items. Only trigger for items that
	# are picked up after that initialization clear. The guard is inside
	# _trigger_inventory_tutorial so deferred calls scheduled before the
	# clear still get silently dropped.
	call_deferred("_trigger_inventory_tutorial")
	
	return true


## Deferred inventory tutorial trigger — runs after TutorialManager is fully loaded.
## Guards against startup: NightManager clears the inventory right after adding
## starting items, so we only show the tutorial for player-picked-up items.
func _trigger_inventory_tutorial() -> void:
	if not _initialization_done:
		return
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("inventory")


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


## Marks the inventory as fully initialized. Called by NightManager after
## clearing the inventory in normal mode, so the inventory tutorial only
## fires for items the player actually picks up in-game.
func mark_initialized() -> void:
	_initialization_done = true

func clear() -> void:
	items.clear()
	_initialization_done = true
	inventory_changed.emit()
