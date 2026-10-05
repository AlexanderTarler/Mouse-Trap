shader_type sky;

// The day/night sky (driven by environment_controller.gd): a gradient that
// warms into dusk and dawn around the sun, the sun and the moon as disks that
// follow their lights across the sky, and stars that fade in at night and
// twinkle. A storm (Weather) brings clouds in: they drift over, thicken to
// an overcast and hide the sun, the moon and the stars.

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
// 0 = clear, 1 = overcast.
uniform float cloud_cover = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 0.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 0.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 0.0));
	float e = hash(vec3(i + vec2(1.0, 1.0), 0.0));
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * noise2(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		amp *= 0.5;
	}
	return v;
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

	// Clouds: noise on a layer high above, drifting with the wind; the
	// cover sets how much of it is cloud.
	float cloud = 0.0;
	vec3 cloud_colour = vec3(0.0);
	if (h > 0.0 && cloud_cover > 0.001) {
		vec2 uv = d.xz / (h + 0.12) * 1.6 + vec2(TIME * 0.012, TIME * 0.005);
		float n = fbm(uv);
		float threshold = mix(0.75, 0.2, cloud_cover);
		cloud = smoothstep(threshold, threshold + 0.25, n) * smoothstep(0.0, 0.08, h);
		cloud = clamp(cloud + cloud_cover * cloud_cover * 0.6, 0.0, 1.0);
		// Lit from above by day, near black at night; darker underneath
		// where they're thick.
		vec3 lit = mix(vec3(0.62, 0.64, 0.68), vec3(0.05, 0.055, 0.07), night);
		cloud_colour = lit * (1.0 - 0.35 * smoothstep(0.4, 0.9, n));
	}
	// What's above the clouds (the sun, the moon, the stars) shows through
	// only where there are none.
	float clear_sky = 1.0 - cloud;

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
			col += vec3(0.9, 0.93, 1.0) * star * twinkle * bright * night * clear_sky * smoothstep(0.0, 0.2, h);
		}

		// The sun: a disk with a soft halo.
		float s = dot(d, normalize(sun_direction));
		float disk = smoothstep(0.99935, 0.99955, s);
		float halo = pow(max(s, 0.0), 220.0) * 0.6 + pow(max(s, 0.0), 12.0) * 0.08 * (1.0 - night);
		vec3 sun_colour = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.55, 0.25), dusk);
		col += sun_colour * (disk * 6.0 + halo) * clear_sky * (1.0 - storm);

		// The moon: a pale disk, mottled, with a faint glow.
		float m = dot(d, normalize(moon_direction));
		float moon_disk = smoothstep(0.99905, 0.99925, m);
		float mottle = 0.82 + 0.18 * hash(floor(d * 900.0));
		float moon_glow = pow(max(m, 0.0), 400.0) * 0.25;
		col += vec3(0.85, 0.88, 0.95) * (moon_disk * 1.6 * mottle + moon_glow) * (0.25 + 0.75 * night) * clear_sky * (1.0 - storm);
		col = mix(col, cloud_colour, cloud);
	}

	COLOR = col;
}
