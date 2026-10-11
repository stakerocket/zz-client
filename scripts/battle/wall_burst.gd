extends Node2D
class_name ZZWallBurst

var _t: float = 0.0


func run() -> void:
	var tw := create_tween()
	tw.tween_method(_set_t, 0.0, 1.0, 0.28)
	await tw.finished
	queue_free()


func _set_t(v: float) -> void:
	_t = v
	queue_redraw()


func _draw() -> void:
	var a := 1.0 - _t
	var r := 4.0 + _t * 14.0
	draw_circle(Vector2.ZERO, r, Color(0.85, 0.7, 0.35, a * 0.85))
	draw_circle(Vector2.ZERO, r * 0.45, Color(1.0, 0.92, 0.55, a))
	for i in 6:
		var ang := TAU * float(i) / 6.0 + _t * 2.0
		var p := Vector2(cos(ang), sin(ang)) * (6.0 + _t * 18.0)
		draw_circle(p, 2.2, Color(0.7, 0.55, 0.25, a))
