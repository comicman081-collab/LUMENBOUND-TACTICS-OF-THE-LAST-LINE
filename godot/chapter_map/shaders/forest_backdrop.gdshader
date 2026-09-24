shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 soil_dark : source_color = vec4(0.13, 0.21, 0.16, 1.0);
uniform vec4 soil_light : source_color = vec4(0.23, 0.29, 0.18, 1.0);
varying vec2 world_xz;
float hash_point(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float moss_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 fraction = fract(p);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), fraction.x), mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), fraction.x), fraction.y);
}
void vertex() { world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	// Broad moss/stone bands at world scale; no screen-space pattern sliding
	// when the tactical camera pans. Existing map greens remain authoritative.
	float ridge = sin(world_xz.x * 0.13 + sin(world_xz.y * 0.11) * 1.8);
	float clearing = sin(world_xz.y * 0.31 - world_xz.x * 0.08) * ridge;
	float patches = moss_noise(world_xz * 0.8);
	float grain = moss_noise(world_xz * 7.0) - 0.5;
	vec3 moss = mix(soil_dark.rgb, soil_light.rgb, clamp(clearing * 0.25 + patches * 0.55 + 0.15, 0.0, 1.0));
	ALBEDO = moss + vec3(0.012, 0.016, 0.009) * grain;
	ROUGHNESS = 1.0;
}
