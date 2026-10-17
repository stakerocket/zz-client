extends Button
class_name ZZInvDragItem

## Draggable inventory cell or equip slot button.

var host: ZZInventoryUI
var item_id: String = ""
var qty: int = 1
## "" = bag cell; "primary"|"secondary"|"armor"|"quick_N" = equip/hotbar slot
var from_slot: String = ""
var accept_slot: String = "" # equip/hotbar slot name this control accepts

var _drag_dimmed: bool = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	if host == null or item_id == "":
		return null
	var tex: Texture2D = icon
	var item_icon := get_node_or_null("ItemIcon") as TextureRect
	if item_icon != null and item_icon.texture != null:
		tex = item_icon.texture
	if tex == null:
		return null

	## Preview must sit above inventory shell (z_index 120), else it looks like
	## the item "vanishes" until drop.
	var root := Control.new()
	root.z_as_relative = false
	root.z_index = 4000
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(56, 56)
	root.custom_minimum_size = Vector2(56, 56)

	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = Vector2(-28, -28)
	tr.size = Vector2(56, 56)
	tr.custom_minimum_size = Vector2(56, 56)
	root.add_child(tr)
	set_drag_preview(root)

	## Dim source while dragging; keep icon so slot doesn't look empty.
	_set_drag_dim(true)
	return {"item_id": item_id, "from_slot": from_slot, "qty": qty}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_drag_dim(false)


func _set_drag_dim(on: bool) -> void:
	if _drag_dimmed == on:
		return
	_drag_dimmed = on
	var item_icon := get_node_or_null("ItemIcon") as TextureRect
	if item_icon != null:
		item_icon.modulate = Color(1, 1, 1, 0.35) if on else Color.WHITE
	else:
		modulate = Color(1, 1, 1, 0.45) if on else Color.WHITE


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if host == null or typeof(data) != TYPE_DICTIONARY:
		return false
	return host.can_drop_on_slot(accept_slot, data) if accept_slot != "" else host.can_drop_on_bag(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if host == null or typeof(data) != TYPE_DICTIONARY:
		return
	_set_drag_dim(false)
	if accept_slot != "":
		host.drop_on_slot(accept_slot, data)
	else:
		host.drop_on_bag(data)


func _make_custom_tooltip(_for_text: String) -> Object:
	if host == null or item_id == "":
		return null
	return host.build_item_tooltip(item_id, qty)
