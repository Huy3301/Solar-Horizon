class_name InventorySystem extends Node
## Manages items, stacks, and transfers.

signal inventory_changed(item_data: Resource, new_amount: int)

# Dictionary mapping item Resource -> int amount
var inventory: Dictionary = {}

## Adds items to the inventory
func add_item(item_data: Resource, amount: int) -> int:
	if not inventory.has(item_data):
		inventory[item_data] = 0
	inventory[item_data] += amount
	inventory_changed.emit(item_data, inventory[item_data])
	return 0

## Removes items, returns actual amount removed.
func remove_item(item_data: Resource, amount: int) -> int:
	if not inventory.has(item_data):
		return 0
	
	var current: int = inventory[item_data]
	var to_remove: int = min(current, amount)
	inventory[item_data] -= to_remove
	
	if inventory[item_data] <= 0:
		inventory.erase(item_data)
		inventory_changed.emit(item_data, 0)
	else:
		inventory_changed.emit(item_data, inventory[item_data])
		
	return to_remove

func get_amount(item_data: Resource) -> int:
	return inventory.get(item_data, 0)

func transfer_to(other_inventory: InventorySystem, item_data: Resource, amount: int) -> int:
	var removed = remove_item(item_data, amount)
	if removed > 0:
		other_inventory.add_item(item_data, removed)
	return removed

