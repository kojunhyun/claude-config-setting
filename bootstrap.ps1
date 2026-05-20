# Claude Config bootstrap — Windows (PowerShell)
# Idempotent. Run after git clone or git pull.
#
# Usage:
#   .\bootstrap.ps1                                    # use default D:\00_Claude_Config
#   .\bootstrap.ps1 -ConfigDir 'C:\path\to\repo'       # custom location
#
# No admin required (uses mklink /J junctions).
# CLAUDE.md uses copy fallback unless Developer Mode is on.

param(
  [string]$ConfigDir   = "",
  [string]$ProjectsDir = "D:\00_Project",
  [string]$ObsidianDir = "D:\obsidian",
  [string]$AgentTeamDir = "D:\00_Agent_Team"
)

$ErrorActionPreference = "Stop"

# ---------- Resolve config dir ----------
if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
  # Default: script's own directory
  $ConfigDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$ConfigDir = (Resolve-Path $ConfigDir).Path

Write-Host "[bootstrap] CLAUDE_CONFIG_DIR = $ConfigDir"
Write-Host "[bootstrap] PROJECTS_DIR      = $ProjectsDir"
Write-Host "[bootstrap] OBSIDIAN_DIR      = $ObsidianDir"
Write-Host "[bootstrap] AGENT_TEAM_DIR    = $AgentTeamDir"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"

# ---------- 1. Ensure dirs ----------
foreach ($d in @($ClaudeDir, $ProjectsDir, $ObsidianDir, $AgentTeamDir)) {
  if (-not (Test-Path $d)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Write-Host "[bootstrap] created $d"
  }
}

# ---------- 2. Junctions for dirs ----------
function New-Junction-Safe {
  param([string]$Source, [string]$Link)
  if (Test-Path $Link) {
    $item = Get-Item $Link -Force -ErrorAction SilentlyContinue
    $isLink = $false
    if ($null -ne $item) {
      $attrs = $item.Attributes
      if (($attrs -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint) {
        $isLink = $true
      }
    }
    if ($isLink) {
      cmd /c rmdir "$Link" 2>$null | Out-Null
    } else {
      $backup = "$Link.bak-$([int][double]::Parse((Get-Date -UFormat %s)))"
      Write-Host "[bootstrap] backing up existing $Link -> $backup"
      Move-Item $Link $backup
    }
  }
  cmd /c mklink /J "$Link" "$Source" | Out-Null
  Write-Host "[bootstrap] junction $Link -> $Source"
}

foreach ($name in @("agents","commands","skills","templates")) {
  $src  = Join-Path $ConfigDir $name
  $link = Join-Path $ClaudeDir $name
  if (Test-Path $src) {
    New-Junction-Safe -Source $src -Link $link
  } else {
    Write-Warning "[bootstrap] source missing: $src"
  }
}

# ---------- 3. CLAUDE.md (symlink if possible, else copy) ----------
$claudeMdSrc  = Join-Path $ConfigDir "CLAUDE.md"
$claudeMdLink = Join-Path $ClaudeDir "CLAUDE.md"

if (Test-Path $claudeMdSrc) {
  if (Test-Path $claudeMdLink) {
    Remove-Item $claudeMdLink -Force
  }
  # Try symlink (requires Developer Mode or admin)
  $symlinked = $false
  try {
    cmd /c mklink "$claudeMdLink" "$claudeMdSrc" 2>$null | Out-Null
    if (Test-Path $claudeMdLink) { $symlinked = $true }
  } catch { $symlinked = $false }

  if (-not $symlinked) {
    Copy-Item $claudeMdSrc $claudeMdLink -Force
    Write-Host "[bootstrap] CLAUDE.md copied (no Developer Mode — symlink unavailable)"
    Write-Host "[bootstrap]   tip: after 'git pull', re-run this script to refresh CLAUDE.md"
  } else {
    Write-Host "[bootstrap] CLAUDE.md symlinked"
  }
}

# ---------- 4. Env vars in PowerShell $PROFILE (replace block if exists) ----------
if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Force -Path $PROFILE | Out-Null
}

$marker    = "# Claude Code per-machine paths (managed by bootstrap.ps1)"
$endMarker = "# /Claude Code per-machine paths"
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $profileContent) { $profileContent = "" }

# Strip any existing block
if ($profileContent -match [regex]::Escape($marker)) {
  $pattern = "(?ms)" + [regex]::Escape($marker) + ".*?" + [regex]::Escape($endMarker) + "\r?\n?"
  $profileContent = [regex]::Replace($profileContent, $pattern, "")
  Set-Content $PROFILE $profileContent -NoNewline
  Write-Host "[bootstrap] removed old env vars block from $PROFILE"
}

$block = @"

$marker
`$env:CLAUDE_CONFIG_DIR = '$ConfigDir'
`$env:PROJECTS_DIR      = '$ProjectsDir'
`$env:OBSIDIAN_DIR      = '$ObsidianDir'
`$env:AGENT_TEAM_DIR    = '$AgentTeamDir'
# Auto-source shared + machine-local env files (Bash-style KEY=value)
foreach (`$_f in @("`$env:CLAUDE_CONFIG_DIR\paths.env","`$env:CLAUDE_CONFIG_DIR\paths.local.env")) {
  if (Test-Path `$_f) {
    Get-Content `$_f | ForEach-Object {
      `$line = `$_.Trim()
      if (`$line -and -not `$line.StartsWith('#') -and `$line.Contains('=')) {
        `$i = `$line.IndexOf('=')
        `$k = `$line.Substring(0, `$i).Trim()
        `$v = `$line.Substring(`$i + 1).Trim()
        if (`$v.Length -ge 2 -and ((`$v[0] -eq '"' -and `$v[-1] -eq '"') -or (`$v[0] -eq "'" -and `$v[-1] -eq "'"))) {
          `$v = `$v.Substring(1, `$v.Length - 2)
        }
        if (`$v) { Set-Item -Path "env:`$k" -Value `$v }
      }
    }
  }
}
$endMarker
"@
Add-Content $PROFILE $block
Write-Host "[bootstrap] env vars written to $PROFILE"

