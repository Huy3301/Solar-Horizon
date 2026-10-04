extends Node

## Manages player discoveries of flora, fauna, and planets.
## Meant to be used as an Autoload.

signal discovery_added(discovery: Dictionary)
signal discovery_uploaded(id: String)
signal discovery_renamed(id: String, new_name: String)

var discoveries: Dictionary = {}

## Register a new scan
func register_discovery(id: String, type: String, default_name: String, planet_id: String) -> void:
	if not discoveries.has(id):
		var d := {
			"id": id,
			"type": type,
			"name": default_name,
			"planet_id": planet_id,
			"uploaded": false
		}
		discoveries[id] = d
		discovery_added.emit(d)

## Rename a discovery before uploading
func rename_discovery(id: String, new_name: String) -> void:
	if discoveries.has(id) and not discoveries[id]["uploaded"]:
		discoveries[id]["name"] = new_name
		discovery_renamed.emit(id, new_name)

## Upload a discovery to earn credits (returns true if successful)
func upload_discovery(id: String) -> bool:
	if discoveries.has(id) and not discoveries[id]["uploaded"]:
		discoveries[id]["uploaded"] = true
		discovery_uploaded.emit(id)
		return true
	return false

## Get all discoveries as an array
func get_all_discoveries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in discoveries:
		result.append(discoveries[key])
	return result

## Save data serialization
func get_state() -> Dictionary:
	return discoveries

## Save data deserialization
func load_state(state: Dictionary) -> void:
	discoveries = state
