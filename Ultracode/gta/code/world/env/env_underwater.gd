extends CanvasLayer
## ENVIRONMENT module helper: full-screen underwater treatment (refraction wobble, absorption
## tint, vignette, light shimmer). Lives on a low CanvasLayer so the HUD draws on top of it.
## Visible only while the active camera is below the sea surface - zero cost otherwise.
## Created and driven by EnvironmentSystem.

const OVERLAY_SHADER: Shader = preload("res://gta/code/world/shaders/env_underwater.gdshader")
const OVERLAY_LAYER := -10

var rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	_build()


func _build() -> void:
	if rect != null:
		return
	layer = OVERLAY_LAYER
	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY_SHADER
	rect = ColorRect.new()
	rect.name = "UnderwaterOverlay"
	rect.color = Color(1, 1, 1, 1)
	rect.material = _mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	add_child(rect)
	visible = false


## `depth` = metres of water above the camera, `daylight` 0..1, `time_s` = gta_time.
func update_overlay(underwater: bool, depth: float, daylight: float, time_s: float) -> void:
	if rect == null:
		return
	if rect.visible != underwater:
		rect.visible = underwater
		visible = underwater
	if not underwater:
		return
	_mat.set_shader_parameter(&"depth_factor", clampf(depth / 14.0, 0.0, 1.0))
	_mat.set_shader_parameter(&"daylight", daylight)
	_mat.set_shader_parameter(&"time_s", time_s)
