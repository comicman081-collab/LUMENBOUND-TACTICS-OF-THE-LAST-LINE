shader_type spatial;
render_mode unshaded;
uniform vec4 base_color : source_color = vec4(0.18, 0.68, 0.58, 1.0);
void fragment() {
	float pulse = 0.82 + 0.18 * sin(TIME * 2.4);
	ALBEDO = base_color.rgb * pulse;
	EMISSION = base_color.rgb * 0.32 * pulse;
}
