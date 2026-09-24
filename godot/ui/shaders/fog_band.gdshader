shader_type canvas_item;

// Low drifting mist for the lower part of a scene (value noise, two layers).

uniform vec4 fog_color : source_color = vec4(0.55, 0.72, 0.86, 1.0);
uniform float intensity = 0.35;
uniform float speed = 1.0;
uniform float top = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	vec2 p = UV * vec2(5.0, 2.2);
	float n = noise(p + vec2(t * 0.05, 0.0)) * 0.6 + noise(p * 2.1 - vec2(t * 0.08, t * 0.01)) * 0.4;
	float mask = smoothstep(top, 1.0, UV.y);
	float a = n * mask * intensity;
	COLOR = vec4(fog_color.rgb, a);
}
