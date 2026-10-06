extends Node2D

@export var swing_angle := 52.0
@export var swing_duration := 0.85

@onready var pivot: Node2D = $Pivot
@onready var hitbox: Area2D = $Pivot/Hitbox

func _ready() -> void:
	hitbox.body_entered.connect(on_body_entered)
	pivot.rotation = deg_to_rad(-swing_angle)
	var swing := create_tween().set_loops()
	swing.tween_property(pivot, "rotation", deg_to_rad(swing_angle), swing_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	swing.tween_property(pivot, "rotation", deg_to_rad(-swing_angle), swing_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func on_body_entered(body: Node2D) -> void:
	if body.has_method("reset_scene"):
		body.call("reset_scene", "Axe hit! Resetting…")
