extends RefCounted
class_name ZZServerConfig

## false = локальный сервер, true = прод.
const USE_PROD := false

const LOCAL_WS_URL := "ws://127.0.0.1:8080/ws"
const PROD_WS_URL := "ws://103.167.235.247:8080/ws"


static func ws_url() -> String:
	return PROD_WS_URL if USE_PROD else LOCAL_WS_URL
