shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, unshaded, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 fog_color : source_color = vec4(0.035, 0.055, 0.065, 0.98);
uniform vec4 fog_highlight : source_color = vec4(0.20, 0.24, 0.24, 0.98);
uniform float blur_lod : hint_range(1.0, 6.0) = 5.6;

float mist_noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 drift = UV * 3.2 + vec2(TIME * 0.045, -TIME * 0.028);
	float soft = mist_noise(floor(drift * 2.0));
	float wave_a = sin(drift.x * 2.7 + drift.y * 1.4 + TIME * 0.32) * 0.5 + 0.5;
	float wave_b = sin(drift.y * 3.1 - drift.x * 0.9 - TIME * 0.21) * 0.5 + 0.5;
	float cloud = clamp(0.12 + soft * 0.24 + wave_a * 0.22 + wave_b * 0.14, 0.12, 0.72);
	// Fog-of-war is a real obscuring veil, not a dark map-border colour. Sample
	// the already rendered map at a coarse mip so undiscovered terrain loses
	// detail, then layer moving pale mist over that blurred image.
	vec3 blurred_map = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	vec3 mist_tint = mix(fog_color.rgb, fog_highlight.rgb, cloud);
	// Unseen territory must read immediately as unavailable information. Keep a
	// heavily blurred ghost of the terrain, but bury its colour/detail under a
	// dense charcoal mist instead of the former pale teal wash that resembled sea.
	ALBEDO = mix(blurred_map * 0.24, mist_tint, 0.82 + cloud * 0.10);
	ALPHA = clamp(0.94 + cloud * 0.05, 0.94, 0.99);
}
