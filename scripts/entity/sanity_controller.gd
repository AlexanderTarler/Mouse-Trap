extends Node3D
## Sanity/Gaze Controller — modular system attached to the player's Camera3D.
## Staring at an Entity builds a gaze meter that triggers escalating
## audio/visual hallucinations, culminating in a 3-second "blindness" climax.

# ============================================================
# Exported parameters
# ============================================================

## How fast the gaze meter fills (points per second). At 25.0, it takes ~4 seconds to max.
@export var build_rate: float = 25.0

## How fast the gaze meter decays when NOT looking at the entity (points per second).
@export var decay_rate: float = 15.0

## Maximum distance the raycast checks for the entity.
@export var max_ray_distance: float = 50.0

## Minimum volume when audio first kicks in (linear, 0.0–1.0).
@export var audio_min_volume: float = 0.15

## Maximum volume at full gaze (linear, 0.0–1.0).
@export var audio_max_volume: float = 0.8

## Minimum pitch scale when audio first kicks in.
@export var audio_min_pitch: float = 0.6

## Maximum pitch scale at full gaze.
@export var audio_max_pitch: float = 1.3

## How long (seconds) the blindness climax holds at full intensity before fading.
@export var blindness_hold_time: float = 0.5

## How long (seconds) the blindness fade-out takes.
@export var blindness_fade_time: float = 3.0

# ============================================================
# Runtime state
# ============================================================

## Current gaze meter value (0.0 to 100.0).
var gaze_meter: float = 0.0

## True while the blindness climax is playing out.
var is_blinded: bool = false

## Reference to the active Tween for the blindness sequence.
var _blindness_tween: Tween = null

## Throttle timer for periodic debug logging
var _debug_timer: float = 0.0

# ============================================================
# Node references (cached in _ready)
# ============================================================

@onready var _raycast: RayCast3D = $SanityRayCast
@onready var _audio: AudioStreamPlayer = $SanityAudio
@onready var _overlay: ColorRect = $OverlayLayer/SanityOverlay
var _overlay_material: ShaderMaterial

# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Configure raycast at runtime (collision_mask = bit 5 → layer 5)
	_raycast.target_position = Vector3(0.0, 0.0, -max_ray_distance)
	_raycast.collision_mask = 1 << 4
	_raycast.exclude_parent = true
	_raycast.enabled = true
	print("[Sanity] Initialized. RayCast mask=%d (layer 5), dist=%.0f" % [_raycast.collision_mask, max_ray_distance])

	# Load the audio stream dynamically (avoids broken UID references in .tscn)
	_audio.stream = load("res://assets/audio/Entity/Entity_Seen.ogg")
	_audio.bus = &"SFX"
	_audio.stop()
	print("[Sanity] Audio loaded: Entity_Seen.ogg on bus SFX")

	# Create the ShaderMaterial dynamically and attach to the ColorRect
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = load("res://shaders/sanity_overlay.gdshader")
	_overlay_material.set_shader_parameter("corruption_intensity", 0.0)
	_overlay.material = _overlay_material
	print("[Sanity] ShaderMaterial created and attached to SanityOverlay")


