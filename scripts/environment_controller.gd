extends Node

## EnvironmentController - Controls the visual day/night cycle with SMOOTH transitions.
## Manages the WorldEnvironment, Sun (DirectionalLight3D), and Moon (DirectionalLight3D).
##
## This controller has its OWN built-in timer as a fallback, so it works even if
## the GameTime autoload is not available. It will also connect to GameTime if present.
##
## CRITICAL: The sky_mode property on DirectionalLight3D determines which light's
## disk is rendered in the ProceduralSky. Only the light with SKY_MODE_LIGHT_AND_SKY
## will show its disk. We swap this between Sun and Moon depending on the phase.
##
## SMOOTH TRANSITIONS:
## Every frame, the sun angle is calculated from cycle_progress mapped to the full
## 360-degree range (0 to TAU radians). Light energies, sky colors, fog density,
## and ambient light are all smoothly interpolated using the sun's height above
## the horizon — no binary snapping between day/night states.

## Reference to the WorldEnvironment node
@export var world_environment: WorldEnvironment

## Reference to the Sun DirectionalLight3D
@export var sun: DirectionalLight3D

## Reference to the Moon DirectionalLight3D
@export var moon: DirectionalLight3D

## Total duration of one full day/night cycle in seconds (10 minutes = 600s)
@export var cycle_duration: float = 600.0

## The ProceduralSkyMaterial to modify at runtime
var _sky_material: ProceduralSkyMaterial

## The Environment resource to modify at runtime
var _environment: Environment

## Current cycle progress (0.0 to 1.0)
var cycle_progress: float = 0.0

## Whether it is currently day (true) or night (false)
var is_day: bool = true

## Internal elapsed time for the fallback timer
var _elapsed: float = 0.0

## Maximum retry attempts for finding GameTime
var _find_gt_attempts: int = 0
const _MAX_FIND_GT_ATTEMPTS: int = 60

## --- Night fog fluctuation ---
## Elapsed time used to drive the fog fluctuation noise
var _fog_noise_time: float = 0.0

## Base fog density factor for the current night (randomized each night)
var _night_fog_base: float = 1.0

## Whether we've initialized fog for the current night
var _fog_initialized: bool = false


func _ready() -> void:
	# Get the Environment resource from the WorldEnvironment
	if world_environment:
		_environment = world_environment.environment
		if _environment and _environment.sky:
			_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
			if not _sky_material:
				push_warning("EnvironmentController: Sky material is not ProceduralSkyMaterial. Sun disk may not render.")
	else:
		push_error("EnvironmentController: WorldEnvironment not assigned!")
		return
	
	# Initialize sky modes immediately
	_update_sky_modes(true)
	
	# Apply initial state
	_apply_cycle()
	
	# Try to find GameTime via the scene tree (autoloads are children of /root)
	_find_game_time()
	
	print("EnvironmentController initialized. Sky material: ", _sky_material != null)


func _find_game_time() -> void:
	_find_gt_attempts += 1
	if _find_gt_attempts > _MAX_FIND_GT_ATTEMPTS:
		print("EnvironmentController: GameTime not found after %d attempts, using built-in timer." % _MAX_FIND_GT_ATTEMPTS)
		return
	
	# Find GameTime via the scene tree (autoloads are children of /root)
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		gt.time_changed.connect(_on_game_time_changed)
		# Sync with GameTime's current state
		cycle_progress = gt.cycle_progress
		is_day = gt.is_day
		_update_sky_modes(is_day)
		_apply_cycle()
		print("EnvironmentController: Connected to GameTime.")
	else:
		# Retry next frame — GameTime might not be ready yet
		call_deferred("_find_game_time")


func _process(delta: float) -> void:
	if not _environment or not _sky_material:
		return
	
	# Advance the fog noise timer every frame so the fog density
	# fluctuates smoothly even when the cycle is paused.
	_fog_noise_time += delta
	
	# If GameTime is NOT available, use our own timer
	var gt = get_node_or_null("/root/GameTime")
	if not gt:
		_elapsed += delta
		cycle_progress = fmod(_elapsed / cycle_duration, 1.0)
		is_day = cycle_progress < 0.5
		_apply_cycle()
	# If GameTime IS available, the signal handler keeps us in sync.
	# No need to poll every frame — _on_game_time_changed handles updates.


func _on_game_time_changed(progress: float) -> void:
	cycle_progress = progress
	is_day = progress < 0.5
	_apply_cycle()


