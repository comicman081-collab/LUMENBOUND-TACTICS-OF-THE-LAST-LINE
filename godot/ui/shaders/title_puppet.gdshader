shader_type canvas_item;
render_mode blend_premul_alpha;

// Title "shader puppet": one standing illustration, warped per pixel by analytic
// deformers and soft region masks. No extra layers, no mesh, no SDK. The painted
// art is the authority; everything below only moves where each pixel is read from.
//   * body: weight shift about the feet, waist counter-rotation, breathing
//   * head: roll about the neck, face parallax (yaw / pitch), eyelid blink, gaze
//   * hair and cloth: simulated by the controller, applied here through the masks
//   * the hanging weapon: its own layer (lantern_tex), swung rigidly about the grip and drawn
//     over the hero image; a displacement field cannot do it, the gap to the cape is 3 px
// The forward displacement field disp(x) is inverted with a few fixed-point steps
// (q = src - disp(q)), which keeps strands and edges clean at these amplitudes.
//
// Textures
//   hero_tex  premultiplied RGBA of the illustration (mipmapped)
//   mask_a    half resolution: R/G/B hair chains A/B/C, A face profile
//   mask_b    half resolution: R cloth, B emissive crystals, A gold/silver trim
//   lantern_tex  premultiplied RGBA of the chain and lantern, cut out of hero_tex (CHR001 only)
// All geometry below is in source pixels of hero_tex.

uniform sampler2D hero_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_a : filter_linear, repeat_disable;
uniform sampler2D mask_b : filter_linear_mipmap, repeat_disable;
uniform sampler2D lantern_tex : filter_linear_mipmap, repeat_disable;

uniform vec2 tex_size = vec2(1086.0, 1448.0);
uniform vec4 src_rect = vec4(-64.0, -64.0, 1150.0, 1512.0);   // visible source rectangle (x0, y0, x1, y1)
uniform vec4 lantern_rect = vec4(0.0);                         // x, y, w, h of lantern_tex in source px; w = 0: no lantern layer
uniform vec2 lantern_seam = vec2(722.0, 740.0);                // rows where hero_tex and lantern_tex overlap and cross-fade

// rig geometry (per hero)
uniform vec4 body_geo = vec4(540.0, 1425.0, 700.0, 0.0);       // centre x, feet y, waist y
uniform vec4 neck_geo = vec4(512.0, 250.0, 238.0, 300.0);      // neck x, y, head fully moving above, head still below
uniform vec4 breath_geo = vec4(260.0, 560.0, 3.0, 0.0);        // rise fully above y.x, none below y.y, rise px
uniform vec4 exp_geo = vec4(250.0, 330.0, 520.0, 700.0);       // chest expansion band: 0 -> 1 -> 1 -> 0
uniform vec4 face_geo = vec4(512.0, 192.0, 58.0, 64.0);        // face centre and half extent
uniform vec4 flutter_geo = vec4(60.0, 360.0, 0.0, 0.0);        // strand flutter fades in between these y values

uniform vec4 eye_a[2];     // cx, cy, theta, half width
uniform vec4 eye_b[2];     // lash top, lower lid, lash thickness, skew
uniform vec4 eye_c[2];     // iris x, iris y, iris radius
uniform vec3 eye_top[2];   // lid colour at the crease
uniform vec3 eye_bot[2];   // lid colour above the lash band

uniform vec2 ha_root = vec2(585.0, 58.0);
uniform float ha_r[6];
uniform vec2 ha_u[6];
uniform vec2 hb_root = vec2(445.0, 100.0);
uniform float hb_r[6];
uniform vec2 hb_u[6];
uniform vec2 hc_root = vec2(520.0, 92.0);
uniform float hc_r[6];
uniform vec2 hc_u[6];

// animation state (controller)
uniform float u_time = 0.0;
uniform vec4 body_rot = vec4(0.0);        // x sway about the feet, y waist counter-rotation, z breath 0..1
uniform vec4 head_mv = vec4(0.0);         // x, y translation (src px), z roll (rad), w yaw parallax (src px)
uniform vec4 head_mv2 = vec4(0.0, 0.0, 0.0, 1.0);  // x pitch parallax, y z gaze (src px), w strand flutter amount
uniform vec2 blink = vec2(0.0);
uniform vec4 pend = vec4(240.0, 725.0, 0.0, 0.0);  // pivot xy, angle (rad)
uniform vec4 cloth = vec4(0.0, 0.0, 0.0, 0.012);   // offset px, wave px, wave phase, wave frequency

