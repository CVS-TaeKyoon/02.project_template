@AGENTS.md

---

# Claude Code 전용

위 AGENTS.md가 이 프로젝트의 기준이다. 아래는 **Claude Code에서만 해당하는 매핑**이며,
여기에 프로젝트 규칙 자체를 쓰지 않는다. 규칙이 바뀌면 AGENTS.md를 고친다.

## 파이프라인 스킬

| 단계 | 스킬 | 산출물 |
|---|---|---|
| 왜 만드는가 | `intent-capture` | 의도·제약·미결 항목 JSON |
| 무엇을 만족해야 하는가 | `spec-authoring` | 요구·결정·검증 기준 항목 JSON |
| 어떤 파일을 어떤 순서로 | `implementation-plan` | 계획 항목 JSON과 작업 상태 |

무엇을 왜 만들지가 아직 문서로 고정되지 않았다면 `intent-capture`부터 시작한다.

이 셋 말고 **안내 스킬** 둘이 더 있다. 파이프라인 단계가 아니라 구조 자체를 다룬다.

| 스킬 | 언제 |
|---|---|
| `project-structure-guide` | 구조·규칙이 궁금할 때. 읽기만 하고 아무것도 바꾸지 않는다 |
| `project-bootstrap` | 새 프로젝트의 초기 설정과 중단된 설정 재개. 완료 기록을 확인한다 |

## 도구 매핑

- 계획 단계에서는 구현 코드를 수정하지 않는다. 도구가 제공하는 계획 기능의 세션 데이터와
  프로젝트의 JSON 계획 원본·사용자 승인 기록을 구분한다.
- 이 템플릿이 제공하는 스킬 경로는 `.claude/skills/`다. **이 폴더는 미러다** —
  수정은 `.agents/skills/`에서 하고 동기화한다.

## 설정 파일

- `.claude/settings.json` — 팀 공유. 커밋 요청이 있을 때 관련 변경에 포함한다.
- `.claude/settings.local.json` — 개인 설정. 커밋하지 않는다.
