class_name TestAASettings
extends TestCase

func test_anti_aliasing_and_debanding_settings() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d"), 2, "4x MSAA configured for 3D")
	assert_eq(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding"), true, "Debanding enabled for color gradients")
	assert_eq(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa"), 1, "FXAA enabled for screen space AA")
	assert_eq(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa"), true, "TAA enabled for temporal stability")
