extends RefCounted
class_name SolarSystemData

const G_CONST: float = 6.67430e-11

static func get_body_data(body_name: String) -> Dictionary:
	var def = BodyRegistry.get_body(body_name)
	if not def:
		return {}
	
	var r = {
		"mass": def.mass_kg,
		"radius": def.radius_m,
		"mu": def.mu_m3_s2,
		"parent": def.parent_id,
		"semi_major_axis": def.semi_major_axis_m,
		"eccentricity": def.eccentricity,
		"inclination_deg": def.inclination_deg,
		"orbital_period_days": 0.0,
		"rotation_period_hours": def.rotation_period_s / 3600.0,
		"surface_gravity": def.surface_gravity,
		"has_atmosphere": def.has_atmosphere,
		"atmosphere_color": def.atmosphere_color,
		"orbit_line_color": def.orbit_line_color,
		"soi_radius": 0.0,
		"surface_pressure_kpa": def.surface_pressure_pa / 1000.0,
		"scale_height_m": def.scale_height_m
	}
	return r
