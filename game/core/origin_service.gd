extends Node

signal origin_shifted(delta: DVec3)

@export var world_root: Node3D
@export var threshold_m: float = 5000.0 # Note: mobile uses 2000.0
@export var focus_node: Node3D = null
@export var hysteresis_margin_m: float = 500.0

var origin: UniversePosition = UniversePosition.new()
var _registered_nodes: Array[Node3D] = []

func register(node: Node3D) -> void:
	if not _registered_nodes.has(node):
		_registered_nodes.append(node)
	if focus_node == null:
		focus_node = node
	if not node.is_in_group("floating"):
		node.add_to_group("floating")

func unregister(node: Node3D) -> void:
	_registered_nodes.erase(node)
	if focus_node == node:
		focus_node = null
		for n in _registered_nodes:
			if is_instance_valid(n):
				focus_node = n
				break

func set_focus_node(node: Node3D) -> void:
	focus_node = node
	if node != null and not _registered_nodes.has(node):
		_registered_nodes.append(node)

func local_to_universe(pos: Vector3) -> UniversePosition:
	var up = UniversePosition.new(origin.sector, origin.offset)
	up.add_offset(DVec3.from_vector3(pos))
	return up

func universe_to_local(up: UniversePosition) -> Vector3:
	return origin.difference_to(up).to_vector3()

func _process(_delta: float) -> void:
	check_and_shift()

func check_and_shift() -> bool:
	var target: Node3D = focus_node
	if not is_instance_valid(target):
		target = null
		for i in range(_registered_nodes.size() - 1, -1, -1):
			var n = _registered_nodes[i]
			if not is_instance_valid(n):
				_registered_nodes.remove_at(i)
			elif target == null:
				target = n
		focus_node = target
		
	if not is_instance_valid(target):
		return false
		
	var pos = target.global_position if target.is_inside_tree() else target.position
	if pos.length() > threshold_m:
		var shift_vec = DVec3.from_vector3(pos)
		_shift_origin(shift_vec)
		return true
	return false

func shift_origin(shift: DVec3) -> void:
	_shift_origin(shift)

func _shift_origin(shift: DVec3) -> void:
	if shift == null or (shift.x == 0.0 and shift.y == 0.0 and shift.z == 0.0):
		return
		
	origin.add_offset(shift)
	var shift_v3 = shift.to_vector3()
	var shifted_node_ids: Dictionary = {}
	var notified_nodes: Dictionary = {}
	
	var root = world_root
	if not is_instance_valid(root) and is_inside_tree():
		var cs = get_tree().current_scene
		if cs is Node3D:
			root = cs
			
	if is_instance_valid(root):
		for child in root.get_children():
			if child is Node3D:
				_shift_node_recursive(child, shift_v3, shifted_node_ids, true, shift, notified_nodes)
				
	if is_inside_tree():
		for f_node in get_tree().get_nodes_in_group("floating"):
			if f_node is Node3D and not shifted_node_ids.has(f_node.get_instance_id()):
				_shift_node_recursive(f_node, shift_v3, shifted_node_ids, true, shift, notified_nodes)
			if not notified_nodes.has(f_node.get_instance_id()):
				notified_nodes[f_node.get_instance_id()] = true
				if f_node.has_method("on_origin_shifted"):
					f_node.on_origin_shifted(shift)
				elif f_node.has_method("shift_origin"):
					f_node.shift_origin(shift)
					
	origin_shifted.emit(shift)

func _shift_rigid_body(body: RigidBody3D, shift_v3: Vector3) -> void:
	var rid = body.get_rid()
	var t = body.global_transform
	t.origin -= shift_v3
	var lv = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var av = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lv)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, av)
	body.global_transform = t
	body.reset_physics_interpolation()

func _shift_node_recursive(node: Node3D, shift_v3: Vector3, shifted_node_ids: Dictionary, is_root_child: bool, shift: DVec3, notified_nodes: Dictionary) -> void:
	var nid = node.get_instance_id()
	if shifted_node_ids.has(nid):
		return
	shifted_node_ids[nid] = true
	
	if is_root_child or node.top_level:
		if node is RigidBody3D:
			_shift_rigid_body(node, shift_v3)
		else:
			if node.is_inside_tree():
				node.global_position -= shift_v3
			else:
				node.position -= shift_v3
			node.reset_physics_interpolation()
	else:
		if node is RigidBody3D:
			var rid = node.get_rid()
			var lv = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var av = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, node.global_transform)
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lv)
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, av)
			node.reset_physics_interpolation()
			
	if not notified_nodes.has(nid):
		if node.has_method("on_origin_shifted"):
			notified_nodes[nid] = true
			node.on_origin_shifted(shift)
			
	for child in node.get_children():
		if child is Node3D:
			_shift_node_recursive(child, shift_v3, shifted_node_ids, false, shift, notified_nodes)
