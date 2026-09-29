extends Node

## TutorialManager — Persistent autoload that manages Just-in-Time tutorial prompts.
##
## Holds an array of TutorialData resources configured in the Inspector.
## Evaluates trigger conditions and prerequisites, then dispatches prompts
## to the HorrorHUD. Tracks which mechanics the player has learned so
## tutorials are never shown twice.
##
## Integration points:
##   - HorrorHUD.show_hint(text) — displays the prompt
##   - HorrorHUD.hide_hint() — dismisses the prompt
##   - RoutineManager.mark_mechanic_learned(id) — persists learning status
##   - RoutineManager.is_mechanic_learned(id) — checks prerequisite completion
##   - player_controller.gd emits signals for trigger moments
##   - NightManager emits night_started for flashlight tutorial

## Paths to TutorialData .tres files. Loaded programmatically since autoloads
## cannot rely on Inspector-based @export assignments.
const TUTORIAL_PATHS: Array[String] = [
	"res://resources/tutorial/tutorial_movement.tres",
	"res://resources/tutorial/tutorial_interact.tres",
	"res://resources/tutorial/tutorial_notebook.tres",
	"res://resources/tutorial/tutorial_sprint.tres",
	"res://resources/tutorial/tutorial_flashlight.tres",
	"res://resources/tutorial/tutorial_inventory.tres",
	"res://resources/tutorial/tutorial_pc_login.tres",
	"res://resources/tutorial/tutorial_pickup_drop.tres",
	"res://resources/tutorial/tutorial_low_battery.tres",
	# ─── DAY 2 NEST TUTORIALS ────────────────────────────────────────
	# These teach the survival mechanics required to document the nests:
	#   overcharge → Nest Alpha, stealth → Nest Beta, stillness → Nest Gamma.
	"res://resources/tutorial/tutorial_overcharge.tres",
	"res://resources/tutorial/tutorial_stealth.tres",
	"res://resources/tutorial/tutorial_stillness.tres",
]

## Loaded TutorialData resources.
var tutorials: Array[TutorialData] = []

## Optional fade-in delay for tutorial prompts (seconds).
var fade_in_delay: float = 0.5

## How long a prompt stays visible before auto-dismiss (seconds). 0 = no auto-dismiss.
var auto_dismiss_after: float = 0.0

## Cached reference to the HorrorHUD.
var _hud: Node = null

## Tracks which mechanics have been shown (one_shot guard).
var _shown: Dictionary = {}



func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	
	# Load all tutorial resources from disk
	for path in TUTORIAL_PATHS:
		var res := load(path) as TutorialData
		if res:
			tutorials.append(res)
			print("[TutorialManager] Loaded tutorial: %s" % res.mechanic_id)
		else:
			push_warning("[TutorialManager] Could not load tutorial resource: %s" % path)
	
	# Wire up signal listeners for trigger moments.
	# Assumes the autoloads exist; if not, we connect lazily.
	var nm := get_node_or_null("/root/NightManager")
	if nm and nm.has_signal("night_started"):
		if not nm.is_connected("night_started", _on_night_started):
			nm.night_started.connect(_on_night_started)


func _find_hud() -> Node:
	if _hud and is_instance_valid(_hud):
		return _hud
	
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	for node in hud_nodes:
		if node.has_method("show_hint"):
			_hud = node
			return _hud
	
	var hud := get_node_or_null("/root/CottageHorror/HUD")
	if hud:
		_hud = hud
		return _hud
	return null


## Helper: formatted timestamp in seconds for debug logging.
func _timestamp() -> String:
	var ms := Time.get_ticks_msec()
	var sec := ms / 1000
	var frac := ms % 1000
	return "%d.%03d" % [sec, frac]


## Trigger a tutorial by its mechanic_id. Called by external scripts (player_controller,
## inventory, NightManager) when a trigger moment occurs.
func trigger(mechanic_id: String) -> void:
	var tutorial := _find_tutorial(mechanic_id)
	if not tutorial:
		push_warning("[TutorialManager] T+%s TRIGGER '%s' — NOT FOUND in loaded tutorials" % [_timestamp(), mechanic_id])
		return
	print("[TutorialManager] T+%s TRIGGER '%s' — prompt='%s'" % [_timestamp(), mechanic_id, tutorial.prompt_text])
	_show(tutorial)


