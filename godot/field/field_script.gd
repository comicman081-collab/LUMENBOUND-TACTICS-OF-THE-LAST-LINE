extends RefCounted

## Field direction script format, library and converters (2026-09-30, phase 3).
##
## A field scene is an ordered list of command dictionaries. Every command has a
## `cmd`; a command with `"with": true` starts together with the one before it,
## otherwise it starts when the previous group has finished.
##
##   say     actor, text | text_key, [speaker | speaker_key], [portrait], [side], [hold]
##           A speech bubble with a typing effect. Waits for a tap, or `hold` seconds
##           once the line has been typed. `side`: ally (teal), foe (red), event (gold).
##   move    actor, (dx, dy | to: front/back/home), [time]      offsets in move units
##   face    actor, toward: another actor | left | right
##   jump    actor, [height 0.1..1.5], [time]
##   emote   actor, kind: alert | question | sweat | anger | spark, [time], [wait]
##   camera  [focus], [zoom 1..2], [shake px], [time]
##   banner  text | text_key, [style boss | event | info], [time], [tap]
##   sfx     id
##   wait    sec
##
## Actors are roles (`leader`, `ally`, `foe`, `boss`, `event`) or concrete ids; the
## host screen resolves them (`FieldStage`). Scripts only carry presentation:
## nothing here touches simulation, rewards, saves or map state.

const LIBRARY_PATH := "res://data/field_scenes/field_scenes.json"
const COMMANDS := ["say", "move", "face", "jump", "emote", "camera", "banner", "sfx", "wait"]
const ACTOR_COMMANDS := ["say", "move", "face", "jump", "emote"]
const EMOTES := ["alert", "question", "sweat", "anger", "spark"]
const SIDES := ["ally", "foe", "event"]
const BANNER_STYLES := ["boss", "event", "info"]
const MAX_STEPS := 64
# Combat sound assets (the game ships no UI sounds): a light metal hit for an alert,
# a heavy slam when a boss steps in.
const EVENT_CONTACT_SFX := "audio_sfx_impact_metal_hit_05"
const BOSS_CONTACT_SFX := "audio_sfx_impact_metal_slam_01"

static var _library: Dictionary = {}
static var _library_loaded := false


## Problems that would make a script misbehave; an empty array means playable.
static func validate(steps: Array) -> Array[String]:
	var errors: Array[String] = []
	if steps.is_empty():
		errors.append("scene has no steps")
	if steps.size() > MAX_STEPS:
		errors.append("scene has %d steps (max %d)" % [steps.size(), MAX_STEPS])
	for index in range(steps.size()):
		var step: Variant = steps[index]
		var label := "step %d" % index
		if not step is Dictionary:
			errors.append("%s is not a dictionary" % label)
			continue
		var data: Dictionary = step
		var cmd := str(data.get("cmd", ""))
		if not COMMANDS.has(cmd):
			errors.append("%s has unknown cmd '%s'" % [label, cmd])
			continue
		if index == 0 and bool(data.get("with", false)):
			errors.append("%s cannot start 'with' a previous step" % label)
		if ACTOR_COMMANDS.has(cmd) and str(data.get("actor", "")).is_empty():
			errors.append("%s (%s) needs an actor" % [label, cmd])
		match cmd:
			"say":
				if str(data.get("text_key", "")).is_empty() and _is_blank(data.get("text", "")):
					errors.append("%s (say) needs text or text_key" % label)
				if data.has("side") and not SIDES.has(str(data.side)):
					errors.append("%s has unknown side '%s'" % [label, str(data.side)])
			"move":
				if not data.has("to") and not data.has("dx") and not data.has("dy"):
					errors.append("%s (move) needs to, dx or dy" % label)
				if data.has("to") and not ["front", "back", "home"].has(str(data.to)):
					errors.append("%s (move) has unknown to '%s'" % [label, str(data.to)])
			"face":
				if str(data.get("toward", "")).is_empty():
					errors.append("%s (face) needs toward" % label)
			"emote":
				if not EMOTES.has(str(data.get("kind", ""))):
					errors.append("%s (emote) has unknown kind '%s'" % [label, str(data.get("kind", ""))])
			"banner":
				if str(data.get("text_key", "")).is_empty() and _is_blank(data.get("text", "")):
					errors.append("%s (banner) needs text or text_key" % label)
				if data.has("style") and not BANNER_STYLES.has(str(data.style)):
					errors.append("%s has unknown banner style '%s'" % [label, str(data.style)])
			"sfx":
				if str(data.get("id", "")).is_empty():
					errors.append("%s (sfx) needs an id" % label)
		for key in ["time", "sec", "height", "zoom", "shake", "hold"]:
			if data.has(key) and (not (data[key] is float or data[key] is int) or float(data[key]) < 0.0):
				errors.append("%s has a bad %s" % [label, key])
	return errors


static func _is_blank(value: Variant) -> bool:
	if value is Dictionary:
		return (value as Dictionary).is_empty()
	return str(value).strip_edges().is_empty()


## A text value is a plain string or a {ko, en} dictionary.
static func text_of(value: Variant, language := "") -> String:
	if value is Dictionary:
		var table: Dictionary = value
		var lang := language if not language.is_empty() else _language()
		if table.has(lang):
			return str(table[lang])
		return str(table.get("ko", table.get("en", "")))
	return str(value)


static func line_of(step: Dictionary, language := "") -> String:
	var key := str(step.get("text_key", ""))
	if not key.is_empty():
		return LocalizationService.tr_key(key)
	return text_of(step.get("text", ""), language)


static func speaker_of(step: Dictionary, language := "") -> String:
	var key := str(step.get("speaker_key", ""))
	if not key.is_empty():
		return LocalizationService.tr_key(key)
	return text_of(step.get("speaker", ""), language)


