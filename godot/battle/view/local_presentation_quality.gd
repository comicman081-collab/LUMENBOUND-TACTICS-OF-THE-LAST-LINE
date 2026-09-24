extends RefCounted

static func allows_hd() -> bool:
	if OS.has_feature("lanternline_reviewed_hd"):
		return true
	if OS.is_debug_build() or OS.has_feature("lanternline_dev_tools"):
		return true
	if not OS.has_feature("lanternline_local_hd"):
		return false
	# The local player has HD art without exposing developer tools or QA saves.
	if not OS.has_feature("web"):
		return true
	return str(JavaScriptBridge.eval("['localhost','127.0.0.1','[::1]'].includes(location.hostname) ? '1' : '0'", true)) == "1"
