extends StaticBody3D

## HasselmusNest - An interactable hazel mouse nest.
##
## The player presses E to document the nest (handled by InteractionManager
## via PhysicalGrab's quick-tap mechanism).
## Each nest can only be documented once. When all 3 nests are
## documented, the routine advances to Step 1 ("Upload nest data on
## the computer") and the eco-survey data becomes available for
## correlation at the FIELD_LOG.EXE terminal.
##
## ─── DAY 2 INTERACTION LOCKS ────────────────────────────────────────────
## Each nest requires a specific survival mechanic to be USED before the
## player can document it. This turns the survival mechanics (Overcharge,
## Stealth/Crouching, Stillness) into diegetic puzzles.
##
##   lock_type = "overcharge": Requires is_overcharged == true for
##                              lock_duration seconds (1.5s default).
##   lock_type = "stealth":    Requires player crouching. The flashlight
##                              requirement has been REMOVED. The clue
##                              prompt appears out to proximity_radius (10m).
##                              If the player performs any non-crouch
##                              movement within stealth_fail_radius (5m),
##                              the stealth check FAILS and the interaction
##                              locks until the player leaves and re-enters.
##   lock_type = "stillness":  Requires player velocity near ZERO for
##                              lock_duration seconds (5.0s default).
##                              While the stillness timer accumulates, an
##                              AudioStreamPlayer3D plays the Entity whisper
##                              track, lerping from inaudible (-80 dB) up to
##                              a quiet peak as the timer completes. Breaking
##                              stillness fades the audio out immediately.
##   lock_type = "none":       Unlocked always (no mechanic required).
##
## While the lock is NOT satisfied, get_interact_text() returns a dimmed
## contextual clue (e.g. "Nest Dormant - Requires Provocation"). Once the
## condition is met, the prompt swaps to the standard "Document Nest".
##
## ─── TUTORIAL TRIGGERS ─────────────────────────────────────────────────
## When the player first enters the nest's proximity radius, the nest calls
## TutorialManager.trigger(tutorial_id) to display a Just-in-Time hint
## teaching the relevant mechanic (overcharge/crouch/stillness).

signal nest_documented(nest_id: String)

## Unique string ID for this nest (e.g., "nest_01", "nest_02", "nest_03")
@export var nest_id: String = "nest_01"

## Display name for this nest
@export var nest_name: String = "Hasselmus Nest"

## Notebook label used to look up lore in NotebookUI.NEST_LORE.
## Must match one of: "Nest Alpha", "Nest Beta", "Nest Gamma"
@export var nest_label: String = "Nest Alpha"

## ─── INTERACTION LOCK CONFIG ──────────────────────────────────────────
## Which mechanic unlocks this nest: "none", "overcharge", "stealth", "stillness".
@export var lock_type: String = "none"

## For timed locks (overcharge/stillness): how many seconds the condition
## must be held before the nest unlocks. Stillness defaults to 5.0s.
@export var lock_duration: float = 5.0

## Clue text shown in the interaction prompt while the lock is not met.
## Set per-nest in the scene. Falls back to auto-generated text if empty.
@export var lock_clue_text: String = ""

## ─── TUTORIAL TRIGGER CONFIG ──────────────────────────────────────────
## mechanic_id to trigger via TutorialManager when the player first
## approaches this nest. Leave empty to disable.
@export var tutorial_id: String = ""

## Distance (meters) at which the proximity tutorial fires and the
## lock condition starts being evaluated.
@export var proximity_radius: float = 4.0

## ─── STEALTH (Nest Beta) CONFIG ───────────────────────────────────────
## Inner radius inside which ANY non-crouch movement fails the stealth
## check and permanently locks the interaction until the player leaves
## the outer proximity radius and re-enters.
@export var stealth_fail_radius: float = 5.0

## ─── STILLNESS (Nest Gamma) AUDIO CONFIG ──────────────────────────────
## Path to the Entity whisper audio track played while the stillness
## timer accumulates.
@export var whisper_audio_path: String = "res://assets/audio/Entity/Entity_Seen.ogg"

## Whisper volume floor (dB) — effectively inaudible before the timer starts.
@export var whisper_min_volume_db: float = -80.0

## Whisper peak volume (dB) — reached exactly as the stillness timer completes.
@export var whisper_peak_volume_db: float = -24.0

## Whether this nest has been documented
var is_documented: bool = false

## Whether the interaction lock condition is currently satisfied.
## When true, the prompt swaps to the standard "Document Nest" text.
var lock_satisfied: bool = false

## Accumulator for timed lock conditions (overcharge/stillness).
var lock_timer: float = 0.0

## Cached player reference (lazy init from the "player" group).
var _player: Node = null

