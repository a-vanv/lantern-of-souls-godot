extends Node2D


var radius: float = 80.0
var color: Color = Color(1.0, 0.95, 0.6, 0.18)  # warm yellow, translucent

func _draw():
	draw_circle(Vector2.ZERO, radius, color)

func set_radius(new_radius: float):
	radius = new_radius
	queue_redraw()  # tells Godot to re-call _draw()
