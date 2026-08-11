shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

// ─── NOTE PICKUP "WAVE OF LIGHT" HIGHLIGHT ────────────────────────────────
// A subtle diagonal band of light that scrolls across the mesh over time,
// catching the player's eye without overpowering the base material.
// Applied via next_pass on the note's material so the base texture/shading
// remains untouched.

// Brightness of the traveling light band (keep subtle — 0.0-0.5 works best).
uniform float wave_intensity : hint_range(0.0, 1.0) = 0.25;
// How fast the diagonal band sweeps across the surface (cycles per second).
uniform float wave_speed : hint_range(0.1, 2.0) = 0.4;
// Width of the light band in UV space (smaller = narrower highlight).
uniform float wave_width : hint_range(0.05, 0.6) = 0.2;
// Base tint of the wave (warm — matches the note's parchment/brown theme).
uniform vec3 wave_color : source_color = vec3(1.0, 0.95, 0.7);
// Overall opacity of the overlay once the band has fully passed.
uniform float base_alpha : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	// Diagonal axis across UV space: u + v. A wave travels along this axis.
	float diagonal = UV.x + UV.y;

	// Scrolling wave coordinate. MOD prevents wrap-around artifacts.
	float wave_pos = mod(diagonal - TIME * wave_speed, 1.0);

	// Smooth band centered on the wave position.
	float band = 1.0 - smoothstep(0.0, wave_width, abs(wave_pos - 0.5));

	// Add a faint constant glow over the whole surface so the note is
	// gently luminous even between waves (catch the eye from a distance).
	float glow = base_alpha + band * wave_intensity;

	// Output as additive light; the base material shows through normally.
	// NOTE: We deliberately do NOT output ALPHA here. In blend_add mode,
	// writing ALPHA replaces the base material's alpha channel, which made
	// the note become fully transparent whenever this next_pass shader ran.
	// The additive blending of ALBEDO/EMISSION is sufficient for the wave effect.
	ALBEDO = wave_color * glow;
	EMISSION = wave_color * glow * 2.0;
}