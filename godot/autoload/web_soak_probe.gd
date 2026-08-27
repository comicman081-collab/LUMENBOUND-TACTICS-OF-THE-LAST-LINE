extends Node

const SAMPLE_INTERVAL_SECONDS := 5.0
const MAX_SAMPLES := 240

var elapsed_seconds := 0.0
var sample_accumulator := 0.0
var samples: Array[Dictionary] = []
var minimum_fps := 1000000.0
var maximum_static_memory := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(OS.has_feature("web"))
	if OS.has_feature("web"):
		var sandbox_state := "active" if SaveService.is_soak_sandbox_enabled() else "inactive"
		print("R7_WEB_SOAK_PROBE_READY interval=5s max_samples=240 sandbox=%s" % sandbox_state)

func _process(delta: float) -> void:
	elapsed_seconds += delta
	sample_accumulator += delta
	if sample_accumulator < SAMPLE_INTERVAL_SECONDS:
		return
	sample_accumulator = fmod(sample_accumulator, SAMPLE_INTERVAL_SECONDS)
	_capture_sample()

func _capture_sample() -> void:
	var fps := float(Engine.get_frames_per_second())
	var static_memory := float(Performance.get_monitor(Performance.MEMORY_STATIC))
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	minimum_fps = min(minimum_fps, fps)
	maximum_static_memory = max(maximum_static_memory, static_memory)
	var sample := {
		"sample": samples.size() + 1,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.001),
		"fps": fps,
		"static_memory_bytes": int(static_memory),
		"node_count": node_count,
		"orphan_node_count": orphan_count,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		# Runtime playback evidence is intentionally metadata-only.  It proves
		# that the WebAudio gate opened and the wired events reached actual
		# AudioStreamPlayers without recording or exposing any audio content.
		"audio": AudioService.runtime_status(),
	}
	if samples.size() >= MAX_SAMPLES:
		samples.pop_front()
	samples.append(sample)
	print("R7_WEB_SOAK_SAMPLE ", JSON.stringify(sample))
	# Emit a non-invasive namespace audit every 30 seconds.  This observes only
	# SaveService's resolved paths; it does not open or inspect production saves.
	if SaveService.is_soak_sandbox_enabled() and samples.size() % 6 == 0:
		print("R7_WEB_SOAK_SAVE_AUDIT ", JSON.stringify(SaveService.sandbox_audit_summary()))
	if samples.size() == MAX_SAMPLES:
		print("R7_WEB_SOAK_COMPLETE ", JSON.stringify(summary()))

func summary() -> Dictionary:
	var fps_total := 0.0
	for sample in samples:
		fps_total += float(sample.fps)
	var first_memory := int(samples.front().static_memory_bytes) if not samples.is_empty() else 0
	var last_memory := int(samples.back().static_memory_bytes) if not samples.is_empty() else 0
	var report := {
		"samples": samples.size(),
		"elapsed_seconds": snappedf(elapsed_seconds, 0.001),
		"average_fps": snappedf(fps_total / max(1, samples.size()), 0.01),
		"minimum_fps": minimum_fps if minimum_fps < 1000000.0 else 0.0,
		"memory_start_bytes": first_memory,
		"memory_end_bytes": last_memory,
		"memory_delta_bytes": last_memory - first_memory,
		"maximum_static_memory_bytes": int(maximum_static_memory),
		"orphan_nodes": int(samples.back().orphan_node_count) if not samples.is_empty() else 0,
	}
	if SaveService.is_soak_sandbox_enabled():
		report["save_sandbox_audit"] = SaveService.sandbox_audit_summary()
	return report
