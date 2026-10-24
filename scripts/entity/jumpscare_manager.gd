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
## The sting when audio_sting isn't assigned.
const AUDIO_STING_DEFAULT := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Bonus/Pure Horror/One-shots/stinger_ph_3.ogg"

var _fade_rect: ColorRect = null
var is_jumping: bool = false
var _audio_sting_player: AudioStreamPlayer = null
## The player's gasp as it's on them.
const GASP_STREAM := preload("res://assets/audio/player/Gasp.wav")
var _gasp_player: AudioStreamPlayer = null


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
	_audio_sting_player.bus = &"SFX"
	if audio_sting:
		_audio_sting_player.stream = audio_sting
	elif ResourceLoader.exists(AUDIO_STING_DEFAULT):
		_audio_sting_player.stream = load(AUDIO_STING_DEFAULT)
	add_child(_audio_sting_player)
	_gasp_player = AudioStreamPlayer.new()
	_gasp_player.bus = &"SFX"
	_gasp_player.stream = GASP_STREAM
	_gasp_player.volume_db = -3.0
	add_child(_gasp_player)
	
	# 3. Connect to the NightManager's event bus
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.connect(_on_horror_event)

func _input(event: InputEvent) -> void:
	# DEBUG: Log every left-click and what was clicked
	# (Debug builds only: in an exported game it raycast on every click.)
	if OS.is_debug_build() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
	if _gasp_player:
		_gasp_player.play()
	
	if cam_holder:
		# ─── TASK 1 FIX: PROPER LOOK_AT CAMERA LOCK ─────────────────
		# The old math computed the look direction from player.global_position
		# (the body's FEET, y≈0) to a target at head height (1.8). That produced
		# a wildly upward pitch (atan2(1.8, dist)) — the camera ended up looking
		# away / slightly upward instead of locking onto the Entity's face.
		#
		# Fix: compute the look vector from the CAMERA EYE position
		# (cam_holder.global_position, ~1.7m standing height) to the Entity's
		# head/chest height (1.5m). This gives a correct look_at that snaps
		# directly to the Entity's face.
		#
		# We decompose the look direction into body yaw + holder pitch (the same
		# split used by mouse-look) instead of baking a full Basis.looking_at()
		# into the holder. Baking yaw into the holder's LOCAL axes would corrupt
		# the basis and cause a spin-out/gimbal-lock on the next mouse move —
		# the exact bug fixed by Task 2. This decomposition is mathematically
		# equivalent to look_at() for a yaw-on-body / pitch-on-holder hierarchy.
		var face_marker = entity.get_node_or_null("FaceTarget")
		var target_pos: Vector3 = face_marker.global_position if face_marker else entity.global_position + Vector3(0, 1.5, 0)
		
		var look_from: Vector3 = cam_holder.global_position
		var to_entity: Vector3 = target_pos - look_from
		var horizontal: float = Vector2(to_entity.x, to_entity.z).length()
		if horizontal > 0.001:
			var yaw: float = atan2(-to_entity.x, -to_entity.z)
			var pitch: float = clampf(atan2(to_entity.y, horizontal), -1.4, 1.4)
			var tween = create_tween()
			tween.tween_property(player, "rotation:y", yaw, 0.1)
			tween.parallel().tween_property(cam_holder, "rotation:x", pitch, 0.1)
			tween.parallel().tween_property(camera, "fov", 40.0, 0.1)
		
		# --- DYNAMIC CAMERA SHAKE ---
		var shake_tween = create_tween().set_loops(12)
		var shake_intensity = 0.05 * GameSettings.shake()
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
		
		# The death cutscene ("The Drag") plays on the black screen.
		await _play_death_cinematic()
		
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

## EndgameCinematics.play_death: our black fade steps aside while it plays
## (it has its own), and is back up when it ends.
func _play_death_cinematic() -> void:
	var cinematics = get_tree().get_first_node_in_group("cinematics")
	if not cinematics or not cinematics.has_method("play_death"):
		return
	cinematics.cover()
	if _fade_rect:
		_fade_rect.color.a = 0.0
	await cinematics.play_death()
	if _fade_rect:
		_fade_rect.color.a = 1.0
	cinematics.clear_overlay()


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
## Survival tips for the death screen, by where the player was caught.
const TIPS_OUTSIDE := [
	"It hunts by sound. Walk, or crouch: sprinting brings it to you.",
	"Crouched in tall plants, you're hard to see, even up close.",
	"Light makes it hesitate. The porch light and lit rooms are safer ground.",
]
const TIPS_INSIDE := [
	"It won't come in through the window of a lit room.",
	"Board up broken windows: planks hold it back for a while.",
	"Hold F to overcharge the flashlight: the beam drives it off.",
	"It listens. A locked door and a quiet house buy you time.",
]
const TIP_CHARGE := "When it roars, it's about to lunge: get out of its sight, fast."


