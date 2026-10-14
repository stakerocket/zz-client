extends Node3D
class_name ZZWallBurst

var _t: float = 0.0
var _core: MeshInstance3D
var _sparks: Array[MeshInstance3D] = []


func _ready() -> void:
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	_core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.4, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core.material_override = mat
	add_child(_core)
	for i in 6:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		s.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.75, 0.55, 0.25, 1.0)
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.material_override = smat
		add_child(s)
		_sparks.append(s)


func run() -> void:
	position.y = maxf(position.y, 0.8)
	var tw := create_tween()
	tw.tween_method(_set_t, 0.0, 1.0, 0.28)
	await tw.finished
	queue_free()


func _set_t(v: float) -> void:
	_t = v
	var a := 1.0 - _t
	var r := 0.2 + _t * 0.7
	if _core:
		_core.scale = Vector3.ONE * (r / 0.2)
		var mat: StandardMaterial3D = _core.material_override
		if mat:
			mat.albedo_color.a = a * 0.85
	for i in _sparks.size():
		var ang := TAU * float(i) / 6.0 + _t * 2.0
		var dist := 0.35 + _t * 0.9
		_sparks[i].position = Vector3(cos(ang) * dist, 0.1, sin(ang) * dist)
		var sm: StandardMaterial3D = _sparks[i].material_override
		if sm:
			sm.albedo_color.a = a
