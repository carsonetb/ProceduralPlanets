@tool
extends Node3D

@export var seed: int = 1:
	set(val):
		seed = val
		if name == "Moon": update_heights_only()
@export var resolution: int = 1:
	set(val):
		resolution = val
		
		if name == "Moon": update_mesh()

@export_group("Craters")
@export var num_craters: float = 1:
	set(val):
		num_craters = val
		if name == "Moon": update_heights_only()
@export var floor_height: float = -1:
	set(val):
		floor_height = val
		if name == "Moon": update_heights_only()
@export var rim_steepness: float = 0.3:
	set(val):
		rim_steepness = val
		if name == "Moon": update_heights_only()
@export var rim_width: float = 0:
	set(val):
		rim_width = val
		if name == "Moon": update_heights_only()
@export var smoothness: float = 0:
	set(val):
		smoothness = val
		if name == "Moon": update_heights_only()
@export var radius_max: float = 0:
	set(val):
		radius_max = val
		if name == "Moon": update_heights_only()
@export_range(0, 1) var crater_radius_bias: float = 0.6:
	set(val):
		crater_radius_bias = val 
		if name == "Moon": update_heights_only()

@export_group("Noise")

@export_subgroup("Shape Noise")
@export var sn_num_layers: int = 3:
	set(val):
		sn_num_layers = val
		if name == "Moon": update_heights_only()
@export var sn_scale: float = 0.66:
	set(val):
		sn_scale = val
		if name == "Moon": update_heights_only()
@export var sn_persistence: float = 0.5:
	set(val):
		sn_persistence = val
		if name == "Moon": update_heights_only()
@export var sn_lacunarity: float = 2:
	set(val):
		sn_lacunarity = val
		if name == "Moon": update_heights_only()
@export var sn_multiplier: float = 1:
	set(val):
		sn_multiplier = val
		if name == "Moon": update_heights_only()

@export_subgroup("Detail Noise")
@export var dn_num_layers: int = 5:
	set(val):
		dn_num_layers = val
		if name == "Moon": update_heights_only()
@export var dn_scale: float = 2:
	set(val):
		dn_scale = val
		if name == "Moon": update_heights_only()
@export var dn_persistence: float = 0.5:
	set(val):
		dn_persistence = val
		if name == "Moon": update_heights_only()
@export var dn_lacunarity: float = 2:
	set(val):
		dn_lacunarity = val
		if name == "Moon": update_heights_only()
@export var dn_multiplier: float = 1:
	set(val):
		dn_multiplier = val
		if name == "Moon": update_heights_only()

@export_subgroup("Ridge Noise")
@export var rn_offset: Vector3 = Vector3.ZERO:
	set(val):
		rn_offset = val
		if name == "Moon": update_heights_only()
@export var rn_num_layers: int = 4:
	set(val):
		rn_num_layers = val
		if name == "Moon": update_heights_only()
@export var rn_persistence: float = 0.42:
	set(val):
		rn_persistence = val
		if name == "Moon": update_heights_only()
@export var rn_lacunarity: float = 5:
	set(val):
		rn_lacunarity = val
		if name == "Moon": update_heights_only()
@export var rn_scale: float = 2:
	set(val):
		rn_scale = val
		if name == "Moon": update_heights_only()
@export var rn_multiplier: float = 1:
	set(val):
		rn_multiplier = val
		if name == "Moon": update_heights_only()
@export var rn_gain: float = 1:
	set(val):
		rn_gain = val
		if name == "Moon": update_heights_only()
@export var rn_power: float = 3:
	set(val):
		rn_power = val
		if name == "Moon": update_heights_only()
@export var rn_vertical_shift: float = 0:
	set(val):
		rn_vertical_shift = val
		if name == "Moon": update_heights_only()

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
