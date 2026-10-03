#!/bin/sh
# /crest:status and /crest:setup. Says in plain words whether Crest is
# answering Claude Code's prompts on the notch and, if not, the one next step.
# Usage: crest-status.sh [--open]
#   --open  also opens the next step: the download page when Crest is missing
#           or too old, or Crest itself when it is installed.
# Always exits 0. Reads only local files; sends nothing anywhere.

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -z "$here" ] || [ ! -f "$here/crest-lib.sh" ]; then
  echo "The Crest plugin is damaged: crest-lib.sh is missing next to crest-status.sh. Reinstall with /plugin install crest@crest-notch."
  exit 0
fi
# shellcheck source=crest-lib.sh
. "$here/crest-lib.sh"

open_flag=""
[ "$1" = "--open" ] && open_flag=1
opener="${CREST_OPEN_CMD:-open}"
# Where the switch lives: Crest 6 splits it in two, Crest 5 had one.
how_on='open Crest, Settings, Agents, and turn on "Allow or deny commands here" and "Answer Claude'"'"'s questions here" (in Crest 5 the one switch is "Answer prompts on the notch")'

crest_state PreToolUse >/dev/null
state="$CREST_STATE"
app="$CREST_FOUND_APP"
ver="${CREST_FOUND_VERSION:-unknown}"
sf=$(crest_settings_file)
next=""

case "$state" in
  not_macos)
    echo "Crest is a Mac app, and this computer is not a Mac. The plugin does nothing here; Claude Code works as usual."
    ;;
  no_app)
    echo "Crest is not installed."
    echo "Crest puts Claude Code's permission prompts and questions on your MacBook notch, so you can answer them without switching to the terminal."
    echo "Download it free: $CREST_DOWNLOAD_URL"
    echo "Until then this plugin does nothing and Claude Code asks in the terminal as usual."
    next=url
    ;;
  outdated)
    echo "Crest $ver is installed at $app, but this plugin needs Crest $CREST_MIN_VERSION or newer."
    echo "Update it from Crest's menu (Check for Updates), or download the latest: $CREST_DOWNLOAD_URL"
    echo "Until then this plugin does nothing and Claude Code asks in the terminal as usual."
    next=url
    ;;
  crest_hook)
    echo "All set. Crest $ver answers Claude Code's prompts on your notch."
    echo "Crest's own hook is in $sf, so Crest handles each prompt and this plugin stays out of the way (every prompt shows once)."
    ;;
  switched_off)
    echo "Crest $ver is installed, but answering Claude Code on the notch is switched off in Crest's Settings."
    echo "The plugin respects that and stays out of the way. To turn it on: $how_on."
    next=app
    ;;
  no_script)
    echo "Crest $ver is installed but has not set up its Claude Code hook yet."
    echo "To set it up: $how_on. Until then Claude Code asks in the terminal as usual."
    next=app
    ;;
  not_running)
    echo "Crest $ver is installed but not running right now, so Claude Code asks in the terminal as usual."
    echo "Open Crest and prompts go to the notch again."
    next=app
    ;;
  ready)
    echo "All set. Crest $ver is running, and this plugin hands Claude Code's prompts to it, so you can answer them on your notch."
    ;;
  *)
    echo "The Crest plugin could not tell what state Crest is in ($state). Claude Code works as usual."
    ;;
esac

if [ -n "$open_flag" ]; then
  case "$next" in
    url) "$opener" "$CREST_DOWNLOAD_URL" >/dev/null 2>&1 && echo "(Opened the download page in your browser.)" ;;
    app) "$opener" "$app" >/dev/null 2>&1 && echo "(Opened Crest.)" ;;
  esac
fi
echo "Privacy: this plugin sends nothing anywhere. It only reads local files to decide whether to hand a prompt to Crest on this Mac."
exit 0