// look
uniform vec4 grade = vec4(1.22, 0.82, 1.12, 0.0);  // exposure, shadow gamma, saturation
uniform vec4 fx = vec4(0.3, 1.0, 0.5, 1.0);        // heartbeat, reveal 0..1, rim strength, emissive gain
uniform vec4 fx2 = vec4(1.0, 0.0, 0.0, 0.0);       // opacity, debug masks, minify lod, quality 0..2
uniform vec4 rim_color = vec4(0.72, 1.0, 0.95, 1.0);
uniform vec4 emis_color = vec4(0.3, 1.0, 0.95, 1.0);
uniform vec4 edge_color = vec4(0.5, 1.0, 0.95, 1.0);
uniform vec4 glint_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform vec4 glint = vec4(-1000.0, 90.0, 0.0, 0.0);  // position along glint_dir, width, amount
uniform vec2 glint_dir = vec2(0.8, 0.6);
uniform vec2 rim_dir = vec2(0.86, -0.5);
uniform float rim_px = 5.0;
uniform float glow_amount = 0.25;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 chain_a(vec2 x) {
	float s = length(x - ha_root);
	vec2 r = ha_u[0];
	for (int i = 1; i < 6; i++) {
		r = mix(r, ha_u[i], smoothstep(ha_r[i - 1], ha_r[i], s));
	}
	return r;
}

vec2 chain_b(vec2 x) {
	float s = length(x - hb_root);
	vec2 r = hb_u[0];
	for (int i = 1; i < 6; i++) {
		r = mix(r, hb_u[i], smoothstep(hb_r[i - 1], hb_r[i], s));
	}
	return r;
}

vec2 chain_c(vec2 x) {
	float s = length(x - hc_root);
	vec2 r = hc_u[0];
	for (int i = 1; i < 6; i++) {
		r = mix(r, hc_u[i], smoothstep(hc_r[i - 1], hc_r[i], s));
	}
	return r;
}

// forward displacement of the content that sits at source position x
vec2 disp(vec2 x, out vec4 ma, out vec4 mb) {
	vec2 d = vec2(0.0);
	float cx = body_geo.x;
	d += body_rot.x * vec2(-(x.y - body_geo.y), x.x - cx);
	d += body_rot.y * smoothstep(body_geo.z + 140.0, body_geo.z - 120.0, x.y) * vec2(-(x.y - body_geo.z), x.x - cx);
	float breath = body_rot.z;
	d.y -= breath * breath_geo.z * smoothstep(breath_geo.y, breath_geo.x, x.y);
	d.x += (x.x - cx) * 0.005 * breath * smoothstep(exp_geo.w, exp_geo.z, x.y) * smoothstep(exp_geo.x, exp_geo.y, x.y);
	float wh = 1.0 - smoothstep(neck_geo.z, neck_geo.w, x.y);
	vec2 r = x - neck_geo.xy;
	float cs = cos(head_mv.z);
	float sn = sin(head_mv.z);
	d += wh * (vec2(cs * r.x - sn * r.y, sn * r.x + cs * r.y) - r + head_mv.xy);
	vec2 uv = x / tex_size;
	ma = textureLod(mask_a, uv, 0.0);
	mb = textureLod(mask_b, uv, 0.0);
	float hv = ma.r + ma.g + ma.b;
	d += (ma.r * chain_a(x) + ma.g * chain_b(x) + ma.b * chain_c(x)) / max(1.0, hv);
	if (hv > 0.01 && head_mv2.w > 0.0) {
		vec2 fl = vec2(vnoise(x * 0.05 + vec2(u_time * 0.55, 0.0)), vnoise(x * 0.05 + vec2(9.7, u_time * 0.5))) - 0.5;
		d += fl * head_mv2.w * clamp(hv, 0.0, 1.0) * smoothstep(flutter_geo.x, flutter_geo.y, x.y);
	}
	d.x += mb.r * (cloth.x + cloth.y * sin(x.y * cloth.w - cloth.z + x.x * 0.006));
	return d;
}

