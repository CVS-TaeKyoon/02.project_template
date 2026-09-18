#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$module = Join-Path $repo 'boilerplate/.agents/design-data/design-data.psm1'
if (-not (Test-Path -LiteralPath $module)) { throw '설계 검증 도구가 없어 정상 데이터와 오류 데이터를 구분할 수 없습니다.' }
Import-Module $module -Force -DisableNameChecking
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('design-data-tests-' + [guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $tempRoot)
$script:passed = 0

function Write-TestJson($root, $path, $value) {
    $target = Join-Path $root $path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllText($target, ($value | ConvertTo-Json -Depth 50) + "`n", [Text.UTF8Encoding]::new($false))
}
function New-TestItem($id = 'decision-one', $revision = 1, $status = 'accepted') {
    return [ordered]@{
        schema_version = 1; id = $id; revision = $revision; kind = 'decision'; status = $status
        title = '시험용 결정'; content = '개발과 무관한 합성 시험 데이터'; rationale = '참조와 승인을 검증한다.'
        exceptions = @(); source_refs = @('source-test'); approval_source = $(if ($status -eq 'accepted') { 'source-test' } else { $null })
        relations = @(); previous_revision = $null; previous_sha256 = $null; change_reason = '시험 초기 데이터'
    }
}
function New-TestStore($name) {
    $root = Join-Path $tempRoot $name
    [void][IO.Directory]::CreateDirectory($root)
    [IO.File]::WriteAllText((Join-Path $root 'AGENTS.md'), '시험용 운영 규칙')
    Write-TestJson $root 'design/registry.json' @{
        schema_version = 1; project_name = '시험'; purpose_id = $null
        authorities = @(@{ domain = '운영 규칙'; path = 'AGENTS.md'; role = 'canonical' })
        global_constraints = @{ paths = @('AGENTS.md'); item_ids = @() }
    }
    Write-TestJson $root 'design/work-state.json' @{
        schema_version = 1; task = '시험'; status = 'in_progress'; current_ids = @('decision-one'); open_ids = @()
        next_actions = @(); steps = @(); validation = @{ structural = 'not_run'; semantic = 'pending'; notes = @() }
    }
    Write-TestJson $root 'design/migration-map.json' @{ schema_version = 1; baseline_commit = $null; files = @() }
    Write-TestJson $root 'design/sources/source-test.json' @{
        schema_version = 1; id = 'source-test'; kind = 'user_approval'
        locator = @{ description = '시험용 승인'; path = $null; commit = $null; message_id = $null; date = $null }
        content = '시험을 위한 합성 승인'; approvals = @(@{ id = 'decision-one'; revision = 1; scope = '시험용 결정' })
    }
    Write-TestJson $root 'design/items/decision-one/0001.json' (New-TestItem)
    return $root
}
function Assert-True($condition, $message) { if (-not $condition) { throw $message } }
function Test-Case($name, [scriptblock]$body) {
    & $body
    $script:passed++
    Write-Host "통과: $name"
}
function Assert-Invalid($root, $code) {
    $result = Test-DesignStore -ProjectRoot $root -SkipIndex
    Assert-True (@($result.errors | Where-Object code -EQ $code).Count -gt 0) "예상한 오류를 찾지 못했습니다: $code"
}
try {
    Test-Case '정상 원본을 검증하고 최신·적용 revision을 구분한다' {
        $root = New-TestStore 'valid'
        $result = Test-DesignStore -ProjectRoot $root -SkipIndex
        Assert-True ($result.errors.Count -eq 0) ($result.errors | ConvertTo-Json -Compress)
        Assert-True ($result.index.items[0].effective_revision -eq 1) '승인본을 찾지 못했습니다.'
        $proposal = New-TestItem 'decision-one' 2 'proposed'
        $proposal.previous_revision = 1
        $proposal.previous_sha256 = (Get-FileHash (Join-Path $root 'design/items/decision-one/0001.json')).Hash.ToLowerInvariant()
        Write-TestJson $root 'design/items/decision-one/0002.json' $proposal
        $result = Test-DesignStore -ProjectRoot $root -SkipIndex
        Assert-True ($result.errors.Count -eq 0) '새 제안이 정상적으로 연결되지 않았습니다.'
        Assert-True ($result.index.items[0].latest_revision -eq 2 -and $result.index.items[0].effective_revision -eq 1) '제안이 기존 승인본을 대체했습니다.'
    }
    Test-Case '필수 필드 누락을 Schema로 거부한다' {
        $root = New-TestStore 'schema'
        $item = New-TestItem; $item.Remove('rationale')
        Write-TestJson $root 'design/items/decision-one/0001.json' $item
        Assert-Invalid $root 'schema'
    }
    Test-Case '같은 ID·revision의 다른 경로 저장을 거부한다' {
        $root = New-TestStore 'duplicate'
        Write-TestJson $root 'design/items/other/0001.json' (New-TestItem)
        Assert-Invalid $root 'duplicate_id_revision'
    }
    Test-Case '미존재 의존 항목을 거부한다' {
        $root = New-TestStore 'reference'
        $item = New-TestItem
        $item.relations = @(@{ type = 'depends_on'; target = 'missing'; revision = $null; reason = '시험' })
        Write-TestJson $root 'design/items/decision-one/0001.json' $item
        Assert-Invalid $root 'broken_reference'
    }
    Test-Case '승인 근거가 없는 accepted를 거부한다' {
        $root = New-TestStore 'approval'
        $item = New-TestItem; $item.approval_source = $null
        Write-TestJson $root 'design/items/decision-one/0001.json' $item
        Assert-Invalid $root 'approval_required'
    }
    Test-Case '다른 revision에 대한 승인을 재사용하지 못한다' {
        $root = New-TestStore 'approval-revision'
        $item = New-TestItem 'decision-one' 2
        $item.previous_revision = 1
        $item.previous_sha256 = (Get-FileHash (Join-Path $root 'design/items/decision-one/0001.json')).Hash.ToLowerInvariant()
        Write-TestJson $root 'design/items/decision-one/0002.json' $item
        Assert-Invalid $root 'approval_scope'
    }
    Test-Case 'revision 누락과 이전 내용 변조를 검출한다' {
        $root = New-TestStore 'revision'
        $item = New-TestItem 'decision-one' 3 'proposed'
        $item.previous_revision = 2; $item.previous_sha256 = '0' * 64
        Write-TestJson $root 'design/items/decision-one/0003.json' $item
        Assert-Invalid $root 'revision_sequence'
        $root = New-TestStore 'history'
        $item.revision = 2; $item.previous_revision = 1
        Write-TestJson $root 'design/items/decision-one/0002.json' $item
        Assert-Invalid $root 'history_hash'
    }
    Test-Case '폐기된 결정에 대한 활성 의존을 거부한다' {
        $root = New-TestStore 'retired'
        $item = New-TestItem 'decision-old' 1 'rejected'
        Write-TestJson $root 'design/items/decision-old/0001.json' $item
        $current = New-TestItem
        $current.relations = @(@{ type = 'depends_on'; target = 'decision-old'; revision = $null; reason = '시험' })
        Write-TestJson $root 'design/items/decision-one/0001.json' $current
        Assert-Invalid $root 'inactive_dependency'
    }
    Test-Case '명시된 충돌은 의미 검토 경고로 보고한다' {
        $root = New-TestStore 'conflict'
        Write-TestJson $root 'design/items/decision-other/0001.json' (New-TestItem 'decision-other' 1 'proposed')
        $item = New-TestItem
        $item.relations = @(@{ type = 'conflicts_with'; target = 'decision-other'; revision = $null; reason = '판단 필요' })
        Write-TestJson $root 'design/items/decision-one/0001.json' $item
        $result = Test-DesignStore -ProjectRoot $root -SkipIndex
        Assert-True (@($result.warnings | Where-Object code -EQ 'semantic_conflict').Count -eq 1) '의미 검토 경고가 없습니다.'
    }
    Test-Case '이전 대응표의 누락 구간을 검출한다' {
        $root = New-TestStore 'migration'
        Write-TestJson $root 'design/sources/archive-test.json' @{
            schema_version = 1; id = 'archive-test'; kind = 'legacy_file'
            locator = @{ description = '합성 원문'; path = 'old.md'; commit = $null; message_id = $null; date = $null }
            content = "첫째`n둘째`n셋째"; approvals = @()
        }
        Write-TestJson $root 'design/migration-map.json' @{
            schema_version = 1; baseline_commit = $null
            files = @(@{ path = 'old.md'; source_id = 'archive-test'; line_count = 3; disposition = 'archived'
                sections = @(@{ start = 1; end = 2; ids = @('decision-one'); disposition = 'mapped'; reason = '합성 시험' }) })
        }
        Assert-Invalid $root 'migration_coverage'
    }
    Test-Case '색인은 재생성 가능하며 역참조와 오염을 검출한다' {
        $root = New-TestStore 'index'
        $item = New-TestItem 'decision-other' 1 'proposed'
        $item.relations = @(@{ type = 'related_to'; target = 'decision-one'; revision = 1; reason = '시험' })
        Write-TestJson $root 'design/items/decision-other/0001.json' $item
        $result = Test-DesignStore -ProjectRoot $root -SkipIndex
        Assert-True ($result.index.items[0].referenced_by -contains 'decision-other') '역참조가 누락됐습니다.'
        Write-TestJson $root 'design/index.json' $result.index
        Assert-True ((Test-DesignStore -ProjectRoot $root).errors.Count -eq 0) '생성한 색인이 유효하지 않습니다.'
        $item.content = '변경된 제안'
        Write-TestJson $root 'design/items/decision-other/0001.json' $item
        Assert-True (@((Test-DesignStore -ProjectRoot $root).errors | Where-Object code -EQ 'stale_index').Count -gt 0) '낡은 색인을 검출하지 못했습니다.'
    }
    Test-Case '일괄 저장은 낡은 기준점을 거부하고 원본을 보존한다' {
        $root = New-TestStore 'concurrency'
        $before = Get-DesignFingerprint -ProjectRoot $root
        $item = New-TestItem 'decision-other' 1 'proposed'
        $batch = @{ expected_fingerprint = '0' * 64; files = @(@{ path = 'items/decision-other/0001.json'; value = $item }) }
        $failed = $false
        try { Save-DesignBatch -ProjectRoot $root -Batch $batch } catch { $failed = $_.Exception.Message -match '동시 수정' }
        Assert-True $failed '동시 수정 거부가 없습니다.'
        Assert-True ((Get-DesignFingerprint -ProjectRoot $root) -eq $before) '실패한 저장이 원본을 바꿨습니다.'
        $batch.expected_fingerprint = $before
        Save-DesignBatch -ProjectRoot $root -Batch $batch
        Assert-True ((Test-DesignStore -ProjectRoot $root).errors.Count -eq 0) '일괄 저장 후 검증 실패'
    }
    Test-Case '이미 저장한 revision을 덮어쓰지 못한다' {
        $root = New-TestStore 'overwrite'
        $before = Get-DesignFingerprint -ProjectRoot $root
        $failed = $false
        try {
            Save-DesignBatch -ProjectRoot $root -Batch @{ expected_fingerprint = $before; files = @(@{ path = 'items/decision-one/0001.json'; value = (New-TestItem) }) }
        } catch { $failed = $_.Exception.Message -match '덮어' }
        Assert-True $failed '기존 이력을 덮어쓸 수 있습니다.'
        Assert-True ((Get-DesignFingerprint -ProjectRoot $root) -eq $before) '덮어쓰기 실패 뒤 데이터가 달라졌습니다.'
    }
    Test-Case '저장 경로가 설계 폴더를 벗어나면 거부한다' {
        $root = New-TestStore 'escape'
        $failed = $false
        try {
            Save-DesignBatch -ProjectRoot $root -Batch @{ expected_fingerprint = (Get-DesignFingerprint -ProjectRoot $root); files = @(@{ path = '../outside.json'; value = @{} }) }
        } catch { $failed = $_.Exception.Message -match '경로' }
        Assert-True $failed '상위 경로 이동을 허용합니다.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'outside.json'))) '설계 폴더 밖에 파일을 만들었습니다.'
    }
    Test-Case '아직 없는 파생 색인도 원본에서 처음 생성할 수 있다' {
        $root = New-TestStore 'initial-index'
        $registry = Get-Content -LiteralPath (Join-Path $root 'design/registry.json') -Raw | ConvertFrom-Json -AsHashtable
        $registry.authorities += @{ domain = '파생 색인'; path = 'design/index.json'; role = 'derived' }
        Write-TestJson $root 'design/registry.json' $registry
        $result = Test-DesignStore -ProjectRoot $root -SkipIndex
        Assert-True ($result.errors.Count -eq 0) '색인이 없다는 이유로 최초 색인을 만들지 못합니다.'
        Save-DesignBatch -ProjectRoot $root -Batch @{ expected_fingerprint = (Get-DesignFingerprint -ProjectRoot $root); files = @() }
        Assert-True ((Test-DesignStore -ProjectRoot $root).errors.Count -eq 0) '최초 색인 생성 후 오류'
    }
    Test-Case '최신 제안이 있어도 이전 승인본의 잘못된 의존을 검사한다' {
        $root = New-TestStore 'active-dependency'
        Write-TestJson $root 'design/items/decision-old/0001.json' (New-TestItem 'decision-old' 1 'rejected')
        $active = New-TestItem
        $active.relations = @(@{ type = 'depends_on'; target = 'decision-old'; revision = $null; reason = '검사 대상' })
        Write-TestJson $root 'design/items/decision-one/0001.json' $active
        $proposal = New-TestItem 'decision-one' 2 'proposed'
        $proposal.previous_revision = 1
        $proposal.previous_sha256 = (Get-FileHash (Join-Path $root 'design/items/decision-one/0001.json')).Hash.ToLowerInvariant()
        Write-TestJson $root 'design/items/decision-one/0002.json' $proposal
        Assert-Invalid $root 'inactive_dependency'
    }
    Test-Case '저장 도중 교체 실패 시 기존 파일을 복구하고 원문도 보존한다' {
        $root = New-TestStore 'interrupted-save'
        $registryPath = Join-Path $root 'design/registry.json'
        $original = [IO.File]::ReadAllText($registryPath)
        $registry = $original | ConvertFrom-Json -AsHashtable
        $registry.project_name = '저장 실패 후보'
        $guard = [IO.File]::Open((Join-Path $root 'design/work-state.json'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $failed = $false
        try {
            Save-DesignBatch -ProjectRoot $root -Batch @{ expected_fingerprint = (Get-DesignFingerprint -ProjectRoot $root); files = @(@{ path = 'registry.json'; value = $registry }) }
        } catch { $failed = $true } finally { $guard.Dispose() }
        Assert-True $failed '파일 잠금에 의한 저장 실패가 발생하지 않았습니다.'
        Assert-True ([IO.File]::ReadAllText($registryPath) -ceq $original) '실패한 저장이 기존 원본을 변경한 채 남겼습니다.'
        $pending = Get-Content -LiteralPath (Join-Path $root 'design/.pending.json') -Raw | ConvertFrom-Json -AsHashtable
        Assert-True ($pending.before_files['registry.json'] -ceq $original) '복구용 원문이 보존되지 않았습니다.'
        Assert-Invalid $root 'incomplete_save'
    }
    Test-Case '중간 결정이 폐기돼도 이전 결정이 되살아나지 않는다' {
        $root = New-TestStore 'supersession-chain'
        $sourcePath = Join-Path $root 'design/sources/source-test.json'
        $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json -AsHashtable
        $source.approvals += @(@{ id = 'decision-two'; revision = 1; scope = '중간 결정' }, @{ id = 'decision-two'; revision = 2; scope = '중간 결정 폐기' }, @{ id = 'decision-three'; revision = 1; scope = '최종 결정' })
        Write-TestJson $root 'design/sources/source-test.json' $source
        $middle = New-TestItem 'decision-two'
        $middle.relations = @(@{ type = 'supersedes'; target = 'decision-one'; revision = 1; reason = '첫 결정 대체' })
        Write-TestJson $root 'design/items/decision-two/0001.json' $middle
        $final = New-TestItem 'decision-three'
        $final.relations = @(@{ type = 'supersedes'; target = 'decision-two'; revision = 1; reason = '중간 결정 대체' })
        Write-TestJson $root 'design/items/decision-three/0001.json' $final
        $retired = New-TestItem 'decision-two' 2 'superseded'
        $retired.approval_source = 'source-test'; $retired.previous_revision = 1
        $retired.previous_sha256 = (Get-FileHash (Join-Path $root 'design/items/decision-two/0001.json')).Hash.ToLowerInvariant()
        Write-TestJson $root 'design/items/decision-two/0002.json' $retired
        $result = Test-DesignStore -ProjectRoot $root -SkipIndex
        Assert-True ($result.errors.Count -eq 0) '정상 대체 이력에 오류가 있습니다.'
        Assert-True ($null -eq ($result.index.items | Where-Object id -EQ 'decision-one').effective_revision) '과거 결정이 다시 활성화됐습니다.'
        Assert-True (($result.index.items | Where-Object id -EQ 'decision-one').referenced_by -contains 'decision-two') '여전히 적용되는 과거 대체 관계가 역참조에서 빠졌습니다.'
    }
    Test-Case '대응표에서 원문 파일 전체 누락과 중복을 검출한다' {
        $root = New-TestStore 'migration-files'
        Write-TestJson $root 'design/sources/archive-test.json' @{
            schema_version = 1; id = 'archive-test'; kind = 'legacy_file'
            locator = @{ description = '합성 원문'; path = 'old.md'; commit = $null; message_id = $null; date = $null }
            content = '기존 결정'; approvals = @()
        }
        Assert-Invalid $root 'migration_file_missing'
        $file = @{ path = 'old.md'; source_id = 'archive-test'; line_count = 1; disposition = 'archived'; sections = @(@{ start = 1; end = 1; ids = @('decision-one'); disposition = 'mapped'; reason = '시험' }) }
        Write-TestJson $root 'design/migration-map.json' @{ schema_version = 1; baseline_commit = $null; files = @($file, $file) }
        Assert-Invalid $root 'migration_file_duplicate'
    }
    Test-Case '저장 미완료 표시가 있어도 실제 참조 오류를 검사한다' {
        $root = New-TestStore 'pending-validation'
        $item = New-TestItem
        $item.relations = @(@{ type = 'depends_on'; target = 'missing-item'; revision = $null; reason = '시험' })
        Write-TestJson $root 'design/items/decision-one/0001.json' $item
        Write-TestJson $root 'design/.pending.json' @{ paths = @('items/decision-one/0001.json') }
        Assert-Invalid $root 'incomplete_save'
        Assert-Invalid $root 'broken_reference'
    }
    Test-Case '빈 boilerplate 복사본에서 이름과 목적을 기록하고 검사한다' {
        $root = Join-Path $tempRoot 'project-test'
        [void][IO.Directory]::CreateDirectory($root)
        Get-ChildItem -LiteralPath (Join-Path $repo 'boilerplate') -Force | Copy-Item -Destination $root -Recurse
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) '원본 Git 메타데이터가 복사됐습니다.'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $root 'design/sources') -File -Filter '*.json').Count -eq 0) '템플릿 관리자의 출처가 새 프로젝트에 섞였습니다.'
        $registry = Get-Content -LiteralPath (Join-Path $root 'design/registry.json') -Raw | ConvertFrom-Json -AsHashtable
        $registry.project_name = 'project-test'; $registry.purpose_id = 'requirement-test-purpose'
        $purpose = New-TestItem 'requirement-test-purpose'
        $purpose.kind = 'requirement'; $purpose.title = '프로젝트 목적'; $purpose.content = '새 프로젝트의 초기 환경을 시험한다.'
        $source = @{
            schema_version = 1; id = 'source-test'; kind = 'user_instruction'
            locator = @{ description = '합성 초기 설정 입력'; path = $null; commit = $null; message_id = $null; date = $null }
            content = '합성 시험 입력: 이름 project-test, 목적 새 프로젝트의 초기 환경 시험.'
            approvals = @(@{ id = 'requirement-test-purpose'; revision = 1; scope = '시험용 이름과 목적' })
        }
        $state = Get-Content -LiteralPath (Join-Path $root 'design/work-state.json') -Raw | ConvertFrom-Json -AsHashtable
        $state.status = 'completed'; $state.current_ids = @('requirement-test-purpose'); $state.steps[0].status = 'completed'
        $state.next_actions = @('실제 개발 환경은 다음 작업에서 확인한다.')
        Save-DesignBatch -ProjectRoot $root -Batch @{
            expected_fingerprint = (Get-DesignFingerprint -ProjectRoot $root)
            files = @(@{ path = 'registry.json'; value = $registry }, @{ path = 'sources/source-test.json'; value = $source }, @{ path = 'items/requirement-test-purpose/0001.json'; value = $purpose }, @{ path = 'work-state.json'; value = $state })
        }
        $saved = Get-Content -LiteralPath (Join-Path $root 'design/registry.json') -Raw | ConvertFrom-Json
        Assert-True ($saved.project_name -eq 'project-test' -and $saved.purpose_id -eq 'requirement-test-purpose') '이름 또는 목적 연결 저장 실패'
        & (Join-Path $PSHOME 'pwsh') -NoProfile -File (Join-Path $root '.agents/design-data/validate.ps1') -ProjectRoot $root
        Assert-True ($LASTEXITCODE -eq 0) '복사본에 포함된 검사 도구가 동작하지 않습니다.'
        Assert-True ((Test-DesignStore -ProjectRoot $root).index.items.Count -eq 1) '기존 프로젝트의 설계 항목이 섞였습니다.'
    }
    Write-Host "설계 데이터 검사: $script:passed 개 통과"
} finally {
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $allowed = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('design-data-tests-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
