extends CharacterBody3D

## Stair climbing settings
@export var stair_step_assist: bool = true
@export var max_step_height: float = 0.7
@export var step_check_distance: float = 0.5

## Jump settings
@export var jump_velocity: float = 4.5

@export var walk_speed: float = 3.5
@export var run_speed: float = 6.5
@export var crouch_speed: float = 1.8
@export var mouse_sensitivity: float = 0.002
@export var head_bob_enabled: bool = true
@export var head_bob_frequency: float = 2.0
@export var head_bob_amplitude: float = 0.06

# Crouch settings
@export var standing_height: float = 1.8
@export var crouching_height: float = 1.45
@export var crouch_transition_speed: float = 10.0

# References to scene nodes
@onready var _camera: Camera3D = $CameraHolder/Camera3D
@onready var _camera_holder: Node3D = $CameraHolder
@onready var _collision_shape: PrismCollider3D = $PrismCollider3D
@onready var _flashlight: SpotLight3D = $CameraHolder/Camera3D/Flashlight
@onready var _interaction_manager: Node = $CameraHolder/InteractionManager
@onready var _physical_grab: Node = $CameraHolder/PhysicalGrab
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio if has_node("FootstepAudio") else null

# PrismCollider3D reference for crouch resizing.
@onready var _prism_collider: Node = $PrismCollider3D if has_node("PrismCollider3D") else null

@export var wood_footsteps: Array[AudioStream] = []
@export var grass_footsteps: Array[AudioStream] = []

var _current_speed: float
var _step_timer: float = 0.0
var _step_interval: float = 0.5
var _head_bob_time: float = 0.0
var _head_bob_active: bool = false
var _is_crouching: bool = false

# Flashlight
var _flashlight_on: bool = false
var _has_flashlight: bool = false

# ─── FLASHLIGHT TAP-vs-HOLD INPUT ─────────────────────────────────────────
## Minimum hold duration (seconds) before the flashlight enters overcharge.
## Taps shorter than this toggle the flashlight ON/OFF. Holds at/above this
## activate the overcharge beam.
const FLASHLIGHT_OVERCHARGE_HOLD_TIME: float = 0.25

## Timestamp (seconds from Time.get_ticks_msec) when F was pressed.
var _flashlight_press_time: float = 0.0

## Whether the F key is currently held down.
var _flashlight_key_held: bool = false

## Whether the flashlight was ON before the current F press.
## Used to distinguish "tap to turn OFF" from "tap turned it ON, leave it ON".
var _flashlight_was_on_before_press: bool = false

# Crosshair
var _crosshair: Control

# Stair climbing state
var _was_on_floor: bool = false

# ─── TUTORIAL: Movement key detection ─────────────────────────────────
## Tracks which WASD/Ctrl keys the player has pressed so the tutorial
## only dismisses once each key has been pressed at least once.
## Uses edge-triggered detection via _input() rather than polling, so
## stale key presses from the main menu don't instantly dismiss the hint.
var _movement_keys_pressed: Dictionary = {}
var _movement_tutorial_ready: bool = false

# ─── RAYCAST THROTTLING ────────────────────────────────────────────────
## Frame counter for stair-step detection. Stair geometry doesn't change
## between frames, so we only need to check every 3rd physics frame (~20Hz
## instead of 60Hz). Reduces raycast cost by 66%.
var _stair_step_frame_counter: int = 0

## How many physics frames between stair-step raycasts.
const STAIR_STEP_CHECK_INTERVAL: int = 3

## Accumulator for flashlight-on-entity throttle (seconds).
## The flashlight beam detection uses an expensive intersect_ray from the
## camera to the Entity. We only need to check this at ~10Hz, not 60Hz.
var _flashlight_entity_check_timer: float = 0.0

## Interval between flashlight-on-entity raycasts in seconds.
const FLASHLIGHT_ENTITY_CHECK_INTERVAL: float = 0.1  # 10Hz

## Cached result of the last flashlight-on-entity check.
var _cached_flashlight_on_entity: bool = false

## Whether the player starts the game with the ability to sprint (SHIFT).
## When true (default), the player can sprint from the start.
## When false, the player must interact with the car alarm during Night 1
## to unlock sprinting. Set this in the inspector per-level.
@export var start_with_sprint: bool = true

## Whether the player starts the game with a flashlight already equipped.
## When true (default), the player can toggle the flashlight with F from
## the very start of the game without needing to find the flashlight pickup.
## When false, the player must find and pick up flashlight.tscn in the world
## before they can use the flashlight.
@export var start_with_flashlight: bool = true

## Whether the player starts the game with the Cabin Key in their inventory.
## When true, the player has the key_resource.tres added to their inventory
## at game start, allowing them to unlock the front door immediately.
## When false (default), the player must find the key in the world.
@export var start_with_key: bool = false

## Whether the player starts the game in "Dev Mode".
## When true, the NightManager's is_dev_mode is set to true, which:
##   - Unlocks sprint, flashlight, key, and all starting items
##   - Unlocks the front door
##   - Powers on the fuse box
##   - Fills the generator to 100%
##   - Unpauses time immediately
##   - Skips the Day 1 onboarding sequence
##   - Allows the Entity to approach windows on any night
## When false (default), the player must work through the full onboarding.
## Toggle this in the Player node's inspector for quick testing.
@export var start_in_dev_mode: bool = false


# Sprint unlock — enabled by default for development convenience
var sprint_unlocked: bool = true

# ─── SPRINT TUTORIAL LEARNED GUARD (BUG 3 FIX) ────────────────────
# Tracks whether the sprint tutorial has been dismissed by actual use.
# Prevents calling mark_learned("sprint") every physics frame while
# running. Learning is only marked once the player genuinely sprints.
var _sprint_tutorial_marked: bool = false


# --- STANDOFF / CHARGE MECHANIC ---
## How long the player has been staring at the Entity with the flashlight on.
## 0.0 = not looking, 1.5+ = Entity charges.
var look_timer: float = 0.0

## Throttle timer for periodic debug logging of flashlight/look state
var _look_debug_timer: float = 0.0

## Reference to the StandoffEffect node on the HUD
var _standoff_effect: Node = null

## Reference to the Entity node (found at runtime)
var _entity_node: Node = null

## Reference to the SanityController (cached once for performance)
var _sanity_controller: Node = null

## Reference to the Notebook UI (instantiated from notebook_ui.tscn)
@onready var _notebook: Control = $NotebookLayer/NotebookUI

# Stamina system
var _stamina: float = 100.0
var _max_stamina: float = 100.0
var _last_emitted_stamina_pct: float = -1.0  # Track last emitted value to avoid 60fps signal spam
var _is_running: bool = false
var _stamina_drain_rate: float = 5.625   # Points per second while running (62.5% slower than original 15.0)
var _stamina_regen_rate: float = 8.0    # Points per second while not running
var _stamina_exhausted: bool = false
var _stamina_exhausted_timer: float = 0.0
var _stamina_exhausted_delay: float = 1.5  # Seconds before regen starts after exhaustion
signal stamina_changed(stamina_percent: float)

# ─── STAMINA BREATHING AUDIO ─────────────────────────────────────────
## Looping audio player for heavy breathing when stamina < 50%.
## Created programmatically in _ready() to avoid scene node dependency.
var _breathing_audio: AudioStreamPlayer3D = null
var _breathing_audio_loaded: bool = false
var _breathing_fade_tween: Tween = null

