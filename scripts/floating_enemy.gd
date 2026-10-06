extends Area2D

signal shattered(world_position: Vector2)

@export var hp := 1
var touch_cooldown := 0.0
var bob_time := 0.0
var origin_y := 0.0

func _ready() -> void:
	origin_y = position.y
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	touch_cooldown = maxf(0.0, touch_cooldown - delta)
	bob_time += delta
	position.y = origin_y + sin(bob_time * 3.0) * 12.0

func _on_body_entered(body: Node2D) -> void:
	if touch_cooldown > 0.0 or not body.is_in_group("player"):
		return
	touch_cooldown = 0.7
	body.call("apply_movement_slow", 1.0, 0.45)

func take_damage(amount: float) -> void:
	hp -= ceili(amount)
	if hp <= 0:
		shattered.emit(global_position)
		queue_free()
