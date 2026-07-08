extends Node3D

## EndgameCinematics — Cinematic camera controller for the three ending cutscenes.
## Attach to a Node3D (e.g., "Cinematics") in cottage_horror.tscn.
##
## Manages an AnimationPlayer and three Camera3D nodes that take over
## the player's view during the ending cinematic, then signal completion
## so the EndgameManager can proceed with fade-to-black and UI.

## The AnimationPlayer that drives all three cinematic animations.
@export var animation_player: AnimationPlayer

## Camera for the DEATH ending (Entity catches the player).
@export var death_cam: Camera3D

## Camera for the ESCAPE_MEDIOCRE ending (van escape, totem intact).
@export var mediocre_cam: Camera3D

## Camera for the ESCAPE_GOOD ending (van escape, totem destroyed).
@export var good_cam: Camera3D


## Plays the cinematic for the given ending and returns the
## AnimationPlayer.animation_finished Signal so callers can await it.
##
## ending — an EndgameManager.Ending enum value (0=DEATH, 1=ESCAPE_MEDIOCRE, 2=ESCAPE_GOOD)
##
## Returns the animation_finished Signal.
func play_ending_cinematic(ending: int) -> Signal:
	# Match the ending enum to the correct camera and animation name.
	# Values must match EndgameManager.Ending: DEATH=0, ESCAPE_MEDIOCRE=1, ESCAPE_GOOD=2.
	var cam: Camera3D
	var anim_name: String

	match ending:
		0:  # Ending.DEATH
			cam = death_cam
			anim_name = "death_drag"
		1:  # Ending.ESCAPE_MEDIOCRE
			cam = mediocre_cam
			anim_name = "escape_mediocre"
		2:  # Ending.ESCAPE_GOOD
			cam = good_cam
			anim_name = "escape_good"
		_:
			push_error("[EndgameCinematics] Unknown ending enum value: ", ending)
			cam = death_cam
			anim_name = "death_drag"

	# Validate references
	if not animation_player:
		push_error("[EndgameCinematics] AnimationPlayer is not assigned!")
		return _create_dummy_signal()

	if not cam:
		push_error("[EndgameCinematics] Camera for ending ", ending, " is not assigned!")
		return _create_dummy_signal()

	# Make this camera current — Godot automatically disables all other Camera3Ds.
	cam.current = true

	# Play the animation
	animation_player.play(anim_name)

	print("[EndgameCinematics] Playing cinematic: ", anim_name, " on camera: ", cam.name)

	# Return the signal so the EndgameManager can await it
	return animation_player.animation_finished


## Creates a one-shot Timer and returns its timeout signal so error-path
## callers have a valid Signal to await (prevents indefinite hangs).
func _create_dummy_signal() -> Signal:
	var timer = Timer.new()
	timer.name = "_CinematicErrorTimer"
	timer.one_shot = true
	timer.wait_time = 0.01
	add_child(timer)
	timer.start()
	# Return the timeout signal — it will fire almost immediately so the
	# caller's await resolves without hanging.
	return timer.timeout
