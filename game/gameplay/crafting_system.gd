extends Node
## Manages recipes and crafting logic.

signal item_crafted(recipe_data: Resource, amount: int)

## Dictionary of recipe Resource -> Dictionary with 'ingredients' and 'products'
var recipes: Dictionary = {}

## Loads recipes from data/recipes/
func _ready() -> void:
	# DEFERRED(phase4): load and parse recipe resources from data/recipes/
	pass

## Expects an InventorySystem reference to consume ingredients and add products
func craft(recipe_data: Resource, inventory: InventorySystem) -> bool:
	if not recipes.has(recipe_data):
		return false
		
	var recipe: Dictionary = recipes[recipe_data]
	var ingredients: Dictionary = recipe.get("ingredients", {})
	
	# Check if we have enough
	for item_data in ingredients:
		if inventory.get_amount(item_data) < ingredients[item_data]:
			return false
			
	# Consume ingredients
	for item_data in ingredients:
		inventory.remove_item(item_data, ingredients[item_data])
		
	# Add products
	var products: Dictionary = recipe.get("products", {})
	for item_data in products:
		inventory.add_item(item_data, products[item_data])
		
	item_crafted.emit(recipe_data, 1)
	return true
