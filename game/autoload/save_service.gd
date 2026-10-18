extends Node
## Persistent save and migration management for Solar Horizon (v1 schema).
## Meant to be used as an Autoload (SaveService).

signal save_completed(path: String)
signal load_completed(path: String)

const SAVE_PATH: String = "user://save_data.json"
const CURRENT_VERSION: int = 1

## Serializes a UniversePosition object to a serializable dictionary
func serialize_universe_position(pos: UniversePosition, body_id: String = "Earth") -> Dictionary:
	if pos == null:
		return {
			"sector": [0, 0, 0],
			"offset": [0.0, 0.0, 0.0],
			"body_id": body_id,
		}
	return {
		"sector": [pos.sector.x, pos.sector.y, pos.sector.z],
		"offset": [pos.offset.x, pos.offset.y, pos.offset.z],
		"body_id": body_id,
	}

## Deserializes a dictionary back into a UniversePosition instance
func deserialize_universe_position(data: Dictionary) -> UniversePosition:
	var sec := Vector3i.ZERO
	if data.has("sector") and data["sector"] is Array and data["sector"].size() >= 3:
		sec = Vector3i(int(data["sector"][0]), int(data["sector"][1]), int(data["sector"][2]))

	var off := DVec3.zero()
	if data.has("offset") and data["offset"] is Array and data["offset"].size() >= 3:
		off = DVec3.new(float(data["offset"][0]), float(data["offset"][1]), float(data["offset"][2]))

	return UniversePosition.new(sec, off)

## Migrates data from older versions (v0 / legacy unstructured) into v1 schema
func migrate_data(raw_data: Dictionary) -> Dictionary:
	var v: int = int(raw_data.get("version", 0))
	if v >= CURRENT_VERSION:
		return raw_data.duplicate(true)

	# Build v1 standardized schema
	var v1_data: Dictionary = {}
	v1_data["version"] = CURRENT_VERSION
	v1_data["timestamp"] = int(raw_data.get("timestamp", Time.get_unix_time_from_system()))

	# Legacy player sub-dict if present
	var legacy_player: Dictionary = raw_data.get("player", {})

	# 1. Inventory
	if raw_data.has("inventory") and raw_data["inventory"] is Dictionary:
		v1_data["inventory"] = _normalize_legacy_inventory(raw_data["inventory"])
	elif legacy_player.has("inventory") and legacy_player["inventory"] is Dictionary:
		v1_data["inventory"] = _normalize_legacy_inventory(legacy_player["inventory"])
	else:
		v1_data["inventory"] = {
			"items": {},
			"max_slots": 20,
			"max_mass": 250.0,
		}

	# 2. Discoveries
	if raw_data.has("discoveries") and raw_data["discoveries"] is Dictionary:
		v1_data["discoveries"] = raw_data["discoveries"].duplicate(true)
	elif legacy_player.has("discoveries") and legacy_player["discoveries"] is Dictionary:
		v1_data["discoveries"] = legacy_player["discoveries"].duplicate(true)
	else:
		v1_data["discoveries"] = {}

	# 3. Unlocked Upgrades & Crafting Stats
	if raw_data.has("unlocked_upgrades") and raw_data["unlocked_upgrades"] is Dictionary:
		v1_data["unlocked_upgrades"] = raw_data["unlocked_upgrades"].duplicate(true)
	elif legacy_player.has("upgrades") and legacy_player["upgrades"] is Dictionary:
		v1_data["unlocked_upgrades"] = legacy_player["upgrades"].duplicate(true)
	else:
		v1_data["unlocked_upgrades"] = {}

	v1_data["crafting_stats"] = raw_data.get("crafting_stats", {
		"max_life_support": 100.0,
		"ship_max_fuel": 1000.0,
		"mining_speed": 1.0,
	})

	# 4. Credits
	if raw_data.has("credits"):
		v1_data["credits"] = int(raw_data["credits"])
	elif legacy_player.has("credits"):
		v1_data["credits"] = int(legacy_player["credits"])
	else:
		v1_data["credits"] = 0

	# 5. Ship state dict
	if raw_data.has("ship_state") and raw_data["ship_state"] is Dictionary:
		v1_data["ship_state"] = raw_data["ship_state"].duplicate(true)
	elif legacy_player.has("ship_state") and legacy_player["ship_state"] is Dictionary:
		v1_data["ship_state"] = legacy_player["ship_state"].duplicate(true)
	else:
		v1_data["ship_state"] = {
			"hull": 1000.0,
			"max_hull": 1000.0,
			"shields": 1000.0,
			"fuel": 1000.0,
			"max_fuel": 1000.0,
			"landed": false,
		}

	# 6. Player position (UniversePosition format)
	if raw_data.has("player_position") and raw_data["player_position"] is Dictionary:
		v1_data["player_position"] = raw_data["player_position"].duplicate(true)
	elif legacy_player.has("position") and legacy_player["position"] is Dictionary:
		v1_data["player_position"] = legacy_player["position"].duplicate(true)
	else:
		v1_data["player_position"] = {
			"sector": [0, 0, 0],
			"offset": [0.0, 0.0, 0.0],
			"body_id": "Earth",
		}

	# 7. Survival state
	v1_data["survival_state"] = raw_data.get("survival_state", {
		"life_support": 100.0,
		"hazard_protection": 100.0,
		"current_body_id": "Earth",
	})

	# 8. Terrain deltas
	v1_data["terrain"] = raw_data.get("terrain", {})

	return v1_data

