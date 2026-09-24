extends SceneTree

func _initialize() -> void:
	for property in ProjectSettings.get_property_list():
		var key := str(property.name)
		if key.begins_with("rendering/") and (key.contains("shader") or key.contains("opengl") or key.contains("compatibility") or key.contains("light") or key.contains("thread") or key.contains("pipeline")):
			print("RENDER_SETTING ", key, "=", ProjectSettings.get_setting(key))
	for method in ClassDB.class_get_method_list("RenderingServer"):
		if "shader" in str(method.name) or "pipeline" in str(method.name): print("RENDER_METHOD ", method)
	quit()
