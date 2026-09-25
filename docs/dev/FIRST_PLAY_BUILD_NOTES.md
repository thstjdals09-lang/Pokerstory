# First Play Prototype — 개발 노트

| 항목 | 내용 |
|---|---|
| 기준 | [First Play Spec v0.2](../design/Project20_First_Play_Spec_v0.2.md) + [Design Correction 02](../design/Project20_Design_Correction_02.md) + [Economy v0.2.1](../design/Project20_Economy_v0.2.1.md) + [Design Review 03 / Economy v0.2.2](../design/Project20_Design_Review_03.md) |
| 엔진 | Godot 4.7.2 stable (GDScript만 사용, 렌더러 GL Compatibility) |
| 대상 | Windows PC, 키보드 + 마우스 |
| 작성 | Claude (개발 담당), 최종 갱신 2026-09-25 |
| 상태 | Design Review 03 반영 완료, 자동 검증 통과. Gate 2(플레이어 시각 검수) 대기 |

---

## 1. 실행 방법

1. [Godot 4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)의 `Godot_v4.7.2-stable_win64.exe.zip`을 받습니다.
2. 다음 중 하나로 실행합니다.
   - 저장소 루트의 `run_game.bat`. 기본 경로는 `%USERPROFILE%\tools\godot\`이고, 다르면 `GODOT` 환경 변수에 exe 경로를 지정합니다.
   - 명령줄: `Godot_v4.7.2-stable_win64.exe --path game`
   - 에디터: `game/project.godot`를 열고 F5

| 입력 | 동작 |
|---|---|
| WASD / 방향키 | 이동 |
| E / Enter | 대화, 출입, 줍기, 대화 넘기기. 화면 아래 프롬프트 버튼과 같음 |
| Esc | 메뉴 / 뒤로 / 창 닫기 |
| Tab | 현재 목표 접기·펼치기 |
| 마우스 | 카드 선택, 버튼, 집 꾸미기 자리 선택 |
| 1~5 | 포커 카드 선택, 대화 선택지 |

---

## 2. 플레이 흐름 (현재 빌드)

```
새 게임 (칩 40, 낮)
 ├ 광장: 루미(낮), 아르바이트 게시판 → 카드·칩 3개 줍기 → +10 (반복 가능)
 ├ 잡화점: 세라 → 꾸러미 배달 의뢰 수락 / 작은 등불 50칩
 ├ 카드룸 문(낮) → "저녁까지 기다리기" → 저녁
 │   카드룸(저녁): 루미, 모아, 포커 테이블
 │   포커: 참가금 20 → 승 +40 / 무 +20 / 패 0 반환. 20칩 미만이면 참가 불가
 │   루미에게 꾸러미 전달 → +30 (1회, 첫 만남 대화에서도 바로 가능)
 │   판 도중 강제 종료 → 재실행 시 같은 판을 이어서 (환불 없음)
 ├ 저녁은 장소를 옮겨도 유지. 저녁 광장에는 루미가 없음
 └ 집: 보관함 → 등불 배치 / 침대 → 저녁까지 쉬기·아침까지 자기
     → 낮에 광장의 루미가 등불 이야기를 함
