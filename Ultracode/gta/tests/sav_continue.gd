extends Node
## sav_continue (SAVE module): the boot "continue" flow end to end, in two runs.
##   run 1 (prepare): writes slot "sav_continue_fixture" with a recognisable state and exits.
##   run 2 (verify, with --continue=sav_continue_fixture): Main boots, EventBus.game_ready fires, the
##        SaveSystem loads the slot behind the loading veil; the test checks position, money, clock,
##        weather, the loading veil and the "continued" bookkeeping, then deletes the fixture.
##
## tools\godot.ps1 -Mode headless -Frames 1500 -TimeoutSec 200 -UserArgs '--test=sav_continue','--disable=traffic,peds,police'
## tools\godot.ps1 -Mode headless -Frames 1500 -TimeoutSec 200 -UserArgs '--test=sav_continue','--disable=traffic,peds,police','--continue=sav_continue_fixture'

const FIXTURE := "sav_continue_fixture"
const MONEY := 31337
const HOUR := 6.5


func _ready() -> void:
	var verify := false
	for a: String in OS.get_cmdline_user_args():
		if a == "--continue=" + FIXTURE:
			verify = true
	if verify:
		await _verify()
	else:
		await _prepare()
	TestHarness.finish()


func _target() -> Vector3:
	var v := Game.get_location("hill_viewpoint").origin + Vector3(-3.0, 0.0, 2.0)
	v.y = Game.ground_height(v.x, v.z) + 0.2
	return v


func _prepare() -> void:
	await TestHarness.wait_frames(60)
	Game.player.call("teleport", _target(), 0.7)
	await TestHarness.wait_physics_frames(40)
	Game.set_money(MONEY)
	WorldClock.set_hour(HOUR)
	Weather.snap_weather("fog")
	var ok := SaveSystem.save_game(FIXTURE)
	TestHarness.check(ok, "fixture written")
	var info := SaveSystem.get_slot_info(FIXTURE)
	TestHarness.log_line("fixture meta: %s" % str(info.get("meta", {})))
	TestHarness.log_line("fixture position: %s" % str(Game.player.global_position))
	TestHarness.check(SaveSystem.continued_from == "", "a test run without --continue did not continue")


func _verify() -> void:
	# the continue flow runs deferred after game_ready: give it a moment
	var waited := 0
	while SaveSystem.continued_from == "" and waited < 240:
		await TestHarness.wait_frames(1)
		waited += 1
	TestHarness.log_line("continued after %d frames: %s / %s" % [waited, SaveSystem.continued_from, str(SaveSystem.last_load_info)])
	TestHarness.check(SaveSystem.continued_from == FIXTURE, "boot continued from the fixture")
	await TestHarness.wait_physics_frames(20)
	var p := Game.player
	TestHarness.check(p.global_position.distance_to(_target()) < 1.2, "player at the saved spot (%s)" % str(p.global_position))
	TestHarness.check(Game.money == MONEY, "money restored (%d)" % Game.money)
	TestHarness.check(absf(WorldClock.hour - HOUR) < 0.2, "clock restored (%.2f)" % WorldClock.hour)
	TestHarness.check(str(Weather.current) == "fog", "weather restored (%s)" % str(Weather.current))
	await TestHarness.wait_seconds(1.0)
	TestHarness.check(not bool(UI.call("is_loading_veil_visible")), "loading veil gone")
	SaveSystem.delete_save(FIXTURE)
	TestHarness.check(not SaveSystem.has_save(FIXTURE), "fixture removed")
