extends Node

## Controls the scene's lighting to create a day/night cycle.
## Smoothly transitions the WorldEnvironment and DirectionalLight3D
## between day and night settings based on the GameTime autoload.
## Controls both the Sun (for day) and Moon (for night) lights.

## Reference to the WorldEnvironment node
@export var world_environment: WorldEnvironment

## Reference to the Sun directional light (used during day)
@export var sun_light: DirectionalLight3D

## Reference to the Moon directional light (used during night)
@export var moon_light: DirectionalLight3D

## Reference to the sky shader material (ShaderMaterial with sun parameters)
@export var sky_material: Material

## Reference to the entity scene (spawned at night, despawned during day)
@export var entity_scene: PackedScene

## Reference to the Player node (assigned to entity as target)
@export var player_node: Node3D

## Reference to the spawned entity instance
var _entity_instance: Node3D = null

## Debug timer for logging sun state
var _debug_timer: float = 0.0


## Day sky color (bright blue sky)
@export var day_sky_color: Color = Color(0.45, 0.7, 1.0, 1.0)

## Night sky color
@export var night_sky_color: Color = Color(0.02, 0.02, 0.03, 1.0)

## Day ambient light (bright, warm ambient)
@export var day_ambient: Color = Color(0.85, 0.9, 1.0, 1.0)

## Night ambient light (near-black for true darkness)
@export var night_ambient: Color = Color(0.01, 0.01, 0.02, 1.0)

## Day light energy (bright sun)
@export var day_light_energy: float = 5.0

## Night light energy (moon) — very dim for true darkness
@export var night_light_energy: float = 0.05

## Day fog density (0 = no fog during day)
@export var day_fog_density: float = 0.0

## Night fog density
@export var night_fog_density: float = 0.015

## Day light color (warm sunlight)
@export var day_light_color: Color = Color(1.0, 0.95, 0.9, 1.0)

## Night light color (moonlight)
@export var night_light_color: Color = Color(0.3, 0.3, 0.5, 1.0)


func _ready() -> void:
	# Try to find GameTime singleton with fallback
	var gt = _get_game_time()
	if gt:
		gt.time_changed.connect(_update_lighting)
		gt.night_started.connect(_spawn_entity)
		gt.day_started.connect(_despawn_entity)
		# Apply initial state immediately
		_update_lighting(gt.cycle_progress, gt.is_day)
		print("DayNightController initialized: is_day=%s, progress=%.2f" % [gt.is_day, gt.cycle_progress])
	else:
		# Retry next frame in case autoloads aren't ready yet
		call_deferred("_retry_init")


## Safely retrieves the GameTime singleton via multiple methods.
func _get_game_time():
	if Engine.has_singleton("GameTime"):
		return Engine.get_singleton("GameTime")
	# Fallback: try to find it in the scene tree
	if has_node("/root/GameTime"):
		return get_node("/root/GameTime")
	return null


## Retries initialization on the next frame.
func _retry_init() -> void:
	var gt = _get_game_time()
	if gt:
		gt.time_changed.connect(_update_lighting)
		gt.night_started.connect(_spawn_entity)
		gt.day_started.connect(_despawn_entity)
		_update_lighting(gt.cycle_progress, gt.is_day)
		print("DayNightController initialized (deferred): is_day=%s, progress=%.2f" % [gt.is_day, gt.cycle_progress])
	else:
		push_error("DayNightController: GameTime singleton not found after retry!")


## Spawns the entity at a random map edge when night falls.
func _spawn_entity() -> void:
	if not entity_scene or _entity_instance:
		return
	_entity_instance = entity_scene.instantiate()
	add_child(_entity_instance)
	# Force the entity to be visible and active immediately
	_entity_instance.visible = true
	if _entity_instance.has_method("activate"):
		_entity_instance.activate()
	if _entity_instance.has_method("spawn_at_map_edge"):
		_entity_instance.spawn_at_map_edge()
	# Assign the player as the entity's target if it has a target property
	if _entity_instance.has_method("set_target") and player_node:
		_entity_instance.set_target(player_node)
	elif _entity_instance.get("target") != null and player_node:
		_entity_instance.target = player_node
	print("Entity spawned by DayNightController and activated")


