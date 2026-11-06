# Crest notch approvals for Claude Code

Answer Claude Code's permission prompts and questions from your MacBook notch, with [Crest](https://crestnotch.app/claude-code-notch?ref=cc-plugin). The plugin is MIT licensed. Crest itself is a paid Mac app: answering Claude Code from the notch is part of Crest Pro, and every new install starts with a 7-day trial with no account or card.

Crest, the notch app for MacBook (crestnotch.app). Made by zack40x, the maker of Crest.

## What it does

When Claude Code wants to run a command, edit a file or fetch a page, or when it asks you a question, Crest shows the prompt on your notch. You tap Allow, Deny or an answer there instead of switching back to the terminal.

Crest can already set this up on its own (Settings, Agents). This plugin is the Claude Code side of the same thing:

- **`/crest:status`** says in plain words whether Crest is installed, new enough, switched on and running, and what to do next if not.
- **`/crest:setup`** does the same and opens the next step for you: the Crest download page if Crest is missing or too old, or Crest itself if it needs switching on.
- **A hook** that hands Claude Code's prompts to Crest when Crest is ready but its own hook is not in your `settings.json` (for example after `settings.json` was reset, or when you run Claude Code with `CLAUDE_CONFIG_DIR` pointing somewhere else).

The plugin does not draw anything or answer anything itself. It runs Crest's own hook script, which Crest keeps up to date with every release.

## Install

You need a Mac with [Crest](https://crestnotch.app/download?ref=cc-plugin) 5.2.0 or newer (7-day trial, then Crest Pro).

In Claude Code:

```
/plugin marketplace add zack40x/crest-claude-code
/plugin install crest@crest-notch
```

Or from your shell:

```
claude plugin marketplace add zack40x/crest-claude-code
claude plugin install crest@crest-notch
```

Then run `/crest:setup` and follow what it says.

## How it stays out of the way

- **Every prompt shows once.** Claude Code runs a plugin's hooks and your `settings.json` hooks side by side. So before doing anything, the plugin checks whether Crest's own hook is already in the `settings.json` Claude Code reads. If it is, the plugin does nothing and Crest handles the prompt as usual.
- **It never blocks Claude Code.** If Crest is not installed, older than 5.2.0, switched off, not running, or anything at all goes wrong, the hook prints nothing and exits 0, and Claude Code asks in the terminal exactly as it would without the plugin.
- **It respects your choice in Crest.** If you switched answering on the notch off in Crest's Settings, the plugin leaves it off.
- **It only watches what Crest watches:** Bash, Edit, Write, MultiEdit, NotebookEdit, WebFetch, WebSearch and AskUserQuestion. Read-only tools are never touched.

## Privacy

The plugin sends nothing anywhere: no telemetry, no network calls. It reads a few local files to decide what to do (Crest's version from `Crest.app`, your Claude Code `settings.json`, Crest's "answer on the notch" preference and its heartbeat file) and hands the prompt to Crest on the same Mac, through Crest's own folder in `~/Library/Application Support/Crest` (the same files Crest's own hook writes). It keeps nothing of its own. What Crest does with a prompt is covered by Crest's own privacy policy at https://crestnotch.app/legal.

## Uninstall

```
/plugin uninstall crest@crest-notch
/plugin marketplace remove crest-notch
```

The plugin never writes to your `settings.json` hooks, so uninstalling it leaves Crest's own hooks (and any of yours) exactly as they were. To stop Crest answering prompts altogether, switch it off in Crest's Settings, Agents.

## Troubleshooting

- Run `/crest:status` first: it names the one thing that is missing.
- To see what the hook decided for each event, start Claude Code with `CREST_PLUGIN_DEBUG=1` in the environment. The hook writes one line per event to stderr, for example `crest plugin: PreToolUse -> crest_hook` (Crest's own hook is installed, so the plugin stepped aside).
- Crest installed somewhere other than `/Applications` or `~/Applications`? Set `CREST_APP` to the full path of `Crest.app`.
- Updates: your own marketplaces do not auto-update by default. Run `/plugin update crest@crest-notch`, or turn on auto-update for `crest-notch` in `/plugin`.

## For developers

This repository is both the plugin and its marketplace (`crest-notch`):

- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`: the manifests
- `hooks/hooks.json`: the PreToolUse, PostToolUse and Notification hooks
- `scripts/`: the hook (`crest-hook.sh`), the status report behind both commands (`crest-status.sh`) and the checks they share (`crest-lib.sh`), all POSIX sh
- `commands/`: `/crest:status` and `/crest:setup`
- `tests/run.sh`: the test suite, `bash tests/run.sh` on a Mac
- `NOTES.md`: how Claude Code plugins work, from Anthropic's docs, with links

## License

MIT, see [LICENSE](LICENSE). Crest itself is a separate app with its own terms.