func _apply_cycle() -> void:
	# --- Calculate the continuous sun angle ---
	# Map cycle_progress (0.0 to 1.0) to a full 360-degree rotation (0 to TAU).
	# At progress 0.0 (midnight), the sun is at its lowest (angle = 0).
	# At progress 0.25 (mid-afternoon), the sun is high in the sky.
	# At progress 0.5 (sunset), the sun is at the horizon.
	# At progress 0.75 (midnight), the sun is at its lowest again.
	var sun_angle: float = cycle_progress * TAU
	
	# The sun's height above the horizon: sin(sun_angle).
	# Positive = above horizon (day), Negative = below horizon (night).
	# At progress 0.25 (mid-afternoon), sin(0.25 * TAU) = sin(PI/2) = 1.0 (zenith).
	# At progress 0.5 (sunset), sin(0.5 * TAU) = sin(PI) = 0.0 (horizon).
	# At progress 0.75 (midnight), sin(0.75 * TAU) = sin(3*PI/2) = -1.0 (nadir).
	var sun_height: float = sin(sun_angle)
	
	# Day factor: 1.0 = full day, 0.0 = full night.
	# Smoothly transitions through the horizon (sun_height crosses 0).
	# We use a smoothstep-like transition in the range -0.2 to 0.2 for a
	# natural dusk/dawn glow that lasts a few minutes of game time.
	var raw_day_factor: float = sun_height / 0.4  # -1 to 1 mapped to -5 to 5
	var day_factor: float = clampf((raw_day_factor + 1.0) / 2.0, 0.0, 1.0)
	
	# --- 1. Rotate the Sun and Moon ---
	_update_light_rotations(sun_angle)
	
	# --- 2. Swap sky_mode so the correct light shows its disk ---
	_update_sky_modes(sun_height)
	
	# --- 3. Update environment settings (smoothly interpolated) ---
	_update_environment(day_factor, sun_height)
	
	# --- 4. Update light colors and energies (smoothly interpolated) ---
	_update_light_appearance(day_factor, sun_height)


func _update_light_rotations(p_sun_angle: float) -> void:
	# The sun rotates through the full 360-degree range.
	# DirectionalLight3D points along the negative Z axis of its local transform.
	# Rotating around X tilts the light forward/backward.
	#
	# sun_angle 0.0   -> rotation.x = 0       (midnight, pointing horizontally)
	# sun_angle PI/2  -> rotation.x = -PI/2   (noon, pointing straight down)
	# sun_angle PI    -> rotation.x = -PI     (sunset, pointing horizontally opposite)
	# sun_angle 3*PI/2 -> rotation.x = -3*PI/2 (midnight, pointing straight up)
	
	# The sun's rotation.x follows the angle directly.
	# We offset by -PI/2 so that at sun_angle = 0, the sun is at the horizon
	# (rotation.x = -PI/2), and at sun_angle = PI/2, it's at zenith (rotation.x = -PI).
	var sun_rotation_x: float = -PI / 2.0 - p_sun_angle
	
	if sun:
		sun.rotation.x = sun_rotation_x
	if moon:
		# The moon is always on the opposite side of the sky
		moon.rotation.x = sun_rotation_x + PI


func _update_sky_modes(p_sun_height: float) -> void:
	# Swap sky_mode at the moment the sun crosses the horizon.
	# When sun_height > 0, the sun is above the horizon → day mode.
	# When sun_height <= 0, the moon should show its disk.
	if sun and moon:
		if p_sun_height > 0.0:
			sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
			moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		else:
			moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
			sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY


