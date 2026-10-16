extends StaticBody3D
class_name Generator

## Generator — Central power management for the cabin's electrical grid.
## Attach this script to the root node of generator.tscn.

## Fuel drain rate per cabin light (fuel units per second).
@export var cabin_light_drain_rate: float = 0.125
## Fuel drain rate for the porch light (fuel units per second).
@export var porch_light_drain_rate: float = 0.075
## Base fuel drain rate (fuel units per second).
@export var base_drain_rate: float = 0.12
## Starting fuel percentage (0.0 to 100.0).
@export var starting_fuel_percent: float = 100.0
## Volume (dB) for the generator's looping audio.
@export var generator_audio_volume_db: float = -12.0
## Path to the generator's looping audio stream.
@export var generator_audio_stream_path: String = "res://assets/audio/Electric/machine_mx_1_loop.ogg"

# ─── SOUND EFFECTS (Assign in Inspector) ────────────────────────────────
## Sound played when the GeneratorSwitch is toggled ON or OFF.
@export var generator_switch_sfx: AudioStream = null

var _generator_audio: AudioStreamPlayer3D = null
var _audio_loaded: bool = false
var is_switched_on: bool = false
const MIN_START_FUEL_PERCENT: float = 10.0
var _fuel_light: OmniLight3D = null
var _blink_timer: float = 0.0
var _light_visible: bool = true
var _audio_was_playing: bool = false
var _nm_cache: Node = null


func _ready() -> void:
	add_to_group("generator_controller")
	add_to_group("xray_generator")
	_nm_cache = get_node_or_null("/root/NightManager")
	_generator_audio = get_node_or_null("GeneratorAudio")
	if _generator_audio:
		_generator_audio.volume_db = generator_audio_volume_db
		var stream := load(generator_audio_stream_path)
		if stream:
			_generator_audio.stream = stream
			_generator_audio.bus = "SFX"
			_generator_audio.max_db = 0.0
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			elif "loop_mode" in stream and stream.has_method("set"):
				stream.loop_mode = 0
			_audio_loaded = true
		else:
			push_warning("[Generator] Could not load audio from path.")
	else:
		push_warning("[Generator] No GeneratorAudio node found.")
	_fuel_light = get_node_or_null("FuelIndicatorLight")
	if _fuel_light:_fuel_light.visible = false

	# BUG 1 FIX: Ensure Layer 2 ("Interactable") is active — must run AFTER any
	# bare 'collision_layer = N' assignment in _ready so it cannot be overwritten.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)

func _process(delta: float) -> void:
	_update_audio(delta)
	_update_fuel_indicator(delta)
	if is_switched_on:
		var nm = _nm_cache if is_instance_valid(_nm_cache) else get_node_or_null("/root/NightManager")
		if nm and nm.generator_fuel <= 0.0:
			is_switched_on = false
			nm.is_generator_on = false

func _update_audio(_delta: float) -> void:
	if not _audio_loaded or not _generator_audio:
		return
	var nm := get_node_or_null("/root/NightManager")
	if not nm:
		return
	var should_play: bool = nm.generator_fuel > 0.0 and nm.is_generator_on
	if should_play and (not _generator_audio.playing or _winding_down):
		if _wind_down and _wind_down.is_valid():
			_wind_down.kill()
		_winding_down = false
		_generator_audio.pitch_scale = 1.0
		_generator_audio.volume_db = generator_audio_volume_db
		if not _generator_audio.playing:
			_generator_audio.play()
	elif not should_play and _generator_audio.playing and not _winding_down:
		if nm.generator_fuel <= 0.0:
			# Out of fuel: the engine sputters down instead of cutting out.
			_winding_down = true
			_wind_down = create_tween().set_parallel()
			_wind_down.tween_property(_generator_audio, "pitch_scale", 0.35, WIND_DOWN_TIME).set_ease(Tween.EASE_IN)
			_wind_down.tween_property(_generator_audio, "volume_db", generator_audio_volume_db - 30.0, WIND_DOWN_TIME).set_ease(Tween.EASE_IN)
			_wind_down.chain().tween_callback(_end_wind_down)
		else:
			_generator_audio.stop()


## Seconds the engine takes to die when the fuel runs out.
const WIND_DOWN_TIME := 2.5
var _wind_down: Tween = null
var _winding_down := false


func _end_wind_down() -> void:
	_generator_audio.stop()
	_generator_audio.pitch_scale = 1.0
	_generator_audio.volume_db = generator_audio_volume_db
	_winding_down = false

