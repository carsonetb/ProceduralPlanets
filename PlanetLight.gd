@tool
extends DirectionalLight3D


func _process(delta):
	get_parent().get_node("Mesh").material_override.set("shader_parameter/world_space_light_pos", global_transform.basis.z)
