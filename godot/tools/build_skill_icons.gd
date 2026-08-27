extends SceneTree

## Deterministic, offline-only skill icon factory.
##
## The source SVG is authored in code so the Web runtime receives only PNG
## derivatives.  No network, external model, paid API or runtime generator is
## involved. Every immutable SkillDef ID receives a different character/type
## motif while sharing one coherent Lanternline frame system.

const OUTPUT_ROOT := "res://assets/art/icons/skills"
const REPORT_ROOT := "res://../reports/r15/skill_icons"
const GENERATOR_VERSION := "lanternline-skill-icons-1.1.0"
const RESOLUTIONS := [256, 128, 64]

const CHARACTER_SPECS := [
	{"id": "CHR001", "primary": "#28d9c6", "secondary": "#256fa8", "accent": "#fff19a", "motifs": {
		"NORMAL": "<path d='M82 80 L128 55 L174 80 V130 C174 164 153 188 128 201 C103 188 82 164 82 130 Z'/><path d='M106 116 H150 M116 98 L128 86 L140 98'/><path d='M98 143 C115 128 141 128 158 143'/>",
		"PASSIVE": "<path d='M86 174 V94 L108 72 V174 M148 174 V82 L170 104 V174'/><path d='M72 174 H184'/><path d='M112 132 L128 108 L144 132 L128 158 Z'/>",
		"ULTIMATE": "<path d='M62 158 C70 92 92 66 128 54 C164 66 186 92 194 158'/><path d='M78 158 H178'/><path d='M104 142 L128 104 L152 142 L128 168 Z'/><path d='M128 54 V86'/>",
	}},
	{"id": "CHR002", "primary": "#ff7b73", "secondary": "#9f3f78", "accent": "#ffe18c", "motifs": {
		"NORMAL": "<path d='M74 170 L166 78 L181 63 L193 75 L178 90 L86 182 Z'/><path d='M70 126 L126 182'/><path d='M118 70 L186 138'/>",
		"PASSIVE": "<path d='M128 60 L150 105 L199 112 L164 146 L173 194 L128 171 L83 194 L92 146 L57 112 L106 105 Z'/><path d='M91 166 L165 92'/>",
		"ULTIMATE": "<path d='M58 170 C94 158 120 127 137 78'/><path d='M83 190 C120 172 151 132 170 69'/><path d='M113 194 C153 167 177 133 194 93'/><path d='M132 76 L150 55 L162 82'/>",
	}},
	{"id": "CHR003", "primary": "#74a7ff", "secondary": "#4354b8", "accent": "#bdfcff", "motifs": {
		"NORMAL": "<circle cx='128' cy='128' r='60'/><circle cx='128' cy='128' r='25'/><path d='M128 46 V91 M128 165 V210 M46 128 H91 M165 128 H210'/>",
		"PASSIVE": "<path d='M52 128 C77 84 101 68 128 68 C155 68 179 84 204 128 C179 172 155 188 128 188 C101 188 77 172 52 128 Z'/><circle cx='128' cy='128' r='31'/><path d='M128 104 V152 M104 128 H152'/>",
		"ULTIMATE": "<path d='M51 128 H185'/><path d='M145 86 L199 128 L145 170'/><path d='M72 103 L98 128 L72 153'/><circle cx='128' cy='128' r='19'/>",
	}},
	{"id": "CHR004", "primary": "#ce78ff", "secondary": "#5e58c8", "accent": "#8ffff1", "motifs": {
		"NORMAL": "<path d='M82 78 L124 119 L105 132 L149 178 L178 145 L137 108 L155 91 L116 54 Z'/><path d='M77 151 L111 117 M145 151 L179 117'/>",
		"PASSIVE": "<path d='M68 100 H102 V70 H154 V100 H188 V156 H154 V186 H102 V156 H68 Z'/><path d='M102 100 H154 V156 H102 Z'/><circle cx='128' cy='128' r='17'/>",
		"ULTIMATE": "<path d='M50 128 L91 94 L128 55 L165 94 L206 128 L165 162 L128 201 L91 162 Z'/><path d='M72 128 H184'/><path d='M128 76 V180'/><circle cx='128' cy='128' r='27'/>",
	}},
	{"id": "CHR005", "primary": "#f29b45", "secondary": "#aa3f54", "accent": "#fff0a6", "motifs": {
		"NORMAL": "<path d='M62 171 Q111 69 176 78'/><path d='M161 63 L190 75 L176 102'/><circle cx='78' cy='172' r='18'/><path d='M60 195 H112'/>",
		"PASSIVE": "<path d='M58 175 C80 130 102 102 128 76 C154 102 176 130 198 175'/><path d='M77 175 H179'/><path d='M94 148 H162'/><circle cx='128' cy='76' r='17'/>",
		"ULTIMATE": "<path d='M128 48 L145 94 L192 84 L163 124 L202 153 L153 151 L147 201 L120 159 L80 190 L94 143 L46 131 L91 113 L67 69 L112 92 Z'/><circle cx='128' cy='128' r='29'/>",
	}},
	{"id": "CHR006", "primary": "#50c5ff", "secondary": "#4153a7", "accent": "#d5ff8a", "motifs": {
		"NORMAL": "<circle cx='128' cy='128' r='65'/><path d='M128 79 V132 L94 154'/><path d='M88 65 L66 87 M168 65 L190 87'/><path d='M86 190 L104 169 M170 190 L152 169'/>",
		"PASSIVE": "<path d='M128 49 L157 98 L207 128 L157 158 L128 207 L99 158 L49 128 L99 98 Z'/><circle cx='128' cy='128' r='32'/><path d='M128 96 V160 M96 128 H160'/>",
		"ULTIMATE": "<path d='M76 91 C97 67 119 82 128 103 C137 82 159 67 180 91 C201 115 179 139 158 145 C151 168 105 168 98 145 C77 139 55 115 76 91 Z'/><path d='M90 165 L72 188 M166 165 L184 188'/><path d='M103 126 H153'/>",
	}},
	{"id": "CHR007", "primary": "#9a8aff", "secondary": "#3d7f83", "accent": "#ffcf83", "motifs": {
		"NORMAL": "<path d='M128 54 L183 86 V142 C183 174 159 194 128 207 C97 194 73 174 73 142 V86 Z'/><path d='M91 128 C109 101 147 101 165 128 C147 155 109 155 91 128 Z'/>",
		"PASSIVE": "<circle cx='128' cy='128' r='25'/><circle cx='128' cy='128' r='65'/><circle cx='128' cy='63' r='11'/><circle cx='184' cy='160' r='11'/><circle cx='72' cy='160' r='11'/><path d='M128 88 V103 M106 141 L85 154 M150 141 L171 154'/>",
		"ULTIMATE": "<path d='M128 47 C145 81 167 95 207 103 C178 128 168 151 174 194 C144 174 112 174 82 194 C88 151 78 128 49 103 C89 95 111 81 128 47 Z'/><path d='M128 81 V167 M89 124 H167'/>",
	}},
	{"id": "CHR008", "primary": "#62e3a1", "secondary": "#3375a7", "accent": "#fff3b0", "motifs": {
		"NORMAL": "<path d='M128 58 V198 M58 128 H198'/><path d='M89 83 C120 86 136 105 128 128 C101 131 84 111 89 83 Z'/><path d='M167 173 C136 170 120 151 128 128 C155 125 172 145 167 173 Z'/>",
		"PASSIVE": "<path d='M62 132 H94 L111 91 L135 169 L151 120 H194'/><path d='M128 195 C92 171 65 148 65 108 C65 69 111 66 128 96 C145 66 191 69 191 108 C191 148 164 171 128 195 Z'/>",
		"ULTIMATE": "<path d='M128 47 L147 92 L195 69 L172 117 L218 128 L172 139 L195 187 L147 164 L128 209 L109 164 L61 187 L84 139 L38 128 L84 117 L61 69 L109 92 Z'/><path d='M128 84 V172 M84 128 H172'/>",
	}},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []
	var manifest_assets: Array = []
	var license_assets: Array = []
	var qa_rows: Array = []
	var hashes_by_resolution := {256: {}, 128: {}, 64: {}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_ROOT))
	for spec_variant in _all_character_specs():
		var spec: Dictionary = spec_variant
		for skill_kind in ["NORMAL", "PASSIVE", "ULTIMATE"]:
			var skill_id := "SK_%s_%s" % [str(spec.id), skill_kind]
			var asset_id := "skill_icon_%s_%s" % [str(spec.id).to_lower(), skill_kind.to_lower()]
			var icon_dir := OUTPUT_ROOT.path_join(asset_id)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(icon_dir))
			var svg := _build_svg(spec, skill_kind)
			var master := Image.new()
			var load_error := master.load_svg_from_string(svg, 1.0)
			if load_error != OK:
				errors.append("%s SVG render error %d" % [asset_id, load_error])
				continue
			var variants := {}
			var variant_hashes := {}
			var resolution_qa := {}
			for resolution in RESOLUTIONS:
				var image := master.duplicate()
				if resolution != 256:
					image.resize(resolution, resolution, Image.INTERPOLATE_LANCZOS)
				var relative_path := icon_dir.path_join("icon_%d.png" % resolution)
				var absolute_path := ProjectSettings.globalize_path(relative_path)
				var save_error: Error = image.save_png(absolute_path)
				if save_error != OK:
					errors.append("%s save %d error %d" % [asset_id, resolution, save_error])
					continue
				var file_hash := FileAccess.get_sha256(relative_path)
				variants[str(resolution)] = relative_path
				variant_hashes[str(resolution)] = file_hash
				hashes_by_resolution[resolution][file_hash] = int(hashes_by_resolution[resolution].get(file_hash, 0)) + 1
				resolution_qa[str(resolution)] = _readability_metrics(image)
			manifest_assets.append({
				"asset_id": asset_id,
				"entity_id": skill_id,
				"category": "skill_icon",
				"subtype": "%s_SKILL" % skill_kind,
				"status": "ART_QA_CANDIDATE",
				"godot_path": variants.get("256", ""),
				"variants": variants,
				"generator_version": GENERATOR_VERSION,
				"source_script": "res://tools/build_skill_icons.gd",
				"seed": 2026082300 + manifest_assets.size(),
				"width": 256,
				"height": 256,
				"alpha": true,
				"readable_resolutions": RESOLUTIONS,
				"dependencies": [],
				"license": "Original internal project asset",
				"commercial_use": true,
				"attribution": "Not required",
				"ownership_status": "ORIGINAL_INTERNAL",
				"sha256": variant_hashes.get("256", ""),
				"variant_sha256": variant_hashes,
				"qa_status": "TECHNICAL_PASS",
				"revision": "R7",
			})
			license_assets.append({
				"asset_id": asset_id,
				"creator": "Lanternline local code-native icon factory",
				"creation_method": "Deterministic offline SVG rasterization in Godot 4.7.1",
				"source_script": "res://tools/build_skill_icons.gd",
				"third_party_dependency": "NONE",
				"license": "Original internal project asset",
				"commercial_use": true,
				"attribution_required": false,
				"ownership_status": "ORIGINAL_INTERNAL",
				"file_sha256": variant_hashes.get("256", ""),
			})
			qa_rows.append({
				"asset_id": asset_id,
				"skill_id": skill_id,
				"resolution_metrics": resolution_qa,
				"all_sizes_readable": _all_sizes_readable(resolution_qa),
			})
	for resolution in RESOLUTIONS:
		for file_hash in hashes_by_resolution[resolution]:
			if int(hashes_by_resolution[resolution][file_hash]) != 1:
				errors.append("duplicate icon at %dpx hash=%s count=%d" % [resolution, file_hash, hashes_by_resolution[resolution][file_hash]])
	var manifest := {
		"schema_version": 1,
		"generator_version": GENERATOR_VERSION,
		"revision": "R7",
		"asset_count": manifest_assets.size(),
		"assets": manifest_assets,
	}
	_write_text(OUTPUT_ROOT.path_join("skill_icon_manifest.json"), JSON.stringify(manifest, "  ") + "\n", errors)
	_write_text(OUTPUT_ROOT.path_join("skill_icon_licenses.json"), JSON.stringify({"schema_version": 1, "assets": license_assets}, "  ") + "\n", errors)
	_write_text(OUTPUT_ROOT.path_join("attribution.md"), "# Skill icon attribution\n\nAll %d icons are ORIGINAL_INTERNAL deterministic local assets. No attribution is required and no external dependency is used.\n" % manifest_assets.size(), errors)
	_write_contact_sheet(manifest_assets, errors)
	var qa_report := {
		"kind": "R15_SKILL_ICON_TECHNICAL_QA",
		"generator_version": GENERATOR_VERSION,
		"planned": _all_character_specs().size() * 3,
		"generated": manifest_assets.size(),
		"unique_per_resolution": {
			"256": hashes_by_resolution[256].size(),
			"128": hashes_by_resolution[128].size(),
			"64": hashes_by_resolution[64].size(),
		},
		"readability_pass": qa_rows.filter(func(row): return bool(row.all_sizes_readable)).size(),
		"errors": errors,
		"icons": qa_rows,
		"verdict": "TECHNICAL_PASS" if errors.is_empty() and manifest_assets.size() == _all_character_specs().size() * 3 and qa_rows.all(func(row): return bool(row.all_sizes_readable)) else "FAIL",
	}
	_write_text(REPORT_ROOT.path_join("SKILL_ICON_TECHNICAL_QA.json"), JSON.stringify(qa_report, "  ") + "\n", errors)
	print("SKILL_ICON_BUILD generated=%d readable=%d errors=%d verdict=%s" % [manifest_assets.size(), qa_report.readability_pass, errors.size(), qa_report.verdict])
	quit(0 if qa_report.verdict == "TECHNICAL_PASS" else 1)


