extends Node

const CachedDraw := preload("res://battle/view/battle_cached_draw.gd")
const Ornament := preload("res://ui/ornament_draw.gd")
const NumberFont := preload("res://assets/fonts/LanternRounded-Black.ttf")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	AppState.new_game()
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N20"), 4711, DataRegistry.data)
	var view := BattleView.new()
	view.size = Vector2(1920, 1080)
	view.setup(sim)
	var actor: Dictionary = sim.state.party[0]
	view.field_offset = Vector2(17, -8)
	view.field_zoom = 1.07
	view.presentation_director.request_combat_focus(1.0, .7, .8)
	view.presentation_director.request_combat_impact(.8, "snap")
	view.presentation_director.advance(.06)
	var expected_ground := view._ground_position(actor)
	var expected_camera := view._battlefield_pixel_transform()
	view._begin_draw_memos()
	check(view._ground_position(actor).is_equal_approx(expected_ground), "memoization retains the moving/shaking actor anchor")
	check(view._battlefield_pixel_transform().is_equal_approx(expected_camera), "memoization retains the current 1080p camera transform")
	view._draw_memo_active = false
	view.engagement_positions[str(actor.uid)] = Vector2(.30, .80)
	view.presentation_director.advance(.08)
	expected_ground = view._ground_position(actor)
	view._begin_draw_memos()
	check(view._ground_position(actor).is_equal_approx(expected_ground), "a new draw discards the prior camera and formation anchor")
	view._draw_memo_active = false
	# One temporary texture exercises the same compact-fallback rectangle path
	# without waiting for optional art loading or changing any asset on disk.
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	view.fallback_combat_previews[str(actor.def_id)] = ImageTexture.create_from_image(image)
	var reference := view._combat_sprite_frame(actor, true)
	view._begin_draw_memos()
	var main_frame := view._combat_sprite_frame(actor, true)
	view.sprite_draw_scale = .70
	var companion := view._combat_sprite_frame(actor, true)
	view.sprite_draw_scale = 1.0
	var main_again := view._combat_sprite_frame(actor, true)
	check(main_frame.rect == reference.rect and main_again.rect == reference.rect, "a scaled companion cannot resize the main body's memo")
	check(companion.rect == Rect2((reference.rect as Rect2).position * .70, (reference.rect as Rect2).size * .70), "a companion keeps the exact authored 70 percent rectangle")
	check(companion.texture == reference.texture, "companions reuse the original texture without copies")
	var down := view._combat_sprite_frame(actor, false)
	check(str(down.animation) == "down" and str(main_again.animation) != "down", "alive and down frame lookups remain separate")
	view._draw_memo_active = false
	var mesh := view._cell_mesh(2, 1, .003)
	view.field_zoom = 1.12
	view.field_offset = Vector2(-31, 6)
	check(view._cell_mesh(2, 1, .003) == mesh, "camera animation reuses fixed cell geometry")
	view.size = Vector2(1080, 1920)
	check(view._cell_mesh(2, 1, .003) != mesh, "portrait resize invalidates the 1080p cell mesh")
	check(CachedDraw.disc_mesh() == CachedDraw.disc_mesh(), "all filled circles reuse one 64-segment mesh")
	_ornament_geometry()
	_ornament_metrics()
	view.free()
	await _draw_flow(sim)
	print("BATTLE_FPS_CACHE_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

class DrawProbe extends BattleView:
	var drawn := 0
	func _ready() -> void:
		set_process(false)
	func _draw() -> void:
		drawn += 1
		super._draw()

func _draw_flow(sim: BattleSimulation) -> void:
	var probe := DrawProbe.new()
	probe.size = Vector2(1920, 1080)
	probe.setup(sim)
	probe.assets_ready = true
	add_child(probe)
	var before := JSON.stringify(sim.result_snapshot())
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	check(probe.drawn > 0 and not probe._draw_memo_active, "the complete 1080p draw flow ends its per-frame memo scope")
	check(JSON.stringify(sim.result_snapshot()) == before, "drawing leaves authoritative combat state unchanged")
	probe.queue_free()

func _ornament_geometry() -> void:
	var same := true
	var samples := 0
	# Include the opening narrow reveal, two clipped boundaries, negative time
	# and the complete 1080p band. Interior vertices bypass only clipping.
	for rect in [Rect2(14.25, 122.5, 1920, 24.624), Rect2(720.0, 125.0, 188.25, 24.624), Rect2(1850.0, 200.0, 70.0, 30.0)]:
		var stripe := float(rect.size.y) * 1.2
		for time in [-1.85, -.01, 0.0, .11, .99, 2.145]:
			var x: float = rect.position.x - rect.size.y - stripe * 2.0 + fposmod(time * stripe * 2.0, stripe * 2.0)
			while x < rect.end.x:
				var original := PackedVector2Array([
					Vector2(x, rect.end.y), Vector2(x + stripe, rect.end.y),
					Vector2(x + stripe + rect.size.y, rect.position.y), Vector2(x + rect.size.y, rect.position.y),
				])
				var clipped := Geometry2D.intersect_polygons(original, PackedVector2Array([
					rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
				]))
				var optimized := Ornament._hazard_stripe_polygon(rect, x, stripe)
				var reference: PackedVector2Array = clipped[0] if not clipped.is_empty() else PackedVector2Array()
				var visible := optimized.size() >= 3 and absf(Ornament._polygon_area(optimized)) > .5
				var expected := reference.size() >= 3 and absf(Ornament._polygon_area(reference)) > .5
				same = same and visible == expected
				if visible and expected:
					same = same and optimized.size() == reference.size()
					for point in optimized:
						var found := false
						for other in reference:
							# Geometry2D's fixed-point clipping rounds coordinates;
							# direct interior vertices retain their float precision.
							found = found or point.distance_to(other) < .002
						same = same and found
				samples += 1
				x += stripe * 2.0
	check(same and samples > 200, "hazard stripes retain the original clipped geometry across 1080p reveal boundaries")

func _ornament_metrics() -> void:
	var font := FontVariation.new()
	font.base_font = NumberFont
	var text := "BOSS ENCOUNTER"
	var metrics := Ornament.text_metrics(font, text, 74)
	check(float(metrics.width) == font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 74).x and float(metrics.ascent) == font.get_ascent(74) and float(metrics.descent) == font.get_descent(74), "cached banner metrics exactly match the original Font measurements")
	check(Ornament.text_metrics(font, text, 74) == metrics, "unchanged labels reuse font metrics")
	font.changed.emit()
	check(not Ornament._text_metrics.has("%d:74:%s" % [font.get_instance_id(), text]), "a changed Font invalidates its measured labels")