## Looping audio player for slow breathing when stamina < 50% and NOT
## running. Plays at the same volume as the fast track.
var _breathing_slow_audio: AudioStreamPlayer3D = null
var _breathing_slow_loaded: bool = false
var _breathing_slow_fade_tween: Tween = null

## Looping audio stream for slow breathing when stamina < 50% and NOT running.
## Assign Breathing_slow.wav from res://assets/audio/player/ here.
@export var breathing_slow_sfx: AudioStream = null

# Noise system
var _noise_timer: float = 0.0

## Starting items to add to the player's inventory on game start.
## Drag ItemData resources (e.g. key_resource.tres, battery_resource.tres) here
## in the editor to give the player items at the beginning of the game.
@export var starting_items: Array[ItemData] = []

## Looping audio stream for heavy breathing when stamina < 50%.
## Assign Breathing_fast.wav from res://assets/audio/player/ here.
@export var breathing_sfx: AudioStream = null

func _ready() -> void:
	# Add starting items to the Inventory autoload
	for item in starting_items:
		if item:
			Inventory.add_item(item)
			print("[Player] Added starting item to inventory: ", item.item_name)
	
	# ─── SPRINT UNLOCK ──────────────────────────────────────────────
	# If start_with_sprint is true (default), the player can sprint from
	# the start. If false, sprint is locked and must be unlocked by
	# interacting with the car alarm during Night 1.
	sprint_unlocked = start_with_sprint
	if not sprint_unlocked:
		print("[Player] Sprint is LOCKED. Investigate the car alarm to unlock it.")
	
	_current_speed = walk_speed
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 1.2
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	
	# ─── BREATHING AUDIO INIT ─────────────────────────────────────────
	# Create a looping 3D audio player for heavy breathing at low stamina.
	# Uses the exported breathing_sfx AudioStream (assign in Inspector).
	if breathing_sfx:
		_breathing_audio = AudioStreamPlayer3D.new()
		if breathing_sfx is AudioStreamOggVorbis or "loop" in breathing_sfx:
			breathing_sfx.loop = true
		_breathing_audio.stream = breathing_sfx
		_breathing_audio.bus = "SFX"
		# ─── TASK: FAST BREATHING −6 dB (50% amplitude reduction) ──────
		# Was −10.0 dB. Halving the amplitude is a −6 dB cut, so the heavy
		# exhaustion breathing now plays at −16.0 dB (same as the slow track
		# so both sound consistent).
		_breathing_audio.volume_db = -16.0
		_breathing_audio.pitch_scale = 0.7
		_breathing_audio.max_db = 0.0
		add_child(_breathing_audio)
		_breathing_audio_loaded = true
		print("[Player] Breathing audio loaded (pitch=%s, vol=%s)." % [0.7, -16.0])
	
	# ─── SLOW BREATHING AUDIO (stamina < 50%, NOT running) ─────────────────
	# Loops while the player is low on stamina but recovering (walking or
	# idle). Plays at the SAME volume (−16.0 dB) and pitch (0.7) as the fast
	# track, so the two mix seamlessly when the player crosses the
	# run/not-run threshold.
	_breathing_slow_audio = AudioStreamPlayer3D.new()
	_breathing_slow_audio.name = "BreathingSlowAudio"
	var slow_stream: AudioStream = null
	if breathing_slow_sfx:
		slow_stream = breathing_slow_sfx
	else:
		slow_stream = load("res://assets/audio/player/Breathing_slow.wav") as AudioStream
	if slow_stream:
		if slow_stream is AudioStreamOggVorbis or "loop" in slow_stream:
			slow_stream.loop = true
		_breathing_slow_audio.stream = slow_stream
		_breathing_slow_audio.bus = "SFX"
		_breathing_slow_audio.volume_db = -16.0
		_breathing_slow_audio.pitch_scale = 0.7
		_breathing_slow_audio.max_db = 0.0
		add_child(_breathing_slow_audio)
		_breathing_slow_loaded = true
		print("[Player] Slow breathing audio loaded (pitch=%s, vol=%s)." % [0.7, -16.0])
	else:
		print("[Player] WARNING: Breathing_slow.wav not found. Slow breathing disabled.")
	
	# ─── FLASHLIGHT INIT ─────────────────────────────────────────────
	# If start_with_flashlight is true (default), the player can toggle the
	# flashlight with F from the very start. If false, the player must find
	# the flashlight pickup in the world first.
	if _flashlight:
		if start_with_flashlight:
			_has_flashlight = true
			_flashlight_on = false
			_flashlight.visible = false
			if _flashlight.has_method("toggle") and _flashlight.is_on:
				_flashlight.is_on = false
			print("[Player] Starting with flashlight equipped. Press F to toggle.")
		else:
			# Flashlight starts disabled until the player picks up flashlight.tscn
			_has_flashlight = false
			_flashlight.visible = false
			if _flashlight.has_method("toggle") and _flashlight.is_on:
				_flashlight.is_on = false
			print("[Player] Flashlight LOCKED. Find the flashlight pickup to unlock it.")
	
	# ─── KEY INIT ────────────────────────────────────────────────────
	# If start_with_key is true, add the Cabin Key to the player's inventory
	# at game start. This allows the player to unlock the front door immediately
	# without needing to find the key in the world.
	if start_with_key:
		var key_res = load("res://resources/key_resource.tres")
		if key_res:
			Inventory.add_item(key_res)
			print("[Player] Starting with Cabin Key in inventory. Front door is unlocked.")
		else:
			print("[Player] WARNING: Could not load key_resource.tres for start_with_key!")

	# ─── DEV MODE PROPAGATION ────────────────────────────────────────
	# If start_in_dev_mode is true, propagate it to NightManager so the
	# entire game system knows we're in dev mode. This unlocks sprint,
	# flashlight, key, all starting items, powers on the fuse box, fills
	# the generator, unpauses time, and skips the Day 1 onboarding sequence.
	if start_in_dev_mode:
		var nm = get_node_or_null("/root/NightManager")
		if nm:
			nm.is_dev_mode = true
			print("[Player] Dev Mode ENABLED via player scene export. NightManager.is_dev_mode = true.")
		else:
			print("[Player] WARNING: NightManager not found! Cannot propagate dev mode.")
	

	# ─── TUTORIAL: Movement prompt on first spawn (deferred) ──────────
	# Must be deferred because the HUD is not yet in the scene tree during _ready().
	call_deferred("_trigger_movement_tutorial")
	
	# Also defer the key detector startup to give the player time to see
	# the prompt before stale main-menu keys accidentally dismiss it.
	call_deferred("_enable_movement_tutorial")

	if _interaction_manager and _interaction_manager.has_method("set_camera"):
		_interaction_manager.set_camera(_camera)
	elif _interaction_manager:
		_interaction_manager.set("_camera", _camera)
	
	if _physical_grab and _physical_grab.has_method("set_camera"):
		_physical_grab.set_camera(_camera)
	elif _physical_grab:
		_physical_grab.set("_camera", _camera)
	
	# ─── NOTEBOOK UI ───────────────────────────────────────────────
	# Load and instance the notebook scene into the NotebookLayer CanvasLayer
	var notebook_scene = load("res://scenes/ui/notebook_ui.tscn")
	if notebook_scene:
		var notebook_instance = notebook_scene.instantiate()
		$NotebookLayer.add_child(notebook_instance)
		_notebook = notebook_instance
		notebook_instance.visible = false
		print("[Player] Notebook UI loaded and attached to NotebookLayer.")
	else:
		print("[Player] WARNING: Could not load notebook_ui.tscn!")
	
	_create_crosshair()
	get_viewport().size_changed.connect(_rebuild_crosshair)
	_step_interval = 2.0 / walk_speed

