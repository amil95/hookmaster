extends CharacterBody2D

const BloodBurst = preload("res://scripts/blood_burst.gd")
const SPEED := 320.0
const JUMP_VELOCITY := -520.0
const GRAVITY := 1400.0
const JUMP_BUFFER_TIME := 0.12
const MIN_JUMP_HOLD_TIME := 0.1
const MAX_JUMPS := 2
const WALL_JUMP_HORIZONTAL_VELOCITY := 430.0
const WALL_JUMP_VERTICAL_VELOCITY := -500.0
const DASH_SPEED := 850.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 0.2
const ATTACK_COOLDOWN := 0.28
const ATTACK_RANGE := 105.0
const POGO_RANGE := 90.0
const POGO_BOUNCE_VELOCITY := -620.0
const BASE_ATTACK_DAMAGE := 1.0
const DAMAGE_BOOST_START_SPEED := SPEED
const MAX_DAMAGE_SPEED := DASH_SPEED
const RESET_MARGIN := 120.0
const HOOKSHOT_RANGE := 500.0
const HOOKSHOT_PROJECTILE_SPEED := 1700.0
const HOOKSHOT_SWING_ACCELERATION := 950.0
const HOOKSHOT_TAUT_TOLERANCE := 2.0
const HOOKSHOT_ATTACH_IMPULSE := 220.0

var jump_buffer_remaining := 0.0
var jump_cut_delay_remaining := 0.0
var jump_released_early := false
var jumps_remaining := MAX_JUMPS
var started_jump_from_ground := false
var in_freefall := false
var dash_remaining := 0.0
var dash_cooldown_remaining := 0.0
var facing_direction := 1.0
var attack_cooldown_remaining := 0.0
var slow_remaining := 0.0
var slow_multiplier := 1.0
var reset_pending := false
var hookshot_attached := false
var hookshot_firing := false
var hook_anchor := Vector2.ZERO
var hook_anchor_body: Node2D
var hook_anchor_local := Vector2.ZERO
var hook_length := 0.0
var hook_projectile_position := Vector2.ZERO
var hook_projectile_direction := Vector2.ZERO
var ledge_grabbing := false
var ledge_top_y := 0.0
var ledge_wall_x := 0.0
var ledge_tween: Tween

@onready var sword_pivot: Node2D = $SwordPivot
@onready var sword_hitbox: Area2D = $SwordPivot/Hitbox
@onready var player_sprite: Sprite2D = $Sprite
@onready var reset_message: Label = $"../HUD/ResetMessage"
@onready var dash_trail: Polygon2D = $DashTrail
@onready var hook_line: Line2D = $HookLine
@onready var hook_head: Polygon2D = $HookHead

