extends SceneTree

func _init():
	var bodies = [
		{"id": "Sun", "parent": "", "type": 0, "mass": 1.9885e30, "mu": 1.32712440018e20, "r": 696340000.0, "rot": 609.12*3600, "g": 274.0, "atm": true, "p": 0.0, "h": 0.0, "col": Color(1.0, 0.85, 0.4, 0.9), "orb": Color(1.0, 0.9, 0.2, 0.8), "a": 0.0, "e": 0.0, "i": 0.0, "omega": 0.0, "w": 0.0, "m0": 0.0},
		{"id": "Mercury", "parent": "Sun", "type": 1, "mass": 3.3011e23, "mu": 2.2032e13, "r": 2439700.0, "rot": 1407.6*3600, "g": 3.7, "atm": false, "p": 0.0, "h": 0.0, "col": Color.TRANSPARENT, "orb": Color(0.75, 0.7, 0.65, 0.7), "a": 57909050000.0, "e": 0.20563593, "i": 7.00497902, "omega": 48.33076593, "w": 29.12703035, "m0": 174.79252722},
		{"id": "Venus", "parent": "Sun", "type": 1, "mass": 4.8675e24, "mu": 3.24859e14, "r": 6051800.0, "rot": -5832.5*3600, "g": 8.87, "atm": true, "p": 9300000.0, "h": 15900.0, "col": Color(0.9, 0.8, 0.5, 0.85), "orb": Color(0.95, 0.75, 0.35, 0.75), "a": 108208000000.0, "e": 0.00677672, "i": 3.39467605, "omega": 76.67984255, "w": 54.92262463, "m0": 50.37663232},
		{"id": "Earth", "parent": "Sun", "type": 1, "mass": 5.9722e24, "mu": 3.986004418e14, "r": 6371000.0, "rot": 23.934*3600, "g": 9.807, "atm": true, "p": 101325.0, "h": 8500.0, "col": Color(0.35, 0.65, 0.95, 0.8), "orb": Color(0.2, 0.6, 1.0, 0.8), "a": 149598023000.0, "e": 0.01671123, "i": -0.00001531, "omega": 0.0, "w": 102.93768193, "m0": -2.47311027},
		{"id": "Moon", "parent": "Earth", "type": 2, "mass": 7.342e22, "mu": 4.9048695e12, "r": 1737400.0, "rot": 655.7*3600, "g": 1.62, "atm": false, "p": 0.0, "h": 0.0, "col": Color.TRANSPARENT, "orb": Color(0.85, 0.88, 0.92, 0.75), "a": 384400000.0, "e": 0.0549, "i": 5.145, "omega": 0.0, "w": 0.0, "m0": 0.0},
		{"id": "Mars", "parent": "Sun", "type": 1, "mass": 6.4171e23, "mu": 4.282837e13, "r": 3389500.0, "rot": 24.623*3600, "g": 3.72, "atm": true, "p": 636.0, "h": 11100.0, "col": Color(0.85, 0.45, 0.3, 0.5), "orb": Color(0.95, 0.4, 0.25, 0.8), "a": 227939200000.0, "e": 0.09339410, "i": 1.84969142, "omega": 49.55953891, "w": -73.5031685, "m0": 19.39019754},
		{"id": "Jupiter", "parent": "Sun", "type": 3, "mass": 1.8982e27, "mu": 1.26686534e17, "r": 69911000.0, "rot": 9.925*3600, "g": 24.79, "atm": true, "p": 0.0, "h": 0.0, "col": Color(0.85, 0.7, 0.55, 0.7), "orb": Color(0.85, 0.65, 0.4, 0.8), "a": 778570000000.0, "e": 0.04838624, "i": 1.30439695, "omega": 100.47390909, "w": -85.74542926, "m0": 19.66796068},
		{"id": "Europa", "parent": "Jupiter", "type": 2, "mass": 4.8e22, "mu": 3.2027e12, "r": 1560800.0, "rot": 85.2*3600, "g": 1.315, "atm": false, "p": 0.0, "h": 0.0, "col": Color.TRANSPARENT, "orb": Color(0.7, 0.85, 0.95, 0.8), "a": 670900000.0, "e": 0.009, "i": 0.47, "omega": 0.0, "w": 0.0, "m0": 0.0},
		{"id": "Saturn", "parent": "Sun", "type": 3, "mass": 5.6834e26, "mu": 3.7931187e16, "r": 58232000.0, "rot": 10.656*3600, "g": 10.44, "atm": true, "p": 0.0, "h": 0.0, "col": Color(0.9, 0.85, 0.6, 0.6), "orb": Color(0.9, 0.8, 0.5, 0.8), "a": 1433530000000.0, "e": 0.05386179, "i": 2.48599187, "omega": 113.66242448, "w": -21.06954976, "m0": -42.63863049},
		{"id": "Titan", "parent": "Saturn", "type": 2, "mass": 1.3452e23, "mu": 8.97813e12, "r": 2574700.0, "rot": 382.7*3600, "g": 1.352, "atm": true, "p": 146700.0, "h": 21000.0, "col": Color(0.95, 0.65, 0.2, 0.85), "orb": Color(0.95, 0.7, 0.25, 0.8), "a": 1221870000.0, "e": 0.0288, "i": 0.348, "omega": 0.0, "w": 0.0, "m0": 0.0}
	]
	for b in bodies:
		var def = CelestialBodyDef.new()
		def.id = b["id"]
		def.display_name = b["id"]
		def.parent_id = b["parent"]
		def.body_type = b["type"]
		def.mass_kg = b["mass"]
		def.mu_m3_s2 = b["mu"]
		def.radius_m = b["r"]
		def.rotation_period_s = b["rot"]
		def.surface_gravity = b["g"]
		def.has_atmosphere = b["atm"]
		def.surface_pressure_pa = b["p"]
		def.scale_height_m = b["h"]
		def.atmosphere_color = b["col"]
		def.orbit_line_color = b["orb"]
		def.semi_major_axis_m = b["a"]
		def.eccentricity = b["e"]
		def.inclination_deg = b["i"]
		def.longitude_ascending_node_deg = b["omega"]
		def.argument_periapsis_deg = b["w"]
		def.mean_anomaly_at_epoch_deg = b["m0"]
		def.epoch_jd = 2451545.0
		ResourceSaver.save(def, "res://game/universe/data/bodies/" + str(b["id"]).to_lower() + ".tres")
	quit()
