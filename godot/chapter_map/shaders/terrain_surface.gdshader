shader_type spatial;
render_mode cull_disabled;
// Region look (phase 2 map surface). The map sets these from the chapter's
// region palette; the defaults are the chapter 1 forest. Colours are raw
// values like the vertex COLOR they blend with, so they carry no sRGB hint.
uniform float tile_size = 1.08;
uniform float elevation_step = 0.86;
uniform vec4 ground_color = vec4(0.259, 0.345, 0.286, 1.0);
uniform vec4 patch_color = vec4(0.235, 0.345, 0.176, 1.0);
uniform float patch_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec4 wear_color = vec4(0.580, 0.530, 0.400, 1.0);
uniform float wear_amount : hint_range(0.0, 1.0) = 0.45;
uniform vec4 lip_color = vec4(0.290, 0.420, 0.200, 1.0);
uniform float ocean_y = -1.55;
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
// Offset of a world xz point from its pointy-top hex centre (axial rounding,
// same layout as HexCoord.axial_to_world).
vec2 hex_local(vec2 xz) {
	float q = (sqrt(3.0) / 3.0 * xz.x - xz.y / 3.0) / tile_size;
	float r = (2.0 / 3.0 * xz.y) / tile_size;
	vec3 cube = vec3(q, -q - r, r);
	vec3 rounded = round(cube);
	vec3 diff = abs(rounded - cube);
	if (diff.x > diff.y && diff.x > diff.z) {
		rounded.x = -rounded.y - rounded.z;
	} else if (diff.y > diff.z) {
		rounded.y = -rounded.x - rounded.z;
	} else {
		rounded.z = -rounded.x - rounded.y;
	}
	vec2 center = vec2(tile_size * sqrt(3.0) * (rounded.x + rounded.z * 0.5), tile_size * 1.5 * rounded.z);
	return xz - center;
}
// 0 at the hex centre, 1 on its edge.
float hex_edge(vec2 p) {
	float d = max(abs(p.x), max(abs(p.x * 0.5 + p.y * 0.8660254), abs(p.x * 0.5 - p.y * 0.8660254)));
	return d / (tile_size * 0.8660254);
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
	vec3 albedo = COLOR.rgb * (1.0 + texture_value + (1.0 - top_face) * 0.08);
	float top = smoothstep(0.82, 0.97, top_face);
	// Tops: region patches (moss, frost, sand...) only on open ground, then a
	// worn, slightly sunken rim along each hex edge broken up by noise.
	float ground_match = 1.0 - smoothstep(0.035, 0.11, distance(COLOR.rgb, ground_color.rgb));
	float patch_noise = soil_noise(world_point.xz * 0.85 + vec2(7.3, 1.9)) + fine * 0.55;
	float patch_mask = smoothstep(0.52, 0.72, patch_noise) * ground_match * patch_amount;
	albedo = mix(albedo, patch_color.rgb * (1.0 + fine * 0.5), patch_mask * top * 0.75);
	float edge = hex_edge(hex_local(world_point.xz));
	float groove = smoothstep(0.90, 0.995, edge);
	float worn = smoothstep(0.74, 0.93, edge) * (1.0 - groove) * smoothstep(0.42, 0.62, soil_noise(world_point.xz * 4.2));
	albedo = mix(albedo, wear_color.rgb, worn * wear_amount * 0.42 * top);
	albedo *= 1.0 - groove * 0.16 * top;
	// Cliffs: layered strata, a grassy overhang just below each terrace lip,
	// and a steady darkening towards the sea.
	float wall = 1.0 - smoothstep(0.30, 0.60, top_face);
	float below_lip = mod(0.018 - world_point.y, elevation_step);
	float bands = sin(world_point.y * 17.0 + soil_noise(world_point.xz * 2.2) * 5.0) * 0.5 + 0.5;
	albedo *= 1.0 - wall * (0.10 * smoothstep(0.55, 0.95, bands) + 0.10 * smoothstep(0.08, 0.80, below_lip / elevation_step));
	float lip = (1.0 - smoothstep(0.02, 0.16, below_lip)) * smoothstep(0.35, 0.6, soil_noise(world_point.xz * 6.0 + world_point.y));
	albedo = mix(albedo, lip_color.rgb, lip * wall * 0.62);
	float depth_dark = mix(0.52, 1.0, smoothstep(ocean_y, ocean_y + 2.6, world_point.y));
	albedo *= mix(1.0, depth_dark, wall);
	ALBEDO = albedo;
	ROUGHNESS = 0.94;
}