func _normalize_legacy_inventory(inventory_data: Dictionary) -> Dictionary:
	if inventory_data.has("items") and inventory_data["items"] is Dictionary:
		return inventory_data.duplicate(true)
	var items: Dictionary = inventory_data.duplicate(true)
	var max_slots: int = 20
	var max_mass: float = 250.0
	if items.has("max_slots"):
		max_slots = int(items["max_slots"])
		items.erase("max_slots")
	if items.has("max_mass"):
		max_mass = float(items["max_mass"])
		items.erase("max_mass")
	return {
		"items": items,
		"max_slots": max_slots,
		"max_mass": max_mass,
	}

## Saves full game profile dictionary to user:// JSON
func save_profile(data: Dictionary, path: String = SAVE_PATH) -> bool:
	var save_data: Dictionary = data.duplicate(true)
	save_data["version"] = CURRENT_VERSION
	save_data["timestamp"] = int(Time.get_unix_time_from_system())
	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		printerr("Failed to open temporary save file for writing: ", temp_path)
		return false

	var json_text := JSON.stringify(save_data, "\t")
	file.store_string(json_text)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		printerr("Failed to write temporary save file: ", temp_path, " (", error_string(write_error), ")")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false

	var absolute_path: String = ProjectSettings.globalize_path(path)
	var absolute_temp_path: String = ProjectSettings.globalize_path(temp_path)
	var absolute_backup_path: String = ProjectSettings.globalize_path(backup_path)
	var had_previous_save: bool = FileAccess.file_exists(path)
	if had_previous_save:
		if FileAccess.file_exists(backup_path):
			var remove_error: Error = DirAccess.remove_absolute(absolute_backup_path)
			if remove_error != OK:
				printerr("Failed to remove previous save backup: ", backup_path, " (", error_string(remove_error), ")")
				DirAccess.remove_absolute(absolute_temp_path)
				return false
		var backup_error: Error = DirAccess.rename_absolute(absolute_path, absolute_backup_path)
		if backup_error != OK:
			printerr("Failed to preserve existing save before replacement: ", path, " (", error_string(backup_error), ")")
			DirAccess.remove_absolute(absolute_temp_path)
			return false

	var replace_error: Error = DirAccess.rename_absolute(absolute_temp_path, absolute_path)
	if replace_error != OK:
		printerr("Failed to replace save file: ", path, " (", error_string(replace_error), ")")
		if FileAccess.file_exists(temp_path):
			var temp_cleanup_error: Error = DirAccess.remove_absolute(absolute_temp_path)
			if temp_cleanup_error != OK:
				printerr("Failed to remove temporary save after replacement failure: ", temp_path, " (", error_string(temp_cleanup_error), ")")
		if had_previous_save:
			var restore_error: Error = DirAccess.rename_absolute(absolute_backup_path, absolute_path)
			if restore_error != OK:
				printerr("Failed to restore previous save from backup: ", backup_path, " (", error_string(restore_error), ")")
		return false

	if had_previous_save:
		var cleanup_error: Error = DirAccess.remove_absolute(absolute_backup_path)
		if cleanup_error != OK:
			printerr("Saved profile but failed to remove backup: ", backup_path, " (", error_string(cleanup_error), ")")
	save_completed.emit(path)
	return true

## Loads and migrates save profile from user:// JSON
func load_profile(path: String = SAVE_PATH) -> Dictionary:
	var backup_path: String = path + ".bak"
	if not FileAccess.file_exists(path) and FileAccess.file_exists(backup_path):
		var restore_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(path)
		)
		if restore_error != OK:
			printerr("Failed to restore save from backup: ", backup_path, " (", error_string(restore_error), ")")
			return {}
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("Failed to open save file for reading: ", path)
		return {}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(content)
	if error != OK:
		printerr("SaveService JSON Parse Error: ", json.get_error_message())
		return {}

	var parsed = json.data
	if not (parsed is Dictionary):
		return {}

	var data: Dictionary = parsed
	if not data.has("version") or int(data["version"]) < CURRENT_VERSION:
		data = migrate_data(data)

	load_completed.emit(path)
	return data

## Convenience method to save all active gameplay systems at once
func save_systems_state(
	inventory: InventorySystem,
	crafting: Node,
	discovery: Node,
	survival: SurvivalSystem,
	ship_state: Dictionary,
	player_pos: UniversePosition,
	body_id: String = "Earth",
	path: String = SAVE_PATH
) -> bool:
	var profile: Dictionary = {
		"version": CURRENT_VERSION,
		"inventory": inventory.to_dict() if inventory != null else {},
		"unlocked_upgrades": crafting.get("unlocked_upgrades") if crafting != null else {},
		"crafting_stats": crafting.get("stats") if crafting != null else {},
		"credits": discovery.get("credits") if discovery != null else 0,
		"discoveries": discovery.get("discoveries") if discovery != null else {},
		"survival_state": survival.to_dict() if survival != null else {},
		"ship_state": ship_state.duplicate(),
		"player_position": serialize_universe_position(player_pos, body_id),
		"terrain": {},
	}
	return save_profile(profile, path)

## Legacy compatibility interface
func save_game(player_state: Dictionary, terrain_deltas: Dictionary, path: String = SAVE_PATH) -> void:
	var save_data := {
		"version": CURRENT_VERSION,
		"player": player_state,
		"terrain": terrain_deltas,
	}
	save_profile(save_data, path)

func load_game(path: String = SAVE_PATH) -> Dictionary:
	return load_profile(path)
