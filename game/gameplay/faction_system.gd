extends Node
## Tracks player reputation with procedural factions.

## Reputation thresholds
const REP_HOSTILE = -100
const REP_NEUTRAL = 0
const REP_FRIENDLY = 100
const REP_ALLIED = 250

## Dictionary mapping faction_id to reputation score
var factions: Dictionary = {}

func _ready() -> void:
	# Default factions, can be expanded by procedural generation
	register_faction("terran_alliance", "Terran Alliance", 0)
	register_faction("free_traders", "Free Traders", 10)
	register_faction("crimson_syndicate", "Crimson Syndicate", -50)
	register_faction("independent", "Independent", 0)

## Registers a new faction. Used by procedural generation.
func register_faction(faction_id: String, faction_name: String, initial_reputation: int = 0) -> void:
	if not factions.has(faction_id):
		factions[faction_id] = {
			"name": faction_name,
			"reputation": initial_reputation
		}

## Modifies the reputation of a faction.
func add_reputation(faction_id: String, amount: int) -> void:
	if factions.has(faction_id):
		factions[faction_id]["reputation"] += amount

## Returns the numerical reputation score.
func get_reputation(faction_id: String) -> int:
	if factions.has(faction_id):
		return factions[faction_id]["reputation"]
	return 0

## Returns a descriptive string of the current standing.
func get_standing_name(faction_id: String) -> String:
	var rep = get_reputation(faction_id)
	
	if rep <= REP_HOSTILE:
		return "Hostile"
	elif rep >= REP_ALLIED:
		return "Allied"
	elif rep >= REP_FRIENDLY:
		return "Friendly"
	elif rep < 0:
		return "Unfriendly"
	else:
		return "Neutral"
