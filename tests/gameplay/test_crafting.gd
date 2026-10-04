class_name TestCrafting extends TestCase

var crafting_script = preload("res://game/gameplay/crafting_system.gd")

func test_recipes_count() -> void:
	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	var all_recipes: Array[RecipeDef] = crafter.get_all_recipes()
	assert_true(all_recipes.size() >= 12, "Should have at least 12 recipes (found %d)" % all_recipes.size())
	crafter.free()

func test_refiner_ore_to_plate() -> void:
	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_mass = 500.0

	var recipe := crafter.get_recipe("refine_iron_plate")
	assert_true(recipe != null, "Recipe refine_iron_plate found")

	# Add ingredients: 2 iron_ore, 1 carbon
	inv.add_item("iron_ore", 2)
	inv.add_item("carbon", 1)

	assert_true(crafter.can_craft(recipe, inv), "Can craft when ingredients present")
	var success := crafter.craft(recipe, inv)
	assert_true(success, "Crafting succeeds")

	assert_eq(inv.get_amount("iron_ore"), 0, "Iron ore consumed")
	assert_eq(inv.get_amount("carbon"), 0, "Carbon consumed")
	assert_eq(inv.get_amount("steel_plate"), 1, "1 steel plate produced")

	inv.free()
	crafter.free()

func test_insufficient_ingredients_fails() -> void:
	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()

	var recipe := crafter.get_recipe("craft_oxygen_canister")
	assert_true(recipe != null, "Recipe found")

	inv.add_item("ice", 1) # Needs 2 ice and 1 steel_plate
	assert_false(crafter.can_craft(recipe, inv), "Cannot craft with missing ingredients")
	assert_false(crafter.craft(recipe, inv), "Craft call fails")

	inv.free()
	crafter.free()

func test_upgrade_suit_o2_three_tiers() -> void:
	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_mass = 1000.0

	var t1 := crafter.get_recipe("upgrade_suit_o2_t1")
	var t2 := crafter.get_recipe("upgrade_suit_o2_t2")
	var t3 := crafter.get_recipe("upgrade_suit_o2_t3")

	# Try crafting t2 directly -> should fail because t1 not unlocked
	inv.add_item("oxygen_canister", 10)
	inv.add_item("steel_plate", 10)
	inv.add_item("circuit", 10)
	inv.add_item("he3", 10)

	assert_false(crafter.can_craft(t2, inv), "Cannot skip to tier 2 without tier 1")

	# Craft Tier 1
	assert_true(crafter.craft(t1, inv), "Tier 1 crafted")
	assert_eq(crafter.get_upgrade_tier("suit_o2_tank"), 1, "Tier 1 recorded")
	assert_almost_eq(crafter.get_stat("max_life_support"), 125.0, 0.01, "Life support stat increased to 125")

	# Craft Tier 2
	assert_true(crafter.craft(t2, inv), "Tier 2 crafted")
	assert_eq(crafter.get_upgrade_tier("suit_o2_tank"), 2, "Tier 2 recorded")
	assert_almost_eq(crafter.get_stat("max_life_support"), 150.0, 0.01, "Life support stat increased to 150")

	# Craft Tier 3
	assert_true(crafter.craft(t3, inv), "Tier 3 crafted")
	assert_eq(crafter.get_upgrade_tier("suit_o2_tank"), 3, "Tier 3 recorded")
	assert_almost_eq(crafter.get_stat("max_life_support"), 200.0, 0.01, "Life support stat increased to 200")

	inv.free()
	crafter.free()

func test_upgrade_ship_fuel_three_tiers() -> void:
	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_mass = 2000.0

	inv.add_item("steel_plate", 20)
	inv.add_item("fuel_cell", 20)
	inv.add_item("circuit", 10)
	inv.add_item("he3", 10)

	var t1 := crafter.get_recipe("upgrade_ship_fuel_t1")
	var t2 := crafter.get_recipe("upgrade_ship_fuel_t2")
	var t3 := crafter.get_recipe("upgrade_ship_fuel_t3")

	assert_true(crafter.craft(t1, inv), "Ship fuel T1 crafted")
	assert_almost_eq(crafter.get_stat("ship_max_fuel"), 1250.0, 0.01)

	assert_true(crafter.craft(t2, inv), "Ship fuel T2 crafted")
	assert_almost_eq(crafter.get_stat("ship_max_fuel"), 1500.0, 0.01)

	assert_true(crafter.craft(t3, inv), "Ship fuel T3 crafted")
	assert_almost_eq(crafter.get_stat("ship_max_fuel"), 2000.0, 0.01)

	inv.free()
	crafter.free()

func test_upgrade_mining_speed_three_tiers() -> void:
	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_mass = 1000.0

	inv.add_item("steel_plate", 10)
	inv.add_item("circuit", 10)
	inv.add_item("he3", 5)

	var t1 := crafter.get_recipe("upgrade_mining_speed_t1")
	var t2 := crafter.get_recipe("upgrade_mining_speed_t2")
	var t3 := crafter.get_recipe("upgrade_mining_speed_t3")

	assert_true(crafter.craft(t1, inv), "Mining speed T1 crafted")
	assert_almost_eq(crafter.get_stat("mining_speed"), 1.25, 0.01)

	assert_true(crafter.craft(t2, inv), "Mining speed T2 crafted")
	assert_almost_eq(crafter.get_stat("mining_speed"), 1.50, 0.01)

	assert_true(crafter.craft(t3, inv), "Mining speed T3 crafted")
	assert_almost_eq(crafter.get_stat("mining_speed"), 2.00, 0.01)

	inv.free()
	crafter.free()

func test_serialization_roundtrip() -> void:
	var crafter1 = crafting_script.new()
	crafter1.load_all_recipes()
	var inv := InventorySystem.new()
	inv.max_mass = 500.0
	inv.add_item("steel_plate", 5)
	inv.add_item("circuit", 5)

	var t1 := crafter1.get_recipe("upgrade_mining_speed_t1")
	crafter1.craft(t1, inv)

	var data := crafter1.to_dict()

	var crafter2 = crafting_script.new()
	crafter2.from_dict(data)

	assert_eq(crafter2.get_upgrade_tier("mining_speed"), 1, "Restored tier")
	assert_almost_eq(crafter2.get_stat("mining_speed"), 1.25, 0.01, "Restored stat")

	inv.free()
	crafter1.free()
	crafter2.free()