```

---

## 3. 구조

```
game/
├─ data/                    게임 데이터 — 콘텐츠·수치 변경 시 코드 수정 불필요
│  ├─ locations.json        4개 공간, 주민 배치(시간대별 time), 문(requires_time), 침대, 게시판
│  ├─ npcs.json / items.json / shops.json
│  ├─ dialogue.json         조건부 대화. 선택지에도 조건 가능
│  ├─ poker.json            룰, 경제(Economy v0.2.2), 능력, 대사
│  ├─ quests.json           일회성 의뢰
│  ├─ jobs.json             반복 아르바이트 (보상, 개수, 후보 지점)
│  └─ goals.json            HUD 현재 목표
├─ scripts/core/            노드에 의존하지 않는 규칙 (단위 테스트 대상)
│  ├─ card, deck, hand_evaluator, poker_ai
│  ├─ poker_match           한 판 진행 + 저장·복원(to_dict / from_dict)
│  ├─ poker_economy         참가금 차감, 정산, 포기
│  ├─ quest_book            의뢰 상태, 1회 보상
│  ├─ plaza_job             아르바이트 1회분 (지점별 1회, 완료 시 1회 지급)
│  ├─ game_state            저장 대상 상태 (v3), 칩 원장, 진행 중인 판
│  ├─ save_system           JSON 단일 슬롯, 버전, v1 → v2 → v3 변환, 복원 불가 판 거부
│  └─ conditions, dialogue_resolver, data_db, geo
├─ scripts/autoload/game.gd 세션: 데이터, 상태, 저장, UI가 호출하는 동작
├─ scripts/world/           공간, 충돌, 플레이어, 주민(시간대별), 줍기 지점
├─ scripts/ui/              타이틀, HUD, 튜토리얼, 대화, 포커, 상점, 집 꾸미기, 메뉴·도감
├─ scripts/main.gd          화면 흐름, 입력 모드, 시간 전환
└─ tests/                   unit/ 단위 테스트, e2e/ 자동 플레이 드라이버
```

---

## 4. 검증 결과

### 4.1 실행

```bash
tools/run_tests.sh          # unit + e2e 전체 (Git Bash). GODOT 환경 변수로 경로 지정
tools/run_tests.sh unit
tools/run_tests.sh e2e
```

### 4.2 결과 (2026-09-25, Windows 10, Godot 4.7.2)

| 묶음 | 결과 |
|---|---|
| 단위 테스트 | **59개 통과** / 0개 실패 |
| E2E `path_a` 포커 승리 → 등불 → 배치 → 반응 | 69개 검증 통과 |
| E2E `path_b` 포커 패배 → 의뢰 → 등불 → 배치 → 반응 | 68개 검증 통과 |
| E2E `path_c` 포커 없이 아르바이트 → 등불 → 배치 → 반응 | 47개 검증 통과 |
| E2E `path_d1` → `path_d2` 판 도중 강제 종료 → 재실행 → 같은 판 이어서 정산 (프로세스 2개) | 16 / 28개 검증 통과 |
| E2E `broke` 포기 → 파산 → 참가 제한 → 아르바이트 → 무승부 → 승리 | 89개 검증 통과 |
| E2E `migrate` v1 저장 파일(잔액 유지), v2 저장 파일(참가금만 차감된 판) | 11~12개 검증 통과 (v2 경우는 무작위 판이라 원장 검사 수가 결과에 따라 다름) |
| E2E `reject` 읽을 수 없는 저장 파일 | 7개 검증 통과 |
| 창 모드 E2E `path_a`·`path_b`·`path_c`·`path_d1/d2` + 스크린샷 | 모두 통과 |

로그의 `ERROR: Parse JSON failed`는 손상된 저장 파일을 일부러 읽히는 테스트의 정상 출력입니다.

### 4.3 E2E의 한계

- 이동은 실제 입력으로 확인하지만, **대상까지 걸어가는 경로는 생략**하고 플레이어를 대상 옆으로 옮깁니다. 이후 상호작용은 실제 E 입력과 월드의 근접 판정을 그대로 거칩니다.
- 버튼과 카드는 마우스 클릭이 발생시키는 것과 같은 `pressed` 신호로 누릅니다.
- 포커 결과는 테스트 전용 스택 덱으로 정합니다. 실제 플레이는 무작위 시드 덱을 씁니다(콘솔에 `[poker] deck seed N` 출력).

---

## 5. 저장 형식 (save_version 3)

저장 위치: `user://save_slot_1.json` (Windows: `%APPDATA%\Godot\app_userdata\Pokerstory\`)

| 키 | 내용 |
|---|---|
| `save_version` | 3. v1·v2는 자동 변환(잔액 유지). 더 새 버전, 손상된 파일, 복원할 수 없는 진행 중 판은 거부하고 파일을 건드리지 않음 |
| `chips_balance`, `chips_ledger[]` | 잔액(음수 불가)과 원장 `{seq, delta, reason, balance}` |
| `pending_poker_stake` | 정산 전 참가금. 판 진행 중에만 0이 아님 |
| `poker_in_progress` | 진행 중인 판: 양쪽 손패, 남은 덱 순서, 시드, 교체 한도, 단계, 능력 사용·결과. 재실행 시 그대로 이어서 진행 |
| `time_of_day` | `day` / `evening` |
| `quests` | `{quest_id: "active" \| "completed"}` |
| `jobs_completed` | 완료한 아르바이트 횟수 (진행 중인 아르바이트는 저장하지 않음) |
| `flags` | `intro_met_lumi`, `lumi_lamp_reaction_seen`, `sera_met` 등 |
| `poker_hands_completed`, `poker_record` | 판 수, 승/무/패/포기 |
| `owned_items`, `home_placements[]`, `collection[]` | 보관함, 배치, 도감 |
| `current_scene`, `player_position` | 이어하기 위치 |

