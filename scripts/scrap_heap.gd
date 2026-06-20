extends StaticBody3D
class_name ScrapHeap

## Scrap Heap — Daytime scavenging container.
## Players can search through industrial debris piles during the day
## to find items, car parts, and clues.
##
## When interacted with, freezes the player and opens a two-panel stash
## UI showing the player's inventory on one side and the scrap heap's
## contents on the other. Items can be transferred between the two.
##
## Scavenging is blocked during night hours — the player must wait
## until dawn to search through scrap.
##
## Each scrap heap spawns with items at game start and is NOT refreshed
## at dawn. Once emptied, the heap is "spent" and shows a message
## instead of opening the stash UI.

# ─── EXPORTS ───────────────────────────────────────────────

## Unique identifier for this scrap heap (used for logging and save data).
@export var scrap_heap_id: String = "scrap_heap_01"

## Internal slot array of item data structures.
## Each entry: { item_data: ItemData, quantity: int }
@export var contents: Array[Dictionary] = []

## If true, this scrap heap will contain one of the 3 car part items
## (to be added later) instead of one of its normal items.
@export var will_contain_car_part: bool = false

## Probability (0.0 to 1.0) that this scrap heap contains a Fuse item
## when searched. The fuse is added as an extra bonus item alongside
## the normal loot, not replacing any existing items.
## Only checked once during _spawn_initial_contents().
@export var fuse_spawn_chance: float = 0.3

# ─── STATE ─────────────────────────────────────────────────

## Whether this scrap heap has been completely emptied.
## When true, interacting shows "No more useable items" instead of
## opening the stash UI.
var is_spent: bool = false

# ─── NODE REFERENCES ───────────────────────────────────────

@onready var _night_manager = get_node_or_null("/root/NightManager")
@onready var _game_time = get_node_or_null("/root/GameTime")


# ─── READY ─────────────────────────────────────────────────

func _ready() -> void:
	# Spawn initial contents if the heap is empty (first time loading)
	if contents.is_empty():
		_spawn_initial_contents()


# ─── INTERACTION PROMPT ────────────────────────────────────

## Returns the interaction prompt text shown in the HUD crosshair.
func get_interact_text() -> String:
	if is_spent:
		return "[E] Search Scrap Heap (spent)"
	return "[E] Search Scrap Heap"


# ─── INTERACT ──────────────────────────────────────────────

## Called by the InteractionManager when the player looks at this
## scrap heap and presses E (quick tap).
##
## If the heap is spent, shows a message and returns immediately.
## Otherwise, checks the night state, freezes the player, and opens
## the stash UI.
func interact(player: Node3D = null) -> void:
	# ─── SPENT CHECK ───────────────────────────────────────
	if is_spent:
		_show_hud_message("No more useable items.")
		print("[ScrapHeap] %s: Spent — no items left." % scrap_heap_id)
		return

	# Resolve player reference if not provided
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0] as Node3D
	if not player:
		print("[ScrapHeap] ERROR: No player found!")
		return

	# ─── NIGHT CHECK ───────────────────────────────────────
	# Block scavenging during night hours. The player must wait
	# until dawn to search through scrap piles.
	var is_night: bool = false

	if _night_manager and _night_manager.is_night_active:
		is_night = true
	elif _game_time and not _game_time.is_day:
		is_night = true

	if is_night:
		_show_hud_message("It's too dark to look through scrap right now...")
		print("[ScrapHeap] %s: Blocked — night time." % scrap_heap_id)
		return

	# ─── FREEZE PLAYER ─────────────────────────────────────
	# Disable player input and physics processing so they can't
	# walk away while the stash UI is open.
	player.set_process_input(false)
	player.set_physics_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	print("[ScrapHeap] %s: Player started searching." % scrap_heap_id)

	# ─── OPEN STASH UI ─────────────────────────────────────
	# Pass a self-reference and the internal contents array.
	# The stash UI will mutate contents directly (by reference).
	var stash_ui = _get_or_create_stash_ui()
	if stash_ui and stash_ui.has_method("open_container_stash"):
		stash_ui.open_container_stash(self, contents)
	else:
		# Fallback: if stash UI can't be created, unfreeze player
		close_container(player)
		print("[ScrapHeap] ERROR: Could not open stash UI!")


# ─── CLOSE CONTAINER ───────────────────────────────────────

## Called by the stash UI when the player exits the screen.
## Re-captures the mouse cursor and cleanly unfreezes player
## inputs and physics processing.
##
## After closing, checks if the heap is now empty and marks it as spent.
func close_container(player: Node3D = null) -> void:
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0] as Node3D
	if not player:
		print("[ScrapHeap] ERROR: No player found to unfreeze!")
		return

	# Re-capture mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Restore player controls
	player.set_process_input(true)
	player.set_physics_process(true)

	# ─── SPENT CHECK ───────────────────────────────────────
	# If all items have been taken, mark this heap as spent
	# so future interactions show "No more useable items".
	if contents.is_empty():
		is_spent = true
		print("[ScrapHeap] %s: Now spent — all items taken." % scrap_heap_id)

	print("[ScrapHeap] %s: Player stopped searching." % scrap_heap_id)


