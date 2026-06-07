extends AnimatableBody3D

## How many degrees the door swings open (90 or -90 depending on hinge side)
@export var open_angle: float = 90.0
## How fast the door opens or closes in seconds
@export var swing_speed: float = 0.4
@export var open_sound: AudioStream
@export var close_sound: AudioStream

## Lock/Key system — if a required_key_name is set, the door starts locked
## and the player needs the matching key item in their inventory to unlock it.
## The key is NOT consumed — the player keeps it and can lock/unlock freely.
@export var required_key_name: String = ""
## Sound to play when the player tries the locked door without a key.
@export var locked_sound: AudioStream
## Sound to play when the door is successfully unlocked.
@export var unlock_sound: AudioStream
## Sound to play when the door is locked shut.
@export var lock_sound: AudioStream

## Programmatically loaded lock/unlock sound paths (fallback if exported streams are null).
const LOCK_SOUND_PATH: String = "res://assets/audio/objects/lock_door.ogg"
const UNLOCK_SOUND_PATH: String = "res://assets/audio/objects/unlock_door.ogg"

## Cached programmatic audio streams for lock/unlock sounds.
## Loaded once in _ready() using ResourceLoader.exists() guards.
var _lock_sound_programmatic: AudioStream = null
var _unlock_sound_programmatic: AudioStream = null

## Cached baseline stream that was pre-assigned to the DoorAudio node in the scene editor.
## Used as the fallback in interact() for open/close sounds, ensuring the default door
## swing audio always plays correctly even after _play_lock_unlock_sound() or
## _play_locked_sound() have overwritten door_audio.stream.
var _original_scene_stream: AudioStream = null

@onready var door_audio: AudioStreamPlayer3D = $DoorAudio if has_node("DoorAudio") else null

var is_open: bool = false
var is_animating: bool = false
var default_rotation_y: float
## Whether this door is currently locked (only used when required_key_name is set).
var is_locked: bool = true


func _ready() -> void:
	# Save the baseline rotation so we always return to a clean closed state
	default_rotation_y = rotation_degrees.y
	
	# ─── CACHE THE ORIGINAL SCENE STREAM ───────────────────────────
	# Snapshot the stream that was pre-assigned to the DoorAudio node in the
	# scene editor. This cached reference is used as the fallback in interact()
	# for open/close sounds, ensuring the default door swing audio always plays
	# correctly even after _play_lock_unlock_sound() or _play_locked_sound()
	# have overwritten door_audio.stream at runtime.
	if door_audio:
		_original_scene_stream = door_audio.stream
	
	# ─── PROGRAMMATIC AUDIO LOADING ────────────────────────────────
	# Load lock/unlock sound effects from file paths using ResourceLoader.exists()
	# guards. These serve as fallbacks if the exported AudioStream properties
	# (lock_sound, unlock_sound) are null in the inspector.
	if ResourceLoader.exists(LOCK_SOUND_PATH):
		_lock_sound_programmatic = load(LOCK_SOUND_PATH) as AudioStream
	if ResourceLoader.exists(UNLOCK_SOUND_PATH):
		_unlock_sound_programmatic = load(UNLOCK_SOUND_PATH) as AudioStream


## Quick tap E — opens/closes the door.
## If the door is locked, always plays the rattle sound (even with key).
## Lock/unlock is ONLY done via hold E for 2 seconds (toggle_lock).
func interact() -> void:
	if is_animating:
		return # Prevent input spam while the door is mid-swing
	
	# If locked, always rattle — no quick unlock
	if required_key_name != "" and is_locked:
		_play_locked_sound()
		print("[Door] Door is locked! Hold E to unlock. Need: ", required_key_name)
		return
	
	# Normal door toggle (open/close)
	is_open = not is_open
	is_animating = true
	
	# Play door audio with pitch randomization
	# Priority 1: Use the exported open_sound / close_sound property if assigned.
	# Priority 2: Fall back to the baseline stream cached from the DoorAudio node
	#             on startup (_original_scene_stream). This ensures the default
	#             door swing audio (e.g. door_1_open.ogg) always plays correctly,
	#             even after _play_lock_unlock_sound() or _play_locked_sound()
	#             have overwritten door_audio.stream at runtime.
	if door_audio:
		var target_stream = open_sound if is_open else close_sound
		if not target_stream:
			# Fallback directly to the baseline asset cached on startup
			target_stream = _original_scene_stream
		if target_stream:
			door_audio.stream = target_stream
			door_audio.pitch_scale = randf_range(0.9, 1.1)
			door_audio.play()
	
	# Determine target rotation destination
	var target_angle = default_rotation_y + (open_angle if is_open else 0.0)
	
	# Create a clean, smooth physics tween interpolation
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "rotation_degrees:y", target_angle, swing_speed)
	
	# Unlock input once the animation finishes moving
	tween.tween_callback(func(): is_animating = false)


