extends Node

## Listens for the Entity catching the player.
## Executes a cinematic jumpscare, applies survival penalties, and resets the player.

var fade_rect: ColorRect
var is_jumping: bool = false

func _ready() -> void:
	# 1. Dynamically generate the Black Screen Overlay so no scene setup is needed
	var canvas = CanvasLayer.new()
	canvas.layer = 127 # Draw above absolutely everything (including the inventory)
	add_child(canvas)
	
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 0) # Start transparent
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(fade_rect)
	
	# 2. Connect to the NightManager's event bus
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.connect(_on_horror_event)

func _input(event: InputEvent) -> void:
	# Press F1 to instantly trigger the jumpscare at any time
	if event is InputEventKey and event.keycode == KEY_F1 and event.pressed and not event.is_echo():
		if not is_jumping:
			_execute_jumpscare()		

func _on_horror_event(event_name: String) -> void:
	if event_name == "entity_caught_player" and not is_jumping:
		_execute_jumpscare()

func _execute_jumpscare() -> void:
		is_jumping = true
		var player = get_tree().get_first_node_in_group("player") as Node3D
		var entity = get_tree().get_first_node_in_group("entity") as Node3D
		if not player or not entity: return
		
		var cam_holder = player.get_node_or_null("CameraHolder")
		var camera = get_viewport().get_camera_3d()
		
		# Freeze player movement
		player.set_physics_process(false)
		player.set_process_input(false)
		
		if cam_holder:
			var face_marker = entity.get_node_or_null("FaceTarget")
			var target_pos = face_marker.global_position if face_marker else entity.global_position + Vector3(0, 1.8, 0)
			
			var target_look = cam_holder.global_transform.looking_at(target_pos, Vector3.UP)
			var tween = create_tween()
			tween.tween_property(cam_holder, "global_transform:basis", target_look.basis, 0.1)
			tween.parallel().tween_property(camera, "fov", 40.0, 0.1)
			
			# Linger on the monster's face
			await get_tree().create_timer(1.2).timeout
			
			# FADE OUT (Black screen)
			var fade_tween = create_tween()
			fade_tween.tween_property(fade_rect, "color:a", 1.0, 0.5)
			await fade_tween.finished
			
			# APPLY PENALTIES
			_apply_survival_penalties(player)
			
			# WAKE UP (Fade back in)
			var wake_tween = create_tween()
			wake_tween.tween_property(fade_rect, "color:a", 0.0, 2.0)
			await wake_tween.finished
			
			# FIX CONTROLS: Explicitly reset the CameraHolder rotation so controls feel normal
			cam_holder.rotation = Vector3.ZERO 
			
			# Unfreeze player
			player.set_physics_process(true)
			player.set_process_input(true)
			is_jumping = false

func _apply_survival_penalties(player: Node3D) -> void:
	# A. TELEPORT TO CABIN
	# Adjust these coordinates to exactly match your cabin floor
	player.global_position = Vector3(9.0, 1.0, 0.4) 
	
	# B. ADVANCE TIME (The 2-Hour Penalty)
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		# Add 0.15 to cycle progress (pushes the night much closer to dawn, giving less time for tasks)
		gt.cycle_progress = min(1.0, gt.cycle_progress + 0.15) 
		gt.time_changed.emit(gt.cycle_progress)
		print("[Jumpscare] Time penalty applied.")
		
# C. DRAIN FLASHLIGHT BATTERY
	# Searches the player for a flashlight node to kill its battery
	var flashlight = player.find_child("*Flashlight*", true, false)
	if flashlight:
		if "battery" in flashlight:
			flashlight.battery = 0.0
		elif "energy" in flashlight:
			flashlight.energy = 0.0
		print("[Jumpscare] Battery drained.")
