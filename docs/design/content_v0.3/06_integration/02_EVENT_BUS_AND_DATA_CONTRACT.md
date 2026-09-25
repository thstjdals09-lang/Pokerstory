# 이벤트·데이터 계약 (구현자가 기존 Godot 구조에 매핑)

## 이벤트 레코드
```json
{"event_id":"evt.home.lamp_placed","source":"housing","actor_id":"player","target_id":"item.furniture.small_lamp","subject_place_id":"player_home","occurrence_id":"uuid-per-action","persistence":"on_save","payload":{"room_id":"starter_room"}}
```

| event | producer | consumer | idempotency |
|---|---|---|---|
| `npc.met` | Dialogue | Relationship, Story | npc_id당 1회 첫인사 |
| `quest.completed` | QuestBook | Economy, Story, Dialogue | quest_id당 1회 |
| `job.completed` | JobSystem | Economy, Dialogue | run_uuid당 1회 |
| `poker.hand_settled` | PokerEconomy | Rivalry, Collection, Story | settlement_id당 1회 |
| `item.purchased` | Shop | Inventory, Collection | purchase_uuid당 1회 |
| `housing.placed` | Housing | Dialogue, Resident Visit | placement_uuid당 1회(반응 flag 따로) |
| `project.completed` | TownProjects | WorldState, Schedule, Shop | project_id당 1회 |
| `story.chapter_completed` | Story | Schedule, Festival | chapter_id당 1회 |

## 구현 경계
- UI는 기존 `Game` facade를 통해 행동 요청, `GameState` 직접 변이 금지.
- 콘텐츠 JSON에 `id, unlock_condition, display_text_key, effects[]` 필드. 조건은 AND/OR/NOT, 관계 임계값, 이벤트 플래그, 재화 잔액, 장소/시간대 정도만 지원. JSON에 임의 스크립트 실행 금지.
- 상태 변경과 원장 기록은 저장 단위에서 원자적. 장애로 저장 실패하면 화면상 보상/배치도 이전으로 복구 또는 안전한 재시도.
- 충돌 리소스(동일 주민의 두 위치, 다른 레코드의 중복 ID, 미존재 대상)를 콘텐츠 검증기에서 출시 전 오류 처리.