static func _language() -> String:
	return str(SettingsService.values.get("language", "ko"))


## Seconds a line stays up after it has been typed when the script sets no `hold`.
static func reading_seconds(text: String) -> float:
	return clampf(0.5 + float(text.length()) * 0.05, 1.0, 6.5)


# -- library ---------------------------------------------------------------

static func library(force_reload := false) -> Dictionary:
	if _library_loaded and not force_reload:
		return _library
	_library = {"scenes": {}, "bindings": {}}
	_library_loaded = true
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if file == null:
		return _library
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var data: Dictionary = parsed
		_library = {"scenes": data.get("scenes", {}), "bindings": data.get("bindings", {})}
	return _library


static func scene_ids() -> Array:
	var ids: Array = library().scenes.keys()
	ids.sort()
	return ids


static func steps_of(scene_id: String) -> Array:
	var entry: Variant = library().scenes.get(scene_id, {})
	if entry is Dictionary:
		var steps: Variant = (entry as Dictionary).get("steps", [])
		if steps is Array:
			return (steps as Array).duplicate(true)
	return []


## The scene id bound to `stage_id` for a moment such as "boss_aftermath", or ""
## when the stage has no authored scene of its own; `default` is the fallback.
static func scene_id_for(binding: String, stage_id: String) -> String:
	var table: Variant = library().bindings.get(binding, {})
	if not table is Dictionary:
		return ""
	var bound := str((table as Dictionary).get(stage_id, (table as Dictionary).get("default", "")))
	return bound if library().scenes.has(bound) else ""


## Steps for a bound moment, with `{boss}`-style placeholders filled from `tokens`.
static func steps_for(binding: String, stage_id: String, tokens := {}) -> Array:
	var scene_id := scene_id_for(binding, stage_id)
	if scene_id.is_empty():
		return []
	return fill_tokens(steps_of(scene_id), tokens)


static func fill_tokens(steps: Array, tokens: Dictionary) -> Array:
	if tokens.is_empty():
		return steps
	var result: Array = []
	for step_value in steps:
		var step: Dictionary = (step_value as Dictionary).duplicate(true)
		for key in ["text", "speaker"]:
			if step.has(key):
				step[key] = _fill_value(step[key], tokens)
		result.append(step)
	return result


static func _fill_value(value: Variant, tokens: Dictionary) -> Variant:
	if value is Dictionary:
		var filled := {}
		for lang in (value as Dictionary).keys():
			filled[lang] = _fill_string(str(value[lang]), tokens)
		return filled
	return _fill_string(str(value), tokens)


static func _fill_string(text: String, tokens: Dictionary) -> String:
	var result := text
	for token in tokens.keys():
		result = result.replace("{%s}" % str(token), str(tokens[token]))
	return result


# -- converters ------------------------------------------------------------

## Turn authored `pre_battle_dialogue` pages (speaker, text_key, portrait) into a
## contact scene: the camera closes in, both sides notice each other, then every
## page is one bubble on its side of the meeting.
##
## options: kind ("EVENT" | "BOSS"), foe_ids (speakers who are the encounter's
## enemy), event_ids (recruit candidates, shown in gold), title_key (an opening
## banner), outcome_key (a banner after the last line), speaker_name (Callable that
## returns the display name for a page).
static func from_dialogue_pages(pages: Array, options := {}) -> Array:
	var foe_ids: Array = options.get("foe_ids", [])
	var event_ids: Array = options.get("event_ids", [])
	var boss := str(options.get("kind", "EVENT")) == "BOSS"
	var resolver: Callable = options.get("speaker_name", Callable())
	var steps: Array = []
	steps.append({"cmd": "camera", "focus": "foe", "zoom": 1.45 if boss else 1.35, "time": 0.55})
	steps.append({"cmd": "face", "actor": "leader", "toward": "foe", "with": true})
	steps.append({"cmd": "face", "actor": "foe", "toward": "leader", "with": true})
	steps.append({"cmd": "emote", "actor": "foe", "kind": "alert", "with": true})
	steps.append({"cmd": "jump", "actor": "leader", "height": 0.45, "time": 0.36, "with": true})
	steps.append({"cmd": "sfx", "id": BOSS_CONTACT_SFX if boss else EVENT_CONTACT_SFX, "with": true})
	var title_key := str(options.get("title_key", ""))
	if not title_key.is_empty():
		steps.append({"cmd": "banner", "text_key": title_key, "style": "boss" if boss else "event", "time": 1.5, "with": true})
	for page_value in pages:
		if not page_value is Dictionary:
			continue
		var page: Dictionary = page_value
		var speaker_id := str(page.get("speaker_id", ""))
		var kind := str(page.get("speaker_kind", ""))
		var side := "ally"
		var actor := "leader"
		if kind == "ENEMY" or foe_ids.has(speaker_id):
			side = "foe"
			actor = "foe"
		elif event_ids.has(speaker_id):
			side = "event"
			actor = "foe"
		elif kind == "NARRATION":
			side = "event"
			actor = "center"
		var say := {"cmd": "say", "actor": actor, "side": side, "text_key": str(page.get("text_key", "")), "portrait": str(page.get("portrait_asset_id", ""))}
		var speaker_key := str(page.get("speaker_key", ""))
		if resolver.is_valid():
			say["speaker"] = str(resolver.call(page))
		elif not speaker_key.is_empty():
			say["speaker_key"] = speaker_key
		steps.append(say)
	var outcome_key := str(options.get("outcome_key", ""))
	if not outcome_key.is_empty():
		steps.append({"cmd": "banner", "text_key": outcome_key, "style": "event", "time": 1.8, "tap": true})
	steps.append({"cmd": "camera", "focus": "center", "zoom": 1.0, "time": 0.4})
	return steps
