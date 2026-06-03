extends PathFollow2D
@export var patrol_speed: float = 80.0  # pixels per second
@export var is_looping: bool = false
@export var pause_duration: float = 0.8
@export var slow_turn_enabled: bool = false
@export var turn_duration: float = 0.5
@export var reverse_turn_direction: bool = false  # NEW: false = default (clockwise), true = counterclockwise
var going_forward: bool = true
var _path_length: float = 0.0
var _pause_timer: float = 0.0
var _turn_pending: bool = false
var _turn_timer: float = 0.0
var _turn_start_rot: float = 0.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	loop = false
	_path_length = get_parent().curve.get_baked_length()
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _turn_timer > 0.0:
		_turn_timer -= delta
		var t = clamp(1.0 - (_turn_timer / turn_duration), 0.0, 1.0)
		# CHANGED: direction of the turn arc is controlled by reverse_turn_direction
		var turn_angle = -PI if reverse_turn_direction else PI
		rotation = lerp(_turn_start_rot, _turn_start_rot + turn_angle, t)
		if _turn_timer <= 0.0:
			rotation = _turn_start_rot
			going_forward = !going_forward
			scale.x *= -1
		return
	if _pause_timer > 0.0:
		_pause_timer -= delta
		if _pause_timer <= 0.0 and _turn_pending:
			_turn_pending = false
			if slow_turn_enabled:
				_turn_start_rot = rotation
				_turn_timer = turn_duration
			else:
				going_forward = !going_forward
				scale.x *= -1
		return
	if is_looping:
		loop_movement(delta)
	else:
		bouncing_movement(delta)
		
func _start_pause() -> void:
	if pause_duration > 0.0:
		_pause_timer = pause_duration
		_turn_pending = true
	else:
		going_forward = !going_forward
		scale.x *= -1
	
func loop_movement(delta):
	progress += delta * patrol_speed
	if progress >= _path_length:
		progress -= _path_length
func bouncing_movement(delta):
	if going_forward:
		progress += delta * patrol_speed
		if progress >= _path_length:
			progress = _path_length
			_start_pause()
	else:
		progress -= delta * patrol_speed
		if progress <= 0.0:
			progress = 0.0
			_start_pause()
