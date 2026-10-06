extends Area2D

@export_file("*.tscn") var destination := "res://scenes/boss_chase.tscn"
var used := false

func _on_body_entered(body: Node2D) -> void:
	if used or not body.is_in_group("player"):
		return
	used = true
	get_tree().change_scene_to_file(destination)
