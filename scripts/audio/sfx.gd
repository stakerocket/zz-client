extends Node
class_name ZZSfx

## Lightweight one-shot SFX pool for combat feedback.

const _FILES := {
	"shoot": "res://assets/sfx/shoot.wav",
	"walk": "res://assets/sfx/walk.wav",
	"hit_target": "res://assets/sfx/hit_target.wav",
	"hit_wall": "res://assets/sfx/hit_wall.wav",
	"miss": "res://assets/sfx/miss.wav",
}

const POOL_SIZE := 8

var _streams: Dictionary = {}
var _pool: Array = []


func _ready() -> void:
	for key in _FILES:
		_streams[key] = _load_stream(str(_FILES[key]))
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func play_shoot() -> void:
	play("shoot", -2.0)


func play_walk() -> void:
	play("walk", -6.0, randf_range(0.92, 1.08))


func play_hit_target() -> void:
	play("hit_target", -1.0)


func play_hit_wall() -> void:
	play("hit_wall", -3.0)


func play_miss() -> void:
	play("miss", -4.0, randf_range(0.95, 1.05))


func play(key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(key) as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer = _acquire()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _acquire() -> AudioStreamPlayer:
	for p in _pool:
		var player: AudioStreamPlayer = p
		if not player.playing:
			return player
	if _pool.is_empty():
		return null
	return _pool[0] as AudioStreamPlayer


func _load_stream(path: String) -> AudioStream:
	# Prefer runtime WAV decode so assets work before/without editor import.
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		var from_buf := AudioStreamWAV.load_from_buffer(bytes)
		if from_buf != null:
			return from_buf
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStream:
			return res
	push_warning("ZZSfx: missing audio %s" % path)
	return null
