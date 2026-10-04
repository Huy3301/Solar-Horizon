class_name ItemDef extends Resource
## Defines an inventory item with mass, stacking, and metadata.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var stack_max: int = 100
@export var mass: float = 1.0
@export var category: String = "mineral"

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"stack_max": stack_max,
		"mass": mass,
		"category": category,
	}
