extends StaticBody3D
class_name Generator

## Generator — Central power management for the cabin's electrical grid.
##
## Attach this script to the root node of generator.tscn.
## Controls the fuel drain rate of the generator with separate public
## variables for cabin lights and the porch light, making it easy to
## tweak the drain balance directly in the editor.
##
## HOW IT WORKS:
##   The NightManager calls recalculate_fuel_drain() whenever a light is
##   toggled or the generator state changes. This script overrides that
##   calculation by providing the total drain rate based on which lights
##   are currently switched on.
##
##   Cabin lights each contribute cabin_light_drain_rate when switched on.
##   The porch light (is_faulty = true) contributes porch_light_drain_rate
##   when the generator is running (it's permanently stuck ON).

## Fuel drain rate per cabin light (fuel units per second).
## Each interior light that is switched ON adds this much drain.
## Default: 0.5 fuel units per second per light.
@export var cabin_light_drain_rate: float = 0.5

## Fuel drain rate for the porch light (fuel units per second).
## The porch light is faulty (is_faulty = true) and permanently stuck ON
## whenever the generator is running. This drain is always active as long
## as the generator has fuel.
## Default: 0.3 fuel units per second.
@export var porch_light_drain_rate: float = 0.3

## Base fuel drain rate (fuel units per second).
## The minimum drain that occurs just from the generator running, even if
## no lights are switched on. Represents standby power loss / idle draw.
## Default: 0.12 fuel units per second.
@export var base_drain_rate: float = 0.12

## Starting fuel percentage (0.0 to 100.0).
## Controls how much fuel the generator has at the start of the game.
## Set this in the Inspector on generator.tscn to configure the initial
## fuel level without modifying code. Default: 100.0 (full tank).
## The NightManager reads this value during _ready() to set generator_fuel.
@export var starting_fuel_percent: float = 100.0

## Volume (dB) for the generator's looping audio.
## Set this in the Inspector on generator.tscn to control loudness.
## Default: -12.0 dB — quiet hum that doesn't overpower gameplay sounds.
@export var generator_audio_volume_db: float = -12.0

## Path to the generator's looping audio stream.
## Override this in the Inspector on generator.tscn if you want a different sound.
## Default: res://assets/audio/Electric/machine_mx_1_loop.ogg
@export var generator_audio_stream_path: String = "res://assets/audio/Electric/machine_mx_1_loop.ogg"

# ─── AUDIO ──────────────────────────────────────────────────────────
var _generator_audio: AudioStreamPlayer3D = null
var _audio_loaded: bool = false

# ─── GENERATOR SWITCH ────────────────────────────────────────────────
## Whether the physical On/Off switch on the generator is toggled ON.
## The generator only runs when BOTH switch is ON AND fuel > 10%.
## Automatically toggles OFF when fuel runs out (auto-shutdown).
var is_switched_on: bool = false

## Minimum fuel percentage required to start the generator.
## If fuel is below this threshold, toggle_switch() refuses to turn on.
const MIN_START_FUEL_PERCENT: float = 10.0

# ─── FUEL INDICATOR LIGHT ───────────────────────────────────────────
var _fuel_light: OmniLight3D = null

## Blink accumulator for the 1-10% range (delta-based).
var _blink_timer: float = 0.0

## Whether the indicator light is currently visible (toggled for blink).
var _light_visible: bool = true

## Whether the generator audio was playing last frame (tracks transitions).
var _audio_was_playing: bool = false

## Cached NightManager reference for non-null-safe access in _process.
var _nm_cache: Node = null


func _ready() -> void:
	add_to_group("generator_controller")
	add_to_group("xray_generator")
	
	_nm_cache = get_node_or_null("/root/NightManager")
	
	# Cache the AudioStreamPlayer3D child (added via generator.tscn)
	_generator_audio = get_node_or_null("GeneratorAudio")
	if _generator_audio:
		_generator_audio.volume_db = generator_audio_volume_db
		var stream := load(generator_audio_stream_path)
		if stream:
			_generator_audio.stream = stream
			_generator_audio.bus = "SFX"
			_generator_audio.max_db = 0.0
			# ─── PROGRAMMATIC LOOP FALLBACK ──────────────────────────────────
			# Force loop mode on the audio stream regardless of import settings.
			# This ensures the generator hum loops seamlessly even if the .import
			# file has loop=false. Matches the pattern used in entity_controller.gd
			# for chase music and night ambience.
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			elif "loop_mode" in stream and stream.has_method("set"):
				stream.loop_mode = 0  # LOOP_FORWARD for WAV streams
			_audio_loaded = true
			print("[Generator] Audio loaded: '%s' at %.1f dB (volume_db=%+.0f dB)" % [generator_audio_stream_path, generator_audio_volume_db, generator_audio_volume_db])
		else:
			push_warning("[Generator] Could not load audio from path: '%s'" % generator_audio_stream_path)
	else:
		push_warning("[Generator] No GeneratorAudio node found as child.")
	
	# Cache the OmniLight3D child (added via generator.tscn)
	_fuel_light = get_node_or_null("FuelIndicatorLight")
	if _fuel_light:
		_fuel_light.visible = false
	
	print("[Generator] Initialized. Base drain: %.2f, Cabin light drain: %.2f, Porch light drain: %.2f, Starting fuel: %.0f%%" % [base_drain_rate, cabin_light_drain_rate, porch_light_drain_rate, starting_fuel_percent])


func _process(delta: float) -> void:
	_update_audio(delta)
	_update_fuel_indicator(delta)


