extends SceneTree

func _init() -> void:
	print("Running tests...")
	var test_files: Array[String] = []
	_find_test_files("res://tests", test_files)
	
	var total = 0
	var passed = 0
	
	var baseline_orphans: Array = Node.get_orphan_node_ids()
	var baseline_root_children: Array = root.get_children()
	
	for file in test_files:
		if file.ends_with("run_tests.gd") or file.ends_with("test_case.gd"):
			continue
			
		var script = load(file)
		if script == null or not script is Script:
			continue
			
		var inst = script.new()
		if not inst is TestCase:
			continue
			
		for method in inst.get_method_list():
			var name = method["name"]
			if name.begins_with("test_"):
				total += 1
				inst._failures.clear()
				inst.call(name)
				var fails = inst.get_failures()
				if fails.is_empty():
					print("PASS: %s::%s" % [file, name])
					passed += 1
				else:
					print("FAIL: %s::%s" % [file, name])
					for f in fails:
						print("  - " + f)
		
		# Leak Guard: Clean up orphaned Node instances created by test script
		_cleanup_orphans(baseline_orphans, baseline_root_children)
	
	_cleanup_orphans(baseline_orphans, baseline_root_children)
	
	print("---")
	print("Tests: %d passed / %d total" % [passed, total])
	if passed == total and total > 0:
		quit(0)
	else:
		quit(1)

func _cleanup_orphans(baseline_orphans: Array, baseline_root_children: Array) -> void:
	for child in root.get_children():
		if not baseline_root_children.has(child):
			if is_instance_valid(child):
				root.remove_child(child)
				child.free()

	for id in Node.get_orphan_node_ids():
		if baseline_orphans.has(id):
			continue
		var obj = instance_from_id(id)
		if is_instance_valid(obj) and obj is Node:
			var top_node: Node = obj
			while top_node.get_parent() != null and top_node.get_parent() != root:
				top_node = top_node.get_parent()
			if top_node != root and is_instance_valid(top_node):
				top_node.free()

func _find_test_files(dir_path: String, files: Array[String]) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_find_test_files(dir_path + "/" + file_name, files)
			else:
				if file_name.begins_with("test_") and file_name.ends_with(".gd"):
					files.append(dir_path + "/" + file_name)
			file_name = dir.get_next()
