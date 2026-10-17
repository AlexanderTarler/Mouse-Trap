class_name MenuBackdrop
extends Node3D
## Behind the main menu: the cabin at night, seen from the treeline. Fog, a
## lit window, the wind, the camera breathing a little; and now and then,
## for a few seconds, something standing at the edge of the trees.
## Built here in code from the game's own models (main_menu.gd adds it).

const CABIN := "res://assets/Three Cabins/Mouse Trap Cabin.glb"
## Where the cabin model goes (its middle at the origin, its front, the
## porch side, towards the camera at z ~7).
const CABIN_OFFSET := Vector3(-0.2, 0.0, -13.8)
const PINES := "res://assets/PSX Nature/Models/GLB/pine_tree_n_%d.glb"
const GRASS := "res://assets/PSX Nature/Models/GLB/grass_%d.glb"
## The Entity's model is made small; the game scales it up (monster_entity.tscn).
const ENTITY_SCALE := 3.5
const ENTITY := "res://assets/character models/elkdemongodot.glb"
const ENTITY_IDLE := "res://assets/animations/entity/looking_around.anim"
const WIND := "res://assets/audio/horror_sfx_vol_1/Ambient Wind/Ambient Wind (2).mp3"
## Where the camera stands, and what it looks at.
const EYE := Vector3(-4.0, 1.55, 24.0)
## (Left of the cabin: the menu is on the left, the cabin to its right.)
const LOOK_AT := Vector3(-7.5, 3.0, 0.0)
## The lit window (upstairs, in the cabin's front wall at z 7) and its lamp.
const WINDOW := Vector3(-1.5, 5.35, 6.78)
## The clearing: no trees within this x of the middle, south of this z.
const CLEARING := Vector2(12.0, 12.0)
## The window's glow on the wall round it.
const LAMP_ENERGY := 0.9
## Seconds between its visits, and how long it stays.
const VISIT_GAP := Vector2(22.0, 40.0)
const VISIT_TIME := Vector2(4.0, 7.0)
## Where it may stand: the treeline left of the cabin, between the menu and
## the cabin in the picture.
const TREELINE_SPOTS := [Vector3(-11.2, 0.0, 0.0), Vector3(-12.5, 0.0, -6.0), Vector3(-14.0, 0.0, -14.0), Vector3(-10.3, 0.0, -9.0)]

var camera: Camera3D
var entity: Node3D
var window_light: OmniLight3D
var _visit_left := 0.0
var _next_visit := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_sky()
	_build_ground()
	_build_cabin()
	_build_trees()
	_build_entity()
	camera = Camera3D.new()
	camera.name = "MenuCamera"
	camera.fov = 58.0
	add_child(camera)
	camera.look_at_from_position(EYE, LOOK_AT)
	camera.current = true
	var wind := AudioStreamPlayer.new()
	wind.name = "Wind"
	var stream := load(WIND) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	wind.stream = stream
	wind.volume_db = -14.0
	wind.bus = "Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else "Master"
	add_child(wind)
	wind.play()
	_next_visit = _rng.randf_range(8.0, 14.0)


func _process(delta: float) -> void:
	_time += delta
	# The camera breathes: a slow drift, as if someone stood there.
	var drift := Vector3(sin(_time * 0.21) * 0.25, sin(_time * 0.33) * 0.06, 0.0)
	camera.look_at_from_position(EYE + drift, LOOK_AT + Vector3(sin(_time * 0.13) * 0.4, 0.0, 0.0))
	# The lamp inside flickers a little.
	window_light.light_energy = LAMP_ENERGY + sin(_time * 7.0) * 0.05 + sin(_time * 2.3) * 0.08
	# Something at the treeline.
	if _visit_left > 0.0:
		_visit_left -= delta
		if _visit_left <= 0.0:
			entity.visible = false
			_next_visit = _rng.randf_range(VISIT_GAP.x, VISIT_GAP.y)
	else:
		_next_visit -= delta
		if _next_visit <= 0.0:
			visit()


## It comes to the treeline for a few seconds, facing the cabin.
func visit(index: int = -1) -> void:
	var spot: Vector3 = TREELINE_SPOTS[index if index >= 0 else _rng.randi() % TREELINE_SPOTS.size()]
	entity.position = spot
	entity.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP, true)
	entity.visible = true
	_visit_left = _rng.randf_range(VISIT_TIME.x, VISIT_TIME.y)


func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.036, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.19, 0.27)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.07, 0.08, 0.11)
	env.fog_density = 0.7
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 95.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-38.0, -150.0, 0.0)
	add_child(moon)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(260.0, 260.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.045, 0.055, 0.035)
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)


