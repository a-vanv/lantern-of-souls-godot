extends CharacterBody2D

## ═══════════════════════════════════════════════════════════════
##  HUNTER — radar-scan enemy
##
##  State cycle:
##    SCAN ──(radar detects light)──► APPROACH
##    APPROACH ──(arrives at location)──► SEARCH
##    SEARCH ──(timer expires)──► SCAN
##    Any state ──(player enters vision cone)──► player.die()
##
##  Required scene nodes:
##    VisionCone              (Area2D)
##    VisionCone/CollisionShape2D
##    VisionCone/Polygon2D    ← tinted by state, copy from enemy.tscn
##
##  For pathfinding: add a NavigationRegion2D to your level scene.
##  Without one the Hunter still works, moving in straight lines.
##
##  NavigationAgent2D inspector settings:
##    Path Desired Distance   → 16.0   (was 4.0)
##    Path Postprocessing     → Corridorfunnel   (was Edgecentered)
## ═══════════════════════════════════════════════════════════════

enum State { SCAN, APPROACH, SEARCH }

# ── Movement ──────────────────────────────────────────────────
@export_group("Movement")
## Speed while walking toward the last known player position
@export var approach_speed: float = 80.0
## How quickly the Hunter turns to face its direction of travel (rad/s)
@export var rotation_speed: float = 3.0

# ── Patrol (optional) ─────────────────────────────────────────
@export_group("Patrol")
## World-space waypoints to walk between while in SCAN state.
## Leave empty for a stationary Hunter.
## Tip: read off coordinates from the Godot 2D editor's position bar.
@export var patrol_points: Array[Vector2] = []
## Speed while patrolling between waypoints
@export var patrol_speed: float = 50.0

# ── Radar Scan ────────────────────────────────────────────────
@export_group("Radar Scan")
## Seconds between radar pulses
@export var scan_interval: float = 6.0
## World-unit radius that the radar can detect player_light areas
@export var scan_radius: float = 1500.0
## If enabled, walls will also block the radar (more forgiving for the player)
@export var scan_needs_los: bool = false

# ── Search ────────────────────────────────────────────────────
@export_group("Search")
## Seconds the Hunter sweeps the area before giving up and returning to SCAN
@export var search_duration: float = 15.0
## Rotation speed while sweeping (rad/s)
@export var search_sweep_speed: float = 1.4
## Total arc covered by the sweep in degrees — split ±half from arrival angle
@export var search_sweep_degrees: float = 360.0

# ── Visuals ───────────────────────────────────────────────────
@export_group("Visuals")
## Show a pulsing circle at the detected player position (the "after-image")
@export var afterimage_enabled: bool = true
## Fill color of the after-image marker
@export var afterimage_color: Color = Color(1.00, 0.45, 0.00, 0.55)
## Radius of the after-image marker in world units
@export var afterimage_radius: float = 14.0
## Emit an expanding ring from the Hunter each time the radar fires
@export var scan_pulse_enabled: bool = true
## Color of the expanding radar ring
@export var pulse_color: Color = Color(1.00, 0.60, 0.00, 0.40)
## Vision cone tint while idle / patrolling
@export var cone_normal_color: Color = Color(0.35, 0.35, 0.90, 0.40)
## Vision cone tint while approaching the last known position
@export var cone_alert_color: Color = Color(1.00, 0.20, 0.10, 0.65)
## Vision cone tint while searching
@export var cone_search_color: Color = Color(1.00, 0.85, 0.00, 0.55)

# ── Key Settings ──────────────────────────────────────────────
@export_group("Key Settings")
@export var has_key: bool = false

# ── Private ───────────────────────────────────────────────────
var _state:             State   = State.SCAN
var _last_known_pos:    Vector2 = Vector2.ZERO

var _scan_timer:        float   = 0.0
var _search_timer:      float   = 0.0
var _search_base_rot:   float   = 0.0
var _search_offset:     float   = 0.0
var _search_dir:        float   = 1.0
var _patrol_index:      int     = 0

## Caches the last valid direction from the nav agent so the Hunter doesn't
## snap toward the player (through walls) during waypoint transitions
var _last_approach_dir: Vector2 = Vector2.RIGHT

## Spawn state — captured in _ready() and restored on player death
var _spawn_position:    Vector2
var _spawn_rotation:    float

## NavigationAgent2D must be a child node in the scene editor.
## Set its Path Desired Distance to 16 and Target Desired Distance to 16.
## Set Path Postprocessing to Corridorfunnel.
@onready var _nav: NavigationAgent2D = $NavigationAgent2D
var _afterimage:  Node2D
var _vision_poly: Polygon2D
@onready var _key_pickup: Area2D = $KeyPickup


