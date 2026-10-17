extends CanvasLayer

## HUD overlay for the horror game showing day/night cycle progression and events.

@onready var night_label: Label = $NightLabel
@onready var time_label: Label = $TimeLabel
@onready var clock_label: Label = $ClockLabel
@onready var event_label: Label = $EventLabel
@onready var event_timer: Timer = $EventTimer
@onready var phase_bar: ProgressBar = $PhaseBar
@onready var objective_label: Label = $ObjectiveLabel

# Onboarding hint nodes
@onready var hint_label: Label = $HintLabel
@onready var hint_timer: Timer = $HintTimer

# Battery meter nodes
@onready var battery_bar: ProgressBar = $BatteryBar
@onready var battery_label: Label = $BatteryBar/BatteryLabel
@onready var low_battery_warning: Label = $LowBatteryWarning

# Stamina meter nodes
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var stamina_label: Label = $StaminaBar/StaminaLabel

# Fuel meter nodes
@onready var fuel_bar: TextureProgressBar = $GeneratorFuelBar
@onready var fuel_label: Label = $GeneratorFuelBar/FuelLabel

# Ending screen nodes (escape endings)
@onready var ending_screen: Panel = $EndingScreen
@onready var mediocre_ending_label: Label = $EndingScreen/MediocreEndingLabel
@onready var good_ending_label: Label = $EndingScreen/GoodEndingLabel
@onready var main_menu_button: Button = $EndingScreen/MainMenuButton

## Reference to the EnvironmentController (set in the scene)
@export var environment_controller: Node

# Flashlight reference
var _flashlight: Node = null

# Low battery warning flicker timer
var _warning_flicker_timer: float = 0.0
var _warning_visible: bool = false

# Message queue for event labels — ensures each message gets its full display time
var _message_queue: Array[String] = []
var _message_busy: bool = false

# ─── PURGE PROGRESS ─────────────────────────────────────────────────────
# While the totem is being purged, its progress goes to the crosshair's ring.
var _purge_bar_visible: bool = false

# ─── FADE-TO-BLACK SYSTEM ──────────────────────────────────────────────
# A full-screen ColorRect overlay that tweens alpha for cinematic fades.
# Created programmatically in _ready() so no scene changes are needed.
var _fade_overlay: ColorRect = null

# ─── ROOM DEBUG LABEL ──────────────────────────────────────────────────
# A small label in the top-left corner showing which room the player is in.
# Created programmatically in _ready() so no scene changes are needed.
var _room_label: Label = null
var _room_label_visible: bool = false

# ─── ITEM PICKUP FEEDBACK LABEL ────────────────────────────────────────
# A dynamic label at the bottom-center of the HUD that pops up whenever an
# item or car part is added to the inventory ("Added [Item Name] to
# inventory"), fades in, holds briefly, then fades out.
var _pickup_label: Label = null
var _pickup_tween: Tween = null


## Developer info (the clock, time to day/night, the phase bar, the room,
## the generator) shows only with F3, like the Entity debug overlay.
var debug_info_visible := false


## The quiet gauges (battery, stamina) that replace the coloured bars.
var _gauges: HudGauges = null
var _day_tween: Tween = null


