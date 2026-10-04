extends Node
# This file is an Autoload script for save management.

## Handles persistent data saving and loading.

const SAVE_PATH: String = "user://save_data.json"
const SAVE_VERSION: int = 1

func save_game(player_state: Dictionary, terrain_deltas: Dictionary) -> void:
	var save_data := {
		"version": SAVE_VERSION,
		"player": player_state,
		"terrain": terrain_deltas
	}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
	else:
		printerr("Failed to open save file for writing.")

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
		
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		file.close()
		var json := JSON.new()
		var error := json.parse(content)
		if error == OK:
			var data: Dictionary = json.data
			if data.has("version") and data["version"] == SAVE_VERSION:
				return data
			else:
				printerr("Save version mismatch or missing version.")
				return {}
		else:
			printerr("JSON Parse Error: ", json.get_error_message())
			return {}
	else:
		printerr("Failed to open save file for reading.")
		return {}
