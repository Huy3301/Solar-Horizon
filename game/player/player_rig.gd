class_name PlayerRig extends Node3D

## High-level player orchestrator and state machine managing Ship <-> Walk (EVA) transitions.
## Supports EVA when ship is landed, hatch interaction to enter/exit, and duck-typed subsystem hooks.

enum PlayerMode {
	SHIP = 0,
	WALK = 1
}

signal mode_changed(new_mode: PlayerMode)
signal entered_ship(ship_node: Node)
signal exited_ship(ship_node: Node, spawn_position: Vector3)
signal hatch_interaction_possible(possible: bool, prompt: String)

@export var current_mode: PlayerMode = PlayerMode.SHIP
@export var ship_path: NodePath
@export var on_foot_rig_path: NodePath
@export var hatch_interaction_distance: float = 6.0
@export var hatch_relative_offset: Vector3 = Vector3(-3.5, 0.0, 0.0)

var current_ship: Node = null
var on_foot_rig: OnFootRig = null

var _cached_interaction_state: bool = false
var _cached_prompt: String = ""

func _ready() -> void:
	_resolve_nodes()
	if current_mode == PlayerMode.SHIP:
		enter_ship(current_ship)
	else:
		exit_ship(true)

func _resolve_nodes() -> void:
	if not ship_path.is_empty():
		current_ship = get_node_or_null(ship_path)
	elif current_ship == null:
		current_ship = _find_ship_in_tree()
		
	if not on_foot_rig_path.is_empty():
		on_foot_rig = get_node_or_null(on_foot_rig_path) as OnFootRig
	elif on_foot_rig == null:
		on_foot_rig = _find_on_foot_rig_in_tree()

func set_ship(ship_node: Node) -> void:
	current_ship = ship_node

func set_on_foot_rig(rig_node: OnFootRig) -> void:
	on_foot_rig = rig_node

func get_current_mode() -> PlayerMode:
	return current_mode

func can_exit_ship() -> bool:
	if current_mode != PlayerMode.SHIP or not is_instance_valid(current_ship):
		return false
	
	# Duck-typed landing checks
	if "is_landed" in current_ship and current_ship.is_landed:
		return true
	if current_ship.has_method("is_ship_landed") and current_ship.is_ship_landed():
		return true
	if current_ship is RigidBody3D and (current_ship as RigidBody3D).linear_velocity.length() < 0.3:
		return true
		
	return false

func is_near_hatch() -> bool:
	if current_mode != PlayerMode.WALK or not is_instance_valid(current_ship) or not is_instance_valid(on_foot_rig):
		return false
	var hatch_pos = get_hatch_position()
	var rig_pos = on_foot_rig.global_position if on_foot_rig.is_inside_tree() else on_foot_rig.position
	return rig_pos.distance_to(hatch_pos) <= hatch_interaction_distance

func get_hatch_position() -> Vector3:
	if not is_instance_valid(current_ship):
		return global_position if is_inside_tree() else position
		
	var hatch_node = current_ship.get_node_or_null("Hatch")
	if not hatch_node:
		hatch_node = current_ship.get_node_or_null("CrewHatch")
	if hatch_node and hatch_node is Node3D:
		return (hatch_node as Node3D).global_position if hatch_node.is_inside_tree() else (hatch_node as Node3D).position
		
	if current_ship is Node3D:
		var ship_pos = (current_ship as Node3D).global_position if (current_ship as Node3D).is_inside_tree() else (current_ship as Node3D).position
		var ship_basis = (current_ship as Node3D).global_transform.basis if (current_ship as Node3D).is_inside_tree() else (current_ship as Node3D).transform.basis
		return ship_pos + ship_basis * hatch_relative_offset
	return global_position if is_inside_tree() else position

func exit_ship(bypass_landed_check: bool = false) -> bool:
	if not bypass_landed_check and not can_exit_ship():
		return false
		
	var spawn_pos: Vector3 = get_hatch_position()
	
	# Neutralize ship controls
	if is_instance_valid(current_ship):
		if "current_throttle" in current_ship:
			current_ship.current_throttle = 0.0
		if "control_pitch" in current_ship:
			current_ship.control_pitch = 0.0
			current_ship.control_yaw = 0.0
			current_ship.control_roll = 0.0
		_set_ship_camera_active(false)
		
	# Activate on-foot rig
	_ensure_on_foot_rig()
	if is_instance_valid(on_foot_rig):
		if on_foot_rig.is_inside_tree():
			on_foot_rig.global_position = spawn_pos
		else:
			on_foot_rig.position = spawn_pos
		on_foot_rig.visible = true
		on_foot_rig.set_active(true)
		
	# Duck-typed survival update
	_update_survival_inside_ship(false)
	
	current_mode = PlayerMode.WALK
	exited_ship.emit(current_ship, spawn_pos)
	mode_changed.emit(current_mode)
	return true

