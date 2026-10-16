extends SceneTree
## planning/tasks.txt (round 6):
##   1 the sprint hint goes after 3 s of sprinting while it's up, even if
##     the player had sprinted plenty before it came up
##   2 the hunting music ("too late (loop)") plays while the Entity is after
##     the player, not while it lies in wait or has lost the trail
##   3 more detail: the cabin's rooms and yard, the trails and the nests'
##     survey stakes (SiteDresser), clear of windows and the paths
##   4 the Day 2 upload: dozing off at the computer (the eyelids blink shut,
##     as going to bed does), then they open on the night
##   5 F4 (temporary): the Entity climbs to the LandingRoom's window and
##     tries to break in
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks12_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D
var _entity: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS12 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _load(dev_start: int = 0) -> void:
	if _scene:
		_scene.queue_free()
		await _frames(3)
		root.get_node("GameReset").new_game()
	paused = false
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	_scene.get_node("Player").dev_start = dev_start
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	var nm: Node = root.get_node("NightManager")
	for i in 60 * 120:
		if nm.dev_start_runner == null:
			break
		await _frames(10)
	_player = get_first_node_in_group("player")
	_entity = get_first_node_in_group("entity")


func _run() -> void:
	await _frames(2)
	await _load()
	if not "upload" in OS.get_cmdline_user_args():
		await _test_sprint_hint()
		await _test_hunt_music()
		await _test_details()
		await _test_landing_breach()
	await _load(DevStart.Start.DAY_2_NESTS)
	await _test_upload_doze()

	print("[TASKS12 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	Engine.time_scale = 1.0
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_sprint_hint() -> void:
	var tm: Node = root.get_node("TutorialManager")
	_player.sprint_unlocked = true
	_player.global_position = Vector3(30.0, 1.0, 30.0)   # the open yard
	await _frames(5)
	# Sprinting for a while before the hint ever comes up.
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _frames(240)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	await _frames(10)
	# Then it comes up (the Night 2.2 chase).
	tm.trigger("sprint", true)
	await _frames(5)
	var up: bool = tm.was_shown("sprint")
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _frames(100)
	var still_up: bool = tm.was_shown("sprint")
	await _frames(100)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	_check("1: sprinted before the hint showed: it still comes up, stays for a while, and goes after 3 s of sprinting",
		up and still_up and not tm.was_shown("sprint"), "up %s, after ~1.7 s %s, after ~3.3 s %s" % [up, still_up, tm.was_shown("sprint")])


func _test_hunt_music() -> void:
	var hsm: Node = root.get_node("HorrorSoundManager")
	var audio: Node = _entity.audio
	_entity.can_kill = false
	_entity._teleport(Vector3(20.0, 0.3, 30.0))
	_entity.request_state(_entity.State.CHARGE, {"no_roar": true})
	await _frames(5)
	var charging: bool = hsm._stalk_chase_playing and hsm._stalk_chase_player.stream.resource_path.ends_with("too late (loop).ogg")
	# Lost it: watching from the treeline; the music lingers, then fades.
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(30)
	var lingering: bool = hsm._stalk_chase_playing
	await _frames(int((audio.HUNT_MUSIC_LINGER + 0.5) * 60.0))
	var stopped: bool = not hsm._stalk_chase_playing
	_check("2: \"too late (loop)\" while it charges; it lingers a moment after, then stops",
		charging and lingering and stopped, "charge %s, linger %s, stopped %s" % [charging, lingering, stopped])
	# Searching with a fresh trail (it just heard the player): on.
	_entity.request_state(_entity.State.SEARCH, {"position": _player.global_position})
	_entity.hear_noise(_player.global_position, &"sprint")
	await _frames(5)
	var trail: bool = audio.is_hunting_player()
	_entity.request_state(_entity.State.OBSERVE)
	_entity.can_kill = true
	_check("2: searching on a fresh trail counts as hunting the player", trail)


func _test_details() -> void:
	var details := _details()
	_check("3: the details are in the level (%d)" % details.size(), details.size() >= 80)
	var windows: Array[Vector3] = []
	for window in get_nodes_in_group("WindowMarkers"):
		if window.has_method("is_passable"):
			windows.append(window.global_position)
	var inside := 0
	var by_window := 0
	var on_path := 0
	var on_path_names := []
	var stakes := 0
	for prop in details:
		if not prop is Node3D:
			continue
		var p: Vector3 = (prop as Node3D).global_position
		if p.x > 2.9 and p.x < 15.4 and p.z > 8.0 and p.z < 20.5:
			inside += 1
		if String(prop.name).begins_with("SurveyStake") or prop.find_children("*", "MeshInstance3D", false, false).size() == 2 and prop.get_child_count() == 2:
			stakes += 1
		for window in windows:
			if Vector2(p.x - window.x, p.z - window.z).length() < 1.0 and absf(p.y - window.y) < 2.0:
				by_window += 1
		var centre: Vector3 = _box(prop).get_center()
		if p.distance_to(Vector3(9.0, 0.0, 15.0)) > 25.0 and TerrainMask.path(centre) > 0.5:
			on_path += 1
			on_path_names.append("%s %s" % [prop.name, centre.snapped(Vector3.ONE * 0.1)])
	_check("3: the cabin's rooms and yard have more in them (%d things)" % inside, inside >= 25)
	_check("3: three survey stakes by each nest (%d)" % stakes, stakes >= 9)
	_check("3: nothing right by a window (%d), nothing on a walking path (%d)" % [by_window, on_path], by_window == 0 and on_path == 0, str(on_path_names))


## The details in the level (tools/bake_details.gd: CabinDetails,
## ForestDetails).
func _details() -> Array:
	var found: Array = []
	for group in ["CabinDetails", "ForestDetails"]:
		var node := _scene.get_node_or_null(group)
		if node:
			found.append_array(node.get_children())
	return found


## A node's meshes' bounds, in world space.
func _box(node: Node3D) -> AABB:
	var box := AABB(node.global_position, Vector3.ZERO)
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _test_landing_breach() -> void:
	var overlay: Node = _entity.get_node_or_null("DebugOverlay")
	if overlay == null:
		_check("5: the debug overlay (F4) exists in debug builds", false)
		return
	_player.global_position = Vector3(12.2, 3.8, 17.4)   # the bedroom
	await _frames(5)
	_entity.can_kill = false
	var ok: bool = overlay.debug_landing_breach()
	await _frames(2)
	var approaching: bool = _entity.get_state_name() == "APPROACH"
	var states := {}
	var link: CabinEntryLink = null
	for window in get_nodes_in_group("TopFloorWindows"):
		if window.name == "LandingWindow":
			link = window._entry_link
	var perched := false
	for i in 60 * 40:
		await physics_frame
		states[_entity.get_state_name()] = true
		perched = perched or _entity.is_perched_at(link)
		if states.has("BREACH") or states.has("ENTER"):
			break
	_entity.can_kill = true
	_check("5: F4: it climbs up to the LandingRoom window and tries to break in",
		ok and approaching and perched and (states.has("BREACH") or states.has("ENTER")), str(states.keys()))
	_entity.request_state(_entity.State.OBSERVE)


func _test_upload_doze() -> void:
	var rm: Node = root.get_node("RoutineManager")
	var ui: Node = get_first_node_in_group("computer_ui")
	var pc: Node = null
	for node in _scene.find_children("*", "", true, false):
		if node.get_script() and node.get_script().resource_path.ends_with("pc_interactable.gd"):
			pc = node
	_check("4: precondition: Day 2, the nests documented", rm.get_current_objective().begins_with("Log the collected"), rm.get_current_objective())
	pc.interact()
	await _frames(60)
	ui._on_field_log_open()
	await _frames(30)
	var rows := [[ui._dropdown_anomaly_a, ui._pop_input_a, "Nest Alpha"],
			[ui._dropdown_anomaly_b, ui._pop_input_b, "Nest Beta"],
			[ui._dropdown_anomaly_c, ui._pop_input_c, "Nest Gamma"]]
	for row in rows:
		var answer: Dictionary = ui.NEST_ANSWER_KEY[row[2]]
		for i in row[0].item_count:
			if row[0].get_item_text(i) == answer.anomaly:
				row[0].select(i)
		row[1].text = answer.pop
	ui._on_correlate_data()
	var dozed := false
	var shut := false
	var blinks := 0
	var peak := 0.0
	var trough := 0.0
	var rising := true
	for i in 60 * 14:
		await process_frame
		var eyes: Node = ui.get_node_or_null("UploadDoze")
		if eyes:
			dozed = true
			var amount: float = eyes.lids_amount()
			shut = shut or amount > 0.99
			# A blink: the lids closing, then opening again.
			if rising:
				peak = maxf(peak, amount)
				if amount < peak - 0.1:
					blinks += 1
					rising = false
					trough = amount
			else:
				trough = minf(trough, amount)
				if amount > trough + 0.1:
					rising = true
					peak = amount
	var nm: Node = root.get_node("NightManager")
	ui.close_computer()
	paused = false
	_check("4: logging the data, the eyelids blink, shut (%d blinks), then night has fallen and they're gone" % blinks,
		dozed and shut and blinks >= 2 and nm.is_night_active and ui.get_node_or_null("UploadDoze") == null,
		"dozed %s, shut %s, night %s, still there %s" % [dozed, shut, nm.is_night_active, ui.get_node_or_null("UploadDoze") != null])