# ---------- 5. Also set User-scope env vars (so non-PS apps see them) ----------
[Environment]::SetEnvironmentVariable("CLAUDE_CONFIG_DIR", $ConfigDir,    "User")
[Environment]::SetEnvironmentVariable("PROJECTS_DIR",     $ProjectsDir,   "User")
[Environment]::SetEnvironmentVariable("OBSIDIAN_DIR",     $ObsidianDir,   "User")
[Environment]::SetEnvironmentVariable("AGENT_TEAM_DIR",   $AgentTeamDir,  "User")
Write-Host "[bootstrap] User env vars set (Windows-wide)"

# ---------- 5a-2. Auto-init paths.local.env with machine-id ----------
$localEnv = Join-Path $ConfigDir "paths.local.env"
if (-not (Test-Path $localEnv)) {
  $hn = [System.Environment]::MachineName.ToLower() -replace '[^a-z0-9-]','-'
  $us = $env:USERNAME.ToLower()             -replace '[^a-z0-9-]','-'
  if (-not $hn) { $hn = "unknown" }
  if (-not $us) { $us = "user" }
  $defaultMid = "$us-$hn"
  $localContent = @"
# paths.local.env -- machine-specific overrides + SECRETS (NOT git tracked)
# bootstrap 이 처음 실행할 때 hostname-user 조합으로 초기화.
#
# WARNING: secret token 을 담는 파일이므로 외부 노출 금지.

# 이 머신의 고유 식별자
CLAUDE_MACHINE_ID=$defaultMid

# weekly 통합 leader 여부 (메인 머신만 true)
CLAUDE_WEEKLY_LEADER=

# --- Notion Integration Token (워크스페이스별 secret) -----
# 발급 절차는 SETUP.md "Notion Integration Token 셋업" 참고.
CLAUDE_LOG_NOTION_PERSONAL_TOKEN=
CLAUDE_LOG_NOTION_WORK_TOKEN=
# CLAUDE_LOG_NOTION_DEFAULT_TOKEN=

# --- 머신별 경로 오버라이드 (선택) ---
# CLAUDE_LOG_OBS_DAILY=
# CLAUDE_LOG_OBS_WEEKLY=
"@
  Set-Content $localEnv $localContent -Encoding UTF8
  Write-Host "[bootstrap] created $localEnv with CLAUDE_MACHINE_ID=$defaultMid"
  Write-Host "[bootstrap]   tip: edit $localEnv  to rename or set CLAUDE_WEEKLY_LEADER=true on leader"
} else {
  Write-Host "[bootstrap] paths.local.env already exists -- preserved"
}

# ---------- 5b. Enable git hooks ----------
if ((Test-Path (Join-Path $ConfigDir ".git")) -and (Test-Path (Join-Path $ConfigDir "hooks"))) {
  Push-Location $ConfigDir
  git config core.hooksPath hooks | Out-Null
  Pop-Location
  Write-Host "[bootstrap] git hooks enabled (core.hooksPath = hooks)"
}

# ---------- 5c. Install plugins from plugins.manifest ----------
$manifest = Join-Path $ConfigDir "plugins.manifest"
if (Test-Path $manifest) {
  $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
  if ($claudeCmd) {
    Write-Host "[bootstrap] syncing plugins from $manifest"
    foreach ($raw in Get-Content $manifest) {
      $line = $raw.Trim()
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if ($line.StartsWith("#")) { continue }

      $parts = $line -split '\s+', 2
      if ($parts.Count -lt 2) { continue }
      $action = $parts[0]
      $arg    = $parts[1].Trim()
      if ([string]::IsNullOrWhiteSpace($arg)) { continue }

      switch ($action) {
        "market" {
          Write-Host "[bootstrap]   market add: $arg"
          try {
            & claude plugin marketplace add $arg 2>&1 | ForEach-Object { Write-Host "[bootstrap]     $_" }
          } catch {
            Write-Host "[bootstrap]     WARN: marketplace add failed: $arg"
          }
        }
        "plugin" {
          Write-Host "[bootstrap]   plugin install: $arg"
          try {
            & claude plugin install $arg 2>&1 | ForEach-Object { Write-Host "[bootstrap]     $_" }
          } catch {
            Write-Host "[bootstrap]     WARN: install failed: $arg"
          }
        }
        default {
          Write-Host "[bootstrap]   WARN: unknown manifest action '$action' — skipped"
        }
      }
    }
    Write-Host "[bootstrap] plugin sync done. Run 'claude plugin list' to verify."
  } else {
    Write-Host "[bootstrap] SKIP: 'claude' CLI not found — install it first, then re-run bootstrap"
    Write-Host "[bootstrap]       (or run /sync-plugins inside Claude Code later)"
  }
}

# ---------- 6. Final hint ----------
Write-Host ""
Write-Host "[bootstrap] done. Next steps:"
Write-Host "  1. restart PowerShell / Claude Code"
Write-Host "  2. install Claude Code if missing:  npm i -g @anthropic-ai/claude-code"
Write-Host "  3. login:  claude login"
Write-Host "  4. MCP auth:  in claude run  /mcp"
