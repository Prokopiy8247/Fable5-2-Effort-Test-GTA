class_name UiPanel
extends PanelContainer
## Glass panel with a vertical body. Variations: GlassPanel (default), SolidPanel, LightPanel,
## AccentPanel, FlatPanel.     var p := UiPanel.new(); p.add(UiKit.header("GARAGE"))

var body: VBoxContainer


func _init(variation: StringName = &"GlassPanel", separation: int = 12) -> void:
	theme_type_variation = variation
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", separation)
	add_child(body)


## Adds `node` to the body and returns it (for chaining).
func add(node: Control) -> Control:
	body.add_child(node)
	return node


func clear() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
