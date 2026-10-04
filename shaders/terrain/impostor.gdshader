shader_type spatial;
render_mode depth_draw_opaque, cull_back, unshaded;

// Placeholder for octahedral impostor shader to save geometry budgets
uniform sampler2D impostor_albedo : source_color, filter_linear_mipmap;
uniform sampler2D impostor_normal : filter_linear_mipmap;
uniform float frames : hint_range(1.0, 64.0) = 16.0;

varying vec2 v_uv;

void vertex() {
	// Billboard logic: makes the impostor face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_uv = UV;
}

void fragment() {
	vec4 albedo = texture(impostor_albedo, v_uv);
	ALBEDO = albedo.rgb;
	
	// Alpha scissor for cutout
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
