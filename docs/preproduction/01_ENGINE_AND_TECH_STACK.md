# 01. 엔진 및 기술 스택 검토

| 항목 | 내용 |
|---|---|
| 문서 상태 | 사전 제작 조사 자료 (결정 문서 아님) |
| 작성 | Claude (개발 담당) |
| 작성일 | 2026-09-25 |
| 기준 문서 | [Project20_Design_Brief_v0.1.md](../Project20_Design_Brief_v0.1.md) |
| 독자 | 티티(ChatGPT, 기획 담당), 프로젝트 오너 |

**표기 규칙**
- **[조사]**: 공개 자료나 엔진 사양으로 확인한 사실입니다. 버전과 가격은 작성일 기준입니다.
- **[권고]**: 개발 담당의 개인 의견입니다. 확정 사항이 아닙니다.
- **[미정]**: 기획서 4절에 따라 아직 결정되지 않은 사항입니다.

> 이 문서는 엔진을 확정하지 않습니다. 엔진 선택은 그래픽 방식(02 문서)과 플랫폼 우선순위(05 문서 A 항목)를 정한 뒤에 하는 것이 맞습니다.

---

## 1. 검토 조건

요청서에 적힌 조건을 기획서 확정 사항과 연결하면 다음과 같습니다.

| 조건 | 기획서 근거 | 엔진 선택에 주는 부담 |
|---|---|---|
| PC 개발 | 요청서 | 모든 후보가 지원 |
| 향후 Steam 출시 | 요청서 | Steamworks 연동(도전과제, 클라우드 세이브) 필요 |
| 모바일 확장 가능성 | 요청서 | 터치 입력, 해상도 대응, 성능, 스토어 빌드 파이프라인 |
| 2D·2.5D 제작 | 요청서, Q10(시점 미정) | 2D 도구와 3D 도구가 모두 쓸 만해야 함 |
| 마을·NPC | Q2, Q3 | 타일맵, 경로 탐색, Y정렬(깊이 정렬) |
| 대화·관계 | Q6 | 분기 대화 도구, 조건·플래그 시스템 |
| 캐주얼 포커 | Q5 | 카드 UI, 트윈 애니메이션, 게임 로직의 테스트 가능성 |
| 캐릭터 커스터마이징 | 요청서 (기획서 Q7에는 없음, 범위 [미정]) | 스프라이트 레이어 합성 또는 3D 메시·머티리얼 교체 |
| 하우징·가구 배치 | Q7 | 그리드 배치, 정렬, 직렬화 |
| 저장·불러오기 | 기획서 4절 [미정] | 직렬화 API, 세이브 버전 관리 |
| AI 활용 개발 | 요청서 | 프로젝트 파일이 텍스트인지, CLI 지원, 에디터 없이 작업 가능한지 |
| 1인 유지보수 | 요청서 | 엔진 업데이트 안정성, 빌드 복잡도, 라이선스 비용 |

---

## 2. 후보 엔진 개요 [조사]

