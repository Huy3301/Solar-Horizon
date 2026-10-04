extends Node

## Handles snapping and placing of modular base components.

signal component_placed(component: Node3D)

var active_blueprint: PackedScene
var placement_preview: Node3D
var snap_distance: float = 2.0
var active_base_root: Node3D

func _ready() -> void:
	pass

func start_placement(blueprint: PackedScene) -> void:
	active_blueprint = blueprint
	if placement_preview:
		placement_preview.queue_free()
	
	placement_preview = blueprint.instantiate() as Node3D
	# Disable collision in preview
	_set_collision_recursive(placement_preview, false)
	add_child(placement_preview)

func update_placement(ray_origin: Vector3, ray_dir: Vector3) -> void:
	if not placement_preview:
		return
	
	var intersection = _raycast_world(ray_origin, ray_dir)
	if intersection.is_empty():
		return
	
	var hit_pos = intersection.position
	
	# Try to snap
	var snapped_pos = _find_snap_point(hit_pos)
	if snapped_pos != Vector3.INF:
		placement_preview.global_position = snapped_pos
	else:
		placement_preview.global_position = hit_pos

func confirm_placement() -> void:
	if not placement_preview or not active_blueprint:
		return
		
	var new_comp = active_blueprint.instantiate() as Node3D
	new_comp.global_transform = placement_preview.global_transform
	
	if active_base_root:
		active_base_root.add_child(new_comp)
	else:
		get_tree().current_scene.add_child(new_comp)
		
	component_placed.emit(new_comp)
	
	# Stop placement
	placement_preview.queue_free()
	placement_preview = null
	active_blueprint = null

func cancel_placement() -> void:
	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null
	active_blueprint = null

func _find_snap_point(pos: Vector3) -> Vector3:
	if not active_base_root:
		return Vector3.INF
	
	var closest_dist: float = snap_distance
	var closest_point: Vector3 = Vector3.INF
	
	for child in active_base_root.get_children():
		if child.has_method("get_snap_points"):
			var points = child.get_snap_points()
			for p in points:
				var dist = p.distance_to(pos)
				if dist < closest_dist:
					closest_dist = dist
					closest_point = p
	return closest_point

func _set_collision_recursive(node: Node, enabled: bool) -> void:
	if node is CollisionShape3D or node is CollisionPolygon3D:
		node.disabled = not enabled
	for child in node.get_children():
		_set_collision_recursive(child, enabled)

func _raycast_world(origin: Vector3, dir: Vector3) -> Dictionary:
	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0)
	return space_state.intersect_ray(query)
