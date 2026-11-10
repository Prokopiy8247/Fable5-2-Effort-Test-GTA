class_name Appearance
extends RefCounted
## Character looks as plain data: body type, skin/hair, clothing colours and accessory
## meshes. Converted into the 16 region colours of the Character shader. Used by the
## player wardrobe / clothing store / barber and by the NPC population generator.

const SKINS := ["f1c9a5", "e3b58c", "d9a273", "c08a5c", "a8734a", "8a5a3a", "6f4a30", "573823"]
const HAIRS := ["1c1a1a", "2e241d", "4f3523", "7a5236", "d9b76a", "a3492a", "8c8983", "e3dfd4", "3a5fa8", "d0409a"]
const SHIRTS := ["f2f0ea", "17181b", "d43d33", "2f6fd0", "3fa55a", "f2c230", "ef7f2d", "7a48c2", "2aa59a", "f08ab8",
	"8b8e93", "22407f", "8f2a25", "6b7a3a", "c9a97f", "3ec3e0", "55585e", "b23a3a"]
const PANTS := ["2e3035", "3d5a80", "22407f", "55585e", "b5a27a", "17181b", "7a5236", "6b7a3a", "8b8e93", "c9bd9a"]
const SHOES := ["17181b", "f2f0ea", "7a5236", "d43d33", "2e3035", "8b8e93"]
const HAIR_STYLES_M := ["", "hair_short", "hair_side", "hair_mohawk", "hair_afro", "hair_long", "hair_pony"]
const HAIR_STYLES_F := ["hair_long", "hair_pony", "hair_bun", "hair_bob", "hair_afro", "hair_short", "hair_side"]
const HATS := ["", "cap", "beanie", "hat_brim"]
const GLASSES := ["", "glasses", "sunglasses"]
const BEARDS := ["", "beard", "mustache"]

static func default_player() -> Dictionary:
	return {
		"body": "male", "skin": "d9a273", "hair_color": "2e241d", "hair": "hair_short", "beard": "",
		"shirt": "22407f", "sleeves": "long", "pants": "2e3035", "legs": "long", "shoes": "f2f0ea",
		"hat": "", "hat_color": "d43d33", "glasses": "", "glasses_color": "17181b",
		"vest": "", "vest_color": "2e3035", "belt": "17181b", "detail": "c9a24a", "extras": [],
	}

static func random_civilian(rng: RandomNumberGenerator) -> Dictionary:
	var fem := rng.randf() < 0.48
	var styles: Array = HAIR_STYLES_F if fem else HAIR_STYLES_M
	var ap := {
		"body": "female" if fem else "male",
		"skin": SKINS[rng.randi() % SKINS.size()],
		"hair_color": HAIRS[rng.randi() % (HAIRS.size() - (0 if rng.randf() < 0.08 else 2))],
		"hair": styles[rng.randi() % styles.size()],
		"beard": "" if fem or rng.randf() < 0.65 else BEARDS[1 + rng.randi() % 2],
		"shirt": SHIRTS[rng.randi() % SHIRTS.size()],
		"sleeves": "long" if rng.randf() < 0.4 else "short",
		"pants": PANTS[rng.randi() % PANTS.size()],
		"legs": "short" if rng.randf() < 0.28 else "long",
		"shoes": SHOES[rng.randi() % SHOES.size()],
		"hat": HATS[rng.randi() % HATS.size()] if rng.randf() < 0.3 else "",
		"hat_color": SHIRTS[rng.randi() % SHIRTS.size()],
		"glasses": GLASSES[1 + rng.randi() % 2] if rng.randf() < 0.22 else "",
		"glasses_color": "17181b",
		"vest": "", "vest_color": "2e3035", "belt": "2e241d", "detail": "c9c9c9", "extras": [],
	}
	if fem and rng.randf() < 0.3:
		ap["extras"] = ["skirt"]
		ap["legs"] = "short"
	return ap

