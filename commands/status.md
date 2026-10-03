---
description: Check whether Crest is installed and answering Claude Code's prompts on your notch
disable-model-invocation: true
allowed-tools: Bash(sh *crest-status.sh*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/crest-status.sh"`

Above is the Crest plugin's status report, produced by a local script. Show it to the user as written, in plain text, keeping any link exactly as it appears. Do not add advice beyond what the report says, and do not run other commands.
