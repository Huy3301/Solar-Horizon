extends "res://tests/test_case.gd"

const TutorialDirectorScript = preload("res://game/tutorial/tutorial_director.gd")

class MockTutorialShip extends RigidBody3D:
	var is_crashed: bool = false
	var is_landed: bool = true
	var current_throttle: float = 0.5
	var landing_gear_deployed: bool = false

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
