extends RefCounted

## Godot's IndexedDB filesystem flush is asynchronous. Keep a synchronous,
## checksummed recovery journal before reporting a browser save as complete.
## The existing user:// path scopes production and every QA sandbox separately.
const SCRIPT := """
(() => {
  window.__lumenboundSaveJournal = (action, key, encoded) => {
    try {
      const raw = localStorage.getItem(key);
      let previous = {};
      try { previous = JSON.parse(raw || '{}'); } catch (_) {}
      if (!previous || previous.version !== 1) previous = {};
      if (action === 'read') return typeof previous.current === 'string' ? previous.current : '';
      if (action === 'backup') return typeof previous.backup === 'string' ? previous.backup : '';
      if (action === 'clear') { localStorage.removeItem(key); return 'ok'; }
      if (action !== 'write') return 'invalid action';
      // One setItem atomically commits both generations. A rejected quota or
      // storage operation leaves the previous journal intact.
      localStorage.setItem(key, JSON.stringify({version: 1, current: encoded,
        backup: typeof previous.current === 'string' ? previous.current : ''}));
      return 'ok';
    } catch (error) {
      return action === 'read' || action === 'backup' ? '' : String(error.name || 'StorageError');
    }
  };
})();
"""

static func call_journal(action: String, save_path: String, encoded := "") -> String:
	if not OS.has_feature("web"):
		return "" if action in ["read", "backup"] else "ok"
	JavaScriptBridge.eval(SCRIPT, true)
	var project_name := str(ProjectSettings.get_setting("application/config/name", "LANTERNLINE"))
	var key := "lumenbound-save-journal:" + project_name + ":" + save_path
	var args := JSON.stringify([action, key, encoded])
	return str(JavaScriptBridge.eval("window.__lumenboundSaveJournal.apply(null, " + args + ")", true))
