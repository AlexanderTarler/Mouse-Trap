extends Node3D
class_name PhotoCamera

## PhotoCamera — Floppy Disk Camera tool for documenting hazel mouse nests.
##
## The player picks up the camera in the world, then presses R to equip it.
## When equipped:
##   - RMB holds to zoom in (narrower FOV)
##   - LMB while zoomed takes an instant photo of whatever nest is in the crosshair
##
## A proximity Geiger-counter audio loop helps the player locate nests
## by playing faster static ticks the closer they get to an undocumented nest.
##
## Visual feedback is handled by the CameraHUD scene (camera_hud.tscn), which
## provides corner brackets, labels, screen flash, and freeze-frame.

signal photo_taken(nest_id: String)
signal zoom_toggled(is_zoomed: bool)

## ─── CONSTANTS ───────────────────────────────────────────────────────────────

## Total number of nests placed in the level
const TOTAL_NESTS: int = 3

## Distance for the proximity Geiger counter audio loop
const GEIGER_RADIUS: float = 10.0

## Maximum distance for detecting a photographable nest
const PHOTO_RANGE: float = 5.0

## Zoomed FOV
const ZOOM_FOV: float = 30.0

## Colors for viewfinder states
const COLOR_IDLE: Color = Color(0.0, 0.8, 0.2, 0.7)
const COLOR_ZOOMED: Color = Color(0.9, 0.8, 0.1, 0.8)
const COLOR_NEST_FOUND: Color = Color(0.0, 1.0, 0.3, 0.9)
const COLOR_ERROR: Color = Color(0.9, 0.1, 0.1, 0.8)

## ─── STATE ───────────────────────────────────────────────────────────────────

## Stores the unique nest_id strings of all successfully photographed nests
var documented_nests: Array[String] = []

## Whether the camera is currently equipped (visible and usable)
var is_equipped: bool = false

## Whether the player is zoomed in (RMB held)
var is_zoomed: bool = false

## Reference to the player's camera (found at runtime)
var _camera: Camera3D = null

## Reference to the player controller (found at runtime)
var _player: Node = null

## AudioStreamPlayer3D for the Geiger counter proximity tick
var _geiger_player: AudioStreamPlayer3D = null

## Timer for Geiger tick rate
var _geiger_tick_timer: float = 0.0

## The closest undocumented nest (for Geiger tracking)
var _closest_undocumented_nest: Node = null

## Distance to the closest undocumented nest
var _closest_nest_distance: float = 999.0

## Original camera FOV to restore after zoom
var _original_fov: float = 75.0

## Reference to the CameraHUD scene instance
var _camera_hud = null

## ─── PERMANENT AUDIO PLAYERS ─────────────────────────────────────────────────
## These are created in _ready() and persist for the lifetime of the PhotoCamera.
## They are attached as children so they follow the camera's position in world space,
## making sounds feel like they're coming from the player's hands.

var _shutter_player: AudioStreamPlayer3D = null
var _zoom_player: AudioStreamPlayer3D = null
var _equip_player: AudioStreamPlayer3D = null
var _error_player: AudioStreamPlayer3D = null


