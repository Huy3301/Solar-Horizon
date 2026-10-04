extends RigidBody3D
class_name RocketFlightController

signal stage_separated(stage_number: int)
signal rocket_telemetry_updated(data: Dictionary)
signal landing_legs_toggled(deployed: bool)

enum FlightPhase {
	PRE_LAUNCH,
	FIRST_STAGE_ASCENT,
	SECOND_STAGE_ORBITAL,
	COAST_IN_ORBIT,
	RETROGRADE_DEORBIT,
	BOOSTER_LANDING_BURN
}

@export_group("Stage 1 Booster Specs")
@export var stage_1_mass_dry: float = 28000.0
@export var stage_1_propellant_mass: float = 410000.0
@export var stage_1_thrust_sea_level: float = 7600000.0
@export var stage_1_thrust_vacuum: float = 8200000.0
@export var stage_1_burn_time: float = 162.0
@export var max_gimbal_angle_deg: float = 5.0

@export_group("Stage 2 Upper Stage Specs")
@export var stage_2_mass_dry: float = 4000.0
@export var stage_2_propellant_mass: float = 92000.0
@export var stage_2_thrust_vacuum: float = 981000.0
@export var stage_2_burn_time: float = 397.0

@export_group("Aerodynamics & Landing Legs")
@export var rocket_diameter: float = 3.7
@export var drag_coefficient_cd: float = 0.32
@export var landing_legs_deployed: bool = false
@export var leg_contact_ray_path: NodePath

var current_stage: int = 1
var current_phase: FlightPhase = FlightPhase.PRE_LAUNCH
var throttle: float = 0.0
var gimbal_pitch: float = 0.0
var gimbal_yaw: float = 0.0
var rcs_roll: float = 0.0

var s1_fuel: float
var s2_fuel: float
var mission_elapsed_time: float = 0.0

@onready var contact_ray: RayCast3D = get_node_or_null(leg_contact_ray_path)

func _ready() -> void:
	s1_fuel = stage_1_propellant_mass
	s2_fuel = stage_2_propellant_mass
	_update_total_mass()

func _update_total_mass() -> void:
	if current_stage == 1:
		mass = stage_1_mass_dry + s1_fuel + stage_2_mass_dry + s2_fuel
	else:
		mass = stage_2_mass_dry + s2_fuel

func _physics_process(delta: float) -> void:
	_handle_inputs(delta)
	
	if current_phase != FlightPhase.PRE_LAUNCH:
		mission_elapsed_time += delta
		_process_propulsion(delta)
		
	_process_aerodynamics()
	_update_total_mass()
	_broadcast_telemetry()

func _handle_inputs(_delta: float) -> void:
	gimbal_pitch = Input.get_axis("pitch_down", "pitch_up")
	gimbal_yaw = Input.get_axis("yaw_right", "yaw_left")
	rcs_roll = Input.get_axis("roll_right", "roll_left")
	
	if Input.is_action_pressed("throttle_up"):
		throttle = clamp(throttle + 0.4 * _delta, 0.0, 1.0)
	elif Input.is_action_pressed("throttle_down"):
		throttle = clamp(throttle - 0.4 * _delta, 0.0, 1.0)
		
	if Input.is_action_just_pressed("vtol_up") and current_phase == FlightPhase.PRE_LAUNCH:
		launch_rocket()
		
	if Input.is_action_just_pressed("toggle_gear"):
		toggle_landing_legs()

func launch_rocket() -> void:
	current_phase = FlightPhase.FIRST_STAGE_ASCENT
	throttle = 1.0

func trigger_stage_separation() -> void:
	if current_stage == 1:
		current_stage = 2
		current_phase = FlightPhase.SECOND_STAGE_ORBITAL
		stage_separated.emit(2)

func toggle_landing_legs() -> void:
	landing_legs_deployed = not landing_legs_deployed
	landing_legs_toggled.emit(landing_legs_deployed)

func _process_propulsion(delta: float) -> void:
	if throttle <= 0.001:
		return
		
	var thrust_mag: float = 0.0
	var altitude: float = max(0.0, global_position.y)
	var atm_ratio: float = clamp(exp(-altitude / 8500.0), 0.0, 1.0)
	
	if current_stage == 1:
		if s1_fuel > 0:
			var consumption_rate: float = (stage_1_propellant_mass / stage_1_burn_time) * throttle
			var fuel_used: float = min(consumption_rate * delta, s1_fuel)
			s1_fuel -= fuel_used
			var max_t: float = lerp(stage_1_thrust_vacuum, stage_1_thrust_sea_level, atm_ratio)
			thrust_mag = max_t * throttle
		else:
			trigger_stage_separation()
	elif current_stage == 2:
		if s2_fuel > 0:
			var consumption_rate: float = (stage_2_propellant_mass / stage_2_burn_time) * throttle
			var fuel_used: float = min(consumption_rate * delta, s2_fuel)
			s2_fuel -= fuel_used
			thrust_mag = stage_2_thrust_vacuum * throttle
			
	var gimbal_rad_p: float = deg_to_rad(gimbal_pitch * max_gimbal_angle_deg)
	var gimbal_rad_y: float = deg_to_rad(gimbal_yaw * max_gimbal_angle_deg)
	
	var thrust_dir_local: Vector3 = Vector3(
		sin(gimbal_rad_y),
		cos(gimbal_rad_p) * cos(gimbal_rad_y),
		-sin(gimbal_rad_p)
	).normalized()
	
	var thrust_force: Vector3 = global_transform.basis * (thrust_dir_local * thrust_mag)
	apply_central_force(thrust_force)
	
	var steering_torque: Vector3 = (
		global_transform.basis.x * (gimbal_pitch * 80000.0) +
		global_transform.basis.z * (gimbal_yaw * 80000.0) +
		global_transform.basis.y * (rcs_roll * 40000.0)
	)
	apply_torque(steering_torque)

func _process_aerodynamics() -> void:
	var vel: Vector3 = linear_velocity
	var speed: float = vel.length()
	if speed < 1.0:
		return
		
	var altitude: float = max(0.0, global_position.y)
	if altitude > 90000.0:
		return
		
	var density: float = 1.225 * exp(-altitude / 8500.0)
	var cross_section_area: float = PI * pow(rocket_diameter * 0.5, 2.0)
	var q: float = 0.5 * density * speed * speed
	
	var drag_force_mag: float = drag_coefficient_cd * q * cross_section_area
	var drag_force: Vector3 = -vel.normalized() * drag_force_mag
	apply_central_force(drag_force)

func _broadcast_telemetry() -> void:
	var vel: Vector3 = linear_velocity
	var alt: float = max(0.0, global_position.y)
	var speed: float = vel.length()
	
	var telemetry: Dictionary = {
		"stage": current_stage,
		"phase": current_phase,
		"mission_time": mission_elapsed_time,
		"altitude_m": alt,
		"speed_ms": speed,
		"vspeed_ms": vel.y,
		"throttle_pct": throttle * 100.0,
		"s1_propellant_pct": (s1_fuel / stage_1_propellant_mass) * 100.0,
		"s2_propellant_pct": (s2_fuel / stage_2_propellant_mass) * 100.0,
		"total_mass_kg": mass,
		"legs_deployed": landing_legs_deployed
	}
	rocket_telemetry_updated.emit(telemetry)
