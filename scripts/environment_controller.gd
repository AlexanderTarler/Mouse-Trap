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

## --- Night darkness tuning (Inspector-editable) ---
## Ambient light energy at full night. Lower = darker.
@export var night_ambient_energy: float = 0.01
## Ambient light color at full night.
@export var night_ambient_color: Color = Color(0.02, 0.02, 0.04)
## Moon light energy multiplier at full night. Lower = darker.
@export var night_moon_energy_mult: float = 0.1
## Tonemap exposure at full night. Lower = darker, but may crush blacks.
@export var night_tonemap_exposure: float = 0.85

## --- Night fog tuning (Inspector-editable) ---
## The night fog has two layers:
##   - Distance fog (depth mode): nothing closer than fog_clear_distance, so it
##     never shows up inside the cabin, thickening to fully opaque at the
##     visibility distance.
##   - Ground fog: the ground_fog FogVolume, densest at ground level and
##     thinning with height, so upstairs windows see over most of it.
## Both scale with the night's thickness (random per night, slow swells,
## +50% from Night 3).
## Distance (m) at which the night fog is fully opaque at normal thickness.
@export var night_fog_visibility: float = 55.0
## No distance fog closer than this (m), so rooms stay clear.
@export var fog_clear_distance: float = 14.0
## Ground fog density at ground level at normal thickness.
@export var night_ground_fog_density: float = 0.04
## FogVolume carrying the ground fog (its material's density is driven here).
@export var ground_fog: FogVolume
## Minimum fog fluctuation multiplier (0.0-1.0). Higher = fog never fully clears at night.
@export var night_fog_fluctuation_min: float = 0.6
## Maximum fog fluctuation multiplier. Higher = thicker fog peaks.
@export var night_fog_fluctuation_max: float = 1.5
## Night fog color.
@export var night_fog_color: Color = Color(0.02, 0.02, 0.04)

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

## Tick accumulator for throttling _process() to 10 Hz (0.1s intervals)
var _env_tick_timer: float = 0.0

# ─── DIRTY CHECK CACHE ───────────────────────────────────────────────────────
## Cached values to avoid redundant shader uniform assignments.
## Only updates that actually change the value will trigger a GPU pipeline flush.
var _cached_sun_sky_mode: int = -1
var _cached_moon_sky_mode: int = -1
var _cached_sun_rotation_x: float = 0.0
var _cached_moon_rotation_x: float = 0.0
var _cached_sky_top_color: Color = Color()
var _cached_sky_horizon_color: Color = Color()
var _cached_ground_bottom_color: Color = Color()
var _cached_sun_angle_max: float = 0.0
var _cached_ambient_energy: float = 0.0
var _cached_ambient_color: Color = Color()
var _cached_ambient_sky_contrib: float = 0.0
var _cached_tonemap_exposure: float = 0.0
var _cached_sun_energy: float = 0.0
var _cached_sun_color: Color = Color()
var _cached_sun_shadow_enabled: bool = false
var _cached_moon_energy: float = 0.0
var _cached_moon_color: Color = Color()
var _cached_moon_shadow_enabled: bool = false
var _cached_fog_enabled: bool = false
var _cached_fog_density: float = 0.0
var _cached_fog_color: Color = Color()
var _cached_vfog_enabled: bool = false
var _cached_vfog_density: float = 0.0
var _cached_fog_depth_end: float = 0.0

## Current distance at which the fog is fully opaque (INF when there is none).
var _fog_visibility: float = INF


## How far the player can see through the fog right now: the distance at
## which the distance fog becomes fully opaque, or INF when there is no fog.
func get_fog_visibility() -> float:
	return _fog_visibility


func _ready() -> void:
	add_to_group("environment_controller")
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
	
	# Editor performance: disable glow in editor viewport.
	# Glow is a full-screen post-processing pass that wastes GPU cycles
	# when viewing the scene in the editor. The game re-enables it at runtime.
	if Engine.is_editor_hint():
		if _environment:
			_environment.glow_enabled = false
	
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
	# --- THROTTLE OPTIMIZATION ---
	# Fog density, color, and volumetric parameters change gradually.
	# Updating at 10 Hz (0.1s) saves CPU without visual degradation.
	_env_tick_timer += delta
	if _env_tick_timer < 0.1:
		return
	_env_tick_timer = 0.0

	if not _environment or not _sky_material:
		return
	
	# Advance the fog noise timer every frame so the fog density
	# fluctuates smoothly even when the cycle is paused.
	_fog_noise_time += delta
	_update_fog_reprojection()
	
	# If GameTime is NOT available, use our own timer
	var gt = get_node_or_null("/root/GameTime")
	if not gt:
		_elapsed += delta
		cycle_progress = fmod(_elapsed / cycle_duration, 1.0)
		is_day = cycle_progress < 0.5
		_apply_cycle()


