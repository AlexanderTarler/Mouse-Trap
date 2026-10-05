extends Area3D
class_name HintArea

## HintArea — Reusable onboarding trigger.
##
## When the player enters this Area3D, it finds the HorrorHUD and displays
## a short hint that fades in after a small delay. The trigger only fires
## once and can be restricted to Day 1.

## The hint text to display on the HUD.
@export var hint_text: String = ""

## Delay in seconds before the hint fades in.
@export var fade_in_delay: float = 0.5

## If true, the hint only appears on Day 1 (current_night == 0).
@export var day_one_only: bool = true

## If true, the trigger is disabled after firing once.
@export var one_shot: bool = true

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered and one_shot:
		return
	
	# Only react to the player. The player scene is expected to be in the
	# "player" group or to have a PlayerController script.
	if not body.is_in_group("player") and not body.is_class("CharacterBody3D"):
		return
	
	if day_one_only:
		var nm = get_node_or_null("/root/NightManager")
		if nm and "current_night" in nm and nm.current_night != 0:
			return
	
	# ─── TUTORIAL MANAGER GATE ─────────────────────────────────────
	# If this hint text matches a known tutorial mechanic_id, route through
	# the TutorialManager instead of directly showing the hint. This ensures
	# prerequisite chains (e.g. notebook must wait for movement) are respected.
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("trigger"):
		# Walk through loaded tutorials to see if this hint_text matches one
		for tutorial in tm.tutorials:
			if tutorial and tutorial is TutorialData and tutorial.prompt_text == hint_text:
				tm.trigger(tutorial.mechanic_id)
				_triggered = true
				print("[HintArea] Routed through TutorialManager: '%s' (id='%s')" % [hint_text, tutorial.mechanic_id])
				return
	
	# Fallback: direct hint display (no matching tutorial found)
	var hud = _find_hud()
	if hud and hud.has_method("show_hint"):
		hud.show_hint(hint_text, fade_in_delay)
		_triggered = true
		print("[HintArea] Triggered hint (direct): '%s'" % hint_text)
	else:
		push_warning("[HintArea] Could not find HorrorHUD with show_hint() method.")


func _find_hud() -> Node:
	# Prefer the group "hud" so designers don't have to worry about paths.
	for node in get_tree().get_nodes_in_group("hud"):
		if node.has_method("show_hint"):
			return node
	return null
