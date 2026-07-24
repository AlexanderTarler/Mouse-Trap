extends Node3D
## Sanity/Gaze Controller — modular system attached to the player's Camera3D.
## Staring at an Entity builds a gaze meter that triggers escalating
## audio/visual hallucinations, culminating in a 3-second "blindness" climax.
##
## FIXED ARCHITECTURE:
##   The shader "corruption_intensity" and the audio are now driven ENTIRELY
##   by entity_seen (whether the player is looking at the Entity). They are
##   COMPLETELY independent of the gaze meter and blindness climax.
##
##   SHADER: Interpolates toward 1.0 while entity_seen, toward 0.0 when not.
##           Rate: 0.6/s up (≈1.7s to full), 0.3/s down (≈3.3s to empty).
##           This reaches FULL SCREEN while staring and sustains there.
##
##   AUDIO: loop=true. Plays at audio_max_volume while entity_seen is true.
##          Stops when entity_seen becomes false. The loop keeps it playing
##          continuously without cutting out.
##
##   GAZE METER + BLINDNESS CLIMAX (legacy, preserved):
##          The gaze meter still builds at build_rate/s and triggers the
##          blindness climax when it hits 100. However, the climax no longer
##          kills the audio or resets the shader — it only creates a brief
##          "overlay flash" via a separate blind_effect ColorRect (if present).
##          The corruption_intensity stays at 1.0 throughout the climax
##          because entity_seen is still true (the player is still staring).
##          After the climax, the gaze meter resets and rebuilds.

# ============================================================
# Exported parameters
# ============================================================

## How fast the gaze meter fills (points per second). At 50.0, it reaches climax in ~2s.
@export var build_rate: float = 50.0

## How fast the gaze meter decays when NOT looking (points per second).
@export var decay_rate: float = 15.0

## Maximum distance the raycast checks for the entity.
@export var max_ray_distance: float = 50.0

## Volume when audio is playing (linear, 0.0–1.0).
@export var audio_volume: float = 0.8

## Pitch scale when audio is playing.
@export var audio_pitch: float = 1.3

## How fast the shader rises toward 1.0 while staring (per second).
## At 0.6/s, reaches full in ~1.7 seconds.
@export var shader_rise_speed: float = 0.6

## How fast the shader falls toward 0.0 when not staring (per second).
## At 0.3/s, reaches zero in ~3.3 seconds.
@export var shader_fall_speed: float = 0.3

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

## Current shader intensity (0.0–1.0). Interpolated smoothly via entity_seen.
var _shader_intensity: float = 0.0

## Whether the entity was seen on the previous frame.
var _prev_entity_seen: bool = false

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
	# Configure raycast at runtime
	_raycast.target_position = Vector3(0.0, 0.0, -max_ray_distance)
	_raycast.collision_mask = 1 << 4
	_raycast.exclude_parent = true
	_raycast.enabled = true
	print("[Sanity] Initialized. RayCast mask=%d (layer 5), dist=%.0f" % [_raycast.collision_mask, max_ray_distance])

	# Load the audio stream dynamically (avoids broken UID references in .tscn)
	_audio.stream = load("res://assets/audio/Entity/Entity_Seen.ogg")
	_audio.bus = &"SFX"
	_audio.stop()
	# Enable looping so audio plays continuously while staring
	if _audio.stream is AudioStreamOggVorbis:
		_audio.stream.loop = true
	print("[Sanity] Audio loop enabled. Loaded: Entity_Seen.ogg on bus SFX")

	# Create the ShaderMaterial dynamically and attach to the ColorRect
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = load("res://shaders/sanity_overlay.gdshader")
	_overlay_material.set_shader_parameter("corruption_intensity", 0.0)
	_overlay.material = _overlay_material
	print("[Sanity] ShaderMaterial created and attached to SanityOverlay")


