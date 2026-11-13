extends Node

## EndgameManager — Global singleton that tracks the game's ending conditions
## and orchestrates the transition from gameplay to the ending sequences.
##
## Three possible endings:
##   DEATH           — The player was caught by the Entity. (BAD)
##   ESCAPE_MEDIOCRE — The player repaired the van and escaped, but did NOT
##                     destroy the TotemAnchor. The Entity is still out there.
##   ESCAPE_GOOD     — The player repaired the van AND destroyed the TotemAnchor
##                     before escaping. The Entity is banished.
##
## INTEGRATION:
##   - JumpscareManager calls trigger_death_ending() → DEATH
##   - EscapeVan calls start_ending_sequence(totem_destroyed) → ESCAPE_GOOD or ESCAPE_MEDIOCRE
##
## USAGE:
##   var em = get_node("/root/EndgameManager")
##   em.trigger_death_ending()

signal ending_triggered(ending: Ending)
signal ending_sequence_started(ending: Ending)
signal ending_sequence_completed(ending: Ending)

## The three possible endings the player can achieve.
enum Ending {
	NONE = -1,       # No ending triggered yet (default state)
	DEATH,           # Caught by the Entity (BAD)
	ESCAPE_MEDIOCRE, # Repaired the van and escaped, but did NOT destroy the Totem
	ESCAPE_GOOD,     # Repaired the van AND destroyed the Totem before escaping
}

## Human-readable names for each ending (used for debug logging and UI).
const ENDING_NAMES: Dictionary = {
	Ending.DEATH: "Death",
	Ending.ESCAPE_MEDIOCRE: "Escape (Mediocre)",
	Ending.ESCAPE_GOOD: "Escape (Good)",
}

## The ending that was triggered (NONE until one fires).
## Default to NONE (enum value 0) instead of -1 to avoid enum cast warning.
var current_ending: Ending = Ending.NONE

## Whether an ending has been triggered (prevents double-triggers).
var is_ending_active: bool = false

## Whether the ending sequence is currently playing (cinematic, fade, etc.).
var is_sequence_playing: bool = false

## How many times the death cutscene has played this session: the first
## plays in full, later ones short (EndgameCinematics.play_death).
var death_cutscenes_seen: int = 0

## The Master volume before the ending faded it out, put back by reset()
## (otherwise the next game is silent). NAN while nothing is faded.
var _master_volume_before_fade: float = NAN
var _audio_fade_tween: Tween = null


func _ready() -> void:
	print("[EndgameManager] Initialized. Waiting for ending conditions.")


## ─── ENDING TRIGGERS ──────────────────────────────────────────────────

## Public API: Called by JumpscareManager when the player is caught by the Entity.
## Triggers the DEATH ending immediately.
func trigger_death_ending() -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate DEATH trigger.")
		return
	_trigger_ending(Ending.DEATH)


## Public API: Called by EscapeVan when the player escapes in the repaired van.
## Triggers ESCAPE_GOOD (if totem was destroyed) or ESCAPE_MEDIOCRE (if not).
func start_ending_sequence(totem_destroyed: bool) -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate escape trigger.")
		return
	
	if totem_destroyed:
		print("[EndgameManager] Player escaped with totem destroyed! GOOD ending.")
		_trigger_ending(Ending.ESCAPE_GOOD)
	else:
		print("[EndgameManager] Player escaped without destroying the totem. MEDIOCRE ending.")
		_trigger_ending(Ending.ESCAPE_MEDIOCRE)


## ─── INTERNAL ─────────────────────────────────────────────────────────