func _physics_process(delta: float) -> void:
	jump_buffer_remaining = maxf(jump_buffer_remaining - delta, 0.0)
	jump_cut_delay_remaining = maxf(jump_cut_delay_remaining - delta, 0.0)
	dash_cooldown_remaining = maxf(dash_cooldown_remaining - delta, 0.0)
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	slow_remaining = maxf(slow_remaining - delta, 0.0)
	if slow_remaining == 0.0:
		slow_multiplier = 1.0
	var wants_upswing := Input.is_action_just_pressed("attack") and Input.is_action_pressed("up_attack") and not Input.is_action_pressed("pogo")
	if Input.is_action_just_pressed("jump"):
		jump_buffer_remaining = JUMP_BUFFER_TIME
	if Input.is_action_just_released("jump"):
		jump_released_early = true
	if jump_released_early and jump_cut_delay_remaining == 0.0 and velocity.y < 0.0:
		velocity.y = 0.0
		jump_released_early = false
	if Input.is_action_just_pressed("reset_scene"):
		reset_scene("Resetting…")
		return
	if is_on_floor():
		jumps_remaining = MAX_JUMPS
		started_jump_from_ground = false
		in_freefall = false
	elif not started_jump_from_ground and not in_freefall:
		# Walking off a platform (or spawning in midair) gets one recovery jump.
		jumps_remaining = 1
		in_freefall = true

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing_direction = direction
		player_sprite.flip_h = facing_direction < 0.0
	if Input.is_action_just_pressed("hookshot") and not hookshot_attached and not hookshot_firing:
		launch_hookshot_projectile()
	if hookshot_firing:
		if Input.is_action_pressed("hookshot"):
			update_hookshot_projectile(delta)
		else:
			cancel_hookshot_projectile()
	if hookshot_attached and not Input.is_action_pressed("hookshot"):
		detach_hookshot()
	if ledge_grabbing:
		update_ledge_grab(direction)
		return

	if hookshot_attached:
		if Input.is_action_just_pressed("jump") and jumps_remaining > 0:
			# Keep the tangential rope momentum, then spend the air jump to launch away.
			detach_hookshot()
			velocity.y = JUMP_VELOCITY
			jumps_remaining -= 1
			started_jump_from_ground = true
			jump_buffer_remaining = 0.0
			jump_cut_delay_remaining = MIN_JUMP_HOLD_TIME
			jump_released_early = not Input.is_action_pressed("jump")
			play_double_jump_animation()
			return
		if Input.is_action_just_pressed("attack") and attack_cooldown_remaining == 0.0:
			attack_cooldown_remaining = ATTACK_COOLDOWN
			attack(wants_upswing)
		update_hookshot_swing(delta)
		reset_if_out_of_bounds()
		return

	if Input.is_action_just_pressed("dash") and dash_cooldown_remaining == 0.0:
		dash_remaining = DASH_TIME
		dash_cooldown_remaining = DASH_TIME + DASH_COOLDOWN
		play_dash_animation()
	if Input.is_action_just_pressed("attack") and not is_on_floor() and Input.is_action_pressed("pogo") and attack_cooldown_remaining == 0.0:
		attack_cooldown_remaining = ATTACK_COOLDOWN
		pogo()
	elif Input.is_action_just_pressed("attack") and attack_cooldown_remaining == 0.0:
		attack_cooldown_remaining = ATTACK_COOLDOWN
		attack(wants_upswing)

	if dash_remaining > 0.0:
		dash_remaining = maxf(dash_remaining - delta, 0.0)
		velocity = Vector2(facing_direction * DASH_SPEED * slow_multiplier, 0.0)
		move_and_slide()
		if dash_remaining == 0.0:
			end_dash_animation()
		reset_if_out_of_bounds()
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if jump_buffer_remaining > 0.0 and not is_on_floor() and is_on_wall():
		perform_wall_jump()
	elif jump_buffer_remaining > 0.0 and jumps_remaining > 0:
		var is_double_jump := not is_on_floor() and started_jump_from_ground and jumps_remaining == 1
		if is_on_floor():
			started_jump_from_ground = true
		velocity.y = JUMP_VELOCITY
		jumps_remaining -= 1
		jump_buffer_remaining = 0.0
		jump_cut_delay_remaining = MIN_JUMP_HOLD_TIME
		jump_released_early = not Input.is_action_pressed("jump")
		if is_double_jump:
			play_double_jump_animation()

	velocity.x = move_toward(velocity.x, direction * SPEED * slow_multiplier, SPEED * 8.0 * delta)
	move_and_slide()
	if try_grab_ledge():
		return
	reset_if_out_of_bounds()

func perform_wall_jump() -> void:
	var wall_normal := get_wall_normal()
	velocity = Vector2(wall_normal.x * WALL_JUMP_HORIZONTAL_VELOCITY, WALL_JUMP_VERTICAL_VELOCITY)
	facing_direction = wall_normal.x
	player_sprite.flip_h = facing_direction < 0.0
	started_jump_from_ground = true
	jumps_remaining = 1
	jump_buffer_remaining = 0.0
	jump_cut_delay_remaining = MIN_JUMP_HOLD_TIME
	jump_released_early = not Input.is_action_pressed("jump")

