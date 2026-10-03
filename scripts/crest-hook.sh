#!/bin/sh
# Crest plugin hook. Usage: crest-hook.sh pre|post|notify  (payload on stdin)
#
# Hands Claude Code's event to Crest's own hook when Crest is installed, new
# enough, switched on and has not already hooked this event itself in
# settings.json. Otherwise it does nothing and Claude Code carries on as if
# the plugin were not here.
#
# Contract with Claude Code: this script ALWAYS exits 0, and prints only what
# Crest's own hook printed (or nothing). It never blocks a tool by itself.
# Set CREST_PLUGIN_DEBUG=1 to get one line on stderr saying what it decided.

payload=$(cat 2>/dev/null)

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -z "$here" ] || [ ! -f "$here/crest-lib.sh" ]; then
  [ -n "$CREST_PLUGIN_DEBUG" ] && echo "crest plugin: crest-lib.sh not found next to $0; passing through" >&2
  exit 0
fi
# shellcheck source=crest-lib.sh
. "$here/crest-lib.sh"

case "$1" in
  pre)    event=PreToolUse ;;
  post)   event=PostToolUse ;;
  notify) event=Notification ;;
  *) [ -n "$CREST_PLUGIN_DEBUG" ] && echo "crest plugin: unknown event '$1'; passing through" >&2; exit 0 ;;
esac

# Fast path, the common case for Crest users: Crest's own hook already gets
# this event, so there is nothing to do (and nothing else worth checking).
if crest_hook_installed "$event"; then
  [ -n "$CREST_PLUGIN_DEBUG" ] && echo "crest plugin: $event -> crest_hook" >&2
  exit 0
fi

crest_state "$event" >/dev/null
state="$CREST_STATE"
[ -n "$CREST_PLUGIN_DEBUG" ] && echo "crest plugin: $event -> $state" >&2
[ "$state" = "ready" ] || exit 0

dir=$(crest_approvals_dir)
case "$event" in
  PreToolUse)
    # Crest's script blocks until the notch answers (or Crest stops beating),
    # then prints Claude Code's decision JSON. Relay it only on a clean exit.
    out=$(printf '%s' "$payload" | sh "$dir/pretooluse.sh" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      [ -n "$out" ] && printf '%s' "$out"
    else
      [ -n "$CREST_PLUGIN_DEBUG" ] && echo "crest plugin: Crest's hook exited $rc; passing through" >&2
    fi
    ;;
  PostToolUse)
    printf '%s' "$payload" | sh "$dir/posttooluse.sh" >/dev/null 2>&1
    ;;
  Notification)
    # The same one-line mirror Crest puts in settings.json (AgentAlertsSetup):
    # an epoch timestamp, the notification JSON, a newline.
    { printf '%s ' "$(date +%s)"; printf '%s\n' "$payload"; } \
      >> "$(crest_support_dir)/claude-events.jsonl" 2>/dev/null
    ;;
esac
exit 0