| 항목 | Godot 4 | Unity 6 | GameMaker | Defold |
|---|---|---|---|---|
| 현재 버전 | 4.7.2 (2026-08-18) | Unity 6 계열 (6000.x) | 2024.x 계열 | 1.13.x |
| 라이선스 | MIT, 완전 무료, 로열티 없음 | Personal: 연 매출·투자 $200K 이하 무료. 초과 시 Pro (좌석당 연 약 $2,000대) | 비상업 무료. 상업 판매는 Professional $99.99 일회성 | 무료, 로열티 없음 (Defold Foundation) |
| 주 언어 | GDScript (Python과 비슷), C# 선택 가능 | C# | GML | Lua |
| 2D 도구 | 전용 2D 렌더러, TileMapLayer, 2D 내비게이션, Y-sort | 2D Tilemap, 2D Animation, Sprite Shape, URP 2D Lights | 2D 전용으로 매우 성숙 | 2D 중심, 가벼움 |
| 3D 도구 | 중간 수준 (4.x에서 크게 개선) | 매우 강함 | 사실상 없음 | 제한적 (최근 개선 중) |
| 프로젝트 파일 형식 | `.tscn`/`.tres` 텍스트 파일 | YAML 텍스트 (Force Text 설정 시), 대신 GUID 참조가 많음 | 텍스트 기반 (`.yy` JSON) | 텍스트 기반 |
| CLI 빌드·실행 | 지원 (헤드리스 실행, 내보내기) | 지원 (batchmode) | 제한적 | 지원 (bob.jar) |
| Steam 연동 | GodotSteam (GDExtension, Godot 4.4 이상, Steamworks SDK 1.65 기준) | Steamworks.NET 등 성숙한 선택지 | 공식 Steam 확장 | 공식 Steam 확장 |
| 모바일 | Android·iOS 내보내기 기본 지원 | 업계 표준 수준 | Android·iOS (Professional 라이선스에 포함) | 모바일에 가장 강함 (작은 용량) |
| 에셋 스토어 | Asset Library (규모 작음) | Asset Store (매우 큼) | Marketplace (중간) | 작음 |
| AI 에디터 연동 | 커뮤니티 MCP 여러 개 (Godot AI, Godot MCP Pro 등) | 공식 Unity MCP (`com.unity.ai.assistant` 패키지, Unity 6 이상) | 없음 (조사 범위 내) | 에디터 스크립팅 API 확장 중 |

### 검토했지만 제외한 엔진

| 엔진 | 제외 이유 |
|---|---|
| Unreal Engine 5 | 2D 지원(Paper2D)이 사실상 방치되어 있습니다. 블루프린트는 바이너리라 AI가 편집할 수 없습니다. 1인이 아기자기한 2D·2.5D 생활 게임을 만들기에는 과합니다. |
| RPG Maker MZ | RPG 구조는 빠르게 만들 수 있지만, 하우징·포커·자율 NPC처럼 고유 시스템이 많아 엔진 구조와 계속 부딪힙니다. |
| Bevy, MonoGame, raylib 같은 코드 전용 프레임워크 | 에디터, 타일맵, UI, 애니메이션 도구를 직접 만들어야 합니다. 이 프로젝트에서는 콘텐츠 제작 도구가 중요해서 비용 대비 효과가 낮습니다. |

---

## 3. 조건별 비교 [조사 + 개발 담당 평가]

평가 기준: ◎ 매우 적합, ○ 적합, △ 가능하지만 제약이 큼, ✕ 부적합.
평가는 이 프로젝트 조건에 대한 개발 담당의 판단이며, 엔진의 절대적 우열이 아닙니다.

| 조건 | Godot 4 | Unity 6 | GameMaker | Defold |
|---|---|---|---|---|
| PC 개발 | ◎ | ◎ | ◎ | ○ |
| Steam 출시 | ○ (GodotSteam, 커뮤니티 유지) | ◎ | ○ | ○ |
| 모바일 확장 | ○ | ◎ | ○ | ◎ |
| 2D 탑다운·아이소메트릭 | ◎ | ○ | ◎ | ○ |
| 2.5D (3D 공간 + 2D 캐릭터) | ○ | ◎ | ✕ | △ |
| 스타일라이즈드 3D | △~○ | ◎ | ✕ | △ |
| 마을·NPC 경로 탐색 | ○ (NavigationServer 2D·3D) | ◎ (NavMesh, 2D는 서드파티 필요) | △ (직접 구현 비중 큼) | △ |
| 대화·관계 도구 | ○ (Dialogue Manager, Dialogic, Yarn Spinner for Godot) | ◎ (Yarn Spinner, Ink, 유료 에셋 다수) | △ | △ |
| 캐주얼 포커 UI·연출 | ◎ (Control 노드 + Tween) | ◎ | ○ | ○ |
| 캐릭터 커스터마이징 | ○ | ◎ (특히 3D) | ○ (2D 레이어) | △ |
| 하우징·가구 배치 | ○ | ◎ | ○ (2D 한정) | △ |
| 저장·불러오기 | ○ (FileAccess, JSON, Resource) | ○ (JsonUtility, Newtonsoft 등) | ○ | ○ |
| AI 활용 편의성 | ◎ | ○ | △ | ○ |
| 1인 유지보수 | ◎ | ○ | ○ | ○ |

---

