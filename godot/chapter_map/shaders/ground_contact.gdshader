shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	vec2 offset = (UV - vec2(0.5)) * 2.0;
	float radius = dot(offset, offset);
	ALBEDO = vec3(0.035, 0.07, 0.045);
	ALPHA = (1.0 - smoothstep(0.08, 1.0, radius)) * 0.22;
}
