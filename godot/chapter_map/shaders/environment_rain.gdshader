shader_type canvas_item;
render_mode unshaded;

// Procedural rain is bounded by three fixed canvas layers. It creates no
// gameplay nodes, allocates no particles and never consumes gameplay RNG.
uniform vec4 rain_color : source_color = vec4(0.68, 0.88, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.1, 4.0) = 1.0;
uniform float wind : hint_range(-1.0, 1.0) = 0.0;
uniform float density : hint_range(0.1, 4.0) = 1.0;
uniform float layer_scale : hint_range(0.4, 2.0) = 1.0;
uniform float camera_phase = 0.0;
uniform float splash_strength : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 point) {
	point = fract(point * vec2(91.17, 41.73));
	point += dot(point, point + 19.19);
	return fract(point.x * point.y);
}

void fragment() {
	vec2 uv = UV;
	uv.x += uv.y * wind * 0.18 + camera_phase * 0.004;
	uv.y += TIME * speed * 0.34;
	// A deliberately sparse, short-streak pattern.  Three depth layers stay
	// readable during STORM instead of accumulating into a white screen.
	vec2 grid = vec2(20.0, 30.0) * density * layer_scale;
	vec2 cell = floor(uv * grid);
	vec2 local = fract(uv * grid);
	float seed = hash21(cell);
	float lane = fract(seed * 19.7);
	float fall_position = fract(seed * 11.31 + TIME * speed * 0.72 + cell.x * 0.13);
	float vertical_offset = local.y - fall_position;
	// The line shears slightly with the wind; it reads as rain rather than
	// square snow pixels at the actual Web-map scale.
	float center_distance = abs(local.x - lane - vertical_offset * wind * 0.62);
	float width = mix(0.006, 0.014, layer_scale);
	float streak = 1.0 - smoothstep(width, width * 2.5, center_distance);
	float length_mask = 1.0 - smoothstep(0.090, 0.260 + seed * 0.045, abs(vertical_offset));
	float rain = streak * length_mask * step(0.80, seed) * intensity;
	float splash = 0.0;
	if (UV.y > 0.64) {
		float splash_phase = fract(TIME * speed * 0.55 + seed * 7.0);
		float ring = 1.0 - smoothstep(0.025, 0.070, abs(length(local - vec2(lane, splash_phase)) - 0.045));
		splash = ring * splash_strength * intensity * step(0.62, seed);
	}
	float alpha = clamp(rain * 0.58 + splash * 0.36, 0.0, 0.56);
	COLOR = vec4(rain_color.rgb, alpha);
}
