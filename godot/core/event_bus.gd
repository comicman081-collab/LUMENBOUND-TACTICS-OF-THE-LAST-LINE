extends Node

signal screen_changed(screen_id: String)
signal save_completed(success: bool, message: String)
signal battle_event_emitted(event: Dictionary)
signal inventory_changed()
signal settings_changed()

