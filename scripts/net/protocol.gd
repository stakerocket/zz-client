extends RefCounted
class_name ZZProtocol


static func join_lobby(nick: String) -> Dictionary:
	return {
		"type": "join_lobby",
		"nick": nick,
		"version": ZZServerConfig.PROTOCOL_VERSION,
	}


static func chat(text: String, channel: String = "lobby") -> Dictionary:
	return {"type": "chat", "text": text, "channel": channel}


static func find_match(nick: String) -> Dictionary:
	return {"type": "find_match", "nick": nick}


static func end_turn(actions: Array) -> Dictionary:
	return {"type": "end_turn", "actions": actions}


static func ping() -> Dictionary:
	return {"type": "ping"}


static func move_action(x: int, y: int) -> Dictionary:
	return {"type": "move", "x": int(x), "y": int(y)}


static func shoot_action(target_id: String) -> Dictionary:
	return {"type": "shoot", "target_id": target_id}


static func burst_action(target_id: String) -> Dictionary:
	return {"type": "burst", "target_id": target_id}


static func duplet_action(target_id: String) -> Dictionary:
	return {"type": "duplet", "target_id": target_id}


static func posture_action(posture: String) -> Dictionary:
	return {"type": "posture", "posture": posture}


static func medkit_action() -> Dictionary:
	return {"type": "medkit"}


static func reload_action() -> Dictionary:
	return {"type": "reload"}


static func switch_weapon_action(weapon_index: int) -> Dictionary:
	return {"type": "switch_weapon", "weapon_index": int(weapon_index)}


static func inventory_action() -> Dictionary:
	return {"type": "inventory"}


static func equip_action(item_id: String, slot: String) -> Dictionary:
	return {"type": "equip", "item_id": item_id, "slot": slot}


static func unequip_action(slot: String) -> Dictionary:
	return {"type": "unequip", "slot": slot}


static func select_ammo_action(ammo_id: String) -> Dictionary:
	return {"type": "select_ammo", "item_id": ammo_id}


static func inventory_get() -> Dictionary:
	return {"type": "inventory_get"}


static func inventory_equip(item_id: String, slot: String) -> Dictionary:
	return {"type": "inventory_equip", "item_id": item_id, "slot": slot}


static func inventory_unequip(slot: String) -> Dictionary:
	return {"type": "inventory_unequip", "slot": slot}


static func inventory_withdraw(item_id: String, qty: int = 1) -> Dictionary:
	return {"type": "inventory_withdraw", "item_id": item_id, "qty": int(qty)}


static func inventory_deposit(item_id: String, qty: int = 1) -> Dictionary:
	return {"type": "inventory_deposit", "item_id": item_id, "qty": int(qty)}


static func set_level(level: int) -> Dictionary:
	return {"type": "set_level", "level": int(level)}


static func spend_stat(stat: String, delta: int) -> Dictionary:
	return {"type": "spend_stat", "stat": stat, "delta": int(delta)}