## Updates the generator looping audio. Plays when BOTH conditions are met:
##   A. The generator has fuel (generator_fuel > 0)
##   B. The power is on (is_generator_on == true, meaning porch light is active)
## Stops when either condition fails.
func _update_audio(_delta: float) -> void:
	if not _audio_loaded or not _generator_audio:
		return
	
	var nm := get_node_or_null("/root/NightManager")
	if not nm:
		return
	
	# ─── TWO CONDITIONS FOR GENERATOR HUM ─────────────────────────────
	# The generator should be audible when:
	#   A. It has fuel to burn (generator_fuel > 0)
	#   B. The power is flowing (is_generator_on == true → porch light is lit)
	var has_fuel: bool = nm.generator_fuel > 0.0
	var power_on: bool = nm.is_generator_on
	var should_play: bool = has_fuel and power_on
	
	# State transitions
	if should_play and not _generator_audio.playing:
		_generator_audio.play()
		print("[Generator] Audio START — fuel=%.1f, power=%s" % [nm.generator_fuel, power_on])
	elif not should_play and _generator_audio.playing:
		_generator_audio.stop()
		print("[Generator] Audio STOP — fuel=%.1f, power=%s" % [nm.generator_fuel, power_on])


## Updates the fuel indicator light color and blink state based on
## current fuel percentage. Only visible when the generator is running.
func _update_fuel_indicator(delta: float) -> void:
	var nm := get_node_or_null("/root/NightManager")
	if not nm or not _fuel_light:
		return
	
	# Hide the light entirely if generator is off or has no fuel
	if not nm.is_generator_on or nm.generator_fuel <= 0.0:
		_fuel_light.visible = false
		_light_visible = true  # Reset blink state
		_blink_timer = 0.0
		return
	
	# Calculate fuel percentage
	var fuel_pct: float = (nm.generator_fuel / nm.max_fuel) * 100.0
	_fuel_light.visible = true
	
	# Map fuel percentage to color & blink state
	if fuel_pct <= 10.0:
		# 1-10%: Blinking Red
		_fuel_light.light_color = Color.RED
		_blink_timer += delta
		if _blink_timer >= 0.5:
			_blink_timer = 0.0
			_light_visible = not _light_visible
		_fuel_light.visible = _light_visible
		
	elif fuel_pct <= 20.0:
		# 11-20%: Static Red
		_fuel_light.light_color = Color.RED
		
	elif fuel_pct <= 35.0:
		# 21-35%: Orange
		_fuel_light.light_color = Color(1.0, 0.55, 0.0)
		
	elif fuel_pct <= 70.0:
		# 36-70%: Yellow
		_fuel_light.light_color = Color.YELLOW
		
	else:
		# 71-100%: Green
		_fuel_light.light_color = Color.GREEN


## Calculates the total fuel drain rate based on which lights are currently
## switched on. Called by NightManager.recalculate_fuel_drain().
##
## Iterates all nodes in the "CabinLights" group and sums their drain:
##   - Interior lights (is_faulty == false) → cabin_light_drain_rate each
##   - Porch light (is_faulty == true)     → porch_light_drain_rate
##
## Returns the total drain rate in fuel units per second.
func calculate_total_drain() -> float:
	var total: float = base_drain_rate
	var lights = get_tree().get_nodes_in_group("CabinLights")
	
	for light in lights:
		if not "is_switched_on" in light:
			continue
		if not light.is_switched_on:
			continue
		
		# Check if this is the faulty porch light
		if "is_faulty" in light and light.is_faulty:
			total += porch_light_drain_rate
		else:
			total += cabin_light_drain_rate
	
	return total


# ─── GENERATOR SWITCH ────────────────────────────────────────────────
## Called by InteractionManager when the player presses E while looking
## at the generator's switch collider. Toggles the generator on/off.
func interact() -> void:
	toggle_switch()


## Toggles the generator on/off. Requires fuel > MIN_START_FUEL_PERCENT
## to turn on. Auto-shutdown is handled in _process() when fuel hits 0.
func toggle_switch() -> void:
	var nm := get_node_or_null("/root/NightManager")
	if not nm:
		return
	
	if is_switched_on:
		# Turn OFF
		is_switched_on = false
		nm.is_generator_on = false
		if nm.has_signal("generator_state_changed"):
			nm.generator_state_changed.emit(false)
		_play_sfx("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/UI/generator_switch.ogg")
		_show_hud_msg("Generator stopped.")
	else:
		# Turn ON — check fuse box prerequisite first
		var fuse_box = get_tree().get_first_node_in_group("FuseBox")
		if not fuse_box:
			var interactables = get_tree().get_nodes_in_group("interactable")
			for node in interactables:
				if node is FuseBox:
					fuse_box = node
					break
		if not fuse_box or not fuse_box.has_method("is_powered") or not fuse_box.is_powered():
			_show_hud_msg("The fuse box needs to be repaired first...")
			return
		
		# Check fuel threshold
		var fuel_pct: float = (nm.generator_fuel / nm.max_fuel) * 100.0
		if nm.generator_fuel <= 0.0:
			_show_hud_msg("The generator is out of fuel...")
			return
		if fuel_pct < MIN_START_FUEL_PERCENT:
			_show_hud_msg("Not enough fuel to start (need > 10%%)...")
			return
		is_switched_on = true
		nm.is_generator_on = true
		if nm.has_signal("generator_state_changed"):
			nm.generator_state_changed.emit(true)
		_play_sfx("res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/UI/generator_switch.ogg")
		_show_hud_msg("Generator started.")


## Returns the interaction prompt text shown in the HUD.
func get_interact_text() -> String:
	if is_switched_on:
		return "[E] Turn Generator Off"
	return "[E] Turn Generator On"


## Shows a HUD message via the HUD node.
func _show_hud_msg(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[Generator HUD]: ", msg)


## Plays a one-shot sound effect via a temporary AudioStreamPlayer3D.
func _play_sfx(res_path: String) -> void:
	var stream := load(res_path)
	if not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
