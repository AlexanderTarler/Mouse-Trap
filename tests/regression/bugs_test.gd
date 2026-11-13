extends SceneTree
## The bugs.txt round:
##   1. The trap: the cable sags and lies on the ground, the light sits on it.
##   2/6. Dying restores the start of the night / day (Checkpoint).
##   3/9. The sprint hint shows over other hints and stays until stamina 70%.
##   4. The willow's canopy has no collision (heavy physics near the totem).
##   5. A storm breaks after documenting Nest Gamma and lasts until Day 3.
##   7. The side-track objectives tick off.
##   8. Fuel cans show their fuel in %; a dropped can keeps its fuel.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/regression/bugs_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[BUGS TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(90)
	# Hints go at once here (bugs4_test covers their minimum time up).
	root.get_node("TutorialManager").min_hint_time = 0.0
	root.get_node("NightManager").is_time_paused = true

	_test_canopy()
	_test_fuel_display()
	await _test_objectives()
	await _test_trap()
	await _test_sprint_hint()
	await _test_storm()
	await _test_night_checkpoint()
	await _test_day_checkpoint()

	print("[BUGS TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _inventory() -> Node:
	return root.get_node("Inventory")


func _item(path: String) -> Resource:
	return (load(path) as Resource).duplicate()


func _test_canopy() -> void:
	var totem: Node = get_first_node_in_group("totem_anchor")
	var shape := totem.get_node_or_null("Weeping Willow/Weeping Willow/StaticBody3D/CollisionShape3D") as CollisionShape3D
	_check("#4 totem: the willow's canopy mesh has no collision (the trunk keeps its own)",
		shape != null and shape.disabled and totem.get_node_or_null("CollisionShape3D") != null)


func _test_fuel_display() -> void:
	var can: Resource = _item("res://resources/fuel_can_resource.tres")
	can.fuel_amount = 62.4
	var pickup: Node = (load("res://scenes/fuel_can.tscn") as PackedScene).instantiate()
	pickup.item_data = can
	_scene.add_child(pickup)
	_check("#8 fuel can: shows its fuel in %, on the item and on the pickup prompt",
		can.get_display_name() == "Fuel Can (62%)" and "(62%)" in pickup.get_interact_text(),
		"%s / %s" % [can.get_display_name(), pickup.get_interact_text()])
	pickup.queue_free()


func _test_objectives() -> void:
	var rm: Node = root.get_node("RoutineManager")
	var inventory := _inventory()
	inventory.add_item(_item("res://resources/fuel_can_resource.tres"))
	rm.arvid_note_2_found = false
	rm.arvid_fuel_can_found = false
	rm.on_arvid_note_2_found()
	_check("#7 'Find fuel can': a can already carried counts when the track starts", rm.arvid_fuel_can_found)

	var totem: Node3D = get_first_node_in_group("totem_anchor")
	var player: Node3D = get_first_node_in_group("player")
	rm.arvid_anchor_located = false
	totem._anchor_located_notified = false
	totem.global_position.y -= 5.0   # buried, as by day
	player.global_position = totem.global_position + Vector3(-7.0, 5.2, 0.0)
	await _frames(5)
	_check("#7 'Locate anchor': standing near the buried totem counts", rm.arvid_anchor_located)
	totem.global_position.y += 5.0


func _test_trap() -> void:
	var rm: Node = root.get_node("RoutineManager")
	rm.is_cable_to_gen_connected = false
	rm.is_cable_to_light_connected = false
	rm.is_trap_triggered = false
	var outlet: Node3D = get_first_node_in_group("generator_outlet")
	var player: Node3D = get_first_node_in_group("player")
	player.global_position = outlet.global_position + Vector3(3.0, -1.2, 0.0)
	await _frames(5)
	_inventory().add_item(_item("res://resources/cable_spool_resource.tres"))
	_inventory().add_item(_item("res://resources/portable_light_resource.tres"))
	outlet.interact()
	await _frames(10)
	_check("#7 'Set trap': connecting spool and light at the generator completes it",
		rm.is_cable_to_gen_connected and rm.is_cable_to_light_connected)
	player.global_position += Vector3(6.0, 0.0, 0.0)   # the open yard east of the generator
	await _frames(20)
	var grab: Node = get_first_node_in_group("physical_grab")
	grab._drop_carried_lamp()
	await _frames(120)
	var lamp: Node3D = null
	for node in get_nodes_in_group("portable_trap"):
		if node.has_method("drop_trap") and node.is_deployed:
			lamp = node
	var cable: Node = get_first_node_in_group("power_cable")
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var probe := PhysicsRayQueryParameters3D.create(lamp.global_position + Vector3.UP, lamp.global_position + Vector3.DOWN * 3.0, 1)
	probe.exclude = [lamp.get_rid()]
	var ground: Dictionary = space.intersect_ray(probe)
	# The lowest corner of its collision box, however it landed.
	var box_node: CollisionShape3D = lamp.get_node("CollisionShape3D")
	var half: Vector3 = (box_node.shape as BoxShape3D).size / 2.0
	var lamp_bottom := INF
	for corner in 8:
		var local := Vector3(half.x * (1 if corner & 1 else -1), half.y * (1 if corner & 2 else -1), half.z * (1 if corner & 4 else -1))
		lamp_bottom = minf(lamp_bottom, (box_node.global_transform * local).y)
	var resting: bool = not ground.is_empty() and absf(lamp_bottom - ground.position.y) < 0.08
	var points: PackedVector3Array = cable._cable_points
	var below_line := 0
	var under_ground := 0
	for i in range(1, points.size() - 1):
		var t := float(i) / float(points.size() - 1)
		var straight: Vector3 = points[0].lerp(points[points.size() - 1], t)
		if points[i].y < straight.y - 0.05:
			below_line += 1
		if points[i].y < 0.0:
			under_ground += 1
	_check("#1 trap: the light rests on the ground and the connected cable sags onto it",
		resting and cable.get_state() == 2 and lamp.is_powered and below_line > points.size() / 2 and under_ground == 0,
		"lamp bottom %.2f vs ground %.2f, %d of %d cable points sag, %d under ground" % [lamp_bottom, ground.position.y if ground else NAN, below_line, points.size(), under_ground])

	# An undeployed light lying elsewhere must not be the one overloaded.
	var spare: Node3D = (load("res://scenes/portable_light.tscn") as PackedScene).instantiate()
	_scene.add_child(spare)
	_scene.move_child(spare, 0)
	spare.global_position = Vector3(30, 1, 30)
	var computer: Node = _scene.find_child("ComputerUI", true, false)
	_check("#7 overload: the deployed, powered light is the one chosen", computer._best_portable_lamp() == lamp)
	spare.queue_free()


func _test_sprint_hint() -> void:
	var tm: Node = root.get_node("TutorialManager")
	var rm: Node = root.get_node("RoutineManager")
	var hud: Node = get_first_node_in_group("hud")
	rm._learned_mechanics.erase("sprint")
	tm._shown.erase("sprint")
	# Another hint is on screen.
	hud.show_hint("Some other hint", 0.0)
	await _frames(40)
	tm.trigger("sprint", true)
	await _frames(40)
	var shown: bool = "sprint" in hud.hint_label.text.to_lower() and hud.hint_label.modulate.a > 0.5
	tm.mark_learned("flashlight")
	await _frames(40)
	var survived: bool = "sprint" in hud.hint_label.text.to_lower() and hud.hint_label.modulate.a > 0.5
	tm.mark_learned("sprint")
	await _frames(40)
	_check("#3/#9 sprint hint: shows over another hint, survives other tutorials, goes once learned",
		shown and survived and hud.hint_label.modulate.a < 0.1,
		"shown=%s, survived flashlight=%s, alpha after %.2f" % [shown, survived, hud.hint_label.modulate.a])


func _test_storm() -> void:
	var weather: Node = root.get_node("Weather")
	var player: Node3D = get_first_node_in_group("player")
	player.global_position = Vector3(30.0, 0.5, -20.0)
	var gamma: Node = null
	for nest in _scene.get_node("NestLocations").get_children():
		if nest.nest_label == "Nest Gamma":
			gamma = nest
	# Document it (its stillness lock lifted for the test).
	gamma.is_documented = false
	gamma.lock_type = "none"
	gamma.interact()
	var started: bool = weather._target > 0.0
	await _frames(60 * 4)
	var environment: Node = get_first_node_in_group("environment_controller")
	var raining: bool = weather.is_raining() and weather._rain_particles != null and environment.weather > 0.1
	player.global_position = Vector3(6.5, 0.8, 11.0)   # back in the cabin
	await _frames(60 * int(weather.INSIDE_ENDS_AFTER + weather.FADE_OUT + 2.0))
	# It rains on (indoors too) until the Day 3 wake-up clears it.
	var still: bool = weather.is_raining()
	var bed_clears := "weather.clear_now()" in FileAccess.get_file_as_string("res://scripts/bed_interactable.gd")
	weather.clear_now()
	_check("#5 storm: documenting Nest Gamma brings rain, a darker sky and fog; it lasts until the Day 3 wake-up",
		started and raining and still and bed_clears and not weather.is_raining() and environment.weather == 0.0,
		"started=%s, raining=%s, still inside=%s, bed clears=%s" % [started, raining, still, bed_clears])


func _window(name: String) -> Node:
	return _scene.get_node("Windows/BottomFloorWindows/" + name)


func _test_night_checkpoint() -> void:
	var nm: Node = root.get_node("NightManager")
	var checkpoint: Node = root.get_node("Checkpoint")
	var inventory := _inventory()
	nm._checkpoint_saved = false
	nm.current_night = 3
	nm.start_night(3)
	await _frames(10)
	var items_before: int = inventory.items.size()
	var fuel_before: float = nm.generator_fuel
	var heap: Node = get_first_node_in_group("scrap_heap")
	var heap_before: int = heap.contents.size()
	var pickups_before: int = checkpoint._pickup_nodes(_scene).size()

	# The night goes badly.
	var boarded: Node = _window("LivingRoomWindow")
	var broken: Node = _window("HallWindowRight")
	boarded.is_boarded = true
	boarded.planks_remaining = 2
	broken._shatter_glass()
	heap.contents.clear()
	inventory.add_item(_item("res://resources/plank_resource.tres"))
	nm.generator_fuel = 3.0
	var gone: Node = checkpoint._pickup_nodes(_scene)[0]
	gone.queue_free()
	await _frames(5)

	nm.restart_from_checkpoint()
	await _frames(10)
	var glass_back: bool = broken.get_node_or_null("PristineVisuals/GlassPane") != null and not broken.is_glass_shattered
	_check("#2/#6 night restart: windows, scrap heap, inventory, fuel and world items as at night start",
		not boarded.is_boarded and glass_back and heap.contents.size() == heap_before
		and inventory.items.size() == items_before and is_equal_approx(nm.generator_fuel, fuel_before)
		and checkpoint._pickup_nodes(_scene).size() == pickups_before and nm.is_night_active,
		"boarded=%s glass back=%s heap %d/%d items %d/%d fuel %.0f/%.0f pickups %d/%d night=%s" % [
			boarded.is_boarded, glass_back, heap.contents.size(), heap_before, inventory.items.size(), items_before,
			nm.generator_fuel, fuel_before, checkpoint._pickup_nodes(_scene).size(), pickups_before, nm.is_night_active])


func _test_day_checkpoint() -> void:
	var nm: Node = root.get_node("NightManager")
	var checkpoint: Node = root.get_node("Checkpoint")
	var inventory := _inventory()
	nm.is_night_active = false
	nm.is_day_active = true
	checkpoint.capture("day")
	var items_before: int = inventory.items.size()
	var heap: Node = get_first_node_in_group("scrap_heap")
	var heap_before: int = heap.contents.size()
	inventory.clear()
	heap.contents.clear()
	nm.restart_from_checkpoint()
	await _frames(10)
	var baseline_kit := false
	for item in inventory.items:
		if item and item.item_name == "Fuse":
			baseline_kit = true
	_check("#2/#6 day restart: back to how the day began (not a fixed item kit)",
		inventory.items.size() == items_before and heap.contents.size() == heap_before and not nm.is_night_active,
		"items %d/%d heap %d/%d" % [inventory.items.size(), items_before, heap.contents.size(), heap_before])