func _ready() -> void:
	add_to_group("hud")
	# The battery and stamina as quiet gauges (HudGauges); the old bars and
	# their emoji labels stay hidden.
	_gauges = HudGauges.new()
	add_child(_gauges)
	for old in [battery_bar, low_battery_warning, stamina_bar]:
		if old:
			old.visible = false
			old.modulate.a = 0.0
	
	# Ending screen: wire the Main Menu button and hide the panel by default.
	if main_menu_button and not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if ending_screen:
		ending_screen.visible = false
	
	# Create the fade overlay programmatically
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 0)  # Start fully transparent
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block clicks
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.z_index = 100  # Render above everything
	add_child(_fade_overlay)

	# ─── ITEM PICKUP FEEDBACK LABEL ──────────────────────────────
	# Created programmatically (like _fade_overlay / _room_label) so no
	# scene changes are needed. Positioned at the bottom-center of the
	# screen, just above the bottom edge, with warm text + shadow for
	# readability over any background.
	_pickup_label = Label.new()
	_pickup_label.name = "PickupLabel"
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.anchor_left = 0.5
	_pickup_label.anchor_right = 0.5
	_pickup_label.anchor_top = 0.85
	_pickup_label.anchor_bottom = 0.85
	_pickup_label.offset_left = -300.0
	_pickup_label.offset_top = 40.0
	_pickup_label.offset_right = 300.0
	_pickup_label.offset_bottom = 70.0
	_pickup_label.add_theme_font_size_override("font_size", 16)
	_pickup_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.76, 0.75))
	_pickup_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_pickup_label.add_theme_constant_override("shadow_offset_x", 2)
	_pickup_label.add_theme_constant_override("shadow_offset_y", 2)
	_pickup_label.z_index = 5
	_pickup_label.modulate.a = 0.0
	add_child(_pickup_label)
	
	# ─── CONNECT INVENTORY ITEM-ADDED SIGNAL ─────────────────────
	# Whenever an item is added to the player's inventory (pickups,
	# stash transfers, car parts, starting items), show the
	# "Added ... to inventory" feedback label.
	var inv := get_node_or_null("/root/Inventory")
	if inv and inv.has_signal("item_added"):
		inv.item_added.connect(_on_item_added)

	# ─── IMMEDIATE DATA SYNC ───────────────────────────────────
	# GameTime starts paused (no signals emitted), so we must
	# manually pull the current state from all autoloads to
	# overwrite the .tscn placeholder text immediately.
	_sync_all_displays()

	# ─── SIGNAL CONNECTIONS ────────────────────────────────────
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.horror_event.connect(_on_horror_event)
		nm.fuel_changed.connect(_on_generator_fuel_changed)
		nm.generator_state_changed.connect(_on_generator_state_changed)
		nm.first_chase_started.connect(_on_first_chase_started)

	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.time_changed.connect(_on_game_time_changed)

	# Find EnvironmentController if not assigned
	if not environment_controller:
		environment_controller = get_tree().get_first_node_in_group("environment_controller")

	event_label.modulate = Color(1, 1, 1, 0)

	# Connect the event timer's timeout signal so messages fade properly
	if event_timer:
		event_timer.timeout.connect(_on_event_timer_timeout)

	# Find the flashlight and connect to its battery_changed signal
	_find_and_connect_flashlight()

	# Connect to player stamina signal
	_find_and_connect_stamina()

	# Connect to RoutineManager for Night 1 bedtime routine objective
	_connect_routine_manager()
	_apply_debug_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_info_visible = not debug_info_visible
		_apply_debug_visibility()


func _apply_debug_visibility() -> void:
	for control in [time_label, clock_label, phase_bar, fuel_bar, _room_label]:
		if control:
			control.visible = debug_info_visible


## The battery shows only while the flashlight is on.
func _update_battery_visibility() -> void:
	var on: bool = _flashlight != null and is_instance_valid(_flashlight) and "is_on" in _flashlight and _flashlight.is_on
	if _gauges:
		_gauges.light_on = on


## Fades the screen to pitch black over the given duration.
## Uses a Tween on the _fade_overlay ColorRect alpha.
func fade_to_black(duration: float = 1.5) -> void:
	if not _fade_overlay:
		return
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks during fade
	var tween = create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, duration)
	await tween.finished


## Fades the screen back in from pitch black over the given duration.
## Uses a Tween on the _fade_overlay ColorRect alpha.
func fade_from_black(duration: float = 2.0) -> void:
	if not _fade_overlay:
		return
	var tween = create_tween()
	tween.tween_property(_fade_overlay, "color:a", 0.0, duration)
	await tween.finished
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Restore click-through


## ─── CAMERA FLASH SNAP ─────────────────────────────────────────────────────
## High-priority white flash overlay for the photo camera's shutter.
##
## freeze_duration: How long the screen stays fully white (default 0.3s).
## decay_duration:  How long the white flash takes to fade to transparent (default 1.0s).
##
## The flash overlay is created programmatically (like _fade_overlay) so it
## works independently of the CameraHUD scene. This ensures the flash always
## renders, even if the CameraHUD has rendering issues.
var _camera_flash_overlay: ColorRect = null

