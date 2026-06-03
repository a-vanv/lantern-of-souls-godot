extends Area2D

@export_file("*.tscn") var next_scene: String = "res://scenes/main.tscn"

@onready var win_panel: Panel = $CanvasLayer/WinPanel
@onready var continue_button: Button = $CanvasLayer/WinPanel/VBoxContainer/ContinueButton

func _ready() -> void:
	win_panel.visible = false
	body_entered.connect(_on_body_entered)

	continue_button.pressed.connect(_on_continue_pressed)

func _on_body_entered(body: Node) -> void:
	if not body.has_method("refill_soul"):
		return

	win_panel.visible = true
	
	get_tree().paused = true

func _on_continue_pressed() -> void:
	get_tree().paused = false

	get_tree().reload_current_scene()