// eyelid slide + iris gaze. Returns the sample position; lid / lidc describe the lid-colour fill.
vec2 eye_rig(vec2 q, int i, float closed, vec2 gaze, out float lid, out vec3 lidc) {
	lid = 0.0;
	lidc = vec3(0.0);
	vec4 g = eye_a[i];
	vec4 p = eye_b[i];
	vec4 ir = eye_c[i];
	float cs = cos(g.z);
	float sn = sin(g.z);
	vec2 dq = q - g.xy;
	vec2 l = vec2(cs * dq.x + sn * dq.y, -sn * dq.x + cs * dq.y);
	float t = l.x / g.w;
	float wu = 1.0 - smoothstep(0.95, 1.35, abs(t));
	if (wu <= 0.0) {
		return q;
	}
	float skew = p.w;
	float tt = t < skew ? (t - skew) / (1.0 + skew) : (t - skew) / (1.0 - skew);
	float par = max(0.0, 1.0 - tt * tt);
	float vt = p.x * par;
	float vl = p.y * par;
	float vt2 = vt + closed * (vl - vt - 0.35 * par);
	float dl = vt2 - vt;
	float v = l.y;
	float vb = vt2 + p.z;
	lid = wu * smoothstep(vt - 0.5, vt + 0.7, v) * (1.0 - smoothstep(vt2 - 0.2, vt2 + 0.6, v)) * smoothstep(0.0, 0.12, closed);
	float fz = smoothstep(vb - 0.8, vb + 0.8, v);
	float vs = v;
	if (v >= vt2 && v < vb + 0.8) {
		vs = mix(v - dl, v, fz);
	}
	vec2 lm = vec2(l.x, mix(v, vs, wu));
	float wi = 1.0 - smoothstep(ir.z * 0.8, ir.z * 1.3, length(lm - ir.xy));
	float gate = smoothstep(0.0, 2.2, lm.y - vt) * smoothstep(0.0, 2.2, vl - lm.y);
	lm -= gaze * wi * gate * wu * (1.0 - closed);
	lidc = mix(eye_top[i], eye_bot[i], smoothstep(vt - 0.5, max(vt2, vt + 0.6), v));
	return g.xy + vec2(cs * lm.x - sn * lm.y, sn * lm.x + cs * lm.y);
}

// Catmull-Rom through nine bilinear taps (or one mip-level tap when minified / on the low tier).
// pos and size are in source pixels of the texture.
vec4 sample_hq(sampler2D tex, vec2 pos, vec2 size) {
	vec2 uv = pos / size;
	if (fx2.z > 0.01 || fx2.w < 0.5) {
		return textureLod(tex, uv, fx2.z);
	}
	vec2 c = floor(pos - 0.5) + 0.5;
	vec2 f = pos - c;
	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);
	vec2 w12 = w1 + w2;
	vec2 off = w2 / w12;
	vec2 p0 = (c - 1.0) / size;
	vec2 p3 = (c + 2.0) / size;
	vec2 p12 = (c + off) / size;
	vec4 r = textureLod(tex, vec2(p0.x, p0.y), 0.0) * w0.x * w0.y
		+ textureLod(tex, vec2(p12.x, p0.y), 0.0) * w12.x * w0.y
		+ textureLod(tex, vec2(p3.x, p0.y), 0.0) * w3.x * w0.y
		+ textureLod(tex, vec2(p0.x, p12.y), 0.0) * w0.x * w12.y
		+ textureLod(tex, p12, 0.0) * w12.x * w12.y
		+ textureLod(tex, vec2(p3.x, p12.y), 0.0) * w3.x * w12.y
		+ textureLod(tex, vec2(p0.x, p3.y), 0.0) * w0.x * w3.y
		+ textureLod(tex, vec2(p12.x, p3.y), 0.0) * w12.x * w3.y
		+ textureLod(tex, p3, 0.0) * w3.x * w3.y;
	return max(r, vec4(0.0));
}

vec4 hero_at(vec2 s) {
	return sample_hq(hero_tex, s, tex_size);
}

// The lantern layer: premultiplied, scaled by its seam cross-fade weight
vec4 lantern_at(vec2 s) {
	return sample_hq(lantern_tex, s - lantern_rect.xy, lantern_rect.zw) * smoothstep(lantern_seam.x, lantern_seam.y, s.y);
}

// coverage of the figure at one position, base layer at qq, lantern layer at qqp (rim light)
float cover_at(vec2 qq, vec2 qqp, bool boxed) {
	float a = textureLod(hero_tex, qq / tex_size, 0.0).a;
	if (boxed) {
		float al = textureLod(lantern_tex, (qqp - lantern_rect.xy) / lantern_rect.zw, 0.0).a * smoothstep(lantern_seam.x, lantern_seam.y, qqp.y);
		a = al + a * (1.0 - al);
	}
	return a;
}

