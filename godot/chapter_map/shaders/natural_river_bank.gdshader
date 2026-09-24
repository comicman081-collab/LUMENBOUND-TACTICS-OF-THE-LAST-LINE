shader_type spatial;
uniform vec4 soil_color : source_color = vec4(.25,.33,.27,1.0);
void fragment() {
	float grain = sin(UV.x*11.0+UV.y*13.0)*sin(UV.x*6.1-UV.y*17.0);
	ALBEDO = soil_color.rgb * mix(.72, 1.05, smoothstep(0.0,1.0,UV.y)) * (1.0+grain*.045);
	ROUGHNESS = .97;
}
