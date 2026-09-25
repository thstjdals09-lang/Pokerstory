# 아이템·수집 6범주 / 공용 스키마

```json
{"id":"item.furniture.small_lamp","category":"furniture","display_name":"작은 등불","price_chips":50,"stackable":false,"placement":{"room_types":["home"],"footprint":[1,1]},"unlock_condition":"start","source_tags":["small_shop"],"discover_on":"acquire"}
```

## 수집 범주
1. `furniture` 가구: 집/커뮤니티 전시에 실제 배치.
2. `decor` 소품: 벽·바닥·탁상에 두는 카드/문양/책.
3. `clothing` 의상/액세서리: 초기에는 캐릭터 실루엣/장식 태그만 바꿔도 획득·착용·저장 가능. 최종 그림은 7단계.
4. `card_back` 덱 뒷면: 카드족보·확률·덱 내부 ID를 변경하지 않는 외형 옵션.
5. `chip_style` 칩 테두리/케이스: 표시만 변하고 **칩 잔액·정산에 영향 없음**.
6. `memento` 주민 추억·행사 물건: 퀘스트/관계/스토리 1회 획득, 전시 가능.

## 상태 구분
`discovered`(한 번 획득했음), `owned_count`(현재 보유), `placed_count`(배치 수), `equipped`(착용 여부)는 독립. 판매·배치·보관해도 도감 발견 기록은 사라지지 않는다. 수집품을 공개 저장소에 넣을 때 타인의 상용 에셋 무단 포함 금지.

## 기존 item 호환
기존 등불의 실제 id/가격/배치 상태를 먼저 확인하여 새로운 id가 중복 아이템으로 만들어지지 않도록 `legacy_id_map`을 설계. 이미 구매한 등불을 강제로 재구매시키지 않는다.
