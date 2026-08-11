extends Node3D # Or Area3D / StaticBody3D depending on your interaction setup

## Objective string updated on HUD when the player falls asleep on Night 1.
const INTRO_OBJECTIVE: String = "Investigate the car alarm outside."

## Objective string for Day 2 after the first sleep transition.
const DAY2_OBJECTIVE: String = "Read the earlier nest data logs in the computer."

@onready var _night_manager = get_node_or_null("/root/NightManager")
@onready var _game_time = get_node_or_null("/root/GameTime")

## Called when the player focuses on the bed and presses the interaction key (e.g., 'E')
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

	# ─── DEBUG: Log bed interaction state ─────────────────────────
	var rm_debug = get_node_or_null("/root/RoutineManager")
	var day_str = rm_debug.get_current_day_string() if rm_debug and rm_debug.has_method("get_current_day_string") else "?"
	print("[BED DEBUG] Bed interacted! current_night=%d, is_day=%s, cycle=%.3f, is_exhausted=%s, day_label='%s'" % [
		_night_manager.current_night, _game_time.is_day, _game_time.cycle_progress,
		str(player.is_exhausted) if "is_exhausted" in player else "N/A", day_str
	])

	# ─── DAY 3+ EXHAUSTION SLEEP (BEFORE all other conditions) ──
	if player and "is_exhausted" in player and player.is_exhausted:
		_trigger_exhaustion_sleep(player)
		return

	var current_night: int = _night_manager.current_night
	var rm = get_node_or_null("/root/RoutineManager")
	
	# ─── CONDITION 1: DAY 1 ONBOARDING (current_night == 0) ──────────
	if current_night == 0:
		var phase2_computer_used = rm and rm.phase2_computer_used if rm else false
		
		if phase2_computer_used:
			var door = get_tree().get_first_node_in_group("Door")
			var door_locked = false
			if door and "is_locked" in door:
				door_locked = door.is_locked
			
			if not door_locked:
				_show_hud_message("The door is still open.")
				return
			
			if rm and rm.has_method("on_bed_interacted"):
				rm.on_bed_interacted()
			
			if player.has_method("set_physics_process"):
				player.set_physics_process(false)
				player.set_process_input(false)
			
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("fade_to_black"):
				await hud.fade_to_black(3.0)
			else:
				await get_tree().create_timer(1.5).timeout
			
			# ─── FREEZE CLOCK BEFORE ADVANCE ───────────────────────
			# Must freeze BEFORE advance_night() so the clock can't tick
			# during the night transition. advance_night() sets cycle_progress
			# to 0.0 (start of day) and unpauses time. We freeze before
			# so it lands at exactly 00:00 and stays there through the fade.
			if _game_time:
				_game_time.is_time_paused = true
			if _night_manager.has_method("advance_night"):
				_night_manager.advance_night()
			# Re-freeze after advance_night() since it may have unpaused time
			if _game_time:
				_game_time.is_time_paused = true
			
			if hud and hud.has_method("show_message"):
				hud.show_message(DAY2_OBJECTIVE)
			var labels = get_tree().get_nodes_in_group("objective_label")
			if not labels.is_empty():
				for label in labels:
					if label is Label:
						label.text = DAY2_OBJECTIVE
			var scene_root = get_tree().current_scene
			if scene_root:
				var obj_label = scene_root.get_node_or_null("HUD/ObjectiveLabel")
				if obj_label and obj_label is Label:
					obj_label.text = DAY2_OBJECTIVE
			
			if hud and hud.has_method("fade_from_black"):
				await hud.fade_from_black(2.0)
			
			# ─── UNFREEZE CLOCK ────────────────────────────────────
			# Time was frozen before and after advance_night() so the HUD
			# would show exactly 00:00. Now unpause it so Day 2's clock runs.
			if _game_time:
				_game_time.is_time_paused = false
			
			if player.has_method("set_physics_process"):
				player.set_physics_process(true)
				player.set_process_input(true)
			
			print("[Bed Scene] Day 2 started! Objective: Document the nests.")
		else:
			_show_hud_message("I should get settled in first before going to bed.")
		return
	
	# ─── CONDITION 2: DAY 2 NEST DOCUMENTATION ───────────────────
	# DATA-DRIVEN: Uses RoutineManager flags instead of current_night
	# to handle the case where the natural night cycle auto-increments
	# current_night before the player completes their objectives.
	
	var phase2_done: bool = rm and rm.phase2_computer_used if rm else false
	var phase3_done: bool = rm and rm.phase3_bed_used if rm else false
	
	# ─── PRIORITY FIX: BLOCK BED DURING INCOMPLETE DAY 2 ─────────
	# If the Day 2 nest-tutorial sequence is active (main_objective >= 99)
	# but NOT yet fully complete (day2_step < 8), the player MUST NOT be
	# able to sleep. Previously, when current_night advanced to 2 during
	# Day 2 daytime, the dawn check below treated the daytime as "dawn"
	# and advanced to the next night immediately — skipping all Day 2
	# objectives. This guard runs BEFORE Conditioning 3/4 to hard-block.
	var day2_nests_documented: int = rm.nests_documented if rm else 0
	var day2_sequence_active: bool = rm and rm.main_objective >= 99 if rm else false
	# ─── BUG 6 FIX: Allow day2_step == 7 through the gate ───────────
	# Previously this checked `day2_step >= 8` (sequence COMPLETE). But step 7
	# IS "Go to bed" — the very interaction this handler is supposed to
	# perform. Blocking everything below step 8 created a deadlock: the player
	# could never reach step 8 because step 7 (going to bed) was blocked by
	# the "not complete" guard. Now the gate only blocks steps 1–6.
	var day2_bed_step_reached: bool = rm and rm.day2_step >= 7 if rm else false
	if day2_sequence_active and not day2_bed_step_reached:
		if day2_nests_documented < 3:
			_show_hud_message("I should document all the nests first before going to bed.")
		else:
			_show_hud_message("I still have work to do before I can sleep.")
		return
	
	# ─── GUARD B (checked FIRST): Nest tasks on Day 2+ ──────────
	# Uses `nests_documented >= 1` instead of `current_night >= 1` because
	# the natural day/night cycle can advance current_night to 1 BEFORE
	# the player finishes Day 1 objectives (e.g., time runs out during
	# the onboarding sequence). This caused a bug where the player was told
	# "Document the nests" when they hadn't even finished Day 1 yet.
	# The correct signal that the player is on Day 2 is that they've already
	# found and documented at least one nest.
	# The is_van_sequence_active guard prevents re-entering after the
	# van sequence has already been triggered.
	if day2_nests_documented >= 1 and not _night_manager.is_van_sequence_active:
		var nests_done: bool = rm and rm.nests_documented >= 3 if rm else false
		var data_uploaded: bool = rm and rm.nests_uploaded if rm else false
		
		if not nests_done:
			_show_hud_message("I should document all the nests first before going to bed.")
			return
		
		if not data_uploaded:
			_show_hud_message("I should upload the nest data on the computer first before going to bed.")
			return
		
		# ─── DAY 2 STEP 6 GATE: LOCK THE DOOR ─────────────────────
		# After uploading the nest data, the Day 2 sequence advances to
		# step 6 ("Lock the door"). The bed refuses until the player has
		# locked the door (which advances to step 7, "Go to bed").
		var day2_step: int = rm.day2_step if rm else 0
		if day2_step == 6:
			_show_hud_message("I should lock the door first.")
			return
		
		if day2_step == 7:
			rm.day2_step = 8
			print("[Bed Scene] Day 2 Step 7 COMPLETE: Player went to bed. Day 2 sequence finished.")
		
		# ─── NESTS DOCUMENTED + UPLOADED → VAN SEQUENCE SLEEP ───
		if player.has_method("set_physics_process"):
			player.set_physics_process(false)
			player.set_process_input(false)
		
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("fade_to_black"):
			await hud.fade_to_black(3.0)
		else:
			await get_tree().create_timer(3.0).timeout
		
		_night_manager.is_van_sequence_active = true
		_night_manager.current_night = 2
		_night_manager.start_night(2)
		
		var gt = get_node_or_null("/root/GameTime")
		if gt:
			gt.cycle_progress = 0.9
			gt._elapsed = gt.cycle_progress * gt.cycle_duration
			gt.is_day = false
			gt.is_time_paused = true
			gt.time_changed.emit(0.9)
			print("[Bed Scene] Time forced to cycle_progress=0.9 (4 min into night, 1 min until dawn). Night 2.2 van sequence starting.")
		
		if hud and hud.has_method("_update_night_label"):
			hud._update_night_label(2)
		
		var horror_sound = get_node_or_null("/root/HorrorSoundManager")
		if horror_sound and horror_sound.has_method("play_car_alarm_telegraph"):
			horror_sound.play_car_alarm_telegraph()
			print("[Bed Scene] HorrorSoundManager instructed to fire car alarm loop.")
		
		if _night_manager:
			_night_manager.horror_event.emit("car_alarm")
			print("[Bed Scene] Car alarm horror event emitted!")
		
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
		
		if hud and hud.has_method("fade_from_black"):
			await hud.fade_from_black(2.0)
		
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
			player.set_process_input(true)
		
		print("[Bed Scene] Day 2 ended! Night 2 started with car alarm.")
		return
	
	# ─── GUARD A (FALLBACK): Day 1 → Day 2 sleep transition ─────
	# Only valid when the player hasn't yet completed Day 1 sleep
	# AND current_night is still at Day 1 (current_night <= 1).
	# The current_night gate prevents this guard from firing on Day 2+
	# if phase3_bed_used was never set (e.g., window wasn't patched).
	#
	# Additionally, we honor the return value of rm.on_bed_interacted()
	# which checks for prerequisites (window patched, door locked).
	# If RM returns false, the bed interaction is cancelled.
	if phase2_done and not phase3_done and current_night <= 1:
		if rm and rm.has_method("on_bed_interacted"):
			var can_sleep = rm.on_bed_interacted()
			if not can_sleep:
				# RM refused the sleep (window not patched or door unlocked).
				# Do NOT proceed with advance_night().
				return
		if player.has_method("set_physics_process"):
			player.set_physics_process(false)
			player.set_process_input(false)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("fade_to_black"):
			await hud.fade_to_black(3.0)
		else:
			await get_tree().create_timer(3.0).timeout
		# ─── FREEZE CLOCK BEFORE ADVANCE ───────────────────────
		if _game_time:
			_game_time.is_time_paused = true
		if _night_manager.has_method("advance_night"):
			_night_manager.advance_night()
		# Re-freeze after advance_night() since it may have unpaused time
		if _game_time:
			_game_time.is_time_paused = true
		
		if hud and hud.has_method("show_message"):
			hud.show_message(DAY2_OBJECTIVE)
		var labels = get_tree().get_nodes_in_group("objective_label")
		if not labels.is_empty():
			for label in labels:
				if label is Label:
					label.text = DAY2_OBJECTIVE
		var scene_root = get_tree().current_scene
		if scene_root:
			var obj_label = scene_root.get_node_or_null("HUD/ObjectiveLabel")
			if obj_label and obj_label is Label:
				obj_label.text = DAY2_OBJECTIVE
		if hud and hud.has_method("fade_from_black"):
			await hud.fade_from_black(2.0)
		
		# ─── UNFREEZE CLOCK ────────────────────────────────────
		if _game_time:
			_game_time.is_time_paused = false
		
		if player.has_method("set_physics_process"):
			player.set_physics_process(true)
			player.set_process_input(true)
		print("[Bed Scene] Day 1 sleep redirect. Day 2 started!")
		return
	
	# ─── CONDITION 3: CAR ALARM ACTIVE ───────────────────────────
	if _night_manager.is_van_sequence_active:
		_show_hud_message("I need to investigate the car alarm outside first.")
		return

	# ─── CONDITION 4: SYSTEMIC DAWN CHECK (NIGHTS 3+) ────────────
	var is_dawn: bool = _game_time.is_day
	
	if is_dawn:
		_advance_to_next_night()
	else:
		_show_hud_message("I can't go to sleep now... It isn't safe.")


