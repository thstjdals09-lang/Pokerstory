# Project 20 / Pokerstory — Content Complete Design Pack v0.3

```yaml
pack: P20-CONTENT-0.3
scope: stage_1_to_6_world_village_residents_life_poker_integration
status: DESIGN_SPEC_READY / NOT_IMPLEMENTED
engine_baseline: Godot 4.7.2 + GDScript
platform: Windows local single-player; no network
art_policy: keep graybox; finish gameplay/content before visual production
source_repo: thstjdals09-lang/Pokerstory
```

## 읽기 순서와 효력
1. `00_governance/01_DECISIONS_AND_PRECEDENCE.md` → `02_CONTENT_COMPLETE_DEFINITION.md`.
2. 세계관 01, 맵 02, 주민 03, 생활 04, 포커 05, 통합 06을 순서대로 읽는다.
3. 개발 담당자는 `07_development/` 지시서의 독립 작업 단위로 구현한다. **이 문서의 작성은 코드 구현·테스트 완료를 뜻하지 않는다.**

### 원칙
- 사용자가 확정한 10문답: 포커 문화를 가진 아기자기한 판타지 마을, 주민과 공동체, 싱글플레이, 관계·연애·라이벌·마을 발전·하우징·수집, 빠른 판타지 포커, 플레이어 주도 시간, 마을 중심 일상.
- 플레이어에게 포커를 강요하지 않으며 승부에서 질 경우 칩을 잃는다. 칩이 0이어도 생활 활동으로 다시 얻는다.
- 이 팩의 구체적인 이름, 수량, 지명, 서사는 **기획 담당이 제안한 콘텐츠 구현 기준 v0.3**이다. 사용자 확정 사항과 충돌하면 사용자 확정 사항을 우선한다.
- 게임이 콘텐츠 완성되기 전에는 고품질 비주얼·별도 exe·Steam/모바일·온라인 기능을 의뢰하지 않는다. 임시 도형 그래픽으로 콘텐츠 기능을 검증한다.

### 문서 사용법
- `id`는 영속 식별자. 화면 표시명은 추후 변경해도 id는 함부로 바꾸지 않는다.
- 숫자는 `00_governance/03_BALANCE_AND_FLAGS.md`에서 용도/가변 여부를 확인한다. 경제 v0.2.2의 시작40/판돈20/등불50/의뢰30/아르바이트10은 호환 기준값이다.
- 모든 이벤트/수치/대사/아이템/주민은 데이터로 관리하고 무결성 검사한다. 미완성 에셋은 임시 표시로 계속 플레이 가능하게 한다.
- 이 팩은 1~6단계의 **기획 산출물**이다. 실제 구현은 개발 AI가 명세에 따라 수행하고 증거·테스트를 제출해야 완료다.
