extends Node

## Listens for the Entity catching the player.
## Executes a cinematic jumpscare, applies survival penalties, and resets the player.
##
## UI is handled via exported scene references (jumpscare_canvas.tscn and death_screen.tscn)
## instead of programmatic Control node generation. Assign these in the editor.

## Reference to a pre-made jumpscare canvas scene containing the fade overlay.
const jumpscare_scene = preload("res://scenes/jumpscare_canvas.tscn")
const death_screen_scene = preload("res://scenes/death_screen.tscn")

## Audio sting played during the jumpscare face-zoom.
@export var audio_sting: AudioStream = null

var _fade_rect: ColorRect = null
var is_jumping: bool = false
var _audio_sting_player: AudioStreamPlayer = null


func _ready() -> void:
	# Ensure this node processes input even when the game is paused
	# (needed for the death screen buttons to work and for debug logging)
	process_mode = PROCESS_MODE_ALWAYS
	
	# 1. Instantiate the jumpscare canvas scene if provided
	if jumpscare_scene:
		var canvas = jumpscare_scene.instantiate()
		add_child(canvas)
		# Find the FadeRect child
		_fade_rect = canvas.get_node_or_null("FadeRect") as ColorRect
		if not _fade_rect:
			# Try recursive search
			_fade_rect = canvas.find_child("FadeRect", true, false) as ColorRect
		if _fade_rect:
			_fade_rect.color = Color(0, 0, 0, 0)  # Start transparent
	else:
		print("[Jumpscare] WARNING: No jumpscare_scene assigned! Fade overlay will not work.")
	
	# 2. Add an audio sting player
	_audio_sting_player = AudioStreamPlayer.new()
	if audio_sting:
		_audio_sting_player.stream = audio_sting
	add_child(_audio_sting_player)
	
	# 3. Connect to the NightManager's event bus
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.connect(_on_horror_event)

func _input(event: InputEvent) -> void:
	# DEBUG: Log every left-click and what was clicked
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos = get_viewport().get_mouse_position()
		# Use raycasting from the current camera to find what's under the cursor
		var camera = get_viewport().get_camera_3d()
		var clicked_node = null
		if camera:
			var from = camera.project_ray_origin(mouse_pos)
			var dir = camera.project_ray_normal(mouse_pos)
			var space_state = camera.get_world_3d().direct_space_state
			if space_state:
				var params = PhysicsRayQueryParameters3D.new()
				params.from = from
				params.to = from + dir * 1000.0
				var result = space_state.intersect_ray(params)
				if result and result.has("collider"):
					clicked_node = result.collider
		var clicked_name = clicked_node.name if clicked_node else "nothing (UI)"
		print("[DEBUG] Left-click at (%d, %d) — clicked: %s" % [mouse_pos.x, mouse_pos.y, clicked_name])
	
	# Press F1 to instantly trigger the jumpscare (debug only — requires dev mode)
	if event is InputEventKey and event.keycode == KEY_F1 and event.pressed and not event.is_echo():
		if not is_jumping:
			var nm = get_node_or_null("/root/NightManager")
			if nm and nm.is_dev_mode:
				_execute_jumpscare()

func _on_horror_event(event_name: String) -> void:
	if event_name == "entity_caught_player" and not is_jumping:
		_execute_jumpscare()

