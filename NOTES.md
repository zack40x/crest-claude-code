# Notes: how Claude Code plugins work (checked 2026-10-03)

Verified against Anthropic's docs on 2026-10-03, Claude Code 2.1.288. Every fact below has its source link. Read these before changing the plugin.

## Plugin structure

Source: https://code.claude.com/docs/en/plugins/manifest-reference and https://code.claude.com/docs/en/plugins/components

- The manifest is `.claude-plugin/plugin.json`. Only `name` is required (kebab-case, permanent: users install by `name@marketplace`, so a rename breaks every existing install). Useful optional fields: `displayName`, `version`, `description`, `author`, `homepage`, `repository`, `license`, `keywords`.
- Component paths must start with `./` and stay inside the plugin root (`..` fails validation).
- A plugin can ship: skills (`skills/<name>/SKILL.md`), commands (`commands/*.md`), agents (`agents/`), hooks (`hooks/hooks.json`), MCP servers (`.mcp.json`), LSP servers (`.lsp.json`), output styles, themes, workflows, monitors (`monitors/monitors.json`), executables on PATH (`bin/`), and channels.
- Commands are namespaced by the plugin: `commands/status.md` in plugin `crest` is `/crest:status`.
- `${CLAUDE_PLUGIN_ROOT}` is the installed plugin's absolute path (changes per version, so never store state there). `${CLAUDE_PLUGIN_DATA}` is a persistent folder (`~/.claude/plugins/data/<id>/`). Both are substituted in hook commands and in skill/command content.
- `hooks/hooks.json` is loaded automatically; do not also list it under `hooks` in `plugin.json` (directory validation warns).

## Commands can run a script before Claude sees them

Source: https://code.claude.com/docs/en/skills

- A line `` !`command` `` in a skill or command runs the shell command first and replaces itself with the output, so Claude receives the data, not the command. Commands take the same frontmatter as skills.
- `allowed-tools` grants the listed tools for the turn that invoked the command. `disable-model-invocation: true` means only the user can run it (Claude never triggers it on its own). Both are used in `commands/*.md`.
- Injection is skipped for skills synced from claude.ai (Claude Code 2.1.228+), and an admin can disable it with `disableSkillShellExecution`. In that case `/crest:status` shows Claude a placeholder instead of the report; the hook is unaffected.
- Checked live: `claude -p "/crest:status" --plugin-dir .` printed the real report.

## Hooks: plugin hooks and settings.json hooks BOTH fire

Source: https://code.claude.com/docs/en/hooks

- "When a plugin is enabled, its hooks merge with your user and project hooks."
- "All matching hooks run in parallel. If you define the same handler in more than one settings file, it runs once. A plugin's or skill's copy of the same handler stays separate."
- So Crest's own PreToolUse entry in `~/.claude/settings.json` and this plugin's PreToolUse hook would BOTH run, in parallel, for every Bash call. That is why `scripts/crest-hook.sh` first checks whether Crest's entry is in the settings file Claude Code reads and exits at once if so. Without that check every prompt would show twice on the notch.
- Exit codes: 0 = success (JSON on stdout is parsed); 2 = blocking error (for PreToolUse it blocks the tool); any other code is a non-blocking error and the action proceeds. The plugin always exits 0, and `hooks.json` adds `|| true` because `sh` itself exits 2 on a syntax error, which would otherwise block the tool.
- PreToolUse decisions: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow|deny|ask|defer", ...}}`. Crest's own script prints these; the plugin relays them untouched.
- Default timeout is 600 s for command hooks. Crest's PreToolUse hook blocks until the notch answers, so both Crest's entry and the plugin's use `"timeout": 86400`.

## Marketplaces

Sources: https://code.claude.com/docs/en/plugins/marketplace-reference and https://code.claude.com/docs/en/plugins/publish

