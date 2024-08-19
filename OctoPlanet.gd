@tool
extends Node3D

@export var seed: int = 1:
	set(val):
		seed = val
		if name == "Planet": update_mesh()
@export var resolution: int = 1:
	set(val):
		resolution = val
		
		if name == "Planet": update_mesh()

@export_group("Ocean")
@export var o_floor_depth: float = 0.5:
	set(val):
		o_floor_depth = val
		if name == "Planet": update_mesh()
@export var o_floor_smoothing: float = 0.5:
	set(val):
		o_floor_smoothing = val
		if name == "Planet": update_mesh()
@export var o_depth_multiplier: float = 1:
	set(val):
		o_depth_multiplier = val
		if name == "Planet": update_mesh()
@export var mountain_blend: float = 1:
	set(val):
		mountain_blend = val
		if name == "Planet": update_mesh()

@export_group("Noise")

@export_subgroup("Continent Noise")
@export var c_num_layers: int = 3:
	set(val):
		c_num_layers = val
		if name == "Planet": update_heights_only()
@export var c_scale: float = 0.66:
	set(val):
		c_scale = val
		if name == "Planet": update_heights_only()
@export var c_persistence: float = 0.5:
	set(val):
		c_persistence = val
		if name == "Planet": update_heights_only()
@export var c_lacunarity: float = 2:
	set(val):
		c_lacunarity = val
		if name == "Planet": update_heights_only()
@export var c_multiplier: float = 1:
	set(val):
		c_multiplier = val
		if name == "Planet": update_heights_only()

@export_subgroup("Mountain Noise")
@export var m_offset: Vector3 = Vector3.ZERO:
	set(val):
		m_offset = val
		if name == "Planet": update_heights_only()
@export var m_num_layers: int = 4:
	set(val):
		m_num_layers = val
		if name == "Planet": update_heights_only()
@export var m_persistence: float = 0.42:
	set(val):
		m_persistence = val
		if name == "Planet": update_heights_only()
@export var m_lacunarity: float = 5:
	set(val):
		m_lacunarity = val
		if name == "Planet": update_heights_only()
@export var m_scale: float = 2:
	set(val):
		m_scale = val
		if name == "Planet": update_heights_only()
@export var m_multiplier: float = 1:
	set(val):
		m_multiplier = val
		if name == "Planet": update_heights_only()
@export var m_gain: float = 1:
	set(val):
		m_gain = val
		if name == "Planet": update_heights_only()
@export var m_power: float = 3:
	set(val):
		m_power = val
		if name == "Planet": update_heights_only()
@export var m_vertical_shift: float = 0:
	set(val):
		m_vertical_shift = val
		if name == "Planet": update_heights_only()

@export_subgroup("Mask Noise")
@export var ma_num_layers: int = 3:
	set(val):
		ma_num_layers = val
		if name == "Planet": update_heights_only()
@export var ma_scale: float = 0.66:
	set(val):
		ma_scale = val
		if name == "Planet": update_heights_only()
@export var ma_persistence: float = 0.5:
	set(val):
		ma_persistence = val
		if name == "Planet": update_heights_only()
@export var ma_lacunarity: float = 2:
	set(val):
		ma_lacunarity = val
		if name == "Planet": update_heights_only()
@export var ma_multiplier: float = 1:
	set(val):
		ma_multiplier = val
		if name == "Planet": update_heights_only()
@export var ma_vertical_shift: float = 0:
	set(val):
		ma_vertical_shift = val
		if name == "Planet": update_heights_only()
	
func _ready():
	update_mesh()
	
func update_mesh():
	$Mesh.update_mesh(resolution)

func update_heights_only():
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	
	var vertices: PackedVector3Array = $Mesh.update_heights(resolution)
	var normals: PackedVector3Array = $Mesh.stored_normals
	var triangles: PackedInt32Array = $Mesh.stored_triangles
	
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_INDEX] = triangles
	data[Mesh.ARRAY_NORMAL] = normals
	
	$Mesh.call_deferred("_update_mesh", data)
