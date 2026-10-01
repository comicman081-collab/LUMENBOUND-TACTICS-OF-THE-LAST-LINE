extends Control

## Title-screen "live 2D": the two cast illustrations are not swapped for a video or a
## skeleton; they are the unmodified standing art, warped per pixel by
## ui/shaders/title_puppet.gdshader. This node owns what a shader cannot: the schedules
## (breath, blink, gaze, head gestures), the mass-spring hair / cloth / weapon
## simulation, the shared heartbeat, the entrance choreography and the quality tiers.
## Presentation only: nothing here touches game state or the deterministic simulation.
##
## Hook: `TitleLive2D.attach(stage)` returns the node, or null when the assets or a real
## renderer are missing; the caller then keeps the static title art.
## QA: `manual = true` stops the automatic loop, `step(dt)` advances it and `debug_over`
## forces individual signals (see capture_title_live2d_qa.gd).

const PuppetShader := preload("res://ui/shaders/title_puppet.gdshader")
const HaloShader := preload("res://ui/shaders/title_halo.gdshader")
const Rig := preload("res://ui/title_live2d_rig.gd")

const BEAT_PERIOD := 2.6
const MAX_NODES := 5

class Puppet extends RefCounted:
	var id := ""
	var cfg: Dictionary = {}
	var rect: ColorRect
	var material: ShaderMaterial
	var tex_size := Vector2.ONE
	var unit := 1.0
	var follow := 1.0
	var scale_px := 0.75
	var rng := RandomNumberGenerator.new()
	var chains: Dictionary = {}
	var hair_r: Dictionary = {}
	var pendulum: Dictionary = {}
	var cloth_chain: Dictionary = {}
	var gesture := {"t0": -99.0, "dur": 2.2, "yaw": 0.0, "roll": 0.0, "gx": 0.0, "gy": 0.0, "next": 6.0}
	var blink := {"next": 2.2, "t": -1.0, "double": false, "active": false, "b": 0.0, "br": 0.0}
	var saccade := {"next": 1.2, "x": 0.0, "y": 0.0, "cx": 0.0, "cy": 0.0}
	var breath_phase := 0.0
	var breath_smooth := 0.0
	var prev_h := Vector2.ZERO
	var prev_hv := Vector2.ZERO
	var impulse_next := 3.0
	var glint_next := 4.5
	var glint_t0 := -99.0
	var sig: Dictionary = {}

var manual := false
var reduced := false
var quality := 2.0
var adapt_quality := true
var time := 0.0
var active_time := 0.0
var beat := 0.3
var pings := Vector3(-1.0, -1.0, -1.0)
var pointer := Vector2.ZERO
var pointer_target := Vector2.ZERO
var pointer_seen := false
var debug_over: Dictionary = {}
var debug_masks := 0
var puppets: Array[Puppet] = []
var rig: Control
var halo: ColorRect
var halo_center := Vector2.ZERO
var halo_unit := 900.0
var rig_scale_ref := 1.0

var _seed := 0
var _dts := PackedFloat32Array()
var _quality_lock := 0.0
var _quality_ok := 0


static func available() -> bool:
	var mode := OS.get_environment("LUMEN_TITLE_LIVE2D")
	if mode == "0":
		return false
	if DisplayServer.get_name() == "headless" and mode != "1":
		return false
	for id in Rig.ORDER:
		var cfg: Dictionary = Rig.HEROES[id]
		for key in ["hero", "mask_a", "mask_b"]:
			if not ResourceLoader.exists(Rig.ASSET_DIR + String(cfg[key])):
				return false
		var lantern: Dictionary = cfg.lantern
		if not lantern.is_empty():
			# the hero image has no weapon without its layer: unusable if the layer is missing or out of date
			var layer: Texture2D = load(Rig.ASSET_DIR + String(lantern.file)) as Texture2D
			var rect: Vector4 = lantern.rect
			if layer == null or Vector2(layer.get_size()) != Vector2(rect.z, rect.w):
				push_warning("TitleLive2D: lantern layer missing or not matching the rig, keeping the static title art")
				return false
	return true


