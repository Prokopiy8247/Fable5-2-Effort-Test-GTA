extends RefCounted
## Registry registrar of the ECONOMY module (shops, economy programmer A).
##
## Kind "shops" (ARCHITECTURE_WAVE2 W2.6): one Dictionary per shop
##   id, landmark, kind ("weapons" | "clothing" | "barber" | "general" | "mod_garage" | "gas"),
##   display_name, screen (UI.SCREENS id), stock (ids, "*" = every def of the matching kind) plus the
##   framework keys read by res://gta/code/world/shop_system.gd:
##   tagline        subtitle of the shop screen
##   map_icon       UiIcons id for map legends (get_shop_locations())
##   uses           [{marker, prompt, screen, args}] Interactables at the landmark markers. A def
##                  WITHOUT "uses" is not managed by the framework (only listed for map legends),
##                  so other modules can register shops that build their own use points.
##   staff          true = persistent "shop_staff" NPC at the `staff_marker` marker
##   staff_look     appearance override for that NPC
##   robbable       threatening the staff with a firearm for ~3 s robs the till
##   robbery_cash   [min, max] dollars handed over
##   closed_hours   in-game hours the shop stays closed after a robbery / the clerk's death
##   items          ids of kind "shop_items" sold here (armour, food ...)
##
## Kind "shop_items": consumables and gear (general store, armour at the gun shop)
##   id, display_name, description, category, price, icon (UiIcons id), model (GLB for the
##   preview, "" = icon only), effects: heal (hp), armor (points), stamina (true = refill),
##   parachute (true), scuba (true).
##
## Prices are balanced against Game.START_MONEY (5000): food 3-16, medkit 120, vests 350-1000,
## parachute 300, scuba 650. Weapons / ammo / attachments use the WeaponSpec / AttachmentSpec
## prices (weapons_registry.gd), clothing and haircuts the appearance registry prices.

const SHOPS := [
	{
		"id": "bay_arms", "landmark": "gun_shop", "kind": "weapons", "display_name": "Bay Arms",
		"tagline": "Firearms, ammunition, armour and a workbench", "screen": "shop_weapons", "map_icon": "gun_shop",
		"uses": [
			{"marker": "Use_Counter", "prompt": "Shop at Bay Arms", "screen": "shop_weapons", "args": {"page": "shop"}},
			{"marker": "Use_Workbench", "prompt": "Use the workbench", "screen": "shop_weapons", "args": {"page": "workbench"}},
		],
		"staff": true, "staff_marker": "Staff",
		"staff_look": {"body": "m", "skin": "#c98f63", "hair": "buzz", "hair_color": "#22201f", "beard": "full",
			"top": "vest", "top_color": "#3b404b", "bottom": "cargo", "bottom_color": "#5f6b45",
			"shoes": "boots", "shoes_color": "#4a3426", "hat": "cap", "hat_color": "#27405f"},
		"robbable": true, "robbery_cash": [700, 1500], "closed_hours": 6.0,
		"stock": ["knife", "bat", "crowbar", "pistol", "heavy_pistol", "smg", "pump_shotgun", "auto_shotgun",
			"assault_rifle", "carbine", "marksman_rifle", "sniper_rifle", "rocket_launcher", "grenade_launcher",
			"grenade", "molotov"],
		"items": ["armor_light", "armor_heavy"],
	},
	{
		"id": "tide_threads", "landmark": "clothing_store", "kind": "clothing", "display_name": "Tide Threads",
		"tagline": "Coastal clothing - tops, bottoms, shoes, hats and glasses", "screen": "shop_clothing", "map_icon": "shirt",
		"uses": [
			{"marker": "Use_Counter", "prompt": "Browse Tide Threads", "screen": "shop_clothing", "args": {}},
			{"marker": "Use_Wardrobe", "prompt": "Change clothes", "screen": "wardrobe", "args": {}},
		],
		"staff": true, "staff_marker": "Staff",
		"staff_look": {"body": "f", "skin": "#e8b88f", "hair": "ponytail", "hair_color": "#a6452a",
			"top": "shirt", "top_color": "#efede6", "bottom": "skirt", "bottom_color": "#22a7a0",
			"shoes": "dress", "shoes_color": "#1c1e23", "glasses": "round"},
		"robbable": true, "robbery_cash": [400, 900], "closed_hours": 6.0,
		"stock": ["*"],
	},
	{
		"id": "harbor_cuts", "landmark": "barber", "kind": "barber", "display_name": "Harbor Cuts",
		"tagline": "Cuts, colours and beard trims", "screen": "shop_barber", "map_icon": "scissors",
		"uses": [
			{"marker": "Use_Chair", "prompt": "Get a haircut", "screen": "shop_barber", "args": {}},
		],
		"staff": true, "staff_marker": "Staff",
		"staff_look": {"body": "m", "skin": "#8a5636", "hair": "slick", "hair_color": "#22201f", "beard": "mustache",
			"outfit": "staff"},
		"robbable": true, "robbery_cash": [150, 450], "closed_hours": 6.0,
		"stock": ["*"],
	},
	{
		"id": "corner_24", "landmark": "general_store", "kind": "general", "display_name": "Corner 24",
		"tagline": "Snacks, drinks, first aid and beach gear - open around the clock", "screen": "shop_general",
		"map_icon": "bag",
		"uses": [
			{"marker": "Use_Counter", "prompt": "Shop at Corner 24", "screen": "shop_general", "args": {}},
		],
		"staff": true, "staff_marker": "Staff",
		"staff_look": {"body": "f", "skin": "#b97c54", "hair": "curly", "hair_color": "#3a2a1e", "outfit": "staff"},
		"robbable": true, "robbery_cash": [250, 650], "closed_hours": 6.0,
		"stock": ["snack_chips", "snack_bar", "snack_burrito", "drink_water", "drink_soda", "drink_coffee",
			"bandage", "medkit", "armor_vest_light", "parachute", "scuba_kit"],
	},
]

