<#
.SYNOPSIS
    문서 양식(docs\templates)과 스킬 안 템플릿의 섹션 구성이 같은지 검사한다.

.DESCRIPTION
    같은 문서의 양식이 두 곳에 있다. docs\templates 는 사람이 직접 쓸 때 보고,
    스킬 안의 템플릿은 에이전트가 문서를 만들 때 쓴다. 둘의 섹션 제목이 어긋나면
    누가 썼느냐에 따라 문서 형식이 갈리고, 다음 단계의 에이전트가 파싱에 실패한다.

    섹션 제목만 비교한다. 본문은 한쪽이 빈 양식이고 다른 쪽이 예시라 원래 다르다.
    어긋나면 종료 코드 1을 반환한다. 커밋 훅이나 CI에서 호출한다.

    ADR(docs\templates\adr.md)은 대응하는 스킬이 없어 검사 대상이 아니다.

.EXAMPLE
    .\.agents\check-templates.ps1
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

$pairs = @(
    @{ Template = 'intent.md'; Skill = 'intent-capture' }
    @{ Template = 'spec.md';   Skill = 'spec-authoring' }
    @{ Template = 'plan.md';   Skill = 'implementation-plan' }
)

# 영어로 고정된 섹션 제목만 추린다 (파이프라인 규약)
function Get-Sections($lines) {
    @($lines | Where-Object { $_ -match '^##\s+[A-Za-z]' } | ForEach-Object { $_.Trim() })
}

# SKILL.md 안의 마크다운 코드블록에서만 추린다
function Get-SkillSections([string]$path) {
    $inBlock = $false
    $collected = @()
    foreach ($line in (Get-Content $path)) {
        if (-not $inBlock -and $line -match '^\s*```markdown\s*$') { $inBlock = $true; continue }
        if ($inBlock -and $line -match '^\s*```\s*$')              { $inBlock = $false; continue }
        if ($inBlock) { $collected += $line }
    }
    Get-Sections $collected
}

$problems = @()

foreach ($pair in $pairs) {
    $tPath = Join-Path $root "docs\templates\$($pair.Template)"
    $sPath = Join-Path $root ".agents\skills\$($pair.Skill)\SKILL.md"

    if (-not (Test-Path $tPath)) { $problems += "양식이 없음: docs\templates\$($pair.Template)"; continue }
    if (-not (Test-Path $sPath)) { $problems += "스킬이 없음: $($pair.Skill)"; continue }

    $a = Get-Sections (Get-Content $tPath)
    $b = Get-SkillSections $sPath

    if ($a.Count -eq 0) { $problems += "$($pair.Template): 영어 섹션 제목을 찾지 못했습니다"; continue }
    if ($b.Count -eq 0) { $problems += "$($pair.Skill): SKILL.md 안에서 마크다운 템플릿 블록을 찾지 못했습니다"; continue }

    if (Compare-Object $a $b -SyncWindow 0) {
        $problems += "$($pair.Template) <-> $($pair.Skill) 섹션 불일치"
        $problems += "    양식: $($a -join ' / ')"
        $problems += "    스킬: $($b -join ' / ')"
    }
}

if ($problems.Count -eq 0) {
    Write-Host "문서 양식과 스킬 템플릿의 섹션이 일치합니다 ($($pairs.Count)쌍)"
    exit 0
}

Write-Host "문서 양식과 스킬 템플릿이 어긋났습니다:"
$problems | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "해결: 한쪽을 기준으로 정하고 다른 쪽의 섹션 제목을 맞추세요."
Write-Host "      섹션 제목은 파이프라인의 규약입니다 - 한쪽만 바꾸면 문서 형식이 갈립니다."
exit 1
