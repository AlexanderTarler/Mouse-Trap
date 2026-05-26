extends Area3D
class_name PCInteractable

## PCInteractable — Physical PC monitor interaction trigger.
## Attach this script to an Area3D (named "InteractionArea") that is a child
## of the pc_monitor_mp_12 model node in the scene.
##
## When the player looks at the monitor and presses E, this script opens
## the ComputerUI overlay (Windows 98-style Archival System).
##
## The InteractionArea needs a CollisionShape3D child (a box shape works well)
## positioned to cover the monitor screen so the player can click on it.

## Path to the ComputerUI scene (computer_ui.tscn)
@export var computer_ui_scene: PackedScene = preload("res://scenes/computer_ui.tscn")

## Marker3D that defines where the player's camera should be positioned
## when sitting at the computer (cinematic sitting transition).
@export var sit_marker: Marker3D

## Reference to the instantiated ComputerUI (stored as Node to avoid parse-time
## type resolution issues with the ComputerUI class_name)
var _computer_ui: Node = null

## Reference to the player's CameraHolder node (found at runtime)
var _camera_holder: Node3D = null

## The CameraHolder's original global transform, saved before the sitting tween
var _original_cam_transform: Transform3D


func _ready() -> void:
	add_to_group("interactable")
	
	# Instantiate the UI
	_computer_ui = computer_ui_scene.instantiate()
	
	# Find the player's CameraHolder for the sitting animation
	_camera_holder = _find_camera_holder()
	
	# Pass player and camera_holder references to the ComputerUI
	# so it doesn't need to look them up itself (more reliable)
	if _computer_ui and _computer_ui.has_method("set_player_references"):
		var player = get_tree().get_first_node_in_group("player")
		_computer_ui.set_player_references(player, _camera_holder)
	
	# Ensure it's hidden by default
	if _computer_ui and _computer_ui.has_method("close_computer"):
		_computer_ui.close_computer()
	
	# Defer adding the UI to the tree to ensure the scene is fully loaded.
	# Adding to get_tree().root during _ready() can fail if the tree isn't
	# fully initialized yet, leaving the UI orphaned and invisible.
	if _computer_ui:
		call_deferred("_add_ui_to_tree")


## Adds the ComputerUI to the scene tree as a child of the current scene.
## Called via call_deferred() from _ready() to ensure the tree is ready.
func _add_ui_to_tree() -> void:
	if not _computer_ui:
		return
	
	# Try to add to current_scene first (most reliable)
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(_computer_ui)
		print("[PCInteractable] ComputerUI added to current_scene: ", scene.name)
		return
	
	# Fallback: add to root
	var root = get_tree().root
	if root:
		root.add_child(_computer_ui)
		print("[PCInteractable] ComputerUI added to root")
		return
	
	print("[PCInteractable] ERROR: Could not add ComputerUI to tree!")


## Walks up the scene tree to find the Player's CameraHolder node.
func _find_camera_holder() -> Node3D:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var holder = player.get_node_or_null("CameraHolder")
		if holder is Node3D:
			return holder
	return null


## Called by the InteractionManager when the player looks at the monitor
## and presses E. Opens the computer UI overlay with a cinematic sitting
## camera transition.
func interact() -> void:
	if not _computer_ui:
		print("[PCInteractable] ComputerUI not available!")
		return
	
	if not _camera_holder:
		print("[PCInteractable] CameraHolder not found!")
		return
	
	if not sit_marker:
		print("[PCInteractable] sit_marker not assigned!")
		return
	
	# --- DISABLE PLAYER INPUT FIRST ---
	# We must disable the player BEFORE the tween, otherwise the player
	# controller's _input() and _physics_process() will fight the tween
	# every frame, causing erratic camera movement.
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_process_input(false)
		player.set_physics_process(false)
	
	# Unlock the mouse so the tween can move the camera freely
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Save the CameraHolder's original transform so we can return to it later
	_original_cam_transform = _camera_holder.global_transform
	
	# Pass the original transform to the ComputerUI so it can restore it on close
	if _computer_ui.has_method("set_original_camera_transform"):
		_computer_ui.set_original_camera_transform(_original_cam_transform)
	
	# Tween the CameraHolder to the sit_marker's position
	var tween = create_tween()
	tween.set_parallel(false)
	tween.tween_property(_camera_holder, "global_transform", sit_marker.global_transform, 0.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# After the tween finishes, open the computer UI
	tween.finished.connect(_on_sit_tween_completed)
	
	print("[PCInteractable] Player sitting at the PC monitor.")


## Called when the sitting tween animation completes.
## Opens the computer UI overlay.
func _on_sit_tween_completed() -> void:
	if _computer_ui.has_method("open_computer"):
		_computer_ui.open_computer()
		print("[PCInteractable] Player interacted with the PC monitor.")
	else:
		print("[PCInteractable] ERROR: ComputerUI missing open_computer method!")


## Returns the interaction prompt text shown in the HUD.
func get_interact_text() -> String:
	return "[E] Use Computer"
