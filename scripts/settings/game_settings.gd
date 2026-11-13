class_name GameSettings
extends RefCounted
## The player's settings, saved in user://settings.cfg and applied at once:
##   display/mode               0 Windowed, 1 Borderless, 2 Fullscreen
##   video/brightness           gamma (1 = as made); a layer under the UI
##   video/fov                  the camera's field of view (degrees)
##   video/head_bob             the camera bobbing while walking
##   controls/mouse_sensitivity a multiplier on the player's mouse look
##   controls/invert_y          mouse up looks down
##   controls/stick_sensitivity a multiplier on the right stick's look speed
##   audio/master, ambient, sfx, room_echo   bus volumes (linear; the Entity's
##                              bus follows Sound Effects)
##   audio/microphone, mic_threshold_db      PlayerVoice
##   video/quality              0 Low, 1 Medium, 2 High (GraphicsQuality)
##   video/screen_shake         the camera shakes (staring, the jumpscare)
##   video/calibrated           the brightness screen has been seen
##   gameplay/objective_highlights   the x-ray outline on the next objective
##   accessibility/captions, caption_size    Captions (0 Small - 2 Large)
## The keys are saved alongside (GameKeys). The options menu edits them
## (OptionsMenu); the main menu applies them at startup (apply_all), and the
## player picks up its own on spawn (apply_player).

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"display/mode": 0,
	"video/brightness": 1.0,
	"video/fov": 75.0,
	"video/head_bob": true,
	"controls/mouse_sensitivity": 1.0,
	"controls/invert_y": false,
	"controls/stick_sensitivity": 1.0,
	"accessibility/captions": false,
	"accessibility/caption_size": 1,
	"audio/microphone": false,
	"audio/mic_threshold_db": -24.0,
	"audio/master": 1.0,
	"audio/ambient": 0.3,
	"audio/sfx": 0.8,
	"audio/room_echo": 1.0,
	"video/quality": 1,
	"video/screen_shake": true,
	"video/calibrated": false,
	"gameplay/objective_highlights": false,
}
## Volume settings -> their AudioServer bus.
const VOLUME_BUSES := {
	"audio/master": "Master",
	"audio/ambient": "Ambient",
	"audio/sfx": "SFX",
	"audio/room_echo": "Interior",
}
## The Entity's bus, as loud as Sound Effects times this (0.6 to 0.8 by
## default, as the sound manager first set them).
const ENTITY_OF_SFX := 0.75
const BRIGHTNESS_LAYER := "BrightnessLayer"

static var _values := {}
static var _loaded := false


static func get_value(key: String) -> Variant:
	_load()
	return _values.get(key, default_of(key))


## A setting's default (the web starts at Low graphics: browsers are slower).
static func default_of(key: String) -> Variant:
	if key == "video/quality" and OS.has_feature("web"):
		return 0
	return DEFAULTS.get(key)


## Sets, saves and applies one setting.
static func set_value(key: String, value: Variant) -> void:
	_load()
	_values[key] = value
	var config := ConfigFile.new()
	config.load(PATH)   # keep anything else saved there
	var parts := key.split("/")
	config.set_value(parts[0], parts[1], value)
	config.save(PATH)
	_apply(key)


static func apply_all() -> void:
	for key in DEFAULTS:
		_apply(key)
	GameKeys.apply()


## Every setting back to its default (the keys too: GameKeys.reset), bar the
## display mode and whether the brightness screen was seen.
static func reset_all() -> void:
	for key in DEFAULTS:
		if key in ["display/mode", "video/calibrated"]:
			continue
		set_value(key, default_of(key))
	GameKeys.reset()


## The camera shake's strength: 1, or 0 with Screen Shake off.
static func shake() -> float:
	return 1.0 if bool(get_value("video/screen_shake")) else 0.0


## The saved volumes onto the buses that exist (the sound manager calls it
## again once it has made them).
static func apply_volumes() -> void:
	for key in VOLUME_BUSES:
		_apply(key)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in DEFAULTS:
		var parts: PackedStringArray = key.split("/")
		if config.has_section_key(parts[0], parts[1]):
			_values[key] = config.get_value(parts[0], parts[1])


static func _apply(key: String) -> void:
	match key:
		"display/mode":
			apply_display_mode(int(get_value(key)))
		"video/brightness":
			_apply_brightness(float(get_value(key)))
		"audio/master", "audio/ambient", "audio/sfx", "audio/room_echo":
			var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
			var linear := float(get_value(key))
			if bus >= 0:
				AudioServer.set_bus_volume_db(bus, linear_to_db(linear))
			var entity := AudioServer.get_bus_index("Entity")
			if key == "audio/sfx" and entity >= 0:
				AudioServer.set_bus_volume_db(entity, linear_to_db(linear * ENTITY_OF_SFX))
		"video/quality":
			GraphicsQuality.apply(int(get_value(key)))
		"gameplay/objective_highlights":
			var routine := _autoload("RoutineManager")
			if routine and routine.has_method("set_highlights"):
				routine.set_highlights(bool(get_value(key)))
		"accessibility/caption_size":
			var captions := _autoload("Captions")
			if captions and captions.has_method("apply_size"):
				captions.apply_size(int(get_value(key)))
		"accessibility/captions", "audio/microphone", "audio/mic_threshold_db", "video/calibrated", "video/screen_shake":
			pass   # read where they're used
		_:
			var tree := Engine.get_main_loop() as SceneTree
			var player := tree.get_first_node_in_group("player") if tree else null
			if player:
				apply_player(player)


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null


## The player's own: look sensitivity and inversion, head bob, field of view.
static func apply_player(player: Node) -> void:
	if "look_scale" in player:
		player.look_scale = float(get_value("controls/mouse_sensitivity"))
	if "invert_y" in player:
		player.invert_y = bool(get_value("controls/invert_y"))
	if "stick_scale" in player:
		player.stick_scale = float(get_value("controls/stick_sensitivity"))
	if "head_bob_enabled" in player:
		player.head_bob_enabled = bool(get_value("video/head_bob"))
	var camera := player.get_node_or_null("CameraHolder/Camera3D") as Camera3D
	if camera:
		camera.fov = float(get_value("video/fov"))


## Windowed: an ordinary window with its frame. Borderless: a borderless
## window covering the whole screen. Fullscreen: exclusive fullscreen.
static func apply_display_mode(mode: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)


## Brightness: a gamma curve over the picture, drawn under every UI layer.
## It lives on the root, so it carries over between scenes. At 1.0 it's off.
static func _apply_brightness(gamma: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var layer := tree.root.get_node_or_null(BRIGHTNESS_LAYER) as CanvasLayer
	if not layer:
		layer = CanvasLayer.new()
		layer.name = BRIGHTNESS_LAYER
		layer.layer = -50
		var rect := ColorRect.new()
		rect.name = "Gamma"
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float gamma = 1.0;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(pow(max(c, vec3(0.0)), vec3(1.0 / gamma)), 1.0);
}
"""
		var material := ShaderMaterial.new()
		material.shader = shader
		rect.material = material
		layer.add_child(rect)
		tree.root.add_child.call_deferred(layer)
	var gamma_rect := layer.get_node("Gamma") as ColorRect
	(gamma_rect.material as ShaderMaterial).set_shader_parameter("gamma", gamma)
	layer.visible = absf(gamma - 1.0) > 0.01
