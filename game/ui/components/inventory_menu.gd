class_name InventoryMenu extends Control

## Keyboard and Gamepad navigable inventory grid menu.
## Connects duck-typed to InventorySystem and presents interactive item slots with details pane.

signal item_selected(slot_index: int, item_data: Variant)
signal item_activated(slot_index: int, item_data: Variant)
signal closed()

@export var slot_count: int = 16
@export var grid_columns: int = 4

var grid_container: GridContainer = null
var label_details_name: Label = null
var label_details_desc: Label = null
var label_details_count: Label = null

var inventory_system: Node = null
var slot_buttons: Array[Button] = []
var slot_items: Array[Dictionary] = [] # Array of { "name": String, "count": int, "desc": String, "raw": Variant }
var selected_index: int = 0

func _ready() -> void:
	_resolve_nodes()
	_init_slots()
	refresh_grid()

func _resolve_nodes() -> void:
	grid_container = get_node_or_null("Panel/HBoxContainer/InventorySection/ScrollContainer/InventoryGrid") as GridContainer
	label_details_name = get_node_or_null("Panel/HBoxContainer/CraftingSection/ItemDetails/NameLabel") as Label
	label_details_desc = get_node_or_null("Panel/HBoxContainer/CraftingSection/ItemDetails/DescLabel") as Label
	label_details_count = get_node_or_null("Panel/HBoxContainer/CraftingSection/ItemDetails/CountLabel") as Label

func _init_slots() -> void:
	if not grid_container:
		_resolve_nodes()
	if not grid_container:
		return
		
	# Clear existing placeholder children
	for child in grid_container.get_children():
		child.queue_free()
		
	slot_buttons.clear()
	slot_items.clear()
	grid_container.columns = grid_columns
	
	for i in range(slot_count):
		var btn = Button.new()
		btn.name = "Slot_%d" % i
		btn.custom_minimum_size = Vector2(64, 64)
		btn.focus_mode = Control.FOCUS_ALL
		btn.text = "Empty"
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(_on_slot_pressed.bind(i))
		btn.focus_entered.connect(_on_slot_focus_entered.bind(i))
		grid_container.add_child(btn)
		slot_buttons.append(btn)
		slot_items.append({})
		
	_setup_focus_neighbors()

func _setup_focus_neighbors() -> void:
	for i in range(slot_buttons.size()):
		var btn = slot_buttons[i]
		var col = i % grid_columns
		var row = i / grid_columns
		
		# Left / Right
		if col > 0:
			btn.focus_neighbor_left = btn.get_path_to(slot_buttons[i - 1])
		if col < grid_columns - 1 and (i + 1) < slot_buttons.size():
			btn.focus_neighbor_right = btn.get_path_to(slot_buttons[i + 1])
			
		# Up / Down
		if row > 0:
			btn.focus_neighbor_top = btn.get_path_to(slot_buttons[i - grid_columns])
		if (i + grid_columns) < slot_buttons.size():
			btn.focus_neighbor_bottom = btn.get_path_to(slot_buttons[i + grid_columns])

func set_inventory_system(inv: Node) -> void:
	inventory_system = inv
	if inv and inv.has_signal("inventory_changed"):
		if not inv.inventory_changed.is_connected(_on_inventory_changed):
			inv.inventory_changed.connect(_on_inventory_changed)
	refresh_grid()

func _on_inventory_changed(_item_data: Variant = null, _amount: int = 0) -> void:
	refresh_grid()

func set_slot(index: int, item_name: String, count: int, desc: String = "", raw_obj: Variant = null) -> void:
	if slot_buttons.is_empty():
		_init_slots()
	if index < 0 or index >= slot_items.size():
		return
	slot_items[index] = {
		"name": item_name,
		"count": count,
		"desc": desc,
		"raw": raw_obj
	}
	_update_slot_button(index)
	if index == selected_index:
		_update_details_panel(index)

func refresh_grid() -> void:
	if slot_buttons.is_empty():
		_init_slots()
		
	if not inventory_system:
		for i in range(slot_items.size()):
			_update_slot_button(i)
		_update_details_panel(selected_index)
		return
		
	# Duck-typed reading from inventory_system
	var items_dict: Dictionary = {}
	if "inventory" in inventory_system and inventory_system.inventory is Dictionary:
		items_dict = inventory_system.inventory
	elif inventory_system.has_method("get_all_items"):
		items_dict = inventory_system.get_all_items()
		
	var idx = 0
	for key in items_dict.keys():
		if idx >= slot_count:
			break
		var item_obj = key
		var count_val: int = int(items_dict[key])
		var item_name: String = "Item"
		var item_desc: String = ""
		
		if item_obj is Resource:
			if "item_name" in item_obj:
				item_name = str(item_obj.item_name)
			elif "name" in item_obj:
				item_name = str(item_obj.name)
			elif "id" in item_obj:
				item_name = str(item_obj.id)
			if "description" in item_obj:
				item_desc = str(item_obj.description)
		elif item_obj is String:
			item_name = item_obj
			
		set_slot(idx, item_name, count_val, item_desc, item_obj)
		idx += 1
		
	# Clear remaining slots
	for i in range(idx, slot_count):
		slot_items[i] = {}
		_update_slot_button(i)
		
	_update_details_panel(selected_index)

func _update_slot_button(index: int) -> void:
	if index < 0 or index >= slot_buttons.size():
		return
	var btn = slot_buttons[index]
	var data = slot_items[index]
	if data.is_empty() or data.get("count", 0) <= 0:
		btn.text = "---"
		btn.modulate = Color(0.6, 0.6, 0.6)
	else:
		btn.text = "%s\n(x%d)" % [data.get("name", "Item"), data.get("count", 1)]
		btn.modulate = Color.WHITE

func _update_details_panel(index: int) -> void:
	if not label_details_name:
		_resolve_nodes()
	if index < 0 or index >= slot_items.size():
		return
	var data = slot_items[index]
	if data.is_empty() or data.get("count", 0) <= 0:
		if label_details_name: label_details_name.text = "No Item Selected"
		if label_details_desc: label_details_desc.text = "Select a filled slot in your inventory grid."
		if label_details_count: label_details_count.text = "Quantity: 0"
	else:
		if label_details_name: label_details_name.text = data.get("name", "Unknown Item")
		if label_details_desc: label_details_desc.text = data.get("desc", "Exploration resource or equipment component.")
		if label_details_count: label_details_count.text = "Quantity: %d" % data.get("count", 1)

func _on_slot_pressed(index: int) -> void:
	selected_index = index
	_update_details_panel(index)
	item_activated.emit(index, slot_items[index])

func _on_slot_focus_entered(index: int) -> void:
	selected_index = index
	_update_details_panel(index)
	item_selected.emit(index, slot_items[index])

func grab_initial_focus() -> void:
	if slot_buttons.size() > 0:
		slot_buttons[0].grab_focus()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		visible = false
		closed.emit()
