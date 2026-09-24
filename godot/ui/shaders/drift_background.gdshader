shader_type canvas_item;

// Slow "Ken Burns" drift for still backgrounds plus a cinematic grade:
// breathing zoom, a gentle pan, vignette and a colour wash.

uniform float speed = 1.0;
uniform float zoom_base = 1.06;
uniform float zoom_amount = 0.025;
uniform float pan_amount = 0.012;
uniform float vignette = 0.55;
uniform vec4 tint : source_color = vec4(0.72, 0.84, 1.0, 1.0);
uniform float tint_strength = 0.18;
uniform float brightness = 1.0;

void fragment() {
	float t = TIME * speed;
	float zoom = zoom_base + sin(t * 0.07) * zoom_amount;
	vec2 pan = vec2(sin(t * 0.043), cos(t * 0.031)) * pan_amount;
	vec2 uv = vec2(0.5) + (UV - vec2(0.5)) / zoom + pan;
	vec4 c = texture(TEXTURE, uv);
	vec3 graded = mix(c.rgb, c.rgb * tint.rgb, tint_strength) * brightness;
	vec2 d = SCREEN_UV - vec2(0.5);
	float v = 1.0 - smoothstep(0.35, 0.95, length(d * vec2(1.25, 1.0))) * vignette;
	COLOR = vec4(graded * v, c.a) * COLOR;
}