# [id, name, category, price, icon, model, effects, description]
const ITEMS := [
	["snack_chips", "Saltwave Chips", "food", 6, "bag", "", {"heal": 12}, "Sea-salt crisps. A small pick-me-up."],
	["snack_bar", "Reef Bar", "food", 9, "bag", "", {"heal": 18}, "Oats, honey and a lot of sugar."],
	["snack_burrito", "Dockside Burrito", "food", 16, "bag", "", {"heal": 35}, "Hot from the counter grill. Heavy."],
	["drink_water", "Bay Spring Water", "drinks", 3, "drop", "", {"heal": 5, "stamina": true}, "Cold water. Restores stamina."],
	["drink_soda", "Fizz Lime Soda", "drinks", 5, "drop", "", {"heal": 8, "stamina": true}, "Sugar rush. Restores stamina."],
	["drink_coffee", "Harbor Roast", "drinks", 8, "drop", "", {"heal": 10, "stamina": true}, "Strong black coffee. Restores stamina."],
	["bandage", "Bandage Roll", "health", 45, "heart", "", {"heal": 40}, "Patches up cuts and grazes."],
	["medkit", "First Aid Kit", "health", 120, "heart", "res://gta/generated/models/props/pickups/medkit.glb", {"heal": 100},
		"Full medical kit. Restores all health."],
	["armor_vest_light", "Light Vest", "gear", 350, "shield", "res://gta/generated/models/props/pickups/armor_vest.glb",
		{"armor": 40}, "Thin soft armour under a jacket. +40 armour."],
	["parachute", "Glide Pack", "gear", 300, "umbrella", "res://gta/generated/models/props/pickups/parachute_pack.glb",
		{"parachute": true}, "Ram-air parachute. Jump from something high and deploy."],
	["scuba_kit", "Scuba Kit", "gear", 650, "bubbles", "res://gta/generated/models/props/pickups/scuba_tank.glb",
		{"scuba": true}, "Tank and regulator. Breath lasts far longer under water."],
	["armor_light", "Patrol Vest", "armour", 500, "shield", "res://gta/generated/models/props/pickups/armor_vest.glb",
		{"armor": 50}, "Soft body armour. +50 armour."],
	["armor_heavy", "Plate Carrier", "armour", 1000, "shield", "res://gta/generated/models/props/pickups/armor_vest.glb",
		{"armor": 100}, "Hard plates front and back. Full armour."],
]


static func register_all(registry: Node) -> void:
	if registry == null or not registry.has_method("register"):
		return
	for d: Dictionary in SHOPS:
		registry.call("register", "shops", d.duplicate(true))
	for row: Array in ITEMS:
		registry.call("register", "shop_items", {
			"id": str(row[0]), "display_name": str(row[1]), "category": str(row[2]), "price": int(row[3]),
			"icon": str(row[4]), "model": str(row[5]), "effects": (row[6] as Dictionary).duplicate(),
			"description": str(row[7]),
		})
