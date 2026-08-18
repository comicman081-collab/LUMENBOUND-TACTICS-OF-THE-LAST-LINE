class_name GameResult
extends RefCounted

var ok := true
var value = null
var error := ""

static func success(result_value = null) -> GameResult:
	var result := GameResult.new()
	result.value = result_value
	return result

static func failure(message: String) -> GameResult:
	var result := GameResult.new()
	result.ok = false
	result.error = message
	return result