static func police(rng: RandomNumberGenerator, tactical := false) -> Dictionary:
	var ap := random_civilian(rng)
	ap["shirt"] = "1c2748" if not tactical else "17181b"
	ap["sleeves"] = "short" if not tactical and rng.randf() < 0.5 else "long"
	ap["pants"] = "1c2748" if not tactical else "17181b"
	ap["legs"] = "long"
	ap["shoes"] = "17181b"
	ap["belt"] = "17181b"
	ap["detail"] = "c9a24a"
	ap["glasses"] = "sunglasses" if rng.randf() < 0.3 else ""
	ap["beard"] = ""
	if tactical:
		ap["hat"] = "helmet_tactical"
		ap["hat_color"] = "26272b"
		ap["vest"] = "vest_tactical"
		ap["vest_color"] = "2e3035"
		ap["extras"] = ["holster"]
		ap["hair"] = ""
	else:
		ap["hat"] = "cap_police"
		ap["hat_color"] = "1c2748"
		ap["extras"] = ["badge", "holster"]
		if ap["hair"] in ["hair_afro", "hair_mohawk", "hair_long"]:
			ap["hair"] = "hair_short"
	return ap

static func staff(rng: RandomNumberGenerator, shirt_hex: String) -> Dictionary:
	var ap := random_civilian(rng)
	ap["shirt"] = shirt_hex
	ap["sleeves"] = "short"
	ap["legs"] = "long"
	ap["hat"] = ""
	return ap

static func gang(rng: RandomNumberGenerator) -> Dictionary:
	var ap := random_civilian(rng)
	ap["body"] = "male"
	ap["shirt"] = ["7a48c2", "17181b", "6a1f2a"][rng.randi() % 3]
	ap["hat"] = "beanie" if rng.randf() < 0.5 else ""
	ap["hat_color"] = "17181b"
	ap["extras"] = ["bandana"] if rng.randf() < 0.5 else []
	ap["hair"] = HAIR_STYLES_M[rng.randi() % HAIR_STYLES_M.size()]
	return ap

static func _c(hex: Variant, fallback := "ff00ff") -> Color:
	var s := String(hex) if hex != null else fallback
	if s == "":
		s = fallback
	return Color.html(s)

## 16 region colours (see tools/blender/SPEC_CHARACTERS.md for the region table).
static func region_colors(ap: Dictionary) -> PackedColorArray:
	var skin := _c(ap.get("skin", "d9a273"))
	var shirt := _c(ap.get("shirt", "f2f0ea"))
	var pants := _c(ap.get("pants", "2e3035"))
	var out := PackedColorArray()
	out.resize(16)
	out[0] = skin
	out[1] = shirt
	out[2] = shirt
	out[3] = shirt if String(ap.get("sleeves", "short")) == "long" else skin
	out[4] = skin
	out[5] = pants
	out[6] = pants
	out[7] = pants if String(ap.get("legs", "long")) == "long" else skin
	out[8] = _c(ap.get("shoes", "17181b"))
	out[9] = _c(ap.get("hair_color", "2e241d"))
	out[10] = Color(0.06, 0.05, 0.05)
	out[11] = _c(ap.get("hat_color", "d43d33"))
	out[12] = _c(ap.get("glasses_color", "17181b"))
	out[13] = _c(ap.get("vest_color", "2e3035"))
	out[14] = _c(ap.get("belt", "17181b"))
	out[15] = _c(ap.get("detail", "c9c9c9"))
	return out

## Names of the accessory meshes (without the "acc_" prefix) that should be visible.
static func accessories(ap: Dictionary) -> Array:
	var out: Array = []
	for key: String in ["hair", "beard", "hat", "glasses", "vest"]:
		var v := String(ap.get(key, ""))
		if v != "":
			out.append(v)
	# full head-wear hides voluminous hair
	var hat := String(ap.get("hat", ""))
	if hat.begins_with("helmet") and out.has(String(ap.get("hair", ""))):
		out.erase(String(ap.get("hair", "")))
	for e in ap.get("extras", []):
		out.append(String(e))
	return out