static func attach(parent: Node) -> Control:
	if not available():
		return null
	var node: Control = load("res://ui/title_live2d.gd").new()
	node.name = "TitleLive2D"
	parent.add_child(node)
	return node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	reduced = _prefers_reduced_motion()
	var seed_text := OS.get_environment("LUMEN_TITLE_SEED")
	_seed = int(seed_text) if seed_text.is_valid_int() else int(Time.get_ticks_usec() & 0x7fffffff)
	var quality_text := OS.get_environment("LUMEN_TITLE_QUALITY")
	if quality_text.is_valid_int():
		quality = clampf(float(quality_text), 0.0, 2.0)
		adapt_quality = false
	rig = Control.new()
	rig.name = "TitleLive2DRig"
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rig)
	halo = ColorRect.new()
	halo.name = "LanternHalo"
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.color = Color.WHITE
	var halo_material := ShaderMaterial.new()
	halo_material.shader = HaloShader
	halo.material = halo_material
	rig.add_child(halo)
	for id in Rig.ORDER:
		_build_puppet(id)
	resized.connect(_layout)
	_layout()
	_push_all()


func _prefers_reduced_motion() -> bool:
	if OS.get_environment("LUMEN_TITLE_REDUCED") == "1":
		return true
	if OS.has_feature("web"):
		var value = JavaScriptBridge.eval("(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) ? 1 : 0", true)
		return int(value) == 1
	return false


func _build_puppet(id: String) -> void:
	var cfg: Dictionary = Rig.HEROES[id]
	var p := Puppet.new()
	p.id = id
	p.cfg = cfg
	p.tex_size = cfg.size
	p.unit = p.tex_size.y / 1002.0
	p.follow = float(cfg.follow)
	p.rng.seed = _seed + hash(id)
	p.gesture.next = p.rng.randf_range(4.5, 8.0)
	p.blink.next = p.rng.randf_range(2.0, 3.6)
	p.breath_phase = p.rng.randf()
	p.glint_next = p.rng.randf_range(3.5, 6.0)
	for key in ["a", "b", "c"]:
		var spec: Dictionary = cfg.chains[key]
		p.chains[key] = _make_chain(spec.freq, spec.zeta, spec.wind, spec.inertia, float(spec.k0), float(spec.phase), float(spec.gain))
		p.hair_r[key] = PackedFloat32Array(spec.radii)
	if not (cfg.pendulum as Dictionary).is_empty():
		var pd: Dictionary = cfg.pendulum
		p.pendulum = {"phi": 0.0, "w": 0.0, "pivot": pd.pivot, "length": float(pd.length), "freq": float(pd.freq), "zeta": float(pd.zeta), "drive": float(pd.drive), "kick": float(pd.kick), "impulse": float(pd.impulse), "bias": float(pd.get("bias", 0.0)), "limit": float(pd.limit)}
	var cl: Dictionary = cfg.cloth
	if float(cl.amp) > 0.0:
		p.cloth_chain = _make_chain([1.1], [0.3], [float(cl.amp) * 0.46], [2.0], 0.3, 0.9, 1.0)
	var rect := ColorRect.new()
	rect.name = "Puppet_" + id
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = PuppetShader
	material.set_shader_parameter("hero_tex", load(Rig.ASSET_DIR + String(cfg.hero)))
	material.set_shader_parameter("mask_a", load(Rig.ASSET_DIR + String(cfg.mask_a)))
	material.set_shader_parameter("mask_b", load(Rig.ASSET_DIR + String(cfg.mask_b)))
	material.set_shader_parameter("tex_size", p.tex_size)
	material.set_shader_parameter("body_geo", cfg.body_geo)
	material.set_shader_parameter("neck_geo", cfg.neck_geo)
	material.set_shader_parameter("breath_geo", cfg.breath_geo)
	material.set_shader_parameter("exp_geo", cfg.exp_geo)
	material.set_shader_parameter("face_geo", cfg.face_geo)
	material.set_shader_parameter("flutter_geo", cfg.flutter_geo)
	material.set_shader_parameter("grade", cfg.grade)
	material.set_shader_parameter("rim_color", cfg.rim_color)
	material.set_shader_parameter("emis_color", cfg.emis_color)
	material.set_shader_parameter("edge_color", cfg.edge_color)
	material.set_shader_parameter("glint_color", cfg.glint_color)
	material.set_shader_parameter("rim_dir", cfg.rim_dir)
	var lantern: Dictionary = cfg.lantern
	if not lantern.is_empty():
		material.set_shader_parameter("lantern_tex", load(Rig.ASSET_DIR + String(lantern.file)))
		material.set_shader_parameter("lantern_rect", lantern.rect)
		material.set_shader_parameter("lantern_seam", lantern.seam)
	var eye_a := PackedVector4Array()
	var eye_b := PackedVector4Array()
	var eye_c := PackedVector4Array()
	var eye_top := PackedVector3Array()
	var eye_bot := PackedVector3Array()
	for eye in cfg.eyes:
		eye_a.append(Vector4(eye[0], eye[1], eye[2], eye[3]))
		eye_b.append(Vector4(eye[4], eye[5], eye[6], eye[10]))
		eye_c.append(Vector4(eye[7], eye[8], eye[9], 0.0))
		eye_top.append(Vector3(eye[11], eye[12], eye[13]))
		eye_bot.append(Vector3(eye[14], eye[15], eye[16]))
	material.set_shader_parameter("eye_a", eye_a)
	material.set_shader_parameter("eye_b", eye_b)
	material.set_shader_parameter("eye_c", eye_c)
	material.set_shader_parameter("eye_top", eye_top)
	material.set_shader_parameter("eye_bot", eye_bot)
	for key in ["a", "b", "c"]:
		var spec: Dictionary = cfg.chains[key]
		material.set_shader_parameter("h%s_root" % key, spec.root)
		material.set_shader_parameter("h%s_r" % key, p.hair_r[key])
	rect.material = material
	rig.add_child(rect)
	p.rect = rect
	p.material = material
	puppets.append(p)


