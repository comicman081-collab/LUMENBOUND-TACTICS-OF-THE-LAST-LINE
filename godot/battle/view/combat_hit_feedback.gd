extends RefCounted

## Hit feedback rules for phase 4 (D6). Everything here is view-only: it reads a
## damage/heal event and the target snapshot and answers how the hit should look
## and feel. Battle math, RNG and the event log are never touched.
##
## A hit is classified once into a style (normal / crit / weak / resist / miss /
## heal / shield). The style picks the damage-number shape, the camera shake
## preset, the hit-spark accent and how hard the victim slides back. The damage
## weight (share of the victim's max HP, saturating at 30 percent) scales the
## camera impulse, so the director's hit-stop (capped at 55 ms) and the knockback
## grow with the damage instead of staying at one fixed size.

const WEIGHT_FULL_SHARE := .30
const WEAK_AFFINITY := 1.2
const RESIST_AFFINITY := .9
const WHITE_FLASH_FRAMES := 2
## Brightening past 1.0 saturates the sprite towards white on the LDR canvas.
const WHITE_FLASH_TINT := Color(4.5, 4.5, 4.5, 1.0)

const SHAKE_PRESETS := ["tap", "thud", "snap", "quake"]

const NUMBER_STYLES := {
	"normal": {"size": 1.0, "ink": Color("fffaf0"), "tag": "", "rise": 34.0, "pop": .16, "duration": 1.15},
	"crit": {"size": 1.38, "ink": Color("ffd24a"), "tag": "CRITICAL", "tag_ink": Color(1.0, .62, .25), "rise": 34.0, "pop": .55, "duration": 1.35},
	"weak": {"size": 1.18, "ink": Color("ff9a4a"), "tag": "WEAK", "tag_ink": Color(.50, .90, 1.0), "rise": 36.0, "pop": .30, "duration": 1.30},
	"resist": {"size": .84, "ink": Color("a9b7c8"), "tag": "RESIST", "tag_ink": Color(.72, .78, .86), "rise": 30.0, "pop": .08, "duration": 1.05},
	"heal": {"size": 1.06, "ink": Color("76e6a5"), "tag": "", "rise": 22.0, "pop": .22, "duration": 1.30},
	"shield": {"size": .96, "ink": Color("72d5ff"), "tag": "", "rise": 26.0, "pop": .14, "duration": 1.15},
	"miss": {"size": .72, "ink": Color(.78, .82, .88), "tag": "", "rise": 34.0, "pop": .16, "duration": 1.15},
}

static func damage_style(event: Dictionary) -> String:
	if int(event.get("value", 0)) <= 0: return "miss"
	var extra: Dictionary = event.get("extra", {})
	if bool(extra.get("crit", false)): return "crit"
	var affinity := float(extra.get("affinity_factor", 1.0))
	if affinity >= WEAK_AFFINITY: return "weak"
	if affinity <= RESIST_AFFINITY: return "resist"
	return "normal"

static func damage_weight(event: Dictionary, target: Dictionary) -> float:
	var extra: Dictionary = event.get("extra", {})
	var amount := maxi(0, int(extra.get("hp_damage", event.get("value", 0))))
	if amount <= 0: return 0.0
	var max_hp := maxf(1.0, float(target.get("max_hp", target.get("hp", 1))))
	return clampf(float(amount) / max_hp / WEIGHT_FULL_SHARE, 0.0, 1.0)

static func impact_strength(style: String, weight: float, source_kind: String, boss_involved: bool) -> float:
	var strength := .22 + .48 * clampf(weight, 0.0, 1.0)
	if style == "crit": strength += .12
	elif style == "weak": strength += .05
	elif style == "resist": strength -= .06
	if source_kind == "ULTIMATE": strength = maxf(strength, .82)
	if boss_involved: strength = maxf(strength, .40 + .25 * weight)
	return clampf(strength, .12, 1.0)

static func shake_preset(style: String, weight: float, source_kind: String) -> String:
	if source_kind == "ULTIMATE": return "quake"
	if style == "crit": return "snap"
	if weight >= .5: return "thud"
	return "tap"

## Shake shape per preset: x/y frequency and amplitude in battlefield pixels.
static func shake_shape(preset: String) -> Dictionary:
	match preset:
		"tap": return {"fx": 163.0, "fy": 121.0, "ax": 5.0, "ay": 2.5}
		"snap": return {"fx": 187.0, "fy": 97.0, "ax": 10.5, "ay": 2.0}
		"quake": return {"fx": 83.0, "fy": 67.0, "ax": 6.0, "ay": 9.5}
	return {"fx": 143.0, "fy": 109.0, "ax": 7.0, "ay": 3.5}

## Flash length and slide distance for the victim. Returns {duration, power}.
static func reaction_span(style: String, weight: float) -> Dictionary:
	var power := .85 + 1.25 * clampf(weight, 0.0, 1.0)
	var duration := .14 + .09 * clampf(weight, 0.0, 1.0)
	if style == "crit":
		power += .35
		duration += .03
	elif style == "weak":
		power += .15
	elif style == "resist":
		power *= .7
	return {"duration": duration, "power": power}

## Accent drawn on the impact burst, "" for plain hits.
static func impact_accent(style: String) -> String:
	if style == "crit": return "crit"
	if style == "weak": return "weak"
	return ""

static func number_style(style: String) -> Dictionary:
	return NUMBER_STYLES.get(style, NUMBER_STYLES.normal)

static func white_flash_active(frames_left: int) -> bool:
	return frames_left > 0
