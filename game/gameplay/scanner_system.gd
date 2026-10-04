class_name ScannerSystem extends Node3D

signal scan_started()
signal scan_completed(targets: Array[Dictionary])
signal scan_failed()

@export var scan_radius: float = 50.0
@export var scan_duration: float = 1.0

var _is_scanning: bool = false
var _scan_timer: float = 0.0

# Represents the visual effect / post processing for the visor
var _visor_active: bool = false

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("scan") and not _is_scanning:
		_start_scan()
	elif event.is_action_pressed("visor"):
		# Toggle visor mode
		_visor_active = not _visor_active

func _process(delta: float) -> void:
	if _is_scanning:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_finish_scan()

func _start_scan() -> void:
	_is_scanning = true
	_scan_timer = scan_duration
	scan_started.emit()
	# Play scan sound / start visual effect

func _finish_scan() -> void:
	_is_scanning = false
	
	var found_targets: Array[Dictionary] = []
	
	# Attempt to find interactive nodes (using groups as a simple mockup)
	var interactables = get_tree().get_nodes_in_group("scannable")
	for node in interactables:
		if is_instance_valid(node) and node is Node3D:
			var dist = global_position.distance_to(node.global_position)
			if dist <= scan_radius:
				found_targets.append({
					"node": node,
					"distance": dist,
					"name": node.name,
					"type": "Entity"
				})
				
				# If the node has a highlight method, call it
				if node.has_method("highlight"):
					node.highlight()
					
	# For GPU scatter layer, we'd normally query the scatter system
	# This is a placeholder for the actual GPU scatter query implementation
	var scatter_system = get_tree().root.get_node_or_null("ScatterSystem")
	if scatter_system and scatter_system.has_method("query_nearby"):
		var scatter_results = scatter_system.query_nearby(global_position, scan_radius)
		for res in scatter_results:
			found_targets.append(res)
			
	if found_targets.size() > 0:
		scan_completed.emit(found_targets)
	else:
		scan_failed.emit()