## ─── INIT ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Walk up the tree to find the player and camera.
	# PhotoCamera is always a child of Camera3D → CameraHolder → Player.
	_camera = get_parent() as Camera3D
	if _camera:
		_original_fov = _camera.fov
		_player = _camera.get_parent().get_parent()  # CameraHolder → Player
		print("[PhotoCamera] Found camera via parent chain: ", _camera, " player: ", _player)
	else:
		# Fallback: try finding via group
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_camera = _player.get_node_or_null("CameraHolder/Camera3D")
			if _camera:
				_original_fov = _camera.fov
	
	if not _camera:
		print("[PhotoCamera] WARNING: Could not find player camera!")

	# Create the Geiger counter audio player
	_geiger_player = AudioStreamPlayer3D.new()
	_geiger_player.bus = "SFX"
	_geiger_player.max_distance = GEIGER_RADIUS
	_geiger_player.unit_size = 0.5
	var tick_stream = load("res://assets/audio/UI/geiger_tick.ogg")
	if tick_stream:
		_geiger_player.stream = tick_stream
	add_child(_geiger_player)
	
	# ─── CREATE PERMANENT AUDIO PLAYERS ────────────────────────────────────
	# These are non-positional stereo players attached to the PhotoCamera node.
	# They persist for the entire session, avoiding the weak "slip" sound of
	# temporary players that get queue_free'd.
	
	_shutter_player = AudioStreamPlayer3D.new()
	_shutter_player.bus = "SFX"
	_shutter_player.unit_size = 0.8
	_shutter_player.stream = load("res://assets/audio/UI/camera_shutter.ogg")
	add_child(_shutter_player)
	
	_zoom_player = AudioStreamPlayer3D.new()
	_zoom_player.bus = "SFX"
	_zoom_player.unit_size = 0.4
	add_child(_zoom_player)
	
	_equip_player = AudioStreamPlayer3D.new()
	_equip_player.bus = "SFX"
	_equip_player.unit_size = 0.5
	add_child(_equip_player)
	
	_error_player = AudioStreamPlayer3D.new()
	_error_player.bus = "SFX"
	_error_player.unit_size = 0.6
	_error_player.stream = load("res://assets/audio/UI/error_beep.ogg")
	add_child(_error_player)
	
	# NOTE: CameraHUD is NOT instantiated here in _ready(). Instantiating a
	# CanvasLayer during scene construction (before the scene is fully loaded)
	# causes Godot's renderer to not properly register it. The HUD is instead
	# created lazily in equip() when the player first presses R, ensuring the
	# scene tree is fully initialized and rendering.
	
	# Start hidden and inactive
	visible = false
	set_process(false)


## ─── EQUIP / UNEQUIP ─────────────────────────────────────────────────────────

func equip() -> void:
	is_equipped = true
	visible = true
	set_process(true)
	_play_equip_sound()
	
	# ─── LAZY CAMERAHUD INSTANTIATION ─────────────────────────────────────
	# The HUD is NOT created in _ready() because instantiating a CanvasLayer
	# during scene construction (before the scene is fully loaded) causes
	# Godot's renderer to not properly register it. Instead, we create it
	# lazily here on the first equip() call, when the scene tree is fully
	# initialized and rendering. This mirrors the Y-key debug workaround.
	if not _camera_hud:
		var hud_scene = load("res://scenes/camera_hud.tscn")
		if hud_scene:
			_camera_hud = hud_scene.instantiate()
			_camera_hud.photo_camera = self
			# CRITICAL: A 2D CanvasLayer CANNOT render properly if nested
			# inside a 3D spatial child chain. Must be added to scene root.
			if is_inside_tree():
				get_tree().current_scene.add_child(_camera_hud)
				print("[PhotoCamera] CameraHUD instantiated and added to scene root (lazy).")
			else:
				get_window().add_child(_camera_hud)
				print("[PhotoCamera] CameraHUD instantiated and added to window (lazy fallback).")
		else:
			print("[PhotoCamera] WARNING: Could not load camera_hud.tscn!")
	
	# Show the CameraHUD
	if _camera_hud and _camera_hud.has_method("show_hud"):
		_camera_hud.show_hud()


func unequip() -> void:
	is_equipped = false
	visible = false
	set_process(false)
	is_zoomed = false
	
	# Restore FOV
	if _camera:
		_camera.fov = _original_fov
	
	# Restore walk speed
	if _player and "walk_speed" in _player:
		_player.walk_speed = 3.5
	
	# Restore player input if frozen
	if _player:
		_player.set_process_input(true)
		_player.set_physics_process(true)
	
	_play_unequip_sound()
	
	# Hide the CameraHUD
	if _camera_hud and _camera_hud.has_method("hide_hud"):
		_camera_hud.hide_hud()


