shader_type canvas_item;

// Distortion overlay shader for the "watched" effect.
// Applies chromatic aberration, pixelation, noise, and vignette
// based on the watched_intensity parameter.

uniform float watched_intensity : hint_range(0.0, 1.0) = 0.0;

// Chromatic aberration strength (max offset in UV)
uniform float chromatic_strength : hint_range(0.0, 0.05) = 0.02;

// Pixelation factor (1.0 = no pixelation, lower = more pixelated)
uniform float pixelation_factor : hint_range(1.0, 100.0) = 100.0;

// Noise intensity
uniform float noise_strength : hint_range(0.0, 0.3) = 0.1;

// Vignette darkness
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;

// Vignette size (0.0 = full screen, 1.0 = edges only)
uniform float vignette_size : hint_range(0.0, 1.0) = 0.3;

// Time uniform for animation
uniform float effect_time : hint_range(0.0, 100.0) = 0.0;


// Simple pseudo-random noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
	vec2 uv = UV;
	float intensity = watched_intensity;
	
	// --- Pixelation ---
	float pixel_size = 1.0 / max(pixelation_factor * (1.0 - intensity * 0.8), 1.0);
	vec2 pixel_uv = floor(uv / pixel_size) * pixel_size + pixel_size * 0.5;
	
	// --- Chromatic Aberration ---
	float chroma_offset = chromatic_strength * intensity;
	vec2 r_uv = pixel_uv + vec2(chroma_offset, 0.0);
	vec2 g_uv = pixel_uv;
	vec2 b_uv = pixel_uv - vec2(chroma_offset, 0.0);
	
	float r = texture(TEXTURE, r_uv).r;
	float g = texture(TEXTURE, g_uv).g;
	float b = texture(TEXTURE, b_uv).b;
	
	vec4 color = vec4(r, g, b, intensity);
	
	// --- Noise overlay ---
	float noise = hash(floor(pixel_uv * 100.0) + effect_time * 10.0);
	float noise_amount = noise_strength * intensity;
	color.rgb += (noise - 0.5) * noise_amount * 2.0;
	
	// --- Vignette ---
	vec2 center = uv - 0.5;
	float dist = length(center);
	float vignette = smoothstep(vignette_size, 0.0, dist) * vignette_strength * intensity;
	color.rgb *= (1.0 - vignette);
	
	// --- Red tint at high intensity ---
	color.rgb += vec3(intensity * 0.3, 0.0, 0.0);
	
	COLOR = color;
}