# ═════════════════════════════════════════════════════
# LIFECYCLE
# ═════════════════════════════════════════════════════

func _ready() -> void:
	_spawn_position = global_position
	_spawn_rotation = rotation

	# Cache the vision cone's Polygon2D so we can tint it per-state
	if has_node("VisionCone/Polygon2D"):
		_vision_poly = $"VisionCone/Polygon2D"
	_set_cone_color(cone_normal_color)

	$VisionCone.body_entered.connect(_on_vision_cone_body_entered)

	# Build the after-image marker (drawn in world space, not relative to Hunter)
	if afterimage_enabled:
		_build_afterimage()

	# Stagger scan timers so multiple Hunters don't all pulse at once
	_scan_timer = randf_range(0.0, scan_interval)

	_key_pickup.visible = has_key
	if has_key:
		_key_pickup.body_entered.connect(_on_key_body_entered)

# ═════════════════════════════════════════════════════
# MAIN LOOP
# ═════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	# Vision cone check is always active regardless of state
	_poll_vision_cone()

	match _state:
		State.SCAN:     _tick_scan(delta)
		State.APPROACH: _tick_approach(delta)
		State.SEARCH:   _tick_search(delta)

	# Pin after-image to its world-space position and rotation, then animate alpha
	if _afterimage != null and _afterimage.visible:
		_afterimage.global_position = _last_known_pos
		_afterimage.global_rotation = 0.0
		_pulse_afterimage()
		
	if _key_pickup.visible:
		_key_pickup.global_position = global_position + (-global_transform.x * 35.0)

	move_and_slide()


# ═════════════════════════════════════════════════════
# STATE TICKS
# ═════════════════════════════════════════════════════

func _tick_scan(delta: float) -> void:
	# Optional patrol while waiting for the next radar pulse
	if patrol_points.is_empty():
		velocity = Vector2.ZERO
	else:
		_advance_patrol(delta)

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = scan_interval
		_fire_radar()


func _tick_approach(delta: float) -> void:
	# NOTE: _refresh_last_known() is intentionally NOT called here.
	# The Hunter commits to the position it saw during the radar scan and
	# walks there. It will not update the target until the next scan cycle.

	var to_target := _last_known_pos - global_position
	if to_target.length() < 20.0:
		velocity = Vector2.ZERO
		_enter_search()
		return

	# NOTE: target_position is set once in _enter_approach, not every frame,
	# so the Hunter follows the originally computed path without interruption.
	var next    := _nav.get_next_path_position()
	var to_next := next - global_position

	var dir: Vector2
	if to_next.length() > 4.0:
		dir = to_next.normalized()
		_last_approach_dir = dir	# cache every valid nav direction
	else:
		# Waypoint transition gap — hold the last known good direction
		# instead of snapping toward to_target (which points through walls)
		dir = _last_approach_dir

	rotation = lerp_angle(rotation, dir.angle(), rotation_speed * delta)
	velocity  = dir * approach_speed


func _tick_search(delta: float) -> void:
	velocity = Vector2.ZERO
	_search_timer -= delta

	# Ping-pong sweep around the arrival angle
	var half := deg_to_rad(search_sweep_degrees * 0.5)
	_search_offset += search_sweep_speed * _search_dir * delta
	if abs(_search_offset) >= half:
		_search_dir    *= -1.0
		_search_offset  = clamp(_search_offset, -half, half)
	rotation = _search_base_rot + _search_offset

	if _search_timer <= 0.0:
		_enter_scan()


# ═════════════════════════════════════════════════════
# RADAR
# ═════════════════════════════════════════════════════

func _fire_radar() -> void:
	if scan_pulse_enabled:
		_emit_scan_ring()

	# Check every node in the player_light group
	for light in get_tree().get_nodes_in_group("player_light"):
		if not light is Node2D:
			continue
		if global_position.distance_to(light.global_position) > scan_radius:
			continue
		if scan_needs_los and not _has_line_of_sight(light.global_position):
			continue
		# Detection — switch to APPROACH using the player's body position
		_enter_approach(light.get_parent().global_position)
		return  # Only react to the first light found


func _refresh_last_known() -> void:
	## Available if needed — updates last known pos while the light is still
	## visible. Not called during APPROACH by design: the Hunter commits to
	## the scanned position and does not track the player mid-approach.
	for light in get_tree().get_nodes_in_group("player_light"):
		if not light is Node2D:
			continue
		if global_position.distance_to(light.global_position) > scan_radius:
			continue
		if scan_needs_los and not _has_line_of_sight(light.global_position):
			continue
		_last_known_pos = light.get_parent().global_position
		return


# ═════════════════════════════════════════════════════
# TRANSITIONS
# ═════════════════════════════════════════════════════