## ─── PROCESS LOOP ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not is_equipped or not _camera:
		return
	
	# ─── PROXIMITY GEIGER COUNTER ──────────────────────────────────────────
	_update_geiger_counter(delta)
	
	# ─── CONTINUOUS AIM DETECTION (when zoomed) ────────────────────────────
	if is_zoomed:
		_update_aim_detection()
	else:
		# Clear aim label when not zoomed
		if _camera_hud and _camera_hud.has_method("update_aim_status"):
			_camera_hud.update_aim_status("", Color.TRANSPARENT)
		
		# Update disk counter
		if _camera_hud and _camera_hud.has_method("update_disk_count"):
			_camera_hud.update_disk_count(documented_nests.size())


## ─── AIM DETECTION ───────────────────────────────────────────────────────────
## Raycasts from camera center every frame when zoomed to detect nests.
## Updates the CameraHUD in real-time.

func _update_aim_detection() -> void:
	if not _camera:
		return
	
	var space_state = _camera.get_world_3d().direct_space_state
	var viewport_size = _camera.get_viewport().size
	var center = viewport_size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * PHOTO_RANGE
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		# Nothing in frame
		if _camera_hud and _camera_hud.has_method("update_aim_status"):
			_camera_hud.update_aim_status("NO TARGET", Color(0.8, 0.2, 0.2, 0.7))
		if _camera_hud and _camera_hud.has_method("set_bracket_color"):
			_camera_hud.set_bracket_color(COLOR_ZOOMED)
		return
	
	var collider = result.collider
	
	if collider and collider.is_in_group("NestNodes"):
		var nest_id_str = collider.get("nest_id") if "nest_id" in collider else ""
		var already_done = documented_nests.has(nest_id_str) or ("is_photographed" in collider and collider.is_photographed)
		
		if already_done:
			if _camera_hud and _camera_hud.has_method("update_aim_status"):
				_camera_hud.update_aim_status("ALREADY ARCHIVED", Color(0.8, 0.6, 0.1, 0.7))
			if _camera_hud and _camera_hud.has_method("set_bracket_color"):
				_camera_hud.set_bracket_color(COLOR_ZOOMED)
		else:
			if _camera_hud and _camera_hud.has_method("update_aim_status"):
				_camera_hud.update_aim_status("NEST DETECTED", Color(0.0, 1.0, 0.3, 0.9))
			if _camera_hud and _camera_hud.has_method("set_bracket_color"):
				_camera_hud.set_bracket_color(COLOR_NEST_FOUND)
	else:
		if _camera_hud and _camera_hud.has_method("update_aim_status"):
			_camera_hud.update_aim_status("NO TARGET", Color(0.8, 0.2, 0.2, 0.7))
		if _camera_hud and _camera_hud.has_method("set_bracket_color"):
			_camera_hud.set_bracket_color(COLOR_ZOOMED)
	
	if _camera_hud and _camera_hud.has_method("update_disk_count"):
		_camera_hud.update_disk_count(documented_nests.size())


## ─── PROXIMITY GEIGER COUNTER ────────────────────────────────────────────────
## Scans for undocumented nests within GEIGER_RADIUS and adjusts the tick rate
## of a static audio effect. Faster ticks = closer to a hidden nest.
func _update_geiger_counter(delta: float) -> void:
	var all_nests = get_tree().get_nodes_in_group("NestNodes")
	_closest_undocumented_nest = null
	_closest_nest_distance = 999.0
	
	for nest in all_nests:
		if not is_instance_valid(nest):
			continue
		if "is_photographed" in nest and nest.is_photographed:
			continue
		if "nest_id" in nest and documented_nests.has(nest.nest_id):
			continue
		
		var dist = global_position.distance_to(nest.global_position)
		if dist < _closest_nest_distance:
			_closest_nest_distance = dist
			_closest_undocumented_nest = nest
	
	if _closest_undocumented_nest and _closest_nest_distance <= GEIGER_RADIUS:
		var proximity_ratio = 1.0 - (_closest_nest_distance / GEIGER_RADIUS)
		var tick_interval = lerpf(2.0, 0.1, proximity_ratio)
		
		_geiger_tick_timer -= delta
		if _geiger_tick_timer <= 0.0:
			_geiger_tick_timer = tick_interval
			_play_geiger_tick(proximity_ratio)
	else:
		_geiger_tick_timer = 0.0


