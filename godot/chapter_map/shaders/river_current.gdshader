shader_type spatial;
render_mode unshaded, cull_back;
varying vec2 world_xz;
void vertex() { world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	// World-anchored, slow current: no UV seams, particles or flashing highlights.
	float current = sin(world_xz.x * 1.7 + world_xz.y * 2.4 - TIME * 0.42);
	float cross = sin(world_xz.x * 3.1 - world_xz.y * 1.3 + TIME * 0.21);
	float reflection = smoothstep(0.76, 0.98, current * 0.5 + 0.5) * (cross * 0.12 + 0.14);
	ALBEDO = mix(vec3(0.045, 0.20, 0.22), vec3(0.10, 0.34, 0.34), current * 0.18 + 0.50) + vec3(0.19, 0.27, 0.23) * reflection;
	ROUGHNESS = 0.45;
}
