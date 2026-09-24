shader_type canvas_item;

// Live2D-style idle motion for a flat illustration. The texture is not rigged,
// so the motion is a UV deformation anchored at the feet: breathing stretches
// the body upward, the upper body sways more than the legs, a fine ripple moves
// hair and cloth, and a thin rim light follows the silhouette.

uniform float phase = 0.0;
uniform float speed = 1.0;
uniform float breath_amount = 0.012;
uniform float sway_amount = 0.008;
uniform float wave_amount = 0.0022;
uniform float anchor_y = 0.97;
uniform vec4 rim_color : source_color = vec4(0.62, 0.92, 1.0, 1.0);
uniform float rim_strength = 0.45;
uniform float emphasis = 0.0;
uniform float dim = 0.0;

void fragment() {
	float t = TIME * speed + phase;
	float height = clamp((anchor_y - UV.y) / max(anchor_y, 0.01), 0.0, 1.0);
	float breath = sin(t * 1.85) * breath_amount;
	vec2 uv = UV;
	uv.y = anchor_y + (UV.y - anchor_y) / (1.0 + breath * height);
	uv.x -= sin(t * 1.1) * sway_amount * height * height;
	uv.x += sin(UV.y * 42.0 + t * 3.2) * wave_amount * height * height;
	vec4 base = texture(TEXTURE, uv);
	float px = TEXTURE_PIXEL_SIZE.x * 3.0;
	float py = TEXTURE_PIXEL_SIZE.y * 3.0;
	float around = min(min(texture(TEXTURE, uv + vec2(px, 0.0)).a, texture(TEXTURE, uv - vec2(px, 0.0)).a), texture(TEXTURE, uv - vec2(0.0, py)).a);
	float edge = clamp(base.a - around, 0.0, 1.0);
	vec3 lit = base.rgb * (1.0 + emphasis * 0.12) * (1.0 - dim * 0.45);
	lit += rim_color.rgb * edge * rim_strength * (0.75 + 0.25 * sin(t * 1.3));
	COLOR = vec4(lit, base.a) * COLOR;
}
