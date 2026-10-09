class_name BodyFrames extends RefCounted

## Orientation + terrain lookup for bodies whose surface is simulated (Earth, Moon).
## MainWorld registers each globe's fixed orientation; flight code uses it to find the terrain
## height under the ship (AGL) with the same CPU function the collision meshes are built from.
## Planets do not spin under the player: day/night comes from rotating the sun direction, so the
## surface frame is inertial and a parked ship stays parked.

static var _bases: Dictionary = {}
const MAX_HEIGHT_M: Dictionary = {&"Earth": 8848.0, &"Moon": 10700.0}

static func set_basis(id: StringName, basis: Basis) -> void:
	_bases[id] = basis.orthonormalized()

static func get_basis(id: StringName) -> Basis:
	return _bases.get(id, Basis.IDENTITY)

static func clear() -> void:
	_bases.clear()

## Planet-local unit direction for a world-space "up" vector at the body.
static func local_dir(id: StringName, world_up: Vector3) -> Vector3:
	return (get_basis(id).inverse() * world_up).normalized()

## Terrain height above the reference sphere (metres) in the given world-space direction.
static func terrain_height_m(id: StringName, world_up: Vector3) -> float:
	if not MAX_HEIGHT_M.has(id):
		return 0.0
	var d: Vector3 = local_dir(id, world_up)
	return TerrainNoise.sample_height(d.x, d.y, d.z, "Moon" if id == &"Moon" else "Earth") * float(MAX_HEIGHT_M[id])

## Direction (planet-local) for geographic lat/lon in degrees, matching TerrainNoise/Earth texture mapping.
static func geo_dir(lat_deg: float, lon_deg: float) -> Vector3:
	var phi: float = deg_to_rad(lat_deg)
	var lam: float = deg_to_rad(lon_deg)
	return Vector3(cos(phi) * sin(lam), sin(phi), -cos(phi) * cos(lam)).normalized()

## Basis that maps planet-local `dir` to world +Y with local north towards world -Z.
static func basis_for_surface_point(dir: Vector3) -> Basis:
	var up: Vector3 = dir.normalized()
	var east: Vector3 = Vector3.UP.cross(up)
	if east.length() < 1e-4:
		east = Vector3.RIGHT
	east = east.normalized()
	var north: Vector3 = up.cross(east).normalized()
	# world = (v.east, v.up, -v.north)
	return Basis(east, up, -north).transposed()
