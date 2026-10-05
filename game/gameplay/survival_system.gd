class_name SurvivalSystem extends Node
## Manages player life support, planetary environmental hazards, and death/respawn cycles.

signal life_support_changed(current: float, maximum: float)
signal hazard_protection_changed(current: float, maximum: float)
signal hazard_protection_warning(level_pct: float)
signal environment_changed(body_id: StringName, hazard_intensity: float)
signal player_died()
signal player_respawned(body_id: StringName, spawn_position: Vector3)

const BASE_LIFE_SUPPORT: float = 100.0
const BASE_HAZARD_PROTECTION: float = 100.0

@export var is_inside_ship: bool = false
@export var current_hazard_intensity: float = 0.0 # 0.0 = safe, 1.0 = lethal

var max_life_support: float = BASE_LIFE_SUPPORT
var max_hazard_protection: float = BASE_HAZARD_PROTECTION

var _life_support: float = BASE_LIFE_SUPPORT
var _hazard_protection: float = BASE_HAZARD_PROTECTION
var _warned_25: bool = false
var _warned_10: bool = false

var current_body_id: StringName = &"Earth"
var has_breathable_atmosphere: bool = true
var is_daytime: bool = true
var vacuum_hazard: float = 0.0
var thermal_hazard: float = 0.0
var radiation_hazard: float = 0.0

const LIFE_SUPPORT_DRAIN_RATE: float = 100.0 / 900.0 # 15 minutes base in vacuum
const HAZARD_DRAIN_RATE_BASE: float = 0.185 # per second at max intensity (~10 min suit under Moon 0.9)
const RECHARGE_RATE: float = 20.0 # per second inside safe haven / ship

func _ready() -> void:
	set_environment(current_body_id)

func _process(delta: float) -> void:
	if is_inside_ship:
		_recharge(delta)
	else:
		_drain(delta)

## Sets current celestial body and calculates environment hazards
func set_environment(body_id: Variant, is_day: bool = true, radiation_level: float = 1.0) -> void:
	is_daytime = is_day
	var name_str: String = str(body_id).to_lower()

	if name_str == "earth":
		current_body_id = &"Earth"
		has_breathable_atmosphere = true
		vacuum_hazard = 0.0
		thermal_hazard = 0.0
		radiation_hazard = 0.0
		current_hazard_intensity = 0.0
	elif name_str == "moon":
		current_body_id = &"Moon"
		has_breathable_atmosphere = false
		vacuum_hazard = 0.4
		# Lunar thermal extremes: +120 C day, -130 C night
		thermal_hazard = 0.3 if is_day else 0.4
		# Lunar surface radiation (solar wind in day, galactic cosmic in night)
		radiation_hazard = (0.2 if is_day else 0.1) * maxf(0.0, radiation_level)
		current_hazard_intensity = clampf(vacuum_hazard + thermal_hazard + radiation_hazard, 0.0, 1.0)
	else:
		current_body_id = StringName(str(body_id))
		has_breathable_atmosphere = false
		vacuum_hazard = 0.5
		thermal_hazard = 0.2
		radiation_hazard = 0.3 * maxf(0.0, radiation_level)
		current_hazard_intensity = clampf(vacuum_hazard + thermal_hazard + radiation_hazard, 0.0, 1.0)

	environment_changed.emit(current_body_id, current_hazard_intensity)

func _recharge(delta: float) -> void:
	var ls_changed: bool = false
	var hazard_changed: bool = false

	if _life_support < max_life_support:
		_life_support = move_toward(_life_support, max_life_support, RECHARGE_RATE * delta)
		ls_changed = true

	if _hazard_protection < max_hazard_protection:
		_hazard_protection = move_toward(_hazard_protection, max_hazard_protection, RECHARGE_RATE * delta)
		hazard_changed = true

	if ls_changed:
		life_support_changed.emit(_life_support, max_life_support)
	if hazard_changed:
		_reset_hazard_warnings_on_increase()
		hazard_protection_changed.emit(_hazard_protection, max_hazard_protection)

