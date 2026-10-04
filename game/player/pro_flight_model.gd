class_name ProFlightModel extends Node
## Advanced "Pro Flight" certification mechanics including aerodynamic drag and re-entry heating.

@export var ship_mass: float = 10000.0
@export var drag_coefficient: float = 0.5
@export var cross_section_area: float = 20.0
@export var max_heat_tolerance: float = 10000.0
@export var heat_dissipation_rate: float = 500.0

var current_heat: float = 0.0

signal hull_damage_taken(amount: float)

## Computes atmospheric density given a CelestialBodyDef and current altitude
func get_atmospheric_density(body_def: CelestialBodyDef, altitude_m: float) -> float:
	if not body_def or not body_def.has_atmosphere:
		return 0.0
	
	var rho0 = body_def.surface_pressure_pa * 1.225 / 101325.0
	var scale_height = body_def.scale_height_m
	if scale_height <= 0:
		scale_height = 8000.0 # fallback
		
	if altitude_m < 0:
		return rho0
	
	return rho0 * exp(-altitude_m / scale_height)

## Apply drag and heating given a velocity vector (in m/s relative to the body)
func process_flight(body_def: CelestialBodyDef, altitude_m: float, velocity_relative: Vector3, delta: float) -> Vector3:
	var density = get_atmospheric_density(body_def, altitude_m)
	if density <= 0.0001:
		current_heat = max(0.0, current_heat - heat_dissipation_rate * delta)
		return Vector3.ZERO # No drag acceleration
	
	var speed = velocity_relative.length()
	if speed < 0.1:
		return Vector3.ZERO
		
	# Drag = 1/2 * rho * v^2 * Cd * A
	var drag_force_mag = 0.5 * density * speed * speed * drag_coefficient * cross_section_area
	var drag_accel_mag = drag_force_mag / ship_mass
	
	var drag_accel = -velocity_relative.normalized() * drag_accel_mag
	
	# Heating is roughly proportional to rho * v^3
	# Calibrate scaling factor so typical re-entry generates heat
	var heating_rate = 1e-4 * density * pow(speed, 3.0)
	current_heat += (heating_rate - heat_dissipation_rate) * delta
	current_heat = max(0.0, current_heat)
	
	if current_heat > max_heat_tolerance:
		var overage = current_heat - max_heat_tolerance
		emit_signal("hull_damage_taken", overage * delta * 0.1)
		
	return drag_accel
