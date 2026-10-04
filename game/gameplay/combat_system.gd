class_name CombatSystem extends Node
## Manages ship hull integrity, shields, and projectile/laser raycasts.

@export var max_hull: float = 1000.0
@export var max_shields: float = 1000.0
@export var shield_regen_rate: float = 50.0
@export var shield_regen_delay: float = 5.0

var current_hull: float
var current_shields: float
var _time_since_last_hit: float = 0.0

signal hull_changed(new_val: float, max_val: float)
signal shields_changed(new_val: float, max_val: float)
signal ship_destroyed

func _ready() -> void:
	current_hull = max_hull
	current_shields = max_shields

func _process(delta: float) -> void:
	_time_since_last_hit += delta
	
	if _time_since_last_hit >= shield_regen_delay and current_shields < max_shields:
		current_shields = min(max_shields, current_shields + shield_regen_rate * delta)
		emit_signal("shields_changed", current_shields, max_shields)

func apply_damage(amount: float) -> void:
	if amount <= 0:
		return
		
	_time_since_last_hit = 0.0
	
	if current_shields > 0:
		if current_shields >= amount:
			current_shields -= amount
			amount = 0
		else:
			amount -= current_shields
			current_shields = 0
		emit_signal("shields_changed", current_shields, max_shields)
		
	if amount > 0:
		current_hull -= amount
		emit_signal("hull_changed", current_hull, max_hull)
		
		if current_hull <= 0:
			emit_signal("ship_destroyed")

## Fires a laser raycast from the given origin in the given direction
func fire_laser(origin: Vector3, direction: Vector3, range_m: float, damage: float, exclude_rids: Array[RID] = []) -> void:
	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * range_m)
	query.exclude = exclude_rids
	
	var result = space_state.intersect_ray(query)
	if result:
		# If we hit something with a take_damage method, call it
		var collider = result.collider
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		elif collider.has_method("apply_damage"):
			collider.apply_damage(damage)
