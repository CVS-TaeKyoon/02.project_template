#requires -Version 7.4
param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)), [Parameter(Mandatory)][string]$ExpectedFingerprint)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'design-data.psm1') -Force -DisableNameChecking
Save-DesignBatch -ProjectRoot $ProjectRoot -Batch @{ expected_fingerprint = $ExpectedFingerprint; files = @() }
Write-Host '원본 검증과 재조회 후 파생 색인을 갱신했습니다. 커밋·push는 하지 않았습니다.'
