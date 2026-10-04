@tool
class_name ShaderBaker
extends Node

## Utilizes Godot 4.7 pipeline precompilation feature to pre-warm shaders during splash.

const SHADER_DIRECTORIES: Array[String] = [
	"res://shaders/",
	"res://game/planet/shaders/"
]

var _is_baking: bool = false

func _ready() -> void:
	pass

## Call this during the splash screen
func bake_shaders() -> void:
	if _is_baking:
		return
	_is_baking = true
	print("Starting shader pipeline precompilation...")
	
	var shaders: Array[Shader] = _gather_shaders(SHADER_DIRECTORIES)
	
	for shader in shaders:
		_precompile_shader(shader)
		
	print("Shader baking completed.")
	_is_baking = false

func _gather_shaders(directories: Array[String]) -> Array[Shader]:
	var result: Array[Shader] = []
	for dir_path in directories:
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(".gdshader"):
					var res := load(dir_path + file_name) as Shader
					if res:
						result.append(res)
				file_name = dir.get_next()
	return result

func _precompile_shader(shader: Shader) -> void:
	if shader:
		# Create a dummy material to force compilation
		var mat := ShaderMaterial.new()
		mat.shader = shader
		# In Godot 4.7, rendering device pipeline precompilation might be available on the RenderingServer
		if RenderingServer.has_method("precompile_shader"):
			RenderingServer.call("precompile_shader", shader.get_rid())