func _layout() -> void:
	if rig == null:
		return
	rig.size = size
	rig.pivot_offset = Vector2(size.x * 0.64, size.y * 0.62)
	var screen_scale := 1.0
	if is_inside_tree():
		screen_scale = maxf(0.01, get_viewport().get_final_transform().get_scale().x)
	rig_scale_ref = size.y / 1080.0
	for p in puppets:
		var box_f: Rect2 = p.cfg.box
		var box := Rect2(box_f.position * size, box_f.size * size)
		var tex: Vector2 = p.tex_size
		var sc := minf(box.size.x / tex.x, box.size.y / tex.y)
		var origin := box.position + (box.size - tex * sc) * 0.5
		var pad: Vector4 = p.cfg.pad
		var sr := Vector4(-pad.x, -pad.y, tex.x + pad.z, tex.y + pad.w)
		p.rect.position = origin + Vector2(sr.x, sr.y) * sc
		p.rect.size = Vector2(sr.z - sr.x, sr.w - sr.y) * sc
		p.scale_px = sc
		p.material.set_shader_parameter("src_rect", sr)
		var shown := sc * screen_scale
		p.material.set_shader_parameter("rim_px", 3.8 / maxf(shown, 0.05))
		p.set_meta("minify", log(1.0 / shown) / log(2.0) if shown < 1.0 else 0.0)
		if p.id == "CHR001":
			halo_center = origin + Vector2(520.0, 470.0) * sc
			halo_unit = 1000.0 * sc * (tex.y / 1536.0) * 1.0
	halo.size = size
	halo.position = Vector2.ZERO
	halo.material.set_shader_parameter("rect_px", size)
	halo.material.set_shader_parameter("center_px", halo_center)
	halo.material.set_shader_parameter("unit_px", halo_unit)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		pointer_target = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and size.x > 1.0 and size.y > 1.0:
		var local := (event as InputEventMouseMotion).position
		var rect := get_global_rect()
		pointer_target = Vector2(clampf((local.x - rect.position.x) / rect.size.x - 0.5, -0.5, 0.5), clampf((local.y - rect.position.y) / rect.size.y - 0.5, -0.5, 0.5)) * 2.0
		pointer_seen = true


func _process(delta: float) -> void:
	if manual or not is_visible_in_tree():
		return
	var dt := clampf(delta, 0.0, 0.05)
	step(dt)
	if adapt_quality:
		_adapt(dt)


func step(dt: float) -> void:
	time += dt
	active_time += dt
	pointer += (pointer_target - pointer) * (1.0 - exp(-dt * 4.5))
	_update_beat()
	for p in puppets:
		_sim(p, dt)
	_push_all()
	_update_rig()


func seek(seconds: float) -> void:
	active_time = seconds


# ------------------------------------------------------------------ simulation

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _ease_in_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


static func _wob(t: float, a: float, b: float, c: float, ph: float) -> float:
	return sin(t * a + ph) * 0.5 + sin(t * b + ph * 1.7 + 1.3) * 0.3 + sin(t * c + ph * 2.9 + 2.1) * 0.2