## 4. 엔진별 장단점과 제약

### 4.1 Godot 4

**장점 [조사]**
- 씬(`.tscn`)과 리소스(`.tres`)가 사람이 읽을 수 있는 텍스트입니다. AI가 에디터 없이도 씬 구성을 직접 읽고 고칠 수 있고, Git에서 변경 내용(diff)을 확인할 수 있습니다.
- 엔진 실행 파일이 하나(수십~100MB대)라 설치와 버전 고정이 쉽습니다. 저장소에 쓸 엔진 버전만 기록해 두면 재현이 됩니다.
- 전용 2D 렌더러가 있습니다. 2D 좌표계를 픽셀 단위로 다루므로 픽셀아트 처리가 깔끔합니다.
- 헤드리스 실행을 지원해서 테스트(GUT, gdUnit4)와 빌드 자동화가 가능합니다.
- MIT 라이선스라 매출과 무관하게 비용이 없고, 라이선스 정책이 바뀔 위험도 없습니다.

**단점과 제약 [조사]**
- **Steam 연동이 커뮤니티 플러그인(GodotSteam)에 의존합니다.** 활발히 유지되고 있지만 공식 지원은 아닙니다. Godot 버전이 바뀔 때 호환 버전이 나올 때까지 기다려야 할 수 있습니다.
- **iOS 내보내기는 macOS와 Xcode가 필수입니다.** 현재 개발 환경(Windows)에서는 불가능합니다.
- **C#을 쓰면 웹 내보내기가 안 되고, Android·iOS 지원은 실험 단계입니다** (공식 문서 기준, 4.2 이후 상태). GDScript를 쓰면 이 제약이 없습니다.
- 3D는 Unity보다 기능과 에셋 생태계가 약합니다. 스타일라이즈드 3D를 택하면 셰이더, 조명, 애니메이션 리타깃팅에 더 많은 수작업이 필요합니다.
- 에셋 스토어가 작습니다. 유료 에셋으로 시간을 사는 전략이 Unity만큼 통하지 않습니다.
- 콘솔 출시는 엔진이 직접 지원하지 않고 서드파티 포팅 업체를 거쳐야 합니다. 기획서 범위 밖이지만 참고로 적습니다.
- 마이너 버전 사이(4.x → 4.y)에도 API가 바뀌는 일이 있습니다. 프로젝트 진행 중에는 버전을 고정하고, 계획을 세워 업그레이드해야 합니다.

### 4.2 Unity 6

**장점 [조사]**
- 모바일과 Steam 출시 사례가 가장 많고, 문제가 생겼을 때 참고할 자료도 가장 많습니다.
- 3D와 2.5D에서 가장 강합니다. 스타일라이즈드 3D나 "3D 공간 + 2D 캐릭터"를 택하면 유리합니다.
- Asset Store에 하우징 시스템, 대화 시스템, 캐릭터 커스터마이징 도구 같은 유료 에셋이 많아 제작 기간을 줄일 수 있습니다.
- 공식 Unity MCP가 있어 AI가 에디터 상태(씬, 콘솔)를 직접 확인할 수 있습니다.

**단점과 제약 [조사]**
- **씬과 프리팹 구성이 에디터 작업에 크게 의존합니다.** YAML 텍스트로 저장할 수는 있지만 GUID 참조가 얽혀 있어, AI가 파일을 직접 고치면 깨지기 쉽습니다. 에디터 연동(MCP)을 쓰더라도 결과 확인은 에디터에서 해야 합니다.
- 에디터와 프로젝트가 무겁습니다. 프로젝트 첫 열기와 스크립트 컴파일 대기가 반복 작업 속도를 떨어뜨립니다.
- 라이선스 정책이 바뀐 적이 있습니다. 2023년 Runtime Fee 발표 후 2024년에 철회되었고, Pro·Enterprise 가격은 2026년 1월에 5% 올랐습니다. 매출이 $200K를 넘으면 Pro 전환 의무가 생깁니다.
- 유료 에셋에 의존할수록 해당 에셋이 업데이트를 중단했을 때의 유지보수 위험이 커집니다.

### 4.3 GameMaker