## ─── DAY 3+ EXHAUSTION SLEEP ────────────────────────────────────────────────
func _trigger_exhaustion_sleep(player: Node3D) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("fade_to_black"):
		hud.fade_to_black(1.5)
		await get_tree().create_timer(1.5).timeout

	var gt = get_node_or_null("/root/GameTime")
	if gt and gt.has_method("set_progress"):
		gt.set_progress(0.20)

	if "is_exhausted" in player:
		player.is_exhausted = false
	if "_exhausted_walk_speed" in player and player._exhausted_walk_speed > 0:
		player.walk_speed = player._exhausted_walk_speed
	if "_exhausted_run_speed" in player and player._exhausted_run_speed > 0:
		player.run_speed = player._exhausted_run_speed
	if "sprint_unlocked" in player:
		player.sprint_unlocked = true

	var door = get_tree().get_first_node_in_group("Door")
	if door:
		door.is_locked = false

	if gt:
		gt.unpause_time()

	if _night_manager:
		_night_manager.is_time_paused = false

	var rm_exh = get_node_or_null("/root/RoutineManager")
	
	# ─── RESET DAY 2 NEST FLAGS (MUST HAPPEN BEFORE _update_hud) ─
	# A new day has started. Clear the nest documentation flags so
	# the RoutineManager objective doesn't show stale "Lock the door
	# and go to bed" from Day 2's nest upload completion.
	# CRITICAL: These MUST be reset BEFORE _update_hud() because
	# get_current_objective() reads nests_uploaded first.
	if rm_exh:
		rm_exh.nests_documented = 0
		rm_exh.nests_uploaded = false

	# ─── ACTIVATE DAY 3 SANDBOX MODE ─────────────────────────────
	# Pauses the linear Day 1–2 schedule and grants total exploration
	# freedom. The van escape and side-track objectives become available.
	if rm_exh and rm_exh.has_method("enable_sandbox_mode"):
		rm_exh.enable_sandbox_mode()

	# ─── NOW REFRESH THE HUD OBJECTIVE ───────────────────────────
	# Now that the stale flags are cleared, refresh the HUD so it
	# shows the correct Day 3+ objective instead of "Lock the door
	# and go to bed."
	if rm_exh and rm_exh.has_method("_update_hud"):
		rm_exh._update_hud()

	# ─── REFRESH HUD DAY LABEL ───────────────────────────────────
	# Force the HUD to re-read current_night and show the correct
	# day label (e.g., "Day 3" instead of stale "Day 2").
	if hud and hud.has_method("_sync_all_displays"):
		hud._sync_all_displays()

	if hud and hud.has_method("fade_from_black"):
		hud.fade_from_black(2.0)
		await get_tree().create_timer(2.0).timeout

	var day_after = rm_exh.get_current_day_string() if rm_exh and rm_exh.has_method("get_current_day_string") else "?"
	print("[BED DEBUG] Waking up! current_night=%d, is_day=%s, cycle=%.3f, day_label='%s'" % [
		_night_manager.current_night, gt.is_day if gt else -1, gt.cycle_progress if gt else -1, day_after
	])
	print("[Bed Scene] Exhaustion sleep complete. Player restored. Door unlocked. Time unpaused. Objective refreshed. Day label: %s" % day_after)


