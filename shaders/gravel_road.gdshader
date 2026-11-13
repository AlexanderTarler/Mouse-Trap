shader_type spatial;
// The gravel road (scripts/world/gravel_road.gd): tiled gravel, two compacted wheel
// ruts, a patchy grassy ridge down the middle, and ragged edges fading into
// the terrain. UV.x runs along the road (m), UV.y across it (-1 to 1).
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform sampler2D gravel : source_color, filter_linear_mipmap, repeat_enable;
// Gravel colour (the texture is dark, wet-looking earth): lifted to dry, dusty gravel.
uniform vec3 tint : source_color = vec3(0.86, 0.8, 0.72);
uniform float brightness = 1.75;
// Metres per texture repeat.
uniform float tile = 2.2;
// Where the wheel ruts run (fraction of the half width) and how wide they are.
uniform float rut_offset = 0.42;
uniform float rut_width = 0.13;
uniform vec3 ridge_color : source_color = vec3(0.15, 0.19, 0.08);
// How far in from the edge the road fades out (fraction of the half width).
uniform float edge_soft = 0.32;
// The road's length (set by gravel_road.gd): both ends fade into the ground.
uniform float road_length = 1000.0;
uniform float end_fade = 4.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	// Two scales of the texture so the repeat doesn't show.
	vec3 g = texture(gravel, w / tile).rgb * 0.6 + texture(gravel, w / (tile * 2.7) + vec2(0.37, 0.61)).rgb * 0.4;
	g *= tint * brightness;
	// Broad patches of lighter and darker gravel.
	g *= 0.82 + 0.36 * noise(w * 0.09);

	float across = UV.y;
	// Wheel ruts: packed down, darker and smoother.
	float rut = 1.0 - smoothstep(rut_width * 0.4, rut_width, abs(abs(across) - rut_offset));
	g = mix(g, g * 0.7, rut * 0.75);
	// A ridge of grass and dirt down the middle, broken up.
	float ridge = (1.0 - smoothstep(0.04, 0.17, abs(across))) * smoothstep(0.3, 0.7, noise(w * 0.7));
	g = mix(g, ridge_color, ridge * 0.65);

	ALBEDO = g;
	ROUGHNESS = 1.0;

	// Ragged edges, fading into the ground.
	float edge = 1.0 - abs(across);
	float ragged = noise(w * 1.4) * 0.6 + noise(w * 4.3) * 0.4;
	float ends = smoothstep(0.0, end_fade * 0.5, UV.x) * (1.0 - smoothstep(road_length - end_fade, road_length, UV.x));
	ALPHA = smoothstep(0.0, edge_soft, edge - (ragged - 0.45) * edge_soft) * ends;
}
