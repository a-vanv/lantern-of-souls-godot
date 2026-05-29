extends CharacterBody2D

@onready var light_shape: CircleShape2D = $LightRadius/CollisionShape2D.shape
@onready var light_visual = $LightRadius/LightVisual
@onready var soul_bar: ProgressBar = $HUD/MarginContainer/VBoxContainer/SoulBar

# --- Feature Toggles (visible as checkboxes in the Inspector) ---
@export_group("Feature Toggles")
@export var scroll_wheel_speed_enabled: bool = false
@export var adjustable_radius_enabled: bool = true
@export var walk_run_mode_enabled: bool = false

# --- Speed Settings ---
@export_group("Speed Settings")
@export var default_speed: float = 200.0
@export var crouch_speed: float = 100.0
@export var scroll_step: float = 20.0
@export var min_scroll_speed: float = 50.0
@export var max_scroll_speed: float = 400.0

# --- Soul Radius Settings ---
@export_group("Soul Radius Settings")
@export var normal_radius: float = 80.0
@export var crouch_radius: float = 35.0
@export var max_radius: float = 120.0

# --- Soul Settings ---
@export_group("Soul Drain Settings")
@export var min_drain_rate: float = 2.0
@export var max_drain_rate: float = 8.0

# --- Crouch, Walk, Run Settings ---
@export_group("Crouch, Walk, Run Settings")
@export var walk_speed: float = 175.0
@export var walk_radius: float = 70.0
@export var sprint_speed: float = 350.0
@export var sprint_radius: float = 100.0
@export var min_crouch_radius: float = 20.0
@export var max_crouch_radius: float = 60.0
@export var min_crouch_scroll_speed: float = 50.0
@export var max_crouch_scroll_speed: float = 125.0

# Internal runtime speed (don't edit directly)
var _current_speed: float
var _spawn_position: Vector2
var _crouch_scroll_speed: float

func _ready() -> void:
	_current_speed = default_speed
	_crouch_scroll_speed = min_crouch_scroll_speed
	_spawn_position = global_position
	soul_bar.min_value = 0.0
	soul_bar.max_value = 100.0
	soul_bar.value = 100.0

func _unhandled_input(event: InputEvent) -> void:
	if not scroll_wheel_speed_enabled and not walk_run_mode_enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		var scrolling_up = event.button_index == MOUSE_BUTTON_WHEEL_UP
		var scrolling_down = event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if walk_run_mode_enabled and Input.is_action_pressed("sprint"):
			if scrolling_up:
				_crouch_scroll_speed = clamp(_crouch_scroll_speed + scroll_step, min_crouch_scroll_speed, max_crouch_scroll_speed)
			elif scrolling_down:
				_crouch_scroll_speed = clamp(_crouch_scroll_speed - scroll_step, min_crouch_scroll_speed, max_crouch_scroll_speed)
		else:
			if scrolling_up:
				default_speed = clamp(default_speed + scroll_step, min_scroll_speed, max_scroll_speed)
			elif scrolling_down:
				default_speed = clamp(default_speed - scroll_step, min_scroll_speed, max_scroll_speed)

func read_input() -> void:
	var input_direction = Vector2.ZERO

	if Input.is_action_pressed("up"):    input_direction.y -= 1
	if Input.is_action_pressed("down"):  input_direction.y += 1
	if Input.is_action_pressed("left"):  input_direction.x -= 1
	if Input.is_action_pressed("right"): input_direction.x += 1

	if scroll_wheel_speed_enabled:
		_current_speed = default_speed

		if adjustable_radius_enabled:
			var scaled = remap(default_speed, min_scroll_speed, max_scroll_speed, crouch_radius, max_radius)
			light_shape.radius = scaled
			light_visual.set_radius(scaled)

	elif walk_run_mode_enabled:
		if Input.is_action_pressed("sprint"):
			_current_speed = _crouch_scroll_speed
			var scaled = remap(_crouch_scroll_speed, min_crouch_scroll_speed, max_crouch_scroll_speed, min_crouch_radius, max_crouch_radius)
			light_shape.radius = scaled
			light_visual.set_radius(scaled)
		elif Input.is_action_pressed("crouch"):
			light_shape.radius = sprint_radius
			light_visual.set_radius(sprint_radius)
			_current_speed = sprint_speed
		else:
			light_shape.radius = walk_radius
			light_visual.set_radius(walk_radius)
			_current_speed = walk_speed

	else:
		if Input.is_action_pressed("crouch"):
			if adjustable_radius_enabled:
				light_shape.radius = crouch_radius
				light_visual.set_radius(crouch_radius)
			_current_speed = crouch_speed
		else:
			if adjustable_radius_enabled:
				light_shape.radius = normal_radius
				light_visual.set_radius(normal_radius)
			_current_speed = default_speed

	velocity = input_direction.normalized() * _current_speed

func _physics_process(delta: float) -> void:
	read_input()
	move_and_slide()
	_update_soul(delta)
	
# --- Soul Logic ---

func _update_soul(delta: float) -> void:
	if walk_run_mode_enabled:
		var drain = remap(light_shape.radius, min_crouch_radius, sprint_radius, min_drain_rate, max_drain_rate)
		soul_bar.value -= drain * delta
	else:
		var drain = remap(light_shape.radius, crouch_radius, max_radius, min_drain_rate, max_drain_rate)
		soul_bar.value -= drain * delta

	if soul_bar.value <= 0.0:
		die()

func die() -> void:
	global_position = _spawn_position
	soul_bar.value = soul_bar.max_value

# Called by Checkpoint nodes when the player steps on them.
func refill_soul() -> void:
	soul_bar.value = soul_bar.max_value

# Called by Checkpoint nodes to register a new respawn point.
func set_spawn(pos: Vector2) -> void:
	_spawn_position = pos
