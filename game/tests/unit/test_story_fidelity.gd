extends "res://tests/test_case.gd"
## Content v0.3.1: the main story keeps the scene scripts' intent and their written lines
## (01_world/04 act 1, 05 act 2, 06 act 3 and postgame), and the conditions that carry the message:
## nobody has to know or win poker, neither Lumi nor Kyle is the villain, the festival ends through
## community work, and the morning after is about who comes back rather than who won.

var db := DataDB.new()
var errors: Array = db.load_all("res://data")


func _lines(id: String) -> String:
	var e := DialogueResolver.find(db.dialogue, id)
	check(not e.is_empty(), "scene %s exists" % id)
	return "\n".join(e.get("lines", []))


func _choice_texts(id: String) -> Array:
	return DialogueResolver.find(db.dialogue, id).get("choices", []).map(func(c): return str(c.get("text", "")))


func test_act1_script_lines_and_welcome() -> void:
	check(_lines("scn.missing_invitation").contains("이번 모임의 초대장, 분명 여기에 두었는데 봉투만 남았어요."), "S1 Moa")
	check_eq(_choice_texts("scn.missing_invitation"), ["찾아볼게요", "나중에요"], "S1 choices")
	check(_lines("scn.postbox_hint").contains("잃어버린 게 아니라 누군가 읽고 다시 접어 둔 것 같아요.") and _lines("scn.postbox_hint").contains("마지막 줄은 물에 젖었지만, 누가 오면 좋겠는지는 남아 있어요."), "S2A Nora")
	check(_choice_texts("scn.postbox_discovery").has("봉투를 모아에게 전하기"), "S2A envelope back to Moa")
	check(_lines("scn.grove_hint").contains("예전엔 클로버 문양을 '우연히 만난 사람도 앉을 자리'란 뜻으로 썼대요."), "S2B Ella")
	check(_lines("scn.grove_hint").contains("가르는 게 아니었어요"), "S2B suits are not a lineage")
	check_eq(_choice_texts("scn.board_reopening"), ["친구와 와도 되나요?", "포커를 몰라도 괜찮나요?"], "S3 questions")
	var answer := _lines("scn.board_reopening_answer")
	check(answer.contains("물론") and answer.contains("포커를 몰라도") and answer.contains("모두 환영"), "S3 everyone is welcome, poker or not")
	for c in DialogueResolver.find(db.dialogue, "scn.board_reopening").get("choices", []):
		check_eq(str(c.get("arg", "")), "scn.board_reopening_answer", "S3 both questions get the same yes")
	var cond: Dictionary = DialogueResolver.find(db.dialogue, "scn.board_reopening")["conditions"]
	check(cond["flags_true"].has("story.clue_postbox") and cond["flags_true"].has("story.clue_grove"), "S3 needs both clues")
	check(not JSON.stringify(cond).contains("poker"), "S3 asks nothing about poker")