## Deferred tutorial trigger — runs after the HUD is in the scene tree.
func _trigger_movement_tutorial() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		tm.trigger("movement")


## Initializes the movement key tracker. Called deferred so stale key
## presses from the main menu don't instantly dismiss the prompt.
func _enable_movement_tutorial() -> void:
	_movement_keys_pressed = {
		KEY_W: false,
		KEY_A: false,
		KEY_S: false,
		KEY_D: false,
		KEY_CTRL: false,
	}
	_movement_tutorial_ready = true


func _create_crosshair() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var container = Control.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(container)
	var center_x = 0.5
	var center_y = 0.5
	var line_length = 0.012
	var line_width = 0.002
	var gap = 0.004
	var color = Color(1, 1, 1, 0.6)
	
	var top = ColorRect.new()
	top.color = color
	top.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	top.position = Vector2(get_viewport().size.x * center_x - top.size.x / 2, get_viewport().size.y * center_y - top.size.y - get_viewport().size.y * gap)
	container.add_child(top)
	
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	bottom.position = Vector2(get_viewport().size.x * center_x - bottom.size.x / 2, get_viewport().size.y * center_y + get_viewport().size.y * gap)
	container.add_child(bottom)
	
	var left = ColorRect.new()
	left.color = color
	left.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	left.position = Vector2(get_viewport().size.x * center_x - left.size.x - get_viewport().size.x * gap, get_viewport().size.y * center_y - left.size.y / 2)
	container.add_child(left)
	
	var right = ColorRect.new()
	right.color = color
	right.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	right.position = Vector2(get_viewport().size.x * center_x + get_viewport().size.x * gap, get_viewport().size.y * center_y - right.size.y / 2)
	container.add_child(right)
	_crosshair = container

func _rebuild_crosshair() -> void:
	if not _crosshair: return
	for child in _crosshair.get_children():
		_crosshair.remove_child(child)
		child.queue_free()
	
	var center_x = 0.5
	var center_y = 0.5
	var line_length = 0.012
	var line_width = 0.002
	var gap = 0.004
	var color = Color(1, 1, 1, 0.6)
	
	var top = ColorRect.new()
	top.color = color
	top.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	top.position = Vector2(get_viewport().size.x * center_x - top.size.x / 2, get_viewport().size.y * center_y - top.size.y - get_viewport().size.y * gap)
	_crosshair.add_child(top)
	
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(get_viewport().size.x * line_width, get_viewport().size.y * line_length)
	bottom.position = Vector2(get_viewport().size.x * center_x - bottom.size.x / 2, get_viewport().size.y * center_y + get_viewport().size.y * gap)
	_crosshair.add_child(bottom)
	
	var left = ColorRect.new()
	left.color = color
	left.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	left.position = Vector2(get_viewport().size.x * center_x - left.size.x - get_viewport().size.x * gap, get_viewport().size.y * center_y - left.size.y / 2)
	_crosshair.add_child(left)
	
	var right = ColorRect.new()
	right.color = color
	right.size = Vector2(get_viewport().size.x * line_length, get_viewport().size.y * line_width)
	right.position = Vector2(get_viewport().size.x * center_x + get_viewport().size.x * gap, get_viewport().size.y * center_y - right.size.y / 2)
	_crosshair.add_child(right)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_camera_holder.rotate_x(-event.relative.y * mouse_sensitivity)
		var rot = _camera_holder.rotation
		rot.x = clamp(rot.x, -1.4, 1.4)
		_camera_holder.rotation = rot
		
	
	# ─── DEBUG: Toggle mouse capture with AltGr (Right Alt) ──────────────
	if event is InputEventKey and event.physical_keycode == KEY_ALT and event.pressed and not event.echo:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# ─── TUTORIAL: Track WASD/Ctrl key presses (edge-triggered) ─────
	if _movement_tutorial_ready and not _movement_keys_pressed.is_empty():
		if event is InputEventKey and event.pressed:
			var keycode = event.keycode
			if keycode in _movement_keys_pressed and not _movement_keys_pressed[keycode]:
				_movement_keys_pressed[keycode] = true
				# Also accept C as alias for Ctrl
				if keycode == KEY_C and KEY_CTRL in _movement_keys_pressed:
					_movement_keys_pressed[KEY_CTRL] = true
				# Check if all keys are now pressed
				var all_pressed := true
				for v in _movement_keys_pressed.values():
					if not v:
						all_pressed = false
						break
				if all_pressed:
					var tm := get_node_or_null("/root/TutorialManager")
					if tm and tm.has_method("mark_learned"):
						tm.mark_learned("movement")
					# ─── TUTORIAL FLOW: Notebook after movement (deferred) ──
					# Delay the notebook trigger by 1 frame so the movement
					# hint's hide animation has time to process before the
					# notebook hint appears in the same label slot.
					if tm and tm.has_method("trigger"):
						tm.call_deferred("trigger", "notebook")
					_movement_keys_pressed.clear()  # prevent re-check
	
	if event is InputEventKey and event.keycode == KEY_F and not event.echo:
		if event.pressed:
			_flashlight_key_pressed()
		else:
			_flashlight_key_released()
	
	# ─── NOTEBOOK OPEN: Q/E flip pages, E is NOT interact ──────────
	if _notebook and _notebook.visible:
		if event.is_action_pressed("notebook_next_page"):
			print("[Player Input] E pressed while notebook open — forwarding to notebook._input()")
			_notebook._input(event)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("notebook_prev_page"):
			print("[Player Input] Q pressed while notebook open — forwarding to notebook._input()")
			_notebook._input(event)
			get_viewport().set_input_as_handled()
		# Absorb ALL actions while notebook is open (except movement/escape)
		if event.is_action_pressed("ui_interact"):
			print("[Player Input] E pressed while notebook open — BLOCKED interact")
			get_viewport().set_input_as_handled()
		return  # Block all further input processing
	

## Called by flashlight_pickup.gd when the player picks up the flashlight item.
## Enables the player's built-in flashlight so they can toggle it with F.
func enable_flashlight() -> void:
	_has_flashlight = true
	_flashlight_on = false
	if _flashlight:
		_flashlight.visible = false
		if _flashlight.has_method("toggle") and _flashlight.is_on:
			_flashlight.is_on = false
	print("[Player] Flashlight acquired! Press F to toggle.")

## Public API: Unlocks sprinting for the player.
## Called by escape_van.gd when the player investigates the car alarm
## during Night 1. This allows the sprint to be gated behind a narrative
## event when start_with_sprint is set to false in the inspector.
func unlock_sprint() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	
	if not sprint_unlocked:
		sprint_unlocked = true
		print("[Player] Sprint UNLOCKED! You can now hold SHIFT to run.")
		# ─── TUTORIAL: Sprint prompt ─────────────────────────────────
		# BUG 3 FIX: Do NOT call mark_learned("sprint") here. Marking it
		# learned consumes the one-shot tutorial before the Night 2.2
		# escape_van.gd trigger("sprint") at the entity-spawn moment can
		# display the hint. Learning is now only marked when the player
		# actually sprints (see _physics_process).
		if tm and tm.has_method("trigger"):
			tm.trigger("sprint")
	else:
		print("[Player] Sprint is already unlocked.")