func _physics_process(delta: float) -> void:
	# --------------------------------------------------------
	# Gaze detection — two-step cone + occlusion
	# --------------------------------------------------------
	# Step 1: Find the Entity. Step 2: Check if the player's camera
	# is looking toward it (cone check). Step 3: Verify line-of-sight
	# with a raycast that respects walls (mask includes Layer 1).
	var entity_seen: bool = false
	var entity_node = get_tree().get_first_node_in_group("entity")
	
	if entity_node:
		var cam = get_viewport().get_camera_3d()
		if cam:
			var entity_target = entity_node.global_position + Vector3(0, 1.0, 0)
			var dir_to_entity = (entity_target - cam.global_position).normalized()
			var cam_forward = -cam.global_transform.basis.z.normalized()
			
			# STEP 1: Vision cone — dot > 0.85 (~31° cone, on-screen)
			if cam_forward.dot(dir_to_entity) > 0.85:
				# STEP 2: Occlusion raycast — mask 17 = Layer 1 (world) | Layer 5 (entity)
				var space = get_world_3d().direct_space_state
				var query = PhysicsRayQueryParameters3D.create(cam.global_position, entity_target)
				query.exclude = [get_parent().get_parent()]  # exclude Player body
				query.collision_mask = 17  # Layer 1 | Layer 5 = 1 | 16
				var result = space.intersect_ray(query)
				if not result.is_empty():
					entity_seen = result.collider != null and result.collider.is_in_group("entity")

	# Throttled debug log every 2 seconds
	_debug_timer += delta
	if _debug_timer >= 2.0:
		_debug_timer = 0.0

	# --------------------------------------------------------
	# Meter adjustment (clamped 0–100)
	# --------------------------------------------------------
	if entity_seen and not is_blinded:
		gaze_meter = minf(gaze_meter + build_rate * delta, 100.0)
	elif not is_blinded:
		gaze_meter = maxf(gaze_meter - decay_rate * delta, 0.0)

	var norm := gaze_meter / 100.0

	# --------------------------------------------------------
	# Blindness climax trigger
	# --------------------------------------------------------
	if gaze_meter >= 100.0 and not is_blinded:
		_trigger_blindness()
		return  # Skip normal update this frame

	if is_blinded:
		return  # During blindness the tween drives everything

	# --------------------------------------------------------
	# Visual escalation (before blindness)
	# --------------------------------------------------------
	_overlay_material.set_shader_parameter("corruption_intensity", norm)

	# --------------------------------------------------------
	# Audio escalation (smooth volume & pitch ramp)
	# --------------------------------------------------------
	if norm > 0.0:
		if not _audio.playing:
			_audio.play()

		# Smoothly crossfade volume to avoid popping
		var target_volume := lerpf(audio_min_volume, audio_max_volume, norm)
		_audio.volume_db = linear_to_db(target_volume)

		# Pitch rises as meter fills — deeper at low gaze, frantic at high
		var target_pitch := lerpf(audio_min_pitch, audio_max_pitch, norm)
		_audio.pitch_scale = target_pitch
	else:
		if _audio.playing:
			_audio.stop()


# ============================================================
# Blindness climax
# ============================================================

func _trigger_blindness() -> void:
	is_blinded = true

	# Kill audio instantly (shock cut-off)
	if _audio.playing:
		_audio.stop()

	# Snap overlay to full intensity
	_overlay_material.set_shader_parameter("corruption_intensity", 1.0)

	# Cancel any previous tween that might be lingering
	if _blindness_tween and _blindness_tween.is_valid():
		_blindness_tween.kill()

	# Create the blindness tween sequence:
	#   1. Hold at 1.0 for blindness_hold_time seconds
	#   2. Tween corruption_intensity from 1.0 → 0.0 over blindness_fade_time
	#   3. Reset state on finish
	_blindness_tween = create_tween()
	_blindness_tween.set_trans(Tween.TRANS_SINE)
	_blindness_tween.set_ease(Tween.EASE_IN)

	# Step 1: hold
	_blindness_tween.tween_interval(blindness_hold_time)

	# Step 2: fade overlay
	_blindness_tween.tween_method(
		_set_overlay_intensity,
		1.0,   # from
		0.0,   # to
		blindness_fade_time
	)

	# Step 3: reset everything
	_blindness_tween.tween_callback(_reset_blindness)


func _set_overlay_intensity(value: float) -> void:
	_overlay_material.set_shader_parameter("corruption_intensity", value)


## Returns the normalized gaze meter value (0.0–1.0) for external systems.
func get_gaze_normalized() -> float:
	return gaze_meter / 100.0


func _reset_blindness() -> void:
	gaze_meter = 0.0
	is_blinded = false
	_overlay_material.set_shader_parameter("corruption_intensity", 0.0)
	_blindness_tween = null