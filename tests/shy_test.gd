extends SceneTree
## The Entity would rather not be seen (EntityWorld.entry_score, LURE):
##   - choosing a way in, it keeps away from the room it believes the player
##     is in;
##   - when the best way in is a window of the player's own room, it plans a
##     lure: a window of another room to knock at;
##   - LURE: it knocks at the decoy, hides nearby, and once it hears the
##     player elsewhere it rushes the real window (APPROACH, rushing);
##   - if the player won't budge it gives up and goes for another room;
##   - spotted while luring, it slips away and avoids that window for a while.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/shy_test.gd

const COMPUTER_ROOM := Vector3(12.5, 1.0, 17.5)

var _failures := 0
var _scene: Node
var _entity
var _player: CharacterBody3D
var _nm: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[SHY TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(10)
	_entity = get_first_node_in_group("entity")
	_player = get_first_node_in_group("player") as CharacterBody3D
	_nm = root.get_node("NightManager")
	_player.set_process(false)

	_nm.current_night = 3
	_nm.is_time_paused = true
	_nm.is_generator_on = false   # every room dark: lights don't sway the choice
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	_entity.can_kill = false
	_entity.config.confidence_drift = 0.0
	_close_cabin()
	await _frames(60)   # the NightManager places the player first
	# The player in the computer room, looking at the floor (it isn't seen).
	_player.global_position = COMPUTER_ROOM
	_player.velocity = Vector3.ZERO
	var holder: Node3D = _player.get_node("CameraHolder")
	holder.rotation.x = deg_to_rad(-85.0)
	_entity.activate()
	_entity.teleport(_entity.world.snap_to_navmesh(Vector3(30.0, 0.3, 30.0)))
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(30)
	_check("setup: the player is inside, in the computer room", _entity.perception.player_inside,
		_entity.perception.player_room)

	_test_avoids_room()
	_test_plan()
	await _test_lure_works()
	await _test_lure_gives_up()
	await _test_lure_spotted()

	print("[SHY TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _close_cabin() -> void:
	for link in get_nodes_in_group("cabin_entry_links"):
		if link.kind == 0:
			link.entry.is_locked = true
			link.entry.is_open = false
	for window in get_nodes_in_group("WindowMarkers"):
		if window.has_method("is_passable"):
			window.is_glass_shattered = false
			window.is_boarded = false


func _believe(room: String) -> void:
	var p = _entity.perception
	p._known_room = room
	p._known_room_clock = p._clock
	p.last_heard_room = room
	p._last_heard_clock = p._clock


func _computer_window() -> Object:
	for link in _entity.world.entries():
		if _entity.world.entry_room(link) == "computerroom" and not link.climb:
			return link
	return null


func _test_avoids_room() -> void:
	_entity.config.lure_chance = 0.0
	var baseline := 0
	_entity.perception.reset_memory()
	for i in 40:
		var link = _entity.world.pick_entry()
		if link and _entity.world.entry_room(link) == "computerroom":
			baseline += 1
	_believe("ComputerRoom")
	var picks := 0
	for i in 40:
		var link = _entity.world.pick_entry()
		if link and _entity.world.entry_room(link) == "computerroom":
			picks += 1
	_check("way in: keeps away from the room it believes the player is in", picks <= 2,
		"%d/40 computer room picks (not knowing where the player is: %d/40)" % [picks, baseline])


func _test_plan() -> void:
	# The computer room's window is the best way in (smashed open)...
	var target = _computer_window()
	target.entry.is_glass_shattered = true
	_believe("ComputerRoom")
	_entity.config.lure_chance = 1.0
	var plan: Dictionary = _entity.world.plan_entry()
	var decoy = plan.get("decoy")
	_check("plan: the best way in is the player's room, so it lures them away first",
		plan.get("entry") == target and decoy != null and _entity.world.entry_room(decoy) != "computerroom" and not decoy.climb,
		"entry %s, decoy %s" % [plan.get("entry").entry.name if plan.get("entry") else "none", decoy.entry.name if decoy else "none"])
	target.entry.is_glass_shattered = false


func _start_lure(wait: float, rounds: int) -> Dictionary:
	_entity.config.lure_wait = wait
	_entity.config.lure_rounds = rounds
	_entity.config.lure_chance = 1.0
	var target = _computer_window()
	target.entry.is_glass_shattered = true
	_believe("ComputerRoom")
	var plan: Dictionary = _entity.world.plan_entry()
	_entity.teleport(_entity.world.snap_to_navmesh(Vector3(30.0, 0.3, 30.0)))
	_entity.request_state(_entity.State.LURE, plan)
	return plan


## Until LURE is hiding (phase HIDE) or `seconds` pass.
func _until_hiding(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await physics_frame
		if _entity.get_state() != _entity.State.LURE or _entity.brain.current._phase == 2:
			break


func _test_lure_works() -> void:
	var plan := await _start_lure(20.0, 2)
	await _until_hiding(60.0)
	var hiding: bool = _entity.get_state() == _entity.State.LURE and _entity.brain.current._phase == 2
	# (Headless audio never finishes playing, so the knocks are counted by the state.)
	var knocks: int = _entity.config.lure_knocks - _entity.brain.current._knocks_left if hiding else 0
	_check("lure: it knocks at another room's window, then hides", hiding and knocks == _entity.config.lure_knocks,
		"%d knocks at %s; state %s" % [knocks, plan.get("decoy").entry.name, _entity.get_state_name()])
	await _frames(60)
	# The player is heard in the decoy's room: drawn out.
	var decoy_room: String = _entity.world.entry_room(plan.get("decoy"))
	_entity.perception.last_heard_room = decoy_room
	_entity.perception._last_heard_clock = _entity.perception._clock
	await _frames(5)
	var state: String = _entity.get_state_name()
	var rushing: bool = state == "APPROACH" and _entity.brain.current._rush and _entity.brain.current._entry == plan.get("entry")
	_check("lure: the player heard elsewhere, it rushes the real window", rushing, state)
	plan.get("entry").entry.is_glass_shattered = false
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(5)


func _test_lure_gives_up() -> void:
	var plan := await _start_lure(1.5, 1)
	await _until_hiding(60.0)
	var went := ""
	for i in 60 * 6:
		await physics_frame
		_believe("ComputerRoom")
		if _entity.get_state() != _entity.State.LURE:
			break
	var entry = _entity.brain.current.get("_entry")
	var ok: bool = _entity.get_state_name() == "APPROACH" and entry != null and _entity.world.entry_room(entry) != "computerroom"
	_check("lure: the player won't budge, so it goes for another room", ok,
		"%s %s" % [_entity.get_state_name(), entry.entry.name if entry else ""])
	plan.get("entry").entry.is_glass_shattered = false
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(5)


func _test_lure_spotted() -> void:
	var plan := await _start_lure(20.0, 2)
	await _frames(10)
	_entity.brain.current._spotted = true
	await _frames(2)
	_check("lure: spotted, it slips away and avoids that window for a while",
		_entity.get_state_name() == "OBSERVE" and _entity.world.is_spotted(plan.get("decoy")), _entity.get_state_name())
	plan.get("entry").entry.is_glass_shattered = false
