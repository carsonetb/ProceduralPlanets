@tool
extends MeshInstance3D

const vertex_pairs := [0, 1, 0, 2, 0, 3, 0, 4, 1, 2, 2, 3, 3, 4, 4, 1, 5, 1, 5, 2, 5, 3, 5, 4]
const edge_triplets := [0, 1, 4, 1, 2, 5, 2, 3, 6, 3, 0, 7, 8, 9, 4, 9, 10, 5, 10, 11, 6, 11, 8, 7]
const base_vertices := [Vector3.UP, Vector3.LEFT, Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN]

var rd: RenderingDevice
var shader

var stored_vertices := PackedVector3Array()
var stored_triangles := PackedInt32Array()
var stored_normals := PackedVector3Array()


func _ready():
	# Load compute shader.
	rd = RenderingServer.create_local_rendering_device()
	var shader_file = load("res://moon_compute_heights.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)

func update_mesh(resolution: int):
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	
	var vertices_per_face: int = ((resolution + 3) * (resolution + 3) - (resolution + 3)) / 2
	var triangles_per_face: int = (resolution + 1) * (resolution + 1)
	var total_vertices: int = vertices_per_face * 8 - (resolution + 2) * 12 + 6
	
	var vertices := PackedVector3Array()
	var triangles := PackedInt32Array()
	var normals := PackedVector3Array()
	var uv_array := PackedVector2Array()
	
	vertices.resize(6)
	normals.resize(6)
	uv_array.resize(total_vertices)
	
	vertices[0] = Vector3.UP
	vertices[1] = Vector3.LEFT
	vertices[2] = Vector3.BACK
	vertices[3] = Vector3.RIGHT
	vertices[4] = Vector3.FORWARD
	vertices[5] = Vector3.DOWN
	normals[0] = Vector3.UP
	normals[1] = Vector3.LEFT
	normals[2] = Vector3.BACK
	normals[3] = Vector3.RIGHT
	normals[4] = Vector3.FORWARD
	normals[5] = Vector3.DOWN
	
	# Create 12 edges, with resolution vertices added along them.
	var edges: Array[Array]
	edges.resize(12)
	for i in range(0, vertex_pairs.size(), 2):
		var start_vertex := vertices[vertex_pairs[i]]
		var end_vertex := vertices[vertex_pairs[i + 1]]
		
		var edge_vertex_indices: Array[int]
		edge_vertex_indices.resize(resolution + 2)
		
		for division_index in range(resolution):
			var t: float = (division_index + 1.0) / (resolution + 1.0)
			edge_vertex_indices[division_index + 1] = vertices.size()
			vertices.append(start_vertex.slerp(end_vertex, t))
			normals.append(start_vertex.slerp(end_vertex, t).normalized())
			
		edge_vertex_indices[resolution + 1] = vertex_pairs[i + 1]
		var edge_index := i / 2.0
		edges[edge_index] = edge_vertex_indices
	
	# Create faces.
	for i in range(0, edge_triplets.size(), 3):
		var face_index := i / 3.0
		var reverse := face_index >= 4
		
		var side_a: Array[int] = edges[edge_triplets[i]]
		var side_b: Array[int] = edges[edge_triplets[i + 1]]
		var bottom: Array[int] = edges[edge_triplets[i + 2]]
		
		var num_points_on_edge := side_a.size()
		
		var vertex_map = PackedInt32Array()
		vertex_map.append(side_a[0])
		
		for j in range(1, num_points_on_edge - 1):
			vertex_map.append(side_a[j])
			
			var side_a_vertex := vertices[side_a[j]]
			var side_b_vertex := vertices[side_b[j]]
			var num_inner_points := j - 1
			
			for k in range(num_inner_points):
				var t: float = (float(k) + 1.0) / (float(num_inner_points) + 1.0)
				vertex_map.append(vertices.size())
				vertices.append(side_a_vertex.slerp(side_b_vertex, t))
				normals.append(side_a_vertex.slerp(side_b_vertex, t).normalized())
			
			vertex_map.append(side_b[j])
			
		for j in range(num_points_on_edge):
			vertex_map.append(bottom[j])
			
		# Triangulate
		var num_rows := resolution + 1
		for row in range(num_rows):
			var top_vertex: int = ((row + 1) * (row + 1) - row - 1) / 2.0
			var bottom_vertex: int = ((row + 2) * (row + 2) - row - 2) / 2.0
			
			var num_triangles_in_row: int = 1 + 2 * row
			for column in range(num_triangles_in_row):
				var v0: int
				var v1: int
				var v2: int
				
				if (column % 2 == 0):
					v0 = top_vertex
					v1 = bottom_vertex + 1
					v2 = bottom_vertex
					top_vertex += 1
					bottom_vertex += 1
				else:
					v0 = top_vertex
					v1 = bottom_vertex
					v2 = top_vertex - 1
				
				triangles.append(vertex_map[v0])
				triangles.append(vertex_map[v2 if reverse else v1])
				triangles.append(vertex_map[v1 if reverse else v2])
	
	# Store values so we don't have to recalculate them later.
	stored_vertices = vertices
	stored_triangles = triangles
	stored_normals = normals
				
	vertices = update_heights(resolution)
	
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_INDEX] = triangles
	data[Mesh.ARRAY_NORMAL] = normals
	data[Mesh.ARRAY_TEX_UV] = uv_array
	
	call_deferred("_update_mesh", data)
	
