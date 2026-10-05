extends "res://tests/test_case.gd"

const TutorialDirectorScript = preload("res://game/tutorial/tutorial_director.gd")

class MockTutorialShip extends RigidBody3D:
	var is_crashed: bool = false
	var is_landed: bool = true
	var current_throttle: float = 0.5
	var landing_gear_deployed: bool = false
	var telemetry_data: Dictionary = {}

func test_tutorial_initial_steps() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	td._init_steps()
	
	assert_eq(td.steps.size(), 6, "Tutorial defines 6 mission steps from Adelaide to Moon and return")
	assert_eq(td.steps[0]["id"], "adelaide_launch", "Step 0 is Adelaide Launch")
	assert_eq(td.steps[1]["id"], "achieve_orbit", "Step 1 is Achieve Orbit")
	assert_eq(td.steps[2]["id"], "moon_landing", "Step 2 is Moon Landing")
	assert_eq(td.steps[3]["id"], "eva_exit", "Step 3 is EVA Exit")
	assert_eq(td.steps[4]["id"], "scan_sample", "Step 4 is Scan Sample")
	assert_eq(td.steps[5]["id"], "return_to_ship", "Step 5 is Return to Ship")
	
	td.free()

func test_tutorial_step_progression() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	td._init_steps()
	td.start_tutorial()
	
	assert_eq(td.get_current_step_index(), 0, "Starts at step 0")
	var step0 = td.get_current_step()
	assert_eq(step0.get("id", ""), "adelaide_launch", "Current step is launch")
	
	var completed_steps = []
	td.step_completed.connect(func(idx, step_id): completed_steps.append(step_id))
	
	td.advance_step() # to orbit
	assert_eq(td.get_current_step_index(), 1, "Advanced to step 1")
	assert_eq(completed_steps.size(), 1, "Recorded 1 completed step")
	assert_eq(completed_steps[0], "adelaide_launch", "Recorded adelaide_launch completion")
	
	td.advance_step() # to landing
	td.advance_step() # to eva
	assert_eq(td.get_current_step_index(), 3, "Advanced to step 3 (EVA)")
	
	# Trigger EVA exit signal
	td._on_exited_ship(null, Vector3.ZERO)
	assert_eq(td.get_current_step_index(), 4, "Advanced to step 4 (Scan) via EVA signal")
	
	# Trigger Scan completion signal
	td._on_scan_completed()
	assert_eq(td.get_current_step_index(), 5, "Advanced to step 5 (Return) via scan signal")
	
	# Trigger Return to ship
	td._on_entered_ship(null)
	assert_eq(td.get_current_step_index(), 6, "Tutorial finished")
	
	td.free()

func test_tutorial_failure_and_respawn_at_base() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	td._init_steps()
	td.adelaide_base_pos = Vector3(500.0, 10.0, -200.0)
	
	var ship = MockTutorialShip.new()
	ship.position = Vector3(9999.0, 50000.0, 9999.0)
	ship.is_crashed = true
	ship.current_throttle = 1.0
	td.ship = ship
	
	td.start_tutorial()
	td.advance_step()
	td.advance_step()
	assert_eq(td.get_current_step_index(), 2, "Progressed to step 2")
	
	var failure_reported = [false]
	var respawn_reported = [false]
	td.mission_failed.connect(func(_r): failure_reported[0] = true)
	td.respawned_at_base.connect(func(): respawn_reported[0] = true)
	
	td.fail_mission("Vessel impact with terrain")
	
	assert_true(failure_reported[0], "Mission failure signal emitted")
	assert_true(respawn_reported[0], "Respawned at base signal emitted")
	assert_eq(td.get_current_step_index(), 0, "Tutorial step reset to step 0 after respawn")
	assert_eq(ship.position, td.adelaide_base_pos, "Ship moved back to Adelaide Base")
	assert_false(ship.is_crashed, "Ship crash flag cleared")
	assert_eq(ship.current_throttle, 0.0, "Ship throttle reset to zero")
	assert_true(ship.is_landed, "Ship marked as landed at base")
	
	td.free()
	ship.free()

func test_orbital_start_scenario_when_in_orbit() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	td.start_scenario = "orbit"
	
	var ship = MockTutorialShip.new()
	ship.telemetry_data = {
		"altitude_agl_m": 120000.0, # 120 km > 100 km
		"speed_ms": 2200.0,         # 2200 m/s > 2000 m/s
	}
	td.ship = ship
	
	var completed = []
	td.step_completed.connect(func(idx, id): completed.append({"index": idx, "id": id}))
	
	td.start_tutorial()
	
	assert_eq(td.get_current_step_index(), 2, "Orbital start scenario jumps directly to moon_landing (step 2)")
	assert_eq(td.get_current_step().get("id", ""), "moon_landing", "Current step is moon_landing")
	assert_eq(completed.size(), 2, "Steps 0 and 1 marked completed")
	if completed.size() >= 2:
		assert_eq(completed[0]["index"], 0, "First completed is step 0")
		assert_eq(completed[0]["id"], "adelaide_launch", "Step 0 id is adelaide_launch")
		assert_eq(completed[1]["index"], 1, "Second completed is step 1")
		assert_eq(completed[1]["id"], "achieve_orbit", "Step 1 id is achieve_orbit")
	
	td.free()
	ship.free()

