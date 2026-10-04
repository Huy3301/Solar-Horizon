class_name ResourceNode extends Area3D
## Harvestable resource deposit that yields materials to an inventory when mined.

signal mined(amount_mined: float, remaining: float)
signal depleted()

@export var item_id: String = "iron_ore"
@export var amount: float = 100.0
@export var max_amount: float = 100.0
@export var mining_rate: float = 10.0 # base units mined per second
@export var hardness: float = 1.0

var _fractional_yield: float = 0.0

## Mines the resource deposit for the given delta time.
## Yields whole units to yield_to inventory if provided.
## Returns the actual float amount of resource extracted.
func mine(delta: float, yield_to: InventorySystem = null, efficiency: float = 1.0) -> float:
	if amount <= 0.0 or delta <= 0.0:
		return 0.0

	var rate := (mining_rate * maxf(0.01, efficiency)) / maxf(0.1, hardness)
	var attempted := rate * delta
	var extracted := minf(amount, attempted)
	amount -= extracted

	if yield_to != null and extracted > 0.0:
		_fractional_yield += extracted
		var whole_units := int(floor(_fractional_yield))
		if whole_units > 0:
			var leftover := yield_to.add_item(item_id, whole_units)
			var accepted := whole_units - leftover
			_fractional_yield -= float(accepted)

	mined.emit(extracted, amount)
	if amount <= 0.0:
		depleted.emit()

	return extracted

func take_damage(damage: float) -> void:
	# Generic damage interaction also damages/mines the resource deposit
	mine(damage * 0.1, null, 1.0)
