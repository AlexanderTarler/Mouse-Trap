extends StaticBody3D

## The car part item this wreck contains.
## Assign an ItemData .tres resource (e.g., car_part_battery.tres) in the Inspector.
@export var item_resource: ItemData

## An inner-monologue message shown when the player interacts BEFORE Day 3.
## Each wreck should have a unique sarcastic message about the abandoned car.
## When Day 3 arrives, the player can salvage the part instead.
@export_multiline var inner_monologue: String = ""

## Tracks whether the player has already looted this specific car.
var is_looted: bool = false

## Tracks whether the inner monologue has been shown (so it doesn't repeat).
var _monologue_shown: bool = false


## Triggered when the player looks at the car and presses the interact key.
func interact(player: Node3D = null) -> void:
	print("[Wreck] interact() CALLED — is_looted=", is_looted, " | item_resource=", item_resource)
	
	# ─── ALREADY LOOTED ─────────────────────────────────────────
	if is_looted:
		_show_hud_message("It's completely stripped. Nothing useful left.")
		print("[Wreck] BLOCKED: Already looted.")
		return
	
	# ─── BEFORE DAY 3: Inner monologue only, NO item given ──────
	# The player notices the wrecks and makes sarcastic observations,
	# but can only actually scavenge them once desperation sets in.
	if _is_before_day_3():
		if inner_monologue.length() > 0 and not _monologue_shown:
			_show_hud_message(inner_monologue)
			_monologue_shown = true
			print("[Wreck] Inner monologue shown (before Day 3). Item NOT given.")
		elif _monologue_shown:
			# Monologue already seen — say nothing, but don't give item
			print("[Wreck] Monologue already shown previously, skipping.")
		else:
			print("[Wreck] No inner_monologue set, but before Day 3. No action.")
		return
	
	# ─── DAY 3+: Salvage the car part ───────────────────────────
	# Validate we have a resource to give
	if not item_resource:
		print("[Wreck] ERROR: item_resource is NULL! No .tres assigned in the scene.")
		_show_hud_message("Nothing useful here.")
		return
	
	print("[Wreck] item_resource OK — class=", item_resource.get_class(), " | item_name=", _get_item_name())
	
	# Resolve the Inventory autoload
	var inventory: Node = _get_inventory()
	if not inventory:
		print("[Wreck] ERROR: Could not find Inventory autoload (/root/Inventory)!")
		_show_hud_message("Cannot access inventory right now.")
		return
	print("[Wreck] Inventory autoload found: ", inventory)
	
	# Add to inventory
	var added: bool = inventory.add_item(item_resource)
	print("[Wreck] Inventory.add_item() returned: ", added)
	
	if not added:
		_show_hud_message("Inventory is full!")
		print("[Wreck] FAILED: Inventory full or item rejected.")
		return
	
	# Update state & show message
	is_looted = true
	var item_name := _get_item_name()
	_show_hud_message("Salvaged: " + item_name)
	print("[Wreck] SUCCESS: Player salvaged '", item_name, "'. is_looted now true.")


## Returns true if the game hasn't reached Day 3 yet.
## Uses NightManager.current_night: 0 = Day 1, 1 = Day 2, 2 = Day 3, etc.
func _is_before_day_3() -> bool:
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm:
		return nm.current_night < 3
	return false


## Safely resolves the Inventory autoload singleton.
func _get_inventory():
	var inv = get_node_or_null("/root/Inventory")
	if inv:
		return inv
	# Fallback: try finding it in groups
	var candidates = get_tree().get_nodes_in_group("inventory")
	if candidates.size() > 0:
		print("[Wreck] Found Inventory via 'inventory' group.")
		return candidates[0]
	return null


## Safely extracts the display name from the item resource.
func _get_item_name() -> String:
	if item_resource and "item_name" in item_resource:
		return str(item_resource.item_name)
	if item_resource and "resource_path" in item_resource:
		var path := str(item_resource.resource_path)
		return path.get_file().get_basename()
	print("[Wreck] WARNING: Could not extract name from item_resource!")
	return "Unknown Part"


## UI Helper to push string messages to the HUD overlay.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
		print("[Wreck HUD] ", msg)
	else:
		print("[Wreck HUD Missing] ", msg)
