shader_type spatial;
uniform vec4 fog_color : source_color = vec4(0.035, 0.07, 0.11, 1.0);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	ALBEDO = mix(fog_color.rgb, vec3(0.10, 0.20, 0.22), reveal);
	ROUGHNESS = 1.0;
}
