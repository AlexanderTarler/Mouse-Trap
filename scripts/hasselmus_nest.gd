extends StaticBody3D

## HasselmusNest - An interactable nest that tracks documentation progress.
## When the player interacts with a nest, it increments the global nests_documented counter.
## When nests_documented reaches 3, triggers the Phone Drop event:
##   - Plays a clattering/falling sound
##   - Plays a deep echoing growl via HorrorSoundManager
##   - Emits a signal to NightManager to force sunset
##   - Disables the player's Phone/Map UI

signal nest_documented(nest_id: int)
signal phone_drop_event

## Unique ID for this nest (1, 2, or 3)
@export var nest_id: int = 1

## Display name for this nest
@export var nest_name: String = "Hasselmus Nest"

## Whether this nest has already been documented
var is_documented: bool = false

## Global counter - stored as an autoload variable
static var nests_documented: int = 0

## Reference to the AudioStreamPlayer for the clatter sound
var _clatter_player: AudioStreamPlayer3D = null

## Whether the phone drop event has been triggered
static var _phone_drop_triggered: bool = false


func _ready() -> void:
	# Add to a group for easy finding
	add_to_group("hasselmus_nests")
	
	# Create the clatter sound player
	_clatter_player = AudioStreamPlayer3D.new()
	_clatter_player.bus = "SFX"
	_clatter_player.max_distance = 20.0
	add_child(_clatter_player)
	
	# Try to load a clatter sound (use a wooden footstep as fallback)
	var clatter_stream = preload("res://assets/horror_sfx_vol_1/Wooden Foosteps/Wooden Foosteps (1).mp3")
	if clatter_stream:
		_clatter_player.stream = clatter_stream


func interact() -> void:
	if is_documented:
		print("[HasselmusNest] Nest ", nest_id, " already documented!")
		return
	
	if _phone_drop_triggered:
		print("[HasselmusNest] Phone drop already triggered!")
		return
	
	# Mark as documented
	is_documented = true
	nests_documented += 1
	
	print("[HasselmusNest] Nest ", nest_id, " documented! (", nests_documented, "/3)")
	print("[DEBUG NEST] Nest documented! Total nests documented variable = ", nests_documented)
	
	# Emit signal
	nest_documented.emit(nest_id)
	
	# Check if we've reached 3 nests
	if nests_documented >= 3:
		print("[DEBUG NEST] 3rd Nest reached! Calling GameTime.unpause_time() right now.")
		# Call GameTime autoload directly (not Engine singleton — it's a root node)
		if get_node_or_null("/root/GameTime"):
			get_node("/root/GameTime").unpause_time()
		else:
			GameTime.unpause_time()
		_trigger_phone_drop()
	else:
		# Just show a confirmation message
		_show_documented_message()


func _show_documented_message() -> void:
	# Find the HUD to show a message
	var hud = get_node_or_null("/root/CottageHorror/HUD")
	if not hud:
		hud = get_node_or_null("/root/Main/HUD")
	
	if hud and hud.has_method("_show_event"):
		hud._show_event("Nest %d documented! (%d/3)" % [nest_id, nests_documented])


func _trigger_phone_drop() -> void:
	_phone_drop_triggered = true
	
	print("[HasselmusNest] PHONE DROP EVENT TRIGGERED!")
	
	# 1. Play clattering/falling sound effect
	if _clatter_player and _clatter_player.stream:
		_clatter_player.play()
	
	# 2. Play deep echoing growl via HorrorSoundManager
	if Engine.has_singleton("HorrorSoundManager"):
		var sm = Engine.get_singleton("HorrorSoundManager")
		# Play a monster growl at the player's position
		var player = get_node_or_null("/root/CottageHorror/Player")
		if not player:
			player = get_node_or_null("/root/Main/Player")
		if player:
			sm.play_footstep_at("wooden", player.global_position)
			# Also play a growl via the event system
			sm._play_event_sound_3d(
				sm._get_random_stream(sm._monster_growl_streams),
				player.global_position + Vector3(0, 1, 0)
			)
	
	# 3. Advance the world state: push time to golden hour (progress 0.44)
	#    and unpause the day/night cycle so the sun sets naturally.
	# GameTime is an Autoload (root node), not an Engine singleton
	if get_node_or_null("/root/GameTime"):
		var gt = get_node("/root/GameTime")
		gt.set_progress(0.44)  # Push to golden hour (just before sunset)
		gt.unpause_time()      # Unfreeze the clock — time now advances
		print("[HasselmusNest] Set progress to 0.44 and unpaused time!")
	else:
		GameTime.set_progress(0.44)
		GameTime.unpause_time()
		print("[HasselmusNest] Set progress to 0.44 and unpaused time! (via global name)")

	
	# 4. Disable the player's Phone/Map UI
	_disable_phone_ui()
	
	# Show event message
	var hud = get_node_or_null("/root/CottageHorror/HUD")
	if not hud:
		hud = get_node_or_null("/root/Main/HUD")
	if hud and hud.has_method("_show_event"):
		hud._show_event("Your phone clatters to the ground... Something is coming!")


func _disable_phone_ui() -> void:
	# Find the InventoryUI (which acts as the phone/map) and disable it
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui:
		inv_ui = get_node_or_null("/root/Main/InventoryUI")
	
	if inv_ui:
		# Close it if it's open
		if inv_ui.has_method("_close_inventory"):
			inv_ui._close_inventory()
		print("[HasselmusNest] Phone/Map UI disabled!")
	
	# Also disable the NoteUI
	var note_ui = get_node_or_null("/root/CottageHorror/NoteUI")
	if not note_ui:
		note_ui = get_node_or_null("/root/Main/NoteUI")
	
	if note_ui:
		note_ui.visible = false
		if note_ui.has_method("_close_note"):
			note_ui._close_note()


func get_interact_text() -> String:
	if is_documented:
		return "[E] Nest %s - Already Documented" % nest_name
	return "[E] Document %s" % nest_name
