class_name CelestialBodyDef extends Resource

enum BodyType { STAR, PLANET, MOON, GAS_GIANT }

@export var id: StringName
@export var display_name: String
@export var parent_id: StringName
@export var body_type: BodyType = BodyType.PLANET
@export var mass_kg: float
@export var mu_m3_s2: float
@export var radius_m: float
@export var rotation_period_s: float
@export var axial_tilt_deg: float
@export var surface_gravity: float

@export var has_atmosphere: bool = false
@export var surface_pressure_pa: float
@export var scale_height_m: float
@export var atmosphere_color: Color
@export var orbit_line_color: Color

@export var semi_major_axis_m: float
@export var eccentricity: float
@export var inclination_deg: float
@export var longitude_ascending_node_deg: float
@export var argument_periapsis_deg: float
@export var mean_anomaly_at_epoch_deg: float
@export var epoch_jd: float = 2451545.0
