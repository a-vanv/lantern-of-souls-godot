extends Area2D

# Whether this checkpoint has already been activated
var _activated: bool = false

func _ready() -> void:
	# Connect the body_entered signal from Area2D.
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	# Check that it's the player, and only trigger once per checkpoint.
	if _activated:
		return
	if not body is CharacterBody2D:
		return

	# Confirm it has the methods we expect before calling them.
	if body.has_method("refill_soul") and body.has_method("set_spawn"):
		_activated = true
		body.set_spawn(global_position)
		body.refill_soul()
		_on_activated()

func _on_activated() -> void:
	# Visual feedback — swap to a "lit" sprite, play a sound, etc.
	# For now just modulate it to signal it's been used.
	modulate = Color(1.0, 0.85, 0.2)  # golden glow
