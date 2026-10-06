extends Node2D

const SURVIVAL_TIME := 30.0
const BASE_SCROLL_SPEED := 335.0
const MAX_SCROLL_SPEED := 620.0
const SPEED_UP_START_X := 820.0
const RIGHT_SOFT_LIMIT_X := 1040.0
const PLATFORM_HEIGHT := 24.0
const PLATFORM_Y := [610.0, 535.0, 460.0, 385.0]
const UPPER_PLATFORM_Y := [220.0, 290.0, 360.0]

@onready var player: CharacterBody2D = $Player
@onready var platform_stream: Node2D = $PlatformStream
@onready var boss: Node2D = $Boss
@onready var timer_label: Label = $HUD/TimerLabel
@onready var result_label: Label = $HUD/ResultLabel

var elapsed := 0.0
var escape_progress := 0.0
var next_platform_x := 0.0
var boss_speed := 12.0
var complete := false
var rng := RandomNumberGenerator.new()
var active_scroll_speed := BASE_SCROLL_SPEED

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
		add_platform(next_platform_x + gap, width, height)
		# Floating platforms create optional hookshot routes above the main path.
		if rng.randf() < 0.45:
			var upper_y: float = float(UPPER_PLATFORM_Y[rng.randi_range(0, UPPER_PLATFORM_Y.size() - 1)])
			var upper_width := rng.randf_range(120.0, 210.0)
			add_platform(next_platform_x + gap + rng.randf_range(50.0, 170.0), upper_width, upper_y)
		next_platform_x += gap + width

func add_platform(x: float, width: float, y: float) -> void:
	var platform := StaticBody2D.new()
	platform.position = Vector2(x + width * 0.5, y)
	platform.add_to_group("chase_platform")
	platform.set_meta("width", width)

	var visual := Polygon2D.new()
	visual.color = Color("43b868")
	visual.polygon = PackedVector2Array([
		Vector2(-width * 0.5, -PLATFORM_HEIGHT * 0.5), Vector2(width * 0.5, -PLATFORM_HEIGHT * 0.5),
		Vector2(width * 0.5, PLATFORM_HEIGHT * 0.5), Vector2(-width * 0.5, PLATFORM_HEIGHT * 0.5)
	])
	platform.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, PLATFORM_HEIGHT)
	collision.shape = shape
	platform.add_child(collision)
	platform_stream.add_child(platform)

func move_platforms(scroll_speed: float, delta: float) -> void:
	for platform in platform_stream.get_children():
		platform.position.x -= scroll_speed * delta
		if platform.position.x + float(platform.get_meta("width")) * 0.5 < -120.0:
			platform.queue_free()
	# Keep the spawn coordinate in the same moving world-space as the chunks.
	next_platform_x -= scroll_speed * delta

func update_boss(delta: float) -> void:
	# The boss steadily consumes screen space from the left.
	boss.position.x += (boss_speed + elapsed * 0.3) * delta
	if boss.position.x > player.position.x - 70.0:
		player.reset_scene("The boss caught you! Resetting…")
