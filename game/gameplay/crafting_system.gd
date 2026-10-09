extends Node
## Manages recipes, refinery processing, tech upgrades, and character/ship stats.

signal item_crafted(recipe: RecipeDef, products: Dictionary)
signal upgrade_unlocked(upgrade_id: String, tier: int, stat_modifiers: Dictionary)
signal stats_changed(new_stats: Dictionary)

## Dictionary of String recipe_id -> RecipeDef
var recipes: Dictionary = {}

## Dictionary of String upgrade_id -> int current_tier
var unlocked_upgrades: Dictionary = {}

## Dynamic player / ship stats dictionary modified by upgrade tiers
var stats: Dictionary = {
	"max_life_support": 100.0,
	"ship_max_fuel": 1000.0,
	"mining_speed": 1.0,
}

func _ready() -> void:
	load_all_recipes()

## Scans game/data/recipes/ and registers all RecipeDef resources
func load_all_recipes() -> void:
	recipes.clear()
	var dir_path: String = "res://game/data/recipes/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var full_path: String = dir_path + file_name
				var res: Resource = load(full_path)
				if res is RecipeDef:
					register_recipe(res)
			file_name = dir.get_next()

func register_recipe(recipe: RecipeDef) -> void:
	if recipe != null and not recipe.id.is_empty():
		recipes[String(recipe.id)] = recipe

func get_recipe(recipe_id: String) -> RecipeDef:
	return recipes.get(recipe_id, null)

func get_all_recipes() -> Array[RecipeDef]:
	var list: Array[RecipeDef] = []
	for k in recipes:
		list.append(recipes[k])
	return list

func get_recipes_by_category(category: String) -> Array[RecipeDef]:
	var list: Array[RecipeDef] = []
	for k in recipes:
		var r: RecipeDef = recipes[k]
		if r.category == category:
			list.append(r)
	return list

func get_upgrade_tier(upgrade_id: String) -> int:
	return unlocked_upgrades.get(upgrade_id, 0)

func get_stat(stat_name: String, default_val: float = 1.0) -> float:
	return stats.get(stat_name, default_val)

## Checks whether a recipe can be crafted or an upgrade can be unlocked
func can_craft(recipe: RecipeDef, inventory: InventorySystem) -> bool:
	if recipe == null or inventory == null:
		return false

	# If it's an upgrade, check tier progression
	if recipe.is_upgrade:
		var current_tier: int = get_upgrade_tier(recipe.upgrade_id)
		if recipe.upgrade_tier != current_tier + 1:
			# Must unlock tier sequentially
			return false

	# Check required ingredients in inventory
	for item_key in recipe.ingredients:
		var required_amount: int = int(recipe.ingredients[item_key])
		if inventory.get_amount(str(item_key)) < required_amount:
			return false

	return true

## Executes crafting or upgrade unlocking, consuming ingredients
func craft(recipe: RecipeDef, inventory: InventorySystem) -> bool:
	if not can_craft(recipe, inventory):
		return false

	# Consume ingredients
	for item_key in recipe.ingredients:
		var required_amount: int = int(recipe.ingredients[item_key])
		inventory.remove_item(str(item_key), required_amount)

	# Handle upgrades vs standard items
	if recipe.is_upgrade:
		unlocked_upgrades[recipe.upgrade_id] = recipe.upgrade_tier
		for stat_key in recipe.stat_modifiers:
			stats[stat_key] = float(recipe.stat_modifiers[stat_key])
		upgrade_unlocked.emit(recipe.upgrade_id, recipe.upgrade_tier, recipe.stat_modifiers)
		stats_changed.emit(stats)
	else:
		for prod_key in recipe.products:
			var prod_amount: int = int(recipe.products[prod_key])
			inventory.add_item(str(prod_key), prod_amount)
		item_crafted.emit(recipe, recipe.products)

	return true

func to_dict() -> Dictionary:
	return {
		"unlocked_upgrades": unlocked_upgrades.duplicate(),
		"stats": stats.duplicate(),
	}

func from_dict(data: Dictionary) -> void:
	unlocked_upgrades.clear()
	var up_dict: Dictionary = data.get("unlocked_upgrades", {})
	for k in up_dict:
		unlocked_upgrades[str(k)] = int(up_dict[k])

	var st_dict: Dictionary = data.get("stats", {})
	for k in st_dict:
		stats[str(k)] = float(st_dict[k])

	stats_changed.emit(stats)