func _update_environment(p_day_factor: float, p_sun_height: float) -> void:
	if not _environment or not _sky_material:
		return
	
	# --- Sky colors: smoothly lerp between day and night ---
	var day_sky_top: Color = Color(0.4, 0.6, 1.0)
	var day_sky_horizon: Color = Color(0.7, 0.8, 1.0)
	var day_ground_bottom: Color = Color(0.2, 0.15, 0.1)
	
	var night_sky_top: Color = Color(0.02, 0.02, 0.05)
	var night_sky_horizon: Color = Color(0.05, 0.05, 0.08)
	var night_ground_bottom: Color = Color(0.01, 0.01, 0.01)
	
	_sky_material.sky_top_color = day_sky_top.lerp(night_sky_top, 1.0 - p_day_factor)
	_sky_material.sky_horizon_color = day_sky_horizon.lerp(night_sky_horizon, 1.0 - p_day_factor)
	_sky_material.ground_bottom_color = day_ground_bottom.lerp(night_ground_bottom, 1.0 - p_day_factor)
	
	# Sun angle max: slightly wider during day for a softer glow
	_sky_material.sun_angle_max = lerpf(8.0, 10.0, p_day_factor)
	
	# --- Ambient light: smoothly dim at night ---
	# Night ambient is intentionally low to create a dark, tense atmosphere.
	# The player relies on the flashlight, moonlight, and cabin lights to see.
	_environment.ambient_light_energy = lerpf(0.175, 0.7, p_day_factor)
	_environment.ambient_light_color = Color(0.04, 0.05, 0.12).lerp(
		Color(0.7, 0.75, 1.0), p_day_factor
	)
	_environment.ambient_light_sky_contribution = lerpf(0.3, 0.5, p_day_factor)
	
	# --- Tonemap exposure: slightly brighter at night to compensate ---
	_environment.tonemap_exposure = lerpf(1.1, 1.2, p_day_factor)
	
	# --- Volumetric fog: smoothly thickens through dusk, then fluctuates at night ---
	# Fog only appears when the sun is near or below the horizon.
	# We use a smooth transition centered on sun_height = 0.
	# When sun_height > 0.1 (well above horizon), fog is disabled.
	# When sun_height < -0.1 (well below horizon), fog is at full night density.
	var fog_factor: float = clampf(1.0 - (p_sun_height + 0.1) / 0.2, 0.0, 1.0)
	
	# --- Night fog fluctuation ---
	# Once we're fully into night (fog_factor >= 1.0), the fog density
	# oscillates up and down using a combination of sine waves to create
	# an organic ebb-and-flow effect. This makes the night feel alive
	# and unpredictable — fog banks rolling in and out.
	#
	# The fluctuation uses two sine waves at different frequencies:
	#   - A slow wave (period ~60s) for the main swell
	#   - A faster wave (period ~20s) for subtle texture
	# The result is a multiplier between 0.3 and 1.3 applied to the base fog.
	var fog_fluctuation: float = 1.0
	if fog_factor >= 0.99:
		# Randomize the base fog density each night for variety
		if not _fog_initialized:
			_night_fog_base = randf_range(0.7, 1.3)
			_fog_initialized = true
		
		# Two sine waves combined for organic fluctuation
		var slow_wave: float = sin(_fog_noise_time * 0.1) * 0.35
		var fast_wave: float = sin(_fog_noise_time * 0.3 + 1.2) * 0.15
		fog_fluctuation = 1.0 + slow_wave + fast_wave
		# Clamp so fog never fully disappears or gets absurdly thick
		fog_fluctuation = clampf(fog_fluctuation, 0.3, 1.3)
	elif _fog_initialized:
		# Reset when we leave full night (e.g., dawn transition)
		_fog_initialized = false
	
	if fog_factor > 0.01:
		_environment.fog_enabled = true
		_environment.fog_density = 0.0075 * fog_factor * fog_fluctuation * _night_fog_base
		_environment.volumetric_fog_enabled = true
		_environment.volumetric_fog_density = 0.003 * fog_factor * fog_fluctuation * _night_fog_base
		
		# Fog color darkens as night deepens
		var day_fog_color: Color = Color(0.7, 0.75, 0.8)
		var night_fog_color: Color = Color(0.02, 0.02, 0.04)
		_environment.fog_light_color = day_fog_color.lerp(night_fog_color, fog_factor)
	else:
		_environment.fog_enabled = false
		_environment.fog_density = 0.0
		_environment.volumetric_fog_enabled = false


func _update_light_appearance(p_day_factor: float, p_sun_height: float) -> void:
	# --- Sun light energy: smoothly scales with sun height ---
	# When the sun is above the horizon, energy follows the sine of its angle.
	# When below, energy is 0.
	if sun:
		var sun_energy: float = maxf(0.0, p_sun_height) * 2.0  # 0 to 2.0
		sun.light_energy = sun_energy
		sun.light_color = Color(1.0, 0.95, 0.85)
		sun.shadow_enabled = sun_energy > 0.05
		if sun.shadow_enabled:
			sun.shadow_bias = 0.1
			sun.shadow_normal_bias = 0.1
	
	# --- Moon light energy: smoothly scales as sun goes down ---
	if moon:
		# Moon energy is high when the sun is below the horizon.
		# We use the inverse of sun_height, clamped to 0-1, scaled to 0.3.
		var moon_energy: float = maxf(0.0, -p_sun_height) * 0.3  # 0 to 0.3
		moon.light_energy = moon_energy
		moon.light_color = Color(0.5, 0.55, 0.8)
		moon.shadow_enabled = moon_energy > 0.02
		if moon.shadow_enabled:
			moon.shadow_bias = 0.1
			moon.shadow_normal_bias = 0.1
