extends SceneTree
## Endings: the three cutscenes play through and hand over to their screens.
##   Mediocre escape: the van drives off down the road, the Entity stands in
##     the road behind, then rides on the roof; the ending screen follows and
##     the game's volume comes back afterwards.
##   Good escape: dawn, the van leaves, the dead ground where the totem stood.
##   Death: dragged to the willow, hoisted up; the death screen follows with
##     the player's own camera back. The second death is short, and a key
##     press skips it.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/endings_test.gd

var _failures := 0
var _scene: Node
var _em: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await _frames(int(s * 60.0))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[ENDINGS TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _load_scene() -> void:
	if _scene:
		_scene.queue_free()
		await _frames(3)
	paused = false
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(70)   # the NightManager's delayed spawn setup


func _run() -> void:
	_em = root.get_node("EndgameManager")
	await _load_scene()
	await _test_mediocre()
	_em.reset()
	await _load_scene()
	await _test_good()
	_em.reset()
	await _load_scene()
	await _test_death()

	print("[ENDINGS TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _ending_screen() -> Node:
	var layer := _scene.get_node_or_null("_EndgameUILayer")
	return layer.get_child(0) if layer and layer.get_child_count() > 0 else null


func _wait_for_ending(max_seconds: float) -> float:
	var waited := 0.0
	while _em.is_sequence_playing and waited < max_seconds:
		await _frames(6)
		waited += 0.1
	return waited


func _test_mediocre() -> void:
	var master := AudioServer.get_bus_index("Master")
	var volume_before := AudioServer.get_bus_volume_db(master)
	var van: Node3D = _scene.get_node("EscapeVan")
	var entity: Node3D = get_first_node_in_group("entity")
	var cinematics: Node = get_first_node_in_group("cinematics")
	_em.start_ending_sequence(false)
	var start: Vector3 = cinematics.road_start

	await _seconds(6.2)
	var cam := root.get_viewport().get_camera_3d()
	var dir: Vector3 = cinematics.road_direction.normalized()
	var behind := (entity.global_position - van.global_position).dot(dir)
	_check("mediocre: the van drives off; from its rear the Entity stands in the road behind",
		cam == cinematics.mediocre_cam and entity.visible and behind < -3.0 and behind > -15.0
		and (van.global_position - start).dot(dir) > 15.0,
		"camera %s, Entity %.1f m behind, van %.1f m down the road" % [cam.name if cam else "none", -behind, (van.global_position - start).dot(dir)])

	await _seconds(3.4)
	var on_roof: bool = entity.global_position.y > van.global_position.y + 2.0 \
		and Vector2(entity.global_position.x - van.global_position.x, entity.global_position.z - van.global_position.z).length() < 2.5
	_check("mediocre: then it rides on the van's roof", on_roof,
		"Entity %s, van %s" % [entity.global_position.snapped(Vector3.ONE * 0.1), van.global_position.snapped(Vector3.ONE * 0.1)])

	var waited: float = await _wait_for_ending(20.0)
	var screen := _ending_screen()
	var caption: Label = screen.find_child("EndingCountLabel", true, false) if screen else null
	_check("mediocre: the cutscene ends and the ending screen shows (\"Ending 1 of 2\")",
		not _em.is_sequence_playing and screen != null and caption != null and caption.text == "Ending 1 of 2" and paused,
		"after %.1f s more, screen=%s, caption=%s" % [waited, screen != null, caption.text if caption else "none"])
	_check("mediocre: the cutscene's black overlay is gone behind the ending screen",
		cinematics._black.color.a == 0.0)
	_em.reset()
	_check("volume: the game's sound comes back after the ending (reset)",
		absf(AudioServer.get_bus_volume_db(master) - volume_before) < 0.01,
		"%.1f dB before, %.1f dB after" % [volume_before, AudioServer.get_bus_volume_db(master)])


func _test_good() -> void:
	var van: Node3D = _scene.get_node("EscapeVan")
	var cinematics: Node = get_first_node_in_group("cinematics")
	var totem: Node3D = get_first_node_in_group("totem_anchor")
	var environment: Node = get_first_node_in_group("environment_controller")
	var start: Vector3 = cinematics.road_start
	_em.start_ending_sequence(true)
	await _seconds(5.0)
	var cam := root.get_viewport().get_camera_3d()
	var dawn: bool = environment.cycle_progress < 0.1 and environment.is_day
	_check("good: it is dawn, and the van pulls away past the camera",
		cam == cinematics.good_cam and dawn and (van.global_position - start).length() > 5.0,
		"camera %s, sky progress %.2f, van moved %.1f m" % [cam.name if cam else "none", environment.cycle_progress, (van.global_position - start).length()])
	await _seconds(4.5)
	var particles := cinematics.find_children("*", "GPUParticles3D", true, false)
	var near_totem: bool = cam.global_position.distance_to(totem.global_position) < 12.0
	_check("good: then the dead ground where the totem stood, ash rising",
		near_totem and not particles.is_empty(),
		"camera %.1f m from the totem, ash=%s" % [cam.global_position.distance_to(totem.global_position), not particles.is_empty()])
	await _wait_for_ending(20.0)
	var screen := _ending_screen()
	var caption: Label = screen.find_child("EndingCountLabel", true, false) if screen else null
	_check("good: the ending screen shows (\"Ending 2 of 2\")",
		screen != null and caption != null and caption.text == "Ending 2 of 2")


func _test_death() -> void:
	var cinematics: Node = get_first_node_in_group("cinematics")
	var jumpscare: Node = root.get_node("JumpscareManager") if root.has_node("JumpscareManager") else null
	if not jumpscare:
		for node in root.get_children():
			if node.has_method("_execute_jumpscare"):
				jumpscare = node
	var player: Node3D = get_first_node_in_group("player")
	var player_cam := root.get_viewport().get_camera_3d()
	var entity: Node3D = get_first_node_in_group("entity")
	var totem: Node3D = get_first_node_in_group("totem_anchor")
	_em.death_cutscenes_seen = 0
	entity.activate()
	entity.teleport(player.global_position + Vector3(0, 0, -2.0))
	jumpscare._execute_jumpscare()

	# Jumpscare 3.2 s + fade 0.5 s, then the cutscene: ~4 s in, being dragged.
	await _seconds(3.7 + 4.0)
	var cam := root.get_viewport().get_camera_3d()
	var low: bool = cam.global_position.y - totem.global_position.y < 1.0
	var toward: bool = cam.global_position.distance_to(totem.global_position) < 18.0
	var dragger: bool = entity.visible and entity.global_position.distance_to(cam.global_position) < 3.5
	_check("death: dragged along the ground towards the willow, the Entity just ahead",
		cam == cinematics.death_cam and low and toward and dragger,
		"camera %s at %s, %.1f m from the willow, Entity %.1f m away" % [cam.name if cam else "none",
			cam.global_position.snapped(Vector3.ONE * 0.1), cam.global_position.distance_to(totem.global_position),
			entity.global_position.distance_to(cam.global_position)])

	await _seconds(6.0)
	var high: bool = cam.global_position.y - totem.global_position.y > 2.5
	var stake: bool = not cam.find_children("*", "MeshInstance3D", true, false).is_empty()
	var trunk := Vector2(cam.global_position.x - totem.global_position.x, cam.global_position.z - totem.global_position.z)
	var facing := Vector2(-cam.global_basis.z.x, -cam.global_basis.z.z)
	var entity_below: bool = entity.global_position.y < cam.global_position.y - 2.0 		and Vector2(entity.global_position.x - totem.global_position.x, entity.global_position.z - totem.global_position.z).length() > trunk.length()
	_check("death: swung up into the tree, back to the trunk, looking down at it, impaled",
		high and stake and trunk.length() < 2.0 and facing.dot(trunk) > 0.0 and entity_below,
		"camera %.1f m up, %.1f m from the trunk, facing away=%s, Entity below and further out=%s, stake=%s" % [
			cam.global_position.y - totem.global_position.y, trunk.length(), facing.dot(trunk) > 0.0, entity_below, stake])

	var waited := 0.0
	while not _scene.has_node("DeathScreenCanvas") and waited < 10.0:
		await _frames(6)
		waited += 0.1
	var back_cam := root.get_viewport().get_camera_3d()
	_check("death: the death screen follows, on the player's own camera, with the black fade up",
		_scene.has_node("DeathScreenCanvas") and back_cam == player_cam and jumpscare._fade_rect.color.a == 1.0
		and cinematics._black.color.a == 0.0 and not cinematics.is_playing(),
		"screen=%s, camera %s" % [_scene.has_node("DeathScreenCanvas"), back_cam.name if back_cam else "none"])

	# Second death: the short version.
	_scene.get_node("DeathScreenCanvas").queue_free()
	paused = false
	await _frames(3)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	cinematics.cover()
	var short_done := false
	var run := func():
		await cinematics.play_death()
		short_done = true
	run.call()
	while cinematics.is_playing() and frames < 900:
		await _frames(1)
		frames += 1
	_check("death: the second time it is short", frames < 6 * 60, "%.1f s" % (frames / 60.0))

	# Third: skipped with a key press.
	frames = 0
	var skip := func():
		await cinematics.play_death()
	skip.call()
	await _frames(40)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.get_viewport().push_input(key)
	while cinematics.is_playing() and frames < 900:
		await _frames(1)
		frames += 1
	_check("death: a key press skips it", frames < 20, "%d frames after the key" % frames)
	_check("death: the HUD comes back after the cutscene", get_first_node_in_group("hud").visible)
