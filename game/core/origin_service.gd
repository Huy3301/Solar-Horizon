class_name OriginService extends Node

signal origin_shifted(delta: DVec3)

@export var world_root: Node3D
@export var threshold_m: float = 5000.0 # Note: mobile uses 2000.0

var origin: UniversePosition = UniversePosition.new()
var _registered_nodes: Array[Node3D] = []

func register(node: Node3D) -> void:
	if not _registered_nodes.has(node):
		_registered_nodes.append(node)

func local_to_universe(pos: Vector3) -> UniversePosition:
	var up = UniversePosition.new(origin.sector, origin.offset)
	up.add_offset(DVec3.from_vector3(pos))
	return up

func universe_to_local(up: UniversePosition) -> Vector3:
	return up.difference_to(origin).to_vector3()

func _process(_delta: float) -> void:
	if not world_root:
		return
		
	var needs_shift = false
	var shift_vec = DVec3.zero()
	
	for node in _registered_nodes:
		if is_instance_valid(node):
			var pos = node.global_position
			if pos.length() > threshold_m:
				needs_shift = true
				shift_vec = DVec3.from_vector3(pos)
				break
				
	if needs_shift:
		_shift_origin(shift_vec)

func _shift_origin(shift: DVec3) -> void:
	origin.add_offset(shift)
	var shift_v3 = shift.to_vector3()
	
	for child in world_root.get_children():
		if child is Node3D:
			if child is RigidBody3D:
				var t = child.global_transform
				t.origin -= shift_v3
				PhysicsServer3D.body_set_state(child.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
				child.reset_physics_interpolation()
			else:
				child.global_position -= shift_v3
				child.reset_physics_interpolation()
				
	origin_shifted.emit(shift)
