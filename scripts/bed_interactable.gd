extends Node3D # Or Area3D / StaticBody3D depending on your interaction setup

## Objective string updated on HUD when the player falls asleep on Night 1.
const INTRO_OBJECTIVE: String = "Investigate the car alarm outside."

## Objective string for Day 2 after the first sleep transition.
const DAY2_OBJECTIVE: String = "Document the nests."

@onready var _night_manager = get_node_or_null("/root/NightManager")
@onready var _game_time = get_node_or_null("/root/GameTime")

## Called when the player focuses on the bed and presses the interaction key (e.g., 'E')
## The player parameter is optional — if not provided, the bed finds the player
## via the "player" group. This matches the 0-argument convention used by
## physical_grab.gd's _fire_interact() which calls target.interact().
func interact(player: Node3D = null) -> void:
	if not _night_manager or not _game_time:
		_show_hud_message("Something feels wrong... (Managers missing)")
		return
	
	# Resolve player reference if not provided
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0] as Node3D
		if not player:
			_show_hud_message("No player found!")
			return

	var current_night: int = _night_manager.current_night
	
	# ─── CONDITION 1: DAY 1 ONBOARDING (current_night == 0) ──────────
	# On Day 1 (before Night 1 starts), the bed serves as the Phase 3
	# completion trigger. The player must first complete Phase 2 (power
	# restored + computer used) before they can sleep.
	# When they sleep, they transition to Day 2 (current_night becomes 1).
	# The screen fades to black, then Day 2 starts with the objective
	# "Document the nests."
	if current_night == 0:
		# Check with RoutineManager if Phase 2 is complete (power restored + computer used)
		var rm = get_node_or_null("/root/RoutineManager")
		var phase2_complete = rm and rm.phase2_complete if rm else false
		
		if phase2_complete:
			# Mark Phase 3 as complete
			if rm and rm.has_method("on_bed_interacted"):
				rm.on_bed_interacted()
			
			# ─── CINEMATIC FADE TO BLACK ──────────────────────────────
			# Disable player controls so they can't walk away mid-fade
			if player.has_method("set_physics_process"):
				player.set_physics_process(false)
				player.set_process_input(false)
			
			# Fade the screen to black
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("fade_to_black"):
				hud.fade_to_black(1.5)
				await get_tree().create_timer(1.5).timeout
			else:
				await get_tree().create_timer(1.5).timeout
			
			# ─── ADVANCE TO DAY 2 ────────────────────────────────────
			# While the screen is black, advance the night cycle.
			# This calls NightManager.advance_night() which ends the
			# current night, increments current_night to 1, and sets
			# time to morning (progress 0.125).
			if _night_manager.has_method("advance_night"):
				_night_manager.advance_night()
			
			# ─── SET DAY 2 OBJECTIVE ─────────────────────────────────
			# Update the HUD objective to "Document the nests."
			if hud and hud.has_method("show_message"):
				hud.show_message(DAY2_OBJECTIVE)
			# Also update the objective label directly
			var labels = get_tree().get_nodes_in_group("objective_label")
			if not labels.is_empty():
				for label in labels:
					if label is Label:
						label.text = DAY2_OBJECTIVE
			# Fallback: try to find the objective label by path
			var scene_root = get_tree().current_scene
			if scene_root:
				var obj_label = scene_root.get_node_or_null("HUD/ObjectiveLabel")
				if obj_label and obj_label is Label:
					obj_label.text = DAY2_OBJECTIVE
			
			# ─── FADE BACK IN ────────────────────────────────────────
			if hud and hud.has_method("fade_from_black"):
				hud.fade_from_black(2.0)
				await get_tree().create_timer(2.0).timeout
			
			# Restore player controls
			if player.has_method("set_physics_process"):
				player.set_physics_process(true)
				player.set_process_input(true)
			
			print("[Bed Scene] Day 2 started! Objective: Document the nests.")
		else:
			_show_hud_message("I should get settled in first before going to bed.")
		return
	
	# ─── CONDITION 2: DAY 2 — DOCUMENT NESTS (current_night == 1) ────
	# On Day 2, the player must document 3 nests and log them on the
	# computer before they can go to bed. When they sleep, they transition
	# to Night 2 (current_night becomes 2) with the car alarm sequence.
	# The peeker appears during the nighttime of Day 2 (natural night cycle)
	# if the player hasn't gone to bed yet.
	if current_night == 1:
		# Check if the player has completed the nest documentation
		var rm = get_node_or_null("/root/RoutineManager")
		var nests_done = rm and rm.nests_documented >= 3 if rm else false
		
		if not nests_done:
			_show_hud_message("I should document all the nests first before going to bed.")
			return
		
		# ─── CINEMATIC FADE TO BLACK ──────────────────────────────
		if player.has_method("set_physics_process"):
			player.set_physics_process(false)
			player.set_process_input(false)
		
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("fade_to_black"):
			hud.fade_to_black(1.5)
			await get_tree().create_timer(1.5).timeout
		else:
			await get_tree().create_timer(1.5).timeout
		
		# ─── TRANSITION TO NIGHT 2 (CAR ALARM) ───────────────────
		# Advance to Night 2 and trigger the car alarm sequence.
		_night_manager.current_night = 2
		
		# Set time to nighttime (cycle_progress ≈ 0.9 = ~1 min before dawn)
		var gt = get_node_or_null("/root/GameTime")
		if gt and gt.has_method("set_progress"):
			gt.set_progress(0.9)
			gt.is_time_paused = true
			print("[Bed Scene] Time set to nighttime (progress: 0.9). ~1 minute before dawn.")
		
		# Update the HUD night label
		if hud and hud.has_method("_update_night_label"):
			hud._update_night_label(2)
		
		# Trigger the car alarm
		var horror_sound = get_node_or_null("/root/HorrorSoundManager")
		if horror_sound and horror_sound.has_method("play_car_alarm_telegraph"):
			horror_sound.play_car_alarm_telegraph()
			print("[Bed Scene] HorrorSoundManager instructed to fire car alarm loop.")
		
		# Emit the car alarm horror event
		if _night_manager:
			_night_manager.horror_event.emit("car_alarm")
			print("[Bed Scene] Car alarm horror event emitted!")
		
		# Set the objective
		if hud and hud.has_method("show_message"):
			hud.show_message(INTRO_OBJECTIVE)
		var labels = get_tree().get_nodes_in_group("objective_label")
		if not labels.is_empty():
			for label in labels:
				if label is Label:
					label.text = INTRO_OBJECTIVE
		var scene_root = get_tree().current_scene
		if scene_root:
			var obj_label = scene_root.get_node_or_null("HUD/ObjectiveLabel")
			if obj_label and obj_label is Label:
				obj_label.text = INTRO_OBJECTIVE
		
		# Fade back in
		if hud and hud.has_method("fade_from_black"):
			hud.fade_from_black(2.0)
			await get_tree().create_timer(2.0).timeout
		
		# Restore player controls
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
			player.set_process_input(true)
		
		print("[Bed Scene] Day 2 ended! Night 2 started with car alarm. Objective: Investigate the car alarm outside.")
		return


	# ─── CONDITION 3: NIGHT 2+ — CAR ALARM / SYSTEMIC DAWN CHECK ──
	# For Night 2 (current_night == 2), the car alarm has already been
	# triggered by the bed transition. The player must investigate it.
	# For Nights 3+, the bed acts as a structural safe haven.
	if current_night == 2:
		_show_hud_message("I need to investigate the car alarm outside first.")
		return


	# ─── CONDITION 4: SYSTEMIC DAWN CHECK (NIGHTS 3+) ───────────────
	# For all subsequent nights, the bed acts as a structural safe haven.
	# The player can only sleep if they have successfully survived until 06:00 AM (Dawn).
	# Check if it's currently day (cycle_progress < 0.5), which means dawn has broken.
	var is_dawn: bool = _game_time.is_day

	
	if is_dawn:
		_advance_to_next_night()
	else:
		# ─── CONDITION 3: MID-HORROR HOUR REJECTION ─────────────────
		# Prevent the player from sleeping away their dread while the Entity is actively hunting.
		_show_hud_message("I can't go to sleep now... It isn't safe.")