## Mark a mechanic as learned (player performed the action).
## Dispatches to RoutineManager for persistence and dismisses the hint.
func mark_learned(mechanic_id: String) -> void:
	print("[TutorialManager] T+%s MARK_LEARNED '%s' — hiding hint" % [_timestamp(), mechanic_id])
	
	# ─── UNCONDITIONALLY HIDE THE HINT ─────────────────────────────────
	# The player has performed the action (e.g., opened the notebook).
	# Regardless of whether _shown tracks this tutorial as currently visible,
	# we must dismiss the hint. This handles the race condition where the
	# player opens the notebook before the tutorial trigger fires, causing
	# _shown["notebook"] to be false when hide_hint would be needed.
	var hud := _find_hud()
	if hud and hud.has_method("hide_hint"):
		hud.hide_hint()
	
	# Clear from shown tracking so future triggers respect one_shot
	_shown.erase(mechanic_id)
	
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("mark_mechanic_learned"):
		rm.mark_mechanic_learned(mechanic_id)
	
	print("[TutorialManager] T+%s MARK_LEARNED '%s' — done" % [_timestamp(), mechanic_id])


## Checks if a mechanic has been learned (via RoutineManager persistence).
func is_learned(mechanic_id: String) -> bool:
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("is_mechanic_learned"):
		return rm.is_mechanic_learned(mechanic_id)
	return true  # If RoutineManager not found, assume learned to avoid stuck prompts


# ─── Internal ──────────────────────────────────────────────────────────

func _find_tutorial(id: String) -> TutorialData:
	for t in tutorials:
		if t and t.mechanic_id == id:
			return t
	return null


func _can_show(tutorial: TutorialData) -> bool:
	# Already shown and one_shot?
	if tutorial.one_shot and _shown.get(tutorial.mechanic_id, false):
		return false
	
	# Already learned?
	if is_learned(tutorial.mechanic_id):
		return false
	
	# Day-one-only restriction?
	if tutorial.day_one_only:
		var nm := get_node_or_null("/root/NightManager")
		if nm and "current_night" in nm and nm.current_night != 0:
			return false
	
	# Prerequisite not yet learned?
	if tutorial.prerequisite and not is_learned(tutorial.prerequisite):
		return false
	
	return true


func _show(tutorial: TutorialData) -> void:
	if not _can_show(tutorial):
		return
	
	var hud := _find_hud()
	if not hud or not hud.has_method("show_hint"):
		push_warning("[TutorialManager] Cannot show hint — no HUD with show_hint() found.")
		return
	
	hud.show_hint(tutorial.prompt_text, fade_in_delay)
	_shown[tutorial.mechanic_id] = true
	
	print("[TutorialManager] Showing prompt: '%s' (%s)" % [tutorial.prompt_text, tutorial.mechanic_id])
	
	# Auto-dismiss if configured
	if auto_dismiss_after > 0.0 and hud.has_method("hide_hint"):
		get_tree().create_timer(auto_dismiss_after).timeout.connect(func():
			if hud and hud.has_method("hide_hint"):
				hud.hide_hint()
		)


# ─── Signal Handlers ────────────────────────────────────────────────────

func _on_night_started(_night: int) -> void:
	# The flashlight hint must only appear when Night 1 starts AND the player
	# already has the flashlight. If they don't have it yet, the hint will fire
	# the first time those two conditions coincide (pickup during Night 1).
	try_trigger_flashlight()


## Triggers the flashlight tutorial hint if (and only if) it is Night 1 and the
## player has already acquired the flashlight. Called on night start and again
## when the flashlight pickup is collected. The one_shot guard in _show()
## ensures it is only ever displayed once.
func try_trigger_flashlight() -> void:
	var nm := get_node_or_null("/root/NightManager")
	if not nm or "current_night" not in nm or nm.current_night != 1:
		return
	
	var player: Node = get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("has_flashlight") or not player.has_flashlight():
		return
	
	trigger("flashlight")
