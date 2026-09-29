extends SceneTree
## Entity behaviour scenarios. Run headless from the project folder:
##   godot --headless --path . --fixed-fps 60 --script res://tests/entity_behavior_test.gd
##
## Loads the real level, freezes the player's own scripts (the test moves the
## player and simulates the flashlight) and checks that the Entity reaches
## the expected states. Prints "[ENTITY TEST] PASS/FAIL" per check and a final
## "ALL PASSED" / "N FAILED" line. (Headless shutdown may segfault after the
## summary; read the summary line, not the exit code.)
##
## No class_name references here: in --script mode they would be compiled
## before the autoloads they depend on.

const YARD := Vector3(20.0, 0.5, 4.0)            # east of the porch
const FAR_YARD := Vector3(30.0, 0.5, -10.0)
const HALL := Vector3(6.5, 1.0, 11.0)
const COMPUTER_ROOM := Vector3(12.5, 1.0, 17.5)

var _failures := 0
var _scene: Node
var _entity: Node
var _player: Node3D
var _nm: Node
var _states: Array[String] = []


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Waits up to `seconds` for the Entity to be in one of `names`.
func _wait_for_state(names: Array, seconds: float) -> bool:
	var frames := int(seconds * 60.0)
	for i in frames:
		if _entity.get_state_name() in names:
			return true
		await physics_frame
	return _entity.get_state_name() in names


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[ENTITY TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _history() -> String:
	return " > ".join(_states.slice(maxi(_states.size() - 8, 0)))


func _place_player(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO


func _flashlight(hit: bool, overcharged: bool, seconds: float) -> void:
	for i in int(seconds * 60.0):
		_entity.on_flashlight(hit, overcharged)
		await physics_frame
	_entity.on_flashlight(false, false)


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	root.add_child(_scene)
	await _frames(10)
	_entity = get_first_node_in_group("entity")
	_player = get_first_node_in_group("player") as Node3D
	_nm = root.get_node("NightManager")
	_player.set_process(false)
	_player.set_physics_process(false)
	_nm.current_night = 3
	# Freeze the game clock so no night starts mid-scenario (a new night
	# clears traces and relocates the Entity).
	_nm.is_time_paused = true
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	_entity.can_kill = false   # Catching ends the Entity's run; not what these scenarios test.
	_entity.brain.state_changed.connect(func(_from, to): _states.append(_entity.State.keys()[to]))
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 0:
			link.entry.is_locked = true
		else:
			link.entry.is_glass_shattered = false
			link.entry.is_boarded = false

	await _test_grounding()
	await _test_break_in()
	await _test_overcharge_repels_indoors()
	await _test_indoor_charge_stays_inside()
	await _test_outdoor_stalk_and_standoff()
	await _test_locked_door_stays_shut()
	await _test_van_chase()
	await _test_presence_flicker()
	await _test_traces_clear_at_night()

	print("[ENTITY TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


# ─── Scenarios ───────────────────────────────────────────────────────────────

## B4: after a teleport it must fall onto the ground, not hover.
func _test_grounding() -> void:
	_entity.activate()
	_place_player(HALL)
	_entity._teleport(YARD + Vector3.UP * 1.5)
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(90)
	var floor_y := _floor_below(_entity.global_position)
	var shape: CollisionShape3D = _entity.collision_shape
	var feet_y: float = _entity.global_position.y + shape.position.y - (shape.shape as CapsuleShape3D).height * 0.5
	_check("grounding: lands on the floor after a teleport", _entity.is_on_floor() and absf(feet_y - floor_y) < 0.1,
		"on_floor=%s, capsule bottom %.2f m above the floor" % [_entity.is_on_floor(), feet_y - floor_y])
	var lowest := INF
	for mesh in _entity.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, aabb.position.y)
	print("[ENTITY TEST] info  model mesh bottom is %.2f m relative to the floor (negative = sunk)" % (lowest - floor_y))


## A yard position with an unobstructed 6 m sightline toward +Z (trees are on
## the world layer and block sight).
func _clear_sightline(near: Vector3, distance: float) -> Vector3:
	for i in 40:
		var candidate := near + Vector3(randf_range(-12.0, 12.0), 0.0, randf_range(-12.0, 12.0))
		candidate = _entity.world.snap_to_navmesh(candidate)
		var eye: Vector3 = candidate + Vector3.UP * _entity.config.eye_height
		var target := candidate + Vector3(0.0, 1.0, distance)
		var q := PhysicsRayQueryParameters3D.create(eye, target, 1, [_entity.get_rid(), _player.get_rid()])
		if _entity.get_world_3d().direct_space_state.intersect_ray(q).is_empty() 				and not _entity.world.is_inside_cabin(candidate) and not _entity.world.is_inside_cabin(target):
			return candidate
	return near


func _floor_below(pos: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 5.0, 1, [_entity.get_rid()])
	var hit: Dictionary = _entity.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else NAN


## Player inside, windows intact, door locked: it approaches, peeks, breaks a
## window, climbs in and hunts.
func _test_break_in() -> void:
	_states.clear()
	_place_player(COMPUTER_ROOM)
	# Deterministic: no bluffing, and confidence stays above the threshold.
	var bluff_chance: float = _entity.config.bluff_chance
	var drift: float = _entity.config.confidence_drift
	_entity.config.bluff_chance = 0.0
	_entity.config.confidence_drift = 0.0
	_entity.confidence.set_confidence(80.0)
	_entity.request_state(_entity.State.OBSERVE)
	var inside: bool = await _wait_for_state(["HUNT", "CHARGE"], 120.0)
	_entity.config.bluff_chance = bluff_chance
	_entity.config.confidence_drift = drift
	_check("break-in: reaches the interior (HUNT/CHARGE)", inside, _history())
	_check("break-in: went through APPROACH, PEEK and BREACH",
		"APPROACH" in _states and "PEEK" in _states and "BREACH" in _states and "ENTER" in _states, _history())
	_check("break-in: physically inside the cabin", _entity.perception.entity_inside,
		"room=%s pos=%s" % [_entity.perception.entity_room, _entity.global_position.snapped(Vector3.ONE * 0.1)])
	await _frames(120)
	_check("traces: gouges under the window and claw prints inside",
		_entity.traces.scratch_count() > 0 and _entity.traces.footprint_count() > 0,
		"scratches=%d footprints=%d" % [_entity.traces.scratch_count(), _entity.traces.footprint_count()])


## Overcharged beam indoors (both inside): standoff, then it flees out of the
## cabin and goes back to the treeline.
func _test_overcharge_repels_indoors() -> void:
	_states.clear()
	if not _entity.perception.entity_inside:
		_check("overcharge indoors: precondition (Entity inside)", false, "skipped")
		return
	_place_player(_entity.global_position + Vector3(2.0, 0.0, 0.0))
	await _frames(60)   # it sees the player and charges; the overcharge must still work
	await _flashlight(true, true, 2.0)
	_check("overcharge indoors: STANDOFF then FLEE", "STANDOFF" in _states and "FLEE" in _states, _history())
	var left: bool = await _wait_for_state(["OBSERVE"], 25.0)
	_check("overcharge indoors: leaves the cabin and returns to OBSERVE", left and not _entity.perception.entity_inside, _history())
	_check("overcharge indoors: relaxing after being repelled", _entity.confidence.is_relaxing())
	var guarded := 0.0
	for link in get_nodes_in_group("cabin_entry_links"):
		guarded = maxf(guarded, _entity.world.guard_score(link))
	_check("memory: the window it was driven from is remembered as guarded", guarded > 0.0, "max guard score %.2f" % guarded)


## B3: seeing the player indoors must never end in the treeline teleport.
func _test_indoor_charge_stays_inside() -> void:
	_states.clear()
	var hall_link = null
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 1 and link.enabled:
			hall_link = link
	if not hall_link:
		_check("indoor charge: precondition (an open window)", false, "none open")
		return
	_entity._teleport(hall_link.end_position)
	_place_player(HALL)
	_entity.request_state(_entity.State.HUNT)
	await _frames(30)
	_entity.request_state(_entity.State.CHARGE)
	await _frames(int(_entity.config.charge_max_time * 60.0) + 30)
	_check("indoor charge: player still inside -> back to HUNT (no treeline teleport)",
		_entity.perception.entity_inside and not ("OBSERVE" in _states), _history())
	_check("memory: remembers where it found the player inside", not _entity.world.hiding_spots().is_empty(),
		"%d spot(s)" % _entity.world.hiding_spots().size())


## Player outside and in view: it stalks. Standard beam held while both are
## outside: standoff, then charge.
func _test_outdoor_stalk_and_standoff() -> void:
	_states.clear()
	_entity.confidence.reset()
	_entity.request_state(_entity.State.DORMANT)
	_entity.activate()
	var spot := _clear_sightline(YARD, 6.0)
	_entity._teleport(spot)
	_place_player(spot + Vector3(0.0, 0.0, 6.0))
	_entity.rotation.y = 0.0   # facing +Z, toward the player
	await _frames(3)
	_entity.request_state(_entity.State.OBSERVE)
	var stalking: bool = await _wait_for_state(["STALK", "CHARGE"], 5.0)
	_check("outdoors: sees the player and stalks", stalking, _history())
	_states.clear()
	await _flashlight(true, false, _entity.config.charge_stare_time + 0.5)
	_check("outdoors: standard beam -> STANDOFF -> CHARGE", "STANDOFF" in _states and "CHARGE" in _states, _history())


## Door locked, windows boarded on Night 2: the interior stays unreachable.
func _test_locked_door_stays_shut() -> void:
	_states.clear()
	_nm.current_night = 2
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 0:
			link.entry.is_locked = true
		else:
			link.entry.is_glass_shattered = true
			link.entry.is_boarded = true
			link.entry.planks_remaining = 3
	_place_player(HALL)
	_entity._teleport(YARD)
	_entity.confidence.set_confidence(80.0)
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(60 * 40)
	_check("locked & boarded (Night 2): never gets inside", not _entity.perception.entity_inside and not ("ENTER" in _states), _history())
	_nm.current_night = 3


## Van chase: pursues until the player is inside, then vanishes (DORMANT).
func _test_van_chase() -> void:
	_states.clear()
	_nm.is_van_sequence_active = true
	_place_player(FAR_YARD)
	_entity.deactivate()
	await _frames(3)
	_entity.start_van_chase(FAR_YARD + Vector3(0.0, 0.0, -20.0))
	await _frames(60)
	_check("van chase: STALK with the chase flag set", _entity.get_state_name() == "STALK" and _entity.van_chase_active, _history())
	_place_player(HALL)
	var gone: bool = await _wait_for_state(["DORMANT"], 20.0)
	_check("van chase: player reaches the cabin -> it vanishes", gone and not _entity.is_active() and not _nm.is_van_sequence_active, _history())


## Passing close outside a lit window makes that room's light stutter.
func _test_presence_flicker() -> void:
	# Pause the game's power logic: it keeps re-evaluating the generator and
	# cancels light flickers, which would fight this check.
	_nm.set_process(false)
	_nm.set_physics_process(false)
	_nm.is_generator_on = true
	var window_link = null
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 1 and link.entry.room_light != null:
			window_link = link
			break
	if not window_link:
		_check("presence: precondition (a window with a room light)", false, "none")
		return
	var light = window_link.entry.room_light
	light.is_switched_on = true
	_entity.activate()
	_entity._teleport(window_link.start_position)
	_entity.request_state(_entity.State.DORMANT)   # active but standing still outside the window
	_entity.world._presence_cooldown.clear()   # earlier scenarios may have used this window's cooldown
	var flickered := false
	for i in 180:
		_nm.is_generator_on = true     # the game's power logic may switch it off
		light.is_switched_on = true
		await physics_frame
		if light._flicker_tween != null:
			flickered = true
			break
	if not flickered:
		var w = _entity.world
		print("[ENTITY TEST] debug presence: timer=%.2f clock=%.1f cooldowns=%s tween=%s entries=%d link=%s" % [
			w._presence_timer, w._clock, w._presence_cooldown.values(), light._flicker_tween, w.entries().size(), window_link.entry.name])
	_check("presence: lit window's light stutters as it passes", flickered,
		"light=%s lit=%s faulty=%s dist=%.2f active=%s inside=%s state=%s" % [light.name, light.is_room_lit(), light.get("is_faulty"),
		_entity.global_position.distance_to(window_link.start_position), _entity.is_active(), _entity.perception.entity_inside, _entity.get_state_name()])
	light.is_switched_on = false
	_nm.is_generator_on = false
	_nm.set_process(true)
	_nm.set_physics_process(true)


## A new night clears last night's traces.
func _test_traces_clear_at_night() -> void:
	_entity.traces.scratch_window(get_nodes_in_group("cabin_entry_links").filter(func(l): return l.kind == 1)[0])
	_entity._on_night_started(3)
	_check("traces: cleared when the next night starts", _entity.traces.scratch_count() == 0 and _entity.traces.footprint_count() == 0)