## Hold E for 2 seconds on a closed door — locks or unlocks it.
## Only available when the door is closed and the player has the key.
## Unlocking just unlocks the door (stays closed) — player can then open it with a quick tap.
## Locking keeps the door closed.
func toggle_lock() -> void:
	if is_animating:
		return
	
	if required_key_name == "":
		return  # No lock system on this door
	
	var has_key = _has_key_in_inventory()
	if not has_key:
		_play_locked_sound()
		print("[Door] Need key to lock/unlock: ", required_key_name)
		return
	
	if is_locked:
		# Unlock (door stays closed — player can then open with quick tap)
		print("[Door] Unlocking door with: ", required_key_name)
		_play_lock_unlock_sound(false)  # false = unlock sound
		is_locked = false
		print("[Door] Door unlocked! (stays closed — tap E to open)")
	else:
		# Lock (door stays closed)
		print("[Door] Locking door with: ", required_key_name)
		_play_lock_unlock_sound(true)  # true = lock sound
		is_locked = true
		print("[Door] Door locked! (stays closed)")
		
		# Check if we should advance the Night 1 bedtime routine
		_check_routine_advance()


## Checks the player's inventory for an item matching required_key_name.
func _has_key_in_inventory() -> bool:
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == required_key_name:
			return true
	return false


## Unlocks and opens the door. Key is NOT consumed.
func _unlock_door() -> void:
	print("[Door] Unlocking door with: ", required_key_name)
	
	# Play unlock sound via the shared helper (supports programmatic fallback)
	_play_lock_unlock_sound(false)  # false = unlock sound
	
	# Unlock and open the door
	is_locked = false
	is_open = true
	is_animating = true
	
	var target_angle = default_rotation_y + open_angle
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "rotation_degrees:y", target_angle, swing_speed)
	tween.tween_callback(func(): is_animating = false)
	
	print("[Door] Door unlocked and opened!")


## Plays the locked rattle sound to indicate the door won't open.
func _play_locked_sound() -> void:
	if locked_sound and door_audio:
		door_audio.stream = locked_sound
		door_audio.pitch_scale = randf_range(0.9, 1.1)
		door_audio.play()


## Plays the lock or unlock sound effect when the door's is_locked state changes.
##
## Priority order:
##   1. Exported AudioStream property (lock_sound / unlock_sound) — set in the inspector.
##   2. Programmatically loaded stream from file path — loaded in _ready() via
##      ResourceLoader.exists() guards.
##
## @param is_locking: If true, plays the lock sound. If false, plays the unlock sound.
func _play_lock_unlock_sound(is_locking: bool) -> void:
	if not door_audio:
		return
	
	var target_stream: AudioStream = null
	
	if is_locking:
		# Priority 1: Exported lock_sound property
		if lock_sound:
			target_stream = lock_sound
		# Priority 2: Programmatic fallback
		elif _lock_sound_programmatic:
			target_stream = _lock_sound_programmatic
	else:
		# Priority 1: Exported unlock_sound property
		if unlock_sound:
			target_stream = unlock_sound
		# Priority 2: Programmatic fallback
		elif _unlock_sound_programmatic:
			target_stream = _unlock_sound_programmatic
	
	if target_stream:
		door_audio.stream = target_stream
		door_audio.pitch_scale = 1.0
		door_audio.play()


## Checks if the Night 1 bedtime routine should advance to Step 4.
## Called when the player locks the door. Only advances if:
##   - We're on Step 3 of the routine
##   - All cabin lights are switched off
func _check_routine_advance() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if not rm or not rm.has_method("advance_step"):
		return
	
	# Only advance if we're on Step 3 (lock door + turn off lights)
	if rm.current_step != 3:
		return
	
	# Check if all cabin lights are off
	# IMPORTANT: Faulty lights (e.g. the permanently short-circuited porch light)
	# are EXCLUDED from this check — they cannot be toggled off and would
	# otherwise block progression forever.
	var all_lights_off = true
	var lights = get_tree().get_nodes_in_group("CabinLights")
	for light in lights:
		# Skip faulty lights — they are permanently stuck ON and cannot be toggled
		if "is_faulty" in light and light.is_faulty:
			print("[Door] Skipping faulty light '%s' (permanently stuck ON)." % light.light_name if "light_name" in light else "unknown faulty")
			continue
		if "is_switched_on" in light and light.is_switched_on:
			all_lights_off = false
			print("[Door] Light '%s' is still on. Cannot advance routine." % light.light_name if "light_name" in light else "unknown")
			break
	
	if not all_lights_off:
		print("[Door] Not all lights are off. Cannot advance routine yet.")
		return
	
	# All conditions met — advance to Step 4
	print("[Door] Door locked and all lights off! Advancing routine to Step 4.")
	rm.advance_step()


func get_interact_text() -> String:
	if required_key_name == "":
		# No lock system — normal door
		return "[E] Open Door"
	
	if is_locked:
		if _has_key_in_inventory():
			return "[Hold E] Unlock Door"
		return "[E] Door is locked"
	
	# Door is unlocked
	if is_open:
		return "[E] Close Door"
	
	# Door is closed and unlocked
	if _has_key_in_inventory():
		return "[E] Open Door\n[Hold E] Lock Door"
	return "[E] Open Door"
