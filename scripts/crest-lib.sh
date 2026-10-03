#!/bin/sh
# Shared checks for the Crest plugin's hook and its /crest:status command.
# POSIX sh, macOS tools only (plutil, defaults, stat). Sourced, never run.
#
# The plugin never answers a prompt itself. When everything below is in place
# it hands the event to Crest's own hook script, the one Crest writes into
# ~/Library/Application Support/Crest/approvals and keeps up to date with
# every Crest release. In every other case it steps aside without a word, so
# Claude Code behaves exactly as if the plugin were not installed.

CREST_MIN_VERSION="5.2.0"
CREST_DOWNLOAD_URL="https://crestnotch.app/download?ref=cc-plugin"
CREST_BUNDLE_ID="com.zack40x.crest"

# Where Crest keeps its hook scripts and heartbeat (Crest's AppPaths.approvals).
crest_support_dir() { printf '%s' "$HOME/Library/Application Support/Crest"; }
crest_approvals_dir() { printf '%s/approvals' "$(crest_support_dir)"; }

# The settings file Claude Code reads for user hooks. Crest writes its entries
# into ~/.claude/settings.json; when CLAUDE_CONFIG_DIR points elsewhere those
# entries do not fire, so the plugin looks only where Claude Code looks.
crest_settings_file() { printf '%s/settings.json' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# The installed Crest.app, or nothing. CREST_APP, when set (even to a path
# that does not exist), is the only place looked at: a seam for the tests and
# for people who keep Crest somewhere unusual.
crest_find_app() {
  if [ -n "${CREST_APP+x}" ]; then
    [ -d "$CREST_APP" ] && printf '%s' "$CREST_APP"
    return 0
  fi
  for a in "/Applications/Crest.app" "$HOME/Applications/Crest.app"; do
    if [ -d "$a" ]; then printf '%s' "$a"; return 0; fi
  done
  return 0
}

# CFBundleShortVersionString of an app bundle, or nothing when unreadable.
crest_app_version() {
  plist="$1/Contents/Info.plist"
  [ -f "$plist" ] || return 0
  /usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null
}

# version_ge A B: true when A >= B. Compares up to three numeric parts;
# anything after the first non-digit in a part is ignored ("6.0.1-beta" is
# 6.0.1). An empty or non-numeric A is never new enough.
crest_version_ge() {
  a="$1"; b="$2"
  case "$a" in [0-9]*) ;; *) return 1 ;; esac
  oldifs=$IFS; IFS=.
  # shellcheck disable=SC2086
  set -- $a; a1=${1:-0}; a2=${2:-0}; a3=${3:-0}
  # shellcheck disable=SC2086
  set -- $b; b1=${1:-0}; b2=${2:-0}; b3=${3:-0}
  IFS=$oldifs
  a1=$(crest_num "$a1"); a2=$(crest_num "$a2"); a3=$(crest_num "$a3")
  b1=$(crest_num "$b1"); b2=$(crest_num "$b2"); b3=$(crest_num "$b3")
  [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
  [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
  [ "$a3" -ge "$b3" ]
}
crest_num() {
  n=$(printf '%s' "$1" | sed 's/[^0-9].*$//')
  printf '%s' "${n:-0}"
}

# crest_hook_installed EVENT: true when Crest's own entry for EVENT is in the
# settings file Claude Code reads, so Crest already gets this event and the
# plugin must not hand it over a second time. Reads the JSON with plutil, the
# way Crest itself checks (a command under hooks.<EVENT> carrying its
# marker). An unreadable settings file counts as "not installed": Claude Code
# cannot run hooks from a file it cannot parse either.
crest_hook_installed() {
  case "$1" in
    PreToolUse)   marker="Crest/approvals/pretooluse.sh" ;;
    PostToolUse)  marker="Crest/approvals/posttooluse.sh" ;;
    Notification) marker="Crest/claude-events.jsonl" ;;
    *) return 1 ;;
  esac
  sf=$(crest_settings_file)
  [ -f "$sf" ] || return 1
  entries=$(/usr/bin/plutil -extract "hooks.$1" json -o - "$sf" 2>/dev/null) || return 1
  # plutil writes "/" as "\/" in JSON output; undo that before matching.
  entries=$(printf '%s' "$entries" | sed 's#\\/#/#g')
  case "$entries" in *"$marker"*) return 0 ;; esac
  return 1
}

# Crest's "Answer prompts on the notch" switch. Only an explicit "off" counts:
# the plugin never turns the feature on behind a choice the person made.
crest_switched_off() {
  v=$(defaults read "${CREST_DEFAULTS_DOMAIN:-$CREST_BUNDLE_ID}" answerPromptsOnNotch 2>/dev/null)
  [ "$v" = "0" ]
}

# Crest is running when its heartbeat file was touched in the last 30 seconds
# (the same window Crest's own hook uses).
crest_running() {
  hb="$(crest_approvals_dir)/heartbeat"
  [ -f "$hb" ] || return 1
  m=$(stat -f %m "$hb" 2>/dev/null) || return 1
  [ $(( $(date +%s) - m )) -le 30 ]
}

# crest_state EVENT -> prints one word saying what the plugin should do for
# EVENT (PreToolUse, PostToolUse or Notification):
#   not_macos | no_app | outdated | crest_hook | switched_off | no_script |
#   not_running | ready
# Only "ready" means "hand the event to Crest". Also sets CREST_STATE (the
# same word), CREST_FOUND_APP and CREST_FOUND_VERSION, so call it WITHOUT
# $( ) when you need those: a subshell would drop them.
crest_state() {
  CREST_FOUND_APP=""; CREST_FOUND_VERSION=""
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    CREST_FOUND_APP=$(crest_find_app)
    [ -n "$CREST_FOUND_APP" ] && CREST_FOUND_VERSION=$(crest_app_version "$CREST_FOUND_APP")
  fi
  CREST_STATE=$(crest_state_word "$1")
  echo "$CREST_STATE"
}

# The decision itself, from what crest_state found. Pure apart from reads.
crest_state_word() {
  event="$1"
  [ "$(uname -s 2>/dev/null)" = "Darwin" ] || { echo not_macos; return 0; }
  [ -n "$CREST_FOUND_APP" ] || { echo no_app; return 0; }
  crest_version_ge "$CREST_FOUND_VERSION" "$CREST_MIN_VERSION" || { echo outdated; return 0; }
  crest_hook_installed "$event" && { echo crest_hook; return 0; }
  crest_switched_off && { echo switched_off; return 0; }
  case "$event" in
    PreToolUse)
      [ -f "$(crest_approvals_dir)/pretooluse.sh" ] || { echo no_script; return 0; }
      crest_running || { echo not_running; return 0; } ;;
    PostToolUse)
      [ -f "$(crest_approvals_dir)/posttooluse.sh" ] || { echo no_script; return 0; } ;;
    Notification)
      [ -d "$(crest_support_dir)" ] || { echo no_script; return 0; } ;;
  esac
  echo ready
}
