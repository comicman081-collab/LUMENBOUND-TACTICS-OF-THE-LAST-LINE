shader_type canvas_item;
render_mode blend_mix;

// Map atmosphere (phase 2): a light tilt-shift blur on the top and bottom
// bands for a miniature read, and distance haze towards the far (top) side.
// Drawn over the map SubViewport only; the HUD sits in a sibling above it.
// It must be the first screen-texture reader in the presentation layer so the
// copy it blurs is the plain 3D frame.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 haze_color : source_color = vec4(0.62, 0.78, 0.80, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.20;
uniform float tilt_amount : hint_range(0.0, 1.0) = 1.0;
uniform float top_band = 0.30;
uniform float bottom_band = 0.20;

void fragment() {
	float top = 1.0 - smoothstep(0.0, top_band, UV.y);
	float bottom = smoothstep(1.0 - bottom_band, 1.0, UV.y);
	float blur = max(top, bottom * 0.8) * tilt_amount;
	float lod = blur * 2.6;
	vec2 spread = SCREEN_PIXEL_SIZE * (1.0 + blur * 4.0);
	vec3 color = textureLod(screen_texture, SCREEN_UV, lod).rgb * 0.36;
	color += textureLod(screen_texture, SCREEN_UV + vec2(spread.x, spread.y), lod).rgb * 0.16;
	color += textureLod(screen_texture, SCREEN_UV + vec2(-spread.x, spread.y), lod).rgb * 0.16;
	color += textureLod(screen_texture, SCREEN_UV + vec2(spread.x, -spread.y), lod).rgb * 0.16;
	color += textureLod(screen_texture, SCREEN_UV + vec2(-spread.x, -spread.y), lod).rgb * 0.16;
	float haze = top * top * haze_amount;
	color = mix(color, haze_color.rgb, haze);
	COLOR = vec4(color, clamp(blur * 1.25 + haze, 0.0, 1.0));
}
