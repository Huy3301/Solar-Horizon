extends Node
## Manages recipes, refinery processing, tech upgrades, and character/ship stats.

signal item_crafted(recipe: RecipeDef, products: Dictionary)
signal craft_failed(recipe_id: StringName, reason: String)
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
		var loaded_paths: Dictionary = {}
		while not file_name.is_empty():
			if not dir.current_is_dir():
				var clean_name: String = file_name
				while clean_name.ends_with(".remap") or clean_name.ends_with(".import"):
					if clean_name.ends_with(".remap"):
						clean_name = clean_name.trim_suffix(".remap")
					elif clean_name.ends_with(".import"):
						clean_name = clean_name.trim_suffix(".import")

				if clean_name.ends_with(".tres") or clean_name.ends_with(".res"):
					var full_path: String = dir_path + clean_name
					if not loaded_paths.has(full_path):
						loaded_paths[full_path] = true
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
func can_craft(recipe_or_id: Variant, inventory: InventorySystem) -> bool:
	var recipe: RecipeDef = null
	if recipe_or_id is RecipeDef:
		recipe = recipe_or_id
	elif recipe_or_id is StringName or recipe_or_id is String:
		recipe = get_recipe(String(recipe_or_id))
	elif recipe_or_id != null and "id" in recipe_or_id:
		recipe = recipe_or_id

	if recipe == null or inventory == null:
		return false

	# If it's an upgrade, check tier progression
	if recipe.is_upgrade:
		var current_tier: int = get_upgrade_tier(recipe.upgrade_id)
		if recipe.upgrade_tier != current_tier + 1:
			# Must unlock tier sequentially
			return false

	# Check required ingredients in inventory
	if "ingredients" in recipe and recipe.ingredients != null:
		for item_key in recipe.ingredients:
			var required_amount: int = int(recipe.ingredients[item_key])
			if inventory.get_amount(str(item_key)) < required_amount:
				return false

	return true

## Executes crafting or upgrade unlocking, consuming ingredients
func craft(recipe_or_id: Variant, inventory: InventorySystem) -> bool:
	if recipe_or_id == null or inventory == null:
		return false

	var recipe: RecipeDef = null
	var recipe_id: StringName = &""
	if recipe_or_id is RecipeDef:
		recipe = recipe_or_id
		recipe_id = recipe.id
	elif recipe_or_id is StringName or recipe_or_id is String:
		recipe_id = StringName(recipe_or_id)
		recipe = get_recipe(String(recipe_id))
	elif "id" in recipe_or_id:
		recipe = recipe_or_id
		recipe_id = StringName(recipe_or_id.id)
	else:
		return false

	if recipe == null:
		craft_failed.emit(recipe_id, "Recipe not found")
		return false

	if not can_craft(recipe, inventory):
		craft_failed.emit(recipe_id, "Missing ingredients")
		return false

	# Verify output items fit in inventory before consuming ingredients
	var output_items: Array = []
	if "output_item_id" in recipe and recipe.get("output_item_id") != null and not str(recipe.get("output_item_id")).is_empty():
		var amt: int = 1
		var amt_prop = recipe.get("output_amount")
		if amt_prop != null:
			amt = int(amt_prop)
		output_items.append({"item_id": recipe.get("output_item_id"), "amount": amt})
	elif "products" in recipe and recipe.get("products") is Dictionary and not recipe.products.is_empty():
		for prod_key in recipe.products:
			output_items.append({"item_id": prod_key, "amount": int(recipe.products[prod_key])})

	if not output_items.is_empty() and not inventory.can_fit_items(output_items):
		craft_failed.emit(recipe_id, "Inventory full")
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
		if not recipe.products.is_empty():
			for prod_key in recipe.products:
				var prod_amount: int = int(recipe.products[prod_key])
				inventory.add_item(str(prod_key), prod_amount)
		elif "output_item_id" in recipe and not str(recipe.get("output_item_id")).is_empty():
			var out_id: String = str(recipe.get("output_item_id"))
			var out_amt: int = 1
			var amt_prop = recipe.get("output_amount")
			if amt_prop != null:
				out_amt = int(amt_prop)
			inventory.add_item(out_id, out_amt)

		var emitted_products: Dictionary = recipe.products if ("products" in recipe and not recipe.products.is_empty()) else {}
		if emitted_products.is_empty() and "output_item_id" in recipe and not str(recipe.get("output_item_id")).is_empty():
			var out_amt: int = 1
			var amt_prop = recipe.get("output_amount")
			if amt_prop != null:
				out_amt = int(amt_prop)
			emitted_products = {str(recipe.get("output_item_id")): out_amt}
		item_crafted.emit(recipe, emitted_products)

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
