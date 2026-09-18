#requires -Version 7.4
param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)), [Parameter(Mandatory)][string]$BatchFile)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'design-data.psm1') -Force -DisableNameChecking
$batch = Get-Content -LiteralPath $BatchFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
Save-DesignBatch -ProjectRoot $ProjectRoot -Batch $batch
Write-Host '설계 원본·작업 상태·색인을 저장하고 재검증했습니다. 커밋·push는 하지 않았습니다.'