func trigger_camera_flash_snap(freeze_duration: float = 0.3, decay_duration: float = 1.0) -> void:
	# Lazily create the camera flash overlay (same pattern as _fade_overlay)
	if not _camera_flash_overlay:
		_camera_flash_overlay = ColorRect.new()
		_camera_flash_overlay.color = Color(1, 1, 1, 0)  # Start transparent
		_camera_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_camera_flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_camera_flash_overlay.z_index = 101  # Above _fade_overlay (100)
		add_child(_camera_flash_overlay)
	
	# Phase 1: Instant white flash
	_camera_flash_overlay.color = Color(1, 1, 1, 1.0)
	_camera_flash_overlay.visible = true
	
	# Phase 2: Hold the freeze for freeze_duration seconds
	await get_tree().create_timer(freeze_duration).timeout
	
	# Phase 3: Elegant Tween decay over decay_duration seconds
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_camera_flash_overlay, "color:a", 0.0, decay_duration)
	await tween.finished
	
	# Cleanup
	_camera_flash_overlay.visible = false


func _connect_routine_manager() -> void:
	var rm = get_node_or_null("/root/RoutineManager")
	if rm:
		rm.routine_step_changed.connect(_on_routine_step_changed)
		# Initialize the objective label with the current step
		if objective_label:
			objective_label.text = rm.get_current_objective()
		print("[HUD] Connected to RoutineManager.")
	else:
		# Retry next frame — RoutineManager might not be ready yet
		call_deferred("_connect_routine_manager")


## Called when the Night 1 bedtime routine advances to a new step.
## Updates the objective label text on the HUD.
func _on_routine_step_changed(step: int, objective_text: String) -> void:
	if not objective_label:
		return
	
	var changed := objective_text != objective_label.text and objective_label.text != ""
	objective_label.text = objective_text
	if changed and objective_text != "":
		_announce_objective()
	print("[HUD] Routine step updated: Step ", step, " — ", objective_text)


## A new objective: the line brightens and settles, "Notebook updated"
## shows under it for a moment, and a pencil scratches (so it isn't missed).
const OBJECTIVE_SOUND := "res://assets/audio/notebook_writing.ogg"
var _objective_note: Label = null
var _objective_tween: Tween = null


func _announce_objective() -> void:
	if not _objective_note:
		_objective_note = Label.new()
		_objective_note.name = "ObjectiveNote"
		_objective_note.text = "Notebook updated"
		_objective_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_objective_note.add_theme_font_size_override("font_size", 13)
		_objective_note.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
		_objective_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_objective_note.add_theme_constant_override("outline_size", 4)
		_objective_note.anchor_left = 0.5
		_objective_note.anchor_right = 0.5
		_objective_note.offset_left = -200.0
		_objective_note.offset_right = 200.0
		_objective_note.offset_top = objective_label.offset_bottom + 2.0
		_objective_note.offset_bottom = objective_label.offset_bottom + 22.0
		_objective_note.modulate.a = 0.0
		_objective_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_objective_note)
	if _objective_tween and _objective_tween.is_valid():
		_objective_tween.kill()
	objective_label.modulate = Color(1.6, 1.5, 1.2, 1.0)
	_objective_tween = create_tween().set_parallel()
	_objective_tween.tween_property(objective_label, "modulate", Color.WHITE, 1.4).set_ease(Tween.EASE_OUT)
	_objective_tween.tween_property(_objective_note, "modulate:a", 1.0, 0.3)
	_objective_tween.chain().tween_interval(2.2)
	_objective_tween.chain().tween_property(_objective_note, "modulate:a", 0.0, 0.8)
	if ResourceLoader.exists(OBJECTIVE_SOUND):
		var sound := AudioStreamPlayer.new()
		sound.bus = &"SFX"
		sound.stream = load(OBJECTIVE_SOUND)
		sound.volume_db = -12.0
		add_child(sound)
		sound.play()
		sound.finished.connect(sound.queue_free)


func _find_and_connect_flashlight() -> void:
	# Try to find the player and flashlight
	var player = get_tree().get_first_node_in_group("player")
	
	if player:
		_flashlight = player.find_child("Flashlight", true, false)
		if _flashlight and _flashlight.has_signal("battery_changed"):
			_flashlight.battery_changed.connect(_on_battery_changed)
			# Initialize the battery display
			if _flashlight.has_method("get_battery_percent"):
				_on_battery_changed(_flashlight.battery_level)
		else:
			# Retry next frame
			call_deferred("_find_and_connect_flashlight")
	else:
		# Retry next frame if player not found yet
		call_deferred("_find_and_connect_flashlight")


