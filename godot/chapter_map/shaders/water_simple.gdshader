shader_type spatial;
uniform vec4 shallow_color : source_color = vec4(0.10, 0.42, 0.58, 1.0);
void fragment() {
	float ripple = sin((VERTEX.x + VERTEX.z) * 6.0 + TIME * 1.6) * 0.035;
	ALBEDO = shallow_color.rgb + ripple;
	ROUGHNESS = 0.34;
}
