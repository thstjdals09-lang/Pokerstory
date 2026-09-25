# 맵·상호작용·장소 상태 규약

## 핵심 사용 흐름
화면의 `E` 프롬프트 → 상호작용 메뉴(사용/대화/가져오기/나가기) → 시스템 요청 → 성공 시 월드 피드백. 물건 자동 습득/이벤트 자동 완료 최소화. 같은 키가 포커 입력과 지도 이동에 동시에 전달되지 않게 입력 모드를 분리.

## 오브젝트 타입
| 타입 | 예시 | 필요한 데이터 | 실패 시 |
|---|---|---|---|
| portal | 잡화점 문 | target_scene, spawn_anchor, time_policy | 막힌 이유 안내/현 위치 유지 |
| board | 공용 게시판 | available_quest_ids, job_ids, event_ids | 빈 목록에도 안내 |
| pickup | 바닥 카드 | collectible_id, location, once/repeat key | 중복 지급 금지 |
| shop | 세라 카운터 | stock_by_unlock, purchase_action | 칩 부족/보관함 가득 안내 |
| guest | NPC | current_place, interaction_priority | 첫인사와 의뢰 전달 동시 메뉴 가능 |
| furnishing | 침대/등불 | room_slot, interact_action, ownership | 슬롯 중복 거부 |

## 비주얼 제작 전 반드시 고정할 기술 경계
- 이동 기준 좌표와 상호작용 반경은 기존 프로토타입과 최대한 호환. 스프라이트 크기는 변경 가능하되 충돌 캡슐/문 anchor의 값은 데이터화.
- 지구 전환 스폰 지점을 자동 테스트하고, UI 앵커/세이브 공간 ID를 시각 에셋과 독립.
- 편집 중 지도/방 가구 배치를 마치지 않고 종료해도 확정 전의 임시 상태가 저장되지 않도록 한다.
