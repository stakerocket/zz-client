extends Node2D
class_name ZZWallBurst

var _t: float = 0.0
var _core: Sprite2D
var _sparks: Array[Sprite2D] = []


func _ready() -> void:
	_core = _make_dot(Color(0.95, 0.8, 0.4, 0.9), 10)
	add_child(_core)
	for i in 6:
		var s := _make_dot(Color(0.75, 0.55, 0.25, 1.0), 5)
		add_child(s)
		_sparks.append(s)


func _make_dot(col: Color, px: int) -> Sprite2D:
	var spr := Sprite2D.new()
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(col)
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return spr


func run() -> void:
	var tw := create_tween()
	tw.tween_method(_set_t, 0.0, 1.0, 0.28)
	await tw.finished
	queue_free()


func _set_t(v: float) -> void:
	_t = v
	var a := 1.0 - _t
	if _core:
		_core.scale = Vector2.ONE * (1.0 + _t * 2.5)
		_core.modulate.a = a * 0.85
	for i in _sparks.size():
		var ang := TAU * float(i) / 6.0 + _t * 2.0
		var dist := 8.0 + _t * 22.0
		_sparks[i].position = Vector2(cos(ang) * dist, sin(ang) * dist)
		_sparks[i].modulate.a = a
