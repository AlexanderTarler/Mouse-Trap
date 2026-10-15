extends SceneTree
## What SiteDresser placed and what it skipped (and why), and how long it
## took.
##   godot --headless --path . --script res://tools/dress_report.gd


func _initialize() -> void:
	_go()


func _go() -> void:
	await process_frame
	var started := Time.get_ticks_msec()
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	root.add_child(s)
	current_scene = s
	var dresser: Node = null
	for i in 600:
		await physics_frame
		dresser = s.find_child("SiteDresser", true, false)
		if dresser and dresser.built:
			break
	if dresser == null or not dresser.built:
		print("[DRESS] not built after 600 frames")
		quit(1)
		return
	print("[DRESS] placed %d, skipped %d (%.1f s since load)" % [dresser.placed, dresser.skipped.size(), (Time.get_ticks_msec() - started) / 1000.0])
	for reason in dresser.skipped:
		print("[SKIP] " + reason)
	quit()
