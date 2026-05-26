extends Node3D
class_name CabinWindow

## CabinWindow — Window barricade and light sanctuary system.
## Attach this script to each window Marker3D (or a parent node) in the cabin.
##
## The player can board up windows using Wooden Planks from their inventory.
## Boarded windows have structural integrity (plank_health) that the Entity
## must damage to break through.
##
## The three plank meshes (Plank1, Plank2, Plank3) visualize the barricade's
## remaining health:
##   - 100%–67% : All 3 planks visible
##   - 66%–34%  : Plank3 disappears (2 planks visible)
##   - 33%–1%   : Plank2 disappears (1 plank visible)
##   - 0%       : Plank1 disappears (barricade broken)
##
## If the room's CabinLight is switched on, the window is considered "secure"
## by light — the Entity will avoid it and pick a different window.
## If boarded up, the Entity must pause and damage the planks until they break.
##
## is_secure() returns true if EITHER the light is on OR the window is boarded.

## Reference to the corresponding room's CabinLight node.
## Assign this in the scene editor to link the window to its room light.
@export var room_light: CabinLight = null

## Whether this window is currently boarded up with planks
var is_boarded: bool = false

## Structural integrity of the planks (0.0 = broken, 100.0 = full health)
var plank_health: float = 100.0

## Reference to the three individual plank meshes (children of BarricadePlanks).
## These are toggled on/off based on remaining health to give a visual
## indication of barricade integrity.
@onready var _plank_1: Node3D = $BarricadePlanks/Plank1 if has_node("BarricadePlanks/Plank1") else null
@onready var _plank_2: Node3D = $BarricadePlanks/Plank2 if has_node("BarricadePlanks/Plank2") else null
@onready var _plank_3: Node3D = $BarricadePlanks/Plank3 if has_node("BarricadePlanks/Plank3") else null

## Reference to an AudioStreamPlayer3D for the plank break sound
@onready var _break_sound: AudioStreamPlayer3D = $BreakSound if has_node("BreakSound") else null

## Reference to an AudioStreamPlayer3D for the plank hammer sound
@onready var _hammer_sound: AudioStreamPlayer3D = $HammerSound if has_node("HammerSound") else null


func _ready() -> void:
	# Add to the WindowMarkers group so the Entity AI can find this window
	add_to_group("WindowMarkers")
	
	# Initialize plank visibility based on initial state
	_update_plank_visuals()


## Updates the visibility of Plank1, Plank2, Plank3 based on current health.
## Called after boarding up, taking damage, or shattering.
func _update_plank_visuals() -> void:
	if not is_boarded:
		# All planks hidden when not boarded
		if _plank_1: _plank_1.visible = false
		if _plank_2: _plank_2.visible = false
		if _plank_3: _plank_3.visible = false
		return
	
	var health_pct = plank_health / 100.0
	
	# Plank1 visible above 0% health
	if _plank_1:
		_plank_1.visible = health_pct > 0.0
	
	# Plank2 visible above 33% health
	if _plank_2:
		_plank_2.visible = health_pct > 0.33
	
	# Plank3 visible above 66% health
	if _plank_3:
		_plank_3.visible = health_pct > 0.66


## Returns true if this window is secure against the Entity.
## A window is secure if:
##   - The room light is switched on (light sanctuary — Entity avoids it), OR
##   - The window is boarded up with planks (Entity must break through)
func is_secure() -> bool:
	# Light sanctuary: if the room light is on, the Entity cannot approach
	if room_light and room_light.is_switched_on:
		return true
	
	# Barricade: if boarded up, the window is secure until planks break
	if is_boarded:
		return true
	
	return false


## Returns the type of security active on this window.
## Returns "light" if protected by room light, "planks" if boarded, "" if unsecured.
func get_secure_type() -> String:
	if room_light and room_light.is_switched_on:
		return "light"
	if is_boarded:
		return "planks"
	return ""


## Called by the Entity AI to damage the barricade over time.
## Returns true if the barricade has been destroyed (plank_health <= 0).
func damage_barricade(delta: float) -> bool:
	if not is_boarded:
		return true  # Already open, no barricade to damage
	
	plank_health -= delta * 10.0  # 10 damage per second (takes ~10s to break)
	plank_health = maxf(plank_health, 0.0)
	
	# Update plank visuals to reflect new health level
	_update_plank_visuals()
	
	if plank_health <= 0.0:
		_shatter_barricade()
		return true
	
	return false


## Destroys the barricade, plays a break sound, and resets the state.
func _shatter_barricade() -> void:
	is_boarded = false
	plank_health = 0.0
	
	# Hide all planks
	_update_plank_visuals()
	
	# Play break sound
	if _break_sound:
		_break_sound.play()
	elif _hammer_sound:
		# Fallback: use hammer sound as a break sound
		_hammer_sound.play()
	
	print("[CabinWindow] Barricade shattered! Window is now exposed.")


## Player interaction: board up this window using a Wooden Plank from inventory.
## Consumes 1 plank item, sets is_boarded to true, restores plank_health to 100.
func interact() -> void:
	# If already boarded, show a different message
	if is_boarded:
		print("[CabinWindow] Window is already boarded up.")
		return
	
	# Check if the player has a Wooden Plank in their inventory
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		print("[CabinWindow] Inventory not found!")
		return
	
	# Find a plank item in the inventory
	var plank_item = null
	for item in inventory.items:
		if item != null and item.item_type == ItemData.ItemType.PLANK:
			plank_item = item
			break
	
	if not plank_item:
		print("[CabinWindow] No Wooden Plank in inventory!")
		return
	
	# Consume one plank
	inventory.remove_item(plank_item)
	
	# Board up the window
	is_boarded = true
	plank_health = 100.0
	
	# Show all three planks
	_update_plank_visuals()
	
	# Play hammer sound
	if _hammer_sound:
		_hammer_sound.play()
	
	print("[CabinWindow] Window boarded up! Plank health: %.1f" % plank_health)


## Returns the interaction prompt text shown in the HUD.
func get_interact_text() -> String:
	if is_boarded:
		return "[E] Window - Boarded (Integrity: %d%%)" % plank_health
	
	# Check if the player has a plank
	var inventory = get_node_or_null("/root/Inventory")
	if inventory:
		for item in inventory.items:
			if item != null and item.item_type == ItemData.ItemType.PLANK:
				return "[E] Board up window"
	
	return "[E] Window - No planks available"
