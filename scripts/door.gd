extends StaticBody2D

# Attach to a StaticBody2D door scene.
# Requires a child Area2D named "DetectionArea" with its own CollisionShape2D.
# Set DetectionArea's collision mask to include the player's layer (layer 2 by default).

func _ready() -> void:
	$DetectionArea.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_key:
		body.use_key()
		queue_free()
