shader_type canvas_item;
render_mode unshaded;

// Cheap value noise makes the atmosphere read as a depth band instead of a
// static grey rectangle. camera_phase is a tiny world-derived offset so a pan
// does not make the haze feel glued to the monitor.
uniform vec4 fog_tint : source_color = vec4(0.18, 0.36, 0.42, 0.0);
uniform float density : hint_range(0.0, 1.0) = 0.0;
uniform float drift_speed : hint_range(0.0, 0.10) = 0.008;
uniform float depth_weight : hint_range(0.1, 2.0) = 1.0;
uniform float camera_phase = 0.0;

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 345.45));
	point += dot(point, point + 34.345);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

void fragment() {
	vec2 drift = vec2(TIME * drift_speed + camera_phase * 0.007, TIME * drift_speed * 0.27);
	float large_noise = value_noise(UV * vec2(3.1, 2.3) + drift);
	float fine_noise = value_noise(UV * vec2(8.0, 5.2) - drift * 0.62);
	float mist = mix(large_noise, fine_noise, 0.32);
	float depth_falloff = pow(clamp(1.0 - UV.y * 0.76, 0.0, 1.0), depth_weight);
	float alpha = density * depth_falloff * mix(0.28, 1.0, mist);
	COLOR = vec4(fog_tint.rgb, alpha);
}