func _update_fuel_indicator(delta: float) -> void:
	var nm := get_node_or_null("/root/NightManager")
	if not nm or not _fuel_light:
		return
	if not nm.is_generator_on or nm.generator_fuel <= 0.0:
		_fuel_light.visible = false; return
	var fuel_pct: float = (nm.generator_fuel / nm.max_fuel) * 100.0
	_fuel_light.visible = true
	if fuel_pct <= 10.0:
		_fuel_light.light_color = Color.RED
		_blink_timer += delta
		if _blink_timer >= 0.5: _blink_timer = 0.0; _light_visible = not _light_visible
		_fuel_light.visible = _light_visible
	elif fuel_pct <= 20.0: _fuel_light.light_color = Color.RED
	elif fuel_pct <= 35.0: _fuel_light.light_color = Color(1.0, 0.55, 0.0)
	elif fuel_pct <= 70.0: _fuel_light.light_color = Color.YELLOW
	else: _fuel_light.light_color = Color.GREEN

func calculate_total_drain() -> float:
	var total: float = base_drain_rate
	for light in get_tree().get_nodes_in_group("CabinLights"):
		if not "is_switched_on" in light or not light.is_switched_on: continue
		total += porch_light_drain_rate if ("is_faulty" in light and light.is_faulty) else cabin_light_drain_rate
	# PORTABLE LAMP CONTRIBUTION
	# The portable lamp (PortableLamp) contributes its own energy_drain_rate
	# while powered on (matches a cabin light's 0.5/s). During overload the
	# lamp spikes its rate to drain the generator's full tank over 30 seconds.
	var lamps = get_tree().get_nodes_in_group("portable_trap")
	for lamp in lamps:
		if lamp and "energy_drain_rate" in lamp and lamp.is_powered:
			total += lamp.energy_drain_rate
	return total

func interact() -> void: toggle_switch()

func toggle_switch() -> void:
	var nm := get_node_or_null("/root/NightManager")
	if not nm: return
	if is_switched_on:
		is_switched_on = false; nm.is_generator_on = false
		if nm.has_signal("generator_state_changed"): nm.generator_state_changed.emit(false)
		if nm.has_method("recalculate_fuel_drain"): nm.recalculate_fuel_drain()
		_play_sfx(generator_switch_sfx)
		_show_hud_msg("There. Generator's off.")
	else:
		var fuse_box = get_tree().get_first_node_in_group("FuseBox")
		if not fuse_box:
			for node in get_tree().get_nodes_in_group("interactable"):
				if node is FuseBox: fuse_box = node; break
		if not fuse_box or not fuse_box.has_method("is_powered") or not fuse_box.is_powered():
			_show_hud_msg("It won't run until I fix the fuse box."); return
		var fuel_pct: float = (nm.generator_fuel / nm.max_fuel) * 100.0
		if nm.generator_fuel <= 0.0: _show_hud_msg("It's bone dry. I need fuel."); return
		if fuel_pct < MIN_START_FUEL_PERCENT: _show_hud_msg("There's barely any fuel in it. Not enough to get it going."); return
		is_switched_on = true; nm.is_generator_on = true
		if nm.has_signal("generator_state_changed"): nm.generator_state_changed.emit(true)
		if nm.has_method("recalculate_fuel_drain"): nm.recalculate_fuel_drain()
		_play_sfx(generator_switch_sfx)
		_show_hud_msg("There we go.")
		# ─── ROUTINE MANAGER: Generator turned ON ─────────────────────
		# The Day 1 "Turn on the generator" objective completes the moment
		# the switch is flipped. This is the post-refuel step before the
		# player can log into the computer.
		var rm := get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_generator_turned_on"):
			rm.on_generator_turned_on()

func get_interact_text() -> String:
	if is_switched_on:
		return "[E] Turn Generator Off"
	# ─── EXPLAIN WHY THE GENERATOR CAN'T START (FIX) ──────────────────
	# Previously the prompt said only "[E] Turn Generator On". Now the
	# player gets actionable feedback when the switch won't work, so a
	# blocked toggle no longer looks like a dead input.
	var nm := get_node_or_null("/root/NightManager")
	if nm:
		var fuse_box = get_tree().get_first_node_in_group("FuseBox")
		if not fuse_box:
			for node in get_tree().get_nodes_in_group("interactable"):
				if node is FuseBox: fuse_box = node; break
		if not fuse_box or not fuse_box.has_method("is_powered") or not fuse_box.is_powered():
			return "Generator (fix the fuse box first)"
		if nm.generator_fuel <= 0.0:
			return "Generator (no fuel)"
		var fuel_pct: float = (nm.generator_fuel / nm.max_fuel) * 100.0
		if fuel_pct < MIN_START_FUEL_PERCENT:
			return "Generator (needs more than 10% fuel)"
	return "[E] Turn Generator On"

func _show_hud_msg(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"): hud.show_message(msg, self)
	else: print("[Generator HUD]: ", msg)

func _play_sfx(stream: AudioStream) -> void:
	if not stream: return
	var p := AudioStreamPlayer3D.new(); p.stream = stream; p.bus = "SFX"
	add_child(p); p.play(); p.finished.connect(p.queue_free)