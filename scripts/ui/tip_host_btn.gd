extends Button
class_name ZZTipHostBtn

## Button that shows inventory-style tooltips (item card or simple title/rows).

var tip_item_id: String = ""
var tip_qty: int = 1
## Optional extra tip rows: Array of [key, value].
var tip_extra: Array = []
## When tip_item_id is empty, build a simple card from these.
var tip_title: String = ""
var tip_subtitle: String = ""


func _make_custom_tooltip(_for_text: String) -> Object:
	if tip_item_id != "":
		return ZZItemTooltip.build(tip_item_id, tip_qty, tip_extra)
	if tip_title != "":
		return ZZItemTooltip.build_simple(tip_title, tip_subtitle, tip_extra)
	return null
