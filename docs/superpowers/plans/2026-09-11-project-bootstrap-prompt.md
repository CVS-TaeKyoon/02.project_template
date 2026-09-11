# 프로젝트 시작 프롬프트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 비개발자가 Codex 채팅에서 공개 템플릿으로 안전하게 새 프로젝트를 만들도록 하는 복사-붙여넣기 프롬프트와 안내 문서를 제공한다.

**Architecture:** 루트 `START_PROJECT_PROMPT.md`를 동작 지침의 단일 기준으로 두고, 루트 `README.md`는 사용자가 그 문서를 쉽게 찾아 복사하도록 안내한다. 생성 대상은 이미 존재하는 `boilerplate` 디렉터리뿐이며, 그 내부의 스킬과 구조는 바꾸지 않는다.

**Tech Stack:** Markdown, PowerShell 검증 명령, Git, GitHub CLI

**Spec:** `docs/superpowers/specs/2026-09-11-project-bootstrap-prompt-design.md`

## Global Constraints

- 템플릿 원본은 `https://github.com/CVS-TaeKyoon/02.project_template`의 `boilerplate` 디렉터리다.
- 사용자 입력은 상위 폴더 경로, 프로젝트 이름, 프로젝트 목적 순서로 한 번에 하나씩 받는다.
- 기존 대상 폴더·기존 원격 저장소·기존 파일을 덮어쓰거나 삭제하지 않는다.
- Markdown의 `<프로젝트 이름>`만 이름으로 치환하고, `README.md`와 `AGENTS.md`의 설명 자리에 목적을 반영한다.
- GitHub 업로드는 최종 승인, `gh` 설치, GitHub 로그인이 모두 확인된 경우에만 한다.
- 키·토큰·비밀번호·`.env`는 채팅에 요구하거나 GitHub에 올리지 않는다.
- 사용자가 터미널 명령을 입력하거나 파일을 직접 수정하도록 요구하지 않는다.

---

### Task 1: 시작 프롬프트 작성

**Files:**
- Create: `START_PROJECT_PROMPT.md`
- Test: PowerShell의 `Select-String`으로 필수 지침 문자열 검사

**Interfaces:**
- Consumes: 공개 템플릿 URL과 `boilerplate` 디렉터리
- Produces: 사용자가 Codex 채팅에 그대로 붙여넣는 단일 Markdown 프롬프트

- [ ] **Step 1: 존재하지 않는 시작 프롬프트를 확인한다**

Run: `Test-Path -LiteralPath START_PROJECT_PROMPT.md`

Expected: `False`

- [ ] **Step 2: `START_PROJECT_PROMPT.md`를 작성한다**

문서에는 아래 내용을 명시한다.

```markdown
- 상위 폴더 경로 → 프로젝트 이름 → 프로젝트 목적을 순서대로 한 번씩 질문한다.
- https://github.com/CVS-TaeKyoon/02.project_template 의 boilerplate만 새 폴더로 복사한다.
- 대상 폴더가 있으면 멈추고 다른 이름 또는 경로를 묻는다.
- Git이 없으면 main 브랜치 ZIP을 내려받아 같은 결과를 만든다.
- GitHub 업로드 전 gh 설치·로그인과 최종 승인을 확인한다.
- .env·키·토큰·비밀번호를 요청하거나 올리지 않는다.
```

- [ ] **Step 3: 필수 지침을 검증한다**

Run: `@('https://github.com/CVS-TaeKyoon/02.project_template','boilerplate','프로젝트를 만들 상위 폴더 경로','프로젝트 이름','프로젝트 목적','gh','.env') | ForEach-Object { if (-not (Select-String -LiteralPath START_PROJECT_PROMPT.md -Pattern ([regex]::Escape($_)) -Quiet)) { throw "시작 프롬프트에 필수 내용이 없습니다: $_" } }`

Expected: 오류 없이 종료

- [ ] **Step 4: 변경을 커밋한다**

```powershell
git add START_PROJECT_PROMPT.md
git commit -m "feat: 프로젝트 시작 프롬프트 추가"
```

### Task 2: 비개발자용 사용 안내 작성

**Files:**
- Create: `README.md`
- Test: Markdown 링크와 사용 흐름 문자열 검사

**Interfaces:**
- Consumes: `START_PROJECT_PROMPT.md`
- Produces: 저장소 첫 화면에서 보이는 간결한 사용 안내

- [ ] **Step 1: 루트 README가 없는 상태를 확인한다**

Run: `Test-Path -LiteralPath README.md`

Expected: `False`

- [ ] **Step 2: `README.md`를 작성한다**

문서에는 템플릿의 용도, `START_PROJECT_PROMPT.md`를 열어 전체 내용을 Codex 채팅에 붙여넣는 단일 사용 방법, Codex가 이후 질문을 하나씩 한다는 점, 생성 프로젝트에는 `boilerplate` 내용만 들어간다는 점을 적는다. GitHub 업로드는 `gh` 설치와 로그인 뒤 사용자 승인을 받아서만 수행된다고 적는다.

- [ ] **Step 3: 안내 문서의 핵심 연결을 검증한다**

Run: `@('START_PROJECT_PROMPT.md','하나씩','GitHub CLI','boilerplate') | ForEach-Object { if (-not (Select-String -LiteralPath README.md -Pattern ([regex]::Escape($_)) -Quiet)) { throw "README에 필수 안내가 없습니다: $_" } }`

Expected: 오류 없이 종료

- [ ] **Step 4: 변경을 커밋한다**

```powershell
git add README.md
git commit -m "docs: 프로젝트 시작 방법 안내"
```

### Task 3: 템플릿 무결성과 최종 검증

**Files:**
- Modify: 없음
- Test: 시작 프롬프트·안내 문서·기존 스킬 미러·Git diff 검증

**Interfaces:**
- Consumes: `START_PROJECT_PROMPT.md`, `README.md`, `boilerplate/.agents/sync-skills.ps1`
- Produces: 검증을 통과한 Git 작업 트리

- [ ] **Step 1: 시작 프롬프트와 안내 문서의 형식 오류를 검사한다**

Run: `git diff --check HEAD~2..HEAD; git diff --check`

Expected: 출력 없음, 종료 코드 0

- [ ] **Step 2: 기존 스킬 원본과 미러의 일치를 검사한다**

Run: `& .\\boilerplate\\.agents\\sync-skills.ps1 -Check`

Expected: `동기화 상태 정상`을 포함하고 종료 코드 0

- [ ] **Step 3: 최종 상태를 확인한다**

Run: `git status --short --branch; git log --oneline -3`

Expected: 작업 트리가 비어 있고, 새 프롬프트·안내 문서 커밋이 `main`에 있다.

- [ ] **Step 4: 원격에 push한다**

```powershell
git push origin main
```

Expected: `main -> main` push 성공
