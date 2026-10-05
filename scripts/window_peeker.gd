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
##   1. On spawn, the MonsterModel starts below ground and tweens up to the
##      window position (creepy rise-up effect).
##   2. After the rise-up, plays the "Peek" animation (lean forward, hold).
##   3. Each frame, checks if the player is looking at this peeker via camera
##      dot-product.
##   4. If the player looks at it, plays the "Vanish" sequence (quick duck down).
##   5. On queue_free, emits "peeker_vanish_finished" so PeekerManager can
##      schedule a re-spawn.

signal peeker_vanish_finished

@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _monster_model: Node3D = $MonsterModel

## Cached reference to the player's 3D camera.
var _cached_camera: Camera3D = null

## Offset applied to the MonsterModel's position in _ready().
## Tweak this at runtime in the Inspector to position the model perfectly
## at the window. The default (-0.57 Y) matches the entity's model offset.
@export var model_offset: Vector3 = Vector3(0, -0.57, 0)

## Dot-product threshold for the player's gaze cone.
## cos(20°) ≈ 0.94 — the player must be looking within ~20 degrees of the
## peeker for it to trigger the vanish.
const GAZE_DOT_THRESHOLD: float = 0.94

## Maximum distance for the gaze check (meters).
const GAZE_MAX_DISTANCE: float = 25.0

## Delay in seconds after the player looks at the peeker before it vanishes.
## 1.325 s: long enough to be sure of what you saw (it was 0.325 s).
const SPOTTED_VANISH_DELAY: float = 1.325

## Timer counting up while the player is looking at this peeker.
## Resets to 0 if the player looks away before SPOTTED_VANISH_DELAY elapses.
var _spotted_timer: float = 0.0

## Sound played when the peeker is spotted and vanishes.
## Assign Piano_stinger_dissonent.wav from assets/audio/ here.
## Leave null for no sound.
@export var piano_stinger_sfx: AudioStream = null

## ─── RISE-UP SPAWN ANIMATION ────────────────────────────────────────

## How far below the window the peeker starts (meters).
## The MonsterModel begins at model_offset.y + SPAWN_RISE_DISTANCE.
const SPAWN_RISE_DISTANCE: float = -3.0

## Duration of the rise-up tween in seconds.
const SPAWN_RISE_DURATION: float = 1.5

## Night 2 (set by PeekerManager before it enters the tree): a much quicker
## rise, and it ducks away sooner and faster once seen.
var quick: bool = false
const QUICK_RISE_DURATION: float = 0.35
const QUICK_VANISH_DELAY: float = 0.35
const QUICK_DUCK_DURATION: float = 0.15

## Whether the peeker is still rising into position.
## Gaze checks are disabled during this phase so the peeker isn't spotted
## before the player can see it.
var _is_rising: bool = true


func _ready() -> void:
	# Cache the player camera
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_cached_camera = player.get_node_or_null("CameraHolder/Camera3D")
	if not _cached_camera:
		_cached_camera = get_viewport().get_camera_3d()
	
	# ─── RISE-UP SPAWN ──────────────────────────────────────────────
	# Start the MonsterModel below ground, then tween it up to create
	# the effect of the peeker creepily rising up to the window.
	if _monster_model:
		# Set initial position: model_offset + below-ground offset
		var start_pos = model_offset
		start_pos.y += SPAWN_RISE_DISTANCE
		_monster_model.position = start_pos
		
		# Tween up to the target model_offset
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(_monster_model, "position", model_offset, QUICK_RISE_DURATION if quick else SPAWN_RISE_DURATION)
		tween.finished.connect(_on_rise_finished)
	else:
		_is_rising = false
		_play_peek_animation()


func _on_rise_finished() -> void:
	_is_rising = false
	_play_peek_animation()


func _play_peek_animation() -> void:
	if _anim_player and _anim_player.has_animation("Peek"):
		_anim_player.play("Peek")
	else:
		print("[WindowPeeker] No 'Peek' animation found. Waiting to be spotted.")


func _process(delta: float) -> void:
	# Sync the model offset so Inspector tweaks take effect in real-time.
	if _monster_model and _monster_model.position != model_offset and not _is_rising:
		_monster_model.position = model_offset
	
	# Don't process gaze during rise-up — the peeker isn't visible yet.
	if _is_rising:
		return
	
	# Check if the player is looking at this peeker.
	if is_player_looking_at_me():
		var pm = get_node_or_null("/root/PeekerManager")
		if (pm and pm.peeker_vanish_on_sight) or not pm:
			_spotted_timer += delta
			if _spotted_timer >= (QUICK_VANISH_DELAY if quick else SPOTTED_VANISH_DELAY):
				_vanish()
	else:
		_spotted_timer = 0.0


## Returns true if the player's camera is pointed within ~20 degrees of
## this peeker's position AND the player is within GAZE_MAX_DISTANCE.
func is_player_looking_at_me() -> bool:
	if not _cached_camera:
		return false
	
	var dist_sq = _cached_camera.global_position.distance_squared_to(global_position)
	if dist_sq > GAZE_MAX_DISTANCE * GAZE_MAX_DISTANCE:
		return false
	
	var cam_forward: Vector3 = -_cached_camera.global_transform.basis.z
	cam_forward = cam_forward.normalized()
	
	var to_peeker: Vector3 = global_position - _cached_camera.global_position
	to_peeker = to_peeker.normalized()
	
	return cam_forward.dot(to_peeker) >= GAZE_DOT_THRESHOLD


## How far down (in meters) the MonsterModel moves when ducking out of sight.
const DUCK_DOWN_DISTANCE: float = -1.5

## Duration of the duck-down tween in seconds.
const DUCK_DOWN_DURATION: float = 0.45

## Whether this peeker is currently in the duck-down (vanish) sequence.
var _is_vanishing: bool = false


## Triggers the vanish sequence — tweens the MonsterModel downward
## (ducking out of sight like a living thing) and then frees the node.
func _vanish() -> void:
	if _is_vanishing:
		return
	
	_is_vanishing = true
	
	# ─── PIANO STINGER ────────────────────────────────────────────────
	# When the player spots the peeker, play a dissonant piano sting.
	_play_sfx(piano_stinger_sfx)
	
	if not _monster_model:
		peeker_vanish_finished.emit()
		queue_free()
		return
	
	var target_y = _monster_model.position.y + DUCK_DOWN_DISTANCE
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_monster_model, "position:y", target_y, QUICK_DUCK_DURATION if quick else DUCK_DOWN_DURATION)
	tween.finished.connect(_on_duck_finished)


func _on_duck_finished() -> void:
	peeker_vanish_finished.emit()
	queue_free()


## Plays a one-shot sound effect via a temporary AudioStreamPlayer3D.
## The piano stinger is played at 50% volume (-6.0 dB) to avoid being jarring.
## Reparents to the scene root so queue_free() on this node doesn't cut the sound.
func _play_sfx(stream: AudioStream) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = -9.0
	player.global_position = global_position
	# Reparent to scene root so queue_free() on the peeker doesn't destroy this player
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
