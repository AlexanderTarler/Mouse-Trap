shader_type canvas_item;

// The Entity's distortion field (driven by sanity_controller.gd), as the
// player's own eyes would suffer it: vision swims and warps around the
// Entity and won't focus on it, the eyes can't converge (double vision),
// colour drains away and the view narrows into a tunnel that throbs with the
// heartbeat. `burst` is a moment of near-blackout: the tunnel closes almost
// shut, then vision swims back.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float burst : hint_range(0.0, 1.0) = 0.0;
// The Entity on screen (0-1).
uniform vec2 center = vec2(0.5);
uniform float aspect = 1.7778;

// A heartbeat: a strong beat and a softer one just after, ~80 bpm.
float heartbeat(float t) {
	float phase = fract(t * 1.35);
	return exp(-phase * 9.0) + 0.6 * exp(-max(phase - 0.2, 0.0) * 9.0) * step(0.2, phase);
}

void fragment() {
	float k = intensity;
	float t = TIME;
	float beat = heartbeat(t);
	vec2 uv = SCREEN_UV;

	// Distance from the Entity, in screen-height units.
	vec2 d = uv - center;
	d.x *= aspect;
	float r = length(d);
	vec2 away = r > 0.0001 ? d / r : vec2(0.0, 1.0);
	float field = exp(-r * 2.6);

	// Vision swims: a slow swirl and a heat-haze ripple around it, swelling
	// on each heartbeat.
	float angle = (0.5 + 0.5 * sin(t * 1.1)) * 0.9 * k * field;
	float cs = cos(angle);
	float sn = sin(angle);
	vec2 dr = vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
	dr += away * sin(r * 30.0 - t * 4.0) * (0.008 + 0.006 * beat) * k * field;
	dr.x /= aspect;
	uv = center + dr;
	uv += vec2(sin(uv.y * 11.0 + t * 1.7), cos(uv.x * 9.0 + t * 1.3)) * 0.004 * k;

	// (Warping past the screen's edge would smear its last pixels.)
	uv = clamp(uv, vec2(0.002), vec2(0.998));

	// Won't focus: blurred, most of all around it.
	float blur = k * (field * 2.5 + 0.6) + burst * 3.0;
	vec3 col = textureLod(screen_tex, uv, blur).rgb;

	// Double vision: the eyes drift apart, pulling together and apart again.
	float split = (0.012 + 0.01 * sin(t * 0.9)) * k + 0.02 * burst;
	vec3 second = textureLod(screen_tex, clamp(uv + vec2(split, split * 0.15), vec2(0.002), vec2(0.998)), blur + 0.5).rgb;
	col = mix(col, second, 0.45 * k + 0.3 * burst);

	// Colour drains away.
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), 0.6 * k);

	// Tunnel vision, throbbing with the heartbeat and reddening at the rim;
	// in a burst it closes almost shut.
	float edge = length((SCREEN_UV - 0.5) * vec2(aspect, 1.0));
	float open = mix(1.1, 0.45, k) - 0.06 * beat * k - 0.4 * burst;
	float tunnel = smoothstep(open - 0.45, open + 0.15, edge);
	col = mix(col, col * vec3(0.55, 0.12, 0.1), tunnel * 0.5 * k);
	col *= 1.0 - tunnel * (0.75 * k + 0.25 * burst);
	col *= 1.0 - 0.6 * burst;

	COLOR = vec4(col, 1.0);
}
