shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 reveal_center_px = vec2(640.0, 360.0);
uniform vec2 overlay_size_px = vec2(1280.0, 720.0);
uniform float reveal_radius_px = 260.0;
uniform float feather_px = 48.0;

float mist_noise(vec2 p) {
	return fract(sin(dot(p, vec2(91.7, 271.9))) * 43758.5453);
}

void fragment() {
	vec2 pixel = UV * overlay_size_px;
	float distance_from_squad = distance(pixel, reveal_center_px);
	float mask = smoothstep(reveal_radius_px - feather_px, reveal_radius_px + feather_px, distance_from_squad);
	vec2 drift = UV * 7.0 + vec2(TIME * 0.035, -TIME * 0.024);
	float grain = mist_noise(floor(drift * 7.0));
	float wave = sin(drift.x * 2.4 + drift.y * 1.8 + TIME * 0.22) * 0.5 + 0.5;
	float cloud = clamp(grain * 0.38 + wave * 0.42, 0.08, 0.88);
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, 5.8).rgb;
	vec3 charcoal = mix(vec3(0.018, 0.027, 0.034), vec3(0.17, 0.20, 0.20), cloud);
	vec3 fogged = mix(blurred * 0.16, charcoal, 0.88);
	COLOR = vec4(fogged, mask * (0.91 + cloud * 0.07));
}