static func _make_chain(freqs: Array, zeta: Array, wind_gain: Array, inertia: Array, k0_fraction: float, phase: float, gain: float) -> Dictionary:
	var n := mini(freqs.size(), MAX_NODES)
	var k := PackedFloat64Array()
	var c := PackedFloat64Array()
	var k0 := PackedFloat64Array()
	var c0 := PackedFloat64Array()
	var wind := PackedFloat64Array()
	var inert := PackedFloat64Array()
	for i in n:
		var stiffness := pow(TAU * float(freqs[i]), 2.0)
		k.append(stiffness)
		c.append(2.0 * float(zeta[i]) * TAU * float(freqs[i]))
		k0.append(stiffness * k0_fraction)
		c0.append(2.0 * float(zeta[i]) * TAU * float(freqs[i]) * 0.2)
		wind.append(float(wind_gain[i]))
		inert.append(float(inertia[i]))
	var x := PackedFloat64Array()
	x.resize(n * 2)
	var v := PackedFloat64Array()
	v.resize(n * 2)
	return {"n": n, "k": k, "c": c, "k0": k0, "c0": c0, "wind": wind, "inertia": inert, "x": x, "v": v, "phase": phase, "gain": gain}


static func _step_chain(ch: Dictionary, dt: float, wx: float, wy: float, ax: float, ay: float) -> void:
	var n: int = ch.n
	if n == 0:
		return
	var sub := maxi(1, ceili(dt / (1.0 / 240.0)))
	var h := dt / float(sub)
	var x: PackedFloat64Array = ch.x
	var v: PackedFloat64Array = ch.v
	var k: PackedFloat64Array = ch.k
	var c: PackedFloat64Array = ch.c
	var k0: PackedFloat64Array = ch.k0
	var c0: PackedFloat64Array = ch.c0
	var wind: PackedFloat64Array = ch.wind
	var inert: PackedFloat64Array = ch.inertia
	for _s in sub:
		for i in n:
			for a in 2:
				var ix := i * 2 + a
				var px := 0.0 if i == 0 else x[ix - 2]
				var pv := 0.0 if i == 0 else v[ix - 2]
				var force := wind[i] * (wx if a == 0 else wy) - inert[i] * (ax if a == 0 else ay)
				v[ix] += (-k[i] * (x[ix] - px) - c[i] * (v[ix] - pv) - k0[i] * x[ix] - c0[i] * v[ix] + force) * h
		for i in n * 2:
			x[i] += v[i] * h
	ch.x = x
	ch.v = v


