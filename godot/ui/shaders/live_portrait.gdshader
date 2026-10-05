shader_type canvas_item;

// Standing illustrations have no separate hair, face, arm or cloth layers.
// UV deformation bent faces and weapons. Translate the painted layer as one
// rigid image by a few pixels, preserving every face, hand and weapon contour.

uniform float phase = 0.0;
uniform vec4 rim_color : source_color = vec4(0.62, 0.92, 1.0, 1.0);
uniform float rim_strength = 0.32;
uniform float emphasis = 0.0;
uniform float dim = 0.0;
uniform float exposure = 1.0;
uniform float shadow_gamma = 1.0;
uniform float saturation = 1.0;

void fragment() {
	float t = TIME * 0.56 + phase;
	vec2 sample_uv = UV + vec2(sin(t * 0.67) * 0.0014, cos(t) * 0.0028);
	vec4 base = texture(TEXTURE, sample_uv);
	float px = TEXTURE_PIXEL_SIZE.x * 2.0;
	float py = TEXTURE_PIXEL_SIZE.y * 2.0;
	float around = min(min(texture(TEXTURE, sample_uv + vec2(px, 0.0)).a, texture(TEXTURE, sample_uv - vec2(px, 0.0)).a), texture(TEXTURE, sample_uv - vec2(0.0, py)).a);
	float edge = clamp(base.a - around, 0.0, 1.0);
	float light_pulse = 0.82 + 0.18 * sin(TIME * 0.8 + phase);
	vec3 graded = pow(max(base.rgb, vec3(0.0)), vec3(shadow_gamma));
	float luma = dot(graded, vec3(0.2126, 0.7152, 0.0722));
	graded = mix(vec3(luma), graded, saturation);
	vec3 lit = graded * exposure * (1.0 + emphasis * 0.08) * (1.0 - dim * 0.36);
	lit += rim_color.rgb * edge * rim_strength * light_pulse;
	COLOR = vec4(lit, base.a) * COLOR;
}
