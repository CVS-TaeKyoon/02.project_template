@AGENTS.md

---

# Claude Code 전용

위 AGENTS.md가 이 프로젝트의 기준이다. 아래는 **Claude Code에서만 해당하는 매핑**이며,
여기에 프로젝트 규칙 자체를 쓰지 않는다. 규칙이 바뀌면 AGENTS.md를 고친다.

## 파이프라인 스킬

| 단계 | 스킬 | 산출물 |
|---|---|---|
| 왜 만드는가 | `intent-capture` | `docs/intent/NNN-슬러그.md` |
| 무엇을 만족해야 하는가 | `spec-authoring` | `docs/specs/NNN-슬러그.md` |
| 어떤 파일을 어떤 순서로 | `implementation-plan` | `docs/plans/NNN-슬러그.md` |

무엇을 왜 만들지가 아직 문서로 고정되지 않았다면 `intent-capture`부터 시작한다.

이 셋 말고 **안내 스킬** 둘이 더 있다. 파이프라인 단계가 아니라 구조 자체를 다룬다.

| 스킬 | 언제 |
|---|---|
| `project-structure-guide` | 구조·규칙이 궁금할 때. 읽기만 하고 아무것도 바꾸지 않는다 |
| `project-bootstrap` | 새 프로젝트의 초기 설정. 한 번 쓰고 스스로 삭제한다 |

## 도구 매핑

- AGENTS.md의 **"파일을 수정할 수 없는 상태에서 계획한다"** = Claude Code의 **Plan Mode**.
  Plan Mode가 자동 저장하는 파일(`~/.claude/plans/`)은 세션 데이터이지 산출물이 아니다.
  승인된 계획은 `docs/plans/`에 별도로 커밋한다.
- 스킬 경로: Claude Code는 `.claude/skills/`만 읽는다. **이 폴더는 미러다** —
  수정은 `.agents/skills/`에서 하고 동기화한다.

## 설정 파일

- `.claude/settings.json` — 팀 공유. 커밋한다.
- `.claude/settings.local.json` — 개인 설정. 커밋하지 않는다.
