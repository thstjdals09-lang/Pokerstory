# Pokerstory (Project 20)

> 정식 게임명은 아직 정해지지 않았습니다. 저장소 이름 `Pokerstory`와 작업명 "Project 20"은 임시 명칭입니다.

포커가 일상 문화인 따뜻한 판타지 마을에서 생활하고 주민들과 관계를 맺으며, 짧은 판타지 포커를 즐기는 게임입니다.

## 현재 단계

| 항목 | 상태 |
|---|---|
| 콘셉트 결정(10개 질문) | 기록 완료 |
| 상세 기획 | **승인되지 않음** |
| 저장소 준비 | 완료 |
| 사전 제작 기술 조사 | 완료 (조사 자료이며 결정 사항 아님) |
| 게임 개발 | **시작하지 않음.** 별도 승인 후 진행 |

지금 이 저장소에는 기획 문서, 기술 조사 문서, 저장소 관리 파일만 있습니다. 게임 코드, 엔진 프로젝트, 에셋은 없습니다.

## 기획 문서 (Source of Truth)

- [docs/Project20_Design_Brief_v0.1.md](docs/Project20_Design_Brief_v0.1.md) (v0.1, 원본 그대로 보관)

기획 문서에 없는 내용은 확정된 요구사항이 아닙니다. 문서의 "아이디어 예시"는 참고용이며 제작 요구사항이 아닙니다.

## 사전 제작 기술 조사 (개발 담당 작성)

엔진, 그래픽, 시스템 규칙을 결정하지 않는 조사 자료입니다. 기획 측이 결정할 때 참고하는 용도입니다.

| 문서 | 내용 |
|---|---|
| [01_ENGINE_AND_TECH_STACK.md](docs/preproduction/01_ENGINE_AND_TECH_STACK.md) | 엔진 후보(Godot, Unity, GameMaker, Defold) 비교와 제약 |
| [02_GRAPHICS_TECHNICAL_OPTIONS.md](docs/preproduction/02_GRAPHICS_TECHNICAL_OPTIONS.md) | 2D 탑다운, 아이소메트릭, 2.5D, 3D의 구현 비용 비교 |
| [03_CORE_SYSTEM_FEASIBILITY.md](docs/preproduction/03_CORE_SYSTEM_FEASIBILITY.md) | 핵심 시스템 10개의 기술 요소, 의존 관계, 위험 |
| [04_AI_DEVELOPMENT_WORKFLOW.md](docs/preproduction/04_AI_DEVELOPMENT_WORKFLOW.md) | 시스템 단위 AI 개발 흐름, 테스트, 데이터·에셋 관리 |
| [05_DESIGN_DECISIONS_REQUIRED.md](docs/preproduction/05_DESIGN_DECISIONS_REQUIRED.md) | 기획 측이 결정해야 할 질문 (개발 전 / 프로토타입 중 / 플레이 테스트 후) |

## 아직 정해지지 않은 것

기획 문서 4절 기준입니다. 확정되기 전에는 아래 항목을 전제로 작업하지 않습니다.

- 정식 게임명, 출시 플랫폼, 싱글/멀티, 온라인 기능
- 엔진/프레임워크, 프로그래밍 언어, 그래픽 표현, 카메라 시점, 입력 방식
- 포커 룰, 보상, 능력 밸런스, 재화·과금 설계
- 월드 맵, 주민·건물 수, 스토리, 퀘스트, 관계·주거·마을 발전 규칙
- 시간 진행 로직, 현실 날짜 이벤트 운영, 저장 방식
- 일정, 인력, 예산, MVP 범위

## 저장소 구성

```
.
├─ docs/          # 기획 문서
│  └─ preproduction/  # 사전 제작 기술 조사
├─ .gitattributes # docs/ 파일을 줄바꿈 변환 없이 원본 그대로 보관
├─ .gitignore     # OS·에디터 임시 파일만 제외 (엔진 관련 항목 없음)
└─ README.md
```

엔진이 정해지면 그에 맞춰 디렉터리 구조를 추가합니다.