func _on_game_time_changed(progress: float) -> void:
	cycle_progress = progress
	is_day = progress < 0.5
	_apply_cycle()


## Forces a completely dark "true night" state regardless of the day/night cycle.
## Called during the Night 2.2 van alarm sequence to disorient the player.
## Sets background to solid black, kills ambient light, sun energy, and moon energy.
## The player must rely entirely on their flashlight during this sequence.
func force_true_night() -> void:
	if not _environment:
		print("[EnvironmentController] force_true_night() called but no environment set. Fetching from world_environment.")
		if world_environment:
			_environment = world_environment.environment
	if not _environment:
		push_warning("[EnvironmentController] force_true_night() cannot proceed — no Environment resource.")
		return
	
	# Kill the sky — solid black background
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color.BLACK
	
	# Zero out all ambient light
	_environment.ambient_light_energy = 0.0
	_environment.ambient_light_color = Color.BLACK
	_environment.ambient_light_sky_contribution = 0.0
	
	# Kill sun and moon light entirely
	if sun:
		sun.light_energy = 0.0
	if moon:
		moon.light_energy = 0.0
	
	# Disable fog so it doesn't add any faint glow
	_environment.fog_enabled = false
	_environment.volumetric_fog_enabled = false
	
	# Invalidate cache so restore_cycle() truly re-applies
	_cached_sun_energy = -1.0
	_cached_moon_energy = -1.0
	_cached_fog_enabled = true  # true so the false assignment goes through
	
	print("[EnvironmentController] True night forced. Background=black, ambient=0, sun=0, moon=0.")


## Restores the environment to normal day/night cycle lighting after a forced
## true_night sequence. Re-triggers _apply_cycle() to recalculate all values.
func restore_cycle() -> void:
	# Restore background mode to sky so the procedural sky renders again
	if _environment:
		_environment.background_mode = Environment.BG_SKY
	
	# Force a full cycle refresh to recalculate all lighting values
	_apply_cycle()
	
	print("[EnvironmentController] Cycle restored. Background mode set to BG_SKY.")


func _apply_cycle() -> void:
	# --- Calculate the continuous sun angle ---
	# Map cycle_progress (0.0 to 1.0) to a full 360-degree rotation (0 to TAU).
	var sun_angle: float = cycle_progress * TAU
	
	# The sun's height above the horizon: sin(sun_angle).
	var sun_height: float = sin(sun_angle)
	
	# Day factor: 1.0 = full day, 0.0 = full night.
	var raw_day_factor: float = sun_height / 0.4
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
	var rotation_x: float = -PI / 2.0 - p_sun_angle
	
	if sun:
		if not is_equal_approx(sun.rotation.x, rotation_x):
			sun.rotation.x = rotation_x
	
	if moon:
		var moon_rotation_x: float = rotation_x + PI
		if not is_equal_approx(moon.rotation.x, moon_rotation_x):
			moon.rotation.x = moon_rotation_x