**저장 시점:** 새 게임, 장소 이동, 대화 플래그, 시간 변경, 판 시작(참가금 + 카드), 능력 사용, 정산·포기, 의뢰 수락·완료, 아르바이트 완료, 구매, 배치, 메뉴 저장, 타이틀 이동, 종료(창 닫기 포함, 판은 포기하지 않고 저장).

---

## 6. 명세와의 차이

v0.2 첫 빌드의 불일치 4건은 [Design Correction 02](../design/Project20_Design_Correction_02.md)에서 수정했습니다. D1~D7에 대한 기획 결정과 Economy v0.2.2는 [Design Review 03](../design/Project20_Design_Review_03.md)에 반영했습니다. 기획 확인이 필요한 2건(R1 창 닫기 처리, R2 이전 빌드 저장 파일 처리)은 같은 문서 4절에 있습니다.

남아 있는 v0.2 해석 사항:

| 항목 | 구현 |
|---|---|
| 도감 기록 시점 | 구매(획득) 시점 |
| `owned_items` 형식 | `{id: 수량}` |
| 가구 | 작은 등불 1종 |
| 한글 폰트 | 시스템 폰트(맑은 고딕 등) 참조. 배포 전에는 라이선스가 확인된 폰트를 포함해야 함 |
| 실행 파일(.exe) | 만들지 않음 (이번 지시에서도 제외) |

---

## 7. 알려진 문제와 확인하지 못한 항목

- 사람이 직접 끝까지 플레이한 확인은 없습니다. 조작감, 아르바이트의 지루함 여부, 포커 경제 체감은 Gate 2에서 판단해야 합니다.
- 경제 밸런스(Economy v0.2.2)는 승인 수치대로 구현했고, 체감 검증은 하지 않았습니다.
- 저녁 조명은 전체 색조만 바꾸는 단순 처리입니다.
- 해상도는 1280×720 기준이고, 다른 비율에서의 UI는 확인하지 않았습니다. 사운드와 애니메이션은 없습니다.
- 이전 보고의 창 모드 간헐 입력 실패는 사용자 창 크기 조작 때문으로 확인되어 조사 대상에서 제외했습니다(수정 지시 02).

---

## 8. 수동 확인 체크리스트 (Gate 2용)

1. 새 게임 → HUD 칩 40, 낮
2. 광장의 루미와 인사 → 아르바이트 게시판 → 카드·칩 3개를 걸어 다니며 줍기 → +10
3. 세라의 잡화점 → 의뢰 수락 → HUD에 "의뢰 중 · 세라의 꾸러미 배달"이 보이는지
4. 카드룸 문(낮) → "그만두기"면 그대로 낮, "저녁까지 기다리기"면 저녁 카드룸에 루미와 모아
5. 루미에게 꾸러미 전달 → +30. 처음 만난 대화에서도 바로 전달되는지, 다시 말 걸면 선택지가 없는지
6. 포커: 참가 시 -20, 결과별 +40 / +20 / 0. 도중에 일어나면 경고 후 참가금 손실
6-1. 포커 중 게임 창을 강제로 닫고 다시 실행 → 같은 카드로 이어지는지, 참가금이 다시 빠지지 않는지
7. 마을로 나가면 저녁 유지, 광장에 루미가 없는지
8. 등불 구매·배치 → 침대에서 아침까지 자기 → 광장 루미가 등불 이야기
9. 칩을 모두 잃은 뒤 포커 참가가 막히고, 아르바이트 2회로 다시 참가할 수 있는지
10. Esc → 저장하고 종료 → 이어하기로 시간대, 칩, 의뢰 상태가 유지되는지

스크린샷: [docs/screenshots/](../screenshots/)
