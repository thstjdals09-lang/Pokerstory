# 생활 의뢰 16개 / 각자 고유 이벤트 ID

**필수**: 목록에서 첫 번째 `quest.sera_delivery`만 기존 구현과 동일한 보상(30칩)을 보존한다. 신규 의뢰 보상은 테스트용 가설이다. 포커 승리를 조건으로 한 의뢰는 없다. 모든 의뢰는 한 번 완료하면 재지급하지 않는다.

| quest_id | 표시명 | 의뢰자 | 전달/상대 | 해금 | 칩 | 서사/상호작용 |
|---|---|---|---|---|---:|---|
| `quest.sera_delivery` | 세라의 꾸러미 배달 | npc_sera | npc_lumi | `start` | 30 | 기존 구현. 첫만남 중 전달 메뉴 허용 |
| `quest.nora_postcard` | 비뚤어진 초대장 | npc_nora | npc_moa | `story.act1_started` | 15 | 1막 단서 1, 우편함에 사본 보관 |
| `quest.rira_tea` | 모임의 빈 찻잔 | npc_rira | npc_taeo | `start` | 15 | 리라가 친목 선호 모임의 사정을 들려줌 |
| `quest.taeo_cushion` | 오래된 쿠션 | npc_taeo | npc_bibi | `start` | 20 | 집 꾸미기 공방/수선 안내 |
| `quest.bibi_parts` | 남겨 둔 부품 | npc_bibi | npc_sera | `project.board_restoration.complete` | 20 | 마을 사업 진행 대사 |
| `quest.ella_symbols` | 네 문양의 기록 | npc_ella | npc_nora | `story.act1_started` | 20 | 1막 단서 2, 문양의 다양성 |
| `quest.haru_path` | 저녁길 표지 | npc_haru | npc_ona | `start` | 15 | 숲길 안전 동선 |
| `quest.ona_glow` | 빛의 세기 | npc_ona | npc_haru | `start` | 15 | 밤길 등불 사업 계기 |
| `quest.kyle_rules` | 쉽게 쓰는 규칙 | npc_kyle | npc_moa | `story.act1_complete` | 20 | 친목과 경기 차이 설명 |
| `quest.juno_poster` | 행사 안내문 | npc_juno | npc_miri | `story.act2_started` | 20 | 2막 행사 기여 |
| `quest.miri_budget` | 읽기 쉬운 예산표 | npc_miri | npc_rira | `story.act2_started` | 20 | 대회와 친목 공존 기획 |
| `quest.ren_cardcase` | 한 장의 출처 | npc_ren | npc_kyle | `start` | 15 | 수집 교환 정보 |
| `quest.yul_bench` | 다 함께 앉는 자리 | npc_yul | npc_bibi | `story.act1_complete` | 20 | 공공사업 안내 |
| `quest.sia_welcome` | 새 손님의 첫 모임 | npc_sia | npc_lumi | `project.guest_cottage.complete` | 20 | 외부 방문은 NPC, 온라인 아님 |
| `quest.festival_letters` | 축제 초대 답장 | npc_nora | npc_juno | `story.act3_started` | 25 | 3막 기여 1회 |
| `quest.festival_lights` | 네잎 불빛 점검 | npc_sera | npc_ona | `story.act3_started` | 25 | 3막 기여 1회 |

## 의뢰 공통 계약
`locked → available → active → completed`. 의뢰 수락·진행·완료·보상은 저장. 수령자가 저녁 다른 곳에 있으면 HUD에 새 위치 갱신, 전달은 첫인사 대화와 같은 메뉴에서 가능. 다른 의뢰를 시작하거나 포커를 치더라도 진행 상태 유지. 보상 중복 방지: `quest:<quest_id>:complete` 단일 트랜잭션. 마을·스토리 1~3막 중 필요한 ‘기여’는 해당 의뢰의 첫 완료만 계산.
