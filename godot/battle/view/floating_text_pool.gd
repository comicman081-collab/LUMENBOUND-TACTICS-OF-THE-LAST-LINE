class_name FloatingTextPool
extends Node

var pool: Array[Label] = []
func acquire() -> Label:
	var label: Label = pool.pop_back() if not pool.is_empty() else Label.new()
	label.visible = true
	return label
func release(label: Label) -> void:
	label.visible = false
	pool.append(label)
