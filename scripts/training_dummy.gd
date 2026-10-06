extends CharacterBody2D

const BloodBurst = preload("res://scripts/blood_burst.gd")
const GRAVITY := 1400.0

@export var max_hp := 5
@export var label_prefix := ""
@export var hop_velocity := -470.0
@export var chase_speed := 170.0
@export var chase_acceleration := 700.0

var hp := 0.0
var alive := true

@onready var visual: Sprite2D = $Sprite
@onready var health_label: Label = $HealthLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	hp = float(max_hp)
	refresh_label()

func _physics_process(delta: float) -> void:
	if not alive:
		return

	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if is_on_floor():
		velocity.y = hop_velocity
	else:
		velocity.y += GRAVITY * delta
	if player:
		var chase_direction := signf(player.global_position.x - global_position.x)
		velocity.x = move_toward(velocity.x, chase_direction * chase_speed, chase_acceleration * delta)

	var was_descending := velocity.y > 0.0
	move_and_slide()
	if is_on_wall():
		velocity.x = -velocity.x
	if was_descending and player and absf(player.global_position.x - global_position.x) < 30.0 and player.global_position.y > global_position.y and player.global_position.y - global_position.y < 68.0:
		player.call("reset_scene", "Crushed! Resetting…")

func take_damage(amount: float) -> void:
	if not alive:
		return

	hp = maxf(hp - amount, 0.0)
	refresh_label()
	BloodBurst.spawn(get_parent(), global_position)
	var hit_flash := create_tween()
	hit_flash.tween_property(visual, "modulate", Color(1.0, 0.35, 0.35), 0.05)
	hit_flash.tween_property(visual, "modulate", Color.WHITE, 0.12)
	if hp == 0:
		die()

func die() -> void:
	alive = false
	collision_shape.set_deferred("disabled", true)
	health_label.text = "DEFEATED"
	var death := create_tween()
	death.parallel().tween_property(visual, "scale", Vector2(1.25, 0.15), 0.25)
	death.parallel().tween_property(visual, "modulate:a", 0.0, 0.25)
	await death.finished
	visible = false

func refresh_label() -> void:
	if label_prefix.is_empty():
		health_label.text = "%.1f / %d HP" % [hp, max_hp]
	else:
		health_label.text = "%s: %.1f / %d HP" % [label_prefix, hp, max_hp]
