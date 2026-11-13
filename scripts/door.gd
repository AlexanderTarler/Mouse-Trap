extends AnimatableBody3D

## How many degrees the door swings open (90 or -90 depending on hinge side)
@export var open_angle: float = 90.0
## How fast the door opens or closes in seconds
@export var swing_speed: float = 0.4
@export var open_sound: AudioStream
@export var close_sound: AudioStream

## Lock/Key system — if a required_key_name is set, the door can be locked
## and the player needs the matching key item in their inventory to unlock it.
## The key is NOT consumed — the player keeps it and can lock/unlock freely.
@export var required_key_name: String = ""

## Whether this door should start the game in a locked state.
## Only takes effect when required_key_name is also set.
## Toggle this in the inspector to make a door start locked or unlocked.
@export var start_locked: bool = false
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
## Night 2.2: back inside after the chase with the door shut, the player
## won't open it again until Day 3 (set and cleared by NightTwoStory).
var story_locked: bool = false
var default_rotation_y: float
## Whether this door is currently locked (only used when required_key_name is set).
## Keeps the door's navigation link in sync, so the Entity can only path through
## the doorway while the door is unlocked.
var is_locked: bool = false:
	set(value):
		is_locked = value
		if _entry_link:
			_entry_link.enabled = not is_locked

## Navigation link from EntityDoorWaypoint (outside) to IndoorBreachWaypoint
## (inside). Only created for doors that have both markers (the cabin door).
var _entry_link: CabinEntryLink = null


## Trying a locked door when locked_sound isn't assigned.
const LOCKED_SOUND_DEFAULT := "res://assets/audio/objects/Locked Door.ogg"


func _ready() -> void:
	if not locked_sound and ResourceLoader.exists(LOCKED_SOUND_DEFAULT):
		locked_sound = load(LOCKED_SOUND_DEFAULT)
	# Save the baseline rotation so we always return to a clean closed state
	default_rotation_y = rotation_degrees.y
	
	# ─── INTERACTABLE COLLISION LAYER ────────────────────
	# Layer 2 ("Interactable") is dedicated to interactable targets; the
	# interaction ray only raycasts against layer 2. This door keeps its
	# default layer 1 (so the player/Entity still collide with it) AND adds
	# layer 2 (1|2 = 3) so the interaction ray can reach it from outside
	# without being blocked by porch/environment geometry.
	set_collision_layer_value(2, true)
	
	# ─── START LOCKED TOGGLE ───────────────────────────────────────
	# If start_locked is true and a required_key_name is set, initialize
	# the door as locked. This allows the level designer to toggle whether
	# a door starts locked or unlocked directly in the inspector.
	if required_key_name != "" and start_locked:
		is_locked = true
		print("[Door] Door starts LOCKED (start_locked=true). Key required: ", required_key_name)
	else:
		is_locked = false

	var outside_marker := get_node_or_null("EntityDoorWaypoint") as Node3D
	var inside_marker := get_node_or_null("IndoorBreachWaypoint") as Node3D
	if outside_marker and inside_marker:
		_entry_link = CabinEntryLink.create(self, CabinEntryLink.Kind.DOOR, outside_marker, inside_marker, not is_locked)

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
	Interactable.make_reachable(self)


