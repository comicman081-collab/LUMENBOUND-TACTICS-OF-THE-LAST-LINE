shader_type spatial;
render_mode cull_disabled;
varying vec3 world_point;
varying float top_face;
float hash_point(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float soil_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 fraction = fract(p);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), fraction.x), mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), fraction.x), fraction.y);
}
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	top_face = abs(NORMAL.y);
}
void fragment() {
	// World-scale surface detail is continuous across chunk and hex boundaries.
	// It needs no large bitmap or per-tile texture residency on a phone.
	// Irregular low-frequency soil avoids the visible fabric/checker pattern
	// and tightly striped cliff walls produced by the original sine lattice.
	float broad = soil_noise(world_point.xz * 1.3) - 0.5;
	float fine = soil_noise(world_point.xz * 9.0) - 0.5;
	float strata = soil_noise(vec2(world_point.x + world_point.z, world_point.y * 3.5)) - 0.5;
	float texture_value = mix(strata * 0.14 + broad * 0.07, broad * 0.18 + fine * 0.045, top_face);
	ALBEDO = COLOR.rgb * (1.0 + texture_value + (1.0 - top_face) * 0.08);
	ROUGHNESS = 0.94;
}
