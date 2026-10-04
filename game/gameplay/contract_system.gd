extends Node

## Generates and tracks procedural "Survey Missions" and credits.
## Meant to be used as an Autoload.

signal contract_generated(contract: Dictionary)
signal contract_completed(contract_id: String)
signal credits_earned(amount: int)

var active_contracts: Array[Dictionary] = []
var credits: int = 0

## Generate a new procedural survey mission
func generate_contract(id: String, target_planet: String, target_type: String, count: int, reward: int) -> void:
	var contract := {
		"id": id,
		"planet": target_planet,
		"type": target_type,
		"target_count": count,
		"current_count": 0,
		"reward": reward,
		"completed": false
	}
	active_contracts.append(contract)
	contract_generated.emit(contract)

## Call this when the player scans something to update progress
func register_scan(planet: String, scan_type: String) -> void:
	for contract in active_contracts:
		if not contract["completed"] and (contract["planet"] == planet or contract["planet"] == "") and (contract["type"] == scan_type or contract["type"] == ""):
			contract["current_count"] += 1
			if contract["current_count"] >= contract["target_count"]:
				contract["completed"] = true
				credits += int(contract["reward"])
				credits_earned.emit(contract["reward"])
				contract_completed.emit(contract["id"])

## Returns non-completed contracts
func get_active_contracts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contract in active_contracts:
		if not contract["completed"]:
			result.append(contract)
	return result

## Save data serialization
func get_state() -> Dictionary:
	return {
		"active_contracts": active_contracts,
		"credits": credits
	}

## Save data deserialization
func load_state(state: Dictionary) -> void:
	if state.has("active_contracts"):
		active_contracts.clear()
		for c in state["active_contracts"]:
			active_contracts.append(c as Dictionary)
	if state.has("credits"):
		credits = state["credits"]