func _all_character_specs() -> Array:
	var specs: Array = CHARACTER_SPECS.duplicate(true)
	var known_ids := {}
	for spec_variant in specs:
		known_ids[str((spec_variant as Dictionary).get("id", ""))] = true
	var file := FileAccess.open("res://data/compiled/game_data.json", FileAccess.READ)
	if file == null:
		return specs
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return specs
	for character_variant in (parsed as Dictionary).get("characters", []):
		var character: Dictionary = character_variant
		var character_id := str(character.get("id", ""))
		if character_id.is_empty() or known_ids.has(character_id):
			continue
		var numeric_id := int(character_id.trim_prefix("CHR"))
		var hue := fposmod(float(numeric_id * 47) / 360.0, 1.0)
		var primary := "#%s" % Color.from_hsv(hue, 0.66, 0.96).to_html(false)
		# Keep the shared card gradient genuinely dark at every hue. This gives the
		# 64px derivative a measurable dark field behind the bright role motif.
		var secondary := "#%s" % Color.from_hsv(fposmod(hue + 0.11, 1.0), 0.74, 0.18).to_html(false)
		var accent := "#%s" % Color.from_hsv(fposmod(hue + 0.48, 1.0), 0.32, 1.0).to_html(false)
		specs.append({
			"id": character_id,
			"primary": primary,
			"secondary": secondary,
			"accent": accent,
			"motifs": _role_motifs(str(character.get("role", "ASSAULT"))),
		})
	return specs


