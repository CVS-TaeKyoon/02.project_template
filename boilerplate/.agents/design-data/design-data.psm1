#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$script:SchemaPath = Join-Path $PSScriptRoot 'schemas/design.schema.json'

function Get-DesignRoot($ProjectRoot, $DesignPath) {
    if ($DesignPath) { return [IO.Path]::GetFullPath($DesignPath) }
    return [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'design'))
}

function Get-DesignFingerprint {
    param([Parameter(Mandatory)][string]$ProjectRoot, [string]$DesignPath)
    $root = Get-DesignRoot $ProjectRoot $DesignPath
    $lines = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' | Where-Object {
        $_.FullName -ne (Join-Path $root 'index.json') -and $_.FullName -ne (Join-Path $root '.pending.json')
    } | Sort-Object FullName | ForEach-Object {
        [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    })
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).ToLowerInvariant()
}

function Test-DesignStore {
    param([Parameter(Mandatory)][string]$ProjectRoot, [string]$DesignPath, [switch]$SkipIndex)
    $root = Get-DesignRoot $ProjectRoot $DesignPath
    $errors = [Collections.Generic.List[object]]::new()
    $warnings = [Collections.Generic.List[object]]::new()
    function Add-Problem($code, $message) { $errors.Add(@{ code = $code; message = $message }) }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Add-Problem 'missing_store' '설계 저장소가 없습니다.'
        return @{ errors = $errors.ToArray(); warnings = @(); index = $null }
    }
    if (Test-Path -LiteralPath (Join-Path $root '.pending.json')) { Add-Problem 'incomplete_save' '이전 일괄 저장이 완료되지 않았습니다. 저장 기록을 확인해야 합니다.' }
    $before = Get-DesignFingerprint -ProjectRoot $ProjectRoot -DesignPath $root
    $schema = Get-Content -LiteralPath $script:SchemaPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    $documents = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        if ($relative -in @('index.json', '.pending.json')) { continue }
        $type = switch -Regex ($relative) {
            '^items/[^/]+/[^/]+\.json$' { 'item'; break }
            '^sources/[^/]+\.json$' { 'source'; break }
            '^registry\.json$' { 'registry'; break }
            '^work-state\.json$' { 'workState'; break }
            '^migration-map\.json$' { 'migration'; break }
            default { $null }
        }
        if (-not $type) { Add-Problem 'unexpected_file' "분류되지 않은 설계 파일: $relative"; continue }
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
            $schema['$ref'] = '#/$defs/' + $type
            if (-not (Test-Json -Json $raw -Schema ($schema | ConvertTo-Json -Depth 60 -Compress) -ErrorAction SilentlyContinue)) {
                Add-Problem 'schema' "필수 필드 또는 구조 오류: $relative"; continue
            }
            $documents[$relative] = @{ value = ($raw | ConvertFrom-Json -AsHashtable); hash = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant(); type = $type }
        } catch { Add-Problem 'schema' "JSON 또는 Schema 오류: $relative" }
    }
    foreach ($required in @('registry.json', 'work-state.json', 'migration-map.json')) {
        if (-not $documents.ContainsKey($required)) { Add-Problem 'missing_file' "필수 파일이 없거나 잘못됐습니다: $required" }
    }
    # 구조가 깨진 항목에서 연쇄적인 참조 오류를 만들지 않는다.
    if (@($errors | Where-Object code -NE 'incomplete_save').Count) { return @{ errors = $errors.ToArray(); warnings = @(); index = $null } }
    $sources = @{}; $groups = @{}; $byRevision = @{}
    foreach ($path in ($documents.Keys | Sort-Object)) {
        $document = $documents[$path]; $value = $document.value
        if ($document.type -eq 'source') {
            if ($sources.ContainsKey($value.id)) { Add-Problem 'duplicate_source' "출처 ID 중복: $($value.id)" }
            if ($path -cne "sources/$($value.id).json") { Add-Problem 'source_path' "출처 ID와 경로가 다릅니다: $path" }
            $sources[$value.id] = $value
        }
        if ($document.type -ne 'item') { continue }
        $key = "$($value.id)@$($value.revision)"
        if ($byRevision.ContainsKey($key)) { Add-Problem 'duplicate_id_revision' "항목 ID·revision 중복: $key" }
        $expectedPath = 'items/{0}/{1:D4}.json' -f $value.id, [int]$value.revision
        if ($path -cne $expectedPath) { Add-Problem 'item_path' "항목 ID·revision과 경로가 다릅니다: $path" }
        $entry = @{ value = $value; hash = $document.hash; path = $path }
        $byRevision[$key] = $entry
        if (-not $groups.ContainsKey($value.id)) { $groups[$value.id] = [Collections.Generic.List[object]]::new() }
        $groups[$value.id].Add($entry)
    }
    $latest = @{}; $effective = @{}
    foreach ($id in ($groups.Keys | Sort-Object)) {
        $sequence = @($groups[$id] | Sort-Object { [int]$_.value.revision })
        $previous = $null; $active = $null
        foreach ($entry in $sequence) {
            $item = $entry.value
            $expectedRevision = if ($previous) { $previous.value.revision + 1 } else { 1 }
            if ($item.revision -ne $expectedRevision -or ($previous -and $item.previous_revision -ne $previous.value.revision) -or (-not $previous -and ($null -ne $item.previous_revision -or $null -ne $item.previous_sha256))) {
                Add-Problem 'revision_sequence' "revision 연결 오류: $id@$($item.revision)"
            }
            if ($previous -and $item.previous_sha256 -cne $previous.hash) { Add-Problem 'history_hash' "이전 내용의 해시가 다릅니다: $id@$($item.revision)" }
            if ($previous -and $item.kind -ne $previous.value.kind) { Add-Problem 'kind_change' "기존 ID의 항목 종류를 바꿀 수 없습니다: $id" }
            foreach ($sourceId in $item.source_refs) {
                if (-not $sources.ContainsKey($sourceId)) { Add-Problem 'broken_source' "출처가 없습니다: $id → $sourceId" }
            }
            if ($item.status -in @('accepted', 'superseded')) {
                if (-not $item.approval_source -or -not $sources.ContainsKey($item.approval_source)) {
                    Add-Problem 'approval_required' "명시적 승인 근거가 필요합니다: $id@$($item.revision)"
                } else {
                    $approval = $sources[$item.approval_source]
                    if ($approval.kind -notin @('user_instruction', 'user_approval') -or $item.approval_source -notin $item.source_refs -or -not @($approval.approvals | Where-Object { $_.id -ceq $id -and $_.revision -eq $item.revision }).Count) {
                        Add-Problem 'approval_scope' "승인 대상 ID·revision이 일치하지 않습니다: $id@$($item.revision)"
                    }
                }
            } elseif ($item.approval_source) { Add-Problem 'status_approval' "미승인 상태에 승인 필드가 설정됐습니다: $id" }
            if ($item.status -eq 'accepted') { $active = $entry }
            if ($item.status -eq 'superseded') { $active = $null }
            $previous = $entry
        }
        $latest[$id] = $sequence[-1]
        $effective[$id] = $active
    }
    foreach ($source in $sources.Values) {
        foreach ($approval in $source.approvals) {
            if (-not $byRevision.ContainsKey("$($approval.id)@$($approval.revision)")) { Add-Problem 'broken_approval' "승인 출처가 없는 항목을 가리킵니다: $($source.id)" }
        }
    }
    $superseders = @{}; $reverse = @{}
    foreach ($id in $groups.Keys) { $reverse[$id] = [Collections.Generic.HashSet[string]]::new() }
    foreach ($entry in $byRevision.Values) {
        foreach ($relation in $entry.value.relations) {
            if (-not $groups.ContainsKey($relation.target) -or ($null -ne $relation.revision -and -not $byRevision.ContainsKey("$($relation.target)@$($relation.revision)"))) {
                Add-Problem 'broken_reference' "관련 항목이 없습니다: $($entry.value.id) → $($relation.target)"; continue
            }
            if ($entry -eq $latest[$entry.value.id] -or $entry -eq $effective[$entry.value.id] -or ($entry.value.status -eq 'accepted' -and $relation.type -eq 'supersedes')) { [void]$reverse[$relation.target].Add($entry.value.id) }
            if ($entry.value.status -eq 'accepted' -and $relation.type -eq 'supersedes') {
                if ($superseders.ContainsKey($relation.target) -and $superseders[$relation.target] -cne $entry.value.id) { Add-Problem 'multiple_superseders' "대체 결정이 둘 이상입니다: $($relation.target)" }
                $superseders[$relation.target] = $entry.value.id
            }
        }
    }
    foreach ($id in $superseders.Keys) {
        $visited = @{}; $cursor = $id
        while ($superseders.ContainsKey($cursor)) {
            if ($visited.ContainsKey($cursor)) { Add-Problem 'supersession_cycle' "대체 관계가 순환합니다: $id"; break }
            $visited[$cursor] = $true; $cursor = $superseders[$cursor]
        }
        $effective[$id] = $null
    }
    foreach ($id in $groups.Keys) {
        if ($latest[$id].value.status -eq 'superseded' -and -not $superseders.ContainsKey($id)) { Add-Problem 'supersession_missing' "대체 결정을 찾지 못했습니다: $id" }
        $reviewEntries = @($latest[$id])
        if ($effective[$id] -and $effective[$id].value.revision -ne $latest[$id].value.revision) { $reviewEntries += $effective[$id] }
        foreach ($entry in $reviewEntries) {
            foreach ($relation in $entry.value.relations) {
                if (-not $groups.ContainsKey($relation.target)) { continue }
                if ($entry -eq $effective[$id] -and $relation.type -eq 'depends_on') {
                    if (-not $effective[$relation.target]) { Add-Problem 'inactive_dependency' "활성 결정이 미승인·폐기된 항목에 의존합니다: $id → $($relation.target)" }
                    elseif ($null -ne $relation.revision -and $relation.revision -ne $effective[$relation.target].value.revision) {
                        Add-Problem 'outdated_dependency' "의존한 revision이 현재 승인본과 다릅니다: $id → $($relation.target)"
                    }
                }
                if ($relation.type -eq 'conflicts_with') { $warnings.Add(@{ code = 'semantic_conflict'; message = "의미 검토 필요: $id ↔ $($relation.target): $($relation.reason)" }) }
            }
        }
    }
    $registry = $documents['registry.json'].value; $state = $documents['work-state.json'].value
    foreach ($id in @($registry.global_constraints.item_ids) + @($state.current_ids) + @($state.open_ids) + @($registry.purpose_id) | Where-Object { $_ }) {
        if (-not $groups.ContainsKey($id)) { Add-Problem 'broken_reference' "원본 목록 또는 작업 상태의 항목이 없습니다: $id" }
    }
    foreach ($id in $registry.global_constraints.item_ids) {
        if ($groups.ContainsKey($id) -and -not $effective[$id]) { Add-Problem 'inactive_global' "공통 제약의 승인본이 없습니다: $id" }
    }
    $domains = @{}
    foreach ($authority in $registry.authorities) {
        if ($authority.role -eq 'canonical') {
            if ($domains.ContainsKey($authority.domain)) { Add-Problem 'duplicate_authority' "기준 원본이 둘입니다: $($authority.domain)" }
            $domains[$authority.domain] = $true
        }
    }
    foreach ($path in @($registry.global_constraints.paths) + @($registry.authorities | Where-Object role -NE 'archive' | ForEach-Object path)) {
        if ($SkipIndex -and $path -eq 'design/index.json') { continue }
        if ([IO.Path]::IsPathRooted($path) -or $path -match '(^|[/\\])\.\.([/\\]|$)') { Add-Problem 'authority_path' "원본 경로는 프로젝트 안의 상대 경로여야 합니다: $path"; continue }
        # 새로 추가되는 설계 파일은 일괄 저장 후보에서 검사한다.
        $target = if ($path -match '^design[/\\]') { Join-Path $root $path.Substring(7) } else { Join-Path $ProjectRoot $path }
        if (-not (Test-Path -LiteralPath $target)) { Add-Problem 'authority_missing' "기준 원본 경로가 없습니다: $path" }
    }
    $mappedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $mappedSources = [Collections.Generic.HashSet[string]]::new()
    foreach ($file in $documents['migration-map.json'].value.files) {
        if (-not $mappedPaths.Add($file.path) -or -not $mappedSources.Add($file.source_id)) { Add-Problem 'migration_file_duplicate' "원문 파일이 중복 대응됐습니다: $($file.path)" }
        if (-not $sources.ContainsKey($file.source_id)) { Add-Problem 'migration_source' "이전 원문이 없습니다: $($file.path)"; continue }
        $source = $sources[$file.source_id]
        if ($source.kind -ne 'legacy_file' -or $source.locator.path -cne $file.path) { Add-Problem 'migration_source' "이전 원문 위치가 다릅니다: $($file.path)" }
        $lineCount = $source.content.TrimEnd("`r", "`n").Split("`n").Count
        if ($file.line_count -ne $lineCount) { Add-Problem 'migration_coverage' "원문 줄 수가 다릅니다: $($file.path)" }
        $next = 1
        foreach ($section in ($file.sections | Sort-Object start)) {
            if ($section.start -ne $next -or $section.end -lt $section.start -or $section.end -gt $lineCount) { Add-Problem 'migration_coverage' "대응표 누락·중복 구간: $($file.path):$next" }
            if ($section.disposition -eq 'mapped' -and -not $section.ids.Count) { Add-Problem 'migration_coverage' "대응 ID가 비었습니다: $($file.path):$next" }
            foreach ($id in $section.ids) { if (-not $groups.ContainsKey($id)) { Add-Problem 'broken_reference' "대응표의 ID가 없습니다: $id" } }
            $next = $section.end + 1
        }
        if ($next -ne $lineCount + 1) { Add-Problem 'migration_coverage' "대응표 끝에 누락이 있습니다: $($file.path)" }
    }
    foreach ($source in $sources.Values | Where-Object kind -EQ 'legacy_file') {
        if (-not $mappedSources.Contains($source.id)) { Add-Problem 'migration_file_missing' "대응표에서 원문 파일이 빠졌습니다: $($source.locator.path)" }
    }
    $indexItems = @(
        foreach ($id in ($groups.Keys | Sort-Object)) {
            $last = $latest[$id]; $active = $effective[$id]
            [ordered]@{ id = $id; title = $last.value.title; kind = $last.value.kind; status = $(if ($superseders.ContainsKey($id)) { 'superseded' } else { $last.value.status }); latest_revision = $last.value.revision; effective_revision = $(if ($active) { $active.value.revision } else { $null }); path = 'design/' + $last.path; effective_path = $(if ($active) { 'design/' + $active.path } else { $null }); referenced_by = @($reverse[$id] | Sort-Object) }
        }
    )
    $after = Get-DesignFingerprint -ProjectRoot $ProjectRoot -DesignPath $root
    if ($before -cne $after) { Add-Problem 'concurrent_change' '검사 중 원본이 바뀌었습니다. 최신 상태를 다시 조회해야 합니다.' }
    $index = [ordered]@{ schema_version = 1; derived = $true; fingerprint = $after; items = $indexItems }
    if (-not $SkipIndex) {
        try {
            $rawIndex = Get-Content -LiteralPath (Join-Path $root 'index.json') -Raw -Encoding utf8
            $schema['$ref'] = '#/$defs/index'
            if (-not (Test-Json -Json $rawIndex -Schema ($schema | ConvertTo-Json -Depth 60 -Compress) -ErrorAction SilentlyContinue)) { throw '색인 구조 오류' }
            $stored = $rawIndex | ConvertFrom-Json
            if (($stored | ConvertTo-Json -Depth 50 -Compress) -cne ($index | ConvertTo-Json -Depth 50 -Compress)) { Add-Problem 'stale_index' '색인이 원본과 다릅니다. 원본 검증 후 재생성해야 합니다.' }
        } catch { Add-Problem 'stale_index' '유효한 파생 색인이 없습니다.' }
    }
    return @{ errors = $errors.ToArray(); warnings = $warnings.ToArray(); index = $index }
}

