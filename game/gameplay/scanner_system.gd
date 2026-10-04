class_name ScannerSystem extends Node3D
## Scans planetary environments, detects resources and entities, and catalogues discoveries.

signal scan_started()
signal scan_completed(targets: Array[Dictionary])
signal scan_failed()
signal visor_toggled(active: bool)

@export var scan_radius: float = 60.0
@export var scan_duration: float = 1.0

var _is_scanning: bool = false
var _scan_timer: float = 0.0
var _visor_active: bool = false

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	if InputMap.has_action("scan") and event.is_action_pressed("scan") and not _is_scanning:
		_start_scan()
	elif InputMap.has_action("visor") and event.is_action_pressed("visor"):
		toggle_visor()

func toggle_visor() -> bool:
	_visor_active = not _visor_active
	visor_toggled.emit(_visor_active)
	return _visor_active

func is_visor_active() -> bool:
	return _visor_active

func _process(delta: float) -> void:
	if _is_scanning:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_finish_scan()

func _start_scan() -> void:
	_is_scanning = true
	_scan_timer = scan_duration
	scan_started.emit()

func _finish_scan() -> void:
	_is_scanning = false
	var targets: Array[Dictionary] = find_scannable_targets()

	if targets.size() > 0:
		scan_completed.emit(targets)
	else:
		scan_failed.emit()

## Locates scannable objects in radius without requiring ScatterSystem autoload
func find_scannable_targets() -> Array[Dictionary]:
	var found_targets: Array[Dictionary] = []

	if is_inside_tree():
		var tree: SceneTree = get_tree()
		if tree != null:
			var interactables: Array[Node] = tree.get_nodes_in_group("scannable")
			for node in interactables:
				if is_instance_valid(node) and node is Node3D:
					var dist: float = global_position.distance_to(node.global_position)
					if dist <= scan_radius:
						var cat: String = "anomaly"
						var id_str: String = node.name
						if "category" in node:
							cat = str(node.category)
						elif "item_id" in node:
							cat = "mineral"
							id_str = str(node.item_id)

						var target_entry: Dictionary = {
							"node": node,
							"id": id_str,
							"distance": dist,
							"name": node.name,
							"category": cat,
							"planet_id": "Earth",
						}
						found_targets.append(target_entry)

						if node.has_method("highlight"):
							node.highlight()

			# Optional non-mandatory check for ScatterSystem (safe null lookup)
			var root: Node = tree.root
			if root != null:
				var scatter_system: Node = root.get_node_or_null("ScatterSystem")
				if scatter_system != null and scatter_system.has_method("query_nearby"):
					var scatter_results = scatter_system.query_nearby(global_position, scan_radius)
					if scatter_results is Array:
						for res in scatter_results:
							if res is Dictionary:
								found_targets.append(res)

	return found_targets

## Helper to scan environment and automatically register findings into a discovery system
func scan_and_catalog(discovery_system: Object = null, planet_id: String = "Earth") -> Array[Dictionary]:
	var targets: Array[Dictionary] = find_scannable_targets()
	if discovery_system == null and is_inside_tree() and get_tree().root != null:
		discovery_system = get_tree().root.get_node_or_null("DiscoverySystem")

	if discovery_system != null:
		for t in targets:
			var id_val: String = str(t.get("id", t.get("name", "unknown")))
			var cat_val: String = str(t.get("category", "mineral"))
			var name_val: String = str(t.get("name", id_val))
			discovery_system.register_discovery(id_val, cat_val, name_val, planet_id, t)

	return targets
