class_name RecipeDef extends Resource
## Defines a crafting, refinery, or upgrade recipe with ingredients and products.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var category: String = "crafting" # "crafting", "refiner", "upgrade"

## Dictionary of String item_id -> int required count
@export var ingredients: Dictionary = {}

## Dictionary of String item_id -> int produced count
@export var products: Dictionary = {}

## Upgrade metadata
@export var is_upgrade: bool = false
@export var upgrade_id: String = "" # e.g. "suit_o2_tank", "ship_fuel_tank", "mining_speed"
@export var upgrade_tier: int = 1 # 1, 2, 3
@export var stat_modifiers: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"category": category,
		"ingredients": ingredients.duplicate(),
		"products": products.duplicate(),
		"is_upgrade": is_upgrade,
		"upgrade_id": upgrade_id,
		"upgrade_tier": upgrade_tier,
		"stat_modifiers": stat_modifiers.duplicate(),
	}
