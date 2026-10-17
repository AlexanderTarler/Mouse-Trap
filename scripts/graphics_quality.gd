class_name GraphicsQuality
extends RefCounted
## Graphics quality (Options > Video): Low, Medium or High. Medium is the
## game as it was made; Low is lighter for slow machines and the browser,
## High sharper for strong ones. What changes:
##   shadows        the sun's and moon's shadow map, the lamps' shadow atlas,
##                  how soft their edges are
##   detail         how soon meshes drop to their simpler LODs
##   ground fog     the volumetric fog's resolution (Forward+ only)
##   small plants   how far the forest floor's small plants are drawn
##                  (FoliageBatcher's batches)
##   edges          anti-aliasing (High: FXAA)
## Applied to the window's viewport and the renderer; it carries over between
## scenes. GameSettings "video/quality" calls apply().

enum Level { LOW, MEDIUM, HIGH }
const NAMES := ["Low", "Medium", "High"]
const SUN_SHADOW := [512, 1024, 2048]
const LAMP_SHADOW := [1024, 2048, 4096]
const SOFT_SHADOWS := [
	RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
]
const LOD_THRESHOLD := [2.0, 1.0, 0.75]
const FOG_SIZE := [48, 64, 96]
const FOG_DEPTH := [32, 64, 96]
## How far the small plants are drawn (m); FoliageBatcher's own distance at
## Medium.
const PLANT_DISTANCE := [40.0, 60.0, 90.0]

static var level := Level.MEDIUM


static func apply(new_level: int) -> void:
	level = clampi(new_level, Level.LOW, Level.HIGH) as Level
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var viewport := tree.root
	viewport.positional_shadow_atlas_size = LAMP_SHADOW[level]
	viewport.mesh_lod_threshold = LOD_THRESHOLD[level]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if level == Level.HIGH else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(SUN_SHADOW[level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SOFT_SHADOWS[level])
	RenderingServer.positional_soft_shadow_filter_set_quality(SOFT_SHADOWS[level])
	RenderingServer.environment_set_volumetric_fog_volume_size(FOG_SIZE[level], FOG_DEPTH[level])
	RenderingServer.environment_set_volumetric_fog_filter_active(level != Level.LOW)
	# The small plants already in the world.
	if tree.current_scene:
		for batch in tree.current_scene.find_children("*", "MultiMeshInstance3D", true, false):
			if (batch as MultiMeshInstance3D).visibility_range_end > 0.0:
				(batch as MultiMeshInstance3D).visibility_range_end = plant_distance()


## How far the small plants are drawn at this level (m).
static func plant_distance() -> float:
	return PLANT_DISTANCE[level]