func _build_cabin() -> void:
	var scene := load(CABIN) as PackedScene
	if scene:
		var cabin := scene.instantiate() as Node3D
		cabin.name = "Cabin"
		# (The model sits off its origin: its middle comes to the clearing's.)
		cabin.position = CABIN_OFFSET
		add_child(cabin)
	# The lit window: warm glass, and the lamp behind it.
	var glass := MeshInstance3D.new()
	glass.name = "LitWindow"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.3)
	glass.mesh = quad
	var warm := StandardMaterial3D.new()
	warm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warm.albedo_color = Color(0.85, 0.5, 0.22)
	glass.material_override = warm
	glass.position = WINDOW
	add_child(glass)
	# Its bars: a cross in front of the glow.
	var bar_material := StandardMaterial3D.new()
	bar_material.albedo_color = Color(0.05, 0.035, 0.025)
	for size in [Vector2(0.07, 1.3), Vector2(1.1, 0.07)]:
		var bar := MeshInstance3D.new()
		var bar_quad := QuadMesh.new()
		bar_quad.size = size
		bar.mesh = bar_quad
		bar.material_override = bar_material
		bar.position = WINDOW + Vector3(0.0, 0.0, 0.01)
		add_child(bar)
	window_light = OmniLight3D.new()
	window_light.name = "WindowLight"
	window_light.light_color = Color(1.0, 0.66, 0.34)
	window_light.omni_range = 5.0
	window_light.light_energy = LAMP_ENERGY
	window_light.position = WINDOW + Vector3(0.0, -0.4, 1.1)
	add_child(window_light)


## A ring of pines round the clearing, and a few close by the camera to look
## out past.
func _build_trees() -> void:
	var models: Array[PackedScene] = []
	for i in [1, 2, 3]:
		var model := load(PINES % i) as PackedScene
		if model:
			models.append(model)
	if models.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1974
	var spots: Array[Vector3] = []
	# The forest round the clearing (the cabin and the open ground between
	# it and the camera).
	while spots.size() < 120:
		var spot := Vector3(rng.randf_range(-48.0, 48.0), 0.0, rng.randf_range(-45.0, EYE.z + 2.0))
		if absf(spot.x) < CLEARING.x and spot.z > -CLEARING.y:
			continue
		if spot.z > EYE.z - 6.0 and absf(spot.x - EYE.x) < 30.0:
			continue   # (the camera's own treeline is placed below)
		spots.append(spot)
	# The treeline the camera stands in.
	for x in [-13.0, -10.0, 4.5, 8.0, 12.0]:
		spots.append(Vector3(x + rng.randf_range(-0.8, 0.8), 0.0, EYE.z + rng.randf_range(-3.5, -1.0)))
	for spot in spots:
		var tree := models[rng.randi() % models.size()].instantiate() as Node3D
		tree.position = spot
		tree.rotation.y = rng.randf_range(0.0, TAU)
		tree.scale = Vector3.ONE * rng.randf_range(0.9, 1.25)
		add_child(tree)
	# Grass in the clearing, thicker near the camera.
	var grasses: Array[PackedScene] = []
	for i in [1, 2, 3, 4]:
		var grass := load(GRASS % i) as PackedScene
		if grass:
			grasses.append(grass)
	if grasses.is_empty():
		return
	for i in 260:
		var near := rng.randf() < 0.6
		var spot := Vector3(rng.randf_range(-22.0, 18.0), 0.0, rng.randf_range(12.0, EYE.z) if near else rng.randf_range(-6.0, 14.0))
		if absf(spot.x) < 7.5 and spot.z < 8.0:
			continue   # (not inside the cabin)
		var clump := grasses[rng.randi() % grasses.size()].instantiate() as Node3D
		clump.position = spot
		clump.rotation.y = rng.randf_range(0.0, TAU)
		clump.scale = Vector3.ONE * rng.randf_range(0.8, 1.5)
		add_child(clump)


func _build_entity() -> void:
	var scene := load(ENTITY) as PackedScene
	if not scene:
		entity = Node3D.new()
		add_child(entity)
		return
	entity = scene.instantiate() as Node3D
	entity.name = "Visitor"
	entity.visible = false
	entity.scale = Vector3.ONE * ENTITY_SCALE
	add_child(entity)
	var skeleton := entity.find_child("GeneralSkeleton", true, false)
	var idle := load(ENTITY_IDLE) as Animation
	if skeleton and idle:
		skeleton.unique_name_in_owner = true
		var library := AnimationLibrary.new()
		idle = idle.duplicate() as Animation
		idle.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(&"idle", idle)
		# The model's own player (it animates from the model's root).
		var player := entity.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if not player:
			player = AnimationPlayer.new()
			entity.add_child(player)
		player.add_animation_library(&"menu", library)
		player.play(&"menu/idle")
