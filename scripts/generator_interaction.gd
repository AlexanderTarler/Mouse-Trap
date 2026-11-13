extends Area3D

## The generator's interaction point: a tap of E switches it on or off
## (Generator.toggle_switch), holding E with a fuel can refills it.
## Attach this script to an Area3D node placed on the physical generator model.
##
## HOLD-TO-REFUEL MECHANIC:
##   PhysicalGrab (physical_grab.gd) detects when the player looks at this
##   generator and holds E. On E press, PhysicalGrab calls start_refuel().
##   On E release, PhysicalGrab calls stop_refuel(). The continuous fuel
##   transfer runs in _process() while _is_refueling is true.
##
##   This mirrors how the door's toggle_lock works: PhysicalGrab tracks the
##   hold, and the target object responds to start/stop signals.
##
##   Fuel scaling:
##     - One fuel can holds FUEL_PER_CAN (50.0) units of generator fuel.
##     - The NightManager's max_fuel is 100.0 (two full cans = full tank).
##     - Hold E for 10 seconds = one full can consumed = 50 units transferred.
##     - Hold E for 2 seconds = 20% of a can = 10 units = 20% of generator.

## How many seconds the player must hold E to fully drain one fuel can.
## Default: 10.0 seconds (2s hold = 20% of a can = 10 fuel units).
@export var refuel_duration_per_can: float = 10.0

## The refill and "Turn on the generator" objectives both highlight the
## whole `xray_generator` group (the generator body).

## How many fuel units one fuel can contains (matches NightManager's fuel scale).
const FUEL_PER_CAN: float = 50.0

## ─── REFUEL SOUND EFFECT ─────────────────────────────────────────────
## Looping audio stream played while the player holds E to refill the
## generator. Assign "res://assets/audio/objects/refuel_generator.ogg"
## (or equivalent) in the Inspector on generator_interaction.tscn.
## Falls back to a hardcoded path if left null.
@export var refuel_sound_stream: AudioStream = null

## Fallback path used if refuel_sound_stream is not assigned in the Inspector.
## NOTE: The actual asset lives in assets/audio/objects/ (not assets/audio/Generator/).
const REFUEL_SOUND_DEFAULT_PATH: String = "res://assets/audio/objects/refuel_generator.ogg"

## Volume (dB) for the refuel loop while playing.
@export var refuel_sound_volume_db: float = -8.0

## Lazily-created AudioStreamPlayer3D for the refuel loop.
var _refuel_audio: AudioStreamPlayer3D = null

## Cache whether the refuel audio stream was successfully loaded.
var _refuel_audio_loaded: bool = false

## Cached reference to the NightManager.
var _nm: Node = null

## Accumulated hold time for the current fuel can transfer (seconds).
## Resets to 0.0 when a new can is selected or refueling stops.
var _hold_time: float = 0.0

## The fuel can ItemData currently being drained from inventory.
var _active_fuel_can = null

## Whether the player is currently holding E and refueling is active.
## Set to true by start_refuel(), set to false by stop_refuel().
## The _process() loop transfers fuel while this is true.
var _is_refueling: bool = false

## Progress from 0.0 to 1.0 within the current fuel can.
## Shown to the player via UI to indicate how much of the current can has been used.
var _can_progress: float = 0.0

## Seconds E is held before fuel starts flowing: a tap (which switches the
## generator on or off) doesn't spill any.
const TAP_GRACE := 0.25
var _held := 0.0
## Fuel went in during this press of E (then letting go doesn't switch it).
var _refuelled_this_press := false

## Whether on_generator_refilled() has been called for this refuel session.
## Ensures the objective notification fires only once per session (on first
## successful fuel transfer), not every frame or only when the tank is full.
var _refuel_notified: bool = false


func _ready() -> void:
	add_to_group("xray_generator")
	_nm = get_node_or_null("/root/NightManager")
	# BUG 1 FIX: Layer 2 ("Interactable") — the interaction ray only raycasts
	# against layer 2, so this Area must be ON layer 2 to be reachable.
	collision_layer = 2
	_setup_refuel_audio()