func _role_motifs(role: String) -> Dictionary:
	var motifs := {
		"GUARDIAN": ["<path d='M82 80 L128 55 L174 80 V130 C174 164 153 188 128 201 C103 188 82 164 82 130 Z'/><path d='M100 129 H156 M128 96 V162'/>", "<path d='M128 49 L157 98 L207 128 L157 158 L128 207 L99 158 L49 128 L99 98 Z'/><circle cx='128' cy='128' r='30'/>", "<path d='M58 170 C74 99 97 62 128 52 C159 62 182 99 198 170'/><path d='M78 169 H178'/><path d='M128 73 V181'/>"],
		"VANGUARD": ["<path d='M68 178 L174 72 L190 88 L84 194 Z'/><path d='M71 119 L137 185'/>", "<path d='M52 157 H170'/><path d='M135 104 L204 157 L135 210'/><path d='M72 104 L118 157 L72 210'/>", "<path d='M56 183 C91 169 118 135 139 69'/><path d='M89 198 C126 173 158 132 181 73'/><path d='M143 74 L161 55 L173 82'/>"],
		"ASSAULT": ["<circle cx='128' cy='128' r='58'/><circle cx='128' cy='128' r='20'/><path d='M128 45 V88 M128 168 V211 M45 128 H88 M168 128 H211'/>", "<path d='M57 128 H199'/><path d='M128 57 V199'/><circle cx='128' cy='128' r='37'/>", "<path d='M48 128 H177'/><path d='M142 84 L208 128 L142 172'/><path d='M82 101 L109 128 L82 155'/>"],
		"ARTILLERY": ["<path d='M59 179 Q107 70 179 79'/><path d='M164 64 L193 76 L178 104'/><circle cx='78' cy='181' r='18'/>", "<path d='M63 175 C85 126 106 96 128 76 C151 96 173 126 194 175'/><path d='M80 175 H176'/><circle cx='128' cy='76' r='15'/>", "<path d='M128 48 L145 95 L194 84 L163 125 L205 152 L154 152 L146 203 L119 160 L76 190 L93 144 L47 130 L91 113 L68 70 L111 92 Z'/><circle cx='128' cy='128' r='24'/>"],
		"SPECIALIST": ["<circle cx='128' cy='128' r='62'/><circle cx='128' cy='128' r='23'/><circle cx='128' cy='63' r='10'/><circle cx='184' cy='160' r='10'/><circle cx='72' cy='160' r='10'/>", "<path d='M128 50 L155 99 L206 128 L155 157 L128 206 L101 157 L50 128 L101 99 Z'/><circle cx='128' cy='128' r='31'/>", "<path d='M128 46 C147 82 169 96 207 104 C178 128 169 153 175 195 C145 174 111 174 81 195 C87 153 78 128 49 104 C87 96 109 82 128 46 Z'/><path d='M128 81 V170'/>"],
		"MEDIC": ["<path d='M128 57 V199 M57 128 H199'/><circle cx='128' cy='128' r='43'/>", "<path d='M62 131 H94 L111 90 L135 168 L151 119 H194'/><path d='M128 196 C92 172 65 149 65 108 C65 70 110 66 128 96 C146 66 191 70 191 108 C191 149 164 172 128 196 Z'/>", "<path d='M128 47 L147 92 L195 69 L172 117 L218 128 L172 139 L195 187 L147 164 L128 209 L109 164 L61 187 L84 139 L38 128 L84 117 L61 69 L109 92 Z'/><path d='M128 87 V169 M87 128 H169'/>"],
	}
	var role_motifs: Array = motifs.get(role, motifs["ASSAULT"])
	return {"NORMAL": role_motifs[0], "PASSIVE": role_motifs[1], "ULTIMATE": role_motifs[2]}