func _update_mesh(data: Array):
	var _mesh := ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	mesh = _mesh
	
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	
	# Calculate vertex normals, face-by-face.
	for i in range(mdt.get_face_count()):
		# Get the index in the vertex array.
		var a = mdt.get_face_vertex(i, 0)
		var b = mdt.get_face_vertex(i, 1)
		var c = mdt.get_face_vertex(i, 2)
		# Get vertex position using vertex index.
		var ap = mdt.get_vertex(a)
		var bp = mdt.get_vertex(b)
		var cp = mdt.get_vertex(c)
		# Calculate face normal.
		var n = (bp - cp).cross(ap - bp).normalized()
		# Add face normal to current vertex normal.
		# This will not result in perfect normals, but it will be close.
		mdt.set_vertex_normal(a, n + mdt.get_vertex_normal(a))
		mdt.set_vertex_normal(b, n + mdt.get_vertex_normal(b))
		mdt.set_vertex_normal(c, n + mdt.get_vertex_normal(c))

	# Run through vertices one last time to normalize normals and
	# set color to normal.
	for i in range(mdt.get_vertex_count()):
		var v = mdt.get_vertex_normal(i).normalized()
		mdt.set_vertex_normal(i, v)
		mdt.set_vertex_color(i, Color(v.x, v.y, v.z))
	
	mesh.clear_surfaces()
	mdt.commit_to_surface(mesh)