func _trigger_sleep_intro_sequence(player: Node3D) -> void:
	print("[Bed Scene] Player went to sleep. Initiating cinematic sequence...")
	
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
		player.set_process_input(false)

	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("fade_to_black"):
		hud.fade_to_black(1.5)
		await get_tree().create_timer(1.5).timeout
	else:
		await get_tree().create_timer(1.5).timeout

	_game_time.is_time_paused = true
	_game_time.set_progress(0.9)
	print("[Bed Scene] Clock warped to nighttime (cycle_progress 0.9). ~1 minute before dawn.")

	var horror_sound = get_node_or_null("/root/HorrorSoundManager")
	if horror_sound and horror_sound.has_method("play_car_alarm_telegraph"):
		horror_sound.play_car_alarm_telegraph()
		print("[Bed Scene] HorrorSoundManager instructed to fire car alarm loop.")
	else:
		print("[Bed Scene] WARNING: HorrorSoundManager not found or missing play_car_alarm_telegraph method.")

	await get_tree().create_timer(2.0).timeout
	
	if hud and hud.has_method("fade_from_black"):
		hud.fade_from_black(2.0)
	if hud and "objective_text" in hud:
		hud.objective_text = INTRO_OBJECTIVE
	
	if _night_manager:
		_night_manager.horror_event.emit("car_alarm")
		print("[Bed Scene] Car alarm horror event emitted! EscapeVan alarm should now be active.")
	
	print("[Bed Scene] Time remains frozen during the night. Player must investigate the car alarm.")
	
	player.set_physics_process(true)
	player.set_process_input(true)
	print("[Bed Scene] Player woke up. Objective updated: Investigate the car alarm outside.")


func _advance_to_next_night() -> void:
	print("[Bed Scene] Night survived! Saving progress and transitioning...")
	await get_tree().create_timer(2.0).timeout
	
	# ─── FORCE END_CURRENT_NIGHT TO EXECUTE ───────────────────────
	# The _on_game_day_started() signal may have already fired and set
	# is_night_active = false, which causes end_current_night() to bail
	# out without incrementing current_night. We override the guard so
	# current_night always advances (e.g., 2→3 for Day 3).
	_night_manager.is_night_active = true
	
	if _night_manager.has_method("advance_night"):
		_night_manager.advance_night()


func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[Bed Prompt Notification]: ", msg)