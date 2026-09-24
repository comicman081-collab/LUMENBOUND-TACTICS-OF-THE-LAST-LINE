shader_type canvas_item;

// A light band periodically sweeps across a title label. Uses screen space
// because glyph UVs point into the font atlas and are not continuous.

uniform vec4 shine_color : source_color = vec4(1.0, 0.96, 0.84, 1.0);
uniform float period = 5.5;
uniform float width = 0.05;
uniform float strength = 0.75;

void fragment() {
	vec4 glyph = texture(TEXTURE, UV) * COLOR;
	float cycle = fract(TIME / period) * 1.8 - 0.4;
	float slant = SCREEN_UV.x + SCREEN_UV.y * 0.35;
	float band = exp(-pow((slant - cycle) / width, 2.0));
	COLOR = vec4(mix(glyph.rgb, shine_color.rgb, band * strength), glyph.a);
}