func enter_ship(ship_target: Node = null) -> bool:
	if ship_target:
		current_ship = ship_target
	if not is_instance_valid(current_ship):
		return false
		
	# Deactivate on-foot rig
	if is_instance_valid(on_foot_rig):
		on_foot_rig.set_active(false)
		on_foot_rig.visible = false
		
	# Activate ship camera
	_set_ship_camera_active(true)
	
	# Duck-typed survival update
	_update_survival_inside_ship(true)
	
	current_mode = PlayerMode.SHIP
	entered_ship.emit(current_ship)
	mode_changed.emit(current_mode)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if current_mode == PlayerMode.SHIP:
			if can_exit_ship():
				exit_ship()
		elif current_mode == PlayerMode.WALK:
			if is_near_hatch():
				enter_ship()

func _process(_delta: float) -> void:
	var can_interact = false
	var prompt = ""
	
	if current_mode == PlayerMode.SHIP:
		if can_exit_ship():
			can_interact = true
			prompt = "[F] EVA / Exit Ship"
	elif current_mode == PlayerMode.WALK:
		if is_near_hatch():
			can_interact = true
			prompt = "[F] Board Ship"
			
	if can_interact != _cached_interaction_state or prompt != _cached_prompt:
		_cached_interaction_state = can_interact
		_cached_prompt = prompt
		hatch_interaction_possible.emit(can_interact, prompt)

func get_active_camera() -> Camera3D:
	if current_mode == PlayerMode.WALK and is_instance_valid(on_foot_rig) and on_foot_rig.camera:
		return on_foot_rig.camera
	elif is_instance_valid(current_ship):
		var cam_ctrl = current_ship.get_node_or_null("CameraController")
		if cam_ctrl and "camera" in cam_ctrl and cam_ctrl.camera:
			return cam_ctrl.camera
		for child in current_ship.get_children():
			if child is Camera3D:
				return child
	return null

func _set_ship_camera_active(active: bool) -> void:
	if not is_instance_valid(current_ship):
		return
	var cam_ctrl = current_ship.get_node_or_null("CameraController")
	if cam_ctrl and "camera" in cam_ctrl and cam_ctrl.camera:
		cam_ctrl.camera.current = active
		cam_ctrl.set_process(active)
		cam_ctrl.set_physics_process(active)
	else:
		for child in current_ship.get_children():
			if child is Camera3D:
				(child as Camera3D).current = active

func _ensure_on_foot_rig() -> void:
	if not is_instance_valid(on_foot_rig):
		on_foot_rig = _find_on_foot_rig_in_tree()
	if not is_instance_valid(on_foot_rig):
		on_foot_rig = OnFootRig.new()
		on_foot_rig.name = "OnFootRig"
		add_child(on_foot_rig)

func _find_ship_in_tree() -> Node:
	var parent_node = get_parent()
	if parent_node:
		if parent_node.name == "Ship" or parent_node is RigidBody3D:
			return parent_node
		var sibling = parent_node.get_node_or_null("Ship")
		if sibling:
			return sibling
	var tree = get_tree()
	if tree:
		return tree.get_first_node_in_group("ship")
	return null

func _find_on_foot_rig_in_tree() -> OnFootRig:
	var child = get_node_or_null("OnFootRig")
	if child is OnFootRig:
		return child
	var tree = get_tree()
	if tree:
		return tree.get_first_node_in_group("on_foot_rig") as OnFootRig
	return null

func _update_survival_inside_ship(inside: bool) -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if not tree or not tree.root:
		return
	var survival = tree.root.get_node_or_null("SurvivalSystem")
	if not survival:
		survival = tree.get_first_node_in_group("survival_system")
	if survival and "is_inside_ship" in survival:
		survival.is_inside_ship = inside
