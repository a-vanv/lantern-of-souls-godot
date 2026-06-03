# watcher.gd
#
# A stationary overhead enemy that sweeps an elliptical spotlight across the
# ground. If the player's body enters the spotlight, they are sent back to their
# last checkpoint via player.die().
#
# ── Required scene structure ─────────────────────────────────────────────────
#
#   Watcher          (Node2D)   ← attach this script
#   ├── Sprite2D                ← optional visual for the watcher "body"
#   └── SpotlightPivot          (Node2D)
#       └── Spotlight           (Area2D)
#           ├── CollisionShape2D
#           └── Polygon2D
#
# The CollisionShape2D and Polygon2D are built at runtime by _rebuild(), so
# leave them empty in the editor — they will be generated on _ready().
#
# ── Collision layer note ──────────────────────────────────────────────────────
#
# On the Spotlight Area2D, set the collision mask to include the layer your
# player CharacterBody2D lives on, so body_entered fires correctly.
#
# ─────────────────────────────────────────────────────────────────────────────

@tool
extends Node2D


# ── Spinning ──────────────────────────────────────────────────────────────────

@export_group("Spinning")

## Master toggle — disabling this freezes the spotlight in place.
@export var spinning_enabled: bool = true

## How fast the spotlight orbits, in radians per second.
@export var rotation_speed: float = 1.0

## Orbit direction. True = clockwise, False = counter-clockwise.
@export var clockwise: bool = true

## Starting angle of the spotlight in degrees (0 = pointing right).
@export var start_angle_degrees: float = 0.0


# ── Spotlight Shape ───────────────────────────────────────────────────────────

@export_group("Spotlight Shape")

## Distance from the Watcher centre to the middle of the spotlight ellipse.
## Increase this until the spotlight no longer overlaps the watcher sprite.
@export var spotlight_distance: float = 150.0:
	set(val):
		spotlight_distance = val
		if is_inside_tree():
			_rebuild()

## Total width of the ellipse (diameter along the horizontal axis).
@export var spotlight_width: float = 100.0:
	set(val):
		spotlight_width = val
		if is_inside_tree():
			_rebuild()

## Total height of the ellipse (diameter along the vertical axis).
@export var spotlight_height: float = 60.0:
	set(val):
		spotlight_height = val
		if is_inside_tree():
			_rebuild()

## Vertex count used to approximate the ellipse. Higher = smoother edges.
@export_range(6, 64) var ellipse_resolution: int = 32:
	set(val):
		ellipse_resolution = val
		if is_inside_tree():
			_rebuild()


# ── Appearance ────────────────────────────────────────────────────────────────

@export_group("Appearance")

## Tint and opacity of the spotlight visual drawn on screen.
@export var spotlight_color: Color = Color(1.0, 0.95, 0.6, 0.45):
	set(val):
		spotlight_color = val
		if is_inside_tree():
			_rebuild()

## Hide the spotlight visual without disabling collision detection.
@export var show_spotlight_visual: bool = true:
	set(val):
		show_spotlight_visual = val
		if is_inside_tree():
			_rebuild()


# ── Detection ─────────────────────────────────────────────────────────────────

@export_group("Detection")

## Master switch — disable to make the spotlight purely decorative.
@export var detection_enabled: bool = true


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	$SpotlightPivot.rotation_degrees = start_angle_degrees
	_rebuild()

	# Only hook up detection signals at runtime, not in the editor.
	if not Engine.is_editor_hint():
		$SpotlightPivot/Spotlight.body_entered.connect(_on_spotlight_body_entered)


func _process(delta: float) -> void:
	# Never spin in the editor — it makes placing the node difficult.
	if Engine.is_editor_hint():
		return

	if spinning_enabled:
		var dir := 1.0 if clockwise else -1.0
		$SpotlightPivot.rotate(rotation_speed * delta * dir)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not detection_enabled:
		return

	# Poll overlapping bodies every physics tick so a player standing still is
	# caught when the spotlight rotates into them (body_entered alone won't fire
	# for a stationary body that an area sweeps over).
	# CHANGED: added _has_line_of_sight check so walls block body detection too.
	for body in $SpotlightPivot/Spotlight.get_overlapping_bodies():
		if body.is_in_group("player"):
			if _has_line_of_sight(body.global_position):
				body.die()
				return

	# NEW: player_light area detection — mirrors the base enemy behaviour.
	# FIXED: was $VisionCone (wrong node); Spotlight IS the detection zone.
	for area in $SpotlightPivot/Spotlight.get_overlapping_areas():
		if area.is_in_group("player_light"):
			var player = area.get_parent()
			if _has_line_of_sight(player.global_position):
				player.die()
				return


# ── Rebuild ───────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	# Guard against running before the scene tree is ready.
	if not has_node("SpotlightPivot/Spotlight"):
		return

	var area: Area2D = $SpotlightPivot/Spotlight

	# Shift the Area2D along the pivot's local X axis so the spotlight is
	# offset from the watcher body by spotlight_distance units.
	area.position = Vector2(spotlight_distance, 0.0)

	# Generate the ellipse point cloud.
	# (Godot 4 has no EllipseShape2D, so we use ConvexPolygonShape2D.)
	var n: int = clampi(ellipse_resolution, 6, 64)
	var pts := PackedVector2Array()
	for i in range(n):
		var a := (TAU / n) * i
		pts.append(Vector2(
			cos(a) * spotlight_width * 0.5,
			sin(a) * spotlight_height * 0.5
		))

	# ── Collision shape ───────────────────────────────────────────────────────
	var shape := ConvexPolygonShape2D.new()
	shape.points = pts
	$SpotlightPivot/Spotlight/CollisionShape2D.shape = shape

	# ── Visual polygon ────────────────────────────────────────────────────────
	var poly: Polygon2D = $SpotlightPivot/Spotlight/Polygon2D
	poly.polygon = pts
	poly.color = spotlight_color
	poly.visible = show_spotlight_visual


# ── Detection handlers ────────────────────────────────────────────────────────

func _on_spotlight_body_entered(body: Node2D) -> void:
	if not detection_enabled:
		return
	if body.is_in_group("player"):
		# CHANGED: added line of sight check — walls now block the signal path too.
		if _has_line_of_sight(body.global_position):
			body.die()


# CHANGED: ray now originates from the spotlight's world position rather than
# the watcher root. This means a wall between the light pool and the player
# correctly blocks detection, which is the physically intuitive behaviour.
#
# FIXED: query.exclude now uses the Spotlight Area2D's RID via .get_rid().
# The watcher root is a plain Node2D with no physics RID, so passing [self]
# as in enemy.gd would be a type error here.
func _has_line_of_sight(target_position: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var spotlight_pos: Vector2 = $SpotlightPivot/Spotlight.global_position
	var query := PhysicsRayQueryParameters2D.create(spotlight_pos, target_position)
	query.exclude = [$SpotlightPivot/Spotlight.get_rid()]

	var result := space_state.intersect_ray(query)

	# If nothing was hit, or the hit collider isn't the player, a wall is in the way.
	return not result.is_empty() and result["collider"].is_in_group("player")
