extends SceneTree
## Good-ending playtest fixes:
##   - the van's escape froze until Esc: the cinematic switches the player
##     off (process_mode) and hides the mouse, and the pause menu took that
##     for the mouse let go in play and paused the game, its menu under the
##     cinematic's black. Now: no pause with the player switched off, or
##     with the mouse hidden by the game; still a pause when the mouse is
##     let go in play (alt-tab, the browser)
##   - pressing E at the willow froze the game (its effects' shaders): the
##     totem makes its effects once ahead (warm_effects, for ShaderWarmup)
##     and keeps their materials, so their shaders stay compiled
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/playtest13_test.gd

const LEVEL := "res://scenes/cottage_horror.tscn"

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("[PLAYTEST13 TEST] %s  %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	await process_frame
	root.get_node("GameReset").new_game()
	change_scene_to_file(LEVEL)
	await _frames(200)
	for o in get_nodes_in_group("opening"):
		o.queue_free()
	await _frames(5)
	var pause_menu: Node = current_scene.get_node("PauseMenu")
	var player := get_first_node_in_group("player") as Node

	# ─── The escape cinematic: player off, mouse hidden ────────────────
	pause_menu._was_captured = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	await _frames(10)
	_check("a cinematic (player switched off, mouse hidden by the game): no pause (paused %s, menu open %s)" % [paused, pause_menu._is_open],
		not paused and not pause_menu._is_open)
	# The mouse let go (not hidden) while the player is switched off: no pause either.
	pause_menu._was_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(10)
	_check("the mouse let go while the player is switched off: no pause", not paused and not pause_menu._is_open)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	# In play, the mouse let go: the pause still comes (alt-tab, the browser).
	pause_menu._was_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(10)
	_check("in play, the mouse let go: the pause menu (paused %s, open %s)" % [paused, pause_menu._is_open], paused and pause_menu._is_open)
	pause_menu._resume()
	await _frames(3)

	# ─── The willow's effects, made ahead ──────────────────────────────
	var totem := get_first_node_in_group("totem_anchor")
	var made: Array[Node] = totem.warm_effects()
	var particles := 0
	var copies := 0
	for node in made:
		if node is GPUParticles3D:
			particles += 1
		elif node is MeshInstance3D:
			copies += 1
	var kept: int = totem._warm_kept.size()
	for node in made:
		node.queue_free()
	await _frames(3)
	var all_kept: bool = totem._warm_kept.size() == kept and totem._warm_kept.all(func(m): return is_instance_valid(m))
	_check("warm_effects: the embers and ash (%d) and the charred willow (%d copies), their materials kept after (%d)" % [particles, copies, kept],
		particles == 2 and copies > 0 and kept >= 4 and all_kept)
	_check("the warm-up runs on every renderer but headless", not ShaderWarmup.needed())

	print("[PLAYTEST13 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
