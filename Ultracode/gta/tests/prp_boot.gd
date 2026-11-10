extends Node
## PropSystem (WORLD DRESSING) boot profile: setup time per placer phase and the node budget.
##   tools\godot.ps1 -Mode headless -Frames 400 -TimeoutSec 200 -UserArgs '--test=prp_boot','--no_player','--disable=traffic,peds,police,wildlife,emergency,transit,taxi,activities,radio,ambience,shops,garage'


func _ready() -> void:
	await TestHarness.wait_frames(10)
	var ps := Game.get_system("props")
	TestHarness.check(ps != null, "props system registered")
	if ps == null:
		TestHarness.finish(false, "no props system")
		return
	var rep: Dictionary = ps.call("get_debug_report")
	var st: Dictionary = rep["stats"]
	var phases: Dictionary = st.get("phase_ms", {})
	var keys := phases.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(phases[a]) > float(phases[b]))
	var top: PackedStringArray = []
	for k: Variant in keys.slice(0, 12):
		top.append("%s %.0f" % [k, float(phases[k])])
	TestHarness.log_line("PRP_BOOT setup %d ms (catalog %d, street %d, sets %d, nature %d, build %d)" % [int(st.get("setup_ms", -1)),
			int(st.get("catalog_ms", -1)), int(st.get("street_ms", -1)), int(st.get("sets_ms", -1)), int(st.get("nature_ms", -1)), int(st.get("build_ms", -1))])
	TestHarness.log_line("PRP_BOOT slowest phases (ms): " + ", ".join(top))
	TestHarness.log_line("PRP_BOOT GLB load + mesh extraction inside the phases: %d ms, build (MultiMesh, bodies, lights, rigid hulls) %d ms, largest rigid hull %d points" % [
			int(st.get("glb_load_ms", -1)), int(st.get("build_ms", -1)), int(st.get("rigid_hull_max_points", -1))])
	# node budget of the whole dressing subtree
	var total := 0
	var by_class := {}
	var stack: Array[Node] = [ps as Node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total += 1
		var c := n.get_class()
		by_class[c] = int(by_class.get(c, 0)) + 1
		for ch: Node in n.get_children():
			stack.append(ch)
	TestHarness.log_line("PRP_BOOT nodes under Props: %d %s" % [total, str(by_class)])
	var c: Dictionary = ps.call("get_counts")
	TestHarness.log_line("PRP_BOOT instances %d, multimesh nodes %d, static bodies %d, lamps %d, ladders %d" % [int(c["instances"]),
			int(c["multimesh_nodes"]), int(c["static_bodies"]), int(c["lamps"]), int(c["ladders"])])
	TestHarness.check(int(st.get("setup_ms", 99999)) < 2500, "dressing setup under 2.5 s (%d ms)" % int(st.get("setup_ms", -1)))
	TestHarness.check(total < 1500, "dressing node count < 1500 (%d)" % total)
	TestHarness.finish()
