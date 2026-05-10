extends Node3D

## PSX-style post-processing effect.
## Adds dithering, low-resolution rendering, and vertex snapping
## to give the game a classic PlayStation 1 horror aesthetic.

## Enable/disable the PSX effect
@export var enabled: bool = true

## Target resolution scale (1.0 = full, 0.5 = half, 0.25 = quarter)
@export var resolution_scale: float = 0.5

## Dithering intensity (0.0 = none, 1.0 = full)
@export var dither_intensity: float = 0.3

## Color depth (reduces color banding - lower = more PSX-like)
@export var color_depth: int = 16

## Affine texture mapping distortion (0.0 = none, 1.0 = full)
@export var affine_distortion: float = 0.1

## Vertex snap distance (for the classic PSX wobble effect)
@export var vertex_snap: float = 0.05

## Whether to apply the effect
var _active: bool = true

## SubViewport for low-res rendering
var _sub_viewport: SubViewport = null

## Camera for the sub-viewport
var _sub_camera: Camera3D = null

## Main camera reference
var _main_camera: Camera3D = null

## ColorRect for displaying the sub-viewport
var _display_rect: ColorRect = null

## CanvasLayer for the display
var _canvas_layer: CanvasLayer = null

## Dithering shader material
var _dither_material: ShaderMaterial = null

func _ready() -> void:
	if not enabled:
		return
	
	# Wait for the scene to be fully ready
	await get_tree().process_frame
	
	_setup_low_res_rendering()
	_setup_dither_shader()

func _setup_low_res_rendering() -> void:
	# Find the main camera
	_main_camera = get_viewport().get_camera_3d()
	if not _main_camera:
		return
	
	# Create a sub-viewport for low-res rendering
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "PSXSubViewport"
	_sub_viewport.size = Vector2i(
		ceil(get_viewport().size.x * resolution_scale),
		ceil(get_viewport().size.y * resolution_scale)
	)
	_sub_viewport.transparent_bg = false
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# render_target_v_flip is not available in Godot 4 SubViewport
	# SubViewports in Godot 4 handle flipping internally
	# disable_3d and disable_2d are not available in Godot 4 SubViewport
	# In Godot 4, SubViewport always renders both 2D and 3D
	_sub_viewport.handle_input_locally = false
	_sub_viewport.snap_2d_vertices_to_pixel = true
	_sub_viewport.snap_2d_transforms_to_pixel = true
	add_child(_sub_viewport)
	
	# Create a camera in the sub-viewport that copies the main camera
	_sub_camera = Camera3D.new()
	_sub_camera.name = "PSXSubCamera"
	_sub_viewport.add_child(_sub_camera)
	
	# Create a CanvasLayer to display the sub-viewport
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)
	
	# Create a ColorRect to show the sub-viewport content
	_display_rect = ColorRect.new()
	_display_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_display_rect)
	
	# Create a texture rect from the sub-viewport
	var texture_rect = TextureRect.new()
	texture_rect.texture = _sub_viewport.get_texture()
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display_rect.add_child(texture_rect)
	
	# Hide the main viewport's 3D content by making the main camera a secondary viewport
	# Instead, we'll just sync the sub-camera with the main camera each frame

func _setup_dither_shader() -> void:
	# Create a simple dithering shader
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float dither_intensity : hint_range(0.0, 1.0) = 0.3;
uniform int color_depth : hint_range(2, 32) = 16;

// Simple ordered dithering pattern
const float dither[16] = float[](
	0.0, 0.5, 0.125, 0.625,
	0.75, 0.25, 0.875, 0.375,
	0.1875, 0.6875, 0.0625, 0.5625,
	0.9375, 0.4375, 0.8125, 0.3125
);

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	
	// Color depth reduction
	float steps = float(color_depth);
	color.r = floor(color.r * steps) / steps;
	color.g = floor(color.g * steps) / steps;
	color.b = floor(color.b * steps) / steps;
	
	// Dithering
	ivec2 pos = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = dither[pos.y * 4 + pos.x];
	
	// Apply dithering based on intensity
	if (dither_intensity > 0.0) {
		vec3 dithered = color.rgb + (threshold - 0.5) * dither_intensity * 0.1;
		color.rgb = dithered;
	}
	
	COLOR = color;
}
"""
	
	_dither_material = ShaderMaterial.new()
	_dither_material.shader = shader
	_dither_material.set_shader_parameter("dither_intensity", dither_intensity)
	_dither_material.set_shader_parameter("color_depth", color_depth)
	
	# Apply to the display rect
	if _display_rect:
		_display_rect.material = _dither_material

func _process(_delta: float) -> void:
	if not enabled or not _active:
		return
	
	# Sync the sub-camera with the main camera
	if _sub_camera and _main_camera:
		_sub_camera.global_transform = _main_camera.global_transform
		_sub_camera.fov = _main_camera.fov
		_sub_camera.near = _main_camera.near
		_sub_camera.far = _main_camera.far
		_sub_camera.cull_mask = _main_camera.cull_mask
		_sub_camera.environment = _main_camera.environment
	
	# Update sub-viewport size if window was resized
	if _sub_viewport and get_viewport():
		var target_size = Vector2i(
			ceil(get_viewport().size.x * resolution_scale),
			ceil(get_viewport().size.y * resolution_scale)
		)
		if _sub_viewport.size != target_size:
			_sub_viewport.size = target_size

## Toggle the PSX effect on/off
func toggle() -> void:
	_active = not _active
	if _display_rect:
		_display_rect.visible = _active
	if _sub_viewport:
		_sub_viewport.visible = _active

## Update shader parameters at runtime
func set_dither_intensity(value: float) -> void:
	dither_intensity = value
	if _dither_material:
		_dither_material.set_shader_parameter("dither_intensity", value)

func set_color_depth(value: int) -> void:
	color_depth = value
	if _dither_material:
		_dither_material.set_shader_parameter("color_depth", value)