func attack(upward := false) -> void:
	sword_pivot.visible = true
	sword_pivot.scale = Vector2.ONE
	var start_angle := 0.0
	var end_angle := 0.0
	if upward:
		# Sweep through the space directly above the character.
		sword_pivot.position = Vector2(0.0, -14.0)
		if facing_direction > 0.0:
			start_angle = deg_to_rad(-160.0)
			end_angle = deg_to_rad(-20.0)
		else:
			start_angle = deg_to_rad(-20.0)
			end_angle = deg_to_rad(-160.0)
	elif facing_direction > 0.0:
		sword_pivot.position = Vector2(24.0, -8.0)
		start_angle = deg_to_rad(55.0)
		end_angle = deg_to_rad(-55.0)
	else:
		sword_pivot.position = Vector2(-24.0, -8.0)
		start_angle = deg_to_rad(125.0)
		end_angle = deg_to_rad(235.0)
	sword_pivot.rotation = start_angle
	var swing := create_tween()
	swing.tween_property(sword_pivot, "rotation", end_angle, 0.13)
	swing.tween_interval(0.12)

	# The hitbox travels with the visible blade. Check it on every physics frame,
	# while limiting each target to one hit per individual swing.
	var hit_targets: Dictionary = {}
	while swing.is_running():
		await get_tree().physics_frame
		for target in sword_hitbox.get_overlapping_bodies():
			if target.is_in_group("damageable") and not hit_targets.has(target):
				hit_targets[target] = true
				target.call("take_damage", calculate_attack_damage())
		for target in sword_hitbox.get_overlapping_areas():
			if target.is_in_group("damageable") and not hit_targets.has(target):
				hit_targets[target] = true
				target.call("take_damage", calculate_attack_damage())
	sword_pivot.visible = false

func apply_movement_slow(duration: float, multiplier: float) -> void:
	slow_remaining = maxf(slow_remaining, duration)
	slow_multiplier = minf(slow_multiplier, multiplier)

func calculate_attack_damage() -> float:
	var speed_ratio := clampf((velocity.length() - DAMAGE_BOOST_START_SPEED) / (MAX_DAMAGE_SPEED - DAMAGE_BOOST_START_SPEED), 0.0, 1.0)
	var damage_multiplier := lerpf(1.0, 2.0, speed_ratio)
	return BASE_ATTACK_DAMAGE * damage_multiplier

func pogo() -> void:
	sword_pivot.visible = true
	sword_pivot.position = Vector2(0.0, 24.0)
	sword_pivot.scale = Vector2.ONE
	sword_pivot.rotation = deg_to_rad(90.0)
	var thrust := create_tween()
	thrust.tween_property(sword_pivot, "position:y", 42.0, 0.08)

	await get_tree().create_timer(0.06).timeout
	for target in get_tree().get_nodes_in_group("damageable"):
		var offset: Vector2 = target.global_position - global_position
		if absf(offset.x) < 48.0 and offset.y > 0.0 and offset.y <= POGO_RANGE:
			target.call("take_damage", calculate_attack_damage())
			velocity.y = POGO_BOUNCE_VELOCITY
			# A connected pogo bounce refreshes the single aerial jump.
			jumps_remaining = max(jumps_remaining, 1)
			started_jump_from_ground = true

	await get_tree().create_timer(0.12).timeout
	sword_pivot.visible = false

func reset_if_out_of_bounds() -> void:
	var screen := get_viewport().get_visible_rect().grow(RESET_MARGIN)
	if not reset_pending and not screen.has_point(global_position):
		reset_scene("Fell! Resetting…")

func reset_scene(message: String) -> void:
	if reset_pending:
		return
	reset_pending = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	if message.begins_with("Axe"):
		BloodBurst.spawn(get_parent(), global_position)
	reset_message.text = message
	reset_message.visible = true
	await get_tree().create_timer(0.45).timeout
	get_tree().reload_current_scene()

func play_dash_animation() -> void:
	dash_trail.visible = true
	dash_trail.scale.x = facing_direction
	dash_trail.modulate = Color(0.3, 0.85, 1.0, 0.65)
	player_sprite.modulate = Color(0.55, 0.9, 1.0)
	var dash_squash := create_tween()
	dash_squash.tween_property(player_sprite, "scale", Vector2(0.78, 0.34), 0.05)