## Quick tap E — opens/closes the door.
## If the door is locked, always plays the rattle sound (even with key).
## Lock/unlock is ONLY done via hold E for 2 seconds (toggle_lock).
func interact() -> void:
	if is_animating:
		return # Prevent input spam while the door is mid-swing

	# ─── EXHAUSTION GUARD (Day 3+) ────────────────────────────────
	# When the player is exhausted after surviving a night, the door
	# is barred — they cannot open it or unlock it. The message is
	# displayed as a centered event text that fades after 5 seconds.
	if _is_player_exhausted():
		_show_exhaustion_message("I'm not leaving the cabin until I've had some sleep.")
		return
	if story_locked and not is_open:
		Monologue.say("There is no way I'm going outside now.")
		return
	
	# If locked, always rattle — no quick unlock
	# The locked condition must ONLY play a rattle sound.
	# Do NOT change game state or call RoutineManager — that was a
	# copy-paste error that reset objectives to "Day 1 complete."
	if required_key_name != "" and is_locked:
		_play_locked_sound()
		print("[Door] Door is locked! Hold E to unlock. Need: ", required_key_name)
		# ─── DAY 1 ONBOARDING: PHASE 1 — DOOR TRIED LOCKED ──────────
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_door_tried_locked"):
			rm.on_door_tried_locked()
		return

	
	# Normal door toggle (open/close)
	is_open = not is_open
	NoiseEvent.emit(self, global_position, &"door")
	is_animating = true
	
	# ─── ENTITY DOOR OPEN DEBUG LOG ─────────────────────────────────
	# Logs when the Entity opens the door (detected by checking if the
	# caller is in the "entity" group). This helps debug whether the
	# Entity is successfully opening the door during APPROACH_WINDOW
	# or if it's getting stuck before reaching the door.
	if is_open and get_tree():
		var entity_nodes = get_tree().get_nodes_in_group("entity")
		for entity in entity_nodes:
			if entity and entity.global_position.distance_to(global_position) < 5.0:
				print("[DOOR_DEBUG] Entity opened door! Entity pos=(%.2f, %.2f, %.2f), Door pos=(%.2f, %.2f, %.2f), Door is_locked=%s" % [
					entity.global_position.x, entity.global_position.y, entity.global_position.z,
					global_position.x, global_position.y, global_position.z,
					is_locked
				])
				break
	
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
## Checkpoint restored is_open / is_locked: swing straight to that position.
func _on_checkpoint_restored() -> void:
	is_animating = false
	rotation_degrees.y = default_rotation_y + (open_angle if is_open else 0.0)


## Open or shut, locked or not, at once and without a sound (a restart
## putting the world back as it should be).
func set_state_quietly(open: bool, locked: bool) -> void:
	is_locked = locked
	story_locked = false
	is_open = open
	_on_checkpoint_restored()


func toggle_lock() -> void:
	if is_animating:
		return

	# ─── EXHAUSTION GUARD (Day 3+) ────────────────────────────────
	if _is_player_exhausted():
		_show_exhaustion_message("I'm not leaving the cabin until I've had some sleep.")
		return
	
	if required_key_name == "":
		return  # No lock system on this door
	
	var has_key = _has_key_in_inventory()
	if not has_key:
		_play_locked_sound()
		print("[Door] Need key to lock/unlock: ", required_key_name)
		# ─── DAY 1 ONBOARDING: PHASE 1 — DOOR TRIED LOCKED ──────────
		var rm2 = get_node_or_null("/root/RoutineManager")
		if rm2 and rm2.has_method("on_door_tried_locked"):
			rm2.on_door_tried_locked()
		return
	
	if is_locked:
		# Unlock (door stays closed — player can then open with quick tap)
		print("[Door] Unlocking door with: ", required_key_name)
		_play_lock_unlock_sound(false)  # false = unlock sound
		is_locked = false
		print("[Door] Door unlocked! (stays closed — tap E to open)")
		
		# ─── DAY 1 ONBOARDING: UNPAUSE TIME ──────────────────────────
		# When the player unlocks the cabin door with the CabinKey,
		# unpause the game clock so the Day 1 onboarding timer starts.
		# This is the trigger that transitions from "Enter the cabin"
		# to "Get settled in the cabin."
		var nm = get_node_or_null("/root/NightManager")
		if nm and nm.has_method("unpause_time"):
			nm.unpause_time()
		
		# ─── DAY 1 ONBOARDING: PHASE 1 — DOOR UNLOCKED ────────────────
		# Notify RoutineManager that the player unlocked the door.
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_door_unlocked"):
			rm.on_door_unlocked()
	else:
		# Lock (door stays closed)
		print("[Door] Locking door with: ", required_key_name)
		_play_lock_unlock_sound(true)  # true = lock sound
		is_locked = true
		print("[Door] Door locked! (stays closed)")
		
		# ─── DAY 1 ONBOARDING: PHASE 3 — DOOR LOCKED ───────────────────
		# Notify RoutineManager that the player locked the door.
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_door_locked"):
			rm.on_door_locked()


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
	NoiseEvent.emit(self, global_position, &"door")
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
		door_audio.pitch_scale = 1.0
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


