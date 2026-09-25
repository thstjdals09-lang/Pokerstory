# 세이브·호환·중단 복원 정책

현재 구현 저장 형식 v3의 기존 필드를 변경 없이 읽고, 신규 기능은 새 데이터 섹션과 기본값으로 추가한다. **실제 save_version 숫자와 마이그레이션 단계는 개발자가 저장소에서 확인한 뒤 결정**한다. 문서의 샘플에 따라 임의로 기존 값을 덮어쓰지 않는다.

## 섹션 예시
```json
{"save_version":"CURRENT_PLUS_ONE","game":{"time_of_day":"day","current_place_id":"village_square"},"economy":{"chips_balance":40,"chips_ledger":[]},"poker":{"pending_hand":null},"story":{"flags":{},"contributions":[]},"relations":{"by_npc":{},"npc_edges":{}},"housing":{"rooms":[],"placed_instances":[]},"quests":{"by_id":{}},"projects":{"by_id":{}},"inventory":{"items":{}}}
```

## 반드시 지키기
- 기존 저장 잔액/첫 구매/루미 인사/등불 배치/의뢰 완료/시간대/진행 중 손패를 보존한다. 신규 주민의 초기 관계만 기본값 부여.
- v3 손패는 손패·루미 패·덱 순서·능력 사용·판돈을 그대로 복원. 더 새 버전/깨진 저장 파일은 파일을 덮어쓰거나 칩을 임의 지급하지 않는다.
- 기존 v2 ‘참가금만 차감’ 데이터의 새 판 1회 예외는 v2 → 현행에서만, 변환 완료 후 같은 파일로 재추첨 불가.
- 자동 저장/수동 저장 도중 오류가 나면 이전 정상 스냅샷을 보존. 가구/사업/아이템/칩의 중복 지급 여부 테스트.
- 이벤트 발생 기록에 `origin_version`, `occurrence_id`를 저장하여 같은 요청 재실행 시 중복 적용하지 않는다.