## Handles the scripted fade-out, clock warp, and car alarm event for the intro
func _trigger_sleep_intro_sequence(player: Node3D) -> void:
	print("[Bed Scene] Player went to sleep. Initiating cinematic sequence...")
	
	# 1. Disable player controls cleanly so they can't walk away mid-fade
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
		player.set_process_input(false)

	# 2. Command the HUD system to fade the screen smoothly to pitch black
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("fade_to_black"):
		hud.fade_to_black(1.5) # 1.5-second cinematic fade
		await get_tree().create_timer(1.5).timeout
	else:
		# Structural fallback if your HUD doesn't have a fade method yet
		await get_tree().create_timer(1.5).timeout

	# 3. Warp the clock variables while the screen is completely black
	# Pause the timeline progression loop and force it to nighttime,
	# about 1 minute before dawn (cycle_progress 0.9).
	# The night phase spans 0.5-1.0, and dawn is at cycle_progress 1.0.
	# So 0.9 gives ~60 seconds before dawn in a 600-second cycle
	# (60s / 600s = 0.1, 1.0 - 0.1 = 0.9).
	# IMPORTANT: Use set_progress() instead of directly assigning cycle_progress
	# so that the internal _elapsed timer stays in sync. Without this, when time
	# is later unpaused, _process() recalculates cycle_progress from the stale
	# _elapsed value and snaps back to daytime.
	_game_time.is_time_paused = true
	_game_time.set_progress(0.9) # 0.9 = nighttime, ~1 minute before dawn
	print("[Bed Scene] Clock warped to nighttime (cycle_progress 0.9). ~1 minute before dawn.")




	# 4. Trigger the auditory alarm telegraph through the sound engines
	var horror_sound = get_node_or_null("/root/HorrorSoundManager")
	if horror_sound and horror_sound.has_method("play_car_alarm_telegraph"):
		horror_sound.play_car_alarm_telegraph()
		print("[Bed Scene] HorrorSoundManager instructed to fire car alarm loop.")
	else:
		print("[Bed Scene] WARNING: HorrorSoundManager not found or missing play_car_alarm_telegraph method.")

	# 5. Linger in the darkness for dramatic suspension, then wake up
	await get_tree().create_timer(2.0).timeout
	
	# 6. Restore player controls and fade back in
	if hud and hud.has_method("fade_from_black"):
		hud.fade_from_black(2.0)
	if hud and "objective_text" in hud:
		hud.objective_text = INTRO_OBJECTIVE
	
	# 7. Emit the car alarm horror event so the EscapeVan activates its alarm
	# light and becomes interactable. The player must go outside and investigate.
	if _night_manager:
		_night_manager.horror_event.emit("car_alarm")
		print("[Bed Scene] Car alarm horror event emitted! EscapeVan alarm should now be active.")
	
	# 8. Time stays FROZEN — the clock will only be unpaused when the Entity
	# spawns (in entity_controller.gd's _on_first_chase_started()).
	# The player must walk to the van with the clock suspended during the night.
	print("[Bed Scene] Time remains frozen during the night. Player must investigate the car alarm.")
	
	player.set_physics_process(true)
	player.set_process_input(true)
	print("[Bed Scene] Player woke up. Objective updated: Investigate the car alarm outside.")



## Calls the NightManager to increment the difficulty and reset the environmental world state
func _advance_to_next_night() -> void:
	print("[Bed Scene] Night survived! Saving progress and transitioning...")
	_show_hud_message("Night survived. Progress saved.")
	
	# Wait a brief moment for the message to display, then boot the transition
	await get_tree().create_timer(2.0).timeout
	if _night_manager.has_method("advance_night"):
		_night_manager.advance_night()


## UI Helper to push string warnings directly onto your HUD layer canvas
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[Bed Prompt Notification]: ", msg)
