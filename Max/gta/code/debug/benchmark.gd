class_name Benchmark
extends Node
## Repeatable benchmark tour for video comparisons: a camera flies through ten viewpoints
## (about 60 s), the player is moved along so traffic and pedestrians stream in as in play,
## and frame times are recorded. Results go to a banner, the log and user://benchmark.txt.

const SEG := 6.0
const POINTS := [
	["Overview", Vector3(40, 150, 290), Vector3(0, 0, 0)],
	["Downtown", Vector3(-70, 16, -30), Vector3(40, 30, -140)],
	["Downtown street", Vector3(36, 2.4, 20), Vector3(40, 3, -60)],
	["Midtown", Vector3(20, 9, 62), Vector3(60, 2, 30)],
	["Palm Row", Vector3(-150, 12, 20), Vector3(-190, 2, 60)],
	["Coral Beach", Vector3(-150, 6, 240), Vector3(-60, 2, 215)],
	["Lookout Hill", Vector3(-120, 30, -100), Vector3(-195, 28, -195)],
	["Ironworks", Vector3(128, 14, -60), Vector3(170, 4, -110)],
	["Vesper Airfield", Vector3(300, 30, 120), Vector3(250, 2, -100)],
	["Marina", Vector3(110, 10, 270), Vector3(86, 0, 215)],
]

var cam: Camera3D
var t := 0.0
var seg := -1
var times := PackedFloat32Array()
var seg_times: Array = []
var _player_xf := Transform3D.IDENTITY
var _was_hud := true
var _done := false

static func start() -> void:
	if Game.main == null or Game.main.get_node_or_null("Benchmark") != null:
		return
	var b := Benchmark.new()
	b.name = "Benchmark"
	Game.main.add_child(b)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	Game.soft_block += 1
	_was_hud = Game.hud.show_hud
	Game.hud.show_hud = false
	if Game.player != null:
		_player_xf = Game.player.global_transform
	for i in POINTS.size():
		seg_times.append(PackedFloat32Array())
	print("[Bench] tour started")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finish(true)

func _process(delta: float) -> void:
	if _done:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	t += real
	var s := int(t / SEG)
	if s >= POINTS.size():
		finish(false)
		return
	if s != seg:
		seg = s
		_move_player(POINTS[s][2])
	var k := smoothstep(0.0, 1.0, fmod(t, SEG) / SEG)
	var a: Vector3 = POINTS[s][1]
	var target: Vector3 = POINTS[s][2]
	# glide sideways past each viewpoint
	var side := (target - a).cross(Vector3.UP).normalized()
	var pos := a + side * lerpf(-6.0, 6.0, k) + Vector3(0, lerpf(0.0, 2.0, k), 0)
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	# skip the first second of every segment (streaming settles after the jump)
	if fmod(t, SEG) > 1.0:
		times.append(real)
		var arr: PackedFloat32Array = seg_times[s]
		arr.append(real)
		seg_times[s] = arr

func _move_player(target: Vector3) -> void:
	var p: Player = Game.player
	if p == null or p.vehicle != null:
		return
	var hit := Game.ray(target + Vector3(0, 60.0, 0), target - Vector3(0, 20.0, 0), Phys.WORLD)
	var at := target
	if not hit.is_empty():
		at = (hit["position"] as Vector3) + Vector3(0, 0.2, 0)
	p.global_position = at
	p.velocity = Vector3.ZERO

static func _stats(arr: PackedFloat32Array) -> Dictionary:
	if arr.is_empty():
		return {"avg": 0.0, "low1": 0.0, "worst_ms": 0.0, "frames": 0}
	var total := 0.0
	var sorted := arr.duplicate()
	sorted.sort()
	for v in arr:
		total += v
	var p99 := sorted[clampi(int(float(sorted.size()) * 0.99), 0, sorted.size() - 1)]
	return {"avg": float(arr.size()) / maxf(total, 0.0001), "low1": 1.0 / maxf(p99, 0.0001),
		"worst_ms": sorted[sorted.size() - 1] * 1000.0, "frames": arr.size()}

func finish(aborted: bool) -> void:
	if _done:
		return
	_done = true
	var st := _stats(times)
	var lines: PackedStringArray = []
	lines.append("NEON TIDE benchmark  %s%s" % [Time.get_datetime_string_from_system(), "  (aborted)" if aborted else ""])
	lines.append("GPU: %s   driver API: %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	lines.append("Window %s  render scale %.2f  quality %d  vsync %s  fps cap %d" % [str(get_viewport().get_visible_rect().size),
		float(Settings.get_v("render_scale", 1.0)), int(Settings.get_v("quality", 1)), str(Settings.get_v("vsync", true)), int(Settings.get_v("max_fps", 60))])
	lines.append("Overall: avg %.1f FPS, 1%% low %.1f FPS, worst frame %.1f ms, %d frames" % [st["avg"], st["low1"], st["worst_ms"], st["frames"]])
	for i in POINTS.size():
		var ss := _stats(seg_times[i])
		if int(ss["frames"]) > 0:
			var spikes := 0
			for ft in (seg_times[i] as PackedFloat32Array):
				if ft > 0.034:
					spikes += 1
			lines.append("  %-16s avg %6.1f   1%% low %6.1f   worst %6.1f ms   frames>34ms %d" % [POINTS[i][0], ss["avg"], ss["low1"], ss["worst_ms"], spikes])
	var text := "\n".join(lines)
	print("[Bench] ", text)
	var f := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	if Game.player != null and Game.player.vehicle == null:
		Game.player.global_transform = _player_xf
	if Game.cam != null:
		Game.cam.cam.make_current()
		Game.cam.snap()
	Game.soft_block = maxi(0, Game.soft_block - 1)
	Game.hud.show_hud = _was_hud
	Game.banner("BENCHMARK", "avg %.0f FPS   1%% low %.0f FPS   worst frame %.1f ms" % [st["avg"], st["low1"], st["worst_ms"]], Color(1.0, 0.85, 0.2), 8.0)
	queue_free()