func test_act2_no_villain() -> void:
	check(_lines("scn.lumi_view").contains("이긴 사람만 오면, 처음 온 친구는 어디 앉지?"), "S4 Lumi")
	check(_lines("scn.kyle_view").contains("경기가 시작되면 누구에게나 같은 규칙이어야 하지."), "S4 Kyle")
	check(_lines("card_room_notes_act2").contains("친목 모임을 늘려 주세요 — 루미") and _lines("card_room_notes_act2").contains("규칙을 미리 알려 주세요 — 카일"), "S4 two notes")
	for id in ["scn.two_tables_argument_lumi", "scn.two_tables_argument_kyle"]:
		var t := _lines(id)
		check(t.contains("대회에 안 나와도 저녁 모임에 앉아도 된다는 말부터 할게."), id + " Lumi")
		check(t.contains("순서를 정해 두면 새 사람도 경기 규칙을 알 수 있겠군요."), id + " Kyle")
		var texts := _choice_texts(id)
		check(texts.size() == 3 and texts[0].begins_with("친목부터 시작") and texts[1].begins_with("규칙 설명부터 시작") and texts[2] == "둘 다 하는 게 어때요?", id + " three answers")
		for c in DialogueResolver.find(db.dialogue, id)["choices"]:
			check_eq(str(c.get("arg", "")), "scn.two_tables_resolved", id + " every answer reconciles")
			check(not JSON.stringify(c).contains("rivalry") and not JSON.stringify(c).contains("friendship"), id + " no side is punished or rewarded")
		var cond: Dictionary = DialogueResolver.find(db.dialogue, id)["conditions"]
		check(cond["flags_true"].has("story.act2_heard_lumi") and cond["flags_true"].has("story.act2_heard_kyle"), id + " only after hearing both")
	check(_lines("scn.two_tables_resolved").contains("두 형식 모두 언제든 열려"), "S6 both formats stay open")
	var resolved := JSON.stringify(DialogueResolver.find(db.dialogue, "scn.two_tables_resolved"))
	check(resolved.contains("reconciled"), "S7 Lumi and Kyle reconcile")
	for id in ["scn.tea_prep_offer", "scn.rules_prep_offer"]:
		check(not JSON.stringify(DialogueResolver.find(db.dialogue, id)).contains("poker_hands"), id + " no poker win needed")


func test_act3_community_ending() -> void:
	var meeting := _lines("scn.festival_meeting")
	check(meeting.contains("칩으로 살 수 있는 건 천막뿐이네요. 와서 앉아 줄 사람은 어떻게 모으죠?"), "S8 Miri")
	check(meeting.contains("초대장을 보내요. 포커를 몰라도, 할 일이 없더라도 와도 된다고요."), "S8 Nora")
	check_eq(_choice_texts("scn.festival_meeting").size(), 4, "S8 four suits")
	var open := DialogueResolver.find(db.dialogue, "scn.fourleaf_evening")
	check(_lines("scn.fourleaf_evening").contains("참가하지 않아도 괜찮아요"), "S9 no pressure to play")
	var endings := 0
	for c in open["choices"]:
		var c_text := JSON.stringify(c)
		if c.get("action", "") == "dialogue":
			# Each activity plays its own short scene, then reaches the same ending.
			var branch := DialogueResolver.find(db.dialogue, str(c["arg"]))
			var next: Array = branch.get("choices", []).map(func(b): return str(b.get("arg", "")))
			check(str(c["arg"]) == "scn.festival_end" or next.has("scn.festival_end"), "S9 %s reaches the shared ending" % c["text"])
			endings += 1
		if c.get("action", "") == "start_poker":
			check(c_text.contains("story.act3_complete"), "S9 entering the tournament ends act 3 without needing a win")
	check_eq(endings, 3, "S9 watch, help and greet all end the festival")
	check(JSON.stringify(DialogueResolver.find(db.dialogue, "scn.festival_end")).contains("story.act3_complete"), "S9 shared ending flag")
	var cond: Dictionary = DialogueResolver.find(db.dialogue, "scn.festival_meeting")["conditions"]
	check_eq(int(cond.get("contributions_min", 0)), 3, "three different contributions")


func test_postgame_is_about_who_comes_back() -> void:
	check(_lines("scn.postgame_lumi").contains("누가 이겼는지는 잘 모르겠어. 다들 다시 오겠다고 했거든."), "S10 Lumi")
	check(_lines("scn.postgame_kyle").contains("규칙판 옆에 빈 자리를 남겨 두었습니다. 다음 사람을 위해서요."), "S10 Kyle")
	var cond: Dictionary = DialogueResolver.find(db.dialogue, "scn.postgame_lumi")["conditions"]
	check(cond["flags_true"].has("story.act3_complete") and cond.get("time", "") == "day", "S10 the morning after")
	check(not JSON.stringify(cond).contains("poker") and not JSON.stringify(cond).contains("tournament"), "S10 the same morning for every player")
	for id in ["lumi_festival", "kyle_festival"]:
		check(not _lines(id).contains("누가 이겼는지는 잘 모르겠어") and not _lines(id).contains("빈 자리를 남겨"), id + " does not repeat the postgame line")
