class_name TestSettingsGraphics
extends TestCase

const SETTINGS_SCENE_PATH = "res://game/ui/settings_menu.tscn"
const SETTINGS_FILE_PATH = "user://settings.cfg"

var _backup_content: PackedByteArray = PackedByteArray()
var _had_backup: bool = false

func _save_backup() -> void:
	if FileAccess.file_exists(SETTINGS_FILE_PATH):
		var f = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
		if f:
			_backup_content = f.get_buffer(f.get_length())
			_had_backup = true
	else:
		_had_backup = false
		_backup_content.clear()

func _restore_backup() -> void:
	if _had_backup:
		var f = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_backup_content)
	else:
		if FileAccess.file_exists(SETTINGS_FILE_PATH):
			DirAccess.remove_absolute(SETTINGS_FILE_PATH)

func test_settings_ui_elements_and_options() -> void:
	var scene = load(SETTINGS_SCENE_PATH) as PackedScene
	assert_true(scene != null, "settings_menu.tscn loads")

	var menu = scene.instantiate()
	assert_true(menu != null, "settings_menu instantiates")
	menu.target_viewport = tree.root
	menu.scene_tree = tree
	menu._ready()

	assert_true(menu.aa_option != null, "AA option button exists")
	assert_eq(menu.aa_option.item_count, 5, "AA option button has 5 choices")
	assert_eq(menu.aa_option.get_item_text(0), "Disabled", "AA item 0 is Disabled")
	assert_eq(menu.aa_option.get_item_text(1), "FXAA", "AA item 1 is FXAA")
	assert_eq(menu.aa_option.get_item_text(2), "2x MSAA", "AA item 2 is 2x MSAA")
	assert_eq(menu.aa_option.get_item_text(3), "4x MSAA", "AA item 3 is 4x MSAA")
	assert_eq(menu.aa_option.get_item_text(4), "TAA", "AA item 4 is TAA")

	assert_true(menu.debanding_check != null, "Debanding check box exists")
	assert_true(menu.debanding_check.text.contains("Color Debanding"), "Debanding check box has correct label")

	assert_true(menu.res_slider != null, "Resolution scale slider exists")
	assert_almost_eq(menu.res_slider.min_value, 0.5, 1e-4, "Resolution scale min is 0.5")
	assert_almost_eq(menu.res_slider.max_value, 1.0, 1e-4, "Resolution scale max is 1.0")

	assert_true(menu.quality_option != null, "Quality preset option button exists")
	assert_eq(menu.quality_option.item_count, 4, "Quality preset has 4 choices")
	assert_eq(menu.quality_option.get_item_text(0), "Desktop High", "Quality preset item 0 is Desktop High")
	assert_eq(menu.quality_option.get_item_text(1), "Desktop Balanced", "Quality preset item 1 is Desktop Balanced")
	assert_eq(menu.quality_option.get_item_text(2), "Mobile 60 FPS", "Quality preset item 2 is Mobile 60 FPS")
	assert_eq(menu.quality_option.get_item_text(3), "Battery Saver 30 FPS", "Quality preset item 3 is Battery Saver 30 FPS")

	menu.free()

func test_aa_mode_updates_viewport() -> void:
	var scene = load(SETTINGS_SCENE_PATH) as PackedScene
	var menu = scene.instantiate()
	menu.target_viewport = tree.root
	menu.scene_tree = tree
	menu._ready()

	var vp = menu._get_target_viewport()
	assert_true(vp != null, "Viewport is accessible")

	# Mode 0: Disabled -> screen_space_aa = 0, msaa_3d = 0, use_taa = false
	menu.set_aa_mode(0)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "AA Mode 0: screen_space_aa is 0 (Disabled)")
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "AA Mode 0: msaa_3d is 0 (Disabled)")
	assert_false(vp.use_taa, "AA Mode 0: use_taa is false")

	# Mode 1: FXAA -> screen_space_aa = 1, msaa_3d = 0, use_taa = false
	menu.set_aa_mode(1)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "AA Mode 1: screen_space_aa is 1 (FXAA)")
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "AA Mode 1: msaa_3d is 0 (Disabled)")
	assert_false(vp.use_taa, "AA Mode 1: use_taa is false")

	# Mode 2: 2x MSAA -> screen_space_aa = 0, msaa_3d = 1, use_taa = false
	menu.set_aa_mode(2)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "AA Mode 2: screen_space_aa is 0 (Disabled)")
	assert_eq(vp.msaa_3d, Viewport.MSAA_2X, "AA Mode 2: msaa_3d is 1 (2x MSAA)")
	assert_false(vp.use_taa, "AA Mode 2: use_taa is false")

	# Mode 3: 4x MSAA -> screen_space_aa = 0, msaa_3d = 2, use_taa = false
	menu.set_aa_mode(3)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "AA Mode 3: screen_space_aa is 0 (Disabled)")
	assert_eq(vp.msaa_3d, Viewport.MSAA_4X, "AA Mode 3: msaa_3d is 2 (4x MSAA)")
	assert_false(vp.use_taa, "AA Mode 3: use_taa is false")

	# Mode 4: TAA -> screen_space_aa = 1, msaa_3d = 0, use_taa = true
	menu.set_aa_mode(4)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "AA Mode 4: screen_space_aa is 1 (FXAA)")
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "AA Mode 4: msaa_3d is 0 (Disabled)")
	assert_true(vp.use_taa, "AA Mode 4: use_taa is true")

	# Test signal emission triggers handler
	menu.aa_option.item_selected.emit(1)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "AA item_selected signal updates Viewport")

	menu.free()

