extends RefCounted

static func spawn(parent: Node, at_position: Vector2) -> void:
	var burst := Node2D.new()
	burst.global_position = at_position
	burst.z_index = 10
	parent.add_child(burst)

	for index in 8:
		var drop := Polygon2D.new()
		drop.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(5, 0), Vector2(-3, 5)])
		drop.color = Color(0.85, 0.08, 0.08, 1.0)
		burst.add_child(drop)
		var angle := lerpf(-2.8, -0.35, float(index) / 7.0)
		var distance := 35.0 + float(index % 3) * 18.0
		var destination := Vector2.from_angle(angle) * distance + Vector2(0, 28)
		var spray := burst.create_tween()
		spray.set_parallel(true)
		spray.tween_property(drop, "position", destination, 0.32)
		spray.tween_property(drop, "rotation", TAU, 0.32)
		spray.tween_property(drop, "modulate:a", 0.0, 0.32)

	burst.get_tree().create_timer(0.35).timeout.connect(burst.queue_free)
