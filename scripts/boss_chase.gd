extends Node2D

const SURVIVAL_TIME := 60.0
const BASE_SCROLL_SPEED := 255.0
const MAX_SCROLL_SPEED := 1250.0
const SPEED_UP_START_X := 720.0
const RIGHT_SOFT_LIMIT_X := 1040.0
const MAX_LEAD := 100.0
const BOSS_SAFE_X := -180.0
const BOSS_DANGER_X := 200.0
const BOSS_CATCH_DISTANCE := 72.0
const RUN_LOG_PATH := "user://chase_run_scores.csv"
const TELEMETRY_QUEUE_PATH := "user://chase_telemetry_queue.json"
const TELEMETRY_ENDPOINT := "https://script.google.com/macros/s/AKfycbwMAGzruSWgjimE0uZ6e4P6OcuDI_asJwFeRkT7kKRsSpgMCb6IPCNkY_GgtJBa8vChQQ/exec"
# This identifies Hookmaster's client, but cannot be a true secret because it
# ships with the game. The endpoint must still rate-limit and validate input.
const TELEMETRY_TOKEN := "abc123asdasdklxcv"
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
@onready var velocity_label: Label = $HUD/VelocityLabel
@onready var result_label: Label = $HUD/ResultLabel

var elapsed := 0.0
var escape_progress := 0.0
var velocity_integral := 0.0
var mean_velocity := 0.0
var top_velocity := 0.0
var result_input_locked := false
var lead_integral := 0.0
var relative_velocity_integral := 0.0
var run_recorded := false
var next_platform_x := 0.0
var boss_speed := 480.0
var boss_slow_remaining := 0.0
var boss_slow_multiplier := 1.0
var boss_hit_tween: Tween
var lead := 55.0
var lead_setback_cooldown := 0.0
var relative_velocity := 0.0
var complete := false
var rng := RandomNumberGenerator.new()
var active_scroll_speed := BASE_SCROLL_SPEED
var enemy_spawn_remaining := 2.5
var next_main_platform_is_one_way := false
var install_id := ""
var telemetry_request: HTTPRequest
var telemetry_uploading := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install_id = load_or_create_install_id()
	telemetry_request = HTTPRequest.new()
	# Apps Script replies with a redirect after it has handled the POST. Following
	# that redirect converts a successful append into an unrelated HTTP 400.
	telemetry_request.max_redirects = 0
	telemetry_request.request_completed.connect(_on_telemetry_request_completed)
	add_child(telemetry_request)
	# HTTPRequest must be fully inside the scene tree before its first request.
	call_deferred("upload_next_telemetry_record")
	rng.randomize()
	# A generous runway before the first random gap.
	add_platform(-100.0, 1050.0, 610.0)
	next_platform_x = 1050.0

func _physics_process(delta: float) -> void:
	if complete:
		return

	elapsed += delta
	var current_velocity := player.velocity.length()
	velocity_integral += current_velocity * delta
	mean_velocity = velocity_integral / elapsed
	top_velocity = maxf(top_velocity, current_velocity)
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
	# Faster world speed is an explicit reward: it advances the survival goal faster.
	escape_progress += delta * (active_scroll_speed / BASE_SCROLL_SPEED)
	update_lead(delta)
	lead_integral += lead * delta
	relative_velocity_integral += relative_velocity * delta
	update_timer()
	if escape_progress >= SURVIVAL_TIME:
		show_escape_results()
		return
	spawn_ahead()
	spawn_enemies(delta)
	update_boss(delta)

func show_escape_results() -> void:
	complete = true
	# Resolve success before any boss/hazard step, then explicitly freeze the
	# player as well as the scene tree so no late collision can cause a reset.
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	record_run("escaped", "")
	result_label.text = "ESCAPED!\nMEAN VELOCITY %d  •  TOP VELOCITY %d\nPRESS ANY INPUT" % [roundi(mean_velocity), roundi(top_velocity)]
	result_label.visible = true
	result_input_locked = true
	get_tree().paused = true
	await get_tree().create_timer(3.0, true).timeout
	result_input_locked = false

func record_player_reset(reason: String) -> void:
	record_run("failed", reason)

