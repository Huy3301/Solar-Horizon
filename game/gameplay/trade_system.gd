extends Node
## Manages localized supply/demand economies and player trading.

const CURRENCY_NAME = "Survey Credits"

var player_credits: int = 1000

## Maps station or planet ID to its local economy state
## Format: { location_id: { "supply": { item_id: amount }, "demand": { item_id: amount }, "wealth_level": float } }
var economies: Dictionary = {}

func _ready() -> void:
	pass

## Initializes an economy for a given location.
func initialize_economy(location_id: String, wealth: float, primary_production: Array[String], primary_needs: Array[String]) -> void:
	var economy = {
		"wealth_level": wealth,
		"supply": {},
		"demand": {}
	}
	
	for item in primary_production:
		economy["supply"][item] = 1.0 + wealth * 0.5
		
	for item in primary_needs:
		economy["demand"][item] = 1.0 + wealth * 0.5
		
	economies[location_id] = economy

## Calculates the buy price of an item at a specific location
func get_buy_price(location_id: String, item_id: String, base_price: int) -> int:
	if not economies.has(location_id):
		return base_price
		
	var economy = economies[location_id]
	var demand_mod = economy["demand"].get(item_id, 1.0)
	var supply_mod = economy["supply"].get(item_id, 1.0)
	
	# High demand = higher price. High supply = lower price.
	var price_multiplier = demand_mod / supply_mod
	return clampi(int(base_price * price_multiplier), 1, 999999)

## Calculates the sell price of an item at a specific location
func get_sell_price(location_id: String, item_id: String, base_price: int) -> int:
	# Selling to them gives less than buying from them, tuned for steady income
	return int(get_buy_price(location_id, item_id, base_price) * 0.90)

## Player buys an item from a location
func buy_item(location_id: String, item_id: String, quantity: int, base_price: int) -> bool:
	var total_cost = get_buy_price(location_id, item_id, base_price) * quantity
	
	if player_credits >= total_cost:
		player_credits -= total_cost
		# Add inventory integration later
		return true
	return false

## Player sells an item to a location
func sell_item(location_id: String, item_id: String, quantity: int, base_price: int) -> void:
	var total_revenue = get_sell_price(location_id, item_id, base_price) * quantity
	player_credits += total_revenue
	# Remove from inventory integration later
