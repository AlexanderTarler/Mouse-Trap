extends SceneTree
## planning/tasks.txt round 3 (planning/tasks_plan.txt):
##   2  going to sleep and waking up in first person (SleepCinematic);
##      Night 2.2 wakes suddenly
##   7  the Peeker: animated, its head following the player, the eye glint,
##      leaning in from beside the frame, crouching away when seen
##   14 the mediocre ending: the Entity sits on the van's roof (not above
##      it), frozen mid-stride
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/regression/tasks8_test.gd

var _failures := 0
var _scene: Node
var _player: Node3D


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * 60.0))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS8 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_player = get_first_node_in_group("player")
	root.get_node("GameTime").is_time_paused = true
	root.get_node("NightManager").is_time_paused = true

	await _test_peeker()
	await _test_sleep()
	await _test_roof()

	print("[TASKS8 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _head(p) -> Transform3D:
	return p._skeleton.global_transform * p._skeleton.get_bone_global_pose(p._head_bone)


func _test_peeker() -> void:
	_player.global_position = Vector3(11.0, 4.0, 17.4)   # the bedroom
	await _frames(20)
	var cam: Camera3D = _player.get_node("CameraHolder/Camera3D")
	cam.look_at(cam.global_position + Vector3(-1, 0, 0))   # away from the window
	var pm: Node = root.get_node("PeekerManager")
	pm.force_spawn_at_window("Bedroom_Right")
	await physics_frame
	var p = pm._active_peeker
	var leaning: bool = p != null and absf(p._monster_model.position.x - p.model_offset.x) > 0.3
	await _seconds(3.0)
	var arrived: bool = not p._is_rising and p._monster_model.position.is_equal_approx(p.model_offset)
	var breathing: bool = p._anim.is_playing() and String(p._anim.current_animation).ends_with("idle")
	_check("7: the Peeker leans in from beside the frame and breathes (the Entity's idle)",
		leaning and arrived and breathing, "leaning=%s arrived=%s anim=%s" % [leaning, arrived, p._anim.current_animation])
	var head := _head(p)
	var facing := head.basis.z.normalized().dot((cam.global_position - head.origin).normalized())
	_player.global_position = Vector3(11.0, 4.0, 19.2)
	await _seconds(1.5)
	head = _head(p)
	var follows := head.basis.z.normalized().dot((cam.global_position - head.origin).normalized())
	_check("7: its head watches the player, and follows them (%.2f, then %.2f after moving)" % [facing, follows],
		facing > 0.85 and follows > 0.85)
	var glint: OmniLight3D = p._glint
	_check("7: the Entity's eye glint, at its eyes (%.2f m from the head, range %.1f m)" % [glint.global_position.distance_to(head.origin), glint.omni_range],
		glint.omni_range <= 1.0 and glint.global_position.distance_to(head.origin) < 0.6)
	cam.look_at(p.global_position)
	var gone := -1
	var crouched := false
	for i in 200:
		await physics_frame
		if not is_instance_valid(p):
			gone = i
			break
		crouched = crouched or (p._is_vanishing and String(p._anim.current_animation).ends_with("crouch"))
	_check("7: looked at, it holds the gaze, then crouches away and is gone (%.1f s)" % (gone / 60.0),
		crouched and gone > 60 and gone < 150)


func _test_sleep() -> void:
	var bed: Node3D = _scene.find_child("Bed", true, false)
	var sleep := SleepCinematic.new().setup(bed)
	bed.add_child(sleep)
	var hud: Node = get_first_node_in_group("hud")
	var cam: Camera3D = _player.get_node("CameraHolder/Camera3D")
	_player.global_position = Vector3(11.5, 4.0, 17.3)
	await _frames(5)
	var t0 := _frames_now()
	sleep.fall_asleep(_player)
	await physics_frame
	var own_cam: bool = cam.current
	await _seconds(2.4)
	var cinematic: Camera3D = get_viewport_camera()
	var lying: bool = cinematic != null and cinematic.name == "SleepCamera" \
		and (-cinematic.global_basis.z).dot(Vector3.UP) > 0.8 and cinematic.global_position.distance_to(sleep.pillow_top()) < 0.6
	while sleep.is_running():
		await physics_frame
	var asleep_time := (_frames_now() - t0) / 60.0
	var black: bool = hud._fade_overlay.color.a > 0.99
	_check("2: going to sleep: onto the pillow looking up, the eyes closing, to black (%.1f s)" % asleep_time,
		not own_cam and lying and black and asleep_time > 2.5 and asleep_time < 6.0, "lying=%s black=%s" % [lying, black])

	t0 = _frames_now()
	await sleep.wake_up(_player, false)
	var wake_time := (_frames_now() - t0) / 60.0
	var stand: Vector3 = sleep.stand_position()
	var box: AABB = sleep.bed_box()
	var beside: bool = _player.global_position.distance_to(stand) < 0.3 and not box.grow(-0.05).has_point(Vector3(_player.global_position.x, box.get_center().y, _player.global_position.z))
	var facing_room: bool = (-_player.global_basis.z).dot(sleep.feet_direction()) > 0.9
	var body := CapsuleShape3D.new()
	body.radius = 0.3
	body.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.transform = Transform3D(Basis.IDENTITY, stand + Vector3.UP * 0.9)
	query.exclude = [_player.get_rid()]
	var hits: Array = _player.get_world_3d().direct_space_state.intersect_shape(query, 8)
	var clear := hits.is_empty()
	_check("2: the spot by the bed is clear (no wall or furniture: %s)" % str(hits.map(func(h): return h.collider.name)), clear)
	_check("2: waking up: the eyes open, sit up, standing by the bed facing the room (%.1f s)" % wake_time,
		cam.current and beside and facing_room and hud._fade_overlay.color.a < 0.01 and wake_time > 3.0 and _player.is_physics_processing(),
		"beside=%s facing=%s" % [beside, facing_room])

	hud.fade_to_black(0.01)
	await _frames(3)
	t0 = _frames_now()
	await sleep.wake_up(_player, true)
	var sudden_time := (_frames_now() - t0) / 60.0
	_check("2: Night 2.2, the alarm: awake and out of bed fast (%.1f s)" % sudden_time, sudden_time < 1.6 and cam.current)
	var bed_script := (load("res://scripts/cabin/bed_interactable.gd") as Script).source_code
	_check("2: every way to bed uses it (sleep and wake), Night 2.2 wakes suddenly",
		bed_script.count("fall_asleep(player)") == 4 and bed_script.count("wake_up(player") == 4 and bed_script.contains("wake_up(player, true)"))


func _frames_now() -> int:
	return Engine.get_physics_frames()


func get_viewport_camera() -> Camera3D:
	return root.get_viewport().get_camera_3d()


func _test_roof() -> void:
	var cin: Node = _scene.find_child("Cinematics", true, false)
	var entity = get_first_node_in_group("entity")
	cin.play_ending_cinematic(1)
	var waited := 0
	while cin._e_mode != cin.EntityMode.ROOF and waited < 60 * 30:
		await physics_frame
		waited += 1
	await _frames(30)
	var low: float = cin._lowest_contact(entity)
	var roof: float = cin._roof_at(entity.global_position)
	var playback = entity.animator.tree.get("parameters/playback")
	var at: float = playback.get_current_play_position()
	await _frames(20)
	var still: bool = is_equal_approx(at, playback.get_current_play_position())
	_check("14: on the van's roof, its lowest hand or foot on it (%.2f m vs the roof %.2f m), frozen mid-stride" % [low, roof],
		absf(low - roof) < 0.08 and still, "frozen=%s" % still)