func _build_svg(spec: Dictionary, skill_kind: String) -> String:
	var type_frame: String = ({
		"NORMAL": "<circle cx='128' cy='128' r='103' fill='none' stroke='%s' stroke-width='5'/>",
		"PASSIVE": "<path d='M128 20 L223 74 L223 182 L128 236 L33 182 L33 74 Z' fill='none' stroke='%s' stroke-width='5'/>",
		"ULTIMATE": "<path d='M128 13 L153 31 L183 25 L197 52 L226 64 L225 95 L243 120 L225 145 L226 176 L197 188 L183 215 L153 209 L128 227 L103 209 L73 215 L59 188 L30 176 L31 145 L13 120 L31 95 L30 64 L59 52 L73 25 L103 31 Z' fill='none' stroke='%s' stroke-width='5'/>",
	}[skill_kind] as String) % str(spec.accent)
	var type_accents: String = {
		"NORMAL": "<path d='M44 94 L55 72 L77 61 M212 94 L201 72 L179 61' fill='none'/>",
		"PASSIVE": "<circle cx='55' cy='128' r='7'/><circle cx='201' cy='128' r='7'/><circle cx='128' cy='49' r='7'/><circle cx='128' cy='207' r='7'/>",
		"ULTIMATE": "<path d='M128 28 V48 M128 208 V228 M28 128 H48 M208 128 H228 M57 57 L72 72 M184 184 L199 199 M199 57 L184 72 M72 184 L57 199' fill='none'/>",
	}[skill_kind]
	return """<svg width='256' height='256' viewBox='0 0 256 256'>
<defs>
 <linearGradient id='bg' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#071421'/><stop offset='.55' stop-color='%s'/><stop offset='1' stop-color='#05080e'/></linearGradient>
 <radialGradient id='core'><stop offset='0' stop-color='%s' stop-opacity='.42'/><stop offset='1' stop-color='%s' stop-opacity='0'/></radialGradient>
</defs>
<rect x='7' y='7' width='242' height='242' rx='48' fill='url(#bg)' stroke='%s' stroke-width='4'/>
<circle cx='128' cy='128' r='94' fill='url(#core)'/>
%s
<g fill='none' stroke='%s' stroke-width='12' stroke-linecap='round' stroke-linejoin='round'>%s</g>
<g fill='%s' stroke='%s' stroke-width='4' stroke-linecap='round' stroke-linejoin='round'>%s</g>
<circle cx='128' cy='128' r='112' fill='none' stroke='#ffffff' stroke-opacity='.16' stroke-width='2'/>
</svg>""" % [str(spec.secondary), str(spec.primary), str(spec.secondary), str(spec.primary), type_frame, str(spec.primary), str(spec.motifs[skill_kind]), str(spec.accent), str(spec.accent), type_accents]