## Resets the camera holder rotation and camera offsets to zero.
## Called by JumpscareManager after the jumpscare completes to fix
## the tilted camera issue on respawn.
##
## BUG 4 FIX: The old implementation set `_camera_holder.global_transform.basis
## = Basis.IDENTITY`, which decoupled the camera holder from the player body's
## yaw — leaving the camera facing the wrong way after respawn, then causing
## upside-down/spin-out camera movement (gimbal lock) once the mouse moved.
## The body uses yaw (CharacterBody3D.rotation.y) and the holder uses ONLY
## pitch. We reset BOTH fully and consistently:
##   - Camera holder local rotation → ZERO (pitch/roll/yaw all cleared).
##   - Body yaw → ZERO (so holder + body are re-aligned to world -Z).
##   - All mouse-look/clamp/state variables → cleared so the next mouse
##     movement starts from a clean basis (no cached/accumulated offsets).
func reset_camera() -> void:
	# ─── RESET BODY YAW ────────────────────────────────────────────
	# The player body carries yaw (rotate_y in _input). The jumpscare tween
	# hijacked the camera; after it, body yaw and camera basis disagree. Reset
	# the body to face world -Z so holder + body are consistent again.
	rotation = Vector3.ZERO

	# ─── RESET CAMERA HOLDER LOCAL ROTATION ────────────────────────
	# The holder carries ONLY pitch (rotate_x in _input). Zeroing local
	# rotation clears pitch/roll/yaw without touching the body transform.
	_camera_holder.rotation = Vector3.ZERO
	_camera_holder.rotation_degrees = Vector3.ZERO

	# ─── TASK 2 FIX: HARD RESET OF GLOBAL ROTATION/BASIS ───────────
	# The jumpscare tween may have written a global rotation on the holder
	# (via cam_holder.rotation:x). If the player body has a non-zero yaw at
	# that moment, the holder's GLOBAL basis disagrees with the body's local
	# yaw — leaving the camera facing the wrong way or upside-down (gimbal
	# lock / basis corruption) on restart. Zeroing the holder's GLOBAL
	# rotation too guarantees the body + holder are re-aligned to world -Z
	# regardless of any global-space tween that ran during the jumpscare.
	_camera_holder.global_rotation = Vector3.ZERO

	# ─── RESET MOUSE-LOOK STATE ────────────────────────────────────
	# No cached pitch/yaw accumulators exist today (rotation is applied
	# directly), but zeroing any related flags prevents a stale state from
	# surviving into the respawn. The _input() clamp (rot.x in -1.4..1.4)
	# will re-apply from a clean 0.0 pitch.
	_head_bob_time = 0.0

	# ─── RESET CAMERA OFFSETS & FOV ───────────────────────────────
	# The jumpscare shake modifies camera h_offset, v_offset, and FOV.
	# Restore them all to defaults so the player doesn't see a tilted/zoomed view.
	if _camera:
		# ─── TASK 2 FIX: RESET CAMERA LOCAL ROTATION & POSITION ────
		# The jumpscare tween could have left residual rotation on the Camera3D
		# node itself (Camera3D is a child of the holder). Zeroing the camera's
		# local rotation guarantees the view basis is perfectly clean. The head
		# bob system writes _camera.position each frame — reset it to ZERO so
		# the camera doesn't start off-center after restart.
		_camera.rotation = Vector3.ZERO
		_camera.position = Vector3.ZERO
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_camera.fov = 75.0


func _toggle_flashlight() -> void:
	if not _has_flashlight:
		# Show a hint that the player needs to find the flashlight first
		print("[Player] You don't have a flashlight yet! Find one in the cabin.")
		return
	if not _flashlight: return
	
	# ─── TUTORIAL: Flashlight learned ──────────────────────────────────
	# Only mark the mechanic as learned while a NIGHT is active. During
	# Day 1 daytime the player may pick up the flashlight and toggle it
	# before the "Press [F] to turn the flashlight on and off." hint has
	# been shown (it fires when Night 1 starts). Marking it learned during
	# the day consumed the one_shot tutorial, so `_can_show()` returned
	# false at the Night 1 trigger and the hint never appeared.
	#
	# TASK 2.3 FIX: SKIP mark_learned("flashlight") while the OVERCHARGE
	# tutorial is still active. Previously, pressing F at Nest Alpha (which
	# calls _toggle_flashlight → mark_learned("flashlight") → hide_hint())
	# instantly dismissed the "Hold [F] to OVERCHARGE" hint before the
	# 3-second hold completed. The overcharge hint must ONLY dismiss after
	# the player successfully holds F for the full duration.
	var tm := get_node_or_null("/root/TutorialManager")
	var nm := get_node_or_null("/root/NightManager")
	if tm and tm.has_method("mark_learned"):
		if nm and "is_night_active" in nm and nm.is_night_active:
			# ─── TASK 2.3: DO NOT dismiss the overcharge hint ──────────
			# If the player hasn't yet completed the overcharge tutorial
			# (3s continuous hold), skip the flashlight mark_learned so the
			# overcharge prompt stays visible. The overcharge hint can only
			# be dismissed by flashlight.gd's _mark_overcharge_tutorial_learned().
			if tm.has_method("is_learned") and not tm.is_learned("overcharge"):
				print("[Player] TASK 2.3: Overcharge tutorial still active. Skipping mark_learned('flashlight') to preserve the hold hint.")
			else:
				tm.mark_learned("flashlight")
	if _flashlight.has_method("toggle"):
		_flashlight.toggle()
	else:
		_flashlight_on = not _flashlight_on
		_flashlight.visible = _flashlight_on
	
	# ─── FLASHLIGHT AUDIO ───────────────────────────────────────────
	# Play a transient non-spatial sound when toggling the flashlight.
	# button_flashlight_1.ogg = ON, button_flashlight_2.ogg = OFF.
	# The AudioStreamPlayer is auto-freed when the sound finishes.
	var sfx_path := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Buttons & Levers/button_flashlight_1.ogg" if _flashlight.is_on else "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Buttons & Levers/button_flashlight_2.ogg"
	var sfx_stream := load(sfx_path)
	if sfx_stream:
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.bus = "SFX"
		sfx_player.stream = sfx_stream
		add_child(sfx_player)
		sfx_player.play()
		sfx_player.finished.connect(sfx_player.queue_free)
	
	print("[Player Flashlight] Toggled! is_on=%s visible=%s battery=%.1f" % [_flashlight.is_on, _flashlight.visible, _flashlight.get_battery_percent()])


