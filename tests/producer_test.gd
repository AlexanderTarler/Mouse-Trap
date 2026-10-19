extends SceneTree
## Producer mode (ProducerMode): Night 3; the ghost flies (through things),
## the replica stays in the cabin with a body, the Entity hunts the replica
## and can't kill it unless allowed.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/producer_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[PRODUCER TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	SaveGame.path = "user://producer_test_save.dat"
	await _frames(2)
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	var player := scene.get_node("Player")
	player.start_in_dev_mode = false
	player.producer_mode = true
	root.add_child(scene)
	current_scene = scene
	var nm: Node = root.get_node("NightManager")
	var producer: Node = null
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 240000:
		await _frames(10)
		producer = scene.get_node_or_null("ProducerMode")
		if producer:
			break
	await _frames(30)
	var entity := get_first_node_in_group("entity")
	_check("producer mode starts at Night 3", producer != null and nm.current_night == 3 and nm.is_night_active, "night %d" % nm.current_night)
	if not producer:
		_finish(scene)
		return
	var replica := player as Node3D
	_check("the ghost's camera is the one in use; the replica has a body and no controls",
		root.get_viewport().get_camera_3d() == producer.camera and replica.get_node_or_null("ReplicaBody") != null
		and not replica.is_physics_processing() and not replica.is_processing_input())
	_check("the Entity is out, after the replica (the player), and can't kill it",
		entity.is_active() and entity._player == replica and not entity.can_kill)
	# Flying: forward through the cabin's wall, the replica stays put.
	var ghost_was: Vector3 = producer.global_position
	var replica_was := replica.global_position
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	var flown: float = producer.global_position.distance_to(ghost_was)
	_check("the ghost flies (%.1f m in a second); the replica stays (%.2f m)" % [flown, replica.global_position.distance_to(replica_was)],
		flown > 3.0 and replica.global_position.distance_to(replica_was) < 0.05)
	# F: the flashlight; V: following the Entity, and still after the mouse
	# moves and a few seconds go by, until V again.
	var key_f := InputEventKey.new()
	key_f.physical_keycode = KEY_F
	key_f.pressed = true
	producer._unhandled_input(key_f)
	var lit: bool = producer.flashlight.visible
	var key_v := InputEventKey.new()
	key_v.physical_keycode = KEY_V
	key_v.pressed = true
	producer._unhandled_input(key_v)
	var nudge := InputEventMouseMotion.new()
	nudge.relative = Vector2(40, 5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	producer._unhandled_input(nudge)
	await _frames(60 * 6)
	var near: float = producer.global_position.distance_to((entity as Node3D).global_position)
	var still_following: bool = producer.following and near < producer.FOLLOW_DISTANCE + 2.0
	producer._unhandled_input(key_v)
	_check("F: a flashlight; V follows the Entity and keeps on (mouse moved, 6 s: %.1f m off) until V again" % near,
		lit and still_following and not producer.following)
	# K: kills allowed; ] faster time.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.pressed = true
	producer._unhandled_input(key)
	key.physical_keycode = KEY_BRACKETRIGHT
	producer._unhandled_input(key)
	_check("K lets the Entity kill, ] speeds time up", entity.can_kill and Engine.time_scale > 1.0)
	_finish(scene)


func _finish(scene: Node) -> void:
	print("[PRODUCER TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	Engine.time_scale = 1.0
	ProducerMode.requested = false
	SaveGame.delete()
	scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)
