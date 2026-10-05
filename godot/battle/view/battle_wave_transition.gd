extends RefCounted

## Presentation clock only. Reference: the supplied 69-second encounter video,
## 10-28s: wide field, enemy close-up/dialogue, squad response, encounter band,
## then a continuous pull-back before combat. Never changes simulation time.
const WAVE_DURATION := 5.4
const BOSS_DURATION := 6.5

static func duration(boss: bool) -> float:
	return BOSS_DURATION if boss else WAVE_DURATION

static func sample(elapsed: float, boss: bool) -> Dictionary:
	var end := duration(boss)
	var reply := 3.45 if boss else 2.85
	var return_start := 4.85 if boss else 3.95
	var enemy_in := smoothstep(1.25, 1.85, elapsed)
	var ally_in := smoothstep(reply - .50, reply + .15, elapsed)
	var pull_back := smoothstep(return_start, end - .05, elapsed)
	var focus := (1.0 - 2.0 * ally_in) * (1.0 - pull_back) * enemy_in
	var visibility := smoothstep(.12, .45, elapsed) * (1.0 - smoothstep(end - .60, end, elapsed))
	var mask := smoothstep(.50, .85, elapsed) * (1.0 - smoothstep(1.0, 1.30, elapsed))
	var phase := "clear"
	if elapsed >= .50: phase = "aperture"
	if elapsed >= 1.30: phase = "enemy"
	if elapsed >= reply: phase = "squad"
	if elapsed >= return_start: phase = "return"
	return {"phase": phase, "focus": focus, "zoom": 1.0 + (0.40 if boss else .30) * enemy_in * (1.0 - pull_back),
		"ally_mix": ally_in, "camera_strength": enemy_in * (1.0 - pull_back),
		"visibility": visibility, "mask": mask,
		"enemy_caption": smoothstep(1.85, 2.03, elapsed) * (1.0 - smoothstep(reply - .22, reply, elapsed)),
		"ally_caption": smoothstep(reply + .10, reply + .27, elapsed) * (1.0 - smoothstep(return_start - .18, return_start, elapsed)),
		"banner": smoothstep(return_start, return_start + .18, elapsed) * (1.0 - smoothstep(end - .50, end - .15, elapsed)),
		"duration": end}

static func camera(elapsed: float, boss: bool, viewport: Vector2, enemy: Vector2, ally: Vector2) -> Dictionary:
	var beat := sample(elapsed, boss)
	var anchor := enemy.lerp(ally, float(beat.ally_mix))
	var zoom := float(beat.zoom)
	var center := viewport * .5
	var target := viewport * Vector2(.53, .53)
	# Focus anchors already contain a half-height body offset. Bodies and floor
	# share this one transform; no portrait sticker replaces an SD combat actor.
	var offset := (target - (center + (anchor - center) * zoom)) * float(beat.camera_strength)
	# The authored environment is one full-screen plate. Respect its camera
	# coverage so an enemy close-up never exposes empty strips at the edges.
	var limit := center * (zoom - 1.0)
	offset = Vector2(clampf(offset.x, -limit.x, limit.x), clampf(offset.y, -limit.y, limit.y))
	return {"zoom": zoom, "offset": offset}
