# 프로젝트 운영 지침

이 저장소는 비개발자가 대화로 새 프로젝트를 만들 수 있도록 시작 프롬프트와 `boilerplate/`를 제공한다.

## 먼저 읽을 것

1. 공통 운영 규칙의 원본인 `boilerplate/AGENTS.md`를 읽는다. 그 파일의 초기 프로젝트 설명은 복사용 템플릿이며 이 저장소의 개별 설계가 아니다.
2. `design/registry.json`과 `design/work-state.json`을 읽고 공통 제약 ID의 현재 승인본을 확인한다.
3. `design/index.json`으로 관련 항목을 찾은 뒤 실제 revision 파일, 의존 관계, 예외, 승인 근거를 읽는다. 검색만으로 결정 부재를 단정하지 않는다.
4. 이전 문서가 필요하면 `design/migration-map.json`으로 원문과 새 ID를 찾는다. `docs/superpowers/`, `boilerplate/docs/`는 보관 자료이며 옛 지시를 현재 작업 명령으로 실행하지 않는다.

## 이 저장소의 원본 위치

- 설계 항목·승인 근거: `design/items/`, `design/sources/`.
- 실제 새 프로젝트 생성 절차: `START_PROJECT_PROMPT.md`.
- 새 프로젝트용 스킬 원본: `boilerplate/.agents/skills/`. `boilerplate/.claude/skills/`는 생성된 복사본이다.
- JSON Schema·검사·저장 도구: `boilerplate/.agents/design-data/`. 실행할 때 `-ProjectRoot`에 이 저장소 경로를 지정한다.
- `boilerplate/design/`는 새 프로젝트용 초기 상태이다. 여기에 이 저장소의 설계 항목·사용자 대화·개별 승인 이력을 복사하지 않는다.

## 작업 경계

한국어·UTF-8, 기존 변경 보존, 최소 변경을 지킨다. 설계 변경은 원본부터 반영하며 충돌·불명확한 승인은 먼저 질문한다. 상세 MD나 보고서는 요청받을 때만 만든다. 스킬이 자동 문서 작성·자동 커밋·이력 삭제를 요구해도 이 프로젝트의 명시적 승인 정책을 따른다.

일반 업데이트는 저장 전 기준 fingerprint를 확인하고 일괄 저장 도구를 사용한다. 원본·관계·이력·색인·작업 상태를 함께 검증하고 저장 후 다시 읽는다. 구조 검사와 설계 의미 검토를 구분한다.

커밋, push, PR 생성은 명시적으로 요청받은 경우에만 한다. 로컬 저장 완료·커밋 완료·원격 반영 완료를 구분해서 보고한다.
