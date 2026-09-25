# 전역 설정·밸런스·플래그 계약

## 변경하면 기존 첫 플레이를 반드시 재검증할 값
```yaml
starting_chips: 40
poker_stake_default: 20
poker_payout: {win: 40, draw: 20, lose: 0}
first_poker_bonus: 0
starter_lamp_price: 50
starter_delivery_reward: 30
plaza_cleanup_reward: 10
plaza_cleanup_targets: 3
time_segments: [day, evening]
```
신규 콘텐츠의 추가 가구/사업 비용은 `04_life/`에서 정의한다. 포커 참가 전 칩 잔액 확인; 부족하면 생활 활동 안내; 포커 패배 시 보상 0; 칩 잔액 음수 불가; 생활 활동은 0칩에서도 가능한 것 최소 1개 이상.

## 대표 플래그 네이밍
- `story.act1_started`, `story.act1_complete`, `story.act2_complete`, `story.act3_complete`.
- `relationship.<npc_id>.friendship` (0~100), `rivalry` (0~100), `romance_route` (`closed|eligible|dating|committed`), `romance_consent` boolean. 호감·경쟁을 합산하지 않는다.
- `npc_pair.<pair_id>.phase` (`neutral|bonded|strained|reconciled`); 모든 쌍 생성 금지, 등록된 관계 간선만 관리.
- `project.<project_id>.state` (`locked|available|funded|complete`), `item.<item_id>.discovered`, `owned_count`, `placed_count`.
- `poker.session_id`, `poker.phase`, `poker.stake_committed`, `poker.settlement_id`, `poker.ability_used_ids`.

## 범위·검증 규칙
관계값 0~100, 칩 정수≥0, 아이템 보유/배치 수량≥0, 이벤트 지급 idempotency key 필수. 임의로 레벨 상한·일일 접속·대회 날짜 타이머를 넣지 않는다. 신규 보상 수치는 초기 가설이며 테스트 후 데이터 변경은 가능하되 기존 승인값은 별도 승인 없이 바꾸지 않는다.