func record_run(outcome: String, reason: String) -> void:
	if run_recorded:
		return
	run_recorded = true
	var mean_lead := lead_integral / maxf(elapsed, 0.001)
	var mean_vs_boss := relative_velocity_integral / maxf(elapsed, 0.001)
	var new_file := not FileAccess.file_exists(RUN_LOG_PATH)
	var file := FileAccess.open(RUN_LOG_PATH, FileAccess.WRITE if new_file else FileAccess.READ_WRITE)
	if file == null:
		push_warning("Could not write chase run log: %s" % RUN_LOG_PATH)
		return
	if new_file:
		file.store_line("timestamp,outcome,reason,real_seconds,escape_progress,mean_velocity,top_velocity,mean_lead,mean_vs_boss")
	else:
		file.seek_end()
	var safe_reason := reason.replace(",", ";").replace("\n", " ")
	file.store_line("%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [
		Time.get_datetime_string_from_system(), outcome, safe_reason, elapsed, escape_progress,
		mean_velocity, top_velocity, mean_lead, mean_vs_boss
	])
	file.close()
	queue_telemetry_record({
		"install_id": install_id,
		"build_id": get_build_id(),
		"outcome": outcome,
		"reason": reason,
		"real_seconds": elapsed,
		"escape_progress": escape_progress,
		"mean_velocity": mean_velocity,
		"top_velocity": top_velocity,
		"mean_lead": mean_lead,
		"mean_vs_boss": mean_vs_boss,
		"final_lead": lead,
		"boss_gap": player.position.x - boss.position.x,
	})
	upload_next_telemetry_record()

func load_or_create_install_id() -> String:
	const INSTALL_ID_PATH := "user://install_id.txt"
	if FileAccess.file_exists(INSTALL_ID_PATH):
		var existing := FileAccess.get_file_as_string(INSTALL_ID_PATH).strip_edges()
		if not existing.is_empty():
			return existing
	var new_id := "%s-%s" % [Time.get_unix_time_from_system(), randi()]
	var file := FileAccess.open(INSTALL_ID_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(new_id)
		file.close()
	return new_id

func get_build_id() -> String:
	# Source-based testers retain .git, so their pulled commit is reported. An
	# exported build has no .git directory and falls back to the project version.
	var build_id := str(ProjectSettings.get_setting("application/config/version", "dev"))
	var head_path := "res://.git/HEAD"
	if FileAccess.file_exists(head_path):
		var head := FileAccess.get_file_as_string(head_path).strip_edges()
		if head.begins_with("ref: "):
			var ref := head.trim_prefix("ref: ")
			var ref_path := "res://.git/%s" % ref
			if FileAccess.file_exists(ref_path):
				build_id = FileAccess.get_file_as_string(ref_path).strip_edges().left(12)
		elif head.length() >= 7:
			build_id = head.left(12)
	# Git is present for source-based playtesters. The check simply falls back
	# for downloaded exports and flags runs made with uncommitted local edits.
	var status_output: Array = []
	var git_exit_code := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "status", "--porcelain"], status_output, true)
	if git_exit_code == 0 and not status_output.is_empty() and not str(status_output[0]).strip_edges().is_empty():
		build_id += "-dirty"
	return build_id

func queue_telemetry_record(record: Dictionary) -> void:
	var queue := load_telemetry_queue()
	queue.append(record)
	var file := FileAccess.open(TELEMETRY_QUEUE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(queue))
		file.close()

func load_telemetry_queue() -> Array:
	if not FileAccess.file_exists(TELEMETRY_QUEUE_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TELEMETRY_QUEUE_PATH))
	return parsed if parsed is Array else []

func save_telemetry_queue(queue: Array) -> void:
	var file := FileAccess.open(TELEMETRY_QUEUE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(queue))
		file.close()