func _enter_approach(pos: Vector2) -> void:
	_last_known_pos    = pos
	_state             = State.APPROACH
	# Seed direction cache toward the target so the first frame has a
	# sensible direction before any nav data arrives
	_last_approach_dir = (pos - global_position).normalized()
	# CHANGED: path is requested here once, not updated every frame in
	# _tick_approach — the Hunter walks to the scanned position and stops
	_nav.target_position = pos
	_set_cone_color(cone_alert_color)
	if afterimage_enabled and _afterimage != null:
		_afterimage.global_position = pos
		_afterimage.visible         = true


func _enter_search() -> void:
	_state           = State.SEARCH
	_search_timer    = search_duration
	_search_base_rot = rotation
	_search_offset   = 0.0
	_search_dir      = 1.0
	_set_cone_color(cone_search_color)


func _enter_scan() -> void:
	_state      = State.SCAN
	_scan_timer = scan_interval
	_set_cone_color(cone_normal_color)
	if _afterimage != null:
		_afterimage.visible = false


# ═════════════════════════════════════════════════════
# DETECTION  (same contract as enemy.gd)
# ═════════════════════════════════════════════════════

func _poll_vision_cone() -> void:
	## Catches overlaps that begin while the cone is resized (e.g. crouch radius)
	for area in $VisionCone.get_overlapping_areas():
		if area.is_in_group("player_light"):
			var player = area.get_parent()
			if _has_line_of_sight(player.global_position):
				player.die()
				return


func _on_vision_cone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if _has_line_of_sight(body.global_position):
			body.die()


func _has_line_of_sight(target: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var q     := PhysicsRayQueryParameters2D.create(global_position, target)
	q.exclude  = [self]
	var hit   := space.intersect_ray(q)
	return not hit.is_empty() and hit["collider"].is_in_group("player")


# ═════════════════════════════════════════════════════
# PATROL
# ═════════════════════════════════════════════════════

func _advance_patrol(delta: float) -> void:
	var target := patrol_points[_patrol_index]
	var dir    := target - global_position
	if dir.length() < 8.0:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		return
	dir      = dir.normalized()
	rotation = lerp_angle(rotation, dir.angle(), rotation_speed * delta)
	velocity = dir * patrol_speed


# ═════════════════════════════════════════════════════
# KEY LOGIC
# ═════════════════════════════════════════════════════

func _on_key_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.collect_key()
		_key_pickup.visible = false

func respawn_key() -> void:
	if has_key:
		_key_pickup.visible = true
	global_position = _spawn_position
	rotation        = _spawn_rotation
	_patrol_index   = 0
	_enter_scan()


# ═════════════════════════════════════════════════════
# VISUALS
# ═════════════════════════════════════════════════════

func _set_cone_color(c: Color) -> void:
	if _vision_poly != null:
		_vision_poly.color = c


func _build_afterimage() -> void:
	_afterimage         = Node2D.new()
	_afterimage.z_index = 5

	# --- Filled circle ---
	var circle := Polygon2D.new()
	var pts    := PackedVector2Array()
	for i in 20:
		var a := (float(i) / 20.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * afterimage_radius)
	circle.polygon = pts
	circle.color   = afterimage_color
	_afterimage.add_child(circle)

	# --- Cross-hair ---
	for axis in [Vector2.RIGHT, Vector2.UP]:
		var line           := Line2D.new()
		line.add_point(-axis * afterimage_radius * 0.65)
		line.add_point( axis * afterimage_radius * 0.65)
		line.default_color  = Color(1.0, 1.0, 1.0, 0.85)
		line.width          = 2.0
		_afterimage.add_child(line)

	add_child(_afterimage)
	_afterimage.visible = false


func _pulse_afterimage() -> void:
	## Gently fades the circle alpha in and out so it reads as a "ghost"
	var t     := Time.get_ticks_msec() * 0.005
	var alpha := sin(t) * 0.5 + 0.5	# oscillates 0 → 1
	var poly  := _afterimage.get_child(0) as Polygon2D
	if poly:
		var c  := afterimage_color
		c.a    = lerp(afterimage_color.a * 0.25, afterimage_color.a, alpha)
		poly.color = c


func _emit_scan_ring() -> void:
	## Spawns a temporary ring that expands to scan_radius and fades out
	var ring     := Polygon2D.new()
	ring.z_index  = 4
	var pts      := PackedVector2Array()
	for i in 32:
		var a := (float(i) / 32.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * 24.0)	# base size before scaling
	ring.polygon = pts
	ring.color   = pulse_color
	add_child(ring)

	var end_scale := Vector2.ONE * (scan_radius / 24.0)
	var tw        := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", end_scale, 0.7) \
	  .set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.7) \
	  .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)
