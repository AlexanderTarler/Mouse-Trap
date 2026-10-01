shader_type sky;

// The day/night sky (driven by environment_controller.gd): a gradient that
// warms into dusk and dawn around the sun, the sun and the moon as disks that
// follow their lights across the sky, and stars that fade in at night and
// twinkle. A storm (Weather) greys it over and hides the stars.

uniform vec3 sky_top_color : source_color = vec3(0.4, 0.6, 1.0);
uniform vec3 sky_horizon_color : source_color = vec3(0.7, 0.8, 1.0);
uniform vec3 ground_color : source_color = vec3(0.2, 0.15, 0.1);
// Directions TO the sun and the moon.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
// 0 = day, 1 = night.
uniform float night = 0.0;
// How strong the dusk/dawn glow is (the sun near the horizon).
uniform float dusk = 0.0;
uniform float storm = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;

	vec3 col;
	if (h >= 0.0) {
		col = mix(sky_horizon_color, sky_top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	} else {
		col = mix(sky_horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}

	// Dusk and dawn: the horizon glows warm, hottest towards the sun.
	vec2 flat_eye = normalize(d.xz + vec2(1e-4));
	vec2 flat_sun = normalize(sun_direction.xz + vec2(1e-4));
	float toward_sun = max(dot(flat_eye, flat_sun), 0.0);
	float band = exp(-abs(h) * 5.0);
	vec3 glow = mix(vec3(0.85, 0.32, 0.42), vec3(1.0, 0.5, 0.18), toward_sun);
	float glow_amount = dusk * band * (0.3 + 0.7 * pow(toward_sun, 2.5)) * (1.0 - storm * 0.85);
	col = mix(col, glow, clamp(glow_amount, 0.0, 0.85));

	if (h > 0.0) {
		// Stars.
		vec3 p = d * 260.0;
		vec3 cell = floor(p);
		float r = hash(cell);
		if (r > 0.9955) {
			vec3 centre = cell + vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3));
			float star = smoothstep(0.42, 0.0, length(p - centre));
			float twinkle = 0.65 + 0.35 * sin(TIME * (1.3 + r * 5.0) + r * 61.0);
			float bright = 0.6 + 2.4 * hash(cell + 9.1);
			col += vec3(0.9, 0.93, 1.0) * star * twinkle * bright * night * (1.0 - storm) * smoothstep(0.0, 0.2, h);
		}

		// The sun: a disk with a soft halo.
		float s = dot(d, normalize(sun_direction));
		float disk = smoothstep(0.99935, 0.99955, s);
		float halo = pow(max(s, 0.0), 220.0) * 0.6 + pow(max(s, 0.0), 12.0) * 0.08 * (1.0 - night);
		vec3 sun_colour = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.55, 0.25), dusk);
		col += sun_colour * (disk * 6.0 + halo) * (1.0 - storm * 0.9);

		// The moon: a pale disk, mottled, with a faint glow.
		float m = dot(d, normalize(moon_direction));
		float moon_disk = smoothstep(0.99905, 0.99925, m);
		float mottle = 0.82 + 0.18 * hash(floor(d * 900.0));
		float moon_glow = pow(max(m, 0.0), 400.0) * 0.25;
		col += vec3(0.85, 0.88, 0.95) * (moon_disk * 1.6 * mottle + moon_glow) * (0.25 + 0.75 * night) * (1.0 - storm * 0.9);
	}

	COLOR = col;
}
