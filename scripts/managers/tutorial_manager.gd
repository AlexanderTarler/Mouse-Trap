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
	# Day 1: the key under the bucket by the door.
	"res://resources/tutorial/tutorial_move_objects.tres",
	"res://resources/tutorial/tutorial_low_battery.tres",
	# The first night: the watch (Wristwatch).
	"res://resources/tutorial/tutorial_watch.tres",
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
## Hints that give way when another tutorial is triggered.
const REPLACEABLE_HINTS := ["inventory"]
## Doing one thing also does what another hint asks: opening the notebook
## is what the PC login hint asks for.
const ALSO_DISMISSES := {"notebook": ["pc_login_hint"]}
## The mechanic whose hint is currently on screen ("" for none).
var _visible_id := ""
## A hint stays up at least this long (s, counting its fade-in).
var min_hint_time := 2.0
## mechanic -> when its hint was shown (_clock, s).
var _shown_at := {}
## Game time (s), for how long a hint has been up.
var _clock := 0.0

## Cached reference to the HorrorHUD.
var _hud: Node = null

## Tracks which mechanics have been shown (one_shot guard).
var _shown: Dictionary = {}



func _process(delta: float) -> void:
	_clock += delta


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
	return null


## Helper: formatted timestamp in seconds for debug logging.
func _timestamp() -> String:
	var ms := Time.get_ticks_msec()
	var sec := ms / 1000
	var frac := ms % 1000
	return "%d.%03d" % [sec, frac]


## Trigger a tutorial by its mechanic_id. Called by external scripts (player_controller,
## inventory, NightManager) when a trigger moment occurs.
## With `force` the hint replaces whatever hint is on screen and skips its
## prerequisite (a hint the story needs right now, like sprinting from the
## Entity); it still respects one_shot and being learned.
func trigger(mechanic_id: String, force: bool = false) -> void:
	var tutorial := _find_tutorial(mechanic_id)
	if not tutorial:
		push_warning("[TutorialManager] T+%s TRIGGER '%s' — NOT FOUND in loaded tutorials" % [_timestamp(), mechanic_id])
		return
	print("[TutorialManager] T+%s TRIGGER '%s' — prompt='%s'" % [_timestamp(), mechanic_id, tutorial.prompt_text])
	_show(tutorial, force)


## The mechanic whose hint is on screen ("" for none).
func visible_hint() -> String:
	return _visible_id


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
	# Only its own hint (matched by what is on screen): learning the
	# flashlight must not wipe the sprint hint off the screen mid-chase.
	_dismiss(mechanic_id)
	for other in ALSO_DISMISSES.get(mechanic_id, []):
		if _visible_id == other or _is_on_screen(other):
			_dismiss(other)
			var routine := get_node_or_null("/root/RoutineManager")
			if routine and routine.has_method("mark_mechanic_learned"):
				routine.mark_mechanic_learned(other)
	
	# Clear from shown tracking so future triggers respect one_shot
	_shown.erase(mechanic_id)
	
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("mark_mechanic_learned"):
		rm.mark_mechanic_learned(mechanic_id)
	
	print("[TutorialManager] T+%s MARK_LEARNED '%s' — done" % [_timestamp(), mechanic_id])


## Whether this mechanic's hint has been shown (and not yet learned).
func was_shown(mechanic_id: String) -> bool:
	return _shown.get(mechanic_id, false) or _visible_id == mechanic_id


## Hides this mechanic's hint if it is the one on screen (another hint,
## say the sprint hint mid-chase, stays).
func _dismiss(mechanic_id: String) -> void:
	var hud := _find_hud()
	if not hud or not hud.has_method("hide_hint"):
		return
	if _visible_id == mechanic_id or _is_on_screen(mechanic_id):
		# Done already (say, crouching as the crouch hint comes up): it
		# still stays long enough to be read.
		var shown_for: float = _clock - float(_shown_at.get(mechanic_id, -INF))
		if shown_for < min_hint_time:
			var text: String = hud.current_hint() if hud.has_method("current_hint") else ""
			get_tree().create_timer(min_hint_time - shown_for).timeout.connect(_late_dismiss.bind(text))
			return
		hud.hide_hint()
		_visible_id = ""


## Hides a hint after its minimum time, if it's still the one up.
func _late_dismiss(text: String) -> void:
	var hud := _find_hud()
	if hud and hud.has_method("current_hint") and text != "" and hud.current_hint() == text:
		hud.hide_hint()
		if _visible_id != "" and _find_tutorial(_visible_id) and _find_tutorial(_visible_id).prompt_text == text:
			_visible_id = ""


## Whether the HUD is showing this mechanic's prompt right now (however it
## got there).
func _is_on_screen(mechanic_id: String) -> bool:
	var hud := _find_hud()
	var tutorial := _find_tutorial(mechanic_id)
	if not hud or not tutorial or not hud.has_method("current_hint"):
		return false
	return hud.current_hint() == GameKeys.keys_in(tutorial.prompt_text)


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


func _can_show(tutorial: TutorialData, force: bool = false) -> bool:
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
	if tutorial.prerequisite and not is_learned(tutorial.prerequisite) and not force:
		return false
	
	return true


func _show(tutorial: TutorialData, force: bool = false) -> void:
	if not _can_show(tutorial, force):
		return
	# A passing hint gives way to the next one instead of blocking it.
	if _visible_id in REPLACEABLE_HINTS:
		force = true
	
	var hud := _find_hud()
	if not hud or not hud.has_method("show_hint"):
		push_warning("[TutorialManager] Cannot show hint — no HUD with show_hint() found.")
		return
	
	# Only counts as shown if it actually made it onto the screen (a hint
	# blocked by another one used to be marked shown, so the one_shot rule
	# then refused it for good).
	var on_screen = hud.show_hint(tutorial.prompt_text, fade_in_delay, force)
	if on_screen == false:
		print("[TutorialManager] '%s' not shown (another hint is up)." % tutorial.mechanic_id)
		return
	_shown[tutorial.mechanic_id] = true
	_visible_id = tutorial.mechanic_id
	_shown_at[tutorial.mechanic_id] = _clock
	
	print("[TutorialManager] Showing prompt: '%s' (%s)" % [tutorial.prompt_text, tutorial.mechanic_id])
	
	# Auto-dismiss if configured
	if auto_dismiss_after > 0.0 and hud.has_method("hide_hint"):
		var shown_id := tutorial.mechanic_id
		get_tree().create_timer(auto_dismiss_after).timeout.connect(func():
			if hud and hud.has_method("hide_hint") and _visible_id == shown_id:
				hud.hide_hint()
				_visible_id = ""
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
