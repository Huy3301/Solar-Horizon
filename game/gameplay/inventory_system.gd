class_name InventorySystem extends Node
## Manages items, mass, stack limits, capacity, and serialization.

signal inventory_changed(item_id: String, new_amount: int)
signal inventory_full(item_id: String)

@export var max_slots: int = 20
@export var max_mass: float = 250.0 # kg

## Internal storage: String item_id -> int amount
var inventory: Dictionary = {}

static var _item_cache: Dictionary = {}

## Static or runtime lookup for ItemDef resources
static func get_item_def(item_id: String) -> ItemDef:
	if _item_cache.has(item_id):
		return _item_cache[item_id]
	var path: String = "res://game/data/items/" + item_id + ".tres"
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is ItemDef:
			_item_cache[item_id] = res
			return res
	# Fallback placeholder ItemDef
	var fallback: ItemDef = ItemDef.new()
	fallback.id = StringName(item_id)
	fallback.display_name = item_id.capitalize()
	fallback.stack_max = 100
	fallback.mass = 1.0
	_item_cache[item_id] = fallback
	return fallback

static func register_item_def(item_def: ItemDef) -> void:
	if item_def != null and not item_def.id.is_empty():
		_item_cache[String(item_def.id)] = item_def

func _extract_id(item_data: Variant) -> String:
	if item_data is ItemDef:
		return String(item_data.id)
	if item_data is Resource and "id" in item_data:
		return String(item_data.id)
	if item_data is StringName:
		return String(item_data)
	if item_data is String:
		return item_data
	return ""

## Calculates total mass of all stored items in kg
func get_total_mass() -> float:
	var total: float = 0.0
	for id_str in inventory:
		var count: int = inventory[id_str]
		var def: ItemDef = get_item_def(id_str)
		total += float(count) * def.mass
	return total

## Calculates number of slots used based on stack_max per item
func get_used_slots() -> int:
	var slots: int = 0
	for id_str in inventory:
		var count: int = inventory[id_str]
		var def: ItemDef = get_item_def(id_str)
		var stack_max: int = maxi(1, def.stack_max)
		slots += ceili(float(count) / float(stack_max))
	return slots

## Adds items to the inventory respecting max_slots and max_mass.
## Returns the count of leftover items that could not fit.
func add_item(item_data: Variant, amount: int) -> int:
	if amount <= 0:
		return 0

	var item_id: String = _extract_id(item_data)
	if item_id.is_empty():
		return amount

	var def: ItemDef = get_item_def(item_id)
	var stack_max: int = maxi(1, def.stack_max)
	var current_amount: int = inventory.get(item_id, 0)

	# 1. Check mass limits
	var max_by_mass: int = amount
	if max_mass > 0.0 and def.mass > 0.0:
		var available_mass: float = maxf(0.0, max_mass - get_total_mass())
		max_by_mass = int(floor(available_mass / def.mass))

	# 2. Check slot limits
	var max_by_slots: int = amount
	if max_slots > 0:
		var current_used_slots: int = get_used_slots()
		var current_slots_for_item: int = ceili(float(current_amount) / float(stack_max))
		var other_slots: int = current_used_slots - current_slots_for_item
		var available_slots: int = maxi(0, max_slots - other_slots)
		var max_allowed_total: int = available_slots * stack_max
		max_by_slots = maxi(0, max_allowed_total - current_amount)

	var can_add: int = mini(amount, mini(max_by_mass, max_by_slots))
	if can_add > 0:
		inventory[item_id] = current_amount + can_add
		inventory_changed.emit(item_id, inventory[item_id])

	var leftover: int = amount - can_add
	if leftover > 0:
		inventory_full.emit(item_id)
	return leftover

## Removes items, returns actual amount removed.
func remove_item(item_data: Variant, amount: int) -> int:
	if amount <= 0:
		return 0

	var item_id: String = _extract_id(item_data)
	if not inventory.has(item_id):
		return 0

	var current: int = inventory[item_id]
	var to_remove: int = mini(current, amount)
	inventory[item_id] -= to_remove

	if inventory[item_id] <= 0:
		inventory.erase(item_id)
		inventory_changed.emit(item_id, 0)
	else:
		inventory_changed.emit(item_id, inventory[item_id])

	return to_remove

func get_amount(item_data: Variant) -> int:
	var item_id: String = _extract_id(item_data)
	return inventory.get(item_id, 0)

func has_item(item_data: Variant, amount: int = 1) -> bool:
	return get_amount(item_data) >= amount

func transfer_to(other_inventory: InventorySystem, item_data: Variant, amount: int) -> int:
	if other_inventory == null or amount <= 0:
		return 0
	var removed: int = remove_item(item_data, amount)
	if removed <= 0:
		return 0
	var leftover: int = other_inventory.add_item(item_data, removed)
	if leftover > 0:
		# Return leftover back to self
		add_item(item_data, leftover)
	return removed - leftover

func clear() -> void:
	var keys: Array = inventory.keys()
	inventory.clear()
	for k in keys:
		inventory_changed.emit(str(k), 0)

func to_dict() -> Dictionary:
	return {
		"items": inventory.duplicate(),
		"max_slots": max_slots,
		"max_mass": max_mass,
	}

func from_dict(data: Dictionary) -> void:
	clear()
	if data.has("max_slots"):
		max_slots = int(data["max_slots"])
	if data.has("max_mass"):
		max_mass = float(data["max_mass"])
	var items_dict: Dictionary = data.get("items", {})
	for k in items_dict:
		var count: int = int(items_dict[k])
		if count > 0:
			inventory[str(k)] = count
			inventory_changed.emit(str(k), count)
