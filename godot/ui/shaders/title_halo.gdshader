shader_type canvas_item;
render_mode blend_add;

// Lantern halo behind the title cast: concentric gold and teal rings with slow
// arcs, tick marks and a soft glow that breathe with the shared heartbeat. Pings
// leave the centre on every beat. Purely additive, so it never covers the art.

uniform vec2 rect_px = vec2(1920.0, 1080.0);
uniform vec2 center_px = vec2(1500.0, 500.0);
uniform float unit_px = 1000.0;
uniform float u_time = 0.0;
uniform float beat = 0.3;
uniform float amount = 1.0;
uniform vec3 ping = vec3(-1.0, -1.0, -1.0);   // ping ages in seconds, < 0 = off
uniform vec3 gold = vec3(0.93, 0.78, 0.46);
uniform vec3 teal = vec3(0.34, 0.95, 0.86);

const float TAU_F = 6.28318530718;

float ring(float r, float radius, float width_px, float aa) {
	float w = width_px / unit_px;
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(r - radius));
}

void fragment() {
	vec2 d = UV * rect_px - center_px;
	float r = length(d) / unit_px;
	float an = atan(d.y, d.x);
	float aa = fwidth(r) * 1.1;
	vec3 col = vec3(0.0);
	// outer ring with four bright arcs
	float arcs = smoothstep(0.80, 0.93, cos(4.0 * (an - u_time * 0.05)));
	float ra = ring(r, 0.45, 1.5, aa) * (0.24 + 0.9 * arcs);
	col += gold * ra;
	// dashed ring
	float dash = step(0.5, fract((an + u_time * 0.035) * 60.0 / TAU_F));
	col += teal * ring(r, 0.385, 1.2, aa) * dash * 0.30;
	// inner thin ring with three markers
	float mk = smoothstep(0.985, 0.999, cos(3.0 * (an + u_time * 0.08)));
	col += mix(teal, gold, 0.35) * (ring(r, 0.305, 1.1, aa) * 0.15 + ring(r, 0.305, 5.0, aa) * mk * 0.8);
	// tick marks
	float tk = smoothstep(0.55, 0.62, abs(fract(an * 120.0 / TAU_F + 0.5) - 0.5) * 2.0);
	float tr = smoothstep(0.412, 0.414, r) * smoothstep(0.428, 0.426, r);
	col += gold * (1.0 - tk) * tr * 0.34;
	// soft halo
	float halo = exp(-pow((r - 0.22) / 0.30, 2.0)) * 0.20 * (0.6 + 0.4 * beat);
	col += mix(gold, teal, smoothstep(0.0, 0.5, r)) * halo;
	// pings emitted on the heartbeat
	for (int i = 0; i < 3; i++) {
		float age = ping[i];
		if (age < 0.0) {
			continue;
		}
		float radius = 0.12 + age * 0.21;
		float al = exp(-age * 1.25) * smoothstep(0.0, 0.12, age);
		float pr = ring(r, radius, 2.2, aa) * al * 0.8 + exp(-pow((r - radius) / 0.02, 2.0)) * al * 0.5;
		col += teal * pr;
	}
	COLOR = vec4(col * amount, 1.0);
}