func _find_and_connect_stamina() -> void:
	# Try to find the player
	var player = get_tree().get_first_node_in_group("player")
	
	if player and player.has_signal("stamina_changed"):
		player.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(100.0)  # Initialize at full
	else:
		# Retry next frame
		call_deferred("_find_and_connect_stamina")


func _on_stamina_changed(percent: float) -> void:
	if not stamina_bar or not stamina_label:
		return
	
	if _gauges:
		_gauges.stamina = percent
	stamina_bar.value = percent
	stamina_label.text = "%d%%" % percent
	
	# Hide stamina bar when at 100%
	if percent >= 99.9:
		stamina_bar.modulate = Color(0.3, 0.8, 0.3, 0)
		stamina_label.modulate = Color(1, 1, 1, 0)
	else:
		# Show and color based on level
		stamina_label.modulate = Color(1, 1, 1, 0.9)
		if percent <= 25.0:
			stamina_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)  # Red - exhausted
		elif percent <= 50.0:
			stamina_bar.modulate = Color(1.0, 0.8, 0.2, 1.0)  # Yellow - warning
		else:
			stamina_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)  # Green - good


func _on_battery_changed(level: float) -> void:
	if not battery_bar or not battery_label:
		return
	
	# Calculate percentage
	var max_battery = _flashlight.max_battery if _flashlight else 100.0
	var percent = (level / max_battery) * 100.0
	if _gauges:
		_gauges.battery = percent
	
	# Update bar
	battery_bar.value = percent
	battery_label.text = "%d%%" % percent
	
	# Color the bar based on battery level
	if percent <= 15.0:
		# Red - critical
		battery_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)
		low_battery_warning.modulate = Color(1, 0.2, 0.2, 1)
	elif percent <= 30.0:
		# Yellow - warning
		battery_bar.modulate = Color(1.0, 0.8, 0.2, 1.0)
		low_battery_warning.modulate = Color(1, 0.2, 0.2, 0)
	else:
		# Green - good
		battery_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)
		low_battery_warning.modulate = Color(1, 0.2, 0.2, 0)


# Poll every frame to update the display
func _process(delta: float) -> void:
	# The clock readouts are only shown with F3: formatted only then.
	if debug_info_visible:
		var progress: float = 0.0
		var p_is_day: bool = true
		# Read from GameTime directly as the primary source (most reliable).
		# Fall back to EnvironmentController if GameTime isn't available.
		var gt = get_node_or_null("/root/GameTime")
		if gt:
			progress = gt.cycle_progress
			p_is_day = gt.is_day
		elif environment_controller:
			progress = environment_controller.cycle_progress
			p_is_day = environment_controller.is_day
		_update_display(progress, p_is_day)
	
	# Update low battery warning flicker
	_update_low_battery_warning(delta)
	_update_battery_visibility()
	
	# ─── ROOM DEBUG LABEL ──────────────────────────────────────────────
	# Update the room label every frame to show which room the player is in.
	# The label is created lazily on first use (like the purge bar).
	_update_room_label()


func _update_low_battery_warning(delta: float) -> void:
	if not low_battery_warning:
		return
	
	# Only flicker if the warning is visible (alpha > 0)
	if low_battery_warning.modulate.a > 0.0:
		_warning_flicker_timer -= delta
		if _warning_flicker_timer <= 0.0:
			_warning_flicker_timer = randf_range(0.1, 0.5)
			_warning_visible = not _warning_visible
			var alpha = 1.0 if _warning_visible else 0.3
			low_battery_warning.modulate = Color(1, 0.2, 0.2, alpha)