func upload_next_telemetry_record() -> void:
	if telemetry_uploading or telemetry_request == null:
		return
	var queue := load_telemetry_queue()
	if queue.is_empty():
		return
	var payload: Dictionary = queue[0]
	payload["token"] = TELEMETRY_TOKEN
	telemetry_uploading = true
	var error := telemetry_request.request(
		TELEMETRY_ENDPOINT,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		telemetry_uploading = false
		return
	# Google Apps Script accepts the POST before its proxy emits an unreliable
	# completion status. Remove this item once Godot has handed it to the
	# transport; otherwise the same first item is retried forever. The CSV log
	# remains the durable source if a manual re-upload is ever needed.
	queue.pop_front()
	save_telemetry_queue(queue)

func _on_telemetry_request_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	telemetry_uploading = false
	upload_next_telemetry_record()

func _unhandled_input(event: InputEvent) -> void:
	if complete and not result_input_locked and event.is_pressed():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func update_timer() -> void:
	var time_multiplier := active_scroll_speed / BASE_SCROLL_SPEED
	var remaining := maxf(0.0, SURVIVAL_TIME - escape_progress)
	timer_label.text = "ESCAPE IN %.1f  •  LEAD %d%%  •  %.1fx" % [remaining, roundi(lead), time_multiplier]
	velocity_label.text = "VELOCITY  NOW %d  •  MEAN %d  •  VS BOSS %+d" % [roundi(player.velocity.length()), roundi(mean_velocity), roundi(relative_velocity)]

func update_scroll_speed() -> void:
	var forward_pressure := maxf(player.position.x - SPEED_UP_START_X, 0.0)
	# Normal running deliberately gains visible screen space. Only a fraction of
	# excess velocity is followed; position pressure then smoothly reels the
	# level forward before the player reaches the far edge.
	var excess_velocity := maxf(player.velocity.x - BASE_SCROLL_SPEED, 0.0)
	var velocity_follow_speed := BASE_SCROLL_SPEED + excess_velocity * 0.25
	var position_catchup_speed := BASE_SCROLL_SPEED + forward_pressure * 2.1
	active_scroll_speed = clampf(maxf(velocity_follow_speed, position_catchup_speed), BASE_SCROLL_SPEED, MAX_SCROLL_SPEED)

func update_lead(delta: float) -> void:
	lead_setback_cooldown = maxf(0.0, lead_setback_cooldown - delta)
	# Lead is relative to the boss's pursuit capability. A player must outrun
	# the current boss pressure to build space; raw speed alone is not enough.
	var forward_velocity := maxf(player.velocity.x, 0.0)
	var boss_pressure_speed := boss_speed
	relative_velocity = forward_velocity - boss_pressure_speed
	var momentum_score := clampf(relative_velocity / 450.0, 0.0, 1.0)
	var forward_position_score := clampf((player.position.x - 520.0) / 360.0, 0.0, 1.0)
	var lead_rate := -6.0 + momentum_score * 12.0 + forward_position_score * 0.5
	lead = clampf(lead + lead_rate * delta, 0.0, MAX_LEAD)

func lose_lead(amount: float) -> void:
	if lead_setback_cooldown > 0.0:
		return
	lead_setback_cooldown = 0.35
	lead = maxf(0.0, lead - amount)

func gain_lead(amount: float) -> void:
	lead = minf(MAX_LEAD, lead + amount)

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
	if not one_way and x > 800.0 and rng.randf() < spike_chance:
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
			push_boss_back(80.0)
			play_boss_slow_hit_animation()
			shard.queue_free()

func push_boss_back(distance: float) -> void:
	# A shard only changes the chase once it visibly reaches the boss.
	boss.position.x -= distance

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
	# Lead—not elapsed time—defines visible boss pressure. Good movement pushes
	# its target left; losing momentum brings it toward a fixed danger position.
	# Do not derive this target from player X: that would make faster running
	# visually pull the boss closer.
	var lead_ratio := lead / MAX_LEAD
	var target_x := lerpf(BOSS_DANGER_X, BOSS_SAFE_X, lead_ratio)
	# Once the hidden lead is exhausted, switch from the abstract pressure meter
	# to a visible pursuit. This avoids a death while the boss is still clearly
	# far away, while still letting a zero-lead state become dangerous.
	if lead <= 0.0:
		target_x = player.position.x - BOSS_CATCH_DISTANCE
	boss.position.x = move_toward(boss.position.x, target_x, boss_speed * delta)
	var boss_gap := player.position.x - boss.position.x
	if lead <= 0.0 and boss_gap <= BOSS_CATCH_DISTANCE:
		player.reset_scene("The boss caught you! Gap %.0f • lead %.0f%%" % [boss_gap, lead])