func _process(delta: float) -> void:
	if not _is_refueling or not _active_fuel_can:
		return
	if not _nm:
		stop_refuel()
		return
	_held += delta
	if _held < TAP_GRACE:
		return
	if not _refuelled_this_press:
		_refuelled_this_press = true
		_start_refuel_audio()
	
	# ─── GENERATOR FULL CHECK ─────────────────────────────────────────
	if _nm.generator_fuel >= _nm.max_fuel:
		print("[Generator] Generator is full. Refuel complete.")
		stop_refuel()
		return
	
	# ─── TASK 1: PROPORTIONAL FUEL CAN DEPLETION ─────────────────────
	# The generator consumes exactly `fuel_to_add` generator units this
	# frame (clamped so it never exceeds the tank's remaining space OR
	# the can's remaining fuel). For every 1 unit of generator fuel, the
	# can loses 2 can-units (2% of its 100-unit capacity). The can's
	# per-instance fuel_amount is decremented in place; when it reaches
	# 0 the can is consumed from inventory and the next can (if any)
	# is auto-selected. Stopping mid-can now correctly preserves the
	# partially-depleted can (fuel_amount persists on the instance).
	var transfer_rate: float = FUEL_PER_CAN / refuel_duration_per_can
	
	# Raw transfer this frame (generator units)
	var fuel_to_add: float = transfer_rate * delta
	
	# Clamp to remaining generator capacity
	var gen_space: float = _nm.max_fuel - _nm.generator_fuel
	fuel_to_add = minf(fuel_to_add, gen_space)
	
	# Clamp to remaining fuel in the current can
	# (1 generator unit = 2 can-units, so max transfer = fuel_amount / 2.0)
	var can_max_transfer: float = _active_fuel_can.fuel_amount / 2.0
	fuel_to_add = minf(fuel_to_add, can_max_transfer)
	
	if fuel_to_add <= 0.0:
		if gen_space <= 0.0:
			print("[Generator] Generator is full. Refuel complete.")
			stop_refuel()
		return
	
	_nm.generator_fuel = minf(_nm.generator_fuel + fuel_to_add, _nm.max_fuel)
	_nm.fuel_changed.emit(_nm.generator_fuel)
	
	# ─── DEPLETE THE CAN: 2 can-units per 1 generator unit ──────────
	_active_fuel_can.fuel_amount -= fuel_to_add * 2.0
	
	# ─── CAN EMPTY: CONSUME AND SELECT NEXT ─────────────────────────
	if _active_fuel_can.fuel_amount <= 0.0:
		print("[Generator] Fuel can fully drained (%.1f generator units transferred)." % fuel_to_add)
		Inventory.remove_item(_active_fuel_can)
		
		# Look for another can with fuel to continue
		_active_fuel_can = _find_fuel_can_in_inventory()
		if _active_fuel_can:
			print("[Generator] Found another fuel can. Continuing refuel...")
		else:
			print("[Generator] No more fuel cans with fuel. Refuel stopped.")
			stop_refuel()
			return
	
	# ─── NOTIFY ROUTINE MANAGER AT 40% FUEL ──────────────────────────
	# The objective "Refuel the generator" should complete when the
	# generator has received at least 40 units (40% of max_fuel).
	# This prevents the notification from firing on the first frame of
	# refueling when only 0.05 units have been transferred.
	var _forty_pct_threshold: float = 40.0  # 40% of max_fuel
	if not _refuel_notified and _nm.generator_fuel >= _forty_pct_threshold:
		_refuel_notified = true
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_generator_refilled"):
			rm.on_generator_refilled()
			print("[Generator] Notified RoutineManager: generator refueled (%.1f units >= 40.0 threshold)." % _nm.generator_fuel)
	
	# ─── NOTIFY IF GENERATOR IS NOW FULL ─────────────────────────────
	if _nm.generator_fuel >= _nm.max_fuel:
		print("[Generator] Generator is now full!")
		stop_refuel()


## ─── REFUEL AUDIO SETUP ─────────────────────────────────────────────
## Lazy-creates an AudioStreamPlayer3D for the refuel loop. Uses the
## exported refuel_sound_stream if assigned, otherwise falls back to the
## hardcoded REFUEL_SOUND_DEFAULT_PATH. The stream is set to loop.
func _setup_refuel_audio() -> void:
	if _refuel_audio:
		return
	_refuel_audio = get_node_or_null("RefuelAudio")
	if not _refuel_audio:
		_refuel_audio = AudioStreamPlayer3D.new()
		_refuel_audio.name = "RefuelAudio"
		add_child(_refuel_audio)
	if not _refuel_audio:
		push_warning("[Generator] Could not create refuel audio player.")
		return
	_refuel_audio.bus = "SFX"
	_refuel_audio.volume_db = refuel_sound_volume_db
	_refuel_audio.max_db = 0.0
	_refuel_audio.unit_size = 8.0  # Audible from a few meters away
	
	var stream := refuel_sound_stream
	if not stream:
		stream = load(REFUEL_SOUND_DEFAULT_PATH) as AudioStream
	if not stream:
		push_warning("[Generator] Could not load refuel sound from '%s'." % REFUEL_SOUND_DEFAULT_PATH)
		return
	_refuel_audio.stream = stream
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_refuel_audio_loaded = true
	print("[Generator] Refuel audio ready.")


## Starts the looping refuel sound. No-op if the stream failed to load.
func _start_refuel_audio() -> void:
	if not _refuel_audio:
		return
	if not _refuel_audio.stream:
		return
	if not _refuel_audio.playing:
		_refuel_audio.play()
		print("[Generator] Refuel sound loop started.")


## Stops the looping refuel sound immediately. No-op if not playing.
func _stop_refuel_audio() -> void:
	if _refuel_audio and _refuel_audio.playing:
		_refuel_audio.stop()
		print("[Generator] Refuel sound loop stopped.")


## Called by PhysicalGrab when the player presses E while looking at this generator.
## While refuelling: how full the tank is, for the crosshair's ring (-1: not refuelling).
func get_hold_progress() -> float:
	if not _is_refueling or not _active_fuel_can or not _nm:
		return -1.0
	return _nm.generator_fuel / _nm.max_fuel


