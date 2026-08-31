extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AppState.new_game()
	var shell := preload("res://screens/boot/boot.tscn").instantiate()
	add_child(shell)
	await get_tree().process_frame
	shell.last_battle_result = {
		"victory": true,
		"time": 42.25,
		"survivors": 5,
		"seed": 20260830,
		"event_hash": "RESULT_RUNTIME_PROBE",
		"damage": {"CHR001": 1234, "CHR002": 987},
		"healing": {"CHR003": 321},
	}
	shell.last_rewards = {"CREDIT": 3000, "TRAINING_NOTE_L": 1}
	shell.last_reward_report = {
		"source_type": "BATTLE",
		"source_id": "CH01-N01",
		"rewards": shell.last_rewards.duplicate(true),
		"growth": {},
		"progress": {},
	}
	shell.current_screen = "BATTLE"
	shell._show_screen("RESULT")
	await get_tree().process_frame
	var action_buttons := shell.find_children("*", "Button", true, false)
	var result_ready := false
	for button_value in action_buttons:
		if button_value is Button and (button_value as Button).text == "챕터 맵으로":
			result_ready = true
			break
	print("RESULT_RUNTIME_PROBE ready=%s buttons=%d screen=%s" % [str(result_ready), action_buttons.size(), str(shell.current_screen)])
	get_tree().quit(0 if result_ready else 1)
