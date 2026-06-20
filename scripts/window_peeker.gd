extends Node3D
class_name WindowPeeker

## WindowPeeker — "Night 1 Peeker" visual prop.
##
## A purely visual, scripted animation actor that peeks through a cabin window
## on Night 1. Completely disconnected from the Entity AI, navigation, or FSM.
## This actor is NOT added to any "Entity" groups and is NOT visible to the
## MasterBehaviorDirector.
##
## BEHAVIOR:
##   1. On _ready(), plays the "Peek" animation (lean forward, hold, vanish down).
##   2. Each frame, checks if the player is looking at this peeker via camera
##      dot-product (reusing logic from entity_sensory.gd).
##   3. If the player looks at it, immediately plays the "Vanish" animation
##      (quick fade-out + downward movement).
##   4. When the Vanish animation finishes, calls queue_free().
##   5. On queue_free, emits "peeker_vanish_finished" so PeekerManager can
##      schedule a re-spawn.

signal peeker_vanish_finished

@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _monster_model: Node3D = $MonsterModel

## Cached reference to the player's 3D camera.
## Resolved once in _ready() to avoid polling get_viewport().get_camera_3d().
var _cached_camera: Camera3D = null

## Offset applied to the MonsterModel's position in _ready().
## Tweak this at runtime in the Inspector to position the model perfectly
## at the window. The default (-0.57 Y) matches the entity's model offset.
## 
## Usage: Run the game, select the WindowPeeker node in the Remote scene tree,
## and adjust this Vector3 in the Inspector. The model moves in real-time.
@export var model_offset: Vector3 = Vector3(0, -0.57, 0)

## Dot-product threshold for the player's gaze cone.
## cos(20°) ≈ 0.94 — the player must be looking within ~20 degrees of the
## peeker for it to trigger the vanish. This prevents accidental triggers
## from peripheral vision.
const GAZE_DOT_THRESHOLD: float = 0.94

## Maximum distance for the gaze check (meters).
## If the player is further than this, the peeker won't vanish even if
## the player is looking in its direction.
const GAZE_MAX_DISTANCE: float = 25.0

## Delay in seconds after the player looks at the peeker before it vanishes.
## This gives the player a brief moment to register what they saw before
## the peeker disappears, creating a more impactful "did I just see that?" moment.
const SPOTTED_VANISH_DELAY: float = 0.5

## Timer counting up while the player is looking at this peeker.
## Resets to 0 if the player looks away before SPOTTED_VANISH_DELAY elapses.
var _spotted_timer: float = 0.0


func _ready() -> void:
	# Cache the player camera
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_cached_camera = player.get_node_or_null("CameraHolder/Camera3D")
	
	# Fallback: try the viewport camera
	if not _cached_camera:
		_cached_camera = get_viewport().get_camera_3d()
	
	# Apply the initial model offset
	if _monster_model:
		_monster_model.position = model_offset
	
	# Play the peek animation sequence.
	# The "Peek" animation plays once (lean forward, hold).
	# When it finishes, the peeker simply stays visible until the player
	# spots it — no auto-vanish. The vanish is triggered by _vanish().
	if _anim_player and _anim_player.has_animation("Peek"):
		_anim_player.play("Peek")
	else:
		# No animation available — just sit there until spotted
		print("[WindowPeeker] No 'Peek' animation found. Waiting to be spotted.")


func _process(delta: float) -> void:
	# Continuously sync the model offset so Inspector tweaks take effect in real-time.
	if _monster_model and _monster_model.position != model_offset:
		_monster_model.position = model_offset
	
	# Check if the player is looking at this peeker.
	# If so, count up the spotted timer. Once it reaches SPOTTED_VANISH_DELAY,
	# trigger the vanish sequence. If the player looks away, reset the timer.
	if is_player_looking_at_me():
		var pm = get_node_or_null("/root/PeekerManager")
		if (pm and pm.peeker_vanish_on_sight) or not pm:
			_spotted_timer += delta
			if _spotted_timer >= SPOTTED_VANISH_DELAY:
				_vanish()
	else:
		# Player looked away — reset the spotted timer
		_spotted_timer = 0.0


## Returns true if the player's camera is pointed within ~20 degrees of
## this peeker's position AND the player is within GAZE_MAX_DISTANCE.
##
## Reuses the same camera dot-product logic from entity_sensory.gd's
## is_player_looking_at_window() method.
func is_player_looking_at_me() -> bool:
	if not _cached_camera:
		return false
	
	# Early-out distance check
	var dist_sq = _cached_camera.global_position.distance_squared_to(global_position)
	if dist_sq > GAZE_MAX_DISTANCE * GAZE_MAX_DISTANCE:
		return false
	
	# Calculate the angle between the camera's forward vector and the
	# direction from the camera to this peeker's position.
	# NOTE: Y component is KEPT in both vectors so the player must actually
	# look at the peeker's vertical position. Without Y, a peeker on the
	# second floor would trigger when looking through a first-floor window
	# directly below it.
	var cam_forward: Vector3 = -_cached_camera.global_transform.basis.z
	cam_forward = cam_forward.normalized()
	
	var to_peeker: Vector3 = global_position - _cached_camera.global_position
	to_peeker = to_peeker.normalized()
	
	# Dot-product gaze cone check
	return cam_forward.dot(to_peeker) >= GAZE_DOT_THRESHOLD


## How far down (in meters) the MonsterModel moves when ducking out of sight.
## A negative value moves it downward below the window frame.
const DUCK_DOWN_DISTANCE: float = -1.5

## Duration of the duck-down tween in seconds.
## Increased by 50% (from 0.3 to 0.45) so the peeker lingers longer
## after being spotted, giving the player a more impactful sighting.
const DUCK_DOWN_DURATION: float = 0.45

## Whether this peeker is currently in the duck-down (vanish) sequence.
var _is_vanishing: bool = false


## Triggers the vanish sequence.
## Instead of playing an animation, this tweens the MonsterModel downward
## (ducking out of sight like a living thing) and then frees the node.
## If already vanishing, this is a no-op.
func _vanish() -> void:
	if _is_vanishing:
		return
	
	_is_vanishing = true
	
	if not _monster_model:
		# No model to animate — just free
		peeker_vanish_finished.emit()
		queue_free()
		return
	
	# Calculate the target Y position: current Y + duck distance
	var target_y = _monster_model.position.y + DUCK_DOWN_DISTANCE
	
	# Create a tween to move the model downward quickly
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_monster_model, "position:y", target_y, DUCK_DOWN_DURATION)
	tween.finished.connect(_on_duck_finished)


## Called when the duck-down tween finishes.
## Emits the vanish-finished signal and frees this peeker.
func _on_duck_finished() -> void:
	peeker_vanish_finished.emit()
	queue_free()
