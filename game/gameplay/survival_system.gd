class_name SurvivalSystem extends Node

signal life_support_changed(current: float, maximum: float)
signal hazard_protection_changed(current: float, maximum: float)
signal player_died()

const MAX_LIFE_SUPPORT = 100.0
const MAX_HAZARD_PROTECTION = 100.0

@export var is_inside_ship: bool = false
@export var current_hazard_intensity: float = 0.0 # 0.0 = no hazard, 1.0 = extreme hazard

var _life_support: float = MAX_LIFE_SUPPORT
var _hazard_protection: float = MAX_HAZARD_PROTECTION

const LIFE_SUPPORT_DRAIN_RATE = 100.0 / 900.0 # 15 minutes (900 seconds) to drain 100
const HAZARD_DRAIN_RATE_BASE = 5.0 # per second at max intensity

const RECHARGE_RATE = 20.0 # per second inside ship

func _process(delta: float) -> void:
	if is_inside_ship:
		_recharge(delta)
	else:
		_drain(delta)

func _recharge(delta: float) -> void:
	var ls_changed = false
	var hazard_changed = false
	
	if _life_support < MAX_LIFE_SUPPORT:
		_life_support = move_toward(_life_support, MAX_LIFE_SUPPORT, RECHARGE_RATE * delta)
		ls_changed = true
		
	if _hazard_protection < MAX_HAZARD_PROTECTION:
		_hazard_protection = move_toward(_hazard_protection, MAX_HAZARD_PROTECTION, RECHARGE_RATE * delta)
		hazard_changed = true
		
	if ls_changed:
		life_support_changed.emit(_life_support, MAX_LIFE_SUPPORT)
	if hazard_changed:
		hazard_protection_changed.emit(_hazard_protection, MAX_HAZARD_PROTECTION)

func _drain(delta: float) -> void:
	# Hazard protection depletes first if there's a hazard
	if current_hazard_intensity > 0.0:
		if _hazard_protection > 0.0:
			_hazard_protection -= HAZARD_DRAIN_RATE_BASE * current_hazard_intensity * delta
			_hazard_protection = max(0.0, _hazard_protection)
			hazard_protection_changed.emit(_hazard_protection, MAX_HAZARD_PROTECTION)
		else:
			# If hazard protection is gone, life support drains much faster
			_life_support -= (LIFE_SUPPORT_DRAIN_RATE + HAZARD_DRAIN_RATE_BASE * current_hazard_intensity) * delta
			_life_support = max(0.0, _life_support)
			life_support_changed.emit(_life_support, MAX_LIFE_SUPPORT)
	else:
		# Standard life support drain
		if _life_support > 0.0:
			_life_support -= LIFE_SUPPORT_DRAIN_RATE * delta
			_life_support = max(0.0, _life_support)
			life_support_changed.emit(_life_support, MAX_LIFE_SUPPORT)
			
	if _life_support <= 0.0:
		player_died.emit()
		set_process(false)

## Replenishes a specific amount of life support (e.g. from consumable)
func replenish_life_support(amount: float) -> void:
	_life_support = clamp(_life_support + amount, 0.0, MAX_LIFE_SUPPORT)
	life_support_changed.emit(_life_support, MAX_LIFE_SUPPORT)

## Replenishes a specific amount of hazard protection
func replenish_hazard_protection(amount: float) -> void:
	_hazard_protection = clamp(_hazard_protection + amount, 0.0, MAX_HAZARD_PROTECTION)
	hazard_protection_changed.emit(_hazard_protection, MAX_HAZARD_PROTECTION)