func _play_geiger_tick(intensity: float) -> void:
	if not _geiger_player or not _geiger_player.stream:
		return
	_geiger_player.pitch_scale = 0.8 + intensity * 0.6
	_geiger_player.volume_db = -20.0 + intensity * 15.0
	_geiger_player.play()


## ─── ZOOM TOGGLE ─────────────────────────────────────────────────────────────
func toggle_zoom(pressed: bool) -> void:
	if not is_equipped:
		return
	
	is_zoomed = pressed
	zoom_toggled.emit(pressed)
	
	if pressed:
		if _camera:
			_camera.fov = ZOOM_FOV
		if _player and "walk_speed" in _player:
			_player.walk_speed = 0.8
		
		if _camera_hud and _camera_hud.has_method("set_bracket_color"):
			_camera_hud.set_bracket_color(COLOR_ZOOMED)
		if _camera_hud and _camera_hud.has_method("set_mode_text"):
			_camera_hud.set_mode_text("🔍 ZOOMED — LMB to capture")
		_play_zoom_in_sound()
	else:
		if _camera:
			_camera.fov = _original_fov
		if _player and "walk_speed" in _player:
			_player.walk_speed = 3.5
		
		if _camera_hud and _camera_hud.has_method("set_bracket_color"):
			_camera_hud.set_bracket_color(COLOR_IDLE)
		if _camera_hud and _camera_hud.has_method("set_mode_text"):
			_camera_hud.set_mode_text("📷 PHOTO MODE — [R] to exit")
		if _camera_hud and _camera_hud.has_method("update_aim_status"):
			_camera_hud.update_aim_status("", Color.TRANSPARENT)
		_play_zoom_out_sound()


## ─── TAKE PHOTO ──────────────────────────────────────────────────────────────
func take_photo() -> void:
	if not is_equipped or not _camera:
		return
	
	# Raycast from camera center to find a nest
	var space_state = _camera.get_world_3d().direct_space_state
	var viewport_size = _camera.get_viewport().size
	var center = viewport_size / 2.0
	var from = _camera.project_ray_origin(center)
	var to = from + _camera.project_ray_normal(center) * PHOTO_RANGE
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		_play_error_beep()
		if _camera_hud and _camera_hud.has_method("trigger_error_flash"):
			_camera_hud.trigger_error_flash()
		return
	
	var collider = result.collider
	
	if collider and collider.is_in_group("NestNodes"):
		var nest_id_str = collider.get("nest_id") if "nest_id" in collider else ""
		
		if documented_nests.has(nest_id_str) or ("is_photographed" in collider and collider.is_photographed):
			_play_error_beep()
			if _camera_hud and _camera_hud.has_method("trigger_error_flash"):
				_camera_hud.trigger_error_flash()
			return
		
		_execute_capture(collider, nest_id_str)
	else:
		_play_error_beep()
		if _camera_hud and _camera_hud.has_method("trigger_error_flash"):
			_camera_hud.trigger_error_flash()


