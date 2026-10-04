class_name OnFootRig extends CharacterBody3D

## Surface exploration character controller with walking, sprinting, jetpack,
## third-person/first-person camera modes, and dynamic celestial gravity (Moon/Earth via GravityService).

signal jetpack_fuel_changed(current_fuel: float, max_fuel: float)
signal camera_mode_changed(is_third_person: bool)

const SPEED_WALK = 4.0
const SPEED_SPRINT = 7.0
const JUMP_VELOCITY = 4.5
const JETPACK_FORCE = 15.0
const JETPACK_MAX_FUEL = 100.0
const JETPACK_DRAIN_RATE = 20.0
const JETPACK_RECHARGE_RATE = 10.0

@export var mouse_sensitivity: float = 0.002
@export var is_third_person: bool = true
@export var third_person_distance: float = 3.5
@export var third_person_height: float = 1.4
@export var first_person_height: float = 1.6
@export var gravity_override: Vector3 = Vector3.ZERO

var _gravity: float = 9.8
var _jetpack_fuel: float = JETPACK_MAX_FUEL
var _is_jetpacking: bool = false
var _is_active: bool = true

var head: Node3D
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	_setup_nodes()
	_setup_camera()
	
	if _is_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Attempt to register with OriginService if it exists
	var origin_service = get_tree().root.get_node_or_null("OriginService") if get_tree() and get_tree().root else null
	if origin_service and origin_service.has_method("register"):
		origin_service.register(self)

func _setup_nodes() -> void:
	collision_shape = get_node_or_null("CollisionShape3D")
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		collision_shape.shape = capsule
		collision_shape.position = Vector3(0, 0.9, 0)
		add_child(collision_shape)

func _setup_camera() -> void:
	# Head/pivot node for pitch tilt
	camera_pivot = get_node_or_null("CameraPivot")
	if not camera_pivot:
		camera_pivot = Node3D.new()
		camera_pivot.name = "CameraPivot"
		add_child(camera_pivot)
	head = camera_pivot # Preserved for backwards compatibility
	
	spring_arm = camera_pivot.get_node_or_null("SpringArm3D")
	if not spring_arm:
		spring_arm = SpringArm3D.new()
		spring_arm.name = "SpringArm3D"
		spring_arm.margin = 0.2
		camera_pivot.add_child(spring_arm)
		
	camera = spring_arm.get_node_or_null("Camera3D")
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.near = 0.05
		camera.far = 500000.0
		spring_arm.add_child(camera)
		
	set_third_person(is_third_person)

func set_third_person(tp: bool) -> void:
	is_third_person = tp
	if spring_arm and camera_pivot:
		spring_arm.spring_length = third_person_distance if is_third_person else 0.0
		camera_pivot.position.y = third_person_height if is_third_person else first_person_height
	camera_mode_changed.emit(is_third_person)

func toggle_camera_mode() -> void:
	set_third_person(not is_third_person)

func set_active(active: bool) -> void:
	_is_active = active
	set_process(active)
	set_physics_process(active)
	if collision_shape:
		collision_shape.disabled = not active
	if camera:
		camera.current = active
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func get_jetpack_fuel() -> float:
	return _jetpack_fuel

func get_max_jetpack_fuel() -> float:
	return JETPACK_MAX_FUEL

func is_jetpacking() -> bool:
	return _is_jetpacking

func _input(event: InputEvent) -> void:
	if not _is_active:
		return
		
	if event.is_action_pressed("toggle_camera"):
		toggle_camera_mode()
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera_pivot:
			camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI/2.4, PI/2.4)

