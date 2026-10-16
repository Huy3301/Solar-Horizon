extends Node
## Visual smoke capture: runs main.tscn under a real renderer and saves PNGs of key moments.
## Works on a CI box with NO GPU using software Vulkan (Mesa lavapipe) + a virtual display:
##   sudo apt-get install -y xvfb mesa-vulkan-drivers libvulkan1
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##   xvfb-run -a -s "-screen 0 960x540x24" godot --rendering-driver vulkan --resolution 960x540 \
##       --path . res://tools/visual/capture_shots.tscn
## Output: user://shots/*.png  (also printed as "SHOT <name>"). Software rendering runs at ~1-2 fps, so
## this checks what things LOOK like (geometry, sky, UI, VFX), not performance.

const OUT_DIR := "user://shots"

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("SHOT ", shot_name)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var w = load("res://scenes/main.tscn").instantiate()
	add_child(w)
	var ship: RigidBody3D = w.get_node("Ship")
	await _frames(100)
	await _shot("01_spawn")
	Input.action_press("throttle_up")
	while float(ship.telemetry_data.get("altitude_agl_m", 0.0)) < 80.0:
		await get_tree().physics_frame
	await _shot("02_takeoff_80m")
	Input.action_release("throttle_up")
	get_tree().quit()