## Internal trigger that fires the ending sequence.
## Guards against double-triggers and logs the event.
func _trigger_ending(ending: Ending) -> void:
	if is_ending_active:
		print("[EndgameManager] Ending already active. Ignoring duplicate trigger: ", ENDING_NAMES.get(ending, "UNKNOWN"))
		return
	
	is_ending_active = true
	current_ending = ending
	print("[EndgameManager] ═══════════════════════════════════════════")
	print("[EndgameManager] 🏁 ENDING TRIGGERED: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	print("[EndgameManager] ═══════════════════════════════════════════")
	
	ending_triggered.emit(ending)
	
	# Begin the ending sequence (cinematic, fade, etc.)
	_play_ending_sequence(ending)


## Path to the ending screen scene.
const ENDING_SCREEN_PATH: String = "res://scenes/ui/ending_screen.tscn"

## Duration of the fade-to-black transition before the ending screen appears.
const FADE_DURATION: float = 1.5

## Reference to the instantiated ending screen (if any).
var _ending_screen_instance: Node = null

## The fade-to-black CanvasLayer created by _fade_screen_to_black().
## Stored so it can be freed once the ending screen (layer 129) is shown,
## otherwise this opaque overlay (layer 128) would cover the UI forever.
var _fade_canvas_layer: CanvasLayer = null


## Plays the ending sequence for the given ending type.
##
## Sequence:
##   1. Disable the Entity visually/mechanically (escape endings only).
##   2. Fade all audio buses to silence.
##   3. Fade the screen to black via a dynamic ColorRect.
##   4. Wait for the fade to complete.
##   5. Instantiate the EndingScreen overlay.
##   6. Pause the game and free the cursor.
func _play_ending_sequence(ending: Ending) -> void:
	if is_sequence_playing:
		return
	
	is_sequence_playing = true
	ending_sequence_started.emit(ending)
	
	print("[EndgameManager] Playing ending sequence for: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	
	# ─── ENDING-SPECIFIC LOGIC ───────────────────────────────────────
	match ending:
		Ending.DEATH:
			print("[EndgameManager] DEATH: The Entity caught the player. (BAD)")
		
		Ending.ESCAPE_MEDIOCRE:
			print("[EndgameManager] ESCAPE_MEDIOCRE: Player escaped in the van, but the Entity is still out there.")
		
		Ending.ESCAPE_GOOD:
			print("[EndgameManager] ESCAPE_GOOD: Player escaped in the van AND destroyed the Totem! The Entity is banished!")
	
	# ─── 1. DISABLE ENTITY FOR ESCAPE ENDINGS ───────────────────────
	# The Entity shouldn't linger in the background while the player reads
	# the ending screen. For death endings, the JumpscareManager already
	# handles this; for escape endings we do it here.
	if ending != Ending.DEATH:
		_disable_entity_for_ending()
	
	# ─── 2. CINEMATIC PLAYBACK ──────────────────────────────────────
	# Lock the player's movement/input, hide the HUD, play the 3D cinematic
	# cutscene, then restore input before fading to black and showing UI.
	await _play_cinematic_and_lock_player(ending)
	
	# ─── 3. FADE AUDIO TO SILENCE ───────────────────────────────────
	_fade_audio_to_silence()
	
	# ─── 4. FADE SCREEN TO BLACK ────────────────────────────────────
	# Create a full-screen ColorRect, fade it in, then show the ending UI.
	await _fade_screen_to_black()
	
	# ─── 4.5. REMOVE THE FADE OVERLAY ─────────────────────────────
	# The fade-to-black CanvasLayer (layer 128) must be REMOVED
	# now that the fade is complete. Previously it was left in the tree
	# permanently, rendering an opaque black rect ABOVE the ending screen
	# (which lives in the default canvas, layer 0) — the Mediocre/Good
	# screens appeared after the fade but were invisible behind the black.
	if _fade_canvas_layer and is_instance_valid(_fade_canvas_layer):
		_fade_canvas_layer.queue_free()
		_fade_canvas_layer = null
	
	# The cutscene's own black screen goes too, now that ours covers it.
	var cinematics = get_tree().get_first_node_in_group("cinematics")
	if cinematics and cinematics.has_method("clear_overlay"):
		cinematics.clear_overlay()
	
	# ─── 4. INSTANTIATE ENDING SCREEN ───────────────────────────────
	# One EndingScreen for every ending (the HUD's old built-in panel is
	# no longer used).
	var ending_scene = load(ENDING_SCREEN_PATH)
	if not ending_scene:
		print("[EndgameManager] ERROR: Could not load ending screen scene: ", ENDING_SCREEN_PATH)
		_complete_ending_sequence(ending)
		return
	
	_ending_screen_instance = ending_scene.instantiate()
	if not _ending_screen_instance:
		print("[EndgameManager] ERROR: Could not instantiate ending screen.")
		_complete_ending_sequence(ending)
		return
	
	# ─── PARENT UNDER HIGH-LAYER CANVAS (129) ──────────────
	# The ending screen is a plain Control node (default canvas layer 0).
	# Adding it directly to current_scene would render BELOW the game
	# HUD (and below the fading overlay). Parent it under its own
	# CanvasLayer at layer 129 — JUST above the now-freed fade overlay
	# (128) and the game HUD — guaranteeing the text screen renders on
	# top of everything.
	# NOTE: ending_screen.tscn already sets process_mode = PROCESS_MODE_ALWAYS,
	# so it stays interactive while get_tree().paused = true (Task 6 dir).
	var ending_canvas := CanvasLayer.new()
	ending_canvas.name = "_EndgameUILayer"
	ending_canvas.layer = 129
	get_tree().current_scene.add_child(ending_canvas)
	ending_canvas.add_child(_ending_screen_instance)
	
	# Configure the ending screen with the correct title/subtitle
	if _ending_screen_instance.has_method("setup_ending"):
		_ending_screen_instance.setup_ending(ending)
	
	# ─── 5. PAUSE & FREE CURSOR ─────────────────────────────────────
	# Pause the game so the player can't move while the ending screen is up.
	# The EndingScreen has process_mode = PROCESS_MODE_ALWAYS so it still
	# processes input and animations while paused.
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	print("[EndgameManager] Game paused. Ending screen displayed.")
	
	# The ending screen handles Retry/MainMenu itself via change_scene_to_file,
	# so we don't need to wait here. The sequence is effectively complete once
	# the screen is shown.
	_complete_ending_sequence(ending)


# ─── CINEMATIC TRANSITION HELPERS ──────────────────────────────────────

## Disables the Entity for escape endings so it doesn't linger in the
## background behind the EndingScreen overlay.
func _disable_entity_for_ending() -> void:
	var entity = get_tree().get_first_node_in_group("entity")
	if not entity or not is_instance_valid(entity):
		print("[EndgameManager] No Entity found to disable for ending.")
		return
	
	print("[EndgameManager] Disabling Entity for escape ending...")
	
	# Out of the game for good (the night can't wake it up again), but still
	# processing, so the ending cutscene can move and animate it.
	entity.set_meta("debug_disabled", true)
	if entity.has_method("deactivate"):
		entity.deactivate()
	else:
		entity.hide()
		entity.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Disable collision
	var collision_shape = entity.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Disable catch area
	var catch_area = entity.get_node_or_null("CatchArea")
	if catch_area:
		catch_area.monitoring = false
	
	print("[EndgameManager] Entity disabled for ending sequence.")


## Locks the player's movement and input, hides the HUD, plays the 3D cinematic
## cutscene via the Cinematics node, then restores player control.
##
## The function finds the Cinematics node via the "cinematics" group,
## the player via the "player" group, and the HUD via the "hud" group.
## If any of these are missing, the function gracefully degrades
## (no cinematic, no lock — just returns immediately).
func _play_cinematic_and_lock_player(ending: Ending) -> void:
	var cinematics = get_tree().get_first_node_in_group("cinematics")
	if not cinematics or not is_instance_valid(cinematics):
		print("[EndgameManager] No Cinematics node found in 'cinematics' group — skipping cinematic.")
		return
	if not cinematics.has_method("play_ending_cinematic"):
		print("[EndgameManager] Cinematics node lacks play_ending_cinematic() — skipping cinematic.")
		return
	
	# ─── LOCK PLAYER ──────────────────────────────────────────────
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		print("[EndgameManager] Locking player input for cinematic...")
		player.process_mode = Node.PROCESS_MODE_DISABLED
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		print("[EndgameManager] WARNING: No player found in 'player' group.")
	
	# ─── HIDE HUD ─────────────────────────────────────────────────
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and is_instance_valid(hud):
		print("[EndgameManager] Hiding HUD for cinematic...")
		hud.visible = false
	
	# ─── PLAY CINEMATIC & AWAIT ───────────────────────────────────
	# The cutscene is a coroutine that always finishes (it no longer waits
	# on an AnimationPlayer that may not have the animation, which froze the
	# game here).
	print("[EndgameManager] Starting cinematic for ending: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	await cinematics.play_ending_cinematic(ending)
	print("[EndgameManager] Cinematic finished.")
	
	# The player stays locked and the HUD hidden: the ending screen follows.
	if player and is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_INHERIT


## Fades all audio buses to silence for cinematic impact.
## Targets the Master bus directly, tweening its volume from current level
## to -80 dB over FADE_DURATION seconds.
func _fade_audio_to_silence() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		print("[EndgameManager] WARNING: Master audio bus not found — skipping audio fade.")
		return
	
	# Capture current volume as the starting point for the tween.
	# We use a dummy Node to drive the tween since AudioServer isn't a Node.
	var current_vol = AudioServer.get_bus_volume_db(master_idx)
	if is_nan(_master_volume_before_fade):
		_master_volume_before_fade = current_vol
	var tween_driver = Node.new()
	tween_driver.name = "_EndgameAudioFadeDriver"
	add_child(tween_driver)
	
	# Store the master bus index on the driver so the tween callback can find it
	tween_driver.set_meta("_master_bus_idx", master_idx)
	
	var tween = tween_driver.create_tween()
	_audio_fade_tween = tween
	tween.tween_method(_set_master_volume.bind(master_idx), current_vol, -80.0, FADE_DURATION)
	tween.tween_callback(tween_driver.queue_free)
	
	print("[EndgameManager] Audio fade to silence started (%.1f dB → -80 dB over %.1fs)." % [current_vol, FADE_DURATION])


## Tween callback: sets the Master bus volume to the interpolated value.
func _set_master_volume(volume_db: float, bus_idx: int) -> void:
	AudioServer.set_bus_volume_db(bus_idx, volume_db)


## Creates a full-screen black ColorRect, fades it from transparent to opaque
## over FADE_DURATION seconds, and waits for the fade to complete.
## Returns when the fade-in (to black) is finished.
func _fade_screen_to_black() -> void:
	# Create a full-screen black overlay as a CanvasLayer child so it
	# renders above the 3D world and the HUD.
	# Store the reference on _fade_canvas_layer so the caller can
	# free it after the fade completes.
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "_EndgameFadeCanvas"
	canvas_layer.layer = 128  # High layer index to be on top of everything
	get_tree().current_scene.add_child(canvas_layer)
	_fade_canvas_layer = canvas_layer
	
	var fade_rect = ColorRect.new()
	fade_rect.name = "FadeRect"
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)  # Start transparent
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(fade_rect)
	
	# Tween the alpha from 0 to 1 (transparent → opaque black)
	var tween = canvas_layer.create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, FADE_DURATION)
	
	# Wait for the fade to finish
	await tween.finished
	
	print("[EndgameManager] Fade to black complete.")


## Completes the ending sequence and cleans up.
func _complete_ending_sequence(ending: Ending) -> void:
	print("[EndgameManager] Ending sequence completed for: ", ENDING_NAMES.get(ending, "UNKNOWN"))
	is_sequence_playing = false
	ending_sequence_completed.emit(ending)


## Returns a human-readable name for the given ending enum value.
func get_ending_name(ending: Ending) -> String:
	return ENDING_NAMES.get(ending, "Unknown")


## Returns true if the given ending has been triggered.
func has_ending_triggered(ending: Ending) -> bool:
	return is_ending_active and current_ending == ending


## Resets the EndgameManager to its initial state.
## Called when the game is restarted from the main menu.
func reset() -> void:
	current_ending = Ending.NONE
	is_ending_active = false
	is_sequence_playing = false
	_restore_master_volume()
	print("[EndgameManager] Reset to initial state.")


## Puts the Master volume back to where it was before the ending faded it.
func _restore_master_volume() -> void:
	if is_nan(_master_volume_before_fade):
		return
	# The fade may still be running.
	if _audio_fade_tween and _audio_fade_tween.is_valid():
		_audio_fade_tween.kill()
	_audio_fade_tween = null
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, _master_volume_before_fade)
	_master_volume_before_fade = NAN
