shader_type canvas_item;
render_mode blend_add;

// Procedural floating light motes (lantern embers) in one draw call: each grid
// cell owns one mote that rises, drifts and twinkles. Three layers give depth.

uniform vec4 mote_color : source_color = vec4(0.62, 0.95, 0.88, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform float density = 1.0;
uniform float intensity = 0.9;
uniform float speed = 1.0;
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float layer(vec2 uv, float cells, float t, float size, float seed) {
	vec2 grid = uv * vec2(cells * aspect, cells);
	grid.y += t;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float h = hash(cell + seed);
	if (h > 0.45 * density) {
		return 0.0;
	}
	vec2 center = vec2(hash(cell + seed + 1.7), hash(cell + seed + 4.1));
	center.x += sin(t * 1.3 + h * 20.0) * 0.18;
	float d = length(local - center);
	float twinkle = 0.55 + 0.45 * sin(t * (2.0 + h * 3.0) + h * 40.0);
	return smoothstep(size, 0.0, d) * twinkle;
}

void fragment() {
	float t = TIME * speed;
	vec2 uv = UV;
	float near = layer(uv, 6.0, t * 0.10, 0.10, 3.0);
	float mid = layer(uv, 11.0, t * 0.16, 0.08, 9.0);
	float far = layer(uv, 19.0, t * 0.22, 0.07, 17.0);
	float fade = smoothstep(0.0, 0.25, uv.y) * (1.0 - smoothstep(0.9, 1.0, uv.y));
	vec3 c = mote_color.rgb * (mid * 0.8 + far * 0.5) + ember_color.rgb * near;
	float a = (near + mid * 0.8 + far * 0.5) * intensity * fade;
	COLOR = vec4(c * intensity * fade, a);
}