void fragment() {
	float quality = fx2.w;
	vec2 src = mix(src_rect.xy, src_rect.zw, UV);
	vec2 q = src;
	vec4 ma = vec4(0.0);
	vec4 mb = vec4(0.0);
	int steps = quality > 1.5 ? 4 : (quality > 0.5 ? 3 : 2);
	for (int i = 0; i < 4; i++) {
		if (i >= steps) {
			break;
		}
		q = src - disp(q, ma, mb);
	}
	vec2 qb = q;   // body frame: hair, cloth, breath and sway applied, not the face rig
	// yaw / pitch parallax of the features
	vec2 fr = (q - face_geo.xy) / face_geo.zw;
	float prof = max(0.0, 1.0 - dot(fr, fr));
	q -= ma.a * prof * vec2(head_mv.w, head_mv2.x);
	vec2 gaze = head_mv2.yz;
	float lid0;
	float lid1;
	vec3 lidc0;
	vec3 lidc1;
	q = eye_rig(q, 0, blink.x, gaze, lid0, lidc0);
	q = eye_rig(q, 1, blink.y, gaze, lid1, lidc1);

	vec4 t = hero_at(q);
	// the hanging weapon: rigid rotation about the grip (exact inverse, no iteration), drawn over the figure
	vec2 qp = qb;
	float lw = 0.0;
	bool boxed = false;
	if (lantern_rect.z > 0.0) {
		vec2 lo = lantern_rect.xy - vec2(48.0);
		vec2 hi = lantern_rect.xy + lantern_rect.zw + vec2(48.0);
		boxed = qb.x > lo.x && qb.y > lo.y && qb.x < hi.x && qb.y < hi.y;
	}
	if (boxed) {
		vec2 pr = qb - pend.xy;
		float pc = cos(pend.z);
		float ps = sin(pend.z);
		qp = pend.xy + vec2(pc * pr.x + ps * pr.y, -ps * pr.x + pc * pr.y);
		vec4 tl = lantern_at(qp);
		t = tl + t * (1.0 - tl.a);
		lw = tl.a;
		mb = mix(mb, textureLod(mask_b, qp / tex_size, 0.0), lw);
	}
	float a = t.a;
	vec3 col = a > 0.002 ? clamp(t.rgb / a, 0.0, 1.0) : vec3(0.0);
	col = mix(col, lidc0, lid0);
	col = mix(col, lidc1, lid1);
	vec3 graded = pow(max(col, vec3(0.0)), vec3(grade.y));
	float luma = dot(graded, vec3(0.2126, 0.7152, 0.0722));
	graded = mix(vec3(luma), graded, grade.z);
	vec3 lit = graded * grade.x;

	float beat = fx.x;
	// emissive crystals breathe with the shared heartbeat
	lit += emis_color.rgb * mb.b * (0.30 + 1.25 * beat) * fx.w;
	float glow = 0.0;
	if (quality > 0.5) {
		// soft halo of the emissive mask (the mask is mipmapped): light that leaves the silhouette
		glow = textureLod(mask_b, (boxed ? qp : q) / tex_size, 3.5).b;
	}
	if (quality > 1.5) {
		float a1 = cover_at(q + rim_dir * rim_px, qp + rim_dir * rim_px, boxed);
		float a2 = cover_at(q + rim_dir * rim_px * 2.2, qp + rim_dir * rim_px * 2.2, boxed);
		float rim = clamp((a - a1) * 1.5 + (a - a2) * 0.6, 0.0, 1.0) * a;
		lit += rim_color.rgb * rim * fx.z * (0.7 + 0.6 * beat);
		float gl = exp(-pow((dot(boxed ? qp : q, glint_dir) - glint.x) / glint.y, 2.0)) * mb.a * glint.z;
		lit += glint_color.rgb * gl;
	}

	// entry: a light line wipes the figure in from the feet up
	float kk = tex_size.y / 1536.0;
	float ry = fx.y;
	float line_y = mix(tex_size.y + 60.0 * kk, -60.0 * kk, ry);
	float wb = (vnoise(vec2(q.x * 0.03, u_time * 1.2)) - 0.5) * 26.0 * kk;
	float vis = smoothstep(line_y + wb - 12.0 * kk, line_y + wb + 12.0 * kk, src.y);
	float edge = exp(-pow((src.y - (line_y + wb)) / (15.0 * kk), 2.0)) * (1.0 - smoothstep(0.92, 1.0, ry));
	lit += edge_color.rgb * edge * 2.2 * step(0.01, a);

	float dbg = fx2.y;
	if (dbg > 0.5) {
		vec3 m = dbg < 1.5 ? vec3(ma.r, ma.g, ma.b) * 0.8 + vec3(ma.a, ma.a, 0.0) * 0.6 : (dbg < 2.5 ? vec3(mb.r, lw, mb.b) : vec3(mb.a));
		lit = mix(lit, m, 0.6);
	}
	float fa = a * vis * fx2.x;
	vec3 halo = emis_color.rgb * glow * glow_amount * (0.5 + 0.9 * beat) * vis * fx2.x;
	COLOR = vec4(lit * fa + halo, fa);
}
