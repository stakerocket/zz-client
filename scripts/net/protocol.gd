extends RefCounted
class_name ZZProtocol


static func join_lobby(nick: String) -> Dictionary:
	return {"type": "join_lobby", "nick": nick}


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


static func posture_action(posture: String) -> Dictionary:
	return {"type": "posture", "posture": posture}


static func medkit_action() -> Dictionary:
	return {"type": "medkit"}


static func reload_action() -> Dictionary:
	return {"type": "reload"}