func _execute_jumpscare() -> void:
	print("[JumpscareManager] _execute_jumpscare() called.")
	is_jumping = true
	var player = get_tree().get_first_node_in_group("player") as Node3D
	var entity = get_tree().get_first_node_in_group("entity") as Node3D
	if not player:
		print("[JumpscareManager] ERROR: Player not found in group 'player'!")
		return
	if not entity:
		print("[JumpscareManager] ERROR: Entity not found in group 'entity'!")
		return
	print("[JumpscareManager] Player and Entity found. Executing jumpscare...")

	
	var cam_holder = player.get_node_or_null("CameraHolder")
	var camera = get_viewport().get_camera_3d()
	var original_fov = camera.fov
	
	# Freeze player movement
	player.set_physics_process(false)
	player.set_process_input(false)
	
	if _audio_sting_player and _audio_sting_player.stream:
		_audio_sting_player.play()
	
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
		
		# Linger on the monster's face (extended for dramatic effect)
		await get_tree().create_timer(3.2).timeout
		camera.v_offset = 0
		camera.h_offset = 0
		
		# FADE OUT (Black screen)
		var fade_tween = create_tween()
		fade_tween.tween_property(_fade_rect, "color:a", 1.0, 0.5)
		await fade_tween.finished
		
		# GAME OVER — always trigger the death screen after a jumpscare.
		# The player must restart the night from the death screen.
		_trigger_game_over()
		
		# FIX CONTROLS — reset camera rotation and offsets to zero
		# This prevents the camera from being permanently tilted after respawn.
		if player.has_method("reset_camera"):
			player.reset_camera()
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
	print("[JumpscareManager] _trigger_game_over() called.")
	
	# Pause the game
	get_tree().paused = true
	print("[JumpscareManager] Game paused.")
	
	# Free the cursor so the player can click the death screen buttons
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[JumpscareManager] Mouse mode set to VISIBLE.")
	
	if death_screen_scene:
		print("[JumpscareManager] Instantiating death screen scene: %s" % death_screen_scene.resource_path)
		var death_canvas = death_screen_scene.instantiate()
		death_canvas.name = "DeathScreenCanvas"
		
		var current_scene = get_tree().current_scene
		if not current_scene:
			print("[JumpscareManager] ERROR: current_scene is null!")
			return
		print("[JumpscareManager] Adding death screen to scene: %s" % current_scene.name)
		current_scene.add_child(death_canvas)
		print("[JumpscareManager] Death screen added. Children count: %d" % current_scene.get_child_count())
		
		# Find and connect the restart button
		var restart_btn = death_canvas.find_child("RestartButton", true, false) as Button
		if restart_btn:
			print("[JumpscareManager] Found RestartButton. Connecting pressed signal...")
			restart_btn.pressed.connect(_on_restart_night.bind(death_canvas))
			print("[JumpscareManager] RestartButton connected.")
		else:
			print("[JumpscareManager] ERROR: RestartButton not found in death screen!")
		
		# Update the night label if present
		var night_label = death_canvas.find_child("NightLabel", true, false) as Label
		if night_label:
			var nm = get_node_or_null("/root/NightManager")
			var night_num = nm.current_night if nm else 1
			night_label.text = "Night %d" % night_num
			print("[JumpscareManager] Night label set to: Night %d" % night_num)
	else:
		print("[JumpscareManager] WARNING: No death_screen_scene assigned! Cannot show game over screen.")
		# Fallback: just unpause and restart
		get_tree().paused = false
		var nm = get_node_or_null("/root/NightManager")
		if nm and nm.has_method("restart_night"):
			nm.restart_night()


func _on_restart_night(death_canvas: CanvasLayer) -> void:
	print("[JumpscareManager] _on_restart_night() called — \"Restart from morning\" button was clicked.")
	
	# Fade the jumpscare overlay back to transparent so the player can see
	if _fade_rect:
		print("[JumpscareManager] Fading jumpscare overlay back to transparent...")
		var fade_in_tween = create_tween()
		fade_in_tween.tween_property(_fade_rect, "color:a", 0.0, 0.5)
		await fade_in_tween.finished
		print("[JumpscareManager] Fade-in complete.")
	
	# Unpause
	get_tree().paused = false
	
	# Recapture the cursor so the player can look around
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Remove the death screen
	death_canvas.queue_free()
	
	# Restart from the morning of the current day via NightManager.
	# This fully resets the player, inventory, world state, and time
	# to the morning baseline, then waits for the natural day/night
	# cycle to reach night again.
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("restart_from_morning"):
		print("[JumpscareManager] Calling NightManager.restart_from_morning()...")
		nm.restart_from_morning()
	else:
		print("[JumpscareManager] ERROR: NightManager not found or restart_from_morning() method missing!")