func _drain(delta: float) -> void:
	# Deplete hazard protection if environmental hazard is present
	if current_hazard_intensity > 0.0:
		if _hazard_protection > 0.0:
			_hazard_protection -= HAZARD_DRAIN_RATE_BASE * current_hazard_intensity * delta
			_hazard_protection = maxf(0.0, _hazard_protection)
			hazard_protection_changed.emit(_hazard_protection, max_hazard_protection)
			_check_hazard_warnings()
		else:
			# Hazard breach drains life support rapidly
			_life_support -= (LIFE_SUPPORT_DRAIN_RATE + HAZARD_DRAIN_RATE_BASE * current_hazard_intensity) * delta
			_life_support = maxf(0.0, _life_support)
			life_support_changed.emit(_life_support, max_life_support)
	else:
		# If safe atmosphere (e.g. Earth), life support is not depleted
		if not has_breathable_atmosphere:
			if _life_support > 0.0:
				_life_support -= LIFE_SUPPORT_DRAIN_RATE * delta
				_life_support = maxf(0.0, _life_support)
				life_support_changed.emit(_life_support, max_life_support)

	if _life_support <= 0.0:
		player_died.emit()
		set_process(false)

func _check_hazard_warnings() -> void:
	var pct: float = (_hazard_protection / max_hazard_protection) * 100.0
	if pct < 25.0 and not _warned_25:
		_warned_25 = true
		hazard_protection_warning.emit(25.0)
	if pct < 10.0 and not _warned_10:
		_warned_10 = true
		hazard_protection_warning.emit(10.0)

func _reset_hazard_warnings_on_increase() -> void:
	var pct: float = (_hazard_protection / max_hazard_protection) * 100.0
	if pct >= 25.0:
		_warned_25 = false
	if pct >= 10.0:
		_warned_10 = false

## Replenishes a specific amount of life support (e.g. from consumable)
func replenish_life_support(amount: float) -> void:
	_life_support = clampf(_life_support + amount, 0.0, max_life_support)
	life_support_changed.emit(_life_support, max_life_support)

## Replenishes a specific amount of hazard protection
func replenish_hazard_protection(amount: float) -> void:
	_hazard_protection = clampf(_hazard_protection + amount, 0.0, max_hazard_protection)
	_reset_hazard_warnings_on_increase()
	hazard_protection_changed.emit(_hazard_protection, max_hazard_protection)

func set_max_life_support(value: float) -> void:
	max_life_support = maxf(1.0, value)
	_life_support = minf(_life_support, max_life_support)
	life_support_changed.emit(_life_support, max_life_support)

func set_max_hazard_protection(value: float) -> void:
	max_hazard_protection = maxf(1.0, value)
	_hazard_protection = minf(_hazard_protection, max_hazard_protection)
	_reset_hazard_warnings_on_increase()
	hazard_protection_changed.emit(_hazard_protection, max_hazard_protection)

## Resets player health/suit and respawns at target body
func respawn(body_id: Variant = &"Earth", spawn_pos: Vector3 = Vector3.ZERO) -> void:
	_life_support = max_life_support
	_hazard_protection = max_hazard_protection
	_warned_25 = false
	_warned_10 = false
	set_process(true)
	set_environment(body_id)
	life_support_changed.emit(_life_support, max_life_support)
	hazard_protection_changed.emit(_hazard_protection, max_hazard_protection)
	player_respawned.emit(current_body_id, spawn_pos)

func get_life_support() -> float:
	return _life_support

func get_hazard_protection() -> float:
	return _hazard_protection

func to_dict() -> Dictionary:
	return {
		"life_support": _life_support,
		"hazard_protection": _hazard_protection,
		"max_life_support": max_life_support,
		"max_hazard_protection": max_hazard_protection,
		"current_body_id": String(current_body_id),
		"is_inside_ship": is_inside_ship,
	}

func from_dict(data: Dictionary) -> void:
	if data.has("max_life_support"):
		max_life_support = float(data["max_life_support"])
	if data.has("max_hazard_protection"):
		max_hazard_protection = float(data["max_hazard_protection"])
	if data.has("life_support"):
		_life_support = float(data["life_support"])
	if data.has("hazard_protection"):
		_hazard_protection = float(data["hazard_protection"])
	if data.has("current_body_id"):
		set_environment(data["current_body_id"])
	if data.has("is_inside_ship"):
		is_inside_ship = bool(data["is_inside_ship"])

	var pct: float = (_hazard_protection / max_hazard_protection) * 100.0
	_warned_25 = pct < 25.0
	_warned_10 = pct < 10.0

	life_support_changed.emit(_life_support, max_life_support)
	hazard_protection_changed.emit(_hazard_protection, max_hazard_protection)
