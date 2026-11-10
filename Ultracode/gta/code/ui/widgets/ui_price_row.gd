class_name UiPriceRow
extends UiListRow
## Stand-alone price row (same drawing as a UiList row with a "price"): name on the left, price on
## the right in sun yellow, red when the player cannot afford it, "OWNED" when owned.
##     var row := UiPriceRow.new("Suppressor", 350, false, &"handgun")
##     row.activated.connect(_buy_suppressor)
## Rows redraw themselves when the player's money changes.

func _init(p_name: String = "", p_price: int = 0, p_owned: bool = false, p_icon: StringName = &"", p_sub: String = "") -> void:
	var d := {"text": p_name, "price": p_price, "owned": p_owned}
	if p_icon != &"":
		d["icon"] = p_icon
	if p_sub != "":
		d["sub"] = p_sub
	super(d)


func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)


func _on_money_changed(_amount: int, _delta: int) -> void:
	queue_redraw()


func set_price(price: int, owned: bool = false) -> void:
	item["price"] = price
	item["owned"] = owned
	queue_redraw()


func get_price() -> int:
	return int(item.get("price", 0))


func is_affordable() -> bool:
	return bool(item.get("owned", false)) or Game.money >= get_price()