func _update_display(progress: float, p_is_day: bool) -> void:
	var phase_duration = 300.0  # 5 minutes per phase (half of 600s cycle)
	var phase_progress: float
	
	if p_is_day:
		phase_progress = progress / 0.5
	else:
		phase_progress = (progress - 0.5) / 0.5
	
	# Clamp phase_progress to valid range
	phase_progress = clampf(phase_progress, 0.0, 1.0)
	
	# Calculate time remaining in current phase
	var remaining = phase_duration * (1.0 - phase_progress)
	var total_seconds = int(remaining)
	var minutes = int(total_seconds / 60.0)
	var seconds = total_seconds % 60
	var time_remaining = "%02d:%02d" % [minutes, seconds]
	
	# Phase name and icon
	var phase_name = "☀️ DAY" if p_is_day else "🌙 NIGHT"
	var next_phase = "night" if p_is_day else "day"
	
	# Time label: show elapsed / remaining in current phase (real-time MM:SS)
	var elapsed = int(phase_duration * phase_progress)
	var e_minutes = int(elapsed / 60.0)
	var e_seconds = elapsed % 60
	time_label.text = "%02d:%02d / %s" % [e_minutes, e_seconds, time_remaining]
	
	# Clock label: show phase progress percentage + countdown to next phase
	var percent = int(phase_progress * 100)
	clock_label.text = "%s  %d%%  (%s until %s)" % [phase_name, percent, time_remaining, next_phase]
	
	# Phase bar: show full cycle progress (0-100%)
	if phase_bar:
		phase_bar.value = progress * 100.0
		if p_is_day:
			phase_bar.modulate = Color(1.0, 0.85, 0.4, 1)  # Warm gold for day
		else:
			phase_bar.modulate = Color(0.3, 0.3, 0.8, 1)  # Cool blue for night


## Called when GameTime emits time_changed — forces an immediate HUD refresh.
## This is the belt-and-suspenders guarantee that the clock updates instantly
## when time is unpaused by the phone drop event.
func _on_game_time_changed(_progress: float) -> void:
	# Re-read the latest values from GameTime and refresh the display
	var progress: float = 0.0
	var p_is_day: bool = true
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		progress = gt.cycle_progress
		p_is_day = gt.is_day
	_update_display(progress, p_is_day)


## Pulls the current state from GameTime and NightManager autoloads and
## updates every HUD label in a single atomic pass. Called once in _ready()
## to overwrite .tscn placeholder text before the scene becomes visible.
## GameTime starts paused (no signals emitted), so this manual sync is
## the only way to get correct values on the HUD at startup.
func _sync_all_displays() -> void:
	# ─── Night label ──────────────────────────────────────────────
	# Use RoutineManager's get_current_day_string() which correctly
	# maps night 0→"Day 1", night 1→"Day 1", night 2→"Day 2", etc.
	var nm = get_node_or_null("/root/NightManager")
	# (As a card that fades, see _show_day_card.)
	_update_night_label(nm.current_night if nm else 0)
	# Also sync fuel display immediately
	if nm:
		_on_generator_fuel_changed(nm.generator_fuel)

	# ─── Event label clear ─────────────────────────────────────────
	if event_label:
		event_label.text = ""
		event_label.modulate = Color(1, 1, 1, 0)

	# ─── Time display ──────────────────────────────────────────────
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		_update_display(gt.cycle_progress, gt.is_day)
		# ─── DEBUG: Log the exact time the HUD shows on screen ──────────
		print("[HorrorHUD] UI Clock: clock_label='%s' time_label='%s' | GameTime: progress=%.4f, is_day=%s)" % [
			clock_label.text if clock_label else "N/A",
			time_label.text if time_label else "N/A",
			gt.cycle_progress, gt.is_day
		])


func _on_night_started(night: int) -> void:
	_update_night_label(night)
	# Event messages removed per design direction


func _on_night_ended(night: int) -> void:
	# Event messages removed per design direction
	# Defer the display sync to the next frame so that NightManager's
	# end_current_night() has fully finished incrementing current_night
	# before RoutineManager reads it. Without this, get_current_day_string()
	# can return "Day 2" because current_night hasn't been updated yet.
	call_deferred("_sync_all_displays")


func _on_horror_event(event_name: String) -> void:
	# Event messages removed per design direction
	pass


## Called when NightManager emits first_chase_started (Night 1 narrative event).
## Unlocks the player's sprint ability.
func _on_first_chase_started() -> void:
	# Find the player and unlock sprint
	var player = get_tree().get_first_node_in_group("player")
	if player and "sprint_unlocked" in player:
		player.sprint_unlocked = true
		print("[HUD] Sprint unlocked for the player!")


