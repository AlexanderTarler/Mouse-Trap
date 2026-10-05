extends SceneTree
## The Entity and the upper floor:
##   - "arrived" is floor-aware; patrol points come one per room, per floor
##   - climbing is allowed from Night 4
##   - it climbs to an upstairs window, peeks and breaks in from the wall, and
##     vaults inside
##   - driven off the wall by the overcharge it drops; when it gives up it
##     climbs down
##   - it can leave the cabin through an open upstairs window, down the wall
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/climb_test.gd

const UPPER_FLOOR_Y := 3.73
const LIVING := Vector3(6.0, 0.75, 17.4)
const LANDING := Vector3(6.0, UPPER_FLOOR_Y, 17.4)
const BEDROOM := Vector3(12.2, UPPER_FLOOR_Y, 17.4)
const EAST_YARD := Vector3(21.0, 0.3, 17.4)
const BACK_YARD := Vector3(7.8, 0.3, 27.0)

var _failures := 0
var _scene: Node
var _entity
var _player: CharacterBody3D
var _nm: Node
var _states: Array[String] = []


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[CLIMB TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _history() -> String:
	return " > ".join(_states.slice(maxi(_states.size() - 10, 0)))


func _wait_for(condition: Callable, seconds: float) -> bool:
	for i in int(seconds * 60.0):
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false   # normal game rules
	root.add_child(_scene)
	current_scene = _scene
	await _frames(10)
	_entity = get_first_node_in_group("entity")
	_player = get_first_node_in_group("player") as CharacterBody3D
	_nm = root.get_node("NightManager")
	_player.set_process(false)
	_player.set_physics_process(false)
	_nm.current_night = 4
	_nm.is_time_paused = true
	_nm.is_generator_on = false   # every room dark: lights don't send it away
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	# Deterministic and quick: no bluffing or ducking, short peeks.
	var config = _entity.config
	config.bluff_chance = 0.0
	config.peek_duck_chance = 0.0
	config.peek_time_min = 1.0
	config.peek_time_max = 1.5
	config.confidence_drift = 0.0
	_entity.can_kill = false
	_entity.brain.state_changed.connect(func(_from, to): _states.append(_entity.State.keys()[to]))
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 0:
			link.entry.is_locked = true
		else:
			link.entry.is_glass_shattered = false
			link.entry.is_boarded = false
	_entity.activate()
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(5)

	await _test_floor_aware()
	_test_night_gate()
	await _test_climb_in()
	await _test_drop_off()
	await _test_climb_down()
	await _test_leave_through_upstairs_window()

	print("[CLIMB TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _link(window_name: String):
	return _scene.get_node("Windows/TopFloorWindows/" + window_name)._entry_link


func _ground(p: Vector3) -> Vector3:
	return _entity.world.snap_to_navmesh(p)


func _place_player(floor_pos: Vector3) -> void:
	_player.global_position = floor_pos + Vector3.DOWN * 0.25
	_player.velocity = Vector3.ZERO


# ─── Scenarios ───────────────────────────────────────────────────────────────

func _test_floor_aware() -> void:
	_entity._teleport(_ground(LIVING))
	await _frames(2)
	var to_landing: float = _entity.move_to(_ground(LANDING), 2.0)
	var to_living: float = _entity.move_to(_ground(LIVING + Vector3(0.3, 0.0, 0.0)), 2.0)
	_check("floors: standing in the living room is not being on the landing above it",
		to_landing > 2.5 and to_living < 1.0, "to landing %.1f, to a spot beside it %.1f" % [to_landing, to_living])

	var centers: Array = _entity.world.room_centers()
	var upper := centers.filter(func(c): return c.y > UPPER_FLOOR_Y - 0.5)
	_check("floors: one patrol point per room (6), 3 of them upstairs, none for the stairs",
		centers.size() == 6 and upper.size() == 3, "%d points, %d upstairs" % [centers.size(), upper.size()])

	_entity.request_state(_entity.State.HUNT)
	await _frames(2)
	var patrol: Array = _entity.brain.current._patrol
	var first_three := patrol.slice(0, 3)
	_check("floors: hunting from downstairs, it patrols the ground floor first",
		first_three.size() == 3 and first_three.all(func(p): return p.y < 2.0),
		str(first_three.map(func(p): return snappedf(p.y, 0.1))))
	_entity.request_state(_entity.State.OBSERVE)


func _test_night_gate() -> void:
	var link = _link("BedroomWindowLeft")
	_nm.current_night = 3
	var night3: bool = _entity.world.is_entry_viable(link)
	_nm.current_night = 4
	var night4: bool = _entity.world.is_entry_viable(link)
	_check("night gate: no climbing on Night 3, climbing from Night 4", not night3 and night4,
		"night 3 %s, night 4 %s" % [night3, night4])


## Approach -> climb -> peek and break in from the wall -> vault in -> hunt.
func _test_climb_in() -> void:
	_states.clear()
	_place_player(BEDROOM)
	var link = _link("BedroomWindowLeft")
	_entity._teleport(_ground(EAST_YARD))
	await _frames(2)
	_entity.request_state(_entity.State.APPROACH, {"entry": link})
	var perched: bool = await _wait_for(func(): return _entity.is_perched_at(link), 20.0)
	var perch_y: float = _entity.global_position.y
	_check("climb in: walks to the wall and climbs up to the window",
		perched and perch_y > 3.0 and not _entity.perception.entity_inside, "perched=%s at y %.2f, %s" % [perched, perch_y, _history()])
	var inside: bool = await _wait_for(func(): return _entity.get_state_name() == "HUNT" and _entity.perception.entity_inside, 40.0)
	_check("climb in: peeks and breaks the glass from the wall, then climbs in",
		inside and "PEEK" in _states and "BREACH" in _states and "ENTER" in _states, _history())
	_check("climb in: it is upstairs, in the bedroom",
		_entity.global_position.y > UPPER_FLOOR_Y - 0.2 and _entity.perception.entity_room == "Bedroom",
		"y %.2f, room %s" % [_entity.global_position.y, _entity.perception.entity_room])
	_check("climb in: it left claw marks up the wall", _entity.traces.scratch_count() >= 4, "%d scratches" % _entity.traces.scratch_count())


## Clinging outside a window, the overcharge makes it drop off and flee.
func _test_drop_off() -> void:
	_states.clear()
	_place_player(BEDROOM)
	var link = _link("BedroomWindowRight")
	_entity._teleport(_ground(EAST_YARD))
	_entity.confidence.reset()
	await _frames(2)
	_entity.request_state(_entity.State.APPROACH, {"entry": link})
	var perched: bool = await _wait_for(func(): return _entity.is_perched_at(link), 20.0)
	if not perched:
		_check("drop off: precondition (clinging outside the window)", false, _history())
		return
	var frames := 0
	for i in 60 * 3:
		_entity.on_flashlight(true, true, 1.0)
		await physics_frame
		frames += 1
		if not _entity.is_clinging() and _entity.global_position.y < 1.5:
			break
	_entity.on_flashlight(false, false)
	_check("drop off: the overcharge makes it drop off the wall and flee",
		"FLEE" in _states and not _entity.is_clinging() and _entity.global_position.y < 1.5 and frames < 60,
		"on the ground after %.2f s, %s" % [frames / 60.0, _history()])
	await _frames(30)


## Clinging at the landing window (no ledge): the player leaves the cabin, it
## climbs back down.
func _test_climb_down() -> void:
	_states.clear()
	_place_player(LANDING)
	var link = _link("LandingWindow")
	_entity._teleport(_ground(BACK_YARD))
	_entity.world._repelled_until.clear()
	_entity.confidence.reset()
	await _frames(2)
	_entity.request_state(_entity.State.APPROACH, {"entry": link})
	var perched: bool = await _wait_for(func(): return _entity.is_perched_at(link), 20.0)
	if not perched:
		_check("climb down: precondition (clinging at the landing window)", false, _history())
		return
	_check("climb down: it clings to the bare wall where there is no ledge",
		_entity.global_position.y > 3.0, "y %.2f" % _entity.global_position.y)
	# The player steps out into the back yard, in its view: it comes down to
	# stalk them (stalking never teleports, so the descent is really climbed).
	var perch: Vector3 = _entity.global_position
	_place_player(_ground(BACK_YARD))
	var frames := 0
	var down := false
	for i in 60 * 10:
		await physics_frame
		frames += 1
		if not _entity.is_clinging() and not _entity.is_traversing() and _entity.global_position.y < 1.5:
			down = true
			break
	var foot: float = Vector2(_entity.global_position.x - perch.x, _entity.global_position.z - perch.z).length()
	_check("climb down: with the player out in the yard it climbs back down (not a drop)",
		down and frames / 60.0 > 1.5 and foot < 1.5 and not ("FLEE" in _states),
		"down=%s after %.1f s, %.1f m from below the window, %s" % [down, frames / 60.0, foot, _history()])


## Inside, with the only open way out an upstairs window: out and down the wall.
func _test_leave_through_upstairs_window() -> void:
	_states.clear()
	var link = _link("BedroomWindowLeft")   # broken open by _test_climb_in
	if not link.enabled:
		_check("leave: precondition (bedroom window broken open)", false)
		return
	_place_player(Vector3(40.0, 0.3, -20.0))
	_entity._teleport(_ground(BEDROOM))
	await _frames(5)
	_entity.request_state(_entity.State.FLEE, {"calm": true})
	var out: bool = await _wait_for(func(): return not _entity.perception.entity_inside and not _entity.is_traversing() \
		and _entity.global_position.y < 1.5, 25.0)
	_check("leave: it leaves through the upstairs window and climbs down the wall",
		out and not _entity.is_clinging(), "pos %s, %s" % [_entity.global_position.snapped(Vector3.ONE * 0.1), _history()])