## Despawns the entity when day breaks.
func _despawn_entity() -> void:
	if _entity_instance:
		_entity_instance.queue_free()
		_entity_instance = null
		print("Entity despawned by DayNightController")


## Fallback: poll GameTime directly every frame to ensure lighting updates
func _process(delta: float) -> void:
	var gt = _get_game_time()
	if gt:
		_update_lighting(gt.cycle_progress, gt.is_day)
	
	# Debug: log sun state every 10 seconds
	_debug_timer += delta
	if _debug_timer >= 10.0:
		_debug_timer = 0.0
		_debug_log_sun_state()


func _debug_log_sun_state() -> void:
	print("=== SUN DEBUG ===")
	if sun_light:
		var rot = sun_light.rotation
		var light_dir = -sun_light.global_transform.basis.z
		var light_to_dir = -light_dir
		print("  Sun node exists: true")
		print("  Sun visible: ", sun_light.visible)
		print("  Sun light_energy: ", sun_light.light_energy)
		print("  Sun sky_mode: ", sun_light.sky_mode)
		print("  Sun rotation (deg): x=%.1f, y=%.1f, z=%.1f" % [rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z)])
		print("  Light direction (shines toward): (%.3f, %.3f, %.3f)" % [light_dir.x, light_dir.y, light_dir.z])
		print("  LIGHT0_DIRECTION (toward light): (%.3f, %.3f, %.3f)" % [light_to_dir.x, light_to_dir.y, light_to_dir.z])
		print("  LIGHT0_DIRECTION.y (shader blend): %.3f" % light_to_dir.y)
		print("  Sun angle above horizon: %.1f degrees" % rad_to_deg(asin(light_to_dir.y)))
	else:
		print("  Sun node: null!")
	
	if moon_light:
		print("  Moon visible: ", moon_light.visible)
		print("  Moon light_energy: ", moon_light.light_energy)
		print("  Moon sky_mode: ", moon_light.sky_mode)
	
	if sky_material:
		var proc_sky = sky_material as ProceduralSkyMaterial
		if proc_sky:
			print("  Sky material: ProceduralSkyMaterial")
			print("  sun_angle_max: ", proc_sky.sun_angle_max)
			print("  sky_top_color: ", proc_sky.sky_top_color)
			print("  sky_horizon_color: ", proc_sky.sky_horizon_color)
		else:
			var shader_mat = sky_material as ShaderMaterial
			if shader_mat:
				var sun_scale = shader_mat.get_shader_parameter(&"sun_scale")
				var sun_strength = shader_mat.get_shader_parameter(&"sun_strength")
				var sun_color = shader_mat.get_shader_parameter(&"sun_color")
				var use_dir = shader_mat.get_shader_parameter(&"use_directional_light")
				var day_night = shader_mat.get_shader_parameter(&"day_night_mix")
				print("  Sky material: ShaderMaterial")
				print("  use_directional_light: ", use_dir)
				print("  day_night_mix: ", day_night)
				print("  sun_scale: ", sun_scale)
				print("  sun_strength: ", sun_strength)
				print("  sun_color: ", sun_color)
			else:
				print("  Sky material: ", sky_material.get_class(), " (unknown type)")
	else:
		print("  Sky material: null!")
	
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		print("  Background mode: ", env.background_mode)
		print("  Ambient light energy: ", env.ambient_light_energy)
		print("  Tonemap exposure: ", env.tonemap_exposure)
	else:
		print("  WorldEnvironment or its environment: null!")
	print("=================")


