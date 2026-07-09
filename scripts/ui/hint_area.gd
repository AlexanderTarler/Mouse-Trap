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
	
	var hud = _find_hud()
	if hud and hud.has_method("show_hint"):
		hud.show_hint(hint_text, fade_in_delay)
		_triggered = true
		print("[HintArea] Triggered hint: '%s'" % hint_text)
	else:
		push_warning("[HintArea] Could not find HorrorHUD with show_hint() method.")


func _find_hud() -> Node:
	# Prefer the group "hud" so designers don't have to worry about paths.
	var hud_nodes = get_tree().get_nodes_in_group("hud")
	for node in hud_nodes:
		if node.has_method("show_hint"):
			return node
	
	# Fallback: common paths
	var hud = get_node_or_null("/root/CottageHorror/HorrorHUD")
	if hud:
		return hud
	return get_node_or_null("/root/Main/HorrorHUD")
