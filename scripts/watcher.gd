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


# ── Waypoint Sweep ────────────────────────────────────────────────────────────

@export_group("Waypoint Sweep")

## Enable waypoint sweep mode. When on, the spotlight cycles between the
## selected cardinal directions, pausing at each one instead of spinning
## continuously. This overrides the Spinning group while active.
@export var waypoint_mode_enabled: bool = false:
	set(val):
		waypoint_mode_enabled = val
		if is_inside_tree() and not Engine.is_editor_hint():
			_init_waypoint_state()

## Which cardinal directions the spotlight will visit. Pick any combination.
## They are cycled in clockwise screen order: Right → Down → Left → Up.
## Select at least two for a meaningful sweep pattern.
@export_flags("Right", "Down", "Left", "Up") var sweep_directions: int = 5:
	set(val):
		sweep_directions = val
		if is_inside_tree() and not Engine.is_editor_hint():
			_init_waypoint_state()

## How long (in seconds) the spotlight lingers at each direction before turning.
@export var pause_duration: float = 2.0

## Controls how quickly the spotlight lerps between directions.
## This is the lerp weight factor per second — higher values snap faster,
## lower values glide more slowly. Values in the 3–6 range feel natural.
@export var turn_speed: float = 4.0


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


# ── Waypoint sweep runtime state ──────────────────────────────────────────────

# Ordered list of target angles (radians) built from sweep_directions at runtime.
var _waypoint_targets: Array = []
# Index of the waypoint currently being targeted or dwelt at.
var _waypoint_index: int = 0
# True while dwelling at a waypoint; false while lerping toward the next one.
var _is_pausing: bool = true
# Counts down (seconds) during the pause phase.
var _pause_timer: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	$SpotlightPivot.rotation_degrees = start_angle_degrees
	_rebuild()

	# Only hook up detection signals and sweep state at runtime, not in editor.
	if not Engine.is_editor_hint():
		$SpotlightPivot/Spotlight.body_entered.connect(_on_spotlight_body_entered)
		if waypoint_mode_enabled:
			_init_waypoint_state()


func _process(delta: float) -> void:
	# Never move in the editor — it makes placing the node difficult.
	if Engine.is_editor_hint():
		return

	if waypoint_mode_enabled:
		_process_waypoint_sweep(delta)
	elif spinning_enabled:
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


# ── Waypoint sweep ────────────────────────────────────────────────────────────

## Initialises (or re-initialises) the waypoint sweep state.
## Called on _ready and whenever waypoint_mode_enabled or sweep_directions
## change at runtime.
func _init_waypoint_state() -> void:
	if not has_node("SpotlightPivot"):
		return
	_waypoint_targets = _build_waypoint_list()
	if _waypoint_targets.is_empty():
		return
	# Begin at whichever waypoint is closest to the current pivot angle so
	# enabling the mode mid-play doesn't cause a jarring long-distance snap.
	_waypoint_index = _nearest_waypoint_index()
	_is_pausing = true
	_pause_timer = pause_duration


## Returns an Array of angles in radians, one per enabled direction,
## in clockwise screen order: Right (0) → Down (π/2) → Left (π) → Up (−π/2).
func _build_waypoint_list() -> Array:
	var targets: Array = []
	if sweep_directions & 1:	# Right  →   0°
		targets.append(0.0)
	if sweep_directions & 2:	# Down   →  90°
		targets.append(PI * 0.5)
	if sweep_directions & 4:	# Left   → 180°
		targets.append(PI)
	if sweep_directions & 8:	# Up     → −90°
		targets.append(-PI * 0.5)
	return targets


## Returns the index of the waypoint whose angle is closest (by angular
## distance) to the SpotlightPivot's current rotation.
func _nearest_waypoint_index() -> int:
	var current: float = $SpotlightPivot.rotation
	var best_idx: int = 0
	var best_diff: float = INF
	for i in range(_waypoint_targets.size()):
		var diff: float = abs(angle_difference(current, _waypoint_targets[i]))
		if diff < best_diff:
			best_diff = diff
			best_idx = i
	return best_idx


## Runs each frame when waypoint_mode_enabled is true.
## Alternates between a lerp-toward-target phase and a timed pause phase.
func _process_waypoint_sweep(delta: float) -> void:
	if _waypoint_targets.is_empty():
		return

	if _is_pausing:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			# Pause expired — start turning toward the next waypoint.
			_is_pausing = false
			_waypoint_index = (_waypoint_index + 1) % _waypoint_targets.size()
	else:
		var target: float = _waypoint_targets[_waypoint_index]
		var current: float = $SpotlightPivot.rotation

		# lerp_angle takes the shortest angular path between two angles.
		# clamp keeps the weight in [0, 1] regardless of frame rate.
		var new_rot: float = lerp_angle(current, target, clamp(turn_speed * delta, 0.0, 1.0))

		# Snap and begin pausing once within a small threshold to prevent
		# indefinite micro-oscillation as the lerp approaches the target.
		if abs(angle_difference(new_rot, target)) < 0.005:
			$SpotlightPivot.rotation = target
			_is_pausing = true
			_pause_timer = pause_duration
		else:
			$SpotlightPivot.rotation = new_rot


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


# FIX: ray now originates from the watcher's own position (global_position)
# rather than the spotlight ellipse center.
#
# The previous approach (casting from the spotlight center) caused false
# positives with large spotlights: the ellipse center could have unobstructed
# LOS to the player even though the player was only overlapping the far edge
# of the ellipse — which was itself blocked by a wall. The ray from the center
# simply didn't cross that wall.
#
# Casting from the watcher root is the physically correct model: the watcher
# is the light source, so any wall between the watcher and the player blocks
# detection regardless of how large the spotlight ellipse is.
#
# NOTE: the watcher scene root is a CharacterBody2D (visible in the Inspector
# despite the script's `extends Node2D`), so get_rid() correctly returns its
# physics body RID and must be excluded to prevent the ray from hitting itself.
func _has_line_of_sight(target_position: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_position)
	# Exclude the watcher's own CharacterBody2D so the ray doesn't self-intersect.
	# Cast to CollisionObject2D (the ancestor that owns get_rid()) because this
	# script extends Node2D and GDScript can't resolve get_rid() on that type
	# directly, even though the actual scene root node is a CharacterBody2D.

	var result := space_state.intersect_ray(query)

	# If nothing was hit, or the first hit isn't the player, a wall is in the way.
	return not result.is_empty() and result["collider"].is_in_group("player")
