class_name MiningLaser extends Node3D
## Directional mining laser implementing raycast harvesting without combat dependencies.

signal laser_fired(origin: Vector3, end_point: Vector3, hit: bool)
signal laser_hit(collider: Object, amount_mined: float)
signal overheated()
signal cooled()

@export var range_m: float = 30.0
@export var mining_efficiency: float = 1.0
@export var max_heat: float = 100.0
@export var heat_rate: float = 25.0 # heat added per second firing
@export var cool_rate: float = 35.0 # heat cleared per second idle

var heat: float = 0.0
var is_overheated: bool = false

func _process(delta: float) -> void:
	if heat > 0.0:
		heat = maxf(0.0, heat - cool_rate * delta)
		if is_overheated and heat <= 0.0:
			is_overheated = false
			cooled.emit()

## Fires mining beam from origin along direction. Returns hit result dictionary.
func fire_laser(
	origin: Vector3,
	direction: Vector3,
	delta: float,
	target_inventory: InventorySystem = null,
	exclude_rids: Array[RID] = []
) -> Dictionary:
	var result_data := {
		"hit": false,
		"position": origin + direction.normalized() * range_m,
		"normal": Vector3.UP,
		"collider": null,
		"amount_mined": 0.0,
		"overheated": is_overheated,
	}

	if is_overheated or delta <= 0.0:
		return result_data

	heat += heat_rate * delta
	if heat >= max_heat:
		heat = max_heat
		is_overheated = true
		overheated.emit()

	var space_state: PhysicsDirectSpaceState3D = null
	var vp := get_viewport()
	if vp != null and vp.world_3d != null:
		space_state = vp.world_3d.direct_space_state
	elif is_inside_tree() and get_tree().root != null and get_tree().root.world_3d != null:
		space_state = get_tree().root.world_3d.direct_space_state

	var target_pos := origin + direction.normalized() * range_m

	if space_state != null:
		var query := PhysicsRayQueryParameters3D.create(origin, target_pos)
		query.exclude = exclude_rids
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			result_data["hit"] = true
			result_data["position"] = hit.position
			result_data["normal"] = hit.normal
			result_data["collider"] = hit.collider
			target_pos = hit.position

			var collider: Object = hit.collider
			var mined := 0.0
			if collider != null:
				if collider.has_method("mine"):
					mined = collider.mine(delta, target_inventory, mining_efficiency)
				elif collider.has_method("harvest"):
					mined = collider.harvest(delta, target_inventory)
				elif collider.has_method("take_damage"):
					collider.take_damage(mining_efficiency * delta * 10.0)
			result_data["amount_mined"] = mined
			laser_hit.emit(collider, mined)

	laser_fired.emit(origin, target_pos, result_data["hit"])
	return result_data
