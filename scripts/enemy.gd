extends CharacterBody2D

func _ready():
	$VisionCone.body_entered.connect(_on_vision_cone_body_entered)

func _physics_process(_delta):
	# Poll overlapping areas every frame — catches radius-resize overlaps
	for area in $VisionCone.get_overlapping_areas():
		if area.is_in_group("player_light"):
			var player = area.get_parent()
			if _has_line_of_sight(player.global_position):
				player.die()
				return

func _has_line_of_sight(target_position: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target_position)
	query.exclude = [self]  # prevent the ray from hitting the enemy itself
	
	var result = space_state.intersect_ray(query)
	
	# If nothing was hit, or what was hit isn't the player, a wall is in the way
	return not result.is_empty() and result["collider"].is_in_group("player")

func _on_vision_cone_body_entered(body):
	if body.is_in_group("player"):
		if _has_line_of_sight(body.global_position):
			body.die()

func _reset_game():
	get_tree().call_deferred("reload_current_scene")