- **장점:** 2D 전용으로 오래 다듬어진 엔진이라 2D 탑다운 생활 게임에 필요한 기능이 충분합니다. 상업 라이선스가 $99.99 일회성으로 저렴합니다.
- **제약:** 3D와 2.5D는 사실상 불가능하므로 그래픽 방식이 A나 B로 정해질 때만 후보가 됩니다. GML은 AI 학습 자료가 GDScript나 C#보다 적습니다. 경로 탐색, 대화 시스템, 직렬화를 직접 구현해야 하는 비중이 큽니다.

### 4.4 Defold

- **장점:** 빌드 용량이 매우 작고 모바일과 웹에 강합니다. 무료이며 Steam 공식 확장이 있습니다.
- **제약:** 에디터 기능과 UI 도구가 단순합니다. 대화, 하우징, 인벤토리처럼 UI가 많은 게임에서는 직접 만들어야 할 부분이 많습니다. 커뮤니티와 참고 자료가 작습니다. 3D·2.5D는 제한적입니다.

---

## 5. 언어 선택 (Godot을 택할 경우)

| 항목 | GDScript | C# (.NET) |
|---|---|---|
| 모든 플랫폼 내보내기 | ◎ | 웹 불가, 모바일 실험 단계 |
| 에디터 통합·반복 속도 | ◎ | ○ (빌드 단계가 있음) |
| 정적 타입 | 선택적 타입 힌트 | 완전 정적 타입 |
| 대규모 로직 유지보수 | ○ (타입 힌트를 강제하면 충분) | ◎ |
| 성능 | 게임 로직 수준에서는 충분 | 연산이 많은 로직에서 유리 |
| AI 코드 작성 정확도 | ○ (Godot 3와 4 문법 혼동에 주의) | ◎ |

[조사] 이 프로젝트의 로직(포커 판정, 관계 수치, 스케줄)은 GDScript로 충분히 처리할 수 있는 규모입니다. 성능이 문제가 되는 부분만 나중에 GDExtension(C++)으로 옮기는 방법도 있습니다.

---

## 6. 보조 도구 후보 [조사]

엔진과 별개로 검토할 도구입니다. 채택은 [미정]입니다.

| 용도 | 후보 | 비고 |
|---|---|---|
| 맵 편집 | 엔진 내장 타일맵, Tiled, LDtk | 외부 도구를 쓰면 엔진 가져오기 플러그인이 필요합니다. |
| 픽셀아트·애니메이션 | Aseprite | 픽셀아트를 택할 때 사실상 표준입니다. |
| 대화 스크립트 | Yarn Spinner, Ink, Dialogue Manager(Godot), Dialogic(Godot) | Yarn과 Ink는 엔진 중립이라 엔진을 바꿔도 대화 데이터를 옮기기 쉽습니다. |
| 게임 데이터 | JSON, CSV, 엔진 리소스 | 04 문서에서 자세히 다룹니다. |
| 테스트 | GUT·gdUnit4 (Godot), Unity Test Framework | |
| 3D 제작 (D 방식일 때) | Blender | glTF 형식으로 엔진에 가져옵니다. |

---

## 7. 출시·계정 비용 [조사]

엔진 선택과 관계없이 드는 비용입니다.

| 항목 | 비용 | 비고 |
|---|---|---|
| Steam Direct | 앱당 $100 | 매출 $1,000 달성 시 환급. 세금·신원 인증 필요 |
| Google Play 개발자 | $25 일회성 | 신규 개인 계정은 비공개 테스트 요건이 있습니다. 출시 시점에 다시 확인해야 합니다. |
| Apple Developer | 연 $99 | macOS 장비가 별도로 필요합니다. |
| Unity Pro | 좌석당 연 약 $2,000대 | Unity를 택하고 연 매출·투자가 $200K를 넘을 때만 해당 |
| GameMaker Professional | $99.99 일회성 | GameMaker를 택할 때만 해당 |

---

## 8. 개발 담당 권고 [권고]

> 아래는 개인 의견입니다. 엔진은 그래픽 방식이 정해진 뒤 기획 측에서 결정합니다.

