---
name: implementation-plan
description: 승인된 요구사항을 구현 순서·변경 파일·위험·검증 기준으로 구체화하거나 여러 파일에 걸친 변경을 준비할 때 사용한다.
---

# 구현 계획

계획을 요청받았을 때는 코드를 수정하지 않고 먼저 읽어 판단한다. 저장할 계획과 작업 상태는 세션 기억이 아니라 프로젝트 JSON 원본에 둔다.

## 진행

1. `AGENTS.md`, 원본 목록, 작업 상태와 전체 공통 제약을 읽는다. 관련 의도·요구사항의 승인본, 예외, 결정 이유, 의존 항목과 역참조를 확인한다.
2. 실제 코드와 인터페이스를 읽고 변경할 파일, 순서, 구체적 위험, 검증 기준과 관련 ID, 검토한 대안을 정리한다. 승인되지 않은 조건을 구현 전제로 삼지 않는다.
3. 계획을 검토한다. 누락된 요구, 가장 위험한 단계, 영향받는 동작, 선택하지 않은 방법과 이유, 되돌릴 방법을 확인한다. 미결 항목과 판단 주체를 이월한다.
4. `kind: plan` JSON 항목으로 저장하고 `work-state.json`의 작업 단계와 연결한다. 3개 이상 파일이나 한 문장으로 설명하기 어려운 변경은 계획을 남긴다. 작은 작업의 생략 판단도 작업 상태에 이유를 남긴다.
5. 명시적 승인 범위가 확인된 계획만 `accepted`로 기록한다. 저장과 커밋·PR은 별개다. 계획 작성 요청만으로 구현에 착수하지 않는다.
6. 구현 요청을 받으면 승인된 범위에서 진행한다. 버그는 실패하는 회귀 테스트를 먼저 확인하고 고친다. 계획이 달라지면 이유를 기록해 다음 revision으로 갱신하고 필요한 승인을 확인한다.
7. 원본·관계·이력·색인·작업 상태를 일괄 저장한다. 실제 검증 결과를 재조회하고 실행하지 못한 검사는 분리해 보고한다. 실패하거나 검토 중인 상태를 완료로 쓰지 않는다.

파일 쓰기를 차단하는 도구 기능이 있다면 계획 분석에 활용하되, 그 기능의 존재나 설정을 꾸며내지 않는다. JSON 계획 저장은 분석이 끝난 뒤 수행한다. 도구가 자동으로 만든 계획 파일이나 커밋 자체는 사용자 승인 기록이 아니다.

## 사람이 읽는 계획 문서를 요청받은 경우

JSON 계획을 먼저 반영한 뒤 `docs/templates/plan.md`의 섹션으로 파생 문서를 만든다. 관련 설계 ID와 원본 revision 또는 Git commit을 표시한다. 아래 경로와 숫자는 과거 가상 예시이며 실제 프로젝트 상태로 사용하지 않는다. 예시 상태 대신 원본의 실제 상태를 표시한다.

```markdown
# Plan: 간편 로그인 개선
출처: docs/intent/002-social-login.md, docs/specs/002-social-login.md · 상태: draft

## Files
- auth-api/src/oauth/provider.ts (신규) — provider 추상화
- auth-api/src/oauth/google.ts (신규)
- auth-api/src/oauth/apple.ts (신규)
- auth-api/src/routes/login.ts (수정) — 콜백 라우트 추가
- auth-api/migrations/0042_add_provider.sql (신규)
- mobile-app/src/screens/Login.tsx (수정)
- auth-api/tests/oauth.test.ts (신규)

## Order of work
1. provider 추상화 인터페이스 추가. 이 시점에 기존 동작은 그대로다.
2. 마이그레이션으로 users에 provider, provider_uid 컬럼 추가 (nullable).
3. Google provider 구현 + 단위 테스트.
4. 이메일 충돌 처리 (spec R3) 구현. 여기가 회귀 위험이 가장 큼.
5. Apple provider 구현. private relay 케이스 포함.
6. 로그인 화면 버튼 연결.

## Risks
- 4번이 기존 이메일 로그인 경로를 건드린다. 기존 로그인
  통합 테스트가 통과하는지 각 단계마다 확인.
- provider 토큰이 에러 로그에 실릴 수 있다 (spec N2, 정책 위반).
  에러 핸들러에서 명시적으로 마스킹 필요.
- 마이그레이션은 nullable로 추가해 롤백 가능하게 유지.

## Proof
- oauth.test.ts가 spec AC1~AC3을 커버한다.
- 기존 auth 통합 테스트 전부 통과.
- 로그인 화면 스크린샷이 승인된 목업과 일치.
- 에러 로그에 provider 토큰이 없음을 테스트로 확인.

## Alternatives considered
- provider별 라우트를 따로 두는 방식: 중복이 커지고 세 번째
  provider 추가 시 비용이 늘어 추상화 계층을 택함.
```
