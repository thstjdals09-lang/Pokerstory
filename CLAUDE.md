# Pokerstory (Project 20) — AI 작업 규칙

## 역할과 문서
- 기획: 티티(ChatGPT). 개발: Claude. 최종 승인: 프로젝트 오너.
- Source of Truth: `docs/Project20_Design_Brief_v0.1.md`, `docs/design/`의 명세. **기존 문서는 수정하지 않는다.** 새 판은 새 파일로 추가한다.
- 명세에 없는 규칙은 확정하지 않는다. 빈 곳은 임시값으로 두고 보고서에 적는다.
- 현재 단계와 승인 범위는 README와 가장 최근 작업 지시를 따른다. 다음 단계는 별도 지시가 있을 때만 시작한다.

## 엔진
- **Godot 4.7.2 stable, GDScript만 사용.** 다른 버전의 API(특히 Godot 3 문법)를 섞지 않는다.
- 로컬 실행 파일: `C:/Users/a/tools/godot/Godot_v4.7.2-stable_win64_console.exe`
- 렌더러는 GL Compatibility. 기준 해상도는 1280×720.

## 코드 규칙
- 게임 규칙 로직은 `game/scripts/core/`에 노드 의존 없이 작성하고 단위 테스트를 붙인다.
- 콘텐츠(대사, 수치, 아이템, 장소)는 `game/data/*.json`에 둔다. 콘텐츠를 추가하려고 코드를 고치지 않는다.
- UI는 GameState를 직접 수정하지 않고 `Game` autoload의 동작을 호출한다.
- 저장 형식을 바꾸면 `GameState.SAVE_VERSION`을 올리고 `SaveSystem._migrate`에 변환을 추가한다.
- `:=`는 타입이 확정되는 식에만 쓴다. Variant 값(딕셔너리 조회 등)에는 명시 타입을 붙인다.

## 테스트
- `tools/run_tests.sh` (unit + e2e). 커밋 전에 전부 통과해야 한다.
- 새 규칙에는 단위 테스트를, 새 플레이 흐름에는 `tests/e2e/first_play_e2e.gd` 검증을 추가한다.
- 화면 확인: `Godot... --path game -- --e2e=win --save-path=user://e2e_shots.json --shots=<절대경로>`로 스크린샷을 찍어 직접 본다.
- 실행하거나 테스트하지 않은 기능을 완료로 보고하지 않는다.

## Git
- 작업이 끝나면 자동으로 커밋·push한다 (저장소 공개: github.com/thstjdals09-lang/Pokerstory).
- 유료·재배포 금지 에셋은 이 공개 저장소에 올리지 않는다.
