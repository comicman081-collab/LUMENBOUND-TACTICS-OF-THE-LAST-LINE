shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 water_color : source_color = vec4(0.10, 0.29, 0.31, 1.0);
void fragment() {
	float edge = abs(UV.y * 2.0 - 1.0);
	float ripple = sin(UV.x * 2.4 - TIME * .62 + sin(UV.y * 9.0)) * .5 + .5;
	float broad = sin(UV.x * .31 + UV.y * 4.0 - TIME * .18) * .5 + .5;
	vec3 deep = water_color.rgb * .84;
	vec3 shallow = mix(water_color.rgb, vec3(.31,.39,.32), .25);
	ALBEDO = mix(deep, shallow, smoothstep(.22,1.0,edge)) * (.98 + broad*.04);
	ALBEDO += vec3(.015,.025,.025) * smoothstep(.89,.98,ripple) * (1.0-edge*.45);
	ROUGHNESS = .62;
}
