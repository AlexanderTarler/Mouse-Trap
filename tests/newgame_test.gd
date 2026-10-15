extends SceneTree
## planning/mvp_plan.txt 1: a new game from the main menu (after quitting
## to it mid-game) starts exactly like the first one: Day 1, the starting
## inventory, the story from the beginning, the clock, no old thoughts or
## checkpoint, and the Day 1 setup run again (GameReset).
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/newgame_test.gd

const GAME := "res://scenes/cottage_horror.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[NEWGAME TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _first_game() -> Dictionary:
	var nm: Node = root.get_node("NightManager")
	var rm: Node = root.get_node("RoutineManager")
	var gt: Node = root.get_node("GameTime")
	var player: Node3D = get_first_node_in_group("player")
	return {
		"night": nm.current_night,
		"items": root.get_node("Inventory").get_item_count(),
		"objective": rm.main_objective,
		"time": snappedf(gt.cycle_progress, 0.01),
		"fuel": nm.generator_fuel,
		"day1_entered": rm.phase1_entered_cabin,
		"position": player.global_position.snapped(Vector3.ONE * 0.5) if player else Vector3.INF,
		"checkpoint": root.get_node("Checkpoint").kind,
	}


func _run() -> void:
	# The first game, as the main menu would start it.
	change_scene_to_file(MENU)
	await _frames(10)
	current_scene._on_play_pressed()
	await _frames(120)
	var first := _first_game()
	print("[NEWGAME TEST] first game: ", first)

	# Play a while: Night 3, a full pack, the story on, a thought, a storm,
	# a checkpoint, the clock on.
	var nm: Node = root.get_node("NightManager")
	var rm: Node = root.get_node("RoutineManager")
	var gt: Node = root.get_node("GameTime")
	var inventory: Node = root.get_node("Inventory")
	var monologue: Node = root.get_node("Monologue")
	nm.current_night = 3
	nm.generator_fuel = 77.0
	for i in 3:
		inventory.add_item(load("res://resources/plank_resource.tres"))
	rm.main_objective = 99
	rm.phase1_entered_cabin = true
	monologue.think("An old game's thought.", null, 1.0, "old_game")
	root.get_node("Weather").start_storm(0.0, true)
	root.get_node("Checkpoint").capture("night")
	gt.cycle_progress = 0.8
	await _frames(10)

	# Quit to the menu (the pause menu's Main Menu), and Play again.
	change_scene_to_file(MENU)
	await _frames(10)
	var menu := current_scene
	menu._on_play_pressed()
	await _frames(120)
	var second := _first_game()
	print("[NEWGAME TEST] second game: ", second)

	_check("the second game is Day 1 again (night %d)" % second.night, second.night == first.night)
	_check("the starting inventory (%d items, the first game had %d)" % [second.items, first.items], second.items == first.items)
	_check("the story from the beginning (objective %d, cabin not yet entered)" % second.objective,
		second.objective == first.objective and second.day1_entered == first.day1_entered)
	_check("the clock and the generator as at the start (time %.2f, fuel %.0f)" % [second.time, second.fuel],
		is_equal_approx(second.time, first.time) and is_equal_approx(second.fuel, first.fuel))
	_check("the Day 1 setup ran again (the player at the start, %s)" % second.position, second.position == first.position)
	_check("no old thoughts, no storm, a fresh checkpoint (%s)" % second.checkpoint,
		not monologue.has_thought("old_game") and not root.get_node("Weather").is_raining() and second.checkpoint == first.checkpoint)
	_check("GameReset counted both games", root.get_node("GameReset").games_started == 2)

	print("[NEWGAME TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	current_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)
