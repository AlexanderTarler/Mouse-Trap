extends SceneTree
## Times pressing Play on the main menu until the game is set up, after
## sitting on the menu for a while (the game loads in the background), and
## the longest frame on the menu meanwhile.
## Run: godot --path . --script res://tools/menu_start_timing.gd -- <seconds on the menu>


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var wait := float(args[0]) if args.size() > 0 else 6.0
	# (Never the player's own save.)
	SaveGame.path = "user://timing_test_save.dat"
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await process_frame
	await process_frame
	var calibration := current_scene.get_node_or_null("Calibration")
	if calibration:
		calibration.queue_free()
	var start := Time.get_ticks_msec()
	var last := start
	var longest := 0
	while Time.get_ticks_msec() - start < wait * 1000.0:
		await process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
	var status := ResourceLoader.load_threaded_get_status("res://scenes/cottage_horror.tscn")
	var t0 := Time.get_ticks_msec()
	current_scene._new_game_armed = 3.0   # (as if pressed twice over a save)
	current_scene._on_play_pressed()
	var nm := root.get_node("NightManager")
	var shown := -1
	while not nm._spawn_setup_done:
		await process_frame
		var secs := int(Time.get_ticks_msec() - t0) / 1000
		if secs != shown:
			shown = secs
			print("[START TIMING] %d s: scene %s, level %d" % [secs, current_scene.name if current_scene else "none", ResourceLoader.load_threaded_get_status("res://scenes/cottage_horror.tscn")])
		if secs > 40:
			break
	var to_game := Time.get_ticks_msec() - t0
	# The opening going on over the level: how smooth, and until it's done.
	var worst := 0
	var before := Time.get_ticks_msec()
	while get_first_node_in_group("opening") and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		var now := Time.get_ticks_msec()
		worst = maxi(worst, now - before)
		before = now
	print("[START TIMING] level up %d ms after Play; the opening over it until %d ms, its longest frame after the level was up %d ms" % [to_game, Time.get_ticks_msec() - t0, worst])
	print("[START TIMING] after %.1f s on the menu (longest menu frame %d ms, level %s): Play to game set up %d ms" % [wait, longest, ["invalid", "loading", "failed", "loaded"][status], Time.get_ticks_msec() - t0])
	SaveGame.delete()
	quit()
