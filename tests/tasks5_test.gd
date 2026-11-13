extends SceneTree
## planning/tasks.txt, round 5:
##   1. "Find the flashlight." takes over the objective when Night 1 falls
##      without one, and hands it back once the flashlight is found;
##   5. the gravel road: under the parked van, along the escape drive;
##   6. the Hallroom window's sounds are outside the room's reverb;
##   7. the stash: centred, the two grids inside their panels, no overlap;
##   8. car parts can only be salvaged once the van was looked at on Day 3;
##   and after: the road runs on to the "road_ending" marker between the
##   trees, the escape drive follows its bend, and the display mode setting.
## (2-4: audio_test; 9: shy_test.)
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/tasks5_test.gd

var _failures := 0
var _scene: Node
var _player: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS5 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_player = get_first_node_in_group("player")
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true
	root.get_node("NightManager").is_time_paused = true

	_test_flashlight_objective()
	_test_road()
	_test_hall_window_sound()
	await _test_stash()
	_test_car_parts()
	_test_road_ending()
	_test_display_mode()

	print("[TASKS5 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_flashlight_objective() -> void:
	var rm: Node = root.get_node("RoutineManager")
	# With a flashlight already: the computer interaction goes straight to
	# the fuse box (no flashlight step).
	_player._has_flashlight = true
	rm.main_objective = 2
	rm.phase2_computer_tried_no_power = false
	rm.flashlight_needed = false
	rm.on_computer_tried_no_power()
	var no_step: bool = rm.main_objective == 4 and rm.get_current_objective() == "Check the fuse box." and not rm.flashlight_needed
	# Without a flashlight: the computer interaction surfaces the
	# "Find the flashlight." objective; picking it up hands back to the
	# fuse box.
	_player._has_flashlight = false
	rm.phase2_computer_tried_no_power = false
	rm.flashlight_needed = false
	rm.on_computer_tried_no_power()
	var took_over: String = rm.get_current_objective()
	rm.on_flashlight_picked_up()
	var back: String = rm.get_current_objective()
	_check("objective: with a flashlight the computer goes straight to the fuse box; without one, \"Find the flashlight.\" takes over after the computer, then hands back",
		no_step and took_over == "Find the flashlight." and back == "Check the fuse box." and not rm.flashlight_needed,
		"%s -> %s -> %s" % ["fuse box" if no_step else str(rm.main_objective), took_over, back])


func _test_road() -> void:
	var road = _scene.get_node("GravelRoad")
	var van: Node3D = _scene.get_node("EscapeVan")
	var cinematics = _scene.find_child("Cinematics", true, false)
	var off := 0
	for d in range(0, 125, 5):
		var p: Vector3 = cinematics.road_start + cinematics.road_direction.normalized() * d
		if p.x < 85.0 and not road.covers(p):   # (then it bends south: _test_road_ending)
			off += 1
	_check("road: a gravel road under the parked van and along the straight of the escape drive",
		road.get_child(0, true).mesh != null and road.covers(van.global_position) and off == 0
			and _scene.get_node_or_null("SM_EC_Path_Mud_00") == null, "%d points of the drive off it" % off)


func _test_hall_window_sound() -> void:
	var window: Node = _scene.get_node("Windows/BottomFloorWindows/HallWindowRight")
	var sound: Node3D = window.get("_hammer_sound")
	var query := PhysicsPointQueryParameters3D.new()
	query.position = sound.global_position
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var reverb := []
	for hit in _scene.get_world_3d().direct_space_state.intersect_point(query, 16):
		if hit.collider is Area3D and hit.collider.reverb_bus_enabled:
			reverb.append(hit.collider.name)
	_check("Hallroom window: its boarding sounds aren't drowned in the room's reverb", reverb.is_empty(), str(reverb))


func _rect(c: Control) -> Rect2:
	return Rect2(c.global_position, c.size)


func _test_stash() -> void:
	root.size = Vector2i(1920, 1080)
	var inv: Node = root.get_node("Inventory")
	var saved: Array = inv.items.duplicate()
	var heap: Node = null
	for n in _scene.find_children("*", "", true, false):
		if n.get_script() and str(n.get_script().resource_path).ends_with("scrap_heap.gd"):
			heap = n
			break
	var item = load("res://resources/portable_light_resource.tres")
	inv.items.clear()
	for i in 10:
		inv.items.append(item)
	var contents := []
	for i in 12:
		contents.append({"item_data": item, "quantity": 1 + i % 3})
	var ui: Node = load("res://scenes/stash_ui.tscn").instantiate()
	_scene.add_child(ui)
	await _frames(3)
	ui.open_container_stash(heap, contents)
	await _frames(5)
	var panel: Control = ui.get_node("StashPanel")
	var screen := Rect2(Vector2.ZERO, Vector2(root.size))
	var left: Control = panel.get_node("Layout/Panels/PlayerInventoryPanel")
	var right: Control = panel.get_node("Layout/Panels/ContainerPanel")
	var outside := 0
	for grid in [ui._player_grid, ui._container_grid]:
		var owner_panel: Control = grid.get_parent().get_parent()
		for b in grid.get_children():
			if not _rect(owner_panel).grow(-2).encloses(_rect(b)):
				outside += 1
	var buttons := [ui._take_all_button, ui._store_all_button, ui._close_button].all(func(b): return _rect(panel).encloses(_rect(b)))
	_check("stash: centred on screen, the two panels apart, every slot and button inside its panel",
		(_rect(panel).get_center() - screen.get_center()).length() < 2.0 and not _rect(left).intersects(_rect(right))
			and outside == 0 and buttons, "panel %s, %d slots outside" % [_rect(panel), outside])
	ui._close_stash()
	ui.queue_free()
	inv.items = saved


func _test_car_parts() -> void:
	var rm: Node = root.get_node("RoutineManager")
	var nm: Node = root.get_node("NightManager")
	var inv: Node = root.get_node("Inventory")
	var wreck: Node = null
	for n in _scene.find_children("*", "", true, false):
		if n.get_script() and str(n.get_script().resource_path).ends_with("wreck_salvage.gd") and n.item_resource:
			wreck = n
			break
	nm.current_night = 3
	rm.is_day3_sandbox = true
	rm.van_inspected = false
	_player.is_exhausted = false
	var saved: Array = inv.items.duplicate()
	inv.items.clear()
	wreck.interact(_player)
	var blocked: bool = not wreck.is_looted and inv.items.is_empty()
	rm.van_inspected = true
	wreck.interact(_player)
	var looted: bool = wreck.is_looted and inv.items.size() == 1
	_check("car parts: not until the van is looked at again on Day 3, then they can be salvaged",
		blocked and looted, "blocked=%s looted=%s" % [blocked, looted])
	inv.items = saved


func _test_road_ending() -> void:
	var marker: Node3D = _scene.get_node("road_ending")
	var line := GravelRoad.centre_points()
	var end := line[line.size() - 1]
	var trees := 0
	for c in _scene.find_children("*", "CollisionShape3D", true, false):
		if not c.disabled and str(c.get_path()).contains("Group of Trees") and GravelRoad.covers(c.global_position, 0.6):
			trees += 1
	# Drivable: no bend tighter than 12 m (radius through points 4 m apart).
	var tightest := INF
	for i in range(4, line.size() - 4):
		var a: Vector2 = line[i - 4]
		var b: Vector2 = line[i]
		var c: Vector2 = line[i + 4]
		var area := absf((b - a).cross(c - a)) * 0.5
		if area > 0.0001:
			tightest = minf(tightest, a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (4.0 * area))
	_check("road: on to the road_ending marker, no tree on it, no bend a car couldn't take",
		end.distance_to(Vector2(marker.global_position.x, marker.global_position.z)) < 0.1 and trees == 0 and tightest > 12.0,
		"end %s, %d trees, tightest bend %.1f m" % [end, trees, tightest])

	# The escape drive follows the bend.
	var cinematics = _scene.find_child("Cinematics", true, false)
	if cinematics._setup_van():
		var off := 0
		for d in range(0, int(GravelRoad.length() - GravelRoad.project(cinematics.road_start)), 4):
			cinematics._v_distance = float(d)
			if not GravelRoad.covers(cinematics._van_position(), -0.5):
				off += 1
		_check("escape drive: the van follows the road round its bend", off == 0, "%d points off it" % off)
	else:
		_check("escape drive: the van", false, "no van")


func _test_display_mode() -> void:
	var menu: Node = load("res://scenes/ui/options_menu.tscn").instantiate()
	_scene.add_child(menu)
	var option: OptionButton = menu.find_child("DisplayModeOption", true, false)
	var names := []
	if option:
		for i in option.item_count:
			names.append(option.get_item_text(i))
	# (Through the instance: naming the class here would compile it before
	# the autoloads it uses exist.)
	var had: int = menu.saved_display_mode()
	if option:
		option.select(2)
		option.item_selected.emit(2)
	var saved: int = menu.saved_display_mode()
	menu.save_display_mode(had)
	menu.queue_free()
	_check("settings: Display Mode offers Windowed, Borderless and Fullscreen, and remembers the choice",
		names == ["Windowed", "Borderless", "Fullscreen"] and saved == 2, str(names))
