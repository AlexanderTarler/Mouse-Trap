extends Node3D

## Simple interaction manager for the horror game.
## Shows a prompt when looking at interactable objects.

@export var interaction_distance: float = 3.0
@export var prompt_text: String = "[E] Interact"

# ─── INTERACTABLE COLLISION LAYER ─────────────────────────────────
# Layer 2 ("Interactable") is dedicated to interactable targets.
# The interaction ray ONLY raycasts against layer 2, so invisible
# environment geometry (porch roof overhang, stairs, cabin bounding
# bodies) on the default layer 1 can never absorb the ray before it
# reaches the door/key/switch collider. Bodies that are interactable
# keep layer 1 as well (so the player and Entity still collide with
# them) and are marked with layer 1|2 = 3 in their own scripts.
const INTERACTABLE_LAYER_MASK: int = 2  # Layer 2 (name: "Interactable")

# Camera reference is set by the player controller when this node is created
var _camera: Camera3D = null
var _current_target: Node = null
var _prompt_label: Label = null

func set_camera(cam: Camera3D) -> void:
	_camera = cam

func _ready() -> void:
	_create_prompt()

## Prompts: "[E] Do thing" (tap) or "[Hold E] Do thing" (hold) in white;
## anything not starting with a key is a status ("Generator (full)", "Too
## tired to do this"): shown dimmed. Formatting tags are dropped (a Label
## would show them as text).
const PROMPT_COLOR := Color(1, 1, 1, 0.9)
const STATUS_COLOR := Color(0.75, 0.72, 0.66, 0.6)
static var _markup := RegEx.create_from_string("[[]/?(color|b|i|u)(=[^]]*)?[]]")


## What is aimed at, for the crosshair: 0 nothing, 1 something to use,
## 2 a status only.
var target_kind := 0


func _show_prompt(text: String) -> void:
	text = GameKeys.keys_in(_markup.sub(text, "", true))
	_prompt_label.text = text
	var action := text.begins_with("[")
	_prompt_label.add_theme_color_override("font_color", PROMPT_COLOR if action else STATUS_COLOR)
	target_kind = 0 if text == "" else (1 if action else 2)


func _create_prompt() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(0, 0)
	_prompt_label.size = Vector2(0, 0)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_label.offset_top = -220
	_prompt_label.offset_bottom = -180
	_prompt_label.add_theme_color_override("font_color", PROMPT_COLOR)
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_prompt_label.add_theme_font_size_override("font_size", 17)
	_prompt_label.text = ""
	canvas.add_child(_prompt_label)

## Returns the current interactable target (the node the player is looking at).
func get_current_target() -> Node:
	return _current_target


## Walks up the parent chain from a collider to find a node that has the given method.
## This handles cases where the CollisionShape3D is a child of the interactable node.
func _find_interactable(from: Node) -> Node:
	var current = from
	while current:
		if current.has_method("interact"):
			return current
		current = current.get_parent()
	return null


func _process(delta: float) -> void:
	if not _camera:
		return
	
	var space_state = get_world_3d().direct_space_state
	var center = _camera.get_viewport().size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * interaction_distance
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Collide with both physics bodies AND areas (Area3D triggers like LightSwitchTrigger).
	# Without this, Area3D-based interactables will never be detected by the raycast.
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# BUG 1 FIX: Restrict the interaction ray to the dedicated "Interactable"
	# layer (Layer 2) only. Previously the ray hit EVERYTHING (default mask
	# 0xFFFFFFFF), so invisible environment geometry on the porch (roof
	# overhang, stair bodies, cabin bounding colliders) absorbed the ray
	# before it could reach the door or key. Now only layer-2 colliders are
	# considered, and interactables opt into layer 2 in their own scripts.
	query.collision_mask = INTERACTABLE_LAYER_MASK
	# Exclude the player (CharacterBody3D) from the raycast
	# InteractionManager is at: Player > CameraHolder > InteractionManager
	# So get_parent() = CameraHolder, get_parent().get_parent() = Player
	var player = get_parent().get_parent() if get_parent() and get_parent().get_parent() else null
	if player:
		query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		if collider:
			var interactable = _find_interactable(collider)
			if interactable:
				_current_target = interactable
				# Use custom prompt text if the object provides it
				if interactable.has_method("get_interact_text"):
					_show_prompt(interactable.get_interact_text())
				else:
					_show_prompt(prompt_text)
				
				return
	
	_current_target = null
	_prompt_label.text = ""
	target_kind = 0

# E key handling is now managed by PhysicalGrab, which delegates quick taps here.
# This script only handles raycasting for the interaction prompt.
func _input(event: InputEvent) -> void:
	pass