## ─── SHUTTER SNAP & CAPTURE ──────────────────────────────────────────────────
func _execute_capture(nest: Node, nest_id_str: String) -> void:
	# 1. Play the heavy mechanical shutter CLACK
	_play_shutter_sound()
	
	# 2. Trigger the classic horror white flash + snappy freeze via HorrorHUD.
	#    The HorrorHUD node is named "HUD" and is a child of the current scene root.
	#    We find it by absolute path rather than group lookup, since the HorrorHUD
	#    scene does not define a "hud" group.
	var horror_hud = get_node_or_null("/root/CottageHorror/HUD")
	if not horror_hud:
		horror_hud = get_node_or_null("/root/Main/HUD")
	if horror_hud and horror_hud.has_method("trigger_camera_flash_snap"):
		horror_hud.trigger_camera_flash_snap(0.3, 1.0)
	
	# 2b. ALSO trigger the CameraHUD freeze-frame (viewport capture + white flash + freeze)
	#     This is the primary visual effect — it captures the viewport, shows a blinding
	#     white flash, holds the frozen frame for 0.5s, then fades out over 0.2s.
	if _camera_hud and _camera_hud.has_method("trigger_freeze_frame"):
		_camera_hud.trigger_freeze_frame()
	
	# 3. Record the nest immediately
	documented_nests.append(nest_id_str)
	
	# 4. Notify the nest that it's been photographed
	if nest.has_method("photograph"):
		nest.photograph()
	
	# 5. Emit signal
	photo_taken.emit(nest_id_str)
	
	# 6. Freeze player input briefly for the freeze-frame effect.
	#    Player controls will be unfrozen at ~0.7s when the freeze-frame
	#    finishes fading out.
	if _player:
		_player.set_process_input(false)
		_player.set_physics_process(false)
	
	# 7. Connect to CameraHUD's photo_captured signal to unfreeze player early.
	#    The freeze-frame lasts 0.5s hold + 0.2s fade = 0.7s total.
	if _camera_hud and _camera_hud.has_signal("photo_captured"):
		if _camera_hud.photo_captured.is_connected(_on_freeze_frame_completed):
			_camera_hud.photo_captured.disconnect(_on_freeze_frame_completed)
		_camera_hud.photo_captured.connect(_on_freeze_frame_completed)
	
	print("[PhotoCamera] Photo captured! Nest ", nest_id_str, " documented. (", documented_nests.size(), "/", TOTAL_NESTS, ")")
	
	
## Called when the CameraHUD freeze-frame finishes fading out (~0.7s after capture).
## Unfreezes player movement and look controls.
func _on_freeze_frame_completed() -> void:
	if _player:
		_player.set_process_input(true)
		_player.set_physics_process(true)
	
	# Disconnect the signal to avoid accumulating connections across multiple photos
	if _camera_hud and _camera_hud.photo_captured.is_connected(_on_freeze_frame_completed):
		_camera_hud.photo_captured.disconnect(_on_freeze_frame_completed)



## ─── AUDIO FEEDBACK ──────────────────────────────────────────────────────────
## Uses permanent AudioStreamPlayer3D children attached to this node.
## These follow the camera's position in world space, making sounds feel
## like they're coming from the player's hands.

func _play_equip_sound() -> void:
	if not _equip_player:
		return
	var stream = load("res://assets/audio/UI/camera_equip.ogg")
	if stream:
		_equip_player.stream = stream
		_equip_player.play()


func _play_unequip_sound() -> void:
	if not _equip_player:
		return
	var stream = load("res://assets/audio/UI/camera_unequip.ogg")
	if stream:
		_equip_player.stream = stream
		_equip_player.play()


func _play_zoom_in_sound() -> void:
	if not _zoom_player:
		return
	var stream = load("res://assets/audio/UI/camera_zoom_in.ogg")
	if stream:
		_zoom_player.stream = stream
		_zoom_player.play()


func _play_zoom_out_sound() -> void:
	if not _zoom_player:
		return
	var stream = load("res://assets/audio/UI/camera_zoom_out.ogg")
	if stream:
		_zoom_player.stream = stream
		_zoom_player.play()


func _play_shutter_sound() -> void:
	if not _shutter_player or not _shutter_player.stream:
		print("[PhotoCamera] No shutter sound file found at res://assets/audio/UI/camera_shutter.ogg")
		return
	_shutter_player.play()


func _play_error_beep() -> void:
	if not _error_player or not _error_player.stream:
		print("[PhotoCamera] No error beep sound file found at res://assets/audio/UI/error_beep.ogg")
		return
	_error_player.play()
