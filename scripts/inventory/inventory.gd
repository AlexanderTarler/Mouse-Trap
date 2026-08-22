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

## ─── TASK 3: CHECKPOINT SNAPSHOT ──────────────────────────────────────
## Deep-duplicated snapshot of `items` taken at the start of each night
## cycle (see NightManager.start_night() → Inventory.save_checkpoint()).
## When the player dies and restarts from the checkpoint, NightManager
## calls Inventory.reset_to_checkpoint() to restore the exact item state,
## reverting any consumed items (e.g. the Cable Spool connected to the
## generator) so nothing is permanently lost.
## Snapshots are deep-duplicates of each ItemData resource so restoring
## produces fully independent instances (mutating one never corrupts the
## other or the original .tres).
var _checkpoint_items: Array = []

const MAX_ITEMS: int = 10


## Adds an item to the inventory.
## Returns true if the item was added, false if the inventory is full.
func add_item(item) -> bool:
	
	if not item:
		
		return false
	if items.size() >= MAX_ITEMS:
		
		return false
	
	# ─── TASK 1: FUEL CAN INSTANCE ISOLATION ──────────────────────────
	# Fuel cans carry a per-instance fuel_amount that drains proportionally
	# with the generator (2 can-units per 1 generator fuel unit). The shared
	# fuel_can_resource.tres must NEVER be mutated in place, or every can in
	# the session would drain together. Duplicate the resource when a fuel
	# can enters the inventory so each can is an independent instance.
	# Non-fuel items pass through untouched (fuel_amount default is ignored).
	if item.item_name == "Fuel Can" and item is Resource:
		item = item.duplicate(false)
	
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
	
	# ─── DAY 3+ CAR PART COLLECTED ─────────────────────────────────────
	# If the player picked up a car part (item_type == 7 CAR_PART),
	# notify RoutineManager so the notebook can show the "collected" state.
	if item.item_type == 7:
		var rm_car = get_node_or_null("/root/RoutineManager")
		if rm_car and rm_car.has_method("on_car_part_collected"):
			rm_car.on_car_part_collected(item.item_name)
	
	# ─── DAY 3+ SIDE-TRACK ITEMS ────────────────────────────────────────
	# Notify RoutineManager about side-track quest item pickups.
	var rm_side = get_node_or_null("/root/RoutineManager")
	if rm_side:
		if item.item_name == "Arvid_Note_2" and rm_side.has_method("on_arvid_note_2_found"):
			rm_side.on_arvid_note_2_found()
		if item.item_name == "Portable Light" and rm_side.has_method("on_portable_light_found"):
			rm_side.on_portable_light_found()
		if item.item_name == "Cable Spool" and rm_side.has_method("on_cable_spool_found"):
			rm_side.on_cable_spool_found()
		if item.item_name == "Fuel Can" and rm_side.has_method("on_fuel_can_found"):
			rm_side.on_fuel_can_found()
	
	# ─── TUTORIAL: Inventory prompt on first real pickup ──────────────────
	# Skip during startup — NightManager clears the inventory right after
	# player_controller adds the starting items. Only trigger for items that
	# are picked up after that initialization clear. The guard is inside
	# _trigger_inventory_tutorial so deferred calls scheduled before the
	# clear still get silently dropped.
	call_deferred("_trigger_inventory_tutorial")
	
	# ─── TASK: INVENTORY ADD SOUND ──────────────────────────────────────
	# Play add_to_inventory.ogg for REAL player pickups. Guarded by
	# _initialization_done so the temporary starting items (which
	# NightManager immediately clears at boot) do NOT trigger the sound.
	if _initialization_done:
		call_deferred("_play_add_to_inventory_sound")
	
	return true


## Plays the add_to_inventory.ogg sound via a transient AudioStreamPlayer.
## The player is auto-freed when the sound finishes.
func _play_add_to_inventory_sound() -> void:
	var stream := load("res://assets/audio/player/add_to_inventory.ogg") as AudioStream
	if not stream:
		return
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = stream
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


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


## ─── TASK 3: CHECKPOINT SNAPSHOT API ───────────────────────────────────
## Captures a deep-duplicate snapshot of the current inventory.
## Called by NightManager.start_night() once per night cycle, so the
## exact item state (including quest items like the Cable Spool) can be
## restored if the player dies and restarts from the checkpoint.
func save_checkpoint() -> void:
	var snapshot: Array = []
	for item in items:
		if item == null:
			snapshot.append(null)
			continue
		# Deep-duplicate Resource-backed ItemData so the snapshot is fully
		# independent of the live inventory and the original .tres file.
		var dup = item.duplicate(true) if item is Resource else item
		snapshot.append(dup)
	_checkpoint_items = snapshot
	print("[Inventory] Checkpoint snapshot saved (%d items)." % _checkpoint_items.size())


## Restores the inventory to the exact state captured by save_checkpoint().
## Called by NightManager.restart_night() when the player restarts from
## the checkpoint after a death. Any items consumed during the night
## (e.g. the Cable Spool) are restored, and any items picked up since the
## snapshot was taken are discarded.
func reset_to_checkpoint() -> void:
	items.clear()
	for item in _checkpoint_items:
		if item == null:
			items.append(null)
			continue
		var dup = item.duplicate(true) if item is Resource else item
		items.append(dup)
	_initialization_done = true
	inventory_changed.emit()
	print("[Inventory] Reset to checkpoint snapshot (%d items restored)." % items.size())
