## 단계
<!-- 해당하는 것만 남기고 아래 "확인" 섹션도 그 단계 것만 남긴다 -->
intent / spec / plan / 구현

## 무엇을
<!-- 한 문장 -->

## 확인 — intent
- [ ] Problem이 해법이 아니라 **겪는 불편**으로 쓰였다
- [ ] Constraints가 비어 있지 않다 (깨지면 안 되는 기존 동작이 최소 하나)
- [ ] Open questions를 추측으로 채우지 않았다
- [ ] 리뷰 승인 후 상태 줄을 `approved` 로 바꿨다

## 확인 — spec
- [ ] 대응 intent: `docs/intent/NNN-*.md` (같은 번호·슬러그)
- [ ] 요구사항에 번호가 붙어 있다 (R__, N__)
- [ ] Acceptance criteria가 검증 가능한 문장이다
- [ ] intent의 Open questions를 처리했다 (답했거나, 이월 이유를 적었다)
- [ ] Concerns에 판단 주체가 적혀 있다
- [ ] 파일 목록·작업 순서가 들어가지 않았다
- [ ] 리뷰 승인 후 상태 줄을 `approved` 로 바꿨다

## 확인 — plan
- [ ] 대응 spec: `docs/specs/NNN-*.md` (같은 번호·슬러그)
- [ ] Files에 실제 경로가 있다 (신규/수정 구분)
- [ ] Risks가 구체적인 파일이나 동작을 지목한다
- [ ] Proof가 spec의 어느 AC에 대응하는지 적혀 있다
- [ ] spec의 미해결 Concerns를 Risks로 이월했다
- [ ] 리뷰 승인 후 상태 줄을 `approved` 로 바꿨다

## 확인 — 구현
- [ ] diff가 `plan.md`와 일치 (벗어난 부분은 같은 커밋에서 plan.md에 반영됨)
- [ ] `plan.md`의 Proof 항목 전부 확인
- [ ] 사용자에게 보이는 변화가 있다면 `CHANGELOG.md` 갱신 (작업 번호 포함)
- [ ] 스킬을 수정했다면 `.agents/skills/`에서 수정하고 미러를 동기화
- [ ] 문서 양식이나 스킬 안 템플릿을 고쳤다면 `.agents/check-templates.ps1` 통과

## 리뷰어에게
<!-- 특히 봐줬으면 하는 부분, 판단이 필요한 지점 -->
