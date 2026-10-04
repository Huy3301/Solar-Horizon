class_name OnFootRig extends CharacterBody3D

const SPEED_WALK = 4.0
const SPEED_SPRINT = 7.0
const JUMP_VELOCITY = 4.5
const JETPACK_FORCE = 15.0
const JETPACK_MAX_FUEL = 100.0
const JETPACK_DRAIN_RATE = 20.0
const JETPACK_RECHARGE_RATE = 10.0

@export var mouse_sensitivity: float = 0.002

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _jetpack_fuel: float = JETPACK_MAX_FUEL
var _is_jetpacking: bool = false

var head: Node3D
var camera: Camera3D

func _ready() -> void:
	head = Node3D.new()
	add_child(head)
	head.position = Vector3(0, 1.6, 0)
	
	camera = Camera3D.new()
	head.add_child(camera)
	
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	collision.position = Vector3(0, 0.9, 0)
	add_child(collision)
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Attempt to register with OriginService if it exists
	var origin_service = get_tree().root.get_node_or_null("OriginService")
	if origin_service and origin_service.has_method("register"):
		origin_service.register(self)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, -PI/2.5, PI/2.5)

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Handle Jetpack
	_is_jetpacking = false
	var jetpack_active = (Input.is_action_pressed("jetpack") or Input.is_action_pressed("jump")) and not is_on_floor()
	if jetpack_active and _jetpack_fuel > 0:
		_is_jetpacking = true
		velocity.y += JETPACK_FORCE * delta
		_jetpack_fuel -= JETPACK_DRAIN_RATE * delta
	
	# Recharge Jetpack
	if is_on_floor() and not Input.is_action_pressed("jump") and not Input.is_action_pressed("jetpack"):
		_jetpack_fuel = move_toward(_jetpack_fuel, JETPACK_MAX_FUEL, JETPACK_RECHARGE_RATE * delta)

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = SPEED_WALK
	if Input.is_action_pressed("sprint"):
		current_speed = SPEED_SPRINT
		
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
