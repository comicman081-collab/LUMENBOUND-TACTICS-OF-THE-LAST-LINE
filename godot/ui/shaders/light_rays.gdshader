shader_type canvas_item;
render_mode blend_add;

// Soft volumetric light shafts radiating from `origin` (in rect UV space).
// Drawn additively over the background; slow rotation keeps them alive.

uniform vec2 origin = vec2(0.72, -0.08);
uniform vec4 ray_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float intensity = 0.32;
uniform float speed = 1.0;
uniform float reach = 1.35;

void fragment() {
	float t = TIME * speed;
	vec2 d = UV - origin;
	d.x *= 1.6;
	float angle = atan(d.y, d.x);
	float dist = length(d);
	float rays = pow(max(0.0, sin(angle * 13.0 + t * 0.21) * 0.5 + 0.5), 4.0) * 0.7;
	rays += pow(max(0.0, sin(angle * 7.0 - t * 0.17 + 1.3) * 0.5 + 0.5), 6.0) * 0.6;
	float falloff = (1.0 - smoothstep(0.0, reach, dist)) * smoothstep(0.02, 0.18, dist);
	float glow = exp(-dist * 3.2) * 0.35;
	float a = (rays * falloff + glow) * intensity * (0.85 + 0.15 * sin(t * 0.9));
	COLOR = vec4(ray_color.rgb * a, a);
}
