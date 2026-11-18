extends Node2D
class_name ZZProjectileBolt

var tint: Color = Color(1, 0.85, 0.35)


func _ready() -> void:
	var spr := Sprite2D.new()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(tint)
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = true
	spr.scale = Vector2(1.5, 1.5)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
