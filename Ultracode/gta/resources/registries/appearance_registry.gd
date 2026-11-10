extends RefCounted
## Registry registrar of the CHARACTER module: kinds "clothing" and "hair".
## Every definition is a Dictionary:
##   id            unique id inside its kind ("top_tee", "hat_cap", "hair_short", "beard_full" ...)
##   slot          appearance key the item goes into: top / bottom / shoes / hat / glasses  (clothing)
##                 or hair / beard (hair)
##   part          value to store under that key, e.g. visual.update_appearance({d.slot: d.part})
##   color_key     appearance key of the item's colour ("" = not recolourable)
##   default_color "#rrggbb" suggested colour
##   colors        palette offered by wardrobe / barber UIs
##   display_name, price, body ("" both, "f" / "m" = cut for that body only), tags
## Wardrobe / shop UIs read them with Registry.all("clothing") / Registry.all("hair"); the look is
## applied through CharacterVisual.update_appearance(). Nothing here is required for gameplay.

const TOP_COLORS := ["#efede6", "#c8443a", "#3f7fc8", "#4e9a63", "#e8c24a", "#ee7e64", "#22a7a0", "#27405f", "#3b404b",
	"#b7a6e0", "#e89aae", "#f0802f", "#8a9a5b", "#7a50d0", "#8fcae8", "#1c1e23", "#a2d9c2", "#b35a42"]
const BOTTOM_COLORS := ["#3f5f8f", "#27405f", "#1c1e23", "#bfa77a", "#3b404b", "#8d887f", "#5f6b45", "#7b5637", "#efede6", "#6b88b5"]
const SHOE_COLORS := ["#2a2a2e", "#e9e7e1", "#4a3426", "#c8443a", "#27405f", "#1c1e23", "#7a5a3c", "#22a7a0"]
const HAT_COLORS := ["#c8443a", "#27405f", "#1c1e23", "#efede6", "#22a7a0", "#e2b13c", "#4e9a63", "#3b404b", "#ee7e64", "#bfa77a"]
const SUIT_COLORS := ["#27405f", "#3b404b", "#1c1e23", "#5b6470", "#7b5637", "#8d887f"]
const HAIR_COLORS := ["#22201f", "#3a2a1e", "#5a3a25", "#8a5a34", "#d9b56a", "#a6452a", "#9a9a98", "#e6e2d8",
	"#22a7a0", "#b7a6e0", "#e89aae", "#2c6fd9"]

# [id, slot, part, display name, price, default colour, palette, body]
const CLOTHING := [
	["top_tee", "top", "tee", "Ringer Tee", 40, "#3f7fc8", TOP_COLORS, ""],
	["top_tank", "top", "tank", "Tank Top", 30, "#ee7e64", TOP_COLORS, ""],
	["top_shirt", "top", "shirt", "Button-Up Shirt", 70, "#efede6", TOP_COLORS, ""],
	["top_hoodie", "top", "hoodie", "Bay Hoodie", 90, "#3b404b", TOP_COLORS, ""],
	["top_jacket", "top", "jacket", "Bomber Jacket", 160, "#22a7a0", TOP_COLORS, ""],
	["top_vest", "top", "vest", "Rider Vest", 140, "#1c1e23", TOP_COLORS, ""],
	["top_suit", "top", "suit", "Tailored Suit Jacket", 450, "#27405f", SUIT_COLORS, ""],
	["bottom_jeans", "bottom", "jeans", "Straight Jeans", 80, "#3f5f8f", BOTTOM_COLORS, ""],
	["bottom_shorts", "bottom", "shorts", "Board Shorts", 45, "#22a7a0", BOTTOM_COLORS, ""],
	["bottom_cargo", "bottom", "cargo", "Cargo Pants", 95, "#bfa77a", BOTTOM_COLORS, ""],
	["bottom_slacks", "bottom", "slacks", "Pressed Slacks", 120, "#3b404b", BOTTOM_COLORS, ""],
	["bottom_skirt", "bottom", "skirt", "A-Line Skirt", 70, "#27405f", BOTTOM_COLORS, "f"],
	["shoes_sneakers", "shoes", "sneakers", "Court Sneakers", 110, "#e9e7e1", SHOE_COLORS, ""],
	["shoes_boots", "shoes", "boots", "Work Boots", 150, "#4a3426", SHOE_COLORS, ""],
	["shoes_dress", "shoes", "dress", "Dress Shoes", 190, "#1c1e23", SHOE_COLORS, ""],
	["hat_none", "hat", "", "No Hat", 0, "", [], ""],
	["hat_cap", "hat", "cap", "Ball Cap", 35, "#c8443a", HAT_COLORS, ""],
	["hat_beanie", "hat", "beanie", "Beanie", 30, "#3b404b", HAT_COLORS, ""],
	["hat_brim", "hat", "brim", "Brim Hat", 85, "#bfa77a", HAT_COLORS, ""],
	["hat_bandana", "hat", "bandana", "Bandana", 20, "#c8443a", HAT_COLORS, ""],
	["glasses_none", "glasses", "", "No Glasses", 0, "", [], ""],
	["glasses_shades", "glasses", "shades", "Shades", 60, "", [], ""],
	["glasses_round", "glasses", "round", "Round Frames", 75, "", [], ""],
]