func test_adelaide_launch_scenario_not_completed_at_spawn() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	td.start_scenario = "adelaide"
	
	var ship = MockTutorialShip.new()
	ship.telemetry_data = {
		"altitude_agl_m": 0.0,
		"speed_ms": 0.0,
		"vspeed_ms": 0.0,
		"is_landed": true,
	}
	td.ship = ship
	
	var completed = []
	td.step_completed.connect(func(_idx, id): completed.append(id))
	
	td.start_tutorial()
	
	assert_eq(td.get_current_step_index(), 0, "Starts at step 0 for Adelaide scenario")
	assert_eq(completed.size(), 0, "No steps completed on launch pad")
	assert_false(td._check_launch(), "Launch condition is false at spawn on launch pad")
	assert_false(td._check_orbit(), "Orbit condition is false at spawn on launch pad")
	
	# Verify stationary at high altitude does NOT trigger launch step
	ship.telemetry_data["altitude_agl_m"] = 30000.0
	ship.telemetry_data["vspeed_ms"] = 0.0 # Stationary
	assert_false(td._check_launch(), "Stationary ship at high altitude does not trigger launch step")
	
	# Verify ascending with sufficient vertical speed does trigger launch step
	ship.telemetry_data["altitude_agl_m"] = 26000.0
	ship.telemetry_data["vspeed_ms"] = 150.0
	assert_true(td._check_launch(), "Ascending ship with vspeed > 100 m/s triggers launch step")
	
	# Test start_scenario == "orbit" when ship is still on pad does NOT jump to orbit
	var td2 = TutorialDirectorScript.new()
	td2.auto_start = false
	td2.start_scenario = "orbit"
	ship.telemetry_data["altitude_agl_m"] = 0.0
	ship.telemetry_data["speed_ms"] = 0.0
	ship.telemetry_data["vspeed_ms"] = 0.0
	td2.ship = ship
	var completed2 = []
	td2.step_completed.connect(func(_idx, id): completed2.append(id))
	td2.start_tutorial()
	assert_eq(td2.get_current_step_index(), 0, "Orbital scenario stays at step 0 if ship is on launch pad")
	assert_eq(completed2.size(), 0, "No steps completed when not in orbit")
	
	td.free()
	td2.free()
	ship.free()

func test_step_1_prompt_throttle_up_not_shift() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	td._init_steps()
	
	var step1 = td.steps[0]
	var instruction = step1.get("instruction", "")
	assert_true(instruction.contains("Throttle Up"), "Step 1 prompt refers to Throttle Up")
	assert_false(instruction.contains("[Shift]"), "Step 1 prompt does NOT refer to Shift (which is boost)")
	assert_true(instruction.contains("Up Arrow") or instruction.contains("R2") or instruction.contains("Up"), "Step 1 prompt includes Up Arrow or R2")
	
	# Dynamic action lookup tests
	var prompt_custom = TutorialDirectorScript.get_action_key_prompt("throttle_up", "[Up Arrow / R2]")
	assert_false(prompt_custom.contains("Shift"), "Throttle up lookup does not contain Shift")
	assert_true(prompt_custom.contains("Up Arrow") or prompt_custom.contains("Up"), "Throttle up lookup formats key")
	
	var fallback_prompt = TutorialDirectorScript.get_action_key_prompt("nonexistent_action_xyz", "[Fallback]")
	assert_eq(fallback_prompt, "[Fallback]", "Fallback returned for unmapped actions")
	
	td.free()

func test_check_orbit_calibrated_threshold() -> void:
	var td = TutorialDirectorScript.new()
	td.auto_start = false
	var ship = MockTutorialShip.new()
	td.ship = ship
	
	# Below 2100 m/s and pe <= 75 km -> false
	ship.telemetry_data = {"pe_km": 50.0, "speed_ms": 2000.0}
	assert_false(td._check_orbit(), "Orbit check false below 2100 m/s")
	
	# Above 2100 m/s (1:10 scale LEO threshold) -> true
	ship.telemetry_data = {"pe_km": 50.0, "speed_ms": 2150.0}
	assert_true(td._check_orbit(), "Orbit check true at 2150 m/s (1:10 LEO threshold)")
	
	# pe > 75 km -> true
	ship.telemetry_data = {"pe_km": 80.0, "speed_ms": 1500.0}
	assert_true(td._check_orbit(), "Orbit check true when periapsis > 75 km")
	
	td.free()
	ship.free()