func _update_sky_modes(p_sun_height: float) -> void:
	if not sun or not moon:
		return
	
	var target_sun_mode: int
	var target_moon_mode: int
	if p_sun_height > 0.0:
		target_sun_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
		target_moon_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	else:
		target_moon_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
		target_sun_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	
	if _cached_sun_sky_mode != target_sun_mode:
		sun.sky_mode = target_sun_mode
		_cached_sun_sky_mode = target_sun_mode
	if _cached_moon_sky_mode != target_moon_mode:
		moon.sky_mode = target_moon_mode
		_cached_moon_sky_mode = target_moon_mode


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
	
	var sky_top: Color = day_sky_top.lerp(night_sky_top, 1.0 - p_day_factor)
	if not _cached_sky_top_color.is_equal_approx(sky_top):
		_sky_material.sky_top_color = sky_top
		_cached_sky_top_color = sky_top
	
	var sky_horizon: Color = day_sky_horizon.lerp(night_sky_horizon, 1.0 - p_day_factor)
	if not _cached_sky_horizon_color.is_equal_approx(sky_horizon):
		_sky_material.sky_horizon_color = sky_horizon
		_cached_sky_horizon_color = sky_horizon
	
	var ground_bottom: Color = day_ground_bottom.lerp(night_ground_bottom, 1.0 - p_day_factor)
	if not _cached_ground_bottom_color.is_equal_approx(ground_bottom):
		_sky_material.ground_bottom_color = ground_bottom
		_cached_ground_bottom_color = ground_bottom
	
	# Sun angle max: slightly wider during day for a softer glow
	var sun_angle_max: float = lerpf(8.0, 10.0, p_day_factor)
	if not is_equal_approx(sun_angle_max, _cached_sun_angle_max):
		_sky_material.sun_angle_max = sun_angle_max
		_cached_sun_angle_max = sun_angle_max
	
	# --- Ambient light: smoothly dim at night ---
	var ambient_energy: float = lerpf(night_ambient_energy, 0.7, p_day_factor)
	if not is_equal_approx(ambient_energy, _cached_ambient_energy):
		_environment.ambient_light_energy = ambient_energy
		_cached_ambient_energy = ambient_energy
	
	var ambient_color: Color = night_ambient_color.lerp(Color(0.7, 0.75, 1.0), p_day_factor)
	if not _cached_ambient_color.is_equal_approx(ambient_color):
		_environment.ambient_light_color = ambient_color
		_cached_ambient_color = ambient_color
	
	var ambient_sky_contrib: float = lerpf(0.3, 0.5, p_day_factor)
	if not is_equal_approx(ambient_sky_contrib, _cached_ambient_sky_contrib):
		_environment.ambient_light_sky_contribution = ambient_sky_contrib
		_cached_ambient_sky_contrib = ambient_sky_contrib
	
	# --- Tonemap exposure: slightly darker at night for deeper shadows ---
	var tonemap_exposure: float = lerpf(night_tonemap_exposure, 1.2, p_day_factor)
	if not is_equal_approx(tonemap_exposure, _cached_tonemap_exposure):
		_environment.tonemap_exposure = tonemap_exposure
		_cached_tonemap_exposure = tonemap_exposure
	
	# --- Volumetric fog: smoothly thickens through dusk, then fluctuates at night ---
	var fog_factor: float = clampf(1.0 - (p_sun_height + 0.1) / 0.2, 0.0, 1.0)
	
	# --- Night fog fluctuation ---
	var fog_fluctuation: float = 1.0
	if fog_factor >= 0.99:
		if not _fog_initialized:
			_night_fog_base = randf_range(0.7, 1.3)
			_fog_initialized = true
		
		var slow_wave: float = sin(_fog_noise_time * 0.1) * 0.35
		var fast_wave: float = sin(_fog_noise_time * 0.3 + 1.2) * 0.15
		fog_fluctuation = 1.0 + slow_wave + fast_wave
		fog_fluctuation = clampf(fog_fluctuation, night_fog_fluctuation_min, night_fog_fluctuation_max)
	elif _fog_initialized:
		_fog_initialized = false
	
	if fog_factor > 0.01:
		var fog_enabled: bool = true
		if _cached_fog_enabled != fog_enabled:
			_environment.fog_enabled = fog_enabled
			_cached_fog_enabled = fog_enabled
		
		# ─── BUG 6 FIX: NIGHT 3+ FOG INCREASE (+50%) ────────────────
		# From Night 3 onward, every night has 50% more atmospheric fog
		# than current. Night 1–2 keep the original density. This creates
		# a progressive dread as the nights get later.
		var night_multiplier: float = 1.0
		var fog_nm = get_node_or_null("/root/NightManager")
		if fog_nm and "current_night" in fog_nm and fog_nm.current_night >= 3:
			night_multiplier = 1.5
		
		var thickness: float = fog_factor * fog_fluctuation * _night_fog_base * night_multiplier

		# Distance fog: clear up to fog_clear_distance, fully opaque at the
		# visibility distance (closer when the fog is thicker). In depth mode
		# fog_density is the opacity reached at fog_depth_end.
		_environment.fog_mode = Environment.FOG_MODE_DEPTH
		_environment.fog_depth_begin = fog_clear_distance
		_fog_visibility = fog_clear_distance + (night_fog_visibility - fog_clear_distance) / maxf(thickness, 0.05)
		if not is_equal_approx(_fog_visibility, _cached_fog_depth_end):
			_environment.fog_depth_end = _fog_visibility
			_cached_fog_depth_end = _fog_visibility
		if not is_equal_approx(fog_factor, _cached_fog_density):
			_environment.fog_density = fog_factor
			_cached_fog_density = fog_factor

		var vfog_enabled: bool = true
		if _cached_vfog_enabled != vfog_enabled:
			_environment.volumetric_fog_enabled = vfog_enabled
			_cached_vfog_enabled = vfog_enabled

		# Ground fog lives in the ground_fog volume only; the global volumetric
		# density stays 0 so there is no fog up high or inside the cabin.
		var vfog_density: float = night_ground_fog_density * thickness
		if not is_equal_approx(vfog_density, _cached_vfog_density):
			_environment.volumetric_fog_density = 0.0
			_set_ground_fog_density(vfog_density)
			_cached_vfog_density = vfog_density
		
		var day_fog_color: Color = Color(0.7, 0.75, 0.8)
		var fog_color: Color = day_fog_color.lerp(night_fog_color, fog_factor)
		if not _cached_fog_color.is_equal_approx(fog_color):
			_environment.fog_light_color = fog_color
			_cached_fog_color = fog_color
	else:
		if _cached_fog_enabled != false:
			_environment.fog_enabled = false
			_cached_fog_enabled = false
		if not is_equal_approx(_cached_fog_density, 0.0):
			_environment.fog_density = 0.0
			_cached_fog_density = 0.0
		if _cached_vfog_enabled != false:
			_environment.volumetric_fog_enabled = false
			_cached_vfog_enabled = false
		if not is_equal_approx(_cached_vfog_density, 0.0):
			_set_ground_fog_density(0.0)
			_cached_vfog_density = 0.0
		_fog_visibility = INF


