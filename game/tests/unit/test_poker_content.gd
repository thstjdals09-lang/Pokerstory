extends "res://tests/test_case.gd"
## Content v0.3 Stage 5: 10 opponents with personas, 8 abilities, practice + 3 modes + tournament,
## on the one five-card single-draw engine. The AI only ever sees its own cards; abilities only
## use the player's cards, a yes/no about the opponent (Star Sense) or public table history.

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _stack(player: String, opponent: String, draws: String = "") -> Deck:
	var p := player.split(" ", false)
	var o := opponent.split(" ", false)
	var order: Array = []
	for i in 5:
		order.append(p[i])
		order.append(o[i])
	order.append_array(Array(draws.split(" ", false)))
	return Deck.stacked(order)


## No card twice among both hands and the rest of the deck; replaced cards left the table.
func _all_unique(m: PokerMatch) -> bool:
	var seen := {}
	var total := 0
	for c in m.player_hand + m.opponent_hand:
		seen[c.code()] = true
		total += 1
	for code in m.deck.codes():
		seen[code] = true
		total += 1
	return seen.size() == total and total == 52 - m.player_discards.size() - m.opponent_discards.size()


func test_ten_opponents_eight_abilities_modes_and_tournament() -> void:
	check_eq(errors, [], "data errors")
	check_eq(db.opponents.size(), 10, "10 opponents")
	for npc in db.opponents:
		var o: Dictionary = db.opponents[npc]
		check(db.npcs.has(npc), npc + " is a resident")
		check(["steady", "keep_pairs", "cautious", "curious", "friendly"].has(o.get("persona", "")), npc + " persona")
		for k in ["win", "draw", "lose"]:
			check(str(o.get("lines", {}).get(k, "")) != "", "%s says something after a %s" % [npc, k])
	check_eq(db.abilities.size(), 8, "8 abilities")
	var effects := {}
	for a in db.abilities.values():
		effects[a["effect"]] = true
		check(int(a.get("uses_per_match", 0)) == 1, a["id"] + " once per hand")
	check_eq(effects.size(), 8, "8 different effects")
	check(db.ability_aliases.get("ability.starlight_sense", "") == "ability.star_sense", "pack id maps to the kept id (C2)")
	var modes: Dictionary = db.poker["modes"]
	for m in ["practice", "homegame", "social_mix", "friendly_challenge", "tournament"]:
		check(modes.has(m), "mode " + m)
	check_eq(int(modes["practice"]["stake"]), 0, "practice is free")
	for m in ["homegame", "social_mix", "friendly_challenge", "tournament"]:
		check_eq(int(modes[m]["stake"]), 20, m + " uses the approved stake 20")
	check_eq(modes["tournament"]["stages"].size(), 3, "tournament has 3 rounds")
	check(not db.shops["swap_shop"]["items"].any(func(e): return (e if e is String else e["item"]) == modes["tournament"]["reward_item"]), "tournament reward is not sold")


func test_ai_sees_only_its_own_cards_for_every_persona() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for persona in ["steady", "keep_pairs", "cautious", "curious", "friendly"]:
		for n in 60:
			var deck := Deck.shuffled(rng.randi())
			var m := PokerMatch.new(deck)
			m.persona = persona
			var own: Array = m.opponent_hand.duplicate()
			var d1 := PokerAI.choose_discards(own.duplicate(), 3, persona)
			var d2 := PokerAI.choose_discards(own.duplicate(), 3, persona)
			check_eq(d1, d2, "%s is deterministic" % persona)
			check(d1.size() <= 3, "%s replaces at most 3" % persona)
			var seen := {}
			for i in d1:
				check(i >= 0 and i < 5 and not seen.has(i), "%s picks valid distinct cards" % persona)
				seen[i] = true
			check(m.player_draw([]), "hand plays")
			check(_all_unique(m), "%s hand keeps 52 unique cards" % persona)
			check_eq(m.opponent_discards, d1, "%s draw follows the public rule" % persona)
	# Same opponent cards, different player cards: the opponent acts the same.
	var a := PokerMatch.new(_stack("AS AH AD 7C 2S", "QS QH 9D 5C 3H"))
	var b := PokerMatch.new(_stack("2C 3D 4H 8S 9C", "QS QH 9D 5C 3H"))
	for m in [a, b]:
		m.persona = "cautious"
		m.player_draw([])
	check_eq(a.opponent_discards, b.opponent_discards, "the player's cards never change the opponent's choice")


func test_personas_differ_only_in_how_boldly_they_replace() -> void:
	var high := PokerMatch.new(_stack("2C 3D 4H 8S 9C", "AS 7H 9D 5C 3S")).opponent_hand
	check_eq(PokerAI.choose_discards(high.duplicate(), 3, "steady").size(), 3, "steady replaces 3 with high card")
	check_eq(PokerAI.choose_discards(high.duplicate(), 3, "cautious").size(), 2, "cautious keeps one more")
	var flushy := PokerMatch.new(_stack("2C 3D 4H 8S 9C", "AS 7S JS 5S 3H")).opponent_hand
	check_eq(PokerAI.choose_discards(flushy.duplicate(), 3, "steady"), [4], "steady chases the flush")
	check_eq(PokerAI.choose_discards(flushy.duplicate(), 3, "curious").size(), 3, "curious always replaces three")
	var pair := PokerMatch.new(_stack("2C 3D 4H 8S 9C", "QS QH 9D 5C 3H")).opponent_hand
	check_eq(PokerAI.choose_discards(pair.duplicate(), 3, "friendly"), [3, 4], "friendly keeps the best kicker")


