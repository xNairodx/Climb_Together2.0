extends CharacterBody3D

# ==========================================
# MOVIMIENTO
# ==========================================

@export var speed: float = 6.0
@export var jump_velocity: float = 4.8
@export var gravity: float = 9.8


# ==========================================
# CAMARA DURANTE ESCALADA
# ==========================================

@export var climb_camera_horizontal_limit: float = 50.0
@export var climb_camera_vertical_limit: float = 35.0

var climb_camera_rotation_y: float = 0.0

# ==========================================
# CAMARA
# ==========================================

@export var mouse_sensitivity: float = 0.002
@export var camera_limit: float = 85.0

var camera_rotation_x: float = 0.0

# ==========================================
# ESCALADA
# ==========================================

@export var climb_speed: float = 4.0
@export var ray_distance: float = 1.5
@export var stick_to_wall_force: float = 2.0
@export var climb_smoothness: float = 10.0

var touching_wall: bool = false
var is_climbing: bool = false

var climb_normal: Vector3 = Vector3.ZERO

# ==========================================
# NODOS
# ==========================================

@onready var neck: Node3D = $Neck
@onready var camera: Camera3D = $Neck/Camera3D

@onready var climb_rays: Array[RayCast3D] = [
	$Neck/ClimbRay_Central,
	$Neck/ClimbRay_Right,
	$Neck/ClimbRay_Left,
	$Neck/ClimbRay_Up,
	$Neck/ClimbRay_Down
]

# ==========================================
# READY
# ==========================================

func _ready() -> void:

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera.current = true

	for ray in climb_rays:

		ray.enabled = true

		ray.target_position = Vector3(
			0,
			0,
			-ray_distance
		)

# ==========================================
# INPUT - CAMARA
# ==========================================


func _input(event: InputEvent) -> void:

	# LIBERAR MOUSE
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# CAPTURAR MOUSE
	if event is InputEventMouseButton:

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# MOVIMIENTO DE CAMARA
	if event is InputEventMouseMotion:

		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

var horizontal: float = event.relative.x * mouse_sensitivity
var vertical: float = event.relative.y * mouse_sensitivity

		# ==================================
		# CAMARA NORMAL
		# ==================================

		if not is_climbing:

			rotation.y -= horizontal

			camera_rotation_x -= vertical

			camera_rotation_x = clamp(
				camera_rotation_x,
				deg_to_rad(-camera_limit),
				deg_to_rad(camera_limit)
			)

			neck.rotation.x = camera_rotation_x

			# Reiniciar rotacion horizontal del cuello
			neck.rotation.y = 0.0

			climb_camera_rotation_y = 0.0

		# ==================================
		# CAMARA DURANTE ESCALADA
		# ==================================

		else:

			# ROTACION HORIZONTAL LIMITADA

			climb_camera_rotation_y -= horizontal

			climb_camera_rotation_y = clamp(
				climb_camera_rotation_y,
				deg_to_rad(-climb_camera_horizontal_limit),
				deg_to_rad(climb_camera_horizontal_limit)
			)

			neck.rotation.y = climb_camera_rotation_y

			# ROTACION VERTICAL LIMITADA

			camera_rotation_x -= vertical

			camera_rotation_x = clamp(
				camera_rotation_x,
				deg_to_rad(-climb_camera_vertical_limit),
				deg_to_rad(climb_camera_vertical_limit)
			)

			neck.rotation.x = camera_rotation_x

# ==========================================
# PHYSICS
# ==========================================

func _physics_process(delta: float) -> void:

	# Detectar superficies
	detect_climb_surfaces()

	# Activar escalada con click izquierdo
	is_climbing = (
		Input.is_action_pressed("Click_Izquierdo_Escalar")
		and touching_wall
	)

	# Movimiento
	if is_climbing:

		climbing_movement(delta)

	else:

		normal_movement(delta)

	# Aplicar fisicas
	move_and_slide()

# ==========================================
# MOVIMIENTO NORMAL
# ==========================================

func normal_movement(delta: float) -> void:

	# GRAVEDAD
	if not is_on_floor():

		velocity.y -= gravity * delta

	# WASD
	var input_dir := Input.get_vector(
		"A_izquierda",
		"D_right",
		"W_adelante",
		"S_atras"
	)

	var direction := (
		transform.basis *
		Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	if direction.length() > 0.0:

		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	else:

		velocity.x = move_toward(
			velocity.x,
			0.0,
			speed * 10.0 * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			speed * 10.0 * delta
		)

	# SALTO - SPACEBAR
	if Input.is_action_just_pressed("SpaceBar_Saltar") and is_on_floor():

		velocity.y = jump_velocity

# ==========================================
# MOVIMIENTO DE ESCALADA
# ==========================================

func climbing_movement(delta: float) -> void:

	# WASD
	var input_dir := Input.get_vector(
		"A_izquierda",
		"D_right",
		"W_adelante",
		"S_atras"
	)

	# DIRECCION HORIZONTAL DE LA PARED
	var right := camera.global_basis.x

	right = (
		right - climb_normal * right.dot(climb_normal)
	).normalized()

	# DIRECCION VERTICAL DE LA PARED
	var up := climb_normal.cross(right).normalized()

	# MOVIMIENTO SOBRE LA SUPERFICIE
	var climb_direction := (
		right * input_dir.x +
		up * -input_dir.y
	)

	if climb_direction.length() > 0.01:

		climb_direction = climb_direction.normalized()

	# VELOCIDAD DE ESCALADA
	var target_velocity := (
		climb_direction * climb_speed
	)

	# ADHERENCIA A LA PARED
	target_velocity += (
		-climb_normal * stick_to_wall_force
	)

	# SUAVIZAR MOVIMIENTO
	velocity = velocity.lerp(
		target_velocity,
		clamp(climb_smoothness * delta, 0.0, 1.0)
	)

# ==========================================
# DETECCION DE SUPERFICIES
# ==========================================

func detect_climb_surfaces() -> void:

	touching_wall = false
	climb_normal = Vector3.ZERO

	var normal_sum := Vector3.ZERO
	var hit_count: int = 0

	for ray in climb_rays:

		ray.force_raycast_update()

		if ray.is_colliding():

			var normal := ray.get_collision_normal()

			normal_sum += normal

			hit_count += 1

	# PROMEDIAR NORMALES
	if hit_count > 0:

		touching_wall = true

		climb_normal = (
			normal_sum / float(hit_count)
		).normalized()
