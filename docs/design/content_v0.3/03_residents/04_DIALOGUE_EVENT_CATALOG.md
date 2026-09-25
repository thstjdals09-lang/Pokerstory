# 대사·주민 사건 제작 계약

## 실제 화면 대사 형식
```json
{"event_id":"npc_lumi.bond_01","speaker_id":"npc_lumi","text_key":"dlg.lumi.bond01.01","mood":"thoughtful","conditions":{"all":["npc_lumi.met","friendship.npc_lumi>=10"]},"choices":[{"text_key":"dlg.choice.listen","action":"advance"},{"text_key":"dlg.choice.later","action":"close"}],"once":true}
```
- 메타 태그 `mood`, `speaker_id`, `scene_id`, `seen_once`, `cooldown_event_id`를 저장. 보여줄 때마다 호감도 지급 금지.
- 대화 우선순위: 중단된 핵심 인터랙션 → 현재 진행 중 의뢰의 전달 선택지 → 처음 인사 → 개인 사건 → 행사 반응 → 일상 대사. **우선순위가 낮은 전달 선택지를 첫인사 메뉴에서도 접근 가능**하게 합성한다.
- 자동 생성 대사는 주민별 말투 가이드를 통과해야 하며 사용자 확정 속성과 충돌하면 안 된다.

## 필수 사건 묶음 (최소)
16명 × 2건 = 개인 사건 32개(`<npc_id>.bond_01/.bond_02`); 첫인사 16, 반복 대사 32, 개인 기억 반응 16, 마을 변화 반응 16, 1~3막 공용 장면 12, 연애 대상 4 × 3단계 = 12장면, 라이벌 사건 4. **실제 화면에 연결된 대사 키**가 없는 플레이스홀더는 완료 아님.

## 공용 장면 예시 12개
`scn.arrival`, `scn.lantern_response`, `scn.missing_invitation`, `scn.postbox_discovery`, `scn.board_reopening`, `scn.two_tables_argument`, `scn.private_homegame_invite`, `scn.open_tournament_rules`, `scn.grove_lantern_vote`, `scn.festival_preparation`, `scn.fourleaf_evening`, `scn.postgame_morning`.

## 실패/우회
대화 건너뛰기, 다른 순서로 NPC 첫인사, 의뢰 아이템 미소지, 포커 0판, 칩 0, 데이트 거절, 이벤트 이미 관람한 세이브 모두 재현 테스트. 첫인사 중 의뢰 전달을 막지 않는다.
