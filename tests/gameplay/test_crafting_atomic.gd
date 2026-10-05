extends "res://tests/test_case.gd"

const CraftingSystemScript = preload("res://game/gameplay/crafting_system.gd")

func test_can_fit_items_slot_and_mass_limits() -> void:
	var inv := InventorySystem.new()
	inv.max_slots = 2
	inv.max_mass = 10.0

	# 1. Fits within limits
	assert_true(inv.can_fit_items([{"item_id": "iron_ore", "amount": 2}]), "Should fit 2 iron ore within slots and mass")

	# 2. Exceeds mass limit
	assert_false(inv.can_fit_items([{"item_id": "iron_ore", "amount": 10}]), "Should reject items exceeding max mass")

	# 3. Add 2 distinct items filling the 2 available slots
	inv.add_item("iron_ore", 1)
	inv.add_item("carbon", 1)
	assert_eq(inv.get_used_slots(), 2, "Used slots should be 2")

	# 4. Adding existing stackable item fits in same slot
	assert_true(inv.can_fit_items([{"item_id": "iron_ore", "amount": 1}]), "Existing item with spare stack fits in same slot")

	# 5. Adding a third distinct item requires a 3rd slot and must be rejected
	assert_false(inv.can_fit_items([{"item_id": "copper_wire", "amount": 1}]), "Third item exceeds max slots of 2")

	# 6. Verify inventory state was untouched by can_fit_items simulation
	assert_eq(inv.get_amount("iron_ore"), 1, "Simulated check must not mutate inventory amounts")
	assert_eq(inv.get_amount("carbon"), 1, "Simulated check must not mutate inventory amounts")
	assert_eq(inv.get_amount("copper_wire"), 0, "Simulated check must not add items")

	inv.free()

func test_craft_into_full_inventory_fails_atomically() -> void:
	var crafter = CraftingSystemScript.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_slots = 2
	inv.max_mass = 100.0

	var recipe := crafter.get_recipe("refine_iron_plate")
	assert_true(recipe != null, "Recipe refine_iron_plate must exist")

	# Fill both slots with ingredients (iron_ore and carbon)
	inv.add_item("iron_ore", 2)
	inv.add_item("carbon", 1)
	assert_eq(inv.get_used_slots(), 2, "Used slots must equal max_slots")

	# Recipe produces "steel_plate", which is a distinct item needing a new slot.
	# Since max_slots = 2 is already reached by ingredients, can_fit_items must fail.
	var failed_info: Dictionary = {
		"received": false,
		"recipe_id": &"",
		"reason": ""
	}

	crafter.craft_failed.connect(func(r_id: StringName, reason: String) -> void:
		failed_info["received"] = true
		failed_info["recipe_id"] = r_id
		failed_info["reason"] = reason
	)

	# Attempt crafting
	var success: bool = crafter.craft(recipe, inv)

	assert_false(success, "Crafting into full inventory must return false")
	assert_true(failed_info["received"], "craft_failed signal must be emitted")
	assert_eq(failed_info["recipe_id"], recipe.id, "craft_failed emitted correct recipe ID")
	assert_eq(failed_info["reason"], "Inventory full", "craft_failed emitted reason 'Inventory full'")

	# Crucial: verify atomic rollback / no consumption occurred
	assert_eq(inv.get_amount("iron_ore"), 2, "Ingredients must not be consumed when crafting fails")
	assert_eq(inv.get_amount("carbon"), 1, "Ingredients must not be consumed when crafting fails")
	assert_eq(inv.get_amount("steel_plate"), 0, "No product must be added")

	# Now increase max_slots to 3; crafting must succeed
	inv.max_slots = 3
	var success_after_expand: bool = crafter.craft(&"refine_iron_plate", inv)
	assert_true(success_after_expand, "Crafting succeeds once inventory has slot capacity")
	assert_eq(inv.get_amount("iron_ore"), 0, "Ingredients consumed after successful craft")
	assert_eq(inv.get_amount("carbon"), 0, "Ingredients consumed after successful craft")
	assert_eq(inv.get_amount("steel_plate"), 1, "Product created after successful craft")

	inv.free()
	crafter.free()

func test_craft_into_mass_constrained_inventory_fails_atomically() -> void:
	var crafter = CraftingSystemScript.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_slots = 10

	var recipe := crafter.get_recipe("refine_iron_plate")
	assert_true(recipe != null, "Recipe refine_iron_plate must exist")

	inv.add_item("iron_ore", 2)
	inv.add_item("carbon", 1)

	# Constrain max_mass exactly to current mass
	inv.max_mass = inv.get_total_mass()

	var failed_info: Dictionary = {"reason": ""}
	crafter.craft_failed.connect(func(_r: StringName, rsn: String) -> void: failed_info["reason"] = rsn)

	var success: bool = crafter.craft(recipe, inv)
	assert_false(success, "Crafting must fail if output mass exceeds max_mass")
	assert_eq(failed_info["reason"], "Inventory full", "Reason must be 'Inventory full'")
	assert_eq(inv.get_amount("iron_ore"), 2, "Iron ore untouched")
	assert_eq(inv.get_amount("carbon"), 1, "Carbon untouched")

	inv.free()
	crafter.free()