## Starts the continuous fuel transfer. Does NOT check inventory — if no fuel can
## is available, _process() does nothing and returns harmlessly.
func start_refuel() -> void:
	if not _nm:
		print("[Generator] ERROR: NightManager not found!")
		return
	
	# ─── CONNECTION PUZZLE REMOVED (Request 3) ──────────────────────
	# The legacy portable-light connection puzzle (consume Cable Spool +
	# Portable Light + spawn lamp) has been moved OUT of this generator
	# refuel interaction. The new flow (Request 3):
	#   1. Player picks up the Portable Light into inventory (portable_lamp.gd).
	#   2. Player interacts with the GENERATOR OUTLET node (generator_outlet.gd),
	#      which consumes Cable Spool + Portable Light, spawns the lamp, and
	#      physically grabs it for the player to carry.
	#   3. The player drops the lamp and connects the free cable end.
	# This generator refuel point no longer consumes those items.
	
	if _is_refueling:
		return
	_refuelled_this_press = false
	_held = 0.0
	
	if _nm.generator_fuel >= _nm.max_fuel:
		print("[Generator] Generator is already full.")
		return
	
	_active_fuel_can = _find_fuel_can_in_inventory()
	if not _active_fuel_can:
		print("[Generator] I need a Fuel Can to refill the generator.")
		return
	
	# ─── BUG 2 FIX: CLEAR X-RAY HIGHLIGHT ON E PRESS ──────────────
	# As soon as the player commits to refueling (holds E), the x-ray
	# highlight on the generator (and its switch) should vanish so the
	# player can see the physical interaction. Previously the highlight
	# persisted until the refuel completed (or the player stopped).
	var rm_highlight = get_node_or_null("/root/RoutineManager")
	if rm_highlight and rm_highlight.has_method("clear_highlight"):
		rm_highlight.clear_highlight("xray_generator")
	
	_is_refueling = true
	_hold_time = 0.0
	_can_progress = 0.0
	print("[Generator] Refuel started. Rate: %.1f units/sec (%.1fs per can)." % [FUEL_PER_CAN / refuel_duration_per_can, refuel_duration_per_can])


## Pushes a text message to the HUD overlay.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg, self)
	else:
		print("[Generator HUD]: ", msg)


## Called by PhysicalGrab when the player releases E while refueling.
## Also called by _process() when refueling completes.
## The current fuel can is preserved (not partially consumed) in inventory.
func stop_refuel() -> void:
	if not _is_refueling:
		return
	_is_refueling = false
	_active_fuel_can = null
	_hold_time = 0.0
	_can_progress = 0.0
	_stop_refuel_audio()
	print("[Generator] Refuel stopped. Partial can preserved in inventory.")


## Called by PhysicalGrab when the player quick-taps E: the generator goes
## on or off (unless the tap was long enough to pour some fuel in).
func interact() -> void:
	if _refuelled_this_press:
		_refuelled_this_press = false
		return
	var generator := _generator()
	if generator:
		generator.toggle_switch()


func _generator() -> Generator:
	return get_parent() as Generator


## Returns the current fuel percentage from NightManager, or 0 if unavailable.
func _get_fuel_percent() -> int:
	if _nm and _nm.max_fuel > 0:
		return int((_nm.generator_fuel / _nm.max_fuel) * 100.0)
	return 0

## Called by the InteractionManager to display the HUD prompt: switching it
## (a tap) and refilling it (a hold), as they apply.
func get_interact_text() -> String:
	var refill := _refill_text()
	var generator := _generator()
	if generator == null or (_is_refueling and _refuelled_this_press):
		return refill
	var switch := generator.get_interact_text()
	var can_refill := refill.begins_with("[")
	if switch.begins_with("["):
		return switch + "\n" + refill if can_refill else "%s (%d%% fuel)" % [switch, _get_fuel_percent()]
	# It can't be switched on yet: refilling it, if that's possible, else why.
	return refill if can_refill else switch


func _refill_text() -> String:
	var fuel_pct: int = _get_fuel_percent()
	if _nm and _nm.generator_fuel >= _nm.max_fuel:
		return "Generator (full)"
	if _is_refueling:
		# ─── BUG 3 FIX: SHOW GENERATOR'S TOTAL FUEL PERCENTAGE ────────
		# Previously this used _can_progress (per-can progress) which
		# restarted from 0% every time a new fuel can was selected or the
		# player stopped and resumed. Now it shows the generator's actual
		# fuel percentage so the number always reflects the real fill level.
		return "Refuelling... %d%%" % fuel_pct
	if not _find_fuel_can_in_inventory():
		return "Generator: %d%% fuel (no fuel can)" % fuel_pct
	return "[Hold E] Refill Generator (%d%% fuel)" % fuel_pct


## Searches the player's inventory for a Fuel Can item.
## TASK 1: Skips cans that have been fully drained (fuel_amount <= 0),
## so only cans with remaining fuel are eligible for refueling.
func _find_fuel_can_in_inventory():
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Fuel Can":
			if "fuel_amount" in item and item.fuel_amount > 0.0:
				return item
	return null
