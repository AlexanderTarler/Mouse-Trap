shader_type canvas_item;

// ============================================================
// Sanity "Nest Overgrowth" Shader
// Simulates thick, coarse, writhing black hair/organic tendrils
// growing from screen edges toward center based on corruption.
// ============================================================

uniform float corruption_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale : hint_range(1.0, 30.0) = 14.0;
uniform float speed : hint_range(0.0, 1.0) = 0.35;
uniform float edge_threshold : hint_range(0.1, 0.9) = 0.52;

// -----------------------------------------------------------
// 2D hash function — deterministic pseudo-random
// -----------------------------------------------------------
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// -----------------------------------------------------------
// Value noise with smooth interpolation
// -----------------------------------------------------------
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// -----------------------------------------------------------
// Layered fbm noise for organic complexity
// -----------------------------------------------------------
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	float persistence = 0.6;
	int octaves = 4;

	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.1;
		amplitude *= persistence;
	}
	return value;
}

// -----------------------------------------------------------
// Main fragment
// -----------------------------------------------------------
void fragment() {
	vec2 uv = UV;

	// Edge distance: 0 at center, 1 at edges
	vec2 from_center = abs(uv - 0.5) * 2.0;
	float edge_dist = max(from_center.x, from_center.y);

	// Organic writhing noise layers
	vec2 noise_uv = uv * noise_scale;
	float time = TIME * speed;

	// Primary tendril pattern — flows from edges inward
	float n1 = fbm(noise_uv + vec2(time * 0.7, time * 0.3));
	float n2 = fbm(noise_uv * 0.6 - vec2(time * 0.5, -time * 0.4));

	// Combine noise with edge distance
	// corruption_intensity controls how far from edges the tendrils reach
	// At 0: tendrils stay at the very edges (invisible)
	// At 1: tendrils reach well past center — full coverage
	float core_influence = 1.0 - corruption_intensity;
	float tendril = edge_dist - (n1 * 0.45 + n2 * 0.2) + core_influence * 0.6;

	// Smooth the tendril threshold with adjustable edge
	float alpha = smoothstep(edge_threshold - 0.15, edge_threshold + 0.25, tendril);

	// FIX 1: At corruption_intensity = 1.0, allow full black (100% opacity).
	// Removed the 0.85 cap that prevented full-screen coverage.
	float max_opacity = corruption_intensity;
	alpha = min(alpha, max_opacity);

	// FIX 2: Center-fill component — at high corruption intensity,
	// the tendrils converge on screen center. The tendril equation
	// naturally leaves the center visible because edge_dist = 0 there.
	// This fill term pushes opacity up at center when intensity is high.
	float center_fill = corruption_intensity * 1.2 - edge_dist;
	center_fill = clamp(center_fill * corruption_intensity, 0.0, 1.0);
	alpha = max(alpha, center_fill);

	// High-frequency micro-gaps — thin slivers of visibility
	// even at full corruption_intensity
	float micro_noise = noise(uv * 90.0 + time * 2.5);
	float micro_gaps = 1.0 - step(0.65, micro_noise) * 0.25;
	alpha *= micro_gaps;

	// Additional coarse gap patterns (larger "breathing" holes)
	float coarse_gaps = noise(uv * 30.0 - time * 1.3);
	alpha *= 0.8 + coarse_gaps * 0.2;

	// Slight edge vignette boost for visual depth
	float vignette = 1.0 - (from_center.x * from_center.y) * 0.3;
	alpha *= vignette;

	// Final color: deep black with subtle brown undertone
	vec3 hair_color = vec3(0.02, 0.01, 0.01);
	COLOR = vec4(hair_color, clamp(alpha, 0.0, 1.0));
}