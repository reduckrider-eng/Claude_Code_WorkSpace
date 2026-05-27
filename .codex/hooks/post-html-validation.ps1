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

function Get-WorkingRoot {
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

function Test-IndexTouched {
    param(
        $Payload,
        [string]$Root
    )

    if ($Payload -and $Payload.tool_input) {
        $toolInput = $Payload.tool_input | ConvertTo-Json -Compress -Depth 20
        if ($toolInput -match "(^|[\\/])index\.html|index\.html") {
            return $true
        }
    }

    $repoRoot = Get-RepoRoot
    if ($repoRoot) {
        $status = (& git -C $repoRoot status --porcelain -- index.html 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
            return $true
        }
    }

    return $false
}

function Test-HtmlStructure {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "index.html does not exist"
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $missing = @()
    if ($content -notmatch "(?i)<html\b") { $missing += "<html" }
    if ($content -notmatch "(?i)<head\b") { $missing += "<head" }
    if ($content -notmatch "(?i)<body\b") { $missing += "<body" }

    if ($missing.Count -gt 0) {
        return "index.html missing required tag(s): $($missing -join ', ')"
    }

    return $null
}

$payload = Get-Payload
$root = Get-WorkingRoot -Payload $payload
Write-HookLog -Root $root -Message "[HOOK] PostToolUse html validation started"

try {
    if (-not (Test-IndexTouched -Payload $payload -Root $root)) {
        Write-HookLog -Root $root -Message "[HOOK] PostToolUse skipped: index.html not changed"
        Write-HookJson @{ success = $true; status = "skip"; reason = "index.html not changed" }
        exit 0
    }

    $indexPath = Join-Path $root "index.html"
    $failure = Test-HtmlStructure -Path $indexPath
    if ($failure) {
        Write-HookLog -Root $root -Message "[HOOK] PostToolUse failed: $failure"
        Write-HookJson @{ decision = "block"; reason = $failure }
        exit 0
    }

    Write-HookLog -Root $root -Message "[HOOK] PostToolUse passed: index.html basic structure valid"
    Write-HookJson @{ success = $true; status = "success"; reason = "index.html basic structure valid" }
    exit 0
} catch {
    $message = "PostToolUse hook error: $($_.Exception.Message)"
    Write-HookLog -Root $root -Message "[HOOK] PostToolUse failed: $message"
    Write-HookJson @{ decision = "block"; reason = $message }
    exit 0
}
