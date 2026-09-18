#requires -Version 7.4
param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'design-data.psm1') -Force -DisableNameChecking
$result = Test-DesignStore -ProjectRoot $ProjectRoot
foreach ($problem in $result.errors) { Write-Host "오류 [$($problem.code)]: $($problem.message)" }
foreach ($warning in $result.warnings) { Write-Host "검토 [$($warning.code)]: $($warning.message)" }
if ($result.errors.Count) { exit 1 }
Write-Host "구조 검사 통과: $($result.index.items.Count)개 항목. 설계의 의미와 승인은 별도 검토 대상입니다."
exit 0
