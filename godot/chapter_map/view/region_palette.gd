extends RefCounted

static var _palettes: Dictionary = {}

# Authored visual-set names select a coherent terrain family. This changes
# presentation only; roads, rivers, elevations and traversal remain canonical.
static func for_definition(definition: Dictionary) -> Dictionary:
	var visual := str(definition.get("visual_set_id", ""))
	if _palettes.has(visual): return _palettes[visual]
	var family := "FOREST"
	if "FROST" in visual: family = "FROST"
	elif "DUNE" in visual or "EXCAVATOR" in visual: family = "DUNE"
	elif "ASH" in visual or "DOOM" in visual: family = "ASH"
	elif "TIDAL" in visual or "TIDE" in visual: family = "TIDAL"
	elif "GLASS" in visual or "VOLT" in visual: family = "GLASS"
	elif "LUNAR" in visual or "DREAM" in visual or "NULL" in visual: family = "LUNAR"
	elif "TERMINUS" in visual or "PRELATE" in visual or "AUDITOR" in visual or "CROWN" in visual or "INDEX" in visual or "TICKET" in visual or "WARDEN" in visual: family = "RUINS"
	var colors: Array = {
		"FOREST": ["354a3e", "735f40", "4b545e", "294637", "3b4b2e"],
		"FROST": ["718d96", "a29b83", "657b8e", "708e94", "a1b8ba"],
		"DUNE": ["75624b", "a58a59", "675851", "5e6042", "958266"],
		"ASH": ["494544", "76614f", "5b5055", "3c443c", "64594c"],
		"TIDAL": ["3f5c59", "8a7b5a", "5b747a", "305c51", "62786a"],
		"GLASS": ["405961", "7c8067", "657c89", "375650", "617b70"],
		"LUNAR": ["4b4c65", "827786", "65718e", "3e4b60", "6b6981"],
		"RUINS": ["50594f", "88765a", "6b7176", "394f42", "626b50"],
	}[family]
	_palettes[visual] = {"family": family, "ground": Color(colors[0]), "road": Color(colors[1]),
		"ruins": Color(colors[2]), "canopy": Color(colors[3]), "bed_light": Color(colors[4])}
	return _palettes[visual]