## One line under the death screen's buttons: how to survive what just
## happened.
func _add_death_tip(death_canvas: Node) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var entity = get_tree().get_first_node_in_group("entity")
	var tip: String
	if entity and entity.get("brain") and entity.brain.state_id == entity.State.CHARGE and randf() < 0.5:
		tip = TIP_CHARGE
	elif player and player.has_method("get_player_room") and player.get_player_room() == "Outside":
		tip = TIPS_OUTSIDE.pick_random()
	else:
		tip = TIPS_INSIDE.pick_random()
	var label := Label.new()
	label.name = "TipLabel"
	label.text = tip
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7, 0.85))
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -360.0
	label.offset_right = 360.0
	label.offset_top = 190.0
	label.offset_bottom = 250.0
	death_canvas.add_child(label)


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
		
		# The death screen's Main Menu button (it had no handler, so it did nothing).
		var menu_btn = death_canvas.find_child("MainMenuButton", true, false) as Button
		if menu_btn:
			menu_btn.pressed.connect(_on_main_menu_from_death.bind(death_canvas))
		
		# Update the night label if present
		# "Night 2" / "Day 3": the same names the HUD and notebook use.
		var night_label = death_canvas.find_child("NightLabel", true, false) as Label
		var rm = get_node_or_null("/root/RoutineManager")
		if night_label:
			var when: String
			if rm and rm.has_method("get_current_day_string"):
				when = rm.get_current_day_string()
			else:
				var nm = get_node_or_null("/root/NightManager")
				when = "Night %d" % (nm.current_night if nm else 1)
			night_label.text = "%s. The researcher is missing." % when
			night_label.custom_minimum_size.x = 600.0
		# A line in the field report, in the title typewriter face.
		var death_label = death_canvas.find_child("DeathLabel", true, false) as Label
		if death_label:
			GameFonts.use_title(death_label)
		_add_death_tip(death_canvas)
		# Where restarting puts the player: this morning, or tonight's start.
		if restart_btn:
			var checkpoint = get_node_or_null("/root/Checkpoint")
			var kind: String = checkpoint.kind if checkpoint else ""
			if kind == "day":
				restart_btn.text = "Restart from this morning"
			elif kind == "night":
				restart_btn.text = "Restart from nightfall"
	else:
		print("[JumpscareManager] WARNING: No death_screen_scene assigned! Cannot show game over screen.")
		# Fallback: just unpause and restart
		get_tree().paused = false
		var nm = get_node_or_null("/root/NightManager")
		if nm and nm.has_method("restart_night"):
			nm.restart_night()


## Death screen -> main menu. The checkpoint stays as it was (capture_on_quit
## doesn't save during a death anyway), so Continue still has it.
func _on_main_menu_from_death(death_canvas: CanvasLayer) -> void:
	if _fade_rect:
		_fade_rect.color.a = 0.0
	var em := get_node_or_null("/root/EndgameManager")
	if em and em.has_method("reset"):
		em.reset()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(death_canvas):
		death_canvas.queue_free()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_restart_night(death_canvas: CanvasLayer) -> void:
	print("[JumpscareManager] _on_restart_night() called — \"Restart from Checkpoint\" button was clicked.")
	
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
	
	# FEATURE 1: Restart from the CURRENT CHECKPOINT via NightManager.
	# restart_from_checkpoint() branches on the active phase:
	#   - Night active → resets time/state to the exact start of the
	#     current night (GameTime dusk + start_night(current_night)).
	#   - Day active → falls back to the morning/day baseline.
	var nm = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("restart_from_checkpoint"):
		print("[JumpscareManager] Calling NightManager.restart_from_checkpoint()...")
		nm.restart_from_checkpoint()
	elif nm and nm.has_method("restart_from_morning"):
		print("[JumpscareManager] WARNING: restart_from_checkpoint() missing. Falling back to restart_from_morning().")
		nm.restart_from_morning()
	else:
		print("[JumpscareManager] ERROR: NightManager not found or restart methods missing!")
