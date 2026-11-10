extends SceneTree
## Tool: exports the code-built game Theme to res://gta/resources/themes/game_theme.tres.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/ui/tools/ui_gen_theme.gd
## The runtime UI always builds the same theme with UiThemeBuilder.build(); the .tres exists for
## scenes / editor previews that want to reference a file (fonts fall back to the engine font).

const OUT := "res://gta/resources/themes/game_theme.tres"


func _initialize() -> void:
	var builder := load("res://gta/code/ui/ui_theme_builder.gd") as Script
	if builder == null:
		print("CHECK_FAIL ui_gen_theme: builder script did not load")
		quit(1)
		return
	var theme: Theme = builder.call("build", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(theme, OUT)
	if err != OK:
		print("CHECK_FAIL ui_gen_theme: save error %d" % err)
		quit(1)
		return
	print("UI_THEME_SAVED ", OUT, " types=", theme.get_type_list().size())
	quit(0)
