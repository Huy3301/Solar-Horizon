class_name UniversePosition extends RefCounted

const SECTOR_SIZE_M: float = 1.0e12

var sector: Vector3i = Vector3i.ZERO
var offset: DVec3 = DVec3.zero()

func _init(_sector: Vector3i = Vector3i.ZERO, _offset: DVec3 = null) -> void:
	sector = _sector
	if _offset != null:
		offset = DVec3.new(_offset.x, _offset.y, _offset.z)
	else:
		offset = DVec3.zero()
	normalize()

func normalize() -> void:
	var half_size = SECTOR_SIZE_M * 0.5
	
	while offset.x > half_size:
		offset.x -= SECTOR_SIZE_M
		sector.x += 1
	while offset.x < -half_size:
		offset.x += SECTOR_SIZE_M
		sector.x -= 1
		
	while offset.y > half_size:
		offset.y -= SECTOR_SIZE_M
		sector.y += 1
	while offset.y < -half_size:
		offset.y += SECTOR_SIZE_M
		sector.y -= 1
		
	while offset.z > half_size:
		offset.z -= SECTOR_SIZE_M
		sector.z += 1
	while offset.z < -half_size:
		offset.z += SECTOR_SIZE_M
		sector.z -= 1

func difference_to(other: UniversePosition) -> DVec3:
	var dx = (other.sector.x - sector.x) * SECTOR_SIZE_M + other.offset.x - offset.x
	var dy = (other.sector.y - sector.y) * SECTOR_SIZE_M + other.offset.y - offset.y
	var dz = (other.sector.z - sector.z) * SECTOR_SIZE_M + other.offset.z - offset.z
	return DVec3.new(dx, dy, dz)

func add_offset(d: DVec3) -> void:
	offset.add_in_place(d)
	normalize()
