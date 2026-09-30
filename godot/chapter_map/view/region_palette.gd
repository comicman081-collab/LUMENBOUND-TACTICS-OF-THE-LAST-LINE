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

## Terrain shader accents per family: open-ground patches (moss, frost, sand),
## worn hex rims and the grassy or frosted lip under each terrace. Chapter 1's
## forest is the reference; other regions reuse the same shader with their own
## colours, so no region needs a new texture.
static func surface_look(definition: Dictionary) -> Dictionary:
	var palette := for_definition(definition)
	var looks := {
		"FOREST": ["3e5a2c", .55, "8f8466", "4c6e32", "a9c7c4"],
		"FROST": ["dce8ec", .62, "b7c3c7", "e6eef1", "c9dae3"],
		"DUNE": ["b99c68", .45, "cdb488", "8a784c", "e0c9a0"],
		"ASH": ["2e2b2a", .45, "85766a", "4a4440", "9a8f88"],
		"TIDAL": ["4d7a5c", .45, "b3a27a", "3e6a54", "a3c9c6"],
		"GLASS": ["6a9fa4", .35, "9cb1a6", "4d7d76", "b4d6dc"],
		"LUNAR": ["696e92", .35, "a099ae", "575c7f", "b7b3d0"],
		"RUINS": ["4a5c38", .40, "998866", "55673e", "b0bcb2"],
	}
	var look: Array = looks.get(str(palette.family), looks.FOREST)
	return {"ground": (palette.ground as Color).lightened(.10), "patch": Color(look[0]), "patch_amount": float(look[1]),
		"wear": Color(look[2]), "lip": Color(look[3]), "haze": Color(look[4])}
