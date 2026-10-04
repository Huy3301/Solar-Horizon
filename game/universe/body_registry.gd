class_name BodyRegistry extends RefCounted

static var _bodies: Dictionary = {}
static var _children: Dictionary = {}
static var _root_id: StringName = ""
static var _initialized: bool = false

static func _init_registry() -> void:
	if _initialized:
		return
	_initialized = true
	var dir_path = "res://game/universe/data/bodies"
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".tres") or file_name.ends_with(".res") or file_name.ends_with(".remap"):
					var load_path = dir_path + "/" + file_name.trim_suffix(".remap")
					var res = ResourceLoader.load(load_path) as CelestialBodyDef
					if res:
						_bodies[res.id] = res
						if res.parent_id == "":
							_root_id = res.id
			file_name = dir.get_next()
	
	for b_id in _bodies:
		var b = _bodies[b_id] as CelestialBodyDef
		if b.parent_id != "":
			if not _children.has(b.parent_id):
				_children[b.parent_id] = []
			var arr = _children[b.parent_id] as Array[StringName]
			arr.append(b.id)

static func get_body(id: StringName) -> CelestialBodyDef:
	if not _initialized:
		_init_registry()
	return _bodies.get(id, null)

static func get_children(id: StringName) -> Array[StringName]:
	if not _initialized:
		_init_registry()
	var arr = _children.get(id, [])
	var ret: Array[StringName] = []
	for x in arr:
		ret.append(x)
	return ret

static func all_ids() -> Array[StringName]:
	if not _initialized:
		_init_registry()
	var keys = _bodies.keys()
	var ret: Array[StringName] = []
	for k in keys:
		ret.append(k)
	return ret

static func get_root() -> StringName:
	if not _initialized:
		_init_registry()
	return _root_id
