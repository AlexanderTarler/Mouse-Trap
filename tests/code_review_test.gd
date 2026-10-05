extends SceneTree
## The fixes from the code review (planning/code_review.txt):
##   - Jolt physics with room for every body in the level;
##   - NightManager's throttled timers run in real time (the dawn door lock
##     after ~3 s in the hall), and find the hall ("Hallroom");
##   - highlights put back the mesh's own material and culling;
##   - the UI is found by group;
##   - the bed ignores E while a sleep sequence runs;
##   - the sound manager's footsteps, and the battery swap sound;
##   - reading a note adds it to the notebook and removes it cleanly;
##   - GameTime keeps real time (no ~8% drift from its 5 Hz tick);
##   - the flashlight reports its battery in steps, not every frame;
##   - refusal/feedback lines show as thoughts (Monologue.say);
##   - the Entity walks past a path point right above it;
##   - after the lamp's stun: a committed chase, and no totem teleport until
##     the player is back in the cabin.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/code_review_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[REVIEW TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)

	_test_physics()
	await _test_dawn_door_lock()
	await _test_highlight_restore()
	_test_groups()
	await _test_bed_guard()
	_test_sounds()
	await _test_note()
	await _test_game_time()
	await _test_battery_signal()
	await _test_feedback_thoughts()
	await _test_overhead_path_point()
	await _test_post_stun()

	print("[REVIEW TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_physics() -> void:
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	var limit: int = ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_bodies", 0)
	var bodies := _scene.find_children("*", "CollisionObject3D", true, false).size()
	_check("physics: Jolt, with room for all %d bodies (limit %d)" % [bodies, limit],
		engine == "Jolt Physics" and limit > bodies)


func _test_dawn_door_lock() -> void:
	var nm: Node = root.get_node("NightManager")
	var player := get_first_node_in_group("player") as CharacterBody3D
	var door: Node = get_first_node_in_group("Door")
	var hall := _scene.get_node("NavigationRegion3D/Cabin/Hallroom/Marker3D") as Node3D
	var was_day: bool = nm.is_day_active
	nm.is_day_active = true
	door.is_locked = false
	player.global_position = hall.global_position + Vector3.UP * 0.2
	await _frames(10)
	var room: String = player.get_player_room()
	nm._awaiting_door_lock = true
	nm._door_lock_delay_timer = 0.0
	# 3 s after reaching the hall (plus a tick): locked. It used to take ~36 s.
	await _frames(int(60 * 3.6))
	_check("dawn: the door locks ~3 s after the player reaches the hall (room '%s')" % room,
		door.is_locked and not nm._awaiting_door_lock, "locked=%s waiting=%s" % [door.is_locked, nm._awaiting_door_lock])
	nm._awaiting_door_lock = false
	door.is_locked = false
	nm.is_day_active = was_day


func _test_highlight_restore() -> void:
	var rm: Node = root.get_node("RoutineManager")
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var own := StandardMaterial3D.new()
	own.albedo_color = Color.RED
	mesh.set_surface_override_material(0, own)
	mesh.extra_cull_margin = 0.5
	mesh.add_to_group("xray_review_test")
	_scene.add_child(mesh)
	var was_enabled: bool = rm.enable_object_highlights
	rm.enable_object_highlights = true
	rm.highlight_target("xray_review_test")
	var lit: Material = mesh.get_surface_override_material(0)
	var highlighted: bool = lit != own and lit.next_pass != null and mesh.custom_aabb.size.x > 100.0
	rm.clear_highlight("xray_review_test")
	var restored: bool = mesh.get_surface_override_material(0) == own and is_equal_approx(mesh.extra_cull_margin, 0.5) \
		and mesh.custom_aabb.size == Vector3.ZERO
	_check("highlight: on (outline, never culled), then the mesh's own material and culling come back",
		highlighted and restored, "highlighted=%s restored=%s" % [highlighted, restored])
	rm.enable_object_highlights = was_enabled
	mesh.queue_free()
	await _frames(1)


func _test_groups() -> void:
	var missing := []
	for group in ["hud", "player", "inventory_ui", "note_ui", "computer_ui", "environment_controller", "perception_manager"]:
		if get_first_node_in_group(group) == null:
			missing.append(group)
	var notebook_found := get_first_node_in_group("notebook_ui") != null
	_check("the UI is found by group (no level paths)", missing.is_empty() and notebook_found, str(missing))


func _test_bed_guard() -> void:
	var bed: Node = null
	for node in _scene.find_children("*", "", true, false):
		var s: Script = node.get_script()
		if s and s.resource_path.ends_with("bed_interactable.gd"):
			bed = node
	var nm: Node = root.get_node("NightManager")
	var night: int = nm.current_night
	bed._busy = true
	bed.interact()
	await _frames(5)
	_check("bed: E while a sleep sequence runs does nothing", nm.current_night == night and bed._busy)
	bed._busy = false


func _test_sounds() -> void:
	var hsm: Node = root.get_node("HorrorSoundManager")
	var inventory_ui: Node = get_first_node_in_group("inventory_ui")
	_check("sound: wooden and grass footsteps loaded (unused surfaces aren't); the battery swap sound exists",
		hsm._wooden_footstep_streams.size() > 0 and hsm._grass_footstep_streams.size() > 0
		and not "_carpet_footstep_streams" in hsm and ResourceLoader.exists(inventory_ui.BATTERY_SWAP_SOUND))


func _test_note() -> void:
	var note := _scene.get_node_or_null("Note")
	var note_ui: Node = get_first_node_in_group("note_ui")
	if not note:
		_check("note: a note to read", false)
		return
	var connections_before: int = note_ui.note_closed.get_connections().size()
	note.interact()
	await _frames(2)
	note_ui.note_closed.emit()
	await _frames(3)
	_check("note: read and closed, it's added and removed, with no connection left behind",
		not is_instance_valid(note) and note_ui.note_closed.get_connections().size() == connections_before,
		"connections %d -> %d" % [connections_before, note_ui.note_closed.get_connections().size()])


func _test_game_time() -> void:
	var gt: Node = root.get_node("GameTime")
	var paused: bool = gt.is_time_paused
	gt.is_time_paused = false
	gt.speed_multiplier = 1.0
	var before: float = gt._elapsed
	await _frames(600)
	var advanced: float = gt._elapsed - before
	gt.is_time_paused = paused
	_check("GameTime: 10 s of play advance the clock ~10 s (%.2f s)" % advanced, absf(advanced - 10.0) < 0.35)


func _test_battery_signal() -> void:
	var player: Node = get_first_node_in_group("player")
	var flashlight: Node = player._flashlight
	var had: bool = player._has_flashlight
	player._has_flashlight = true
	var count := [0]
	var counter := func(_level: float): count[0] += 1
	flashlight.battery_changed.connect(counter)
	flashlight.battery_level = flashlight.max_battery
	flashlight.is_on = true
	await _frames(120)
	flashlight.is_on = false
	flashlight.battery_changed.disconnect(counter)
	player._has_flashlight = had
	_check("flashlight: battery reported in steps (%d times in 2 s, not 120)" % count[0], count[0] > 0 and count[0] < 40)


func _test_feedback_thoughts() -> void:
	var hud: Node = get_first_node_in_group("hud")
	var monologue: Node = root.get_node("Monologue")
	monologue._clear()
	hud.show_message("I should lock the door first.")
	await _frames(2)
	var shown: bool = is_instance_valid(monologue._thought) and monologue._said == "I should lock the door first."
	# Again while showing: not restarted; a story thought isn't interrupted.
	var first: Node = monologue._thought
	hud.show_message("I should lock the door first.")
	var same: bool = monologue._thought == first
	monologue._clear()
	monologue.think("A story thought.", null, 3.0, "review_story")
	var story: Node = monologue._thought
	hud.show_message("Inventory is full!")
	var kept: bool = monologue._thought == story
	monologue._clear()
	_check("feedback lines show as thoughts; repeats don't restart; story thoughts aren't interrupted",
		shown and same and kept, "shown=%s same=%s kept=%s" % [shown, same, kept])


## The Entity's agent with a path point 0.7 m straight above it: the reach
## distance stretches to cover the gap (it used to stand there for good).
func _test_overhead_path_point() -> void:
	var entity: Node = get_first_node_in_group("entity")
	var src := FileAccess.get_file_as_string("res://scripts/entity/entity.gd")
	_check("entity: a path point right overhead counts as reached (move_to)",
		"nav_agent.path_desired_distance = gap + 0.2" in src and entity.PATH_DESIRED_DISTANCE == 0.6)


## The lamp's stun wears off with the player outside: a committed charge,
## and the totem defence stays off until the player is in the cabin again.
func _test_post_stun() -> void:
	var entity: Node = get_first_node_in_group("entity")
	var player := get_first_node_in_group("player") as Node3D
	var hall := _scene.get_node("NavigationRegion3D/Cabin/Hallroom/Marker3D") as Node3D
	entity.can_kill = false
	player.global_position = Vector3(20.0, 0.5, 4.0)
	entity.activate()
	entity._teleport(Vector3(40.0, 0.5, 30.0))
	entity.request_state(entity.State.STUNNED, {"duration": 0.5})
	await _frames(20)
	var during: bool = entity.totem_defense_disabled
	await _frames(40)
	var charge = entity.brain._states.get(entity.State.CHARGE)
	var chasing: bool = entity.get_state() == entity.State.CHARGE and charge._committed \
		and is_equal_approx(charge._max_time, entity.config.post_stun_chase_time)
	var still_off: bool = entity.totem_defense_disabled
	player.global_position = hall.global_position + Vector3.UP * 0.2
	await _frames(30)
	var back_on: bool = not entity.totem_defense_disabled
	entity.deactivate()
	entity.can_kill = true
	_check("stun: then a committed chase; no totem teleport until the player is back in the cabin",
		during and chasing and still_off and back_on,
		"during=%s chasing=%s (%s) still_off=%s back_on=%s" % [during, chasing, entity.get_state_name(), still_off, back_on])
