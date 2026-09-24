shader_type canvas_item;
render_mode unshaded;

// A battle source cell contains a complete posed body.  The tactical HUD is a
// face-only affordance, so it crops around a supplied face anchor rather than
// reducing the whole pose into an unreadable miniature.  It never modifies the
// source texture or its alpha provenance. While the ultimate is charging the
// face is desaturated and dimmed; a ready ultimate shows in full colour.
uniform vec2 portrait_focus = vec2(0.50, 0.24);
uniform float portrait_zoom = 2.45;
uniform float saturation = 1.0;
uniform float brightness = 1.0;

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float circular_alpha = 1.0 - smoothstep(0.910, 1.0, length(centered));
	vec2 portrait_uv = portrait_focus + (UV - vec2(0.5)) / max(portrait_zoom, 1.0);
	portrait_uv = clamp(portrait_uv, vec2(0.001), vec2(0.999));
	vec4 portrait = texture(TEXTURE, portrait_uv);
	float grey = dot(portrait.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = mix(vec3(grey), portrait.rgb, saturation) * brightness;
	COLOR = vec4(rgb, portrait.a * circular_alpha);
}