func test_debanding_updates_viewport() -> void:
	var scene = load(SETTINGS_SCENE_PATH) as PackedScene
	var menu = scene.instantiate()
	menu.target_viewport = tree.root
	menu.scene_tree = tree
	menu._ready()

	var vp = menu._get_target_viewport()
	assert_true(vp != null, "Viewport is accessible")

	menu.set_debanding(true)
	assert_true(vp.use_debanding, "Viewport use_debanding enabled")

	menu.set_debanding(false)
	assert_false(vp.use_debanding, "Viewport use_debanding disabled")

	# Test checkbox toggled signal
	menu.debanding_check.button_pressed = true
	menu.debanding_check.toggled.emit(true)
	assert_true(vp.use_debanding, "Debanding toggled signal enables debanding on Viewport")

	menu.free()

func test_resolution_scale_updates_viewport() -> void:
	var scene = load(SETTINGS_SCENE_PATH) as PackedScene
	var menu = scene.instantiate()
	menu.target_viewport = tree.root
	menu.scene_tree = tree
	menu._ready()

	var vp = menu._get_target_viewport()
	assert_true(vp != null, "Viewport is accessible")

	menu.set_resolution_scale(0.75)
	assert_almost_eq(vp.scaling_3d_scale, 0.75, 1e-4, "Viewport scaling_3d_scale is 0.75")

	menu.set_resolution_scale(0.5)
	assert_almost_eq(vp.scaling_3d_scale, 0.5, 1e-4, "Viewport scaling_3d_scale is 0.5")

	menu.res_slider.value = 0.9
	menu.res_slider.value_changed.emit(0.9)
	assert_almost_eq(vp.scaling_3d_scale, 0.9, 1e-4, "Slider value_changed signal updates scaling_3d_scale")

	menu.free()

func test_quality_preset_notification() -> void:
	var governor_script = preload("res://game/autoload/quality_governor.gd")
	var governor = governor_script.new()
	governor.name = "QualityGovernor"
	tree.root.add_child(governor)

	var scene = load(SETTINGS_SCENE_PATH) as PackedScene
	var menu = scene.instantiate()
	menu.target_viewport = tree.root
	menu.scene_tree = tree
	menu._ready()

	# Preset 3: Battery Saver 30 FPS
	menu.set_quality_preset(3)
	assert_eq(governor.current_preset, "battery_saver", "Battery saver preset applied to QualityGovernor")
	assert_almost_eq(governor.target_fps, 30.0, 1e-4, "Target FPS is 30 for battery saver")

	# Preset 2: Mobile 60 FPS
	menu.set_quality_preset(2)
	assert_eq(governor.current_preset, "performance", "Performance preset applied to QualityGovernor")
	assert_almost_eq(governor.target_fps, 60.0, 1e-4, "Target FPS is 60 for mobile 60")

	# Preset 0: Desktop High
	menu.set_quality_preset(0)
	assert_eq(governor.current_preset, "desktop_high", "Desktop high preset notified")
	assert_almost_eq(governor.max_fsr_scale, 1.0, 1e-4, "Max FSR scale is 1.0 for desktop high")

	# Preset 1: Desktop Balanced
	menu.set_quality_preset(1)
	assert_eq(governor.current_preset, "desktop_balanced", "Desktop balanced preset notified")
	assert_almost_eq(governor.max_fsr_scale, 0.85, 1e-4, "Max FSR scale is 0.85 for desktop balanced")

	menu.free()
	tree.root.remove_child(governor)
	governor.free()

func test_persistence_roundtrip() -> void:
	_save_backup()

	var scene = load(SETTINGS_SCENE_PATH) as PackedScene
	var menu1 = scene.instantiate()
	menu1.target_viewport = tree.root
	menu1.scene_tree = tree
	menu1._ready()

	# Configure non-default graphics settings
	menu1.set_aa_mode(3) # 4x MSAA
	menu1.set_debanding(true)
	menu1.set_resolution_scale(0.85)
	menu1.set_quality_preset(1) # Desktop Balanced

	# Verify file on disk
	assert_true(FileAccess.file_exists(SETTINGS_FILE_PATH), "settings.cfg file created")
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)
	assert_eq(err, OK, "settings.cfg loads without error")
	assert_eq(config.get_value("graphics", "aa_mode"), 3, "persisted aa_mode is 3")
	assert_eq(config.get_value("graphics", "debanding"), true, "persisted debanding is true")
	assert_almost_eq(config.get_value("graphics", "resolution_scale"), 0.85, 1e-4, "persisted resolution_scale is 0.85")
	assert_eq(config.get_value("graphics", "quality_preset"), 1, "persisted quality_preset is 1")

	menu1.free()

	# Instantiate a fresh menu and verify it loads the saved settings
	var menu2 = scene.instantiate()
	menu2.target_viewport = tree.root
	menu2.scene_tree = tree
	menu2._ready()

	assert_eq(menu2.aa_option.selected, 3, "Loaded aa_option.selected is 3 (4x MSAA)")
	assert_true(menu2.debanding_check.button_pressed, "Loaded debanding_check is true")
	assert_almost_eq(menu2.res_slider.value, 0.85, 1e-4, "Loaded res_slider is 0.85")
	assert_eq(menu2.quality_option.selected, 1, "Loaded quality_option is 1 (Desktop Balanced)")

	var vp = menu2._get_target_viewport()
	assert_true(vp != null, "Viewport accessible on menu2")
	assert_eq(vp.msaa_3d, Viewport.MSAA_4X, "Viewport has 4x MSAA applied from loaded settings")
	assert_true(vp.use_debanding, "Viewport has debanding applied from loaded settings")
	assert_almost_eq(vp.scaling_3d_scale, 0.85, 1e-4, "Viewport has scaling_3d_scale applied from loaded settings")

	menu2.free()

	_restore_backup()
