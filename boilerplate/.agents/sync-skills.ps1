<#
.SYNOPSIS
    스킬 원본(.agents\skills)을 미러(.claude\skills)로 동기화한다.

.DESCRIPTION
    Claude Code는 .agents\skills 를, Codex는 .claude\skills 를 읽지 못한다.
    두 도구가 같은 스킬을 쓰려면 파일이 두 경로에 있어야 하므로, 원본을 미러로 복제한다.
    원본은 .agents\skills 뿐이다. 미러는 생성물이며 직접 수정하지 않는다.

.PARAMETER Check
    복사하지 않고 차이만 검사한다. 어긋나 있으면 종료 코드 1을 반환한다.
    커밋 훅이나 CI에서 이 모드로 호출한다.

.EXAMPLE
    .\.agents\sync-skills.ps1
    .\.agents\sync-skills.ps1 -Check
#>
param([switch]$Check)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root '.agents\skills'
$dst  = Join-Path $root '.claude\skills'

if (-not (Test-Path $src)) {
    Write-Host "원본을 찾을 수 없습니다: $src"
    exit 1
}

function Get-FileMap([string]$path) {
    $map = @{}
    if (-not (Test-Path $path)) { return $map }
    Get-ChildItem $path -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($path.Length).TrimStart('\')
        $map[$rel] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
    return $map
}

$srcMap = Get-FileMap $src
$dstMap = Get-FileMap $dst

$diff = @()
foreach ($key in $srcMap.Keys) {
    if (-not $dstMap.ContainsKey($key))      { $diff += "미러에 없음  : $key" }
    elseif ($srcMap[$key] -ne $dstMap[$key]) { $diff += "내용 불일치  : $key" }
}
foreach ($key in $dstMap.Keys) {
    if (-not $srcMap.ContainsKey($key))      { $diff += "원본에 없음  : $key" }
}

if ($Check) {
    if ($diff.Count -eq 0) {
        Write-Host "동기화 상태 정상 ($($srcMap.Count)개 파일)"
        exit 0
    }
    Write-Host "미러가 원본과 다릅니다:"
    $diff | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "해결: .agents\sync-skills.ps1 을 실행하고 결과를 함께 커밋하세요."
    Write-Host "주의: .claude\skills 를 직접 고쳤다면 그 수정은 사라집니다. 원본에 옮기세요."
    exit 1
}

if ($diff.Count -eq 0) {
    Write-Host "이미 동기화되어 있습니다 ($($srcMap.Count)개 파일)"
    exit 0
}

if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Copy-Item $src $dst -Recurse

Write-Host "동기화 완료 ($($srcMap.Count)개 파일). 반영된 차이:"
$diff | ForEach-Object { Write-Host "  $_" }
exit 0