const HAIR := [
	["hair_bald", "hair", "bald", "Clean Shave", 15, "", [], ""],
	["hair_buzz", "hair", "buzz", "Buzz Cut", 20, "#22201f", HAIR_COLORS, ""],
	["hair_short", "hair", "short", "Short Crop", 25, "#3a2a1e", HAIR_COLORS, ""],
	["hair_slick", "hair", "slick", "Pompadour", 35, "#22201f", HAIR_COLORS, ""],
	["hair_curly", "hair", "curly", "Curls", 35, "#3a2a1e", HAIR_COLORS, ""],
	["hair_ponytail", "hair", "ponytail", "Ponytail", 30, "#5a3a25", HAIR_COLORS, ""],
	["hair_long", "hair", "long", "Long & Loose", 40, "#5a3a25", HAIR_COLORS, ""],
	["hair_bob", "hair", "bob", "Blunt Bob", 40, "#a6452a", HAIR_COLORS, ""],
	["hair_bun", "hair", "bun", "Top Bun", 30, "#22201f", HAIR_COLORS, ""],
	["hair_mohawk", "hair", "mohawk", "Bayside Mohawk", 45, "#22a7a0", HAIR_COLORS, ""],
	["beard_none", "beard", "", "Clean Shaven", 10, "", [], ""],
	["beard_mustache", "beard", "mustache", "Moustache", 15, "", [], "m"],
	["beard_goatee", "beard", "goatee", "Goatee", 18, "", [], "m"],
	["beard_full", "beard", "full", "Full Beard", 22, "", [], "m"],
]

const COLOR_KEYS := {"top": "top_color", "bottom": "bottom_color", "shoes": "shoes_color", "hat": "hat_color",
	"glasses": "", "hair": "hair_color", "beard": "hair_color"}


static func register_all(registry: Node) -> void:
	if registry == null or not registry.has_method("register"):
		return
	for row: Array in CLOTHING:
		registry.call("register", "clothing", _def(row, "clothing"))
	for row: Array in HAIR:
		registry.call("register", "hair", _def(row, "hair"))


static func _def(row: Array, kind: String) -> Dictionary:
	var slot := str(row[1])
	var colors: Array = (row[6] as Array).duplicate()
	return {
		"id": str(row[0]),
		"kind": kind,
		"slot": slot,
		"part": str(row[2]),
		"display_name": str(row[3]),
		"price": int(row[4]),
		"default_color": str(row[5]),
		"color_key": str(COLOR_KEYS.get(slot, "")) if not colors.is_empty() else "",
		"colors": colors,
		"body": str(row[7]),
		"tags": [slot],
	}
