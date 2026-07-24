shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, depth_test_disabled, blend_mix;

uniform vec4 highlight_color : source_color = vec4(1.0, 0.9, 0.3, 0.6);

void vertex() {
	// Standard vertex transform
}

void fragment() {
	ALBEDO = highlight_color.rgb;
	ALPHA = highlight_color.a;
	// No shading calculation since we're unshaded
}