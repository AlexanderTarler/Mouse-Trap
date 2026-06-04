extends Node

## Listens for the Entity catching the player.
## Executes a cinematic jumpscare, applies survival penalties, and resets the player.

var fade_rect: ColorRect = null
var is_jumping: bool = false
var audio_sting: AudioStreamPlayer = null

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
	
	# 2. Add an audio sting player
	audio_sting = AudioStreamPlayer.new()
	add_child(audio_sting)
	# 3. Connect to the NightManager's event bus
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
	var original_fov = camera.fov
	
	# Freeze player movement
	player.set_physics_process(false)
	player.set_process_input(false)
	
	if audio_sting.stream:
		audio_sting.play()
	
	if cam_holder:
		var face_marker = entity.get_node_or_null("FaceTarget")
		var target_pos = face_marker.global_position if face_marker else entity.global_position + Vector3(0, 1.8, 0)
		
		var target_look = cam_holder.global_transform.looking_at(target_pos, Vector3.UP)
		var tween = create_tween()
		tween.tween_property(cam_holder, "global_transform:basis", target_look.basis, 0.1)
		tween.parallel().tween_property(camera, "fov", 40.0, 0.1)
		
		# --- DYNAMIC CAMERA SHAKE ---
		var shake_tween = create_tween().set_loops(12)
		var shake_intensity = 0.05
		shake_tween.tween_property(camera, "v_offset", shake_intensity, 0.05)
		shake_tween.tween_property(camera, "h_offset", -shake_intensity, 0.05)
		shake_tween.tween_property(camera, "v_offset", -shake_intensity, 0.05)
		shake_tween.tween_property(camera, "h_offset", shake_intensity, 0.05)
		
		# Linger on the monster's face
		await get_tree().create_timer(1.2).timeout
		camera.v_offset = 0
		camera.h_offset = 0
		
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
		
		# FIX CONTROLS — restore original rotation instead of zeroing it
		# Zeroing would snap the camera to look straight forward, which is jarring.
		cam_holder.global_transform.basis = cam_holder.global_transform.basis.orthonormalized()
		camera.fov = original_fov
		
		# Unfreeze player
		player.set_physics_process(true)
		player.set_process_input(true)
		is_jumping = false

func _apply_survival_penalties(player: Node3D) -> void:
	var nm = get_node_or_null("/root/NightManager")
	var current_night = nm.current_night if nm else 1
	
	# --- NIGHTS 3-5: HARD GAME OVER ---
	# On later nights, being caught is fatal. No second chances.
	if current_night >= 3:
		print("[Jumpscare] Night %d — HARD GAME OVER! Player was caught." % current_night)
		_trigger_game_over()
		return
	
	# --- NIGHTS 1-2: SURVIVAL PENALTY (wake up, lose time & flashlight) ---
	player.global_position = Vector3(9.0, 1.0, 0.4)
	
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		# Dynamic penalty: Night 1 is ~0.10, Night 5 is massive (0.25)
		var penalty: float = 0.05 + (current_night * 0.04)
		# Use set_progress() to keep GameTime's internal _elapsed in sync
		if gt.has_method("set_progress"):
			gt.set_progress(minf(1.0, gt.cycle_progress + penalty))
		else:
			gt.cycle_progress = minf(1.0, gt.cycle_progress + penalty)
			gt.time_changed.emit(gt.cycle_progress)
		print("[Jumpscare] Time penalty applied: ", penalty)
	
	var flashlight = player.find_child("*Flashlight*", true, false)
	if flashlight:
		if flashlight.has_method("set_battery_level"):
			flashlight.set_battery_level(0.0)
		elif "battery_level" in flashlight:
			flashlight.battery_level = 0.0
		print("[Jumpscare] Battery drained.")


## Triggers a hard Game Over state: pauses the game, shows a death screen,
## and provides an option to restart the current night.
func _trigger_game_over() -> void:
	# Pause the game
	get_tree().paused = true
	
	# Create a CanvasLayer overlay for the death screen
	var death_canvas = CanvasLayer.new()
	death_canvas.layer = 128  # Above everything
	death_canvas.name = "DeathScreenCanvas"
	get_tree().current_scene.add_child(death_canvas)
	
	# Full-screen black background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_canvas.add_child(bg)
	
	# "YOU DIED" text
	var death_label = Label.new()
	death_label.text = "YOU DIED"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_label.add_theme_font_size_override("font_size", 64)
	death_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.size = Vector2(400, 100)
	death_label.position = Vector2(-200, -80)
	death_canvas.add_child(death_label)
	
	# Night info
	var night_label = Label.new()
	var nm = get_node_or_null("/root/NightManager")
	var night_num = nm.current_night if nm else 1
	night_label.text = "Night %d" % night_num
	night_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	night_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	night_label.add_theme_font_size_override("font_size", 32)
	night_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	night_label.set_anchors_preset(Control.PRESET_CENTER)
	night_label.size = Vector2(200, 50)
	night_label.position = Vector2(-100, 10)
	death_canvas.add_child(night_label)
	
	# Restart button
	var restart_btn = Button.new()
	restart_btn.text = "Restart Night"
	restart_btn.set_anchors_preset(Control.PRESET_CENTER)
	restart_btn.size = Vector2(200, 50)
	restart_btn.position = Vector2(-100, 80)
	restart_btn.pressed.connect(_on_restart_night.bind(death_canvas))
	death_canvas.add_child(restart_btn)


func _on_restart_night(death_canvas: CanvasLayer) -> void:
	# Unpause
	get_tree().paused = false
	
	# Remove the death screen
	death_canvas.queue_free()
	
	# Restart the current night via NightManager
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("restart_night"):
		nm.restart_night()