## Whether the proximity tutorial has already been triggered for this nest.
var _tutorial_triggered: bool = false

## ─── STEALTH FAIL STATE (Nest Beta) ───────────────────────────────────
## Set true when the player performs any non-crouch movement inside
## stealth_fail_radius. The interaction stays locked until the player
## leaves the outer proximity radius (which resets this flag).
var _stealth_failed: bool = false

## ─── STILLNESS WHISPER AUDIO (Nest Gamma) ─────────────────────────────
## Lazily created AudioStreamPlayer3D for the whisper track.
var _whisper_player: AudioStreamPlayer3D = null

## Whether the whisper is currently being faded out (prevents re-triggering
## the fade tween every frame).
var _whisper_fading: bool = false


func _ready() -> void:
	# Add to groups for easy finding
	add_to_group("hasselmus_nests")
	add_to_group("NestNodes")
	add_to_group("interactable_nests")
	
	# Add to x-ray highlight group for objective tracking
	# Uses nest_label (e.g. "Nest Alpha") rather than nest_id (e.g. "nest_01")
	# because the routine_manager documents nests by label, not ID.
	match nest_label:
		"Nest Alpha":
			add_to_group("xray_nest_alpha")
		"Nest Beta":
			add_to_group("xray_nest_beta")
		"Nest Gamma":
			add_to_group("xray_nest_gamma")
	
	# Setup the whisper audio player for stillness nests (defensive —
	# only create/configure it when actually needed).
	if lock_type == "stillness":
		_setup_whisper_audio()
	
	# BUG 1 FIX: Interactable Layer 2 — the interaction ray only raycasts
	# against layer 2. Keep layer 1 (so the player/Entity still collide with
	# the stump) AND add layer 2 (1|2 = 3) so the E-prompt can reach the nest.
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)


func _process(delta: float) -> void:
	# ─── PROXIMITY EVALUATION ───────────────────────────────────────
	# If the nest is already documented, no lock/tutorial logic needed.
	if is_documented:
		return
	
	# Lazily find the player
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	
	# Distance check
	var dist := global_position.distance_to(_player.global_position)
	if dist > proximity_radius:
		# Player left the proximity — reset lock timer AND stealth failure
		# so they must re-satisfy the condition from scratch on re-entry.
		lock_timer = 0.0
		lock_satisfied = false
		if _stealth_failed:
			_stealth_failed = false
			print("[HasselmusNest] %s: Stealth failure reset — player left the nest's territory." % nest_label)
		return
	
	# ─── PROXIMITY TUTORIAL ─────────────────────────────────────────
	# First time the player enters the radius, fire the TutorialManager
	# trigger for this nest's mechanic. One-shot per nest.
	if not _tutorial_triggered and not tutorial_id.is_empty():
		_tutorial_triggered = true
		var tm := get_node_or_null("/root/TutorialManager")
		if tm and tm.has_method("trigger"):
			tm.trigger(tutorial_id)
			print("[HasselmusNest] Tutorial '%s' triggered for %s." % [tutorial_id, nest_label])
	
	# ─── LOCK CONDITION EVALUATION ──────────────────────────────────
	match lock_type:
		"overcharge":
			var flashlight := _get_flashlight()
			if flashlight and flashlight.is_overcharged:
				lock_timer += delta
				if lock_timer >= lock_duration:
					lock_satisfied = true
			else:
				lock_timer = 0.0
				lock_satisfied = false
		
		"stealth":
			# ─── STEALTH REWORK (Nest Beta) ─────────────────────────
			# The ONLY requirement is that the player is crouching.
			# The flashlight requirement has been removed entirely.
			# The clue/hint prompt fires out to proximity_radius (10m).
			var crouching := _is_player_crouching()
			var in_fail_zone: bool = dist <= stealth_fail_radius
			
			# If the player already failed the stealth check, the nest
			# stays locked until they leave the outer proximity radius.
			if _stealth_failed:
				lock_satisfied = false
				return
			
			# ANY non-crouch movement within the fail zone (5m) breaks
			# stealth permanently (until re-entry).
			if in_fail_zone and not crouching:
				_stealth_failed = true
				lock_satisfied = false
				_show_stealth_fail_message()
				return
			
			# Otherwise the nest unlocks purely by crouching.
			lock_satisfied = crouching
		
		"stillness":
			# Player velocity near zero for lock_duration seconds.
			# While the timer runs, play the whisper audio and lerp its
			# volume from inaudible up to a quiet peak.
			var speed: float = 0.0
			if _player is CharacterBody3D:
				speed = (_player as CharacterBody3D).velocity.length()
			if speed < 0.05:
				lock_timer += delta
				_start_whisper_if_needed()
				_update_whisper_volume()
				if lock_timer >= lock_duration:
					lock_satisfied = true
					_stop_whisper()
					print("[HasselmusNest] %s: Stillness complete (%.1fs). Nest unlocked." % [nest_label, lock_duration])
			else:
				# Player moved — break the stillness timer and fade the
				# whisper audio out immediately.
				if lock_timer > 0.0:
					lock_timer = 0.0
					_fade_out_whisper()
				lock_satisfied = false
		
		_:
			# "none" or unknown — always unlocked.
			lock_satisfied = true