## Updates the generator fuel bar on the HUD.
## Colors the bar green/yellow when fuel is healthy, red when below 25%.
func _on_generator_fuel_changed(current_fuel: float) -> void:
	if not fuel_bar or not fuel_label:
		return
	
	fuel_bar.value = current_fuel
	fuel_label.text = "Fuel"
	
	# Color the bar based on fuel level
	if current_fuel <= 25.0:
		# Red - critical
		fuel_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)
	elif current_fuel <= 50.0:
		# Yellow - warning
		fuel_bar.modulate = Color(1.0, 0.8, 0.2, 1.0)
	else:
		# Green - good
		fuel_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)


## Called when the generator turns on or off.
## Shows a blackout event message when the generator stops.
func _on_generator_state_changed(is_running: bool) -> void:
	if not is_running:
		# Gray out the fuel bar to indicate the generator is off
		if fuel_bar:
			fuel_bar.modulate = Color(0.4, 0.4, 0.4, 0.6)
		if fuel_label:
			fuel_label.text = "Fuel: off"
	else:
		# Restore fuel bar color and label (will be updated by next fuel_changed signal)
		if fuel_bar:
			fuel_bar.modulate = Color(0.3, 0.8, 0.3, 1.0)
		if fuel_label:
			fuel_label.text = "Fuel"


func _update_night_label(night: int) -> void:
	# Use RoutineManager's day mapping (Night 0→"Day 1", Night 1→"Day 1",
	# Night 2→"Day 2", etc.) for the HUD label. Fall back to raw night
	# number if RoutineManager is unavailable.
	var rm = get_node_or_null("/root/RoutineManager")
	var text: String = rm.get_current_day_string() if rm and rm.has_method("get_current_day_string") else "Night %d" % night
	# A new day or night (or the first time): the card.
	if text != night_label.text or _day_tween == null:
		night_label.text = text
		_show_day_card()


## "Day 2" / "Night 2": a card that fades in at the top left as the day
## or night begins, then goes (it doesn't need to sit there all day).
func _show_day_card() -> void:
	if _day_tween and _day_tween.is_valid():
		_day_tween.kill()
	GameFonts.use_title(night_label)
	night_label.modulate.a = 0.0
	_day_tween = create_tween()
	_day_tween.tween_property(night_label, "modulate:a", 1.0, 1.0)
	_day_tween.tween_interval(5.0)
	_day_tween.tween_property(night_label, "modulate:a", 0.0, 1.5)


## Shows an event message with a 3-second display time, then fades out.
## Messages are queued so each one gets its full display time.
func _show_event(text: String) -> void:
	# Event messages removed per design direction
	pass


func _display_next_message() -> void:
	# Event messages removed per design direction
	_message_busy = false


func _on_event_timer_timeout() -> void:
	# Event messages removed per design direction
	pass


# ─── PURGE PROGRESS BAR ────────────────────────────────────────────────
# Public API for the TotemAnchor to display a timed hold-to-purge progress
# meter on the HUD. The bar is created programmatically on first use.

## Shows the purge progress bar overlay at the center of the screen.
## Called by TotemAnchor.interact() when the player begins purging.
func show_purge_progress() -> void:
	_purge_bar_visible = true


## The purge's progress (0..1), shown on the crosshair's ring like every
## other hold.
func update_purge_progress(progress_ratio: float) -> void:
	if not _purge_bar_visible:
		return
	var ring := get_tree().get_first_node_in_group("crosshair")
	if ring:
		ring.set_hold(progress_ratio)


func hide_purge_progress() -> void:
	_purge_bar_visible = false


## Updates the room debug label every frame.
## Creates the label lazily on first call (no scene changes needed).
## Shows which room the player is currently in by calling
## player_controller.gd's get_player_room() method.
func _update_room_label() -> void:
	# Lazily create the room label on first use
	if not _room_label:
		_room_label = Label.new()
		_room_label.name = "RoomLabel"
		_room_label.theme = Theme.new()
		_room_label.theme.default_font_size = 14
		_room_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.7))  # Light blue, semi-transparent
		_room_label.add_theme_constant_override("outline_size", 1)
		_room_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		_room_label.position = Vector2(20, 230)  # Below the stamina bar
		_room_label.z_index = 10
		add_child(_room_label)
		_room_label_visible = true
		_room_label.visible = debug_info_visible
	if not _room_label.visible:
		return
	
	# Find the player and get the current room
	var player = get_tree().get_first_node_in_group("player")
	
	if player and player.has_method("get_player_room"):
		var room_name = player.get_player_room()
		_room_label.text = "📍 Room: %s" % room_name
	else:
		_room_label.text = "📍 Room: N/A"