## Returns true if the player is currently in an exhausted state (Day 3+).
func _is_player_exhausted() -> bool:
	var player_node = get_tree().get_first_node_in_group("player") as Node3D
	return player_node and "is_exhausted" in player_node and player_node.is_exhausted


## Shows a one-shot hint message on the HUD.
func _show_hint(message: String) -> void:
	print("[Door] ", message)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(message, self)


## The exhaustion line, as the player's thought over the door.
func _show_exhaustion_message(message: String) -> void:
	_show_hint(message)


## Closes and locks the door with a smooth animation (used by NightManager
## during the Day 3+ dawn exhaustion deferred lock sequence).
## Unlike the raw property assignments in NightManager._process(),
## this properly plays the door-close animation and manages is_animating.
func close_and_lock() -> void:
	if is_open:
		is_open = false
		is_animating = true
		var target_angle = default_rotation_y
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(self, "rotation_degrees:y", target_angle, swing_speed)
		tween.tween_callback(func(): is_animating = false)
		# Play close sound
		if door_audio:
			var target_stream = close_sound if close_sound else _original_scene_stream
			if target_stream:
				door_audio.stream = target_stream
				door_audio.pitch_scale = randf_range(0.9, 1.1)
				door_audio.play()
	var was_locked := is_locked
	is_locked = true
	# The game locking it for them counts as locking it (the "Lock the
	# door" objectives).
	if not was_locked:
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_door_locked"):
			rm.on_door_locked()


## Public API: Unlocks the door WITHOUT opening it. The door stays closed
## and the player must physically interact to open it.
## Used by RoutineManager on Day 2 Step 1 completion (notebook review).
func unlock() -> void:
	if is_locked:
		is_locked = false
		_play_lock_unlock_sound(false)  # false = unlock sound
		print("[Door] Door unlocked via unlock() — stays closed. Tap E to open.")
	# Ensure the door can be opened even if it was already unlocked
	set_collision_layer_value(1, true)


## Public API: Locks the door. Used by RoutineManager at the start of
## Day 2 to keep the player inside until they review the Nest Logs.
func lock() -> void:
	if not is_locked:
		is_locked = true
		_play_lock_unlock_sound(true)  # true = lock sound
		print("[Door] Door locked via lock().")


## Forces the door open, unlocking it. Not used by the Entity, which can only
## come in through the door while it is unlocked.
func break_door() -> void:
	print("[Door] Entity forcing door open via break_door()!")
	
	# Unlock the door if it was locked
	if is_locked:
		is_locked = false
		print("[Door] Door force-unlocked by Entity!")
	
	# Open the door if it's closed
	if not is_open:
		is_open = true
		is_animating = true
		
		var target_angle = default_rotation_y + open_angle
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(self, "rotation_degrees:y", target_angle, swing_speed * 0.5)  # Faster swing for Entity
		tween.tween_callback(func(): is_animating = false)
		
		# Play door open sound
		if door_audio:
			var target_stream = open_sound if open_sound else _original_scene_stream
			if target_stream:
				door_audio.stream = target_stream
				door_audio.pitch_scale = randf_range(0.8, 1.0)  # Slightly lower pitch for menacing effect
				door_audio.play()
		
		print("[Door] Door forced open by Entity!")
		
		# ─── FIX: Temporarily disable door collision for 5 seconds ──────────
		# When the Entity forces the door open, its collision shape can block
		# the Entity from walking through the doorway. By disabling collision
		# on the door for 5 seconds, the Entity can pass through the threshold
		# without getting stuck on the door's physics body.
		# After 5 seconds, collision is re-enabled so the door behaves normally
		# for the player (can be closed, blocks the Entity on subsequent passes).
		print("[FIX] Door collision temporarily disabled for 5 seconds to allow Entity passage.")
		set_collision_layer_value(1, false)
		set_collision_mask_value(1, false)
		
		# Re-enable collision after 5 seconds using a one-shot timer
		var collision_restore_tween = create_tween().set_loops(1)
		collision_restore_tween.tween_interval(5.0)
		collision_restore_tween.tween_callback(func():
			set_collision_layer_value(1, true)
			set_collision_mask_value(1, true)
			print("[FIX] Door collision re-enabled after 5-second window.")
		)
	else:
		print("[Door] Door was already open.")


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