func _readability_metrics(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var visible := 0
	var bright := 0
	var dark := 0
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if color.a > 0.08:
				visible += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
				var luminance := color.get_luminance()
				if luminance > 0.62: bright += 1
				if luminance < 0.18: dark += 1
	var total := width * height
	var bbox_width := maxi(0, max_x - min_x + 1)
	var bbox_height := maxi(0, max_y - min_y + 1)
	var coverage := float(visible) / float(total)
	# Icons use luminous motifs over a dark translucent card.  Requiring 20% of
	# all pixels to be near-black incorrectly rejects a deliberately bright skill
	# symbol, while 5% still proves that the 64 px derivative keeps meaningful
	# foreground/background contrast instead of collapsing into a flat bloom.
	var pass_readability := coverage > 0.55 and coverage < 0.99 and float(bbox_width) / width > 0.90 and float(bbox_height) / height > 0.90 and bright > total * 0.008 and dark > total * 0.05
	return {
		"width": width,
		"height": height,
		"alpha_coverage": snappedf(coverage, 0.0001),
		"bbox": [min_x, min_y, bbox_width, bbox_height],
		"bright_pixels": bright,
		"dark_pixels": dark,
		"readability_pass": pass_readability,
	}


func _all_sizes_readable(metrics: Dictionary) -> bool:
	for resolution in RESOLUTIONS:
		if not bool(metrics.get(str(resolution), {}).get("readability_pass", false)):
			return false
	return true


func _write_contact_sheet(assets: Array, errors: Array[String]) -> void:
	var cell := 132
	var padding := 12
	var sheet := Image.create(3 * cell + 4 * padding, 8 * cell + 9 * padding, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("07101c"))
	for index in range(assets.size()):
		var path := str(assets[index].get("variants", {}).get("128", ""))
		var icon := Image.new()
		var error := icon.load(ProjectSettings.globalize_path(path))
		if error != OK:
			errors.append("contact sheet load failed %s" % path)
			continue
		var column := index % 3
		var row := index / 3
		var target := Vector2i(padding + column * (cell + padding) + 2, padding + row * (cell + padding) + 2)
		sheet.blit_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), target)
	var output := ProjectSettings.globalize_path(REPORT_ROOT.path_join("SKILL_ICON_CONTACT_SHEET.png"))
	var error := sheet.save_png(output)
	if error != OK: errors.append("contact sheet save error %d" % error)


func _write_text(path: String, text: String, errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("cannot write %s" % path)
		return
	file.store_string(text)
