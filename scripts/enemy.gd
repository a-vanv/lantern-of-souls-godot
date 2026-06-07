extends CharacterBody2D

@export_group("Spinning Settings")
@export var spinning_enabled: bool = false
@export var rotation_speed: float = PI

# --- Key Settings ---
@export_group("Key Settings")
@export var has_key: bool = false

var _key_pickup: Area2D = null

func _ready() -> void:
	$VisionCone.body_entered.connect(_on_vision_cone_body_entered)
	if has_key:
		_spawn_key()

func _physics_process(_delta) -> void:
	# Poll overlapping areas every frame — catches radius-resize overlaps
	for area in $VisionCone.get_overlapping_areas():
		if area.is_in_group("player_light"):
			var player = area.get_parent()
			if _has_line_of_sight(player.global_position):
				player.die()
				return

func _process(delta: float) -> void:
	if spinning_enabled:
		rotate(rotation_speed * delta)
	# Key is a scene sibling (not a child) so it doesn't rotate with the enemy
	if is_instance_valid(_key_pickup):
		_key_pickup.global_position = global_position + (-transform.y * 35.0)

# --- Key Logic ---

func _spawn_key() -> void:
	_key_pickup = Area2D.new()
	_key_pickup.name = "KeyPickup"
	_key_pickup.collision_mask = 0xFFFFFFFF  # catch player on any collision layer

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	_key_pickup.add_child(shape)

	var label = Label.new()
	label.text = "🗝"
	label.add_theme_font_size_override("font_size", 20)
	label.position = Vector2(-10, -12)
	_key_pickup.add_child(label)

	_key_pickup.body_entered.connect(_on_key_body_entered)
	# Deferred so the parent level scene is fully ready before we add to it
	call_deferred("_add_key_to_parent")

func _add_key_to_parent() -> void:
	if is_instance_valid(_key_pickup):
		get_parent().add_child(_key_pickup)
		_key_pickup.global_position = global_position + (-transform.x * 36.0)

func _on_key_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.collect_key()
		_key_pickup.queue_free()
		_key_pickup = null

func respawn_key() -> void:
	if has_key and not is_instance_valid(_key_pickup):
		_spawn_key()

# --- Sight ---

func _has_line_of_sight(target_position: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target_position)
	query.exclude = [self]  # prevent the ray from hitting the enemy itself

	var result = space_state.intersect_ray(query)

	# If nothing was hit, or what was hit isn't the player, a wall is in the way
	return not result.is_empty() and result["collider"].is_in_group("player")

func _on_vision_cone_body_entered(body) -> void:
	if body.is_in_group("player"):
		if _has_line_of_sight(body.global_position):
			body.die()

func _reset_game() -> void:
	get_tree().call_deferred("reload_current_scene")