- A marketplace is `.claude-plugin/marketplace.json` in a git repo: required `name`, `owner.name`, `plugins[]`; each entry needs `name` and `source`. A repo can be its own marketplace with `"source": "./"` (this repo does that). Keep the entry name equal to the `plugin.json` name.
- Reserved marketplace names include `claude-plugins-official`, `claude-code-plugins`, `claude-community`, `anthropic-*` look-alikes, `github`, `npm`, and anything starting with `claudeai-`. Ours is `crest-notch`.
- Users: `/plugin marketplace add owner/repo` then `/plugin install name@marketplace`, or the shell forms `claude plugin marketplace add ...` / `claude plugin install ...`. Since 2.1.275 also `/plugin install name --marketplace owner/repo`.
- Validate with `claude plugin validate --strict <path>` (exit 0 pass, 1 fail). Both manifests here pass.
- Updates: auto-update is OFF by default for third-party marketplaces. If `version` is set in `plugin.json` it must be raised on every release, or `claude plugin update` says "already at the latest version".

## Anthropic's directory (the official listing)

Sources: https://code.claude.com/docs/en/plugins/publish, https://claude.com/docs/plugins/submit, https://claude.com/docs/plugins/pre-submission-checklist

- There is ONE submission path: the developer portal at https://claude.ai/directory/manage ("Submit new", then "Plugin bundle"). The old link https://clau.de/plugin-directory-submission points there too.
- It needs a paid claude.ai plan (Pro or Max from your own account) and your GitHub account connected on claude.ai with push access to the repo. The repo must be public before the listing goes live.
- `anthropics/claude-plugins-official` does not take submissions through the portal (partners only). `anthropics/claude-plugins-community` is a read-only mirror of approved directory plugins; pull requests opened against it are closed automatically.
- What the portal checks (beyond `claude plugin validate`): README of 40+ words in the plugin folder, a LICENSE file or `license` field, a lowercase-hyphen name built on your own product name, no `.DS_Store`, files under 256 KiB, readable source. Then a security scan for undisclosed behavior (sending data elsewhere, hidden code, changing permission settings), so the README must describe everything the plugin runs.
- A plugin in a subfolder of its repo gets stricter hook checks (no shell variables other than `${CLAUDE_PLUGIN_ROOT}`, no scripts calling other files, or it is held for a reviewer). This repo puts the plugin at the repository root for that reason.
- After submitting: scan, possibly a reviewer hold, then "Publish" (by default a reviewer publishes each version). Listed plugins reach Claude Code users as `<name>@synced`.

## Crest facts this plugin depends on

From the Crest source (`Sources/Crest/Features/Developer/ApprovalHook.swift`, `AgentAlertsSetup.swift`, `AgentPromptSwitch.swift`, `Team/TeamEnforcement.swift`, `AgentMonitor.swift`):

- Crest's hook is NOT a binary inside Crest.app. Crest writes POSIX sh scripts to `~/Library/Application Support/Crest/approvals/` (`pretooluse.sh`, `posttooluse.sh`) and rewrites them on every launch, so they always match the installed Crest.
- Crest's settings.json entries: PreToolUse `sh '<approvals>/pretooluse.sh'` (matcher `Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch|WebSearch|AskUserQuestion`, timeout 86400), PostToolUse `sh '<approvals>/posttooluse.sh'` (matcher `AskUserQuestion`, timeout 10), Notification: an inline append to `~/Library/Application Support/Crest/claude-events.jsonl`. Crest finds its own entries by the substrings `Crest/approvals/pretooluse.sh`, `Crest/approvals/posttooluse.sh` and `Crest/claude-events.jsonl`; the plugin uses the same markers.
- Crest only ever writes `~/.claude/settings.json`. When `CLAUDE_CONFIG_DIR` points elsewhere, Crest's entries do not fire, and the plugin's hook is what reaches Crest.
- Crest touches `approvals/heartbeat` every 3 s while running. Its scripts (and the plugin) treat a heartbeat older than 30 s as "Crest is not running".
- Crest scans `approvals/pending-*.json` whenever it runs, whether or not its own entries are in settings.json, so prompts handed over by the plugin are shown like any other.
- The switch is stored as `answerPromptsOnNotch` in the `com.zack40x.crest` defaults. A Mac that never turned it on stores `false` the first time Crest reads it, so the plugin forwards only when the switch is on (or was never read) and never overrides an explicit off.
- Minimum Crest: 5.2.0, the first release with the current hook protocol (team never-allow checks, the `notch-off` flag, prompts that stay until answered).
- Plugin hook PATH caveat: `plutil` is called as `/usr/bin/plutil`; `defaults`, `stat`, `sed`, `date` come from the default macOS PATH.
