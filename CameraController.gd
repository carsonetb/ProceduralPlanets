extends Camera3D


var speed_multiplier = 0.01

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	far = 99999

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if !Input.is_action_pressed("rclick"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	if Input.is_action_pressed("left"):
		position -= global_transform.basis.x * delta * 60 * speed_multiplier / Engine.time_scale
	if Input.is_action_pressed("right"):
		position += global_transform.basis.x * delta * 60 * speed_multiplier / Engine.time_scale
	if Input.is_action_pressed("forward"):
		position -= global_transform.basis.z * delta * 60 * speed_multiplier / Engine.time_scale
	if Input.is_action_pressed("backward"):
		position += global_transform.basis.z * delta * 60 * speed_multiplier / Engine.time_scale
	
	if Input.is_action_just_pressed("decrease_speed"):
		speed_multiplier /= 1.2
	if Input.is_action_just_pressed("increase_speed"):
		speed_multiplier *= 1.2

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotation_degrees.y -= event.relative.x / (90 - fov)
			rotation_degrees.x -= event.relative.y / (90 - fov)
