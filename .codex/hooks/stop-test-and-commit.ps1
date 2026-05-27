$ErrorActionPreference = "Stop"

function Write-HookJson {
    param([hashtable]$Data)
    Write-Output ($Data | ConvertTo-Json -Compress -Depth 8)
}

function Get-Payload {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    try {
        return $raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-RepoRoot {
    try {
        $root = (& git rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root)) {
            return ($root | Select-Object -First 1).Trim()
        }
    } catch {
    }

    return $null
}

function Get-LogRoot {
    param($Payload)

    $repoRoot = Get-RepoRoot
    if ($repoRoot) {
        return $repoRoot
    }

    if ($Payload -and $Payload.cwd) {
        return [string]$Payload.cwd
    }

    return (Get-Location).Path
}

function Write-HookLog {
    param(
        [string]$Root,
        [string]$Message
    )

    $logDir = Join-Path $Root ".codex\hooks"
    $logPath = Join-Path $logDir "hook.log"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$timestamp $Message"
}

function Block-Stop {
    param(
        [string]$Root,
        [string]$Reason
    )

    Write-HookLog -Root $Root -Message "[HOOK] Stop blocked: $Reason"
    Write-HookJson @{
        continue = $false
        stopReason = "BLOCKED: $Reason"
        systemMessage = "BLOCKED: $Reason"
    }
}

function Get-ChangedFiles {
    param([string]$Root)

    $tracked = @()
    $tracked += & git -C $Root diff --name-only --cached
    $tracked += & git -C $Root diff --name-only
    $tracked += & git -C $Root ls-files --others --exclude-standard
    return $tracked | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
}

function Test-AllowedFile {
    param([string]$Path)

    $normalized = $Path -replace "\\", "/"
    if ($normalized -eq ".codex/hooks.json") {
        return $true
    }
    if ($normalized -like ".codex/hooks/*") {
        return $true
    }
    if ($normalized -match "\.html$") {
        return $true
    }
    if ($normalized -match "\.py$") {
        return $true
    }

    return $false
}

function Test-HtmlStructure {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "HTML file does not exist: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $missing = @()
    if ($content -notmatch "(?i)<html\b") { $missing += "<html" }
    if ($content -notmatch "(?i)<head\b") { $missing += "<head" }
    if ($content -notmatch "(?i)<body\b") { $missing += "<body" }

    if ($missing.Count -gt 0) {
        return "$Path missing required tag(s): $($missing -join ', ')"
    }

    return $null
}

function Test-PythonCompile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "Python file does not exist: $Path"
    }

    try {
        $compileOutput = & python -m py_compile $Path 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "python compile failed for ${Path}: $($compileOutput -join ' ')"
        }
    } catch {
        return "python compile failed for ${Path}: $($_.Exception.Message)"
    }

    return $null
}

$payload = Get-Payload
$logRoot = Get-LogRoot -Payload $payload
Write-HookLog -Root $logRoot -Message "[HOOK] Stop test and commit started"

try {
    $repoRoot = Get-RepoRoot
    if (-not $repoRoot) {
        Block-Stop -Root $logRoot -Reason "not a git repository"
        exit 0
    }

    $status = & git -C $repoRoot status --porcelain
    if ([string]::IsNullOrWhiteSpace(($status -join "`n"))) {
        Write-HookLog -Root $repoRoot -Message "[HOOK] Stop skipped: no changes"
        Write-HookJson @{ continue = $true }
        exit 0
    }

    $userName = (& git -C $repoRoot config --get user.name 2>$null)
    $userEmail = (& git -C $repoRoot config --get user.email 2>$null)
    if ([string]::IsNullOrWhiteSpace(($userName -join "`n")) -or [string]::IsNullOrWhiteSpace(($userEmail -join "`n"))) {
        Block-Stop -Root $repoRoot -Reason "git user.name or user.email is not configured"
        exit 0
    }

    $deleted = $status | Where-Object { $_.Length -ge 3 -and $_.Substring(0, 2) -match "D" }
    if ($deleted.Count -gt 0) {
        Block-Stop -Root $repoRoot -Reason "deleted files are not allowed for auto commit: $($deleted -join '; ')"
        exit 0
    }

    $changedFiles = Get-ChangedFiles -Root $repoRoot
    $blockedFiles = $changedFiles | Where-Object { -not (Test-AllowedFile -Path $_) }
    if ($blockedFiles.Count -gt 0) {
        Block-Stop -Root $repoRoot -Reason "changed files outside allowed range: $($blockedFiles -join ', ')"
        exit 0
    }

    foreach ($file in $changedFiles) {
        $fullPath = Join-Path $repoRoot $file
        if ($file -match "\.html$") {
            $failure = Test-HtmlStructure -Path $fullPath
            if ($failure) {
                Block-Stop -Root $repoRoot -Reason $failure
                exit 0
            }
        } elseif ($file -match "\.py$") {
            $failure = Test-PythonCompile -Path $fullPath
            if ($failure) {
                Block-Stop -Root $repoRoot -Reason $failure
                exit 0
            }
        }
    }

    $addOutput = & git -C $repoRoot add . 2>&1
    if ($LASTEXITCODE -ne 0) {
        Block-Stop -Root $repoRoot -Reason "git add failed: $($addOutput -join ' ')"
        exit 0
    }

    $commitOutput = & git -C $repoRoot commit -m "auto: Codex generated update" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Block-Stop -Root $repoRoot -Reason "git commit failed: $($commitOutput -join ' ')"
        exit 0
    }

    $commitHash = (& git -C $repoRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
    Write-HookLog -Root $repoRoot -Message "[HOOK] Stop committed: $commitHash"
    Write-HookJson @{ continue = $true }
    exit 0
} catch {
    Block-Stop -Root $logRoot -Reason "Stop hook error: $($_.Exception.Message)"
    exit 0
}