func _physics_process(delta: float) -> void:
	# --------------------------------------------------------
	# NIGHT GATE: Hallucinations only work from Night 2 onward.
	# Before Night 2, the Entity is inactive and the player
	# should NOT experience sanity/gaze effects even if they
	# look in the Entity's direction.
	# --------------------------------------------------------
	var nm = get_node_or_null("/root/NightManager")
	if nm and "current_night" in nm and nm.current_night < 2:
		# Before Night 2 — suppress all hallucination effects
		if _shader_intensity > 0.0:
			_shader_intensity = move_toward(_shader_intensity, 0.0, shader_fall_speed * delta)
			_overlay_material.set_shader_parameter("corruption_intensity", _shader_intensity)
		if _prev_entity_seen:
			_audio.stop()
			_prev_entity_seen = false
		if gaze_meter > 0.0:
			gaze_meter = maxf(gaze_meter - decay_rate * delta, 0.0)
		return
	
	# --------------------------------------------------------
	# Gaze detection — two-step cone + occlusion
	# --------------------------------------------------------
	var entity_seen: bool = false
	var entity_node = get_tree().get_first_node_in_group("entity")
	
	# Also check if the entity is actually active — if it's
	# dormant/inactive, don't trigger hallucination effects.
	if entity_node and entity_node.has_method("is_active") and not entity_node.is_active():
		entity_node = null
	
	if entity_node:
		var cam = get_viewport().get_camera_3d()
		if cam:
			var entity_target = entity_node.global_position + Vector3(0, 1.0, 0)
			var dir_to_entity = (entity_target - cam.global_position).normalized()
			var cam_forward = -cam.global_transform.basis.z.normalized()
			
			# STEP 1: Vision cone — dot > 0.85 (~31° cone)
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
		print("[Sanity] entity_seen=%s gaze=%.1f shader=%.2f" % [entity_seen, gaze_meter, _shader_intensity])

	# --------------------------------------------------------
	# SHADER — driven SOLELY by entity_seen (not by gaze meter)
	# --------------------------------------------------------
	if entity_seen:
		_shader_intensity = move_toward(_shader_intensity, 1.0, shader_rise_speed * delta)
		_overlay_material.set_shader_parameter("corruption_intensity", _shader_intensity)
	else:
		_shader_intensity = move_toward(_shader_intensity, 0.0, shader_fall_speed * delta)
		_overlay_material.set_shader_parameter("corruption_intensity", _shader_intensity)

	# --------------------------------------------------------
	# AUDIO — driven SOLELY by entity_seen (edge-detected to
	# avoid restarts on every frame). loop=true keeps it going.
	# --------------------------------------------------------
	if entity_seen and not _prev_entity_seen:
		# Just started looking — play at max volume
		_audio.volume_db = linear_to_db(audio_volume)
		_audio.pitch_scale = audio_pitch
		_audio.play()
	elif not entity_seen and _prev_entity_seen:
		# Just looked away — stop
		_audio.stop()

	_prev_entity_seen = entity_seen

	# --------------------------------------------------------
	# GAZE METER — builds while looking, decays while not.
	# Triggers blindness climax when full.
	# DOES NOT affect shader or audio — those are independent.
	# --------------------------------------------------------
	if entity_seen and not is_blinded:
		gaze_meter = minf(gaze_meter + build_rate * delta, 100.0)
	elif not is_blinded:
		gaze_meter = maxf(gaze_meter - decay_rate * delta, 0.0)

	if gaze_meter >= 100.0 and not is_blinded:
		_trigger_blindness()
		# NOTE: _trigger_blindness no longer stops audio or resets shader
		# The blindness climax only manages its own tween.

	if is_blinded:
		return  # Skip gaze meter update during climax (tween handles state)


# ============================================================
# Blindness climax — visual-only flash effect
# Does NOT stop audio or reset shader.
# ============================================================

func _trigger_blindness() -> void:
	is_blinded = true

	# Cancel any previous tween that might be lingering
	if _blindness_tween and _blindness_tween.is_valid():
		_blindness_tween.kill()

	# Create the blindness tween sequence.
	# The shader intensity is already at or near 1.0 (driven by entity_seen),
	# so we don't need to snap it — we just hold and then let entity_seen
	# resume driving the intensity when the climax ends.
	_blindness_tween = create_tween()
	_blindness_tween.set_trans(Tween.TRANS_SINE)
	_blindness_tween.set_ease(Tween.EASE_IN)

	# Step 1: short interval
	_blindness_tween.tween_interval(blindness_hold_time)

	# Step 2: No fade needed — the shader stays where entity_seen put it.
	# The climax just marks time, then resets the gaze meter.
	_blindness_tween.tween_callback(_reset_blindness)


func _reset_blindness() -> void:
	gaze_meter = 0.0
	is_blinded = false
	_blindness_tween = null