**그래픽 방식이 A(2D 탑다운)나 B(2D 아이소메트릭)로 정해지면: Godot 4 + GDScript를 권고합니다.**
- AI가 씬과 리소스 파일을 직접 다룰 수 있어 개발 속도와 검증 가능성이 가장 높습니다.
- 라이선스 비용이나 정책 변경 위험이 없어 1인 장기 유지보수에 유리합니다.
- GDScript를 쓰면 PC, Android, 웹까지 제약 없이 내보낼 수 있습니다.
- 위험 요소는 GodotSteam 의존과 iOS용 macOS 필요입니다. 둘 다 출시 단계의 문제라 초기 개발을 막지는 않습니다.

**그래픽 방식이 C(2.5D)나 D(스타일라이즈드 3D)로 정해지면: Godot과 Unity를 다시 비교해야 합니다.**
- 3D 에셋 생태계, 캐릭터 커스터마이징 도구, 조명 품질에서는 Unity가 앞섭니다.
- 대신 AI가 직접 편집할 수 있는 범위가 줄어들고 에디터에서 확인하는 비중이 커집니다.
- 이 경우 한쪽 엔진으로 작은 기술 검증(마을 한 블록 + 캐릭터 1명 + 가구 배치)을 해 본 뒤 결정하는 것을 권고합니다. 기술 검증도 별도 승인 후 진행합니다.

**GameMaker와 Defold는** 2D로 확정되고 특별한 이유(예: 모바일 용량 최우선)가 있을 때만 다시 검토하면 됩니다.

**엔진과 무관하게 권고하는 원칙**
- 엔진 버전을 고정하고, 업그레이드는 별도 작업으로 계획해서 진행합니다.
- 대화 데이터는 가능하면 엔진 중립 형식(Yarn, Ink, JSON 등)으로 둡니다.
- 게임 규칙 로직(포커 판정, 관계 계산 등)은 엔진 노드에 의존하지 않는 순수 코드로 분리해 테스트할 수 있게 합니다.

---

## 9. 추가 확인이 필요한 사항

- GodotSteam이 Godot 4.7.x를 지원하는 시점. 2026년 상반기 기준으로 4.5.2와 4.6.1용 업데이트가 확인되었습니다.
- Godot 4.7에서 C# 모바일·웹 지원이 달라졌는지. 이 문서의 내용은 공식 문서의 4.2 기준 서술입니다.
- Unity MCP와 Godot 커뮤니티 MCP의 실제 사용성. 실제로 연결해서 검증한 결과가 아닙니다.
- Google Play 신규 개인 개발자 계정의 테스트 요건 최신 내용.

## 출처

- [Godot (game engine) — Wikipedia](https://en.wikipedia.org/wiki/Godot_(game_engine))
- [Godot 4.7 개요 — Ziva](https://ziva.sh/blogs/godot-4-7)
- [Godot 4.6 릴리스 — Digital Production](https://digitalproduction.com/2026/01/28/godot-4-6-arrives-with-major-cg-friendly-updates/)
- [Godot 릴리스 — GitHub](https://github.com/godotengine/godot/releases)
- [Current state of C# platform support in Godot 4.2](https://godotengine.org/article/platform-state-in-csharp-for-godot-4-2/)
- [GodotSteam GDExtension — Asset Library](https://godotengine.org/asset-library/asset/2445)
- [GodotSteam 블로그: Godot 4.6.1 지원](https://godotsteam.com/blog/2026/02/17/godotsteam-for-godot-461/)
- [Unity Pricing Changes](https://unity.com/products/pricing-updates)
- [Unity Runtime Fee 철회](https://unity.com/blog/unity-is-canceling-the-runtime-fee)
- [Unity MCP 시작하기 — Unity Docs](https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.7/manual/integration/unity-mcp-get-started.html)
- [Godot AI — Godot Asset Store](https://store.godotengine.org/asset/dlight/godot-ai/)
- [Godot MCP Pro — Asset Library](https://godotengine.org/asset-library/asset/4961)
- [GameMaker 라이선스](https://gamemaker.io/en/get)
- [Defold 2026 상반기 요약](https://defold.com/2026/06/30/Defold-H1-2026/)
- [Defold Steam 확장](https://defold.com/extension-steam/)