## ─── FLASHLIGHT TAP vs HOLD ─────────────────────────────────────────────
## Called on F key press (edge-triggered, no echo).
## - Flashlight OFF → turn ON immediately (zero latency), track for hold.
## - Flashlight ON → defer the toggle decision to release or hold threshold.
func _flashlight_key_pressed() -> void:
	if not _has_flashlight or not _flashlight:
		# Show a hint that the player needs to find the flashlight first
		print("[Player] You don't have a flashlight yet! Find one in the cabin.")
		return
	
	_flashlight_key_held = true
	_flashlight_press_time = Time.get_ticks_msec() / 1000.0
	_flashlight_was_on_before_press = _flashlight.is_on
	
	if not _flashlight.is_on:
		# Turn ON immediately — zero input latency for the common action.
		_toggle_flashlight()


## Called every frame from _process() while F may be held. Once the hold
## duration reaches the overcharge threshold AND the flashlight is ON,
## activate the overcharge beam.
func _update_flashlight_overcharge(_delta: float) -> void:
	if not _flashlight_key_held or not _flashlight or not _has_flashlight:
		return
	if not _flashlight.is_on:
		return
	if _flashlight.is_overcharged:
		return  # Already overcharging
	
	var held_duration := (Time.get_ticks_msec() / 1000.0) - _flashlight_press_time
	if held_duration >= FLASHLIGHT_OVERCHARGE_HOLD_TIME:
		if _flashlight.has_method("activate_overcharge"):
			_flashlight.activate_overcharge()


## Called on F key release.
## - Overcharge was active → deactivate, flashlight stays ON.
## - Tap (< threshold) while flashlight was already ON → toggle OFF.
## - Tap while flashlight was OFF (turned ON on press) → stays ON.
func _flashlight_key_released() -> void:
	if not _flashlight_key_held:
		return  # Safety — release without a tracked press
	
	_flashlight_key_held = false
	
	if not _flashlight:
		return
	
	if _flashlight.is_overcharged:
		# Hold released overcharge — drop back to standard beam, keep light ON.
		if _flashlight.has_method("deactivate_overcharge"):
			_flashlight.deactivate_overcharge()
		return
	
	var held_duration := (Time.get_ticks_msec() / 1000.0) - _flashlight_press_time
	if held_duration < FLASHLIGHT_OVERCHARGE_HOLD_TIME and _flashlight_was_on_before_press:
		# Tap while the flashlight was already ON → toggle it OFF.
		_toggle_flashlight()
	# else: tap that just turned the light ON → it stays ON.


