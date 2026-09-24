class_name Card
extends RefCounted
## A standard playing card. rank: 2..14 (11 = J, 12 = Q, 13 = K, 14 = A). suit: 0..3.

const RANK_CHARS := "23456789TJQKA"
const SUIT_CHARS := "SHDC"
const SUIT_SYMBOLS := ["♠", "♥", "♦", "♣"]

var rank: int
var suit: int


func _init(p_rank: int = 2, p_suit: int = 0) -> void:
	assert(p_rank >= 2 and p_rank <= 14, "rank out of range")
	assert(p_suit >= 0 and p_suit <= 3, "suit out of range")
	rank = p_rank
	suit = p_suit


## Parses two-character codes such as "AS", "TD", "9H", "2C".
static func from_code(code_text: String) -> Card:
	if code_text.length() != 2:
		push_error("Invalid card code: %s" % code_text)
		return null
	var r := RANK_CHARS.find(code_text.substr(0, 1).to_upper())
	var s := SUIT_CHARS.find(code_text.substr(1, 1).to_upper())
	if r < 0 or s < 0:
		push_error("Invalid card code: %s" % code_text)
		return null
	return Card.new(r + 2, s)


static func rank_text(r: int) -> String:
	match r:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
	return str(r)


func code() -> String:
	return RANK_CHARS[rank - 2] + SUIT_CHARS[suit]


func rank_label() -> String:
	return rank_text(rank)


func suit_symbol() -> String:
	return SUIT_SYMBOLS[suit]


func is_red() -> bool:
	return suit == 1 or suit == 2


func label() -> String:
	return rank_label() + suit_symbol()


func _to_string() -> String:
	return code()