## Returns true if the player is currently crouching.
func _is_player_crouching() -> bool:
	if _player == null:
		return false
	return _player.has_method("is_crouching") and _player.is_crouching()


## Shows the stealth-failure HUD message when the player gets caught
## moving inside the nest's fail radius.
func _show_stealth_fail_message() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message("The nest sensed my presence — I startled them.")
	print("[HasselmusNest] %s: STEALTH FAILED! Player moved within %.1fm while not crouching." % [nest_label, stealth_fail_radius])


## Returns the player's flashlight node (SpotLight3D with flashlight.gd).
func _get_flashlight() -> Node:
	if _player == null:
		return null
	return _player.get_node_or_null("CameraHolder/Camera3D/Flashlight")


## ─── WHISPER AUDIO (Nest Gamma) ───────────────────────────────────────

## Creates/loads the AudioStreamPlayer3D used for the stillness whisper.
## Uses defensive if/elif checks so a missing stream or node never crashes.
func _setup_whisper_audio() -> void:
	if _whisper_player:
		return
	_whisper_player = get_node_or_null("WhisperAudio")
	if not _whisper_player:
		_whisper_player = AudioStreamPlayer3D.new()
		_whisper_player.name = "WhisperAudio"
		add_child(_whisper_player)
	if not _whisper_player:
		push_warning("[HasselmusNest] Could not create whisper audio player for %s." % nest_label)
		return
	_whisper_player.bus = "SFX"
	_whisper_player.volume_db = whisper_min_volume_db
	_whisper_player.max_db = 0.0
	var stream := load(whisper_audio_path)
	if stream:
		_whisper_player.stream = stream
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		elif "loop_mode" in stream and stream.has_method("set"):
			stream.loop_mode = 0
	else:
		push_warning("[HasselmusNest] Could not load whisper audio from '%s' for %s." % [whisper_audio_path, nest_label])


## Starts the whisper loop if it isn't already playing.
func _start_whisper_if_needed() -> void:
	if not _whisper_player:
		return
	if not _whisper_player.stream:
		return
	if not _whisper_player.playing:
		_whisper_player.volume_db = whisper_min_volume_db
		_whisper_player.play()
		print("[HasselmusNest] %s: Whisper audio started." % nest_label)


## Lerps the whisper volume from inaudible to the quiet peak based on
## stillness progress (0.0 → 1.0 across lock_duration).
func _update_whisper_volume() -> void:
	if not _whisper_player or not _whisper_player.playing:
		return
	if lock_duration <= 0.0:
		return
	var progress: float = clampf(lock_timer / lock_duration, 0.0, 1.0)
	var vol := lerpf(whisper_min_volume_db, whisper_peak_volume_db, progress)
	_whisper_player.volume_db = vol


## Fades the whisper audio out over 0.3s, then stops it.
## Used when the player breaks the stillness timer.
func _fade_out_whisper() -> void:
	if not _whisper_player or not _whisper_player.playing:
		return
	if _whisper_fading:
		return
	_whisper_fading = true
	var fade := create_tween()
	fade.tween_property(_whisper_player, "volume_db", whisper_min_volume_db, 0.3)
	fade.tween_callback(_stop_whisper)
	fade.tween_callback(func(): _whisper_fading = false)
	print("[HasselmusNest] %s: Whisper audio fading out (stillness broken)." % nest_label)


## Stops the whisper audio and resets its volume to the inaudible floor.
## Also called when the stillness timer completes successfully.
func _stop_whisper() -> void:
	_whisper_fading = false
	if _whisper_player:
		_whisper_player.stop()
		_whisper_player.volume_db = whisper_min_volume_db


