# CONTRIBUTING.md

This file provides guidance to Claude Code (claude.ai/code) when working **in this repository** — i.e. editing the config itself (skills, agents, commands, bootstrap, hooks).

> `CLAUDE.md` in this repo is **not** a repo guide — it is the **Arch orchestrator persona**, symlinked to `~/.claude/CLAUDE.md` and loaded as the global system prompt for *every* project on the machine. Do not overwrite it with repo-mechanics docs. Edit it only to change Arch's global behavior, knowing the change ships to all projects. Repo-working guidance lives here instead.

## What this repo is

A **git-managed Claude Code configuration**, not an application. There is no build, no test runner, no package to compile. "Correctness" means: the symlinks resolve, the frontmatter parses, paths stay env-var-relative, and no secrets are committed. The repo is cloned to a per-OS location and `bootstrap` wires `~/.claude/{agents,commands,skills,templates}` + `CLAUDE.md` to it.

## The symlink model — read before editing anything

On macOS/Linux/WSL, `~/.claude/{agents,commands,skills,templates,CLAUDE.md}` are **symlinks into this repo**. Consequences:

- **Editing a file here changes the live config immediately** — there is no install step for content edits.
- **New** skills/agents/commands require a **Claude Code restart** to be registered (the directory listing is read at startup). Edits to *existing* files take effect without restart.
- On **Windows (Dev Mode off)**, `CLAUDE.md` is a **copy**, not a symlink. The `post-merge` hook re-copies it after every pull; a bare file edit on Windows won't propagate until pull or re-bootstrap.

## Cross-machine workflow (this IS the "build/deploy" loop)

Changes propagate machine→machine through git, not a daemon:

```
edit files here  →  /config-push   (commit + push, with secret scan)
other machine    →  /config-sync   (pull --rebase + change summary)  →  restart Claude Code
```

- `/config-push` (skill `skills/config-push/`) — scans for secret patterns, auto-generates a commit message, `pull --rebase --autostash`, pushes. Aborts on any secret hit or rebase conflict. Runs hourly via `/schedule` on each machine, so a manual edit left uncommitted will be picked up automatically (safety net, not a substitute for intentional commits on large changes).
- `/config-sync` — pull side, prints what changed and reminds about restart.
- Direct `git commit && git push` is fine; the next auto-push is then a no-op.

## Anatomy of a feature (command + skill, optionally agents)

A user-facing capability is usually **two files**, by convention same-named:

| Layer | Path | Role |
|---|---|---|
| Command | `commands/<name>.md` | The `/name` slash entry. Thin — frontmatter (`name`, `description`) + a short body that says "run the `<name>` skill" and documents usage/scheduling. |
| Skill | `skills/<name>/SKILL.md` | The actual logic/instructions. Frontmatter: `name`, `description` (multi-line; the description doubles as the trigger blurb), `when_to_use` list. |

Agents (`agents/<name>.md`) are a separate axis — the 8 Arch leads + extras (`ai-lead`, `security-lead`). Frontmatter: `name`, `description` (with Korean trigger keywords), `tools` (explicit allowlist), `model` (e.g. `claude-opus-4-7`), `color`. The body is the agent's system prompt. `CLAUDE.md` references these leads by name and model — **keep the CLAUDE.md team table, the `agents/` files, and any model IDs in sync** when adding/renaming a lead.

When adding a feature: create both the command and skill files, follow the frontmatter shape of an existing pair (e.g. `config-push`), then restart to register.

## Paths & env vars — hard rule

**Never bake an absolute path into a skill, command, agent, or hook.** Resolve these env vars (set per-machine in shell rc by bootstrap) at runtime:

- `$CLAUDE_CONFIG_DIR` — this repo (varies: `/mnt/d/00_Claude_Config`, `~/claude-config`, `D:\00_Claude_Config`)
- `$PROJECTS_DIR`, `$OBSIDIAN_DIR`, `$AGENT_TEAM_DIR` — output/vault/memory dirs (vary per OS)
- `$CLAUDE_MACHINE_ID`, `$CLAUDE_WEEKLY_LEADER` — machine identity / leader election (set in `paths.local.env`)

`paths.env` is git-tracked shared policy; `paths.local.env` is **gitignored** per-machine secrets/IDs (Notion tokens, machine ID, leader flag). Secrets live only in gitignored files — never in tracked content.

## bootstrap

`bootstrap.sh` (macOS/Linux/WSL) and `bootstrap.ps1` (Windows) are **idempotent and location-aware** — they operate relative to their own directory, so moving the repo + re-running fixes all links/env vars. Running from **WSL invokes the Windows `bootstrap.ps1` automatically** (shared D: drive sets up both OSes in one shot). `bootstrap` also reads `plugins.manifest` and installs plugins. After moving the repo, re-run bootstrap.

## Hooks

Wired via `core.hooksPath = hooks` (post-merge) and `settings.json` (UserPromptSubmit). Both are committed scripts:

- `hooks/post-merge` — after every pull: re-copies `CLAUDE.md` on Windows/WSL-to-Windows, and prints an add/modify/delete summary of changed `skills/agents/commands/hooks`. OS-detection via `uname`/`/proc/version`.
- `hooks/user-prompt-submit` — intercepts messages from the **Telegram** plugin. If the body starts with a **whitelisted** CLI slash command (`/new /clear /compact /cost /exit /login /logout /config /model /help`), it dispatches that token into the active Claude tmux pane via `scripts/telegram-slash-dispatch.sh` and **exits 2 to block** the original prompt. Only the validated whitelist token is passed downstream (tmux literal mode) — never the raw body. Note: `/new` and `/clear` are handled behaviorally by Arch as a context reset (see `CLAUDE.md`), separate from this whitelist dispatch.

`scripts/` also holds Telegram MCP health-check and watchdog-patch scripts referenced by schedules.

## plugins.manifest

Declarative plugin list consumed by bootstrap. One action per line: `market <github-repo>` registers a marketplace, `plugin <name>@<marketplace>` installs. Disable by commenting the line with `#`. `settings.json` mirrors the enabled set under `enabledPlugins` / `extraKnownMarketplaces`.

## Output language

User-facing text in skills/commands/agents is **Korean**; internal reasoning and code/comments are English. Match the surrounding file.

## Don't commit / don't touch

Runtime/state dirs are gitignored and machine-local — do not stage or hand-edit them: `cache/ backups/ file-history/ session-env/ sessions/ shell-snapshots/ projects/ tasks/ plugins/ ide/ telemetry/ paste-cache/`, plus `history.jsonl`, `.claude.json`, `.credentials.json`, `*.token`, `*.key`, `paths.local.env`, `settings.local.json`.
