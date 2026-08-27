shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 weather_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float ripple_intensity : hint_range(0.0, 1.0) = 0.16;
uniform float wet_weather : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float time_value = TIME * (0.16 + ripple_intensity * 0.17);
	vec2 point = UV * 18.0;
	float swell = sin(point.x * 1.16 + point.y * 0.74 + time_value) * 0.5 + 0.5;
	float cross = sin(point.y * 2.18 - point.x * 0.42 - time_value * 0.68) * 0.5 + 0.5;
	float long_wave = smoothstep(0.72, 0.94, sin(point.x * 0.46 - point.y * 0.91 + time_value * 1.42) * 0.5 + 0.5);
	float current_band = smoothstep(0.67, 0.88, sin(UV.x * 5.4 - UV.y * 2.1 + time_value * 0.72) * 0.5 + 0.5);
	float rain_ripple = smoothstep(0.90 - ripple_intensity * 0.18, 0.99, sin((point.x * 3.8 + point.y * 4.7) + TIME * 2.6) * 0.5 + 0.5);
	// R9 keeps the deep ocean distinct from the cool terrain grade: a blue
	// midtone and cyan tide are readable even during the rain-route preset.
	vec3 abyss = vec3(0.008, 0.055, 0.120);
	vec3 ocean = vec3(0.018, 0.255, 0.408);
	vec3 tide = vec3(0.080, 0.510, 0.590);
	float volume = clamp(swell * 0.40 + cross * 0.18 + long_wave * 0.27 + current_band * 0.15, 0.0, 1.0);
	vec3 base = mix(abyss, ocean, volume);
	base = mix(base, base * (1.0 - weather_tint.rgb * 0.34), wet_weather);
	base += tide * (long_wave * 0.31 + current_band * 0.14 + rain_ripple * ripple_intensity * 0.24);
	ALBEDO = mix(base, weather_tint.rgb, weather_tint.a * 0.35);
	EMISSION = vec3(0.010, 0.135, 0.205) * (long_wave * 0.54 + current_band * 0.22 + rain_ripple * 0.20 * ripple_intensity);
	ROUGHNESS = 0.42 + wet_weather * 0.10;
}
