class_name MapDraw
extends RefCounted
## Shared vector map renderer for the minimap and the full-screen map. Everything is drawn
## straight from CityLayout / CityBuilder data, so the map can never drift from the world.

const C_WATER := Color(0.09, 0.2, 0.28)
const C_LAND := Color(0.2, 0.26, 0.22)
const C_HILL := Color(0.19, 0.3, 0.2)
const C_SAND := Color(0.62, 0.56, 0.4)
const C_BLOCK := Color(0.27, 0.28, 0.31)
const C_PARK := Color(0.2, 0.36, 0.22)
const C_ROAD := Color(0.5, 0.52, 0.56)
const C_ARTERIAL := Color(0.72, 0.68, 0.5)
const C_BUILDING := Color(0.4, 0.41, 0.45)
const C_RUNWAY := Color(0.42, 0.43, 0.47)

const ICONS := {
	"shop_guns": ["G", Color(1.0, 0.55, 0.15)], "shop_clothes": ["C", Color(0.2, 0.85, 0.95)], "shop_barber": ["B", Color(1.0, 0.3, 0.3)],
	"shop_market": ["M", Color(0.3, 0.9, 0.45)], "shop_garage": ["T", Color(1.0, 0.85, 0.2)], "safehouse": ["H", Color(0.45, 0.9, 0.6)],
	"police_hq": ["P", Color(0.35, 0.55, 1.0)], "hospital": ["+", Color(1.0, 1.0, 1.0)], "airfield": ["A", Color(0.8, 0.85, 0.95)],
	"marina": ["~", Color(0.4, 0.75, 1.0)], "lm_gas_station": ["F", Color(0.4, 1.0, 0.5)], "range": ["R", Color(1.0, 0.6, 0.6)],
	"taxi_depot": ["Z", Color(1.0, 0.8, 0.1)], "lookout": ["^", Color(0.7, 0.9, 0.7)], "helipad_tower": ["h", Color(0.8, 0.85, 0.95)],
	"stunt": ["J", Color(1.0, 0.45, 0.2)],
}
const ICON_NAMES := {
	"shop_guns": "Bulwark Arms (weapons)", "shop_clothes": "Threadline (clothing)", "shop_barber": "Fade Factory (barber)",
	"shop_market": "QuikNook 24 (snacks)", "shop_garage": "Torque House Customs", "safehouse": "Safehouse",
	"police_hq": "VBPD Headquarters", "hospital": "Vesper General", "airfield": "Vesper Airfield", "marina": "Marina",
	"lm_gas_station": "Gull Gas", "range": "Shooting range", "taxi_depot": "ZipCab depot", "lookout": "Lookout Hill",
	"helipad_tower": "Helipad tower", "stunt": "Stunt jump",
}

static func draw(ci: CanvasItem, xf: Transform2D, detail: bool, font: Font = null) -> void:
	var world: World = Game.world
	if world == null or world.layout == null:
		return
	var layout := world.layout
	ci.draw_set_transform_matrix(xf)
	# land masses over a water background (caller clears to water colour)
	ci.draw_rect(Rect2(-520, -520, 816, 742), C_LAND)
	ci.draw_rect(Rect2(-520, -520, 461, 461), C_HILL)
	ci.draw_rect(Rect2(-300, 222, 340, 15), C_SAND)
	ci.draw_rect(Rect2(31, 222, 12, 70), C_BLOCK)
	for b in layout.blocks:
		var r: Rect2 = b["rect"]
		if r.size.x < 0.5 or r.size.y < 0.5:
			continue
		var col := C_BLOCK
		match String(b["district"]):
			"park", "residential": col = C_PARK if String(b["district"]) == "park" else Color(0.24, 0.3, 0.25)
			"beach": col = Color(0.5, 0.42, 0.3)
			"airfield": col = Color(0.26, 0.31, 0.24)
		ci.draw_rect(r, col)
	# runway + taxiway
	ci.draw_rect(Rect2(CitySpecial.RW_X - CitySpecial.RW_HW, CitySpecial.RW_Z0, CitySpecial.RW_HW * 2.0, CitySpecial.RW_Z1 - CitySpecial.RW_Z0), C_RUNWAY)
	ci.draw_rect(Rect2(CitySpecial.TW_X - CitySpecial.TW_HW, -274.0, CitySpecial.TW_HW * 2.0, 370.0), C_RUNWAY.darkened(0.15))
	ci.draw_rect(Rect2(-64.0, 222.0, 8.0, 74.0), Color(0.45, 0.38, 0.28))
	for road in layout.roads:
		var pts: PackedVector3Array = road["pts"]
		var col2 := C_ARTERIAL if road["kind"] == "arterial" else C_ROAD
		var width := float(road["hw"]) * 2.0
		var line := PackedVector2Array()
		for p in pts:
			line.append(Vector2(p.x, p.z))
		if line.size() >= 2:
			ci.draw_polyline(line, col2, width)
	for id in layout.nodes.keys():
		var nr := layout.node_rect(layout.nodes[id])
		ci.draw_rect(nr, C_ROAD)
	if detail and world.city != null:
		for f in world.city.footprints:
			ci.draw_rect(f["rect"], C_BUILDING)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## Location icons (drawn unrotated in screen space). Returns [[screen pos, id], ...] for hit-testing.
static func draw_icons(ci: CanvasItem, xf: Transform2D, font: Font, size: float, clip_radius := -1.0, clip_center := Vector2.ZERO) -> Array:
	var out: Array = []
	var world: World = Game.world
	if world == null or world.city == null:
		return out
	for key in world.city.locations.keys():
		var loc: Dictionary = world.city.locations[key]
		var lid := String(loc.get("id", key))
		if not ICONS.has(lid):
			continue
		var wp: Vector3 = loc["pos"]
		var sp := xf * Vector2(wp.x, wp.z)
		if clip_radius > 0.0:
			var d := sp - clip_center
			if d.length() > clip_radius:
				continue
		var ic: Array = ICONS[lid]
		ci.draw_circle(sp, size * 0.62, Color(0.05, 0.06, 0.08, 0.85))
		ci.draw_arc(sp, size * 0.62, 0.0, TAU, 20, ic[1], 1.6)
		if font != null:
			var ts := font.get_string_size(ic[0], HORIZONTAL_ALIGNMENT_CENTER, -1, int(size))
			ci.draw_string(font, sp + Vector2(-ts.x * 0.5, size * 0.36), ic[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), ic[1])
		out.append([sp, key])
	return out
