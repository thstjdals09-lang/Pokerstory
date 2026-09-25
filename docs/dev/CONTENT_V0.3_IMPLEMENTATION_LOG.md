# Content Pack v0.3 구현 기록 (Stage 0~6)

| 항목 | 내용 |
|---|---|
| 기획 팩 | [docs/design/content_v0.3/](../design/content_v0.3/) (P20-CONTENT-0.3) |
| 브랜치 | `feature/content-v0.3` |
| 기준 커밋 | `67ea5c8` (main) |
| 작성 | Claude (개발 담당) |

---

## Stage 0 — 기준선

| 항목 | 기준값 |
|---|---|
| 엔진 | Godot 4.7.2, GDScript |
| save_version | 3 (v1·v2 변환 지원, 진행 중 포커 판 저장) |
| 장소(scene) ID | `village_square`, `player_home`, `card_room`, `small_shop` |
| 주민 ID | `npc_lumi`, `npc_moa`, `npc_sera` |
| 아이템 ID | `furniture.lamp_small` (50칩) |
| 능력 ID | `ability.star_sense` |
| 의뢰 / 아르바이트 | `quest.sera_delivery` (30) / `job.plaza_cleanup` (10, 3개 줍기) |
| 경제 | v0.2.2: 시작 40, 참가 20, 승 +20 / 무 0 / 패 -20, 패배·첫 참가 보상 없음 |
| 기준 테스트 | 단위 60개, E2E 8개 시나리오 (첫 플레이 경로 A~D, 파산, 변환, 거부) 모두 통과 |

## 호환·우선순위 결정 (00_governance/01 규칙에 따른 기록)

팩의 제안이 기존 구현·승인과 충돌하거나 해석이 필요한 부분입니다. 기존 결정을 우선하고, 팩의 신규 내용은 기존 동작을 깨지 않는 범위에서 적용합니다.

| # | 팩 내용 | 구현 결정 | 이유 |
|---|---|---|---|
| C1 | 플레이어 집은 주거 골목, 잡화점은 장터 지구 소속 | 집·잡화점·카드룸의 **문은 기존대로 광장에** 둡니다. 장소 레지스트리에는 팩의 지구 소속을 그대로 기록합니다. | 팩의 "기존 scene ID를 깨지 않는다" 규칙과 기존 세이브의 위치·스폰 호환을 위해서입니다. |
| C2 | 별빛 감각 ID `ability.starlight_sense` | 기존 ID `ability.star_sense`를 유지하고, 팩 ID를 별칭으로 매핑합니다. | 팩 02_ABILITIES_8의 "기존 ID가 다르면 보존" 규칙 |
| C3 | 등불 ID `item.furniture.small_lamp` | 기존 ID `furniture.lamp_small` 유지, `legacy_id_map`으로 매핑 | 팩 05_ITEM_AND_COLLECTION_SCHEMA의 규칙 |
| C4 | 모아의 낮 위치: 광장 게시판 뒤 (D7은 "프로토타입에서만 저녁 카드룸") | 팩대로 낮에는 광장 게시판 옆에 배치 | D7이 "향후 주민 생활 확장 때 낮 위치를 별도로 설계"한다고 했고, 팩 03_residents/01이 그 설계입니다. |
| C5 | 주민 대사 `text_key` 형식 | 대사 문장을 데이터에 직접 넣고, 항목별 고유 ID를 둡니다. | 기존 대사 데이터 구조와의 호환. 현지화 키는 추후 ID로 추출할 수 있습니다. |
