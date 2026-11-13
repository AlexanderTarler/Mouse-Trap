extends SceneTree
## The second bugs.txt round:
##   1. The TAB hint goes when the inventory opens, or for the next hint.
##   2. Day/night sky: the time glides, stars and the moon come out.
##   3. Slot labels are distinct ("Fu" was both Fuse and Fuel Can).
##   4. Inner monologue: a thought floats up when the first plank is taken.
##   5. The bed glows while the objective is to go to bed.
##   6. The computer looks like Windows 95.
##   7. A documented nest's prompt says "Nest Alpha", not "Nest Nest Alpha".
##   8. Rain falls (outside) while the player is inside; no storm fog.
##   9. The door-lock Peeker is at the hall window.
##  10. The car alarm light is brighter and has a beacon.
##  11. Dying in Night 2.2 restarts at the van, the alarm going.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/bugs2_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[BUGS2 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


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

	await _test_tab_hint()
	await _test_sky()
	_test_short_labels()
	await _test_monologue()
	_test_bed_highlight()
	_test_win95()
	_test_nest_prompt()
	await _test_rain_indoors()
	await _test_peeker_window()
	await _test_van_alarm()

	print("[BUGS2 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	paused = false
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_tab_hint() -> void:
	var tm: Node = root.get_node("TutorialManager")
	var rm: Node = root.get_node("RoutineManager")
	var hud: Node = get_first_node_in_group("hud")
	for id in ["inventory", "notebook"]:
		rm._learned_mechanics.erase(id)
		tm._shown.erase(id)
	rm._learned_mechanics["movement"] = true
	tm.trigger("inventory", true)
	await _frames(2)
	var shown_first: String = tm.visible_hint()
	tm.trigger("notebook")
	await _frames(2)
	_check("#1 the TAB hint gives way to the next tutorial hint",
		shown_first == "inventory" and tm.visible_hint() == "notebook",
		"%s -> %s" % [shown_first, tm.visible_hint()])
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint()
	tm._visible_id = ""
	tm._shown.erase("inventory")
	tm.trigger("inventory", true)
	await _frames(2)
	var before: String = tm.visible_hint()
	var inventory_ui: Node = _scene.find_child("InventoryUI", true, false)
	inventory_ui._open_inventory()
	await _frames(2)
	_check("#1 the TAB hint goes once the inventory opens",
		before == "inventory" and tm.visible_hint() == "", "%s -> '%s'" % [before, tm.visible_hint()])
	if inventory_ui.has_method("_close_inventory"):
		inventory_ui._close_inventory()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint()
	tm._visible_id = ""


func _test_sky() -> void:
	var ec: Node = get_first_node_in_group("environment_controller")
	var sky := ec._sky_material as ShaderMaterial
	_check("#2 the sky is the day/night sky shader", sky != null and sky.shader == ec.SKY_SHADER)
	ec._on_game_time_changed(0.25, true)
	var day_night: float = sky.get_shader_parameter("night")
	ec._on_game_time_changed(0.75, true)
	await _frames(2)
	var night: float = sky.get_shader_parameter("night")
	var moon: Vector3 = sky.get_shader_parameter("moon_direction")
	_check("#2 stars and the moon at night (night %.2f by day, %.2f at night; moon up %.2f)" % [day_night, night, moon.y],
		day_night < 0.2 and night > 0.8 and moon.y > 0.0)
	# A step forward in time glides instead of jumping.
	ec._on_game_time_changed(0.5, true)
	var dusk: float = sky.get_shader_parameter("dusk")
	ec._on_game_time_changed(0.47, true)
	ec._on_game_time_changed(0.53)
	await _frames(3)
	var gliding: float = ec.cycle_progress
	_check("#2 dusk: time glides into the night (%.3f between 0.47 and 0.53)" % gliding,
		gliding > 0.47 and gliding < 0.53)
	_check("#2 dusk glow around sunset (%.2f)" % dusk, dusk > 0.5)
	var gt: Node = root.get_node("GameTime")
	ec._on_game_time_changed(gt.cycle_progress, true)


func _test_short_labels() -> void:
	var labels := {}
	for name in ["Fuse", "Fuel Can", "Battery", "Car Battery", "Wooden Plank", "Cable Spool", "Cabin Key", "Portable Light", "Radiator", "Ignition Wiring"]:
		var item: Resource = load("res://scripts/items/item_data.gd").new()
		item.item_name = name
		labels[name] = item.short_label()
	var unique := {}
	for label in labels.values():
		unique[label] = true
	_check("#3 slot labels are distinct (Fuse %s, Fuel Can %s)" % [labels["Fuse"], labels["Fuel Can"]],
		unique.size() == labels.size())


func _test_monologue() -> void:
	var monologue: Node = root.get_node("Monologue")
	_check("#4 the player's starting plank did not set off the thought", not monologue.has_thought("broken_window"))
	var rm: Node = root.get_node("RoutineManager")
	rm._think_about_broken_window()
	await _frames(2)
	var thought: Node = monologue._thought
	var text := ""
	if thought is Label3D:
		text = (thought as Label3D).text
	elif thought:
		text = (thought.get_child(0) as Label).text
	_check("#4 the first plank: a thought, styled apart from hints",
		monologue.has_thought("broken_window") and "patch up" in text, text)
	monologue._clear()


func _test_bed_highlight() -> void:
	var rm: Node = root.get_node("RoutineManager")
	var beds := get_nodes_in_group("xray_bed")
	rm._update_bed_highlight("Go to bed.")
	var on: bool = rm._bed_highlighted
	rm._update_bed_highlight("Find the fuse.")
	_check("#5 the bed glows during 'Go to bed' only", beds.size() > 0 and on and not rm._bed_highlighted,
		"%d bed node(s)" % beds.size())


func _test_win95() -> void:
	var pc: Node = _scene.find_child("ComputerUI", true, false)
	var background := pc.get_node("DesktopBackground") as ColorRect
	var taskbar := pc.get_node_or_null("Taskbar")
	var icon := pc.get_node("DesktopView/FieldLogIcon") as Button
	_check("#6 the computer: teal desktop, taskbar with Start, icons with pictures",
		background.color.is_equal_approx(Color8(0, 128, 128)) and taskbar != null
		and taskbar.get_node_or_null("StartButton") != null and icon.icon != null
		and (pc.get_node("LoginScreen") as Control).theme != null)


func _test_nest_prompt() -> void:
	var nest: Node = get_first_node_in_group("hasselmus_nests")
	var was: bool = nest.is_documented
	nest.is_documented = true
	var prompt: String = nest.get_interact_text()
	nest.is_documented = was
	_check("#7 a documented nest's prompt names it once", not "Nest Nest" in prompt and nest.nest_label in prompt, prompt)


func _test_rain_indoors() -> void:
	var ec: Node = get_first_node_in_group("environment_controller")
	var env: Environment = ec.world_environment.environment
	var fog_clear := [env.fog_density, env.volumetric_fog_density]
	var weather: Node = root.get_node("Weather")
	var player := get_first_node_in_group("player") as Node3D
	var spawn: Marker3D = _scene.get_node("PlayerSpawnpoints/PlayerSpawnDev")
	player.global_position = spawn.global_position
	await _frames(5)
	weather.start_storm()
	weather.level = 1.0
	await _frames(60)
	var rain := weather._rain_particles as GPUParticles3D
	var room: String = player.get_player_room() if player.has_method("get_player_room") else "?"
	_check("#8 it rains (seen through the windows) while the player is inside",
		rain != null and rain.emitting and room != "Outside", "room %s" % room)
	var fog_storm := [env.fog_density, env.volumetric_fog_density]
	_check("#8 the storm adds no fog", is_equal_approx(fog_clear[0], fog_storm[0]) and is_equal_approx(fog_clear[1], fog_storm[1]),
		"%s -> %s" % [fog_clear, fog_storm])
	weather.clear_now()


func _test_peeker_window() -> void:
	var rm: Node = root.get_node("RoutineManager")
	var pm: Node = root.get_node("PeekerManager")
	var objective: int = rm.main_objective
	var player := get_first_node_in_group("player") as Node3D
	var was_at := player.global_position
	# Locked downstairs: the bedroom is upstairs, so it waits for them there
	# (never up there while they're down: its legs showed through the floor).
	player.global_position = Vector3(6.0, 0.75, 17.4)
	pm._last_peeker_window_id = ""
	rm.main_objective = 8
	rm.on_door_locked()
	await _frames(2)
	var waited: bool = pm._active_peeker == null and pm._pending_window_id == "Bedroom_Right"
	player.global_position = Vector3(6.0, 3.73, 17.4)
	await _frames(2)
	_check("#9 the Day 1 door-lock Peeker shows at the bedroom window once the player is upstairs",
		waited and pm._last_peeker_window_id == "Bedroom_Right" and pm._active_peeker != null,
		"waited %s, at %s" % [waited, pm._last_peeker_window_id])
	player.global_position = was_at
	if pm.has_method("remove_active_peeker"):
		pm.remove_active_peeker()
	rm.main_objective = objective


func _test_van_alarm() -> void:
	var nm: Node = root.get_node("NightManager")
	var van: Node = _scene.find_child("EscapeVan", true, false)
	var player := get_first_node_in_group("player") as Node3D
	# As after going to bed on Day 2: the van sequence, the night not yet
	# started (it starts when the van is investigated).
	nm.current_night = 2
	nm.is_night_active = false
	nm._checkpoint_saved = false
	nm.is_van_sequence_active = true
	nm.horror_event.emit("car_alarm")
	await _frames(5)
	var light: OmniLight3D = van._alarm_light
	_check("#10 the alarm light reaches the cabin, with a beacon (range %.0f m)" % light.omni_range,
		van.alarm_active and light.omni_range >= 80.0 and van._beacon != null and van._beacon.visible)
	var checkpoint: Node = root.get_node("Checkpoint")
	_check("#11 the alarm going off is a checkpoint", checkpoint.tag == "van_alarm", checkpoint.tag)
	# Investigate (the chase starts), then die.
	van.interact()
	await _frames(10)
	player.global_position = Vector3(0, 1, 0)
	nm.restart_from_checkpoint()
	await _frames(10)
	var distance := player.global_position.distance_to((van as Node3D).global_position)
	_check("#11 dying in Night 2.2: back at the van, the alarm going, not yet investigated (%.1f m away)" % distance,
		van.alarm_active and not van.van_investigated and distance < 10.0)
