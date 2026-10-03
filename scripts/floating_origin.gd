extends Node
class_name FloatingOrigin

## Floating Origin System for Astronomical Scale Simulation.
## Prevents 32-bit floating-point precision breakdown and visual jitter by periodically
## recentering the Godot world origin around the active player vessel.
## Tracks universe-scale positions using double-precision Vector3 coordinates.

signal origin_shifted(shift_delta: Vector3)

@export var tracking_target: Node3D
@export var threshold_distance: float = 3000.0 # Meters from (0,0,0) before origin shift triggers
@export var is_active: bool = true

var universe_origin_offset: Vector3 = Vector3.ZERO
var total_shifts_performed: int = 0
var shiftable_nodes: Array[Node3D] = []

func _ready() -> void:
	add_to_group("floating_origin_system")

func register_shiftable_node(node: Node3D) -> void:
	if not shiftable_nodes.has(node):
		shiftable_nodes.append(node)

func unregister_shiftable_node(node: Node3D) -> void:
	shiftable_nodes.erase(node)

func _physics_process(_delta: float) -> void:
	if not is_active or not is_instance_valid(tracking_target):
		return
		
	var target_pos: Vector3 = tracking_target.global_position
	if target_pos.length() > threshold_distance:
		_perform_origin_shift(target_pos)

func _perform_origin_shift(shift_vector: Vector3) -> void:
	universe_origin_offset += shift_vector
	total_shifts_performed += 1
	
	if tracking_target is RigidBody3D:
		var rb: RigidBody3D = tracking_target as RigidBody3D
		var cur_trans: Transform3D = rb.global_transform
		cur_trans.origin -= shift_vector
		rb.global_transform = cur_trans
	else:
		tracking_target.global_position -= shift_vector
		
	for node in shiftable_nodes:
		if is_instance_valid(node) and node != tracking_target:
			node.global_position -= shift_vector
			
	var world_root: Node = get_tree().current_scene
	if world_root:
		for child in world_root.get_children():
			if child is Node3D and child != self and not child.is_ancestor_of(tracking_target) and child != tracking_target:
				if not shiftable_nodes.has(child):
					child.global_position -= shift_vector
					
	origin_shifted.emit(shift_vector)

func local_to_universe(local_pos: Vector3) -> Vector3:
	return local_pos + universe_origin_offset

func universe_to_local(univ_pos: Vector3) -> Vector3:
	return univ_pos - universe_origin_offset

func get_target_universe_position() -> Vector3:
	if is_instance_valid(tracking_target):
		return local_to_universe(tracking_target.global_position)
	return universe_origin_offset
