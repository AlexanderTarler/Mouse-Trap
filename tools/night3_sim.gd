extends SceneTree
## Night 3 survival simulation: the real night (the Entity's AI, its tricks,
## the generator's fuel) against a simple scripted player, to measure how
## hard Night 3 is. One run per call:
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/night3_sim.gd -- <strategy> <seed>
##
## Strategies (the player doesn't move; it only reacts):
##   lit      in the computer room with its light on; switches it back on
##            1.5 s after it's killed; overcharges the flashlight at a charge
##   dark     crouched in the dark bedroom upstairs; overcharges at a charge
##            and holds the beam until it's gone
##   flicker  as dark, but lets go of the beam as soon as the charge stops
##   passive  standing in the hall, no light, no flashlight (the baseline)
## The first catch is the death (the run ends there). Prints [SIM] lines.

const NIGHT_SECONDS := 300.0
const REACTION := 0.6        ## Seconds from seeing a charge to the beam.
const RELIGHT_DELAY := 1.5
const THREAT_DISTANCE := 10.0

var _strategy := "lit"
var _scene: Node
var _player: Node3D
var _entity
var _nm: Node
var _gt: Node
var _cam: Camera3D
var _flashlight: Node
var _clock := 0.0
var _threat := 0.0
var _relight := 0.0
var _states: Dictionary = {}
var _last_state := ""
var _charges := 0
var _light_kills := 0
var _entries := 0
var _ambushes := 0
var _fake_departures := 0
var _closest := INF
var _sightings := 0
var _seen := false
var _inside_time := 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_strategy = args[0] if args.size() > 0 else "lit"
	seed(int(args[1]) if args.size() > 1 else 1)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	for i in 60:
		await physics_frame
	_player = get_first_node_in_group("player")
	_entity = get_first_node_in_group("entity")
	_nm = root.get_node("NightManager")
	_gt = root.get_node("GameTime")
	_cam = _player.get_node("CameraHolder/Camera3D")
	_flashlight = _cam.get_node("Flashlight")
	_entity.can_kill = false
	_player.enable_flashlight()   # (picked up on Day 1)

	# Day 3 done: the generator full and running, the door locked, dusk.
	_nm.generator_fuel = _nm.max_fuel
	_nm.is_generator_on = true
	_nm.generator_state_changed.emit(true)
	var door: Node = get_first_node_in_group("Door")
	door.set_state_quietly(false, true)
	_place()
	if _strategy == "flicker":
		_player.global_position = Vector3(11.5, 3.9, 17.3)
		_player._is_crouching = true
	_nm.current_night = 3
	_gt.cycle_progress = 0.5
	_gt._elapsed = 0.5 * _gt.cycle_duration
	_gt.is_day = false
	_gt.is_time_paused = false
	_gt.is_running = true
	_nm.is_time_paused = false
	_nm.start_night(3)
	await physics_frame

	var died_at := -1.0
	var frames := int(NIGHT_SECONDS * 60.0)
	for i in frames:
		await physics_frame
		var delta := 1.0 / 60.0
		_clock += delta
		_track_states()
		if OS.get_environment("SIM_TRACE") != "" and _entity.get_state_name() == "HUNT" and int(_clock * 60) % 12 == 0:
			var h = _entity.brain.current
			print("[TRACE]   hunt %.1fs at %s inside=%s lead=%s cover=%.1f ambush=%s patrol=%s traversing=%s target=%s" % [_clock,
				_entity.global_position.snapped(Vector3.ONE * 0.1), _entity.perception.entity_inside, h._lead, h._cover_left,
				h._ambush != Vector3.INF, h._patrol[h._patrol_index].snapped(Vector3.ONE * 0.1) if not h._patrol.is_empty() else null,
				_entity.is_traversing(), _entity.nav_agent.target_position.snapped(Vector3.ONE * 0.1)])
		if _entity.is_active() and _entity.perception.entity_inside:
			_inside_time += delta
			_closest = minf(_closest, _entity.global_position.distance_to(_player.global_position))
		var seen: bool = _entity.perception.can_see_player
		if seen and not _seen:
			_sightings += 1
		_seen = seen
		_react(delta)
		if _caught():
			died_at = _clock
			break
		if _gt.is_day:
			break
	var fuel: float = _nm.generator_fuel
	print("[SIM] strategy=%s seed=%s result=%s time=%.0fs charges=%d light_kills=%d entries=%d ambushes=%d fake_departures=%d fuel_left=%.0f battery_left=%.0f inside=%.0fs closest=%.1fm sightings=%d driven_off=%d" % [
		_strategy, args[1] if args.size() > 1 else "1",
		"DIED" if died_at >= 0.0 else "SURVIVED", died_at if died_at >= 0.0 else _clock,
		_charges, _light_kills, _entries, _ambushes, _fake_departures, fuel, _flashlight.battery_level, _inside_time, _closest, _sightings, _entity.times_driven_off])
	print("[SIM] states: ", _states)
	_scene.queue_free()
	for i in 2:
		await physics_frame
	quit()


