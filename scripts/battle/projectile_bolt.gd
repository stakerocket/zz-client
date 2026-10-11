extends Node2D
class_name ZZProjectileBolt

var tint: Color = Color(1, 0.85, 0.35)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, tint)
	draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 0.85, 1))
	draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 20, Color(0, 0, 0, 0.35), 1.5, true)