# ─── INITIAL SPAWN ─────────────────────────────────────────

## Generates the initial contents for this scrap heap.
## Called once in _ready() when the heap has no contents yet.
## If will_contain_car_part is true, one slot is reserved for a
## car part item (placeholder for future implementation).
func _spawn_initial_contents() -> void:
	contents.clear()

	# Determine how many normal items to spawn
	var normal_count = randi_range(2, 4)

	# If this heap will contain a car part, reduce normal items by 1
	if will_contain_car_part and normal_count > 1:
		normal_count -= 1

	# Spawn normal items
	for i in range(normal_count):
		var item_data = _get_random_item_data()
		if item_data:
			# 50% chance of stacking
			var quantity = 2 if randf() > 0.5 else 1
			contents.append({
				"item_data": item_data,
				"quantity": quantity
			})

	# ─── FUSE BONUS LOOT ───────────────────────────────────
	# Roll the dice: if fuse_spawn_chance succeeds, add a Fuse item
	# as an extra bonus alongside the normal loot.
	if randf() < fuse_spawn_chance:
		var fuse_data = _try_load_resource("res://resources/fuse_resource.tres")
		if fuse_data:
			contents.append({
				"item_data": fuse_data,
				"quantity": 1
			})
			print("[ScrapHeap] %s: Fuse spawned! (chance was %.0f%%)" % [scrap_heap_id, fuse_spawn_chance * 100.0])
		else:
			print("[ScrapHeap] %s: Fuse resource not found, skipping fuse spawn." % scrap_heap_id)

	# If this heap is flagged for a car part, add a random car part item
	if will_contain_car_part:
		var car_part = _get_random_car_part_data()
		if car_part:
			contents.append({
				"item_data": car_part,
				"quantity": 1
			})
			print("[ScrapHeap] %s: Car part spawned: %s" % [scrap_heap_id, car_part.item_name])
		else:
			print("[ScrapHeap] %s: Car part resource not found, skipping." % scrap_heap_id)

	print("[ScrapHeap] %s: Initial contents spawned with %d item types." % [scrap_heap_id, contents.size()])


## Returns a random ItemData resource from a predefined pool.
## Uses try_load to gracefully handle missing resource files.
## Override this in subclasses for custom loot tables.
func _get_random_item_data():
	var pool = []
	
	# Try to load each resource — gracefully skip if file doesn't exist
	var battery = _try_load_resource("res://resources/battery_resource.tres")
	if battery:
		pool.append(battery)
	
	var fuel = _try_load_resource("res://resources/fuel_can_resource.tres")
	if fuel:
		pool.append(fuel)
	
	var plank = _try_load_resource("res://resources/plank_resource.tres")
	if plank:
		pool.append(plank)
	
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


## Returns a random car part ItemData resource from the 3 possible parts.
## The player needs all 3 to repair the van, but they only find one per
## scrap heap — they must scavenge multiple heaps to collect them all.
func _get_random_car_part_data():
	var pool = []
	
	var battery = _try_load_resource("res://resources/car_part_battery.tres")
	if battery:
		pool.append(battery)
	
	var radiator = _try_load_resource("res://resources/car_part_radiator.tres")
	if radiator:
		pool.append(radiator)
	
	var wiring = _try_load_resource("res://resources/car_part_wiring.tres")
	if wiring:
		pool.append(wiring)
	
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


## Safely attempts to load a resource, returning null if the file
## doesn't exist instead of throwing a parse error.
func _try_load_resource(path: String):
	if ResourceLoader.exists(path):
		return load(path)
	return null


# ─── UI HELPERS ────────────────────────────────────────────

## Finds an existing StashUI in the scene tree, or lazy-instantiates
## a new one from the stash_ui.tscn scene.
func _get_or_create_stash_ui() -> Node:
	# Search the entire scene tree for an existing StashUI instance
	var existing = get_tree().root.find_child("StashUI", true, false)
	if existing:
		return existing

	# Lazy-load and instantiate the stash UI scene
	var stash_scene = preload("res://scenes/stash_ui.tscn")
	if stash_scene:
		var instance = stash_scene.instantiate()
		instance.name = "StashUI"

		# Add to the current scene (most reliable)
		var scene = get_tree().current_scene
		if scene:
			scene.add_child(instance)
			print("[ScrapHeap] StashUI instantiated and added to current scene.")
			return instance

		# Fallback: add to root
		var root = get_tree().root
		if root:
			root.add_child(instance)
			print("[ScrapHeap] StashUI instantiated and added to root.")
			return instance

	print("[ScrapHeap] ERROR: Could not instantiate stash_ui.tscn!")
	return null


## Pushes a text message to the HUD overlay.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[ScrapHeap HUD]: ", msg)