func end_dash_animation() -> void:
	dash_trail.visible = false
	var dash_reset := create_tween()
	dash_reset.set_parallel(true)
	dash_reset.tween_property(player_sprite, "scale", Vector2(0.5, 0.5), 0.1)
	dash_reset.tween_property(player_sprite, "modulate", Color.WHITE, 0.1)

func play_double_jump_animation() -> void:
	player_sprite.rotation = 0.0
	player_sprite.modulate = Color(0.55, 0.9, 1.0)
	var jump_effect := create_tween()
	jump_effect.set_parallel(true)
	jump_effect.tween_property(player_sprite, "rotation", TAU, 0.24)
	jump_effect.tween_property(player_sprite, "scale", Vector2(0.68, 0.38), 0.1)
	jump_effect.chain().tween_property(player_sprite, "scale", Vector2(0.5, 0.5), 0.14)
	jump_effect.chain().tween_property(player_sprite, "modulate", Color.WHITE, 0.14)

func launch_hookshot_projectile() -> void:
	hookshot_firing = true
	hook_projectile_position = global_position
	hook_projectile_direction = Vector2(facing_direction, -1.0).normalized()
	hook_line.width = 3.0
	hook_head.scale = Vector2.ONE
	update_hookshot_projectile_visual()

func update_hookshot_projectile(delta: float) -> void:
	var previous_position := hook_projectile_position
	var next_position := previous_position + hook_projectile_direction * HOOKSHOT_PROJECTILE_SPEED * delta
	var query := PhysicsRayQueryParameters2D.create(previous_position, next_position)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		hook_projectile_position = hit.position
		attach_hookshot(hit)
		return
	hook_projectile_position = next_position
	update_hookshot_projectile_visual()
	if global_position.distance_to(hook_projectile_position) >= HOOKSHOT_RANGE:
		cancel_hookshot_projectile()

func update_hookshot_projectile_visual() -> void:
	var local_head := to_local(hook_projectile_position)
	hook_line.points = PackedVector2Array([Vector2.ZERO, local_head])
	hook_line.visible = true
	hook_head.position = local_head
	hook_head.visible = true

func cancel_hookshot_projectile() -> void:
	hookshot_firing = false
	hook_line.visible = false
	hook_head.visible = false

func attach_hookshot(hit: Dictionary) -> void:
	hookshot_firing = false

	hookshot_attached = true
	# Grappling a surface also refreshes the single aerial jump for the release.
	jumps_remaining = max(jumps_remaining, 1)
	started_jump_from_ground = true
	hook_anchor = hit.position
	# Keep a platform-local anchor when possible. This makes a scrolling platform
	# carry the rope (and its swinging player) rather than leaving it behind.
	if hit.collider is Node2D:
		hook_anchor_body = hit.collider as Node2D
		hook_anchor_local = hook_anchor_body.to_local(hook_anchor)
	else:
		hook_anchor_body = null
	hook_length = global_position.distance_to(hook_anchor)
	var rope_direction := (global_position - hook_anchor).normalized()
	var tangent := Vector2(-rope_direction.y, rope_direction.x)
	if tangent.x * facing_direction < 0.0:
		tangent = -tangent
	velocity += tangent * HOOKSHOT_ATTACH_IMPULSE
	hook_line.width = 4.0
	hook_head.scale = Vector2.ONE
	update_hookshot_visual()

func update_hookshot_swing(delta: float) -> void:
	update_moving_hook_anchor()
	velocity.y += GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		detach_hookshot()
		return

	var rope_direction := global_position - hook_anchor
	if rope_direction.length() > 0.0:
		rope_direction = rope_direction.normalized()
		# Always project onto the rope radius: no slack means no spring-back.
		global_position = hook_anchor + rope_direction * hook_length
		velocity -= rope_direction * velocity.dot(rope_direction)
		if absf(rope_direction.angle_to(Vector2.DOWN)) >= deg_to_rad(80.0):
			detach_hookshot()
			return
	update_hookshot_visual()

