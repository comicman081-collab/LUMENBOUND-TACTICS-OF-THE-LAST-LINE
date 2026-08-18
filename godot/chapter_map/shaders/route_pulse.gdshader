shader_type spatial;
render_mode unshaded;
uniform vec4 route_color : source_color = vec4(0.45, 1.0, 0.88, 1.0);
void fragment() {
	float wave = 0.7 + 0.3 * sin(TIME * 4.0 + UV.x * 18.0);
	ALBEDO = route_color.rgb * wave;
	EMISSION = route_color.rgb * wave;
}
