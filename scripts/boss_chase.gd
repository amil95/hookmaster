extends Node2D

const SURVIVAL_TIME := 30.0
const BASE_SCROLL_SPEED := 335.0
const MAX_SCROLL_SPEED := 620.0
const SPEED_UP_START_X := 820.0
const RIGHT_SOFT_LIMIT_X := 1040.0
const PLATFORM_HEIGHT := 24.0
# Lower routes are now uncommon. Most generated footing is elevated so the
# hookshot becomes the primary way to preserve speed through the chase.
const PLATFORM_Y := [535.0, 455.0, 455.0, 375.0, 375.0, 305.0]
const UPPER_PLATFORM_Y := [155.0, 225.0, 295.0]
const FloatingEnemy = preload("res://scripts/floating_enemy.gd")

@onready var player: CharacterBody2D = $Player
@onready var platform_stream: Node2D = $PlatformStream
@onready var boss: Node2D = $Boss
@onready var enemy_stream: Node2D = $EnemyStream
@onready var shard_stream: Node2D = $ShardStream
@onready var timer_label: Label = $HUD/TimerLabel
@onready var result_label: Label = $HUD/ResultLabel

var elapsed := 0.0
var escape_progress := 0.0
var next_platform_x := 0.0
var boss_speed := 24.0
var boss_slow_remaining := 0.0
var boss_slow_multiplier := 1.0
var boss_hit_tween: Tween
var complete := false
var rng := RandomNumberGenerator.new()
var active_scroll_speed := BASE_SCROLL_SPEED
var enemy_spawn_remaining := 2.5
var next_main_platform_is_one_way := false

func _ready() -> void:
	rng.randomize()
	# A generous runway before the first random gap.
	add_platform(-100.0, 1050.0, 610.0)
	next_platform_x = 1050.0

func _physics_process(delta: float) -> void:
	if complete:
		return

	elapsed += delta
	update_scroll_speed()
	move_platforms(active_scroll_speed, delta)
	move_enemies(active_scroll_speed, delta)
	move_shards(delta)
	# The world is a conveyor: ordinary running is just below neutral, while
	# dashes and hook movement earn forward progress and a faster escape.
	# A hooked player is carried by the moving hook platform in player.gd.
	# Applying the conveyor here too would move them twice per frame.
	if not player.hookshot_attached:
		player.position.x -= active_scroll_speed * delta
	if player.position.x > RIGHT_SOFT_LIMIT_X:
		player.position.x = RIGHT_SOFT_LIMIT_X
		player.velocity.x = minf(player.velocity.x, 0.0)
	# Faster world speed is an explicit reward: it advances the survival goal faster.
	escape_progress += delta * (active_scroll_speed / BASE_SCROLL_SPEED)
	update_timer()
	spawn_ahead()
	spawn_enemies(delta)
	update_boss(delta)

	if escape_progress >= SURVIVAL_TIME:
		complete = true
		result_label.text = "ESCAPED!"
		result_label.visible = true
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func update_timer() -> void:
	var time_multiplier := active_scroll_speed / BASE_SCROLL_SPEED
	var remaining := maxf(0.0, SURVIVAL_TIME - escape_progress)
	timer_label.text = "ESCAPE IN %.1f  •  %.1fx SPEED" % [remaining, time_multiplier]

func update_scroll_speed() -> void:
	var forward_pressure := maxf(player.position.x - SPEED_UP_START_X, 0.0)
	active_scroll_speed = clampf(BASE_SCROLL_SPEED + forward_pressure * 1.45, BASE_SCROLL_SPEED, MAX_SCROLL_SPEED)

func spawn_ahead() -> void:
	while next_platform_x < 1550.0:
		var gap := rng.randf_range(50.0, 115.0)
		var width := rng.randf_range(180.0, 320.0)
		var height: float = float(PLATFORM_Y[rng.randi_range(0, PLATFORM_Y.size() - 1)])
		add_platform(next_platform_x + gap, width, height, next_main_platform_is_one_way)
		next_main_platform_is_one_way = not next_main_platform_is_one_way
		# Floating platforms create optional hookshot routes above the main path.
		if rng.randf() < 0.72:
			var upper_y: float = float(UPPER_PLATFORM_Y[rng.randi_range(0, UPPER_PLATFORM_Y.size() - 1)])
			var upper_width := rng.randf_range(120.0, 210.0)
			add_platform(next_platform_x + gap + rng.randf_range(50.0, 170.0), upper_width, upper_y, next_main_platform_is_one_way)
		next_platform_x += gap + width

func add_platform(x: float, width: float, y: float, one_way := false) -> void:
	var platform := StaticBody2D.new()
	platform.position = Vector2(x + width * 0.5, y)
	platform.add_to_group("chase_platform")
	if one_way:
		platform.add_to_group("one_way_platform")
	platform.set_meta("width", width)

	var visual := Polygon2D.new()
	visual.color = Color("4d8fff") if one_way else Color("43b868")
	visual.polygon = PackedVector2Array([
		Vector2(-width * 0.5, -PLATFORM_HEIGHT * 0.5), Vector2(width * 0.5, -PLATFORM_HEIGHT * 0.5),
		Vector2(width * 0.5, PLATFORM_HEIGHT * 0.5), Vector2(-width * 0.5, PLATFORM_HEIGHT * 0.5)
	])
	platform.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, PLATFORM_HEIGHT)
	collision.shape = shape
	collision.one_way_collision = one_way
	platform.add_child(collision)
	platform_stream.add_child(platform)
	# The high route is hazardous: use it as a hook anchor and swing past the
	# spikes rather than treating every platform as a safe landing.
	var spike_chance := 0.18
	if y <= 460.0:
		spike_chance = 0.68
	elif y <= 540.0:
		spike_chance = 0.38
	if x > 800.0 and rng.randf() < spike_chance:
		add_spikes(platform, width)

