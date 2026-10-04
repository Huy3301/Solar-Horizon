class_name FloraSpawner
extends ScatterSystem
## Procedural Flora v2 scatter system.
## Expands base scatter logic by supporting biome masks and diverse flora types with vertex-wind.

@export var biome_mask_texture: Texture2D
@export var wind_strength: float = 0.5
@export var wind_speed: float = 2.0

func _ready() -> void:
	super._ready()
	_setup_flora_materials()

func _setup_flora_materials() -> void:
	if not multimesh_instance or not multimesh_instance.multimesh:
		return
		
	# Create diverse flora types by assigning a ShaderMaterial with vertex-wind
	var flora_shader = _create_flora_shader()
	var material = ShaderMaterial.new()
	material.shader = flora_shader
	material.set_shader_parameter("wind_strength", wind_strength)
	material.set_shader_parameter("wind_speed", wind_speed)
	
	if biome_mask_texture:
		material.set_shader_parameter("biome_mask", biome_mask_texture)
		
	# Assuming a basic quad or custom mesh, assign the material
	if not multimesh_instance.multimesh.mesh:
		var quad = QuadMesh.new()
		quad.size = Vector2(1.0, 2.0)
		# Pivot at bottom
		quad.center_offset = Vector3(0.0, 1.0, 0.0) 
		multimesh_instance.multimesh.mesh = quad
		
	multimesh_instance.multimesh.mesh.surface_set_material(0, material)

func _create_flora_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode cull_disabled, depth_draw_opaque;
	
	uniform sampler2D biome_mask;
	uniform float wind_strength = 0.5;
	uniform float wind_speed = 2.0;
	
	void vertex() {
		// Basic vertex wind displacement
		// Height factor so roots don't move
		float height_factor = max(0.0, VERTEX.y);
		
		// Time-based wind
		float time = TIME * wind_speed;
		float wind_offset_x = sin(time + NODE_POSITION_WORLD.x * 0.5) * wind_strength * height_factor;
		float wind_offset_z = cos(time + NODE_POSITION_WORLD.z * 0.5) * wind_strength * height_factor;
		
		VERTEX.x += wind_offset_x;
		VERTEX.z += wind_offset_z;
	}
	
	void fragment() {
		// Basic procedural color based on world pos (diverse flora types)
		vec3 base_color = vec3(0.2, 0.6, 0.2); // Greenish
		
		// Slight color variation per instance
		float var1 = fract(NODE_POSITION_WORLD.x * 0.1);
		float var2 = fract(NODE_POSITION_WORLD.z * 0.1);
		vec3 color_variation = vec3(var1 * 0.2, var2 * 0.2, 0.0);
		
		ALBEDO = base_color + color_variation;
		ROUGHNESS = 0.8;
	}
	"""
	return shader

## DEFERRED(Phase 5): In the future, override update_scatter or add a new dispatch 
## that uses the biome_mask in the compute shader to filter placement.
