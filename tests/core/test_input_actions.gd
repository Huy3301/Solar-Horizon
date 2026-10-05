class_name TestInputActions
extends TestCase

## SH-23 & SH-24 Verification: Input Action and Autoload Audit
## Scans GDScript codebase for action queries and validates InputMap completeness.

func test_autoload_audio_manager_configured() -> void:
	var setting = ProjectSettings.get_setting("autoload/AudioManager")
	assert_true(setting != null and str(setting) != "", "AudioManager registered in autoload")
	if setting != null:
		assert_true(str(setting).contains("game/audio/audio_manager.gd"), "AudioManager points to game/audio/audio_manager.gd")

func test_required_flight_actions_defined() -> void:
	var required = ["boost", "pulse_drive", "space_cruise"]
	for action in required:
		assert_true(InputMap.has_action(action), "InputMap contains required action '%s'" % action)
		var events = InputMap.action_get_events(action)
		assert_true(events.size() > 0, "Action '%s' has at least one event mapped" % action)

func test_all_script_input_actions_exist_in_input_map() -> void:
	var script_paths: Array[String] = []
	_scan_directory("res://scripts", script_paths)
	_scan_directory("res://game", script_paths)
	
	var regex_action = RegEx.new()
	regex_action.compile("(?:Input|event)\\.(?:is_action_\\w+|get_action_strength)\\(\\s*[\"']([a-zA-Z0-9_]+)[\"']\\s*\\)")
	
	var regex_axis = RegEx.new()
	regex_axis.compile("Input\\.get_axis\\(\\s*[\"']([a-zA-Z0-9_]+)[\"']\\s*,\\s*[\"']([a-zA-Z0-9_]+)[\"']\\s*\\)")
	
	var discovered_actions: Dictionary = {}
	
	for path in script_paths:
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var content = file.get_as_text()
		file.close()
		
		for m in regex_action.search_all(content):
			var act = m.get_string(1)
			if not act.is_empty():
				discovered_actions[act] = path
				
		for m in regex_axis.search_all(content):
			var a1 = m.get_string(1)
			var a2 = m.get_string(2)
			if not a1.is_empty():
				discovered_actions[a1] = path
			if not a2.is_empty():
				discovered_actions[a2] = path
				
	assert_true(discovered_actions.size() > 0, "Discovered at least one input action in scripts")
	
	var missing: Array[String] = []
	for action in discovered_actions.keys():
		if not InputMap.has_action(action):
			missing.append("%s (found in %s)" % [action, discovered_actions[action]])
			
	assert_true(missing.is_empty(), "All actions used in scripts exist in InputMap. Missing: %s" % [", ".join(missing)])

func _scan_directory(dir_path: String, out_paths: Array[String]) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_scan_directory(dir_path + "/" + file_name, out_paths)
		else:
			if file_name.ends_with(".gd"):
				out_paths.append(dir_path + "/" + file_name)
		file_name = dir.get_next()
