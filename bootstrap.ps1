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

# ---------- 4. Env vars in PowerShell $PROFILE ----------
if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Force -Path $PROFILE | Out-Null
}

$marker = "# Claude Code per-machine paths (managed by bootstrap.ps1)"
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $profileContent) { $profileContent = "" }

if ($profileContent -notmatch [regex]::Escape($marker)) {
  $block = @"

$marker
`$env:CLAUDE_CONFIG_DIR = '$ConfigDir'
`$env:PROJECTS_DIR      = '$ProjectsDir'
`$env:OBSIDIAN_DIR      = '$ObsidianDir'
`$env:AGENT_TEAM_DIR    = '$AgentTeamDir'
"@
  Add-Content $PROFILE $block
  Write-Host "[bootstrap] env vars appended to $PROFILE"
} else {
  Write-Host "[bootstrap] env vars already in $PROFILE — skipping"
}

# ---------- 5. Also set User-scope env vars (so non-PS apps see them) ----------
[Environment]::SetEnvironmentVariable("CLAUDE_CONFIG_DIR", $ConfigDir,    "User")
[Environment]::SetEnvironmentVariable("PROJECTS_DIR",     $ProjectsDir,   "User")
[Environment]::SetEnvironmentVariable("OBSIDIAN_DIR",     $ObsidianDir,   "User")
[Environment]::SetEnvironmentVariable("AGENT_TEAM_DIR",   $AgentTeamDir,  "User")
Write-Host "[bootstrap] User env vars set (Windows-wide)"

# ---------- 6. Final hint ----------
Write-Host ""
Write-Host "[bootstrap] done. Next steps:"
Write-Host "  1. restart PowerShell / Claude Code"
Write-Host "  2. install Claude Code if missing:  npm i -g @anthropic-ai/claude-code"
Write-Host "  3. login:  claude login"
Write-Host "  4. MCP auth:  in claude run  /mcp"
