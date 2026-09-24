extends SceneTree
func _initialize() -> void:
	var request := HTTPRequest.new()
	for property in request.get_property_list():
		if str(property.name) in ["download_chunk_size", "use_threads", "body_size_limit", "timeout"]:
			print("HTTP_DEFAULT ", property.name, "=", request.get(property.name))
	request.free()
	quit()
