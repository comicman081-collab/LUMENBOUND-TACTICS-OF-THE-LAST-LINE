shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.25, 0.4, 0.3, 1.0);
// 0 foliage, 1 weathered stone, 2 bark. Cached once per immutable palette.
uniform int surface_kind = 0;
varying vec3 surface_point;
varying float upward;
void vertex() {
	surface_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upward = clamp((MODEL_NORMAL_MATRIX * NORMAL).y, 0.0, 1.0);
}
void fragment() {
	float mottling = sin(surface_point.x * 23.0 + sin(surface_point.z * 17.0)) * sin(surface_point.z * 29.0 + surface_point.y * 31.0);
	float patches = sin(surface_point.x * 7.0 + surface_point.z * 9.0) * sin(surface_point.y * 11.0 - surface_point.z * 6.0);
	vec3 tint = base_color.rgb;
	if (surface_kind == 0) {
		// Warm crown, cool underside: volume remains legible without expensive
		// moving shadow maps or extra leaf textures on the Web target.
		tint *= 0.82 + upward * 0.30 + patches * 0.065 + mottling * 0.055;
		tint += vec3(0.036, 0.028, 0.006) * upward;
	} else if (surface_kind == 1) {
		tint *= 0.94 + patches * 0.10 + mottling * 0.045;
		tint = mix(tint, vec3(0.23, 0.31, 0.22), upward * smoothstep(-0.2, 0.8, patches) * 0.38);
	} else {
		float furrow = sin(surface_point.x * 72.0 + surface_point.z * 49.0 + sin(surface_point.y * 8.0));
		tint *= 0.91 + furrow * 0.08 + patches * 0.06;
	}
	ALBEDO = tint;
	ROUGHNESS = 0.93;
}