func test_abilities_use_only_allowed_information() -> void:
	var same_player := "AS AH KD 7C 2S"
	var own_effects := ["own_suit_count", "discard_hint", "help_focus"]
	for a in db.abilities.values():
		if not own_effects.has(a["effect"]):
			continue
		var x := PokerMatch.new(_stack(same_player, "QS QH 9D 5C 3H"))
		var y := PokerMatch.new(_stack(same_player, "2D 2H 2C 9S 9H"))
		var rx := x.use_ability(a)
		var ry := y.use_ability(a)
		check(rx["ok"], a["id"] + " works")
		check_eq(rx, ry, a["id"] + " does not depend on the opponent's hidden cards")
		check(not x.use_ability(a)["ok"], a["id"] + " only once per hand")
	var suit := PokerMatch.new(_stack("AS 3S KS 7C 2D", "QS QH 9D 5C 3H"))
	var rs := suit.use_ability(db.abilities["ability.suit_echo"])
	check_eq([rs["suit"], rs["count"]], ["♠", 3], "suit echo counts my spades")
	var hint := PokerMatch.new(_stack("AS AH KD 7C 2S", "QS QH 9D 5C 3H")).use_ability(db.abilities["ability.discard_hint"])
	check_eq(hint["keep"], [0, 1], "discard hint points at the pair")
	# Public history only.
	var read := PokerMatch.new(_stack(same_player, "QS QH 9D 5C 3H"))
	check_eq(read.use_ability(db.abilities["ability.table_read"], {"history": []})["known"], false, "no history, nothing known")
	var hist := [{"discards": 3, "hand": "원페어"}, {"discards": 1, "hand": "투페어"}, {"discards": 3, "hand": "원페어"}]
	var r2 := PokerMatch.new(_stack(same_player, "QS QH 9D 5C 3H")).use_ability(db.abilities["ability.table_read"], {"history": hist})
	check_eq(r2["discards"], 3, "last public discard count")
	var pb := PokerMatch.new(_stack(same_player, "QS QH 9D 5C 3H")).use_ability(db.abilities["ability.pattern_book"], {"history": hist})
	check_eq([pb["common_hand"], pb["hands_seen"]], ["원페어", 3], "pattern book reads public hands")
	for r in [r2, pb]:
		check(not str(r).contains("QS") and not str(r).contains("♥"), "no card of the current hidden hand")


func test_lucky_mark_and_steady_hand_never_change_cards() -> void:
	var m := PokerMatch.new(_stack("AS AH KD 7C 2S", "QS QH 9D 5C 3H", "6H 4D 8S JC"))
	var before := m.player_hand.map(func(c): return c.code())
	check(m.use_ability(db.abilities["ability.lucky_mark"], {"index": 1})["ok"], "mark a card")
	check_eq(m.player_hand.map(func(c): return c.code()), before, "marking changes no card")
	check(not m.player_draw([1, 4]), "a marked card cannot be replaced")
	check(m.player_draw([4]), "other cards still can")
	check_eq(m.player_hand[1].code(), "AH", "marked card kept")
	var u := PokerMatch.new(_stack("AS AH KD 7C 2S", "QS QH 9D 5C 3H"))
	var codes := u.deck.codes()
	check(u.use_ability(db.abilities["ability.steady_hand"])["undo"], "undo used")
	check_eq(u.deck.codes(), codes, "undo does not touch the deck")


func test_mode_ability_and_mark_survive_a_restart() -> void:
	var m := PokerMatch.new(_stack("AS AH KD 7C 2S", "QS QH 9D 5C 3H"))
	m.mode = "friendly_challenge"
	m.opponent_id = "npc_kyle"
	m.persona = "steady"
	m.ability_id = "ability.lucky_mark"
	m.stake = 20
	m.use_ability(db.abilities["ability.lucky_mark"], {"index": 2})
	var back := PokerMatch.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check(back != null, "restores")
	check_eq([back.mode, back.opponent_id, back.ability_id, back.stake, back.locked_index], ["friendly_challenge", "npc_kyle", "ability.lucky_mark", 20, 2], "table, opponent, loadout, stake and mark")
	check(not back.can_use_ability(db.abilities["ability.lucky_mark"]), "the ability stays used")
	check_eq(back.deck.codes(), m.deck.codes(), "same deck")
	var old := m.to_dict()
	for k in ["mode", "opponent_id", "persona", "ability_id", "stake", "locked_index"]:
		old.erase(k)
	var legacy := PokerMatch.from_dict(old)
	check_eq([legacy.mode, legacy.stake, legacy.locked_index], ["homegame", -1, -1], "a v3 hand is the card-room home game")


func test_public_history_survives_saving() -> void:
	var s := GameState.new()
	s.poker_history["npc_kyle"] = [{"discards": 2, "hand": "투페어", "outcome": "lose"}]
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(back.poker_history["npc_kyle"], [{"discards": 2, "hand": "투페어", "outcome": "lose"}], "table history kept through a save")