func update_heights(resolution):
	var vertices := stored_vertices.duplicate()
	var vertices_per_face: int = ((resolution + 3) * (resolution + 3) - (resolution + 3)) / 2
	var triangles_per_face: int = (resolution + 1) * (resolution + 1)
	var total_vertices: int = vertices_per_face * 8 - (resolution + 2) * 12 + 6
	
	# Compute shader to compute heights.
	# Vertex buffer.
	var vertex_array_bytes := vertices.to_byte_array()
	var vertex_buffer := rd.storage_buffer_create(vertex_array_bytes.size(), vertex_array_bytes)
	var vertex_uniform := RDUniform.new()
	vertex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	vertex_uniform.binding = 0
	vertex_uniform.add_id(vertex_buffer)
	
	# Params buffer.
	var parameters_array := PackedFloat32Array(
		[
			0.0,
			vertices_per_face * 8 - (resolution + 2) * 12 + 6,
			get_parent().num_craters,
			get_parent().floor_height,
			get_parent().rim_steepness,
			get_parent().rim_width,
			get_parent().smoothness,
			
			get_parent().sn_num_layers,
			get_parent().sn_scale,
			get_parent().sn_persistence,
			get_parent().sn_lacunarity,
			get_parent().sn_multiplier,
			
			get_parent().dn_num_layers,
			get_parent().dn_scale,
			get_parent().dn_persistence,
			get_parent().dn_lacunarity,
			get_parent().dn_multiplier,
			
			get_parent().rn_offset.x,
			get_parent().rn_offset.y,
			get_parent().rn_offset.z,
			get_parent().rn_num_layers,
			get_parent().rn_persistence,
			get_parent().rn_lacunarity,
			get_parent().rn_scale,
			get_parent().rn_multiplier,
			get_parent().rn_gain,
			get_parent().rn_power,
			get_parent().rn_vertical_shift
		]
	)
	var parameters_array_bytes := parameters_array.to_byte_array()
	var parameter_buffer := rd.storage_buffer_create(parameters_array_bytes.size(), parameters_array_bytes)
	var parameter_uniform := RDUniform.new()
	parameter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	parameter_uniform.binding = 1
	parameter_uniform.add_id(parameter_buffer)
	
	# Heights buffer.
	var blank_heights_array := PackedFloat32Array()
	blank_heights_array.resize(vertices.size())
	var blank_heights_array_bytes := blank_heights_array.to_byte_array()
	var heights_buffer := rd.storage_buffer_create(blank_heights_array_bytes.size(), blank_heights_array_bytes)
	var heights_uniform := RDUniform.new()
	heights_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	heights_uniform.binding = 2
	heights_uniform.add_id(heights_buffer)
	
	# Crater centers buffer.
	var crater_centers_array := PackedVector3Array()
	crater_centers_array.resize(get_parent().num_craters)
	for i in range(get_parent().num_craters):
		seed(get_parent().seed + i)
		crater_centers_array[i] = vertices[randi_range(0, vertices.size())]
	var crater_centers_array_bytes := crater_centers_array.to_byte_array()
	var crater_centers_buffer := rd.storage_buffer_create(crater_centers_array_bytes.size(), crater_centers_array_bytes)
	var crater_centers_uniform := RDUniform.new()
	crater_centers_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	crater_centers_uniform.binding = 3
	crater_centers_uniform.add_id(crater_centers_buffer)
	
	# Crater radii buffer.
	var crater_radii_array := PackedFloat32Array()
	crater_radii_array.resize(get_parent().num_craters)
	for i in range(get_parent().num_craters):
		seed(get_parent().seed + i)
		crater_radii_array[i] = _helper_bias(randf_range(0.1, 1), get_parent().crater_radius_bias) * get_parent().radius_max
	var crater_radii_array_bytes := crater_radii_array.to_byte_array()
	var crater_radii_buffer := rd.storage_buffer_create(crater_radii_array_bytes.size(), crater_radii_array_bytes)
	var crater_radii_uniform := RDUniform.new()
	crater_radii_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	crater_radii_uniform.binding = 4
	crater_radii_uniform.add_id(crater_radii_buffer)
	
	# Add to set.
	var uniform_set := rd.uniform_set_create(
		[vertex_uniform, parameter_uniform, heights_uniform, crater_centers_uniform, crater_radii_uniform],
		shader, 0
	)
	
	# Create compute pipeline
	var pipeline := rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, vertices.size(), 1, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Retrieve output of compute shader.
	var heights_array_bytes := rd.buffer_get_data(heights_buffer)
	var heights_array := heights_array_bytes.to_float32_array()
	
	# Basic for loop until I can get the compute shader working.
	for i in range(0, vertices.size()):
		vertices[i] *= heights_array[i]
	
	return vertices

func _helper_bias(x: float, bias: float) -> float:
	var k := pow(1 - bias, 3)
	return (x * k) / (x * k - x + 1)