static func _chain_uniform(ch: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(MAX_NODES + 1)
	var n: int = ch.n
	var x: PackedFloat64Array = ch.x
	for i in n:
		out[i + 1] = Vector2(x[i * 2], x[i * 2 + 1])
	for i in range(n + 1, MAX_NODES + 1):
		out[i] = out[n]
	return out


func _update_beat() -> void:
	var phase := fposmod(time, BEAT_PERIOD)
	var x := phase / BEAT_PERIOD
	var bump := clampf(exp(-pow((x - 0.06) / 0.022, 2.0)) + 0.6 * exp(-pow((x - 0.15) / 0.028, 2.0)), 0.0, 1.0)
	beat = lerpf(0.12, 1.0, bump)
	var age := phase - 0.06 * BEAT_PERIOD
	pings = Vector3(age if age <= 2.6 else -1.0, age + BEAT_PERIOD if age + BEAT_PERIOD <= 2.6 else -1.0, -1.0)


func _sim(p: Puppet, dt: float) -> void:
	var t := time
	var tl := active_time
	var u := p.unit
	var amp := 0.25 if reduced else 1.0
	var ramp := 0.25 if reduced else _smooth(0.6, 2.4, tl)
	var px := pointer.x * p.follow
	var py := pointer.y * p.follow
	var rng := p.rng
	var safe_dt := maxf(dt, 1e-4)
	# breathing: shorter inhale, longer exhale
	p.breath_phase += dt / (4.4 * (1.0 + 0.07 * sin(t * 0.21)))
	var bp := fposmod(p.breath_phase, 1.0)
	var breath := (0.5 - 0.5 * cos(PI * bp / 0.4)) if bp < 0.4 else (0.5 + 0.5 * cos(PI * (bp - 0.4) / 0.6))
	p.breath_smooth += (breath - p.breath_smooth) * (1.0 - exp(-dt / 0.35))
	# look gestures every few seconds: a little turn, roll and glance, usually with a blink
	var g: Dictionary = p.gesture
	var gesture_started := false
	if tl > 1.8 and t >= float(g.next):
		g.t0 = t
		g.dur = rng.randf_range(1.8, 2.8)
		g.yaw = rng.randf_range(-1.0, 1.0) * 1.9
		g.roll = rng.randf_range(-1.0, 1.0) * 0.011
		g.gx = rng.randf_range(-1.0, 1.0) * 1.5
		g.gy = rng.randf_range(-0.5, 0.5)
		g.next = t + rng.randf_range(7.0, 13.0)
		gesture_started = true
		if rng.randf() < 0.7:
			p.blink.next = minf(float(p.blink.next), t + rng.randf_range(0.2, 0.5))
	var gp := clampf((t - float(g.t0)) / float(g.dur), 0.0, 1.0)
	var gs := pow(sin(PI * gp), 2.0) if (gp > 0.0 and gp < 1.0) else 0.0
	# micro saccades keep the eyes alive
	var sc: Dictionary = p.saccade
	if t >= float(sc.next):
		sc.x = rng.randf_range(-0.55, 0.55)
		sc.y = rng.randf_range(-0.3, 0.3)
		sc.next = t + rng.randf_range(0.9, 3.2)
	sc.cx += (float(sc.x) - float(sc.cx)) * (1.0 - exp(-dt / 0.045))
	sc.cy += (float(sc.y) - float(sc.cy)) * (1.0 - exp(-dt / 0.045))
	# blink: quick close, tiny hold, slower open; the second eye lags a hair; now and then a double
	var bl: Dictionary = p.blink
	if not bool(bl.active) and t >= float(bl.next) and tl > 1.2:
		bl.active = true
		bl.t = 0.0
		bl["double"] = rng.randf() < 0.18
	if bool(bl.active):
		bl.t += dt
		bl.b = _blink_profile(float(bl.t))
		bl.br = _blink_profile(float(bl.t) - 0.012)
		if float(bl.t) > 0.07 + 0.035 + 0.13 + 0.02:
			bl.b = 0.0
			bl.br = 0.0
			if bool(bl["double"]):
				bl["double"] = false
				bl.t = -0.09
			else:
				bl.active = false
				bl.next = t + rng.randf_range(2.4, 5.8)
	else:
		bl.b = 0.0
		bl.br = 0.0
	# head / body
	var psi1 := ramp * 0.0046 * amp * (sin(TAU * t / 8.6 + 0.4) * 0.75 + sin(TAU * t / 5.3 + 1.7) * 0.25)
	var psi2 := -0.5 * psi1 + ramp * 0.0012 * amp * sin(TAU * t / 6.7 + 2.0)
	var head_dx := (ramp * amp * 1.7 * _wob(t, 0.73, 1.21, 2.3, 0.6) + px * 3.2 * amp) * u
	var head_dy := (ramp * amp * 0.9 * _wob(t, 0.61, 1.1, 1.9, 1.4) + (breath - p.breath_smooth) * 1.6 + py * 1.6 * amp) * u
	var roll := ramp * amp * 0.0075 * _wob(t, 0.62, 0.97, 1.7, 0.2) + gs * float(g.roll) * ramp + px * 0.012 * amp
	var yaw := (ramp * amp * 0.9 * _wob(t, 0.5, 0.87, 1.4, 2.3) + gs * float(g.yaw) * ramp + px * 2.4 * amp) * u
	var pitch := (py * 1.6 * amp + gs * float(g.gy) * 0.8 * ramp) * u
	var gaze_x := clampf(px * 1.15 + gs * float(g.gx) + float(sc.cx), -1.9, 1.9) * ramp * u
	var gaze_y := clampf(py * 0.7 + gs * float(g.gy) * 0.6 + float(sc.cy), -1.0, 1.0) * ramp * u
	var blink_l := float(bl.b)
	var blink_r := float(bl.br)
	var sig := {"breath": breath, "psi1": psi1, "psi2": psi2, "head_dx": head_dx, "head_dy": head_dy, "roll": roll, "yaw": yaw, "pitch": pitch, "gaze_x": gaze_x, "gaze_y": gaze_y, "blink_l": blink_l, "blink_r": blink_r}
	if not debug_over.is_empty():
		for key in debug_over:
			if key == "blink":
				sig.blink_l = float(debug_over[key])
				sig.blink_r = float(debug_over[key])
			elif key == "no_idle":
				if bool(debug_over[key]):
					for zero_key in ["psi1", "psi2", "head_dx", "head_dy", "roll", "yaw", "pitch", "gaze_x", "gaze_y"]:
						sig[zero_key] = 0.0
			elif sig.has(key):
				sig[key] = float(debug_over[key])
	p.sig = sig
	# hair: inertial pseudo force from the head frame + wind
	var arm := float(p.cfg.body_geo.y) - float(p.cfg.neck_geo.y)
	var hx: float = float(sig.head_dx) + float(sig.psi1) * arm
	var hy: float = float(sig.head_dy)
	var hv := Vector2((hx - p.prev_h.x) / safe_dt, (hy - p.prev_h.y) / safe_dt)
	var limit := 900.0 * u
	var ha := Vector2(clampf((hv.x - p.prev_hv.x) / safe_dt, -limit, limit), clampf((hv.y - p.prev_hv.y) / safe_dt, -limit, limit))
	p.prev_h = Vector2(hx, hy)
	p.prev_hv = hv
	var env := 0.6 + 0.4 * sin(t * 0.37 + 0.9)
	var first := 0.0 if tl < 0.05 else 1.0
	for key in ["a", "b", "c"]:
		var ch: Dictionary = p.chains[key]
		var ph: float = ch.phase
		var gain: float = ch.gain
		var wx := (230.0 * env * _wob(t, 1.9, 3.1, 4.7, ph) - 42.0) * gain * ramp * amp * u
		var wy := 60.0 * env * _wob(t, 1.3, 2.3, 3.7, ph + 1.1) * gain * ramp * amp * u
		_step_chain(ch, dt, wx, wy, ha.x * first, ha.y * first)
	if not p.cloth_chain.is_empty():
		var wc := (230.0 * env * _wob(t, 1.5, 2.6, 4.1, 0.9) - 20.0) * ramp * amp * u
		_step_chain(p.cloth_chain, dt, wc, 0.0, ha.x * first, 0.0)
	if not p.pendulum.is_empty():
		var pd: Dictionary = p.pendulum
		var w0 := TAU * float(pd.freq)
		if gesture_started:
			pd.w += float(pd.kick) * rng.randf_range(-1.0, 1.0) * ramp * amp
		if t >= float(p.impulse_next) and tl > 1.0:
			pd.w += float(pd.impulse) * rng.randf_range(-1.0, 1.0) * ramp * amp
			p.impulse_next = t + rng.randf_range(2.4, 5.6)
		var target := float(pd.bias) * ramp + float(pd.drive) * _wob(t, 0.8, 1.35, 2.2, 0.7) * ramp * amp + ha.x * 0.8 / (float(pd.length) * w0 * w0)
		var sub := maxi(1, ceili(dt / (1.0 / 240.0)))
		var h := dt / float(sub)
		for _i in sub:
			var acc := -w0 * w0 * (float(pd.phi) - target) - 2.0 * float(pd.zeta) * w0 * float(pd.w)
			pd.w += acc * h
			pd.phi += float(pd.w) * h
		if debug_over.has("pendulum"):
			pd.phi = float(debug_over.pendulum)
	# light glint sweeping over the gold / silver trim every few seconds
	if tl > 2.4 and t >= p.glint_next:
		p.glint_t0 = t
		p.glint_next = t + rng.randf_range(6.0, 10.0)


static func _blink_profile(u: float) -> float:
	var close := 0.07
	var hold := 0.035
	var open := 0.13
	if u < 0.0:
		return 0.0
	if u < close:
		return pow(u / close, 1.6)
	if u < close + hold:
		return 1.0
	if u < close + hold + open:
		return 1.0 - _ease_out((u - close - hold) / open)
	return 0.0


# ------------------------------------------------------------------ presentation

func _push_all() -> void:
	var tl := active_time
	for p in puppets:
		var m := p.material
		var sig: Dictionary = p.sig
		if sig.is_empty():
			sig = {"breath": 0.0, "psi1": 0.0, "psi2": 0.0, "head_dx": 0.0, "head_dy": 0.0, "roll": 0.0, "yaw": 0.0, "pitch": 0.0, "gaze_x": 0.0, "gaze_y": 0.0, "blink_l": 0.0, "blink_r": 0.0}
		m.set_shader_parameter("u_time", time)
		m.set_shader_parameter("body_rot", Vector4(sig.psi1, sig.psi2, sig.breath, 0.0))
		m.set_shader_parameter("head_mv", Vector4(sig.head_dx, sig.head_dy, sig.roll, sig.yaw))
		m.set_shader_parameter("head_mv2", Vector4(sig.pitch, sig.gaze_x, sig.gaze_y, 0.2 * p.unit if reduced else 1.1 * p.unit))
		m.set_shader_parameter("blink", Vector2(sig.blink_l, sig.blink_r))
		for key in ["a", "b", "c"]:
			var nodes := _chain_uniform(p.chains[key])
			if debug_over.has("hair"):
				# QA: push every hair node along a ramp, as a stress test of the masks
				for node_index in range(1, nodes.size()):
					nodes[node_index] += (debug_over.hair as Vector2) * p.unit * float(node_index) / float(MAX_NODES)
			m.set_shader_parameter("h%s_u" % key, nodes)
		if not p.pendulum.is_empty():
			var pd: Dictionary = p.pendulum
			var limit := float(pd.limit)
			var phi := float(pd.phi) if debug_over.has("pendulum") else limit * tanh(float(pd.phi) / limit)
			m.set_shader_parameter("pend", Vector4(pd.pivot.x, pd.pivot.y, phi, 0.0))
		var cl: Dictionary = p.cfg.cloth
		if float(cl.amp) > 0.0:
			var drift := 0.0
			if not p.cloth_chain.is_empty():
				drift = (p.cloth_chain.x as PackedFloat64Array)[0]
			var wave := float(cl.wave) * p.unit * (0.6 + 0.4 * sin(time * 0.5)) * (0.25 if reduced else 1.0)
			m.set_shader_parameter("cloth", Vector4(drift, wave, time * 1.8, float(cl.freq)))
		var reveal := _ease_in_out((tl - float(p.cfg.reveal_delay)) / 1.4)
		m.set_shader_parameter("fx", Vector4(beat, reveal, 0.55, 1.0))
		var minify := float(p.get_meta("minify", 0.0))
		m.set_shader_parameter("fx2", Vector4(1.0, float(debug_masks), minify, quality))
		var gl_age := time - p.glint_t0
		var glint_pos := lerpf(-260.0 * p.unit, (p.tex_size.x * 0.8 + p.tex_size.y * 0.6) + 260.0 * p.unit, clampf(gl_age / 1.5, 0.0, 1.0))
		var glint_amt := 0.0 if (gl_age < 0.0 or gl_age > 1.5) else 0.85 * sin(PI * clampf(gl_age / 1.5, 0.0, 1.0))
		m.set_shader_parameter("glint", Vector4(glint_pos, 90.0 * p.unit, glint_amt, 0.0))
	var hm := halo.material as ShaderMaterial
	hm.set_shader_parameter("u_time", time)
	hm.set_shader_parameter("beat", beat)
	hm.set_shader_parameter("ping", pings)
	hm.set_shader_parameter("amount", _smooth(0.4, 1.6, tl) * (0.6 if reduced else 1.0))


func _update_rig() -> void:
	var tl := active_time
	var push := 1.0 + 0.06 * (1.0 - _ease_out(tl / 4.2))
	rig.scale = Vector2(push, push)
	var parallax := Vector2.ZERO if reduced else Vector2(-pointer.x * 10.0, -pointer.y * 5.0) * rig_scale_ref
	var slide := (1.0 - _ease_out((tl - 0.5) / 1.6)) * 36.0 * rig_scale_ref
	rig.position = parallax + Vector2(slide, 0.0)


func _adapt(dt: float) -> void:
	_dts.append(dt)
	if _dts.size() < 90:
		return
	var sorted := _dts.duplicate()
	sorted.sort()
	var p75: float = sorted[int(sorted.size() * 0.75)]
	_dts.clear()
	if p75 > 0.026 and quality > 0.0 and time > _quality_lock:
		quality -= 1.0
		_quality_lock = time + 8.0
		_quality_ok = 0
	elif p75 < 0.0185:
		_quality_ok += 1
		if _quality_ok >= 3 and quality < 2.0 and time > _quality_lock:
			quality += 1.0
			_quality_ok = 0
			_quality_lock = time + 8.0
	else:
		_quality_ok = 0
