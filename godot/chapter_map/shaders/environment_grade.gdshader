shader_type canvas_item;
render_mode unshaded;

// Applied only inside the chapter-map SubViewport layer. HUD controls are a
// sibling above this rect and deliberately never receive this presentation tint.
uniform vec4 world_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float radius = length(centered_uv);
	float edge = smoothstep(0.34, 1.30, radius);
	float alpha = clamp(world_tint.a + edge * vignette_amount, 0.0, 0.92);
	COLOR = vec4(world_tint.rgb, alpha);
}