func add_spikes(platform: StaticBody2D, width: float) -> void:
	var spike := Area2D.new()
	spike.position = Vector2(rng.randf_range(-width * 0.3, width * 0.3), -PLATFORM_HEIGHT * 0.5 - 12.0)
	spike.collision_layer = 0
	spike.collision_mask = 1
	spike.body_entered.connect(_on_hazard_body_entered)

	var visual := Polygon2D.new()
	visual.color = Color(0.95, 0.32, 0.28)
	visual.polygon = PackedVector2Array([
		Vector2(-30, 12), Vector2(-20, -12), Vector2(-10, 12),
		Vector2(0, -12), Vector2(10, 12), Vector2(20, -12), Vector2(30, 12)
	])
	spike.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(58, 20)
	collision.shape = shape
	spike.add_child(collision)
	platform.add_child(spike)

func _on_hazard_body_entered(body: Node2D) -> void:
	if complete or not body.is_in_group("player"):
		return
	body.call("reset_scene", "Spikes! Resetting…")

func move_platforms(scroll_speed: float, delta: float) -> void:
	for platform in platform_stream.get_children():
		platform.position.x -= scroll_speed * delta
		if platform.position.x + float(platform.get_meta("width")) * 0.5 < -120.0:
			platform.queue_free()
	# Keep the spawn coordinate in the same moving world-space as the chunks.
	next_platform_x -= scroll_speed * delta

func spawn_enemies(delta: float) -> void:
	enemy_spawn_remaining -= delta
	if enemy_spawn_remaining > 0.0:
		return
	# Escalate pressure across the run: roomy openings at the start, then a
	# denser stream of enemies as the escape timer nears zero.
	var danger_progress := clampf(escape_progress / SURVIVAL_TIME, 0.0, 1.0)
	var average_interval := lerpf(3.2, 0.75, danger_progress)
	enemy_spawn_remaining = rng.randf_range(average_interval * 0.75, average_interval * 1.25)
	var enemy := Area2D.new()
	enemy.set_script(FloatingEnemy)
	enemy.position = Vector2(1420.0, rng.randf_range(255.0, 520.0))
	enemy.collision_layer = 1
	enemy.collision_mask = 1
	enemy.add_to_group("damageable")

	var visual := Polygon2D.new()
	visual.color = Color(0.94, 0.45, 0.18)
	visual.polygon = PackedVector2Array([Vector2(-20, 0), Vector2(-10, -18), Vector2(12, -14), Vector2(22, 0), Vector2(10, 16), Vector2(-12, 18)])
	enemy.add_child(visual)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 19.0
	collision.shape = shape
	enemy.add_child(collision)
	enemy_stream.add_child(enemy)
	enemy.connect("shattered", _on_enemy_shattered)

func move_enemies(scroll_speed: float, delta: float) -> void:
	for enemy in enemy_stream.get_children():
		enemy.position.x -= scroll_speed * delta
		if enemy.position.x < -100.0:
			enemy.queue_free()

func _on_enemy_shattered(world_position: Vector2) -> void:
	for index in 3:
		var shard := Node2D.new()
		shard.position = world_position
		shard.set_meta("velocity", Vector2(-rng.randf_range(650.0, 820.0), (index - 1) * 120.0))
		var visual := Polygon2D.new()
		visual.color = Color(1.0, 0.78, 0.25)
		visual.rotation = rng.randf_range(0.0, TAU)
		visual.polygon = PackedVector2Array([Vector2(-9, -5), Vector2(10, 0), Vector2(-7, 6)])
		shard.add_child(visual)
		shard_stream.add_child(shard)

func move_shards(delta: float) -> void:
	for shard in shard_stream.get_children():
		var shard_velocity: Vector2 = shard.get_meta("velocity")
		shard.position += shard_velocity * delta
		if shard.position.x <= boss.position.x + 55.0:
			slow_boss(2.0, 0.20)
			play_boss_slow_hit_animation()
			shard.queue_free()

func slow_boss(duration: float, multiplier: float) -> void:
	boss_slow_remaining = maxf(boss_slow_remaining, duration)
	boss_slow_multiplier = minf(boss_slow_multiplier, multiplier)

func play_boss_slow_hit_animation() -> void:
	if is_instance_valid(boss_hit_tween):
		boss_hit_tween.kill()
	boss.modulate = Color(0.32, 0.82, 1.0, 1.0)
	boss.scale = Vector2(1.22, 0.76)
	boss_hit_tween = create_tween()
	boss_hit_tween.set_parallel(true)
	boss_hit_tween.tween_property(boss, "modulate", Color.WHITE, 0.32)
	boss_hit_tween.tween_property(boss, "scale", Vector2(0.86, 1.14), 0.1)
	boss_hit_tween.chain().tween_property(boss, "scale", Vector2.ONE, 0.16)

func update_boss(delta: float) -> void:
	var danger_progress := clampf(escape_progress / SURVIVAL_TIME, 0.0, 1.0)
	boss_slow_remaining = maxf(0.0, boss_slow_remaining - delta)
	if boss_slow_remaining == 0.0:
		boss_slow_multiplier = 1.0
	# Boss pressure rises on the same curve as enemy density. Defeated enemies
	# return fire as shards, briefly reducing that pressure.
	var escalating_speed := lerpf(boss_speed, 72.0, danger_progress)
	boss.position.x += escalating_speed * boss_slow_multiplier * delta
	if boss.position.x > player.position.x - 70.0:
		player.reset_scene("The boss caught you! Resetting…")