## Called when the player presses E on this nest.
## If the interaction lock is NOT satisfied, the nest refuses and the
## player sees a contextual prompt explaining what to do instead.
func interact() -> void:
	if is_documented:
		print("[HasselmusNest] Nest ", nest_id, " already documented!")
		return
	
	# ─── INTERACTION LOCK GATE ─────────────────────────────────────
	# Evaluate the lock condition fresh (in case _process hasn't run
	# this frame or the player just pressed E instantly).
	_refresh_lock_snapshot()
	if not lock_satisfied:
		print("[HasselmusNest] Lock NOT satisfied for ", nest_id, " (lock_type=%s). Interaction refused." % lock_type)
		# Show the clue text again so the player knows what to do.
		var clue := _get_clue_text()
		if not clue.is_empty():
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("show_message"):
				hud.show_message(clue)
		return
	
	# Mark as documented
	is_documented = true
	
	print("[HasselmusNest] Nest ", nest_id, " documented!")
	
	# Emit signal
	nest_documented.emit(nest_id)

	# The last nest: a storm breaks for the long walk back to the cabin.
	if nest_label == "Nest Gamma":
		var weather := get_node_or_null("/root/Weather")
		if weather and weather.has_method("start_storm"):
			weather.start_storm()
	
	# Notify RoutineManager
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("document_nest"):
		rm.document_nest(nest_label)
	
	# Add documentation entry to the NotebookUI
	_add_to_notebook()
	
	# Show a confirmation message
	_show_documented_message()


## Forces a one-shot evaluation of the lock condition.
## Used by interact() so the gate is airtight even if _process()
## hasn't run since the player entered the radius.
func _refresh_lock_snapshot() -> void:
	match lock_type:
		"overcharge":
			var flashlight := _get_flashlight()
			if flashlight and flashlight.is_overcharged:
				lock_timer = lock_duration  # Assume the condition was held
				lock_satisfied = true
			else:
				lock_timer = 0.0
				lock_satisfied = false
		"stealth":
			# STEALTH REWORK: crouching only, no flashlight requirement.
			# A previously-failed stealth check stays locked until re-entry.
			if _stealth_failed:
				lock_satisfied = false
				return
			lock_satisfied = _is_player_crouching()
		"stillness":
			var speed: float = 0.0
			if _player is CharacterBody3D:
				speed = (_player as CharacterBody3D).velocity.length()
			if _player and speed < 0.05 and lock_timer >= lock_duration:
				lock_satisfied = true
			else:
				lock_satisfied = false
		_:
			lock_satisfied = true


## Returns the contextual clue text for this nest's lock.
## Uses the exported lock_clue_text if set, otherwise auto-generates.
func _get_clue_text() -> String:
	if _stealth_failed:
		return "The nest is on guard — I startled them. Leave and approach in silence."
	if not lock_clue_text.is_empty():
		return lock_clue_text
	match lock_type:
		"overcharge":
			return "Nest Dormant - Requires Provocation"
		"stealth":
			return "The nest is watching. Stay low and approach quietly."
		"stillness":
			return "Nest Silent - Too Much Noise"
	return ""


func _add_to_notebook() -> void:
	# Find the NotebookUI via multiple methods for robust lookup
	var notebook: Node = null
	
	# Method 1: Try RoutineManager's cached reference (set in NotebookUI._connect_to_managers)
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and "_notebook_ui" in rm and rm._notebook_ui:
		notebook = rm._notebook_ui
	
	# Method 2: Try the dynamic NotebookUI via the player (NotebookLayer is instantiated at runtime)
	if not notebook:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			notebook = player.get_node_or_null("NotebookLayer/NotebookUI")
	
	# Method 3: Fall back to hardcoded paths
	if not notebook:
		notebook = get_node_or_null("/root/CottageHorror/Player/NotebookLayer/NotebookUI")
	if not notebook:
		notebook = get_node_or_null("/root/Main/Player/NotebookLayer/NotebookUI")
	
	if notebook and notebook.has_method("add_documentation"):
		notebook.add_documentation(nest_label)
		print("[HasselmusNest] Added '%s' to NotebookUI documentation." % nest_label)
	else:
		push_warning("[HasselmusNest] NotebookUI not found — documentation not recorded.")


func _show_documented_message() -> void:
	# Play notebook_writing.ogg sound effect
	_play_notebook_sfx()


## Plays the notebook_writing.ogg sound via a transient AudioStreamPlayer.
## The player is auto-freed when the sound finishes.
func _play_notebook_sfx() -> void:
	var stream := load("res://assets/audio/notebook_writing.ogg")
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	print("[HasselmusNest] Played notebook_writing.ogg")


func get_interact_text() -> String:
	if is_documented:
		return "[E] %s - Already Documented" % nest_label
	
	# ─── LOCK STATE PROMPT SWAP ────────────────────────────────────
	# While the lock is NOT satisfied, show the dimmed contextual clue.
	# Once satisfied, swap to the standard "Document Nest" prompt.
	if not lock_satisfied and lock_type != "none":
		return _get_clue_text()
	
	return "[E] Document %s" % nest_name