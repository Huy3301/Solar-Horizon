extends "res://tests/test_case.gd"

const InventoryMenuScript = preload("res://game/ui/components/inventory_menu.gd")
const PauseMenuScript = preload("res://game/ui/components/pause_menu.gd")
const GameUIScript = preload("res://game/ui/game_ui.gd")

func test_inventory_grid_init_and_navigation() -> void:
	var inv_scene = preload("res://game/ui/inventory_menu.tscn")
	var inv_menu = inv_scene.instantiate()
	inv_menu._ready()
	
	assert_eq(inv_menu.slot_buttons.size(), inv_menu.slot_count, "Slot buttons array matches slot count")
	assert_true(inv_menu.slot_buttons.size() >= 16, "Default inventory has at least 16 slots")
	
	# Check focus neighbor wiring on first slot
	var slot0 = inv_menu.slot_buttons[0]
	assert_false(slot0.focus_neighbor_right.is_empty(), "First slot has right neighbor")
	assert_false(slot0.focus_neighbor_bottom.is_empty(), "First slot has bottom neighbor")
	
	inv_menu.free()

func test_inventory_item_details_inspection() -> void:
	var inv_scene = preload("res://game/ui/inventory_menu.tscn")
	var inv_menu = inv_scene.instantiate()
	inv_menu._ready()
	
	inv_menu.set_slot(0, "Regolith Sample", 5, "Lunar surface sample rich in helium-3.")
	inv_menu._update_details_panel(0)
	
	assert_eq(inv_menu.label_details_name.text, "Regolith Sample", "Details name matches")
	assert_true(inv_menu.label_details_desc.text.contains("helium-3"), "Details description matches")
	assert_true(inv_menu.label_details_count.text.contains("5"), "Details quantity matches")
	
	inv_menu.free()

func test_pause_menu_focus_and_open_close() -> void:
	var pmenu_scene = preload("res://game/ui/components/pause_menu.tscn")
	var pmenu = pmenu_scene.instantiate()
	pmenu._ready()
	
	assert_false(pmenu.btn_resume.focus_neighbor_bottom.is_empty(), "Resume button has bottom neighbor")
	assert_false(pmenu.btn_settings.focus_neighbor_top.is_empty(), "Settings button has top neighbor")
	
	# Open & close signals
	var state = [false]
	pmenu.resumed.connect(func(): state[0] = true)
	
	pmenu.close()
	assert_true(state[0], "close() emits resumed signal")
	assert_false(pmenu.visible, "Pause menu is not visible when closed")
	
	pmenu.free()

func test_game_ui_mode_switching() -> void:
	var game_ui_scene = preload("res://game/ui/game_ui.tscn")
	var gui = game_ui_scene.instantiate()
	gui._ready()
	
	# Set SHIP mode (0)
	gui.set_mode(0)
	assert_true(gui.flight_telemetry.visible, "Flight telemetry visible in SHIP mode")
	assert_false(gui.suit_bars.visible, "Suit bars hidden in SHIP mode")
	
	# Set WALK mode (1)
	gui.set_mode(1)
	assert_false(gui.flight_telemetry.visible, "Flight telemetry hidden in WALK mode")
	assert_true(gui.suit_bars.visible, "Suit bars visible in WALK mode")
	
	# Toggle menus
	gui.toggle_inventory()
	assert_true(gui.inventory_menu.visible, "Inventory visible after toggle")
	gui.toggle_inventory()
	assert_false(gui.inventory_menu.visible, "Inventory hidden after second toggle")
	
	gui.toggle_orbit_map()
	assert_true(gui.orbit_map.visible, "Orbit map visible after toggle")
	gui.toggle_orbit_map()
	assert_false(gui.orbit_map.visible, "Orbit map hidden after second toggle")
	
	gui.free()
