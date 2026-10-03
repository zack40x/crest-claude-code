---
description: Set up Crest notch approvals - opens the Crest download page if Crest is missing, or Crest itself if it needs switching on
disable-model-invocation: true
allowed-tools: Bash(sh *crest-status.sh*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/crest-status.sh" --open`

Above is the Crest plugin's setup report, produced by a local script (it may have opened the download page or the Crest app). Show it to the user as written, in plain text, keeping any link exactly as it appears. Do not add advice beyond what the report says, and do not run other commands.