## Public API: Shows a temporary message on the HUD event label.
## Called by TotemAnchor and other interactables to display feedback text
## (e.g., "The totem is protected by the Entity's presence...").
## The message is displayed for 3.0 seconds, then fades out automatically
## via the existing _show_event() message queue system.
## Feedback lines ("Inventory is full!", "I should lock the door first.",
## "I am too tired to read this right now..."). The event label that showed
## them was removed, which left them going nowhere: refused actions gave no
## reason. They're shown as the player's thought on screen (Monologue.say).
## Off: silent again.
@export var show_feedback_as_thoughts: bool = true


## `subject`: what it's about (the thought floats over it while on screen).
func show_message(msg: String, subject: Node3D = null) -> void:
	if not show_feedback_as_thoughts:
		return
	var monologue := get_node_or_null("/root/Monologue")
	if monologue and monologue.has_method("say"):
		monologue.say(msg, 3.5, subject)


## ─── ITEM PICKUP FEEDBACK ──────────────────────────────────────────────
## Called whenever an item is added to the player's inventory (Inventory
## autoload emits item_added). Pops up "Added [Item Name] to inventory"
## at the bottom-center of the HUD.
func _on_item_added(item) -> void:
	if not is_instance_valid(_pickup_label):
		return
	if not item:
		return
	var item_name: String = item.item_name if "item_name" in item else "Item"
	# A short, quiet line (not a menu's "Added X to inventory").
	show_pickup_message("+ %s" % item_name)


## Displays a pickup-feedback message: fades in over 0.3s, holds for 2.5s,
## then fades out over 0.5s. Any previous in-progress pickup tween is killed
## so rapid successive pickups don't cause competing fade animations.
func show_pickup_message(msg: String) -> void:
	if not is_instance_valid(_pickup_label):
		return
	
	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	
	_pickup_label.text = msg
	_pickup_label.modulate.a = 0.0
	
	# Fade in quickly
	_pickup_tween = create_tween()
	_pickup_tween.tween_property(_pickup_label, "modulate:a", 1.0, 0.3)
	# Hold for 2.5 seconds
	_pickup_tween.tween_interval(2.5)
	# Fade back out over 0.5 seconds
	_pickup_tween.tween_property(_pickup_label, "modulate:a", 0.0, 0.5)


var _hint_tween: Tween = null

## Tracks whether any hint has been shown yet. Used to distinguish a
## genuine visible hint from the HintLabel's default alpha=1.0 in the scene.
var _hint_has_been_shown: bool = false

# ─── ONBOARDING HINT SYSTEM ─────────────────────────────────────────────
# Displays a short contextual hint that fades in after a small delay.
# Designed for Day 1 onboarding triggers (e.g., HintArea near the cabin).

## Helper: formatted timestamp in seconds for debug logging.
func _timestamp() -> String:
	var ms := Time.get_ticks_msec()
	var sec := ms / 1000
	var frac := ms % 1000
	return "%d.%03d" % [sec, frac]