func _update_sky_material(t: float, is_day: bool) -> void:
	"""Update the sky material colors and shader parameters.
	Supports both ProceduralSkyMaterial and custom ShaderMaterial."""
	if not sky_material:
		return
	
	# Handle ProceduralSkyMaterial (built-in Godot sky)
	var proc_sky = sky_material as ProceduralSkyMaterial
	if proc_sky:
		# Make the sun disk large and visible
		proc_sky.sun_angle_max = 10.0
		
		if is_day:
			# Day: bright blue sky
			proc_sky.sky_top_color = Color(0.45, 0.7, 1.0)  # Bright blue
			proc_sky.sky_horizon_color = Color(0.75, 0.85, 0.85)  # Light blue-white
			proc_sky.ground_bottom_color = Color(0.3, 0.25, 0.2)  # Brownish ground
			proc_sky.ground_horizon_color = Color(0.5, 0.55, 0.5)  # Greenish horizon
		else:
			# Night: dark sky
			proc_sky.sky_top_color = Color(0.02, 0.02, 0.03)  # Near-black
			proc_sky.sky_horizon_color = Color(0.1, 0.15, 0.2)  # Dark blue-gray
			proc_sky.ground_bottom_color = Color(0.01, 0.01, 0.01)  # Black ground
			proc_sky.ground_horizon_color = Color(0.05, 0.05, 0.05)  # Dark ground
		
		# The sun disk visibility is controlled by:
		# - DirectionalLight3D.sky_mode = SKY_MODE_LIGHT_AND_SKY (set in _update_lighting)
		# - DirectionalLight3D.light_energy (set in _update_lighting)
		# - ProceduralSkyMaterial.sun_angle_max (set above)
		return
	
	# Handle custom ShaderMaterial (e.g. the custom sky shader)
	var shader_mat = sky_material as ShaderMaterial
	if shader_mat:
		if is_day:
			# Day phase: t=0 = full day, t=1 = dusk
			var mix_val = 0.8 * (1.0 - t)
			shader_mat.set_shader_parameter(&"day_night_mix", mix_val)
			shader_mat.set_shader_parameter(&"sun_scale", 1.0)
			shader_mat.set_shader_parameter(&"sun_strength", 2.0)
		else:
			# Night phase: t=0 = full night, t=1 = dawn
			var mix_val = -0.8 * (1.0 - t)
			shader_mat.set_shader_parameter(&"day_night_mix", mix_val)


func _update_lighting(progress: float, is_day: bool) -> void:
	if not world_environment or not world_environment.environment: 
		return
	
	var env = world_environment.environment
	var t = progress 

	if is_day:
		# --- Environment ---
		env.ambient_light_energy = lerp(0.6, 0.05, t) 
		env.ambient_light_color = Color.WHITE.lerp(Color(0.2, 0.2, 0.3), t)
		env.tonemap_exposure = lerp(1.2, 0.8, t)
		
		# --- Sun (The Light that casts shadows and renders the sun disk) ---
		if sun_light:
			sun_light.light_energy = day_light_energy * (1.0 - t) # Fade out as dusk hits
			sun_light.visible = true
			# Set sky mode to 0 (SKY_MODE_LIGHT_AND_SKY) so the sky shader renders the sun disk
			# Using integer directly because enum constants may not resolve correctly
			sun_light.sky_mode = 0
			# Rotation: full 180-degree arc
			# t=0 (morning): -180° (east horizon)
			# t=0.5 (noon):   -90° (zenith)
			# t=1 (evening):    0° (west horizon)
			sun_light.rotation.x = deg_to_rad(-180.0 + (t * 180.0))
			sun_light.rotation.y = deg_to_rad(t * 180.0) # Sweep east to west
		
		# --- Moon (inactive during day) ---
		if moon_light:
			moon_light.light_energy = 0.0
			moon_light.visible = false
			moon_light.sky_mode = 1 # SKY_MODE_LIGHT_ONLY
	else:
		# --- Environment ---
		env.ambient_light_energy = lerp(0.05, 0.6, t)
		env.tonemap_exposure = lerp(0.8, 1.2, t)
		
		# --- Moon (active during night) ---
		if moon_light:
			moon_light.light_energy = night_light_energy * (1.0 - t)
			moon_light.visible = true
			moon_light.sky_mode = 0 # SKY_MODE_LIGHT_AND_SKY
			moon_light.rotation.x = deg_to_rad(-180.0 + (t * 180.0))
			moon_light.rotation.y = deg_to_rad(t * 180.0)
		
		# --- Sun (inactive during night) ---
		if sun_light:
			sun_light.light_energy = 0.0
			sun_light.visible = false
			sun_light.sky_mode = 1 # SKY_MODE_LIGHT_ONLY

	# Update the visual sky colors and shader parameters
	_update_sky_material(t, is_day)
