extends Area3D

## Generator refill interaction point.
## Attach this script to an Area3D node placed on the physical generator model.
## When the player interacts (presses E) while looking at this area, it checks
## the inventory for a Fuel Can and shows a confirmation popup asking if they
## want to add fuel. Only consumes the fuel can if the player clicks "Yes".

## Amount of fuel restored per can (50% of max_fuel)
const REFILL_AMOUNT: float = 50.0


func _ready() -> void:
	# Ensure this Area3D can be detected by the interaction manager's raycast
	collision_layer = 1


func interact() -> void:
	var nm = get_node_or_null("/root/NightManager")
	if not nm:
		print("[Generator] ERROR: NightManager not found!")
		return
	
	# Check if the player has a Fuel Can in their inventory
	var fuel_can = _find_fuel_can_in_inventory()
	
	if not fuel_can:
		print("[Generator] I need a Fuel Can to refill the generator.")
		return
	
	# Show confirmation popup asking the player if they want to add fuel
	_show_fuel_confirmation(nm, fuel_can)


## Shows a confirmation dialog asking the player if they want to add fuel.
## If they click "Yes", the fuel can is consumed and the generator is refilled.
func _show_fuel_confirmation(nm: Node, fuel_can: ItemData) -> void:
	# Create a temporary ConfirmationDialog
	var dialog = ConfirmationDialog.new()
	dialog.title = "Refill Generator"
	dialog.dialog_text = "Add fuel? (Refills %.0f%%)" % REFILL_AMOUNT
	dialog.ok_button_text = "Yes"
	dialog.cancel_button_text = "No"
	dialog.exclusive = true
	
	# Add it to the scene tree so it appears on screen
	get_tree().current_scene.add_child(dialog)
	
	# Center the dialog on screen
	dialog.popup_centered()
	
	# Wait for the player's choice
	# The 'confirmed' signal fires when "Yes" is clicked
	await dialog.confirmed
	
	# If confirmed (Yes), consume the fuel can and refill
	_apply_fuel(nm, fuel_can)
	
	# Clean up the dialog
	dialog.queue_free()


## Consumes one fuel can from inventory and refills the generator.
func _apply_fuel(nm: Node, fuel_can: ItemData) -> void:
	# Consume 1 fuel can from inventory
	Inventory.remove_item(fuel_can)
	
	# Refill the generator
	nm.generator_fuel = min(nm.generator_fuel + REFILL_AMOUNT, nm.max_fuel)
	
	# Emit fuel_changed so the HUD updates immediately
	nm.fuel_changed.emit(nm.generator_fuel)
	
	# If the generator was off, turn it back on
	if not nm.is_generator_on:
		nm.is_generator_on = true
		nm.generator_state_changed.emit(true)
		print("[Generator] Generator restarted!")
	
	# Recalculate fuel drain to account for any lights that may have been off
	nm.recalculate_fuel_drain()
	
	# Advance the Night 1 bedtime routine to the next step.
	# Only advance if we're on Step 2 (refill generator) to prevent
	# premature advancement if the player refuels before the computer upload.
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("advance_step") and rm.current_step == 2:
		rm.advance_step()
	
	print("[Generator] Refueled successfully! Fuel: %.1f / %.1f" % [nm.generator_fuel, nm.max_fuel])


## Searches the player's inventory for a Fuel Can item.
## Returns the first matching ItemData, or null if none found.
func _find_fuel_can_in_inventory():
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Fuel Can":
			return item
	return null


func get_interact_text() -> String:
	return "[E] Refill Generator"