## Volumetric fog blends every frame with the previous ones (temporal
## reprojection) to hide its noise. When the camera moves, that drags fog from
## outside through the walls into the cabin: a haze in the rooms that grew
## the more the player moved. Indoors it is off, so the FogVolume erasers keep
## the rooms clear; outdoors it stays on and keeps the fog smooth.
func _update_fog_reprojection() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var inside: bool = player != null and player.has_method("get_player_room") and player.get_player_room() != "Outside"
	if _environment.volumetric_fog_temporal_reprojection_enabled == inside:
		_environment.volumetric_fog_temporal_reprojection_enabled = not inside


func _set_ground_fog_density(value: float) -> void:
	if ground_fog and ground_fog.material is FogMaterial:
		(ground_fog.material as FogMaterial).density = value


func _update_light_appearance(p_day_factor: float, p_sun_height: float) -> void:
	# --- Sun light energy: smoothly scales with sun height ---
	if sun:
		var sun_energy: float = maxf(0.0, p_sun_height) * 2.0
		if not is_equal_approx(sun_energy, _cached_sun_energy):
			sun.light_energy = sun_energy
			_cached_sun_energy = sun_energy
		
		var sun_color: Color = Color(1.0, 0.95, 0.85)
		if not _cached_sun_color.is_equal_approx(sun_color):
			sun.light_color = sun_color
			_cached_sun_color = sun_color
		
		var sun_shadow_enabled: bool = sun_energy > 0.05
		if _cached_sun_shadow_enabled != sun_shadow_enabled:
			sun.shadow_enabled = sun_shadow_enabled
			_cached_sun_shadow_enabled = sun_shadow_enabled
			if sun.shadow_enabled:
				sun.shadow_bias = 0.1
				sun.shadow_normal_bias = 0.1
	
	# --- Moon light energy: smoothly scales as sun goes down ---
	if moon:
		var moon_energy: float = maxf(0.0, -p_sun_height) * night_moon_energy_mult
		if not is_equal_approx(moon_energy, _cached_moon_energy):
			moon.light_energy = moon_energy
			_cached_moon_energy = moon_energy
		
		var moon_color: Color = Color(0.5, 0.55, 0.8)
		if not _cached_moon_color.is_equal_approx(moon_color):
			moon.light_color = moon_color
			_cached_moon_color = moon_color
		
		var moon_shadow_enabled: bool = moon_energy > 0.02
		if _cached_moon_shadow_enabled != moon_shadow_enabled:
			moon.shadow_enabled = moon_shadow_enabled
			_cached_moon_shadow_enabled = moon_shadow_enabled
			if moon.shadow_enabled:
				moon.shadow_bias = 0.1
				moon.shadow_normal_bias = 0.1