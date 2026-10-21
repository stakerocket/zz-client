extends Node
class_name ZZSfx

## Lightweight one-shot SFX pool for combat feedback.

const _FILES := {
	"shoot": "res://assets/sfx/weapon/shoot.wav",
	"shoot_ak47": "res://assets/sfx/weapon/ak47_shot.wav",
	"shoot_revolver": "res://assets/sfx/weapon/revolver_shot.wav",
	"shoot_glock": "res://assets/sfx/weapon/glock_shot.wav",
	"shoot_sawed_off": "res://assets/sfx/weapon/sawed_off_shot.wav",
	"shoot_saiga12": "res://assets/sfx/weapon/saiga12_shot.wav",
	"shoot_uzi": "res://assets/sfx/weapon/uzi_shot.wav",
	"walk": "res://assets/sfx/walk.wav",
	"hit_wall": "res://assets/sfx/hit_wall.wav",
	"miss": "res://assets/sfx/miss.wav",
	"death": "res://assets/sfx/death.wav",
	"click": "res://assets/sfx/weapon/click.wav",
	"reload": "res://assets/sfx/weapon/reload.wav",
	"weapon_switch": "res://assets/sfx/weapon/weapon_switch.wav",
}

const POOL_SIZE := 16

var _streams: Dictionary = {}
var _pool: Array = []
var _walk_player: AudioStreamPlayer


func _ready() -> void:
	for key in _FILES:
		_streams[key] = _load_stream(str(_FILES[key]))
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_walk_player = AudioStreamPlayer.new()
	_walk_player.bus = "Master"
	add_child(_walk_player)


func play_shoot(weapon_id: String = "", _act_type: String = "shoot") -> void:
	if weapon_id == "glock17" and _streams.has("shoot_glock"):
		play("shoot_glock", -0.5, randf_range(0.98, 1.02))
		return
	if weapon_id == "revolver_38" and _streams.has("shoot_revolver"):
		play("shoot_revolver", -0.5, randf_range(0.98, 1.02))
		return
	if weapon_id == "sawed_off" and _streams.has("shoot_sawed_off"):
		play("shoot_sawed_off", -0.5, randf_range(0.98, 1.02))
		return
	if weapon_id == "saiga12" and _streams.has("shoot_saiga12"):
		play("shoot_saiga12", -0.5, randf_range(0.98, 1.02))
		return
	if weapon_id == "uzi" and _streams.has("shoot_uzi"):
		play("shoot_uzi", -0.5, randf_range(0.98, 1.02))
		return
	if _streams.has("shoot_ak47"):
		play("shoot_ak47", -0.5, randf_range(0.98, 1.02))
		return
	play("shoot", -0.5, randf_range(0.98, 1.02))


func play_walk() -> void:
	# Dedicated player so footsteps aren't stolen by combat one-shots.
	var stream: AudioStream = _streams.get("walk") as AudioStream
	if stream == null or _walk_player == null:
		return
	_walk_player.stream = stream
	_walk_player.volume_db = -5.0
	_walk_player.pitch_scale = randf_range(0.90, 1.12)
	_walk_player.play()


func play_hit_wall() -> void:
	play("hit_wall", -3.0)


func play_miss() -> void:
	play("miss", -4.0, randf_range(0.95, 1.05))


func play_death() -> void:
	play("death", -1.5, randf_range(0.96, 1.04))


func play_click() -> void:
	## Fire-selector detent — dry tick (no ringing tone).
	play("click", -3.0, randf_range(0.98, 1.04))


func play_reload() -> void:
	## Mag scrape + seat + bolt click (procedural WAV, no ringing tone).
	play("reload", -2.5, randf_range(0.97, 1.02))


func play_weapon_switch() -> void:
	## Holster rustle + grab/seat snap (procedural, no ring).
	play("weapon_switch", -2.0, randf_range(0.97, 1.03))


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
	# Prefer idle; if all busy, skip rather than cutting a live gunshot.
	return null


func _load_stream(path: String) -> AudioStream:
	# Runtime decode so assets work before/without editor import.
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		if path.ends_with(".mp3"):
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
		var from_buf := AudioStreamWAV.load_from_buffer(bytes)
		if from_buf != null:
			return from_buf
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStream:
			return res
	push_warning("ZZSfx: missing audio %s" % path)
	return null