func update_moving_hook_anchor() -> void:
	if not is_instance_valid(hook_anchor_body):
		return
	var previous_anchor := hook_anchor
	hook_anchor = hook_anchor_body.to_global(hook_anchor_local)
	# Carry the character by the exact platform displacement. Velocity remains
	# relative to that platform, which keeps a scrolling-platform swing natural.
	global_position += hook_anchor - previous_anchor

func update_hookshot_visual() -> void:
	var local_anchor := to_local(hook_anchor)
	hook_line.points = PackedVector2Array([Vector2.ZERO, local_anchor])
	hook_line.visible = true
	hook_head.position = local_anchor
	hook_head.visible = true

func detach_hookshot() -> void:
	# A rope only permits tangential motion. Preserve that exact release vector.
	var rope_direction := (global_position - hook_anchor).normalized()
	var tangent := Vector2(-rope_direction.y, rope_direction.x)
	velocity = tangent * velocity.dot(tangent)
	hookshot_attached = false
	hook_anchor_body = null
	hook_line.visible = false
	hook_head.visible = false

func try_grab_ledge() -> bool:
	if is_on_floor() or velocity.y < 0.0:
		return false
	var side := Vector2(facing_direction, 0.0)
	var physics := get_world_2d().direct_space_state
	var wall_query := PhysicsRayQueryParameters2D.create(global_position + Vector2(side.x * 18.0, -10.0), global_position + Vector2(side.x * 44.0, -10.0))
	wall_query.exclude = [get_rid()]
	wall_query.collision_mask = 1
	var wall_hit := physics.intersect_ray(wall_query)
	if wall_hit.is_empty() or not wall_hit.collider is TileMapLayer:
		return false

	var clear_query := PhysicsRayQueryParameters2D.create(global_position + Vector2(side.x * 18.0, -48.0), global_position + Vector2(side.x * 44.0, -48.0))
	clear_query.exclude = [get_rid()]
	clear_query.collision_mask = 1
	if not physics.intersect_ray(clear_query).is_empty():
		return false

	var terrain: TileMapLayer = wall_hit.collider
	var cell := terrain.local_to_map(terrain.to_local(wall_hit.position))
	var cell_center := terrain.to_global(terrain.map_to_local(cell))
	ledge_top_y = cell_center.y - 32.0
	ledge_wall_x = wall_hit.position.x
	ledge_grabbing = true
	velocity = Vector2.ZERO
	global_position = Vector2(ledge_wall_x - side.x * 28.0, ledge_top_y + 16.0)
	play_ledge_grab_animation()
	return true

func update_ledge_grab(direction: float) -> void:
	velocity = Vector2.ZERO
	if Input.is_action_just_pressed("jump"):
		ledge_grabbing = false
		end_ledge_grab_animation()
		jump_buffer_remaining = 0.0
		global_position = Vector2(ledge_wall_x + facing_direction * 35.0, ledge_top_y - 26.0)
		return
	if direction != 0.0 and direction != facing_direction:
		ledge_grabbing = false
		end_ledge_grab_animation()
		velocity.y = 80.0

func play_ledge_grab_animation() -> void:
	if ledge_tween:
		ledge_tween.kill()
	player_sprite.rotation = deg_to_rad(-8.0 * facing_direction)
	player_sprite.scale = Vector2(0.54, 0.45)
	player_sprite.modulate = Color(1.0, 0.83, 0.48)
	ledge_tween = create_tween().set_loops()
	ledge_tween.tween_property(player_sprite, "position:y", -3.0, 0.22).set_trans(Tween.TRANS_SINE)
	ledge_tween.tween_property(player_sprite, "position:y", 2.0, 0.22).set_trans(Tween.TRANS_SINE)

func end_ledge_grab_animation() -> void:
	if ledge_tween:
		ledge_tween.kill()
	var recover := create_tween()
	recover.set_parallel(true)
	recover.tween_property(player_sprite, "position", Vector2.ZERO, 0.1)
	recover.tween_property(player_sprite, "rotation", 0.0, 0.1)
	recover.tween_property(player_sprite, "scale", Vector2(0.5, 0.5), 0.1)
	recover.tween_property(player_sprite, "modulate", Color.WHITE, 0.1)