## Shows a hint with the given text. The hint stays invisible for `delay`
## seconds, then fades in over 0.5s. Call hide_hint() to dismiss it.
##
## If a previous hint is still fading in (timer running), the text is
## replaced in-place without restarting the timer, preventing the "flash"
## caused by competing fade animations.
##
## If a hint is already fully visible, it IGNORES the new request so the
## current hint stays on screen until dismissed by mark_learned(), unless
## `force` is set (then the new hint replaces it). Returns whether the hint
## is (or will be) on screen.
func show_hint(text: String, delay: float = 0.5, force: bool = false) -> bool:
	if not hint_label:
		return false
	text = GameKeys.keys_in(text)   # (as the player's keys)
	
	# If a hint is already visible AND we've already shown one before, ignore.
	# (The first call must pass through — HintLabel starts at alpha=1.0 in the
	# scene file, so we'd skip every tutorial without this guard.)
	if _hint_has_been_shown and hint_label.modulate.a > 0.0:
		if force:
			print("[HorrorHUD] T+%s show_hint FORCED over '%s' → '%s'" % [_timestamp(), hint_label.text, text])
			hint_label.text = text
			return true
		print("[HorrorHUD] T+%s show_hint BLOCKED — hint already visible: '%s'" % [_timestamp(), hint_label.text])
		return false
	
	# If hint timer is still running (fade-in hasn't started yet),
	# just update the text — keep the existing timer/tween.
	if hint_timer and not hint_timer.is_stopped():
		print("[HorrorHUD] T+%s show_hint REPLACED timer text → '%s'" % [_timestamp(), text])
		hint_label.text = text
		return true
	
	# Kill any existing tween so we don't get competing fade animations
	if is_instance_valid(_hint_tween):
		_hint_tween.kill()
	
	_hint_has_been_shown = true
	hint_label.text = text
	hint_label.modulate = Color(0.9, 0.9, 0.8, 0.0)
	
	print("[HorrorHUD] T+%s show_hint SET → '%s' (fade-in in %.1fs)" % [_timestamp(), text, delay])
	
	if hint_timer:
		hint_timer.stop()
		hint_timer.wait_time = delay
		# Disconnect previous connection before adding a new one to prevent
		# connection pile-up that causes competing fade tweens.
		if hint_timer.timeout.is_connected(_on_hint_timer_timeout):
			hint_timer.timeout.disconnect(_on_hint_timer_timeout)
		hint_timer.timeout.connect(_on_hint_timer_timeout)
		hint_timer.start()
	return true


## The hint on screen (or about to fade in), "" for none.
func current_hint() -> String:
	if not hint_label:
		return ""
	if hint_label.modulate.a > 0.0 or (hint_timer and not hint_timer.is_stopped()):
		return hint_label.text
	return ""


## Fades the hint label from alpha 1 to 0 over 0.5 seconds.
func hide_hint() -> void:
	if not hint_label:
		return
	
	print("[HorrorHUD] T+%s hide_hint — stopped: '%s'" % [_timestamp(), hint_label.text])
	
	# CRITICAL FIX: Stop the hint_timer to prevent _on_hint_timer_timeout()
	# from re-tweening the hint back to alpha 1.0. Without this, when the
	# hint's 0.5s fade-in delay timer fires AFTER hide_hint() was called
	# (e.g., player opens the notebook during the delay), the timeout
	# kills the fade-out tween and re-shows the hint permanently.
	hint_timer.stop()
	hint_label.modulate.a = 0.0
	
	if is_instance_valid(_hint_tween):
		_hint_tween.kill()
	
	_hint_tween = create_tween()
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 0.5)


## Called once the hint delay timer expires. Fades the hint in naturally.
func _on_hint_timer_timeout() -> void:
	if not hint_label:
		return
	
	if is_instance_valid(_hint_tween):
		_hint_tween.kill()
	
	_hint_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_property(hint_label, "modulate:a", 1.0, 0.5)


## Shows the escape-ending screen overlay, hiding every other HUD element.
## Called by EndgameManager for ESCAPE_GOOD (good_ending = true) and
## ESCAPE_MEDIOCRE (good_ending = false). Toggles the correct label and
## leaves the MainMenuButton to return to the main menu.
func show_ending_screen(good_ending: bool) -> void:
	# Hide all other HUD visuals (Labels, ProgressBars, ColorRects, CanvasLayers).
	for child in get_children():
		if child == ending_screen:
			continue
		if child is CanvasItem or child is CanvasLayer:
			child.visible = false
	
	# Show the panel and the correct label.
	if ending_screen:
		ending_screen.visible = true
	if mediocre_ending_label:
		mediocre_ending_label.visible = not good_ending
	if good_ending_label:
		good_ending_label.visible = good_ending
	
	print("[HorrorHUD] Ending screen shown (good_ending=%s)." % good_ending)


## MainMenuButton handler: unpause, reset EndgameManager, return to menu.
func _on_main_menu_pressed() -> void:
	print("[HorrorHUD] Main Menu pressed. Returning to main menu.")
	var em := get_node_or_null("/root/EndgameManager")
	if em and em.has_method("reset"):
		em.reset()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")