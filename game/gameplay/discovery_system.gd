extends Node
## Manages player discoveries of minerals, flora, fauna, and anomalies, and credits rewards.
## Meant to be used as an Autoload (DiscoverySystem).

signal discovery_added(discovery: Dictionary)
signal discovery_uploaded(id: String, reward: int)
signal discovery_renamed(id: String, new_name: String)
signal credits_changed(new_credits: int)

const REWARD_TABLE: Dictionary = {
	"mineral": 100,
	"flora": 250,
	"fauna": 500,
	"anomaly": 1000,
}

var credits: int = 0
## Dictionary mapping String discovery_id -> Dictionary entry
var discoveries: Dictionary = {}

func get_reward_for_category(category: String) -> int:
	return int(REWARD_TABLE.get(category.to_lower(), 100))

## Registers a new scan result into the scientific catalogue
func register_discovery(
	id: String,
	category: String,
	default_name: String,
	planet_id: String,
	details: Dictionary = {}
) -> Dictionary:
	if not discoveries.has(id):
		var cat_clean: String = category.to_lower()
		var d: Dictionary = {
			"id": id,
			"category": cat_clean,
			"name": default_name,
			"planet_id": planet_id,
			"uploaded": false,
			"reward": get_reward_for_category(cat_clean),
			"details": details.duplicate(),
		}
		discoveries[id] = d
		discovery_added.emit(d)
		return d
	return discoveries[id]

## Rename a discovery before or after uploading
func rename_discovery(id: String, new_name: String) -> void:
	if discoveries.has(id):
		discoveries[id]["name"] = new_name
		discovery_renamed.emit(id, new_name)

## Upload a discovery to earn credits (returns credits awarded)
func upload_discovery(id: String) -> int:
	if discoveries.has(id) and not discoveries[id].get("uploaded", false):
		discoveries[id]["uploaded"] = true
		var reward: int = int(discoveries[id].get("reward", 100))
		credits += reward
		discovery_uploaded.emit(id, reward)
		credits_changed.emit(credits)
		return reward
	return 0

## Uploads all pending un-uploaded discoveries and returns total credits earned
func upload_all_pending() -> int:
	var total_earned: int = 0
	for id in discoveries:
		if not discoveries[id].get("uploaded", false):
			discoveries[id]["uploaded"] = true
			var r: int = int(discoveries[id].get("reward", 100))
			total_earned += r
			discovery_uploaded.emit(id, r)
	if total_earned > 0:
		credits += total_earned
		credits_changed.emit(credits)
	return total_earned

func add_credits(amount: int) -> void:
	if amount > 0:
		credits += amount
		credits_changed.emit(credits)

func spend_credits(amount: int) -> bool:
	if amount > 0 and credits >= amount:
		credits -= amount
		credits_changed.emit(credits)
		return true
	return false

func get_credits() -> int:
	return credits

func is_discovered(id: String) -> bool:
	return discoveries.has(id)

func is_uploaded(id: String) -> bool:
	return discoveries.has(id) and bool(discoveries[id].get("uploaded", false))

func get_discovery(id: String) -> Dictionary:
	return discoveries.get(id, {})

func get_all_discoveries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in discoveries:
		result.append(discoveries[key])
	return result

func get_discoveries_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var target_cat: String = category.to_lower()
	for key in discoveries:
		var d: Dictionary = discoveries[key]
		if d.get("category", "") == target_cat:
			result.append(d)
	return result

func get_discoveries_by_planet(planet_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in discoveries:
		var d: Dictionary = discoveries[key]
		if d.get("planet_id", "") == planet_id:
			result.append(d)
	return result

## State serialization
func get_state() -> Dictionary:
	return {
		"credits": credits,
		"discoveries": discoveries.duplicate(true),
	}

func load_state(state: Dictionary) -> void:
	if state.has("discoveries"):
		discoveries = state["discoveries"].duplicate(true)
		credits = int(state.get("credits", 0))
	else:
		# Support legacy format where state was raw discoveries dictionary
		discoveries = state.duplicate(true)
		credits = 0
	credits_changed.emit(credits)