func _place() -> void:
	_player.set_physics_process(false)
	match _strategy:
		"lit":
			_player.global_position = Vector3(12.5, 1.0, 17.5)
		"dark":
			_player.global_position = Vector3(11.5, 3.9, 17.3)
			_player._is_crouching = true
		_:
			_player.global_position = Vector3(7.0, 1.0, 11.0)   # the hall
	_player.velocity = Vector3.ZERO
	for light in get_nodes_in_group("CabinLights"):
		if light.get("is_faulty"):
			continue
		var want_on: bool = _strategy == "lit" and light == _room_light()
		if light.is_switched_on != want_on:
			light.toggle_light()


func _room_light() -> Node:
	var room = root.get_node("RoomLightDetector").get_room_at(_player.global_position + Vector3.UP)
	return room.get("room_light") if room else null


## Counts what the Entity does (states entered, its tricks).
func _track_states() -> void:
	var state: String = _entity.get_state_name()
	if state == _last_state:
		return
	if OS.get_environment("SIM_TRACE") != "":
		print("[TRACE] %.1fs %s -> %s at %s inside=%s room=%s dist=%.1f sees=%s" % [_clock, _last_state, state,
			_entity.global_position.snapped(Vector3.ONE * 0.1), _entity.perception.entity_inside,
			_entity.perception.entity_room, _entity.global_position.distance_to(_player.global_position), _entity.perception.can_see_player])
	_states[state] = _states.get(state, 0) + 1
	if state == "CHARGE":
		_charges += 1
	if state == "HUNT" and _last_state == "ENTER":
		_entries += 1
	_last_state = state
	var hunt = _entity.brain.get_state(_entity.State.HUNT)
	if hunt._tell_left > 0.0 and not has_meta("tell"):
		set_meta("tell", true)
		_ambushes += 1
	elif hunt._tell_left < 0.0 and has_meta("tell"):
		remove_meta("tell")
	if hunt._leave_after_ambush and not has_meta("faked"):
		set_meta("faked", true)
		_fake_departures += 1


## The scripted player: the light back on, the beam at a charge.
func _react(delta: float) -> void:
	if _strategy == "passive":
		return
	var state: String = _entity.get_state_name()
	if _strategy == "lit":
		var light := _room_light()
		if light and not light.is_switched_on and _nm.is_generator_on and _nm.generator_fuel > 0.0:
			if _relight <= 0.0:
				_light_kills += 1
			_relight += delta
			if _relight >= RELIGHT_DELAY:
				light.toggle_light()
				_relight = 0.0
		else:
			_relight = 0.0
	var close: bool = _entity.global_position.distance_to(_player.global_position) < THREAT_DISTANCE
	# Holding the beam through the standoff (flicker: only while it charges).
	var held_states := ["CHARGE"] if _strategy == "flicker" else ["CHARGE", "STANDOFF"]
	var charging: bool = state in held_states
	if charging and close:
		_threat += delta
	else:
		_threat = 0.0
	if OS.get_environment("SIM_TRACE") != "" and charging:
		print("[TRACE]   charge %.2fs dist=%.1f threat=%.2f beam=%s over=%s illuminated=%s overcharged=%s oneshot=%.2f" % [_clock,
			_entity.global_position.distance_to(_player.global_position), _threat, _flashlight.is_on, _flashlight.is_overcharged,
			_entity.perception.illuminated, _entity.perception.overcharged, _entity._oneshot_left])
	if _threat >= REACTION and _flashlight.battery_level > 0.0:
		_cam.look_at(_entity.global_position + Vector3.UP * 1.2)
		if not _flashlight.is_on:
			_flashlight.toggle()
		if not _flashlight.is_overcharged:
			_flashlight.activate_overcharge()
	elif _flashlight.is_on and _threat <= 0.0:
		_flashlight.toggle()


## Would have been caught (the Entity in a catching state, in reach).
func _caught() -> bool:
	return _entity.is_active() and _entity.brain.current.can_catch() \
		and _entity.global_position.distance_to(_player.global_position) <= _entity.config.catch_distance
