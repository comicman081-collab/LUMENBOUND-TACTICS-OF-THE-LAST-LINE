shader_type canvas_item;

// Hex cells that live in world space, drawn as 2D triangles through the map
// camera's projection on the GPU.
//
// The chapter map's movement range, route cells and orientation grid used to be
// projected on the CPU once and then slid around as one rigid Control. A rigid
// slide is only right for an orthographic camera: under the perspective camera
// every height and depth moves by a different amount, so highlighted cells
// drifted off the terrain (worst on raised plateaus) whenever the camera panned,
// zoomed or played a camera moment. Projecting here means the overlay is exact
// for every camera, and a pan costs one uniform upload instead of a rebuild.
//
// Vertex layout (ArrayMesh, 2D vertices):
//   VERTEX = world (x, z)
//   UV.x   = world height (y)
//   UV.y   = distance field, see the two modes below.
//
// Cell mode (ribbon = 0): UV.y is 1.0 at the cell centre and 0.0 on both corners of
// an outlined outer edge, so UV.y / |grad UV.y| is the screen distance to that edge:
// a fill plus a constant-pixel outline. A corner pair with UV.y = 1.0 (flat) has no
// outline on that edge.
// Ribbon mode (ribbon = 1): a band of world width. UV.y is 0.0 along both long sides
// and 1.0 along the middle line; only the line colour is painted, anti-aliased on
// the sides.

uniform mat4 world_to_clip;
uniform vec2 target_size = vec2(1280.0, 720.0);
uniform vec4 fill_color = vec4(0.0);
uniform vec4 line_color = vec4(1.0);
uniform float ribbon = 0.0;
// Half width of the outline in canvas pixels, and physical pixels per canvas pixel.
uniform float line_half_width = 1.0;
uniform float px_scale = 1.0;
uniform float opacity = 1.0;

void vertex() {
	vec4 clip = world_to_clip * vec4(VERTEX.x, UV.x, VERTEX.y, 1.0);
	// Cells are only ever submitted well in front of the camera; the clamp just
	// keeps a stray vertex from turning into NaN.
	float w = max(clip.w, 0.05);
	vec2 ndc = clip.xy / w;
	VERTEX = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5) * target_size;
}

void fragment() {
	float edge = UV.y;
	float gradient = max(length(vec2(dFdx(edge), dFdy(edge))), 1.0e-5);
	float distance_px = edge / gradient;
	if (ribbon > 0.5) {
		float band_alpha = line_color.a * clamp(distance_px + 0.5, 0.0, 1.0) * opacity;
		if (band_alpha < 0.004) {
			discard;
		}
		COLOR = vec4(line_color.rgb, band_alpha);
	} else {
		float half_width = max(line_half_width * px_scale, 0.0);
		float line_alpha = line_color.a * (1.0 - smoothstep(half_width - 0.5, half_width + 0.5, distance_px)) * opacity;
		float fill_alpha = fill_color.a * opacity;
		float alpha = line_alpha + fill_alpha * (1.0 - line_alpha);
		if (alpha < 0.004) {
			discard;
		}
		vec3 rgb = (line_color.rgb * line_alpha + fill_color.rgb * fill_alpha * (1.0 - line_alpha)) / max(alpha, 1.0e-5);
		COLOR = vec4(rgb, alpha);
	}
}
