extends SceneTree
## Times starting the game: loading the level, instancing it, its first
## frames (its _ready()s), until the player is set up.
## Run: godot [--headless] --path . --script res://tools/load_timing.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	var packed := load("res://scenes/cottage_horror.tscn") as PackedScene
	var t1 := Time.get_ticks_msec()
	var scene := packed.instantiate()
	var t2 := Time.get_ticks_msec()
	root.add_child(scene)
	current_scene = scene
	var t3 := Time.get_ticks_msec()
	var frames := 0
	var longest := 0
	var last := Time.get_ticks_msec()
	var nm := root.get_node("NightManager")
	while not nm._spawn_setup_done and frames < 2000:
		await process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
		frames += 1
	var t4 := Time.get_ticks_msec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
	var t5 := Time.get_ticks_msec()
	print("[LOAD TIMING] load %d ms, instantiate %d ms, add_child (_ready) %d ms, to spawn setup %d ms (%d frames, longest %d ms), next 120 frames %d ms" % [t1 - t0, t2 - t1, t3 - t2, t4 - t3, frames, longest, t5 - t4])
	quit()