func _toggle_inventory() -> void:
	# ─── TUTORIAL: Inventory learned ───────────────────────────────────
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("mark_learned"):
		tm.mark_learned("inventory")
	
	var inv_ui = get_node_or_null("/root/CottageHorror/InventoryUI")
	if not inv_ui: inv_ui = get_node_or_null("/root/Main/InventoryUI")
	if inv_ui and inv_ui.has_method("_open_inventory") and inv_ui.has_method("_close_inventory"):
		if inv_ui.get("_is_open"): inv_ui._close_inventory()
		else: inv_ui._open_inventory()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity
		make_noise(15.0, 1.0) # Jumping is loud!

	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C):
		if not _is_crouching: _is_crouching = true
	else:
		if _is_crouching: _is_crouching = false
	

	# ─── SPRINT & STAMINA ──────────────────────────────────────────────
	# Sprint is only active when SHIFT is held AND the player is moving
	# forward (W, A, or D). Moving backwards (S) does NOT count as sprinting
	# — stamina only drains when sprinting in a forward direction.
	# This prevents the player from sprinting backwards away from the Entity,
	# which would feel unfair and break the horror tension.
	var _is_moving_forward = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
	_is_running = Input.is_key_pressed(KEY_SHIFT) and sprint_unlocked and not _is_crouching and _stamina > 0.0 and not _stamina_exhausted and _is_moving_forward
	
	# ─── BUG 3 FIX: MARK SPRINT TUTORIAL LEARNED ON ACTUAL USE ──────
	# The sprint hint (triggered by escape_van.gd during Night 2.2) is now
	# dismissed only when the player genuinely sprints — NOT when sprint is
	# merely unlocked (that premature mark consumed the one-shot before the
	# hint could show). Marking is one-shot via _sprint_tutorial_marked.
	if _is_running and not _sprint_tutorial_marked:
		_sprint_tutorial_marked = true
		var tm_sprint := get_node_or_null("/root/TutorialManager")
		if tm_sprint and tm_sprint.has_method("mark_learned"):
			tm_sprint.mark_learned("sprint")
	
	if _is_crouching: _current_speed = crouch_speed
	elif _is_running: _current_speed = run_speed
	else: _current_speed = walk_speed
	
	# --- STAMINA DRAIN / REGEN ---
	if _is_running:
		# Drain stamina only while sprinting forward (W, A, D — not S)
		_stamina -= _stamina_drain_rate * delta
		if _stamina <= 0.0:
			_stamina = 0.0
			_stamina_exhausted = true
			_stamina_exhausted_timer = 0.0
	elif _stamina_exhausted:
		# Wait for exhaustion delay before regen starts
		_stamina_exhausted_timer += delta
		if _stamina_exhausted_timer >= _stamina_exhausted_delay:
			_stamina_exhausted = false
	else:
		# Regen stamina when not running
		_stamina += _stamina_regen_rate * delta
		if _stamina > _max_stamina:
			_stamina = _max_stamina
	
	# ─── PERFORMANCE: Only emit stamina signal when value actually changes ──
	# Prevents 60fps signal spam when standing still with full stamina.
	var _new_stamina_pct = _stamina / _max_stamina * 100.0
	if _new_stamina_pct != _last_emitted_stamina_pct:
		_last_emitted_stamina_pct = _new_stamina_pct
		stamina_changed.emit(_new_stamina_pct)
	
	# ─── STAMINA BREATHING AUDIO ──────────────────────────────────────
	# Two mutually-exclusive tracks when stamina < 50%:
	#   FAST  — low stamina AND sprinting (heavy exhaustion breathing)
	#   SLOW  — low stamina AND NOT running (recovery breathing, same volume)
	# Both fade in over 0.5s and fade out over 1.0s. The FAST track was
	# lowered −6 dB (−10 → −16 dB) for a 50% amplitude reduction.
	var low_stamina: bool = _new_stamina_pct < 50.0
	var should_breathe_fast: bool = low_stamina and _is_running
	var should_breathe_slow: bool = low_stamina and not _is_running
	
	if _breathing_audio_loaded and _breathing_audio:
		if should_breathe_fast and not _breathing_audio.playing:
			_breathing_audio.volume_db = -80.0
			_breathing_audio.play()
			# Fade in over 0.5s — target is −16.0 dB (50% amplitude cut).
			if _breathing_fade_tween: _breathing_fade_tween.kill()
			_breathing_fade_tween = create_tween().set_parallel(true)
			_breathing_fade_tween.tween_property(_breathing_audio, "volume_db", -16.0, 0.5).set_ease(Tween.EASE_OUT)
		elif not should_breathe_fast and _breathing_audio.playing:
			# Fade out over 1.0s then stop
			if _breathing_fade_tween: _breathing_fade_tween.kill()
			_breathing_fade_tween = create_tween().set_parallel(true)
			_breathing_fade_tween.tween_property(_breathing_audio, "volume_db", -80.0, 1.0).set_ease(Tween.EASE_IN)
			_breathing_fade_tween.finished.connect(_on_breathing_fade_out)
	
	# ─── SLOW BREATHING (low stamina, NOT running) ──────────────────
	# Plays at the SAME volume (−16.0 dB) as the fast track, so the two
	# blend seamlessly when the player crosses the run/not-run threshold.
	if _breathing_slow_loaded and _breathing_slow_audio:
		if should_breathe_slow and not _breathing_slow_audio.playing:
			_breathing_slow_audio.volume_db = -80.0
			_breathing_slow_audio.play()
			if _breathing_slow_fade_tween: _breathing_slow_fade_tween.kill()
			_breathing_slow_fade_tween = create_tween().set_parallel(true)
			_breathing_slow_fade_tween.tween_property(_breathing_slow_audio, "volume_db", -16.0, 0.5).set_ease(Tween.EASE_OUT)
		elif not should_breathe_slow and _breathing_slow_audio.playing:
			# Fade out over 1.0s then stop
			if _breathing_slow_fade_tween: _breathing_slow_fade_tween.kill()
			_breathing_slow_fade_tween = create_tween().set_parallel(true)
			_breathing_slow_fade_tween.tween_property(_breathing_slow_audio, "volume_db", -80.0, 1.0).set_ease(Tween.EASE_IN)
			_breathing_slow_fade_tween.finished.connect(_on_breathing_slow_fade_out)

	var input_dir := Vector2(
		-1.0 if Input.is_key_pressed(KEY_A) else (1.0 if Input.is_key_pressed(KEY_D) else 0.0),
		-1.0 if Input.is_key_pressed(KEY_W) else (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	)
	
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * _current_speed
		velocity.z = direction.z * _current_speed
		_head_bob_active = true
		
		# ─── ACOUSTIC DETECTION: Movement Noise ──────────────────────────
		# The Entity can hear the player based on movement state:
		#   Sprinting: 20m radius, every 0.5s (loud, fast footsteps)
		#   Walking:   10m radius, every 0.6s (moderate, periodic footsteps)
		#   Crouching: Silent (0m) — no noise emitted
		#
		# Each noise call updates the Entity's last_known_position if the
		# Entity is within the noise radius. This is the core stealth mechanic:
		# crouching = invisible to sound, walking = risky, sprinting = beacon.
		if _is_running and is_on_floor():
			_noise_timer += delta
			if _noise_timer >= 0.5:
				make_noise(20.0, 0.5)  # Sprint: 20m radius
				_noise_timer = 0.0
		elif not _is_running and not _is_crouching and is_on_floor() and direction:
			# Walking noise — periodic footsteps at 10m radius
			_noise_timer += delta
			if _noise_timer >= 0.6:
				make_noise(10.0, 0.3)  # Walk: 10m radius
				_noise_timer = 0.0

	else:
		velocity.x = move_toward(velocity.x, 0, _current_speed)
		velocity.z = move_toward(velocity.z, 0, _current_speed)
		_head_bob_active = false
		_noise_timer = 0.0

	if stair_step_assist and _was_on_floor and direction.length() > 0 and is_on_floor():
		# ─── STAIR-STEP THROTTLING ───────────────────────────────
		# Stair geometry doesn't change between frames, so we only
		# fire the 3 raycasts every 3rd physics frame (~20Hz).
		# This cuts the raycast cost for stair detection by 66%.
		_stair_step_frame_counter += 1
		if _stair_step_frame_counter >= STAIR_STEP_CHECK_INTERVAL:
			_stair_step_frame_counter = 0
			_try_step_up(direction)

	var landed = not _was_on_floor and is_on_floor()
	if landed: make_noise(15.0, 1.0) # Thud on landing

	move_and_slide()
	_was_on_floor = is_on_floor()
	_update_crouch(delta)
	
	if velocity.length() > 0.5 and is_on_floor():
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_surface_footstep()
			# Dynamic footstep speed: when sprinting, footsteps play twice as fast
			# (interval cut in half) to match the increased movement speed.
			if _is_running and sprint_unlocked:
				_step_timer = _step_interval * 0.5
			else:
				_step_timer = _step_interval
	else:
		_step_timer = 0.0
	
	if head_bob_enabled and _head_bob_active and is_on_floor() and not _is_crouching:
		_head_bob_time += delta * _current_speed * head_bob_frequency
		var bob_offset = Vector3(head_bob_amplitude * cos(_head_bob_time * 0.5) * 0.3, head_bob_amplitude * sin(_head_bob_time), 0)
		_camera.position = bob_offset
	else:
		_head_bob_time = 0.0
		_camera.position = _camera.position.lerp(Vector3.ZERO, delta * 10.0)

func _try_step_up(direction: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state or not _collision_shape or not _collision_shape.shape: return
	
	var capsule: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
	var capsule_center_y = global_position.y + _collision_shape.position.y
	var capsule_bottom_y = capsule_center_y - capsule.height / 2.0
	
	var down_here_start = Vector3(global_position.x, capsule_bottom_y + 0.1, global_position.z)
	var down_here_end = Vector3(global_position.x, capsule_bottom_y - max_step_height - 0.5, global_position.z)
	var here_query = PhysicsRayQueryParameters3D.create(down_here_start, down_here_end)
	here_query.exclude = [self]
	
	var here_result = space_state.intersect_ray(here_query)
	if here_result.is_empty(): return
	var floor_y = here_result.position.y
	
	var ahead_pos = global_position + direction * (step_check_distance + capsule.radius * 0.5)
	var down_ahead_start = Vector3(ahead_pos.x, capsule_bottom_y + max_step_height + 0.5, ahead_pos.z)
	var down_ahead_end = Vector3(ahead_pos.x, capsule_bottom_y - 0.5, ahead_pos.z)
	var ahead_query = PhysicsRayQueryParameters3D.create(down_ahead_start, down_ahead_end)
	ahead_query.exclude = [self]
	
	var ahead_result = space_state.intersect_ray(ahead_query)
	if ahead_result.is_empty(): return
	var ahead_floor_y = ahead_result.position.y
	var step_height = ahead_floor_y - floor_y
	
	if step_height <= 0.01 or step_height > max_step_height: return
	
	var check_height = capsule_bottom_y + max_step_height + 0.1
	var check_start = Vector3(global_position.x, check_height, global_position.z)
	var check_end = check_start + direction * (step_check_distance + capsule.radius)
	var check_query = PhysicsRayQueryParameters3D.create(check_start, check_end)
	check_query.exclude = [self]
	
	if not space_state.intersect_ray(check_query).is_empty(): return
	
	velocity.y = sqrt(2.0 * get_gravity().length() * step_height) * 1.2
	global_position += direction * 0.02

func _play_surface_footstep() -> void:
	if not footstep_audio:
		return
	
	var room := get_player_room()
	var array: Array[AudioStream]
	
	if room == "Outside":
		array = grass_footsteps
	else:
		array = wood_footsteps
	
	if array.size() > 0:
		footstep_audio.stream = array.pick_random()
		footstep_audio.pitch_scale = randf_range(0.85, 1.15)
		footstep_audio.play()

func _update_crouch(delta: float) -> void:
	var target_height = crouching_height if _is_crouching else standing_height
	
	# ─── Resize CapsuleShape3D (if present) ──────────────────────────────
	if _collision_shape and _collision_shape.shape:
		var capsule: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
		if capsule:
			capsule.height = lerp(capsule.height, target_height, delta * crouch_transition_speed)
			var col_pos = _collision_shape.position
			col_pos.y = capsule.height / 2.0 + capsule.radius
			_collision_shape.position = col_pos
	
	# ─── Resize PrismCollider3D (if present) ─────────────────────────────
	if _prism_collider:
		_prism_collider.total_height = lerp(_prism_collider.total_height, target_height, delta * crouch_transition_speed)
	
	var target_cam_height = target_height - 0.1
	var cam_pos = _camera_holder.position
	cam_pos.y = lerp(cam_pos.y, target_cam_height, delta * crouch_transition_speed)
	_camera_holder.position = cam_pos

# --- CABIN ENTRY DETECTION ---
## Tracks whether the player has been detected inside the cabin.
## Used to notify RoutineManager when the player enters the cabin
## (fallback in case the door unlock trigger doesn't fire).
var _cabin_entry_reported: bool = false

## Tracks the player's previous room to detect transitions from "Outside" to inside.
## Starts as empty string ("") for first-frame calibration.
## On the first frame, _previous_room is set to the actual current room without
## triggering entry detection. This prevents false triggers when the player
## starts inside the cabin (e.g. dev mode spawn, death respawn, or scene reload).
var _previous_room: String = ""

# ─── EXHAUSTION MECHANIC (Day 3+) ──────────────────────────────────────
## When true, the player is physically broken after surviving a night of
## terror. Set by NightManager at dawn (Day 3+). Cleared by the Bed.
## While exhausted AND outside: 65% movement speed reduction + sprint lock.
## While exhausted AND inside: normal movement (player reached safety).
## All resource interactions are blocked while exhausted.
var is_exhausted: bool = false

## Cached original speeds — snapshotted on the first frame of exhaustion
## so they can be restored when the player sleeps in the bed.
var _exhausted_walk_speed: float = 0.0
var _exhausted_run_speed: float = 0.0

# Timer for throttling get_player_room() calls in _process (10Hz).
var _room_check_timer: float = 0.0

# Cached RoutineManager reference (avoids per-frame get_node_or_null).
var _routine_manager: Node = null



# --- STANDOFF / CHARGE: LOOK TIMER & CAMERA SHAKE ---
func _process(delta: float) -> void:
	# ─── FLASHLIGHT OVERCHARGE HOLD DETECTION ─────────────────────────
	# While F is held and the flashlight is ON, accumulate toward the
	# overcharge threshold. Runs in _process (not _physics_process) so
	# hold detection is smooth and independent of physics tick rate.
	_update_flashlight_overcharge(delta)
	
	# ─── EXHAUSTION SPEED PENALTY REMOVED (TASK 2.1) ────────────────────
	# The Day 3+ exhaustion mechanic no longer slows the player down.
	# This felt bad — the player was already punished enough by the night.
	# Instead, exhaustion now DISABLES interaction with scrap heaps, car
	# wrecks, the totem anchor, and notes (handled in each interactable's
	# get_interact_text() / interact() methods). Standard doors/locks
	# remain fully interactable.
	#
	# The original speed penalty has been completely removed. Movement
	# speed is never modified by exhaustion. The is_exhausted flag is
	# still tracked (set by NightManager, cleared by the Bed) so the
	# interactables can check it.
	if is_exhausted:
		pass  # No speed penalty — exhaustion blocks interactions instead

	# ─── CABIN ENTRY DETECTION ──────────────────────────────────────────
	# Check if the player has entered the cabin (fallback detection).
	# This is a safety net in case the door unlock trigger doesn't fire.
	# Only triggers on a transition from "Outside" to inside — the player
	# must physically walk through the door to trigger this. Starting inside
	# the cabin (e.g. after a death respawn) will NOT falsely trigger entry.
	if not _cabin_entry_reported:
		# PERFORMANCE: Throttle cabin entry checks to 5Hz
		_room_check_timer += delta
		if _room_check_timer >= 0.2:
			_room_check_timer = 0.0
			var room = get_player_room()
			
			# First frame calibration: _previous_room starts as "" (empty).
			# On the first frame, just record the current room without triggering
			# entry detection. This prevents false triggers when the player starts
			# inside the cabin (e.g. dev mode spawn, death respawn, or scene reload).
			if _previous_room == "":
				_previous_room = room
			# Only report entry if the player was previously "Outside" and is now inside.
			# The player must physically walk through the door to trigger this.
			elif _previous_room == "Outside" and room != "Outside":
				_cabin_entry_reported = true
				if not _routine_manager:
					_routine_manager = get_node_or_null("/root/RoutineManager")
				if _routine_manager and _routine_manager.has_method("on_player_entered_cabin"):
					_routine_manager.on_player_entered_cabin()
					print("[Player] Cabin entry detected via room check: ", room)
			_previous_room = room


	
	# Find the StandoffEffect node on the HUD (lazy init)

	if not _standoff_effect:
		var hud = get_node_or_null("/root/CottageHorror/HorrorHUD")
		if not hud:
			hud = get_node_or_null("/root/Main/HorrorHUD")
		if hud:
			_standoff_effect = hud.get_node_or_null("StandoffText")
	
	# Find the Entity node (lazy init)
	if not _entity_node:
		_entity_node = get_tree().get_first_node_in_group("entity")
	
	# ─── FLASHLIGHT-ON-ENTITY THROTTLING ──────────────────────────
	# The _is_flashlight_on_entity() function fires an expensive
	# intersect_ray from the camera to the Entity every call.
	# We only need to check this at ~10Hz (every 0.1s), not 60Hz.
	# Between checks, we use the cached result.
	_flashlight_entity_check_timer -= delta
	if _flashlight_entity_check_timer <= 0.0:
		_flashlight_entity_check_timer = FLASHLIGHT_ENTITY_CHECK_INTERVAL
		_cached_flashlight_on_entity = _is_flashlight_on_entity()
	
	# Check if the flashlight is ON and we're looking at the Entity
	var is_looking_at_entity = _cached_flashlight_on_entity
	
	# Throttled debug log every 2 seconds
	_look_debug_timer += delta
	if _look_debug_timer >= 2.0:
		_look_debug_timer = 0.0
		var ent_name = _entity_node.name if _entity_node else "null"
		var has_fl = _has_flashlight and _flashlight
		var fl_on = _flashlight.is_on if (has_fl and "is_on" in _flashlight) else false
	
	# ─── SANITY GAZE SHAKE ──────────────────────────────────────
	# Fetch the sanity gaze level from SanityController if available.
	if not _sanity_controller:
		var cam = _camera
		if cam and cam.has_node("SanityController"):
			_sanity_controller = cam.get_node("SanityController")
	var gaze_norm := 0.0
	if _sanity_controller and _sanity_controller.has_method("get_gaze_normalized"):
		gaze_norm = _sanity_controller.get_gaze_normalized()
	
	if is_looking_at_entity:
		# Increase look_timer while staring at the Entity with flashlight
		look_timer += delta
		
		# Clamp to max meaningful value (1.5s triggers charge)
		if look_timer > 2.0:
			look_timer = 2.0
		
		# Notify the Entity that it's being stared at (triggers STANDOFF state)
		# Pass is_overcharged so the Director knows whether this is the standard
		# beam (ignored indoors) or the overcharge beam (drives the standoff).
		if _entity_node and _entity_node.has_method("on_player_stare"):
			_entity_node.on_player_stare(look_timer, is_flashlight_overcharged())
	else:
		# Not looking at the Entity — decay look_timer
		if look_timer > 0.0:
			look_timer -= delta * 2.0  # Decay twice as fast as it builds
			if look_timer < 0.0:
				look_timer = 0.0
			
			# Notify the Entity that stare is ending — clear overcharge flag
			if _entity_node and _entity_node.has_method("on_player_stare"):
				_entity_node.on_player_stare(look_timer, is_flashlight_overcharged())
	
	# ─── COMBINED CAMERA SHAKE (TASK 3 AMPLIFIED) ────────────────
	# Takes the MAX of flashlight stare intensity and sanity gaze
	# intensity, so both systems contribute independently.
	# TASK 3: The shake now RAMP-UPS the longer the player stares at
	# the Entity (up to 1.6x after 3 seconds) and adds a low-frequency
	# rumble (~4Hz) for an increasingly violent feel. The darkness
	# overlay was removed, so this camera shake is the primary visual
	# feedback for staring.
	var flashlight_intensity := look_timer / 1.5  # 0.0→1.0 at 1.5s
	var shake_intensity := maxf(flashlight_intensity, gaze_norm)
	
	if shake_intensity > 0.05:
		# ─── RAMP-UP FACTOR ─────────────────────────────────────────
		# Intensity ramps from 1.0x to 1.6x over 3 seconds of continuous
		# staring. The longer the player holds the gaze, the more violent
		# the shake becomes — no hard cutoff, just escalating dread.
		var stare_ramp := minf(look_timer / 3.0, 1.0)
		var ramped_intensity := shake_intensity * (1.0 + 0.6 * stare_ramp)
		
		# ─── AMPLIFIED HIGH-FREQUENCY SHAKE ─────────────────────────
		# Increased from 0.04 to 0.07 radians (~4.0° max) so the shake
		# is visibly more aggressive at peak.
		var shake := ramped_intensity * 0.07
		_camera.h_offset = randf_range(-shake, shake)
		_camera.v_offset = randf_range(-shake, shake)
		
		# ─── LOW-FREQUENCY RUMBLE (≈4Hz) ────────────────────────────
		# A slow rolling sine wave that grows with gaze duration, layered
		# on top of the high-frequency jitter. This feels like the camera
		# is physically being disturbed rather than just twitching.
		var rumble_t := Time.get_ticks_msec() / 1000.0
		var rumble := sin(rumble_t * TAU * 4.0) * 0.02 * shake_intensity
		_camera.h_offset += rumble
		_camera.v_offset += rumble * 0.7
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	
	# Update the StandoffEffect with the current look_timer
	if _standoff_effect and _standoff_effect.has_method("update_look_timer"):
		_standoff_effect.update_look_timer(look_timer)
	
	# ─── OVERCHARGE UI ESCALATION ─────────────────────────────────────
	# Forward the overcharge state to the StandoffEffect so it can amplify
	# the hallucination visuals/audio during the indoor standoff.
	if _standoff_effect and _standoff_effect.has_method("update_overcharge"):
		_standoff_effect.update_overcharge(is_flashlight_overcharged())


## Checks if the player's flashlight is currently shining on the Entity.
## Uses a RayCast3D from the center of the camera to detect the Entity.
func _is_flashlight_on_entity() -> bool:
	# Flashlight must be on
	if not _flashlight or not _has_flashlight:
		return false
	if not _flashlight.is_on:
		return false
	
	if not _entity_node or not is_instance_valid(_entity_node):
		return false
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return false
	
	# ─── STEP 1: VISION CONE (dot product) ────────────────────────
	# The player must be looking roughly at the Entity.
	# Standard beam: dot > 0.95 = ~18° cone — matches the flashlight beam.
	# Overcharge beam: dot > 0.985 = ~10° cone — tighter, rewards precision.
	var cam_forward = -_camera.global_transform.basis.z.normalized()
	var entity_target = _entity_node.global_position + Vector3(0, 1.0, 0)
	var dir_to_entity = (entity_target - _camera.global_position).normalized()
	
	var cone_dot_threshold: float = 0.95
	if _flashlight and _flashlight.is_overcharged:
		cone_dot_threshold = 0.985
	
	if cam_forward.dot(dir_to_entity) < cone_dot_threshold:
		return false
	
	# ─── STEP 2: OCCLUSION RAYCAST ────────────────────────────────
	# Cast from camera toward the Entity's chest.
	# collision_mask = 17  → Layer 1 (world/cabin) | Layer 5 (entity)
	# If the ray hits a wall before the Entity, is_player_spotting fails.
	var query = PhysicsRayQueryParameters3D.create(
		_camera.global_position,
		entity_target
	)
	query.exclude = [self]
	query.collision_mask = 17  # Layer 1 (world) | Layer 5 (entity) = 1 | 16
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	
	var collider = result.collider
	return collider != null and collider.is_in_group("entity")


## Public API: returns true if the player's flashlight is currently on.
## Called by entity_sensory.gd to check flashlight state without string-based property access.
func is_flashlight_on() -> bool:
	return _has_flashlight and _flashlight != null and _flashlight.is_on


## Public API: returns true if the flashlight is currently in overcharge mode.
## Forwarded to the Entity's on_player_stare() so the Director can distinguish
## the standard beam (ignored indoors) from the overcharge beam (standoff).
func is_flashlight_overcharged() -> bool:
	return _has_flashlight and _flashlight != null and _flashlight.is_overcharged


## Returns true if the player is currently crouching.
## Used by the Entity's sensory system (entity_sensory.gd) to apply the
## crouch visibility multiplier — crouching players are much harder to see
## in the dark (vision range reduced to 20% of normal).
func is_crouching() -> bool:
	return _is_crouching


## Returns the name of the room the player is currently in, or "Outside" if
## the player is not inside any registered cabin interior area.
## Uses CabinRoom nodes in the "Cabin_Interior" group. The room name is taken
## from CabinRoom.get_room_name() which respects the room_name_override export.
##
## NOTE: This method now prefers CabinRoom nodes (which have the room_light
## reference) over plain Area3D nodes. If a CabinRoom is found, its
## get_room_name() is used. Falls back to the node's name for legacy areas.
func get_player_room() -> String:
	var cabin_interiors = get_tree().get_nodes_in_group("Cabin_Interior")
	
	for area in cabin_interiors:
		if area is Area3D:
			# Check if the Player (self) is inside this area
			if area.overlaps_body(self):
				# Use CabinRoom.get_room_name() if available, else node name
				if area.has_method("get_room_name"):
					return area.get_room_name()
				return area.name
	
	return "Outside"



# --- NEW NOISE SYSTEM EMITTER ---
func make_noise(radius: float, intensity: float = 1.0) -> void:
	var entity = get_tree().get_first_node_in_group("entity")
	if entity and entity.has_method("hear_noise"):
		entity.hear_noise(global_position, radius, intensity)


## Called when the breathing audio fade-out tween finishes.
## Stops the breathing audio player after the fade completes.
func _on_breathing_fade_out() -> void:
	if _breathing_audio and _breathing_audio.playing:
		_breathing_audio.stop()

## Called when the SLOW breathing audio fade-out tween finishes.
## Stops the slow breathing player after the fade completes.
func _on_breathing_slow_fade_out() -> void:
	if _breathing_slow_audio and _breathing_slow_audio.playing:
		_breathing_slow_audio.stop()
