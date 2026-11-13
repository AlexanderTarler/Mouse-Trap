extends SceneTree
## Screenshots of the Entity at the cabin's windows, to check by eye:
##   1. clinging outside the LandingRoom's window (twice, a second apart:
##      the climb pose should be frozen, the same both times), seen from the
##      yard;
##   2. leaving through a ground-floor window (the living room's): facing it,
##      crawling, a few frames as it goes;
##   3. leaving through the upstairs window it came in by.
## Prints its state, height and facing at each. Renders, so run WITHOUT
## --headless.
##   godot --path . --resolution 1280x720 --script res://tools/entity_window_shot.gd -- <out_prefix>


func _initialize() -> void:
	_go()


func _go() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://entity"
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	s.get_node("Player").dev_start = DevStart.Start.DAY_1   # (no opening)
	root.add_child(s)
	current_scene = s
	for i in 90:
		await process_frame
	var gt = root.get_node("GameTime")
	gt.is_time_paused = true
	gt.cycle_progress = 0.3
	gt._elapsed = 0.3 * gt.cycle_duration
	gt.time_changed.emit(0.3)
	get_first_node_in_group("environment_controller")._on_game_time_changed(0.3, true)
	var player: CharacterBody3D = get_first_node_in_group("player")
	player.global_position = Vector3(12.2, 3.9, 17.4)   # the bedroom
	player.set_physics_process(false)
	var entity = get_first_node_in_group("entity")
	entity.can_kill = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	s.add_child(cam)
	cam.current = true
	for layer in root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false

	# 1. Up the wall to the landing window.
	var link: CabinEntryLink = null
	for window in get_nodes_in_group("TopFloorWindows"):
		if window.name == "LandingWindow":
			link = window._entry_link
	entity.get_node("DebugOverlay").debug_landing_breach()
	for i in 60 * 30:
		await process_frame
		if entity.is_perched_at(link):
			break
	var outward: Vector3 = (link.start_position - link.end_position) * Vector3(1, 0, 1)
	cam.global_position = link.entry.global_position + outward.normalized() * 7.0 + Vector3(2.5, -2.0, 0.0)
	cam.look_at(entity.global_position + Vector3.UP * 1.0)
	for i in 20:
		await process_frame
	_shot(out + "_cling_a.png", entity, link)
	await _seconds(1.0)
	_shot(out + "_cling_b.png", entity, link)

	# 2. A ground-floor window, open: from inside, it leaves through it.
	var living: Node = null
	for window in get_nodes_in_group("WindowMarkers"):
		if window.name == "LivingRoomWindow":
			living = window
	living.shatter_window()
	for i in 6:
		living.damage_barricade()
	await _seconds(0.5)
	var ground_link: CabinEntryLink = living._entry_link
	entity._teleport(ground_link.end_position + (ground_link.end_position - ground_link.start_position).normalized() * 2.5 * Vector3(1, 0, 1))
	entity.debug_breach = false
	entity.request_state(entity.State.FLEE, {"calm": true})
	var out_dir: Vector3 = (ground_link.start_position - ground_link.end_position) * Vector3(1, 0, 1)
	cam.global_position = ground_link.end_position + out_dir.normalized() * 6.0 + Vector3(-3.0, 1.6, 0.0)
	cam.look_at(living.global_position)
	var shots := 0
	for i in 60 * 15:
		await process_frame
		if entity.is_traversing() and shots < 4 and i % 12 == 0:
			_shot(out + "_ground_%d.png" % shots, entity, ground_link)
			shots += 1
		if shots >= 4 or (shots > 0 and not entity.is_traversing()):
			break
	print("[ENTITY SHOT] ground window: %d shots" % shots)

	# 3. Out of the landing window again (open), down the wall.
	var landing: Node = link.entry
	landing.shatter_window()
	for i in 6:
		landing.damage_barricade()
	await _seconds(0.5)
	living.set("is_glass_shattered", false)
	entity._teleport(link.end_position + (link.end_position - link.start_position).normalized() * 1.5 * Vector3(1, 0, 1))
	entity.request_state(entity.State.FLEE, {"calm": true})
	cam.global_position = landing.global_position + outward.normalized() * 7.0 + Vector3(2.5, -2.0, 0.0)
	cam.look_at(landing.global_position + Vector3.DOWN * 1.5)
	shots = 0
	for i in 60 * 15:
		await process_frame
		if entity.is_traversing() and shots < 5 and i % 15 == 0:
			_shot(out + "_upper_%d.png" % shots, entity, link)
			shots += 1
		if shots > 0 and not entity.is_traversing():
			break
	print("[ENTITY SHOT] upstairs window: %d shots" % shots)
	quit()


func _seconds(s: float) -> void:
	for i in int(s * 60.0):
		await process_frame


func _shot(path: String, entity: Node3D, link: CabinEntryLink) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	var to_window: Vector3 = (link.entry.global_position - entity.global_position) * Vector3(1, 0, 1)
	var facing: Vector3 = entity.global_basis.z * Vector3(1, 0, 1)
	var anim: String = String(entity.animator.playback.get_current_node()) if entity.animator.playback else "?"
	var anim_speed: float = entity.animator.player.speed_scale if entity.animator.player else -1.0
	print("[ENTITY SHOT] %s: state %s, y %.2f, %.0f deg off facing the window, anim %s at %.2f" % [path.get_file(), entity.get_state_name(), entity.global_position.y, rad_to_deg(facing.angle_to(to_window)), anim, anim_speed])
