extends SceneTree

const MainScene = preload("res://scripts/ui/main_scene.gd")

const ICONS := [
	"normal",
	"elite",
	"boss",
	"shop",
	"event",
	"rest",
	"treasure",
	"reward",
	"relic",
	"potion",
	"save",
	"intent_attack",
	"intent_block"
]

const SFX := [
	"button",
	"reward",
	"gold",
	"error",
	"save_ok",
	"node",
	"shop",
	"rest"
]


func _init() -> void:
	var view := MainScene.new()
	for icon_id in ICONS:
		var texture := view._icon(icon_id)
		_assert(texture != null, "missing or invalid icon: %s" % icon_id)
	for sfx_id in SFX:
		var path := String(view.SFX.get(sfx_id, ""))
		_assert(not path.is_empty(), "missing sfx mapping: %s" % sfx_id)
		var stream := view._load_audio_stream(path)
		_assert(stream != null, "missing or invalid sfx: %s" % sfx_id)
	view.icon_cache.clear()
	view.free()
	print("M2 presentation resource test passed")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