func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	# Handle Gamepad / Look Actions
	var look_x = Input.get_axis("look_left", "look_right")
	var look_y = Input.get_axis("look_up", "look_down")
	if abs(look_x) > 0.05:
		rotate_y(-look_x * 2.5 * delta)
	if abs(look_y) > 0.05 and camera_pivot:
		camera_pivot.rotate_x(-look_y * 2.0 * delta)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI/2.4, PI/2.4)

	# Dynamic gravity from celestial body (e.g. Moon = 1.62 m/s^2, Earth = 9.81 m/s^2)
	var grav_vec = calculate_gravity_vector()
	var g_magnitude = grav_vec.length()
	_gravity = g_magnitude
	
	# Apply gravity acceleration
	if not is_on_floor():
		velocity += grav_vec * delta

	# Handle Jetpack
	_is_jetpacking = false
	var jetpack_active = (Input.is_action_pressed("jetpack") or Input.is_action_pressed("jump")) and not is_on_floor()
	if jetpack_active and _jetpack_fuel > 0.0:
		_is_jetpacking = true
		# Upward direction opposing gravity
		var up_dir = -grav_vec.normalized() if g_magnitude > 0.01 else Vector3.UP
		velocity += up_dir * (JETPACK_FORCE * delta)
		_jetpack_fuel = max(0.0, _jetpack_fuel - JETPACK_DRAIN_RATE * delta)
		jetpack_fuel_changed.emit(_jetpack_fuel, JETPACK_MAX_FUEL)
	
	# Recharge Jetpack on floor
	if is_on_floor() and not Input.is_action_pressed("jump") and not Input.is_action_pressed("jetpack"):
		if _jetpack_fuel < JETPACK_MAX_FUEL:
			_jetpack_fuel = move_toward(_jetpack_fuel, JETPACK_MAX_FUEL, JETPACK_RECHARGE_RATE * delta)
			jetpack_fuel_changed.emit(_jetpack_fuel, JETPACK_MAX_FUEL)

	# Handle Jump (in lunar gravity, low gravity allows high buoyancy jumps)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		var up_dir = -grav_vec.normalized() if g_magnitude > 0.01 else Vector3.UP
		velocity += up_dir * JUMP_VELOCITY

	# Horizontal movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_basis = transform.basis
	var direction = (move_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = SPEED_WALK
	if Input.is_action_pressed("sprint"):
		current_speed = SPEED_SPRINT
		
	var horiz_accel = 20.0 if is_on_floor() else 4.0 # Less air authority in low gravity
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, horiz_accel * delta * current_speed)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, horiz_accel * delta * current_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, horiz_accel * delta * current_speed)
		velocity.z = move_toward(velocity.z, 0.0, horiz_accel * delta * current_speed)

	move_and_slide()

func calculate_gravity_vector() -> Vector3:
	if gravity_override != Vector3.ZERO:
		return gravity_override
		
	var universe_pos = _get_universe_pos()
	var tree = get_tree() if is_inside_tree() else null
	var sim_clock = tree.root.get_node_or_null("SimulationClock") if tree and tree.root else null
	var sim_time = sim_clock.sim_time_s if sim_clock and "sim_time_s" in sim_clock else 0.0
	
	# Query GravityService
	var grav_acc = GravityService.gravity_accel(universe_pos, sim_time)
	var grav_vec = grav_acc.to_vector3()
	if grav_vec.length() > 0.05:
		return grav_vec
		
	# Fallback to default gravity
	var default_g = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return Vector3(0.0, -default_g, 0.0)

func get_dominant_body_name() -> String:
	var universe_pos = _get_universe_pos()
	var tree = get_tree() if is_inside_tree() else null
	var sim_clock = tree.root.get_node_or_null("SimulationClock") if tree and tree.root else null
	var sim_time = sim_clock.sim_time_s if sim_clock and "sim_time_s" in sim_clock else 0.0
	return String(GravityService.dominant_body(universe_pos, sim_time))

func _get_universe_pos() -> DVec3:
	var tree = get_tree() if is_inside_tree() else null
	if tree and tree.root:
		var origin_svc = tree.root.get_node_or_null("OriginService")
		if origin_svc == null:
			origin_svc = tree.get_first_node_in_group("origin_service")
		if origin_svc and origin_svc.has_method("local_to_universe"):
			var pos = global_position if is_inside_tree() else position
			var up = origin_svc.local_to_universe(pos)
			return up.offset
	var pos = global_position if is_inside_tree() else position
	return DVec3.from_vector3(pos)