function Save-DesignBatch {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][System.Collections.IDictionary]$Batch)
    $project = [IO.Path]::GetFullPath($ProjectRoot)
    $root = Get-DesignRoot $project $null
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('design-data-stage-' + [guid]::NewGuid())
    $lock = $null
    try {
        try { $lock = [IO.FileStream]::new((Join-Path $project '.design-data.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose) }
        catch { throw '동시 수정 잠금을 얻지 못했습니다. 다른 저장 작업이 끝난 뒤 최신 원본을 확인하세요.' }
        if ((Get-DesignFingerprint -ProjectRoot $project) -cne $Batch.expected_fingerprint) { throw '동시 수정 감지: 읽었던 원본과 현재 원본이 다릅니다. 저장하지 않았습니다.' }
        if (Test-Path -LiteralPath (Join-Path $root '.pending.json')) { throw '이전 저장이 미완료 상태입니다. .pending.json 기록부터 확인하세요.' }
        [void][IO.Directory]::CreateDirectory($stage)
        Get-ChildItem -LiteralPath $root -Force | Copy-Item -Destination $stage -Recurse
        $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $Batch.files) {
            $path = [string]$file.path
            if ($path -notmatch '^(items/[a-z][a-z0-9-]{2,100}/[0-9]{4,}\.json|sources/[a-z][a-z0-9-]{2,100}\.json|registry\.json|work-state\.json|migration-map\.json)$') { throw "허용되지 않은 저장 경로: $path" }
            if (-not $paths.Add($path)) { throw "중복 저장 경로: $path" }
            $target = Join-Path $root $path
            $cursor = Split-Path -Parent $target
            while ($cursor.Length -ge $root.Length) {
                if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "연결된 폴더 경로에는 저장하지 않습니다: $path" }
                $cursor = Split-Path -Parent $cursor
            }
            if ($path -match '^(items|sources)/' -and (Test-Path -LiteralPath $target)) { throw "기존 원본을 덮어쓸 수 없습니다: $path" }
            $candidate = Join-Path $stage $path
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $candidate))
            [IO.File]::WriteAllText($candidate, ($file.value | ConvertTo-Json -Depth 60) + "`n", [Text.UTF8Encoding]::new($false))
        }
        $result = Test-DesignStore -ProjectRoot $project -DesignPath $stage -SkipIndex
        if ($result.errors.Count) { throw ('후보 검증 실패: ' + (($result.errors | ForEach-Object { $_.code + ': ' + $_.message }) -join '; ')) }
        $stateFile = Join-Path $stage 'work-state.json'
        $state = Get-Content -LiteralPath $stateFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $state.validation.structural = 'passed'
        # 구조 검증으로 의미 검토 완료를 만들어 내지 않는다.
        [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Depth 60) + "`n", [Text.UTF8Encoding]::new($false))
        [void]$paths.Add('work-state.json')
        $result = Test-DesignStore -ProjectRoot $project -DesignPath $stage -SkipIndex
        if ($result.errors.Count) { throw '작업 상태 반영 후 후보 검증에 실패했습니다.' }
        [IO.File]::WriteAllText((Join-Path $stage 'index.json'), ($result.index | ConvertTo-Json -Depth 60) + "`n", [Text.UTF8Encoding]::new($false))
        if ((Get-DesignFingerprint -ProjectRoot $project) -cne $Batch.expected_fingerprint) { throw '동시 수정 감지: 후보 검증 중 원본이 바뀌어 저장하지 않았습니다.' }
        $pending = Join-Path $root '.pending.json'
        $beforeFiles = @{}
        $publishPaths = @($paths | Sort-Object) + @('index.json')
        foreach ($path in $publishPaths) {
            $target = Join-Path $root $path
            if (Test-Path -LiteralPath $target) { $beforeFiles[$path] = [IO.File]::ReadAllText($target) }
        }
        [IO.File]::WriteAllText($pending, (@{ expected_fingerprint = $Batch.expected_fingerprint; candidate_fingerprint = $result.index.fingerprint; paths = $publishPaths; before_files = $beforeFiles } | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $published = [Collections.Generic.List[string]]::new()
        try {
            foreach ($path in $publishPaths) {
                $target = Join-Path $root $path
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
                if ($path -match '^(items|sources)/') { [IO.File]::Copy((Join-Path $stage $path), $target, $false) }
                else {
                    $swap = $target + '.new-' + [guid]::NewGuid()
                    try {
                        [IO.File]::Copy((Join-Path $stage $path), $swap, $false)
                        [IO.File]::Move($swap, $target, $true)
                    } finally { if (Test-Path -LiteralPath $swap) { [IO.File]::Delete($swap) } }
                }
                $published.Add($path)
            }
            if ((Get-DesignFingerprint -ProjectRoot $project) -cne $result.index.fingerprint) { throw '저장 중 원본이 달라졌습니다.' }
            $saved = Test-DesignStore -ProjectRoot $project
            if (@($saved.errors | Where-Object code -NE 'incomplete_save').Count) { throw '저장 후 재조회 검증에 실패했습니다.' }
            [IO.File]::Delete($pending)
        } catch {
            # 이번 호출이 교체한 내용만 되돌린다. 다른 작성자가 바꾼 파일은 덮어쓰지 않는다.
            foreach ($path in $published) {
                if (-not $beforeFiles.ContainsKey($path)) { continue }
                $target = Join-Path $root $path
                try {
                    if ([IO.File]::ReadAllText($target) -ceq [IO.File]::ReadAllText((Join-Path $stage $path))) {
                        $restore = $target + '.restore-' + [guid]::NewGuid()
                        try {
                            [IO.File]::WriteAllText($restore, $beforeFiles[$path], [Text.UTF8Encoding]::new($false))
                            [IO.File]::Move($restore, $target, $true)
                        } finally { if (Test-Path -LiteralPath $restore) { [IO.File]::Delete($restore) } }
                    }
                } catch { } # 자동 복구에 실패해도 pending의 원문은 남아 있다.
            }
            throw '일괄 저장이 완료되지 않았습니다. 기존 원문을 .pending.json에 보존하고 가능한 파일을 복구했습니다. 저장 기록과 현재 상태를 대조하세요.'
        }
    } finally {
        if ($lock) { $lock.Dispose() }
        $resolved = [IO.Path]::GetFullPath($stage)
        $allowed = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('design-data-stage-') -and (Test-Path -LiteralPath $resolved)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

Export-ModuleMember -Function Test-DesignStore, Get-DesignFingerprint, Save-DesignBatch
