#!/bin/bash
# Test suite for the Crest Claude Code plugin. Run: bash tests/run.sh
# Every test builds its own throwaway HOME (fake Crest.app, fake settings.json,
# fake Crest approvals folder), so nothing on this Mac is read or touched,
# except the optional end-to-end test, which copies Crest's real hook script
# (when this Mac has one) into the throwaway HOME.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLUGIN="$ROOT"   # the repository root is the plugin (and the marketplace)
HOOK="$PLUGIN/scripts/crest-hook.sh"
STATUS="$PLUGIN/scripts/crest-status.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/crest-plugin-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; SKIP=0; CURRENT=""
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL [$CURRENT] $*"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP [$CURRENT] $*"; }
t()    { CURRENT="$1"; }

assert_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3: expected [$2] got [$1]"; fi; }
assert_contains() { case "$1" in *"$2"*) ok ;; *) bad "$3: [$2] not in output: $1" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3: [$2] should not be in: $1" ;; *) ok ;; esac; }
assert_file() { if [ -e "$1" ]; then ok; else bad "$2: missing $1"; fi; }
assert_no_file() { if [ -e "$1" ]; then bad "$2: should not exist: $1"; else ok; fi; }

PAYLOAD='{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_use_id":"toolu_test1"}'
DECISION='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
PRE_MARK="Crest/approvals/pretooluse.sh"
POST_MARK="Crest/approvals/posttooluse.sh"
NOTE_MARK="Crest/claude-events.jsonl"

# ---------- fixture builders ----------

# fresh_env: a new HOME with nothing in it. Exports what the scripts read.
fresh_env() {
  E="$WORK/env$RANDOM$RANDOM"
  mkdir -p "$E/home/.claude"
  export HOME="$E/home"
  export CREST_APP="$E/Crest.app"             # not created until make_app
  export CREST_DEFAULTS_DOMAIN="$E/prefs.plist" # absent until set_pref
  unset CLAUDE_CONFIG_DIR CREST_PLUGIN_DEBUG
  APPROVALS="$HOME/Library/Application Support/Crest/approvals"
  SUPPORT="$HOME/Library/Application Support/Crest"
}

make_app() { # make_app VERSION  (VERSION "none" = no Info.plist)
  mkdir -p "$CREST_APP/Contents"
  [ "$1" = "none" ] && return
  cat > "$CREST_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.zack40x.crest</string>
<key>CFBundleShortVersionString</key><string>$1</string>
</dict></plist>
EOF
}

set_pref() { # set_pref true|false
  defaults write "$CREST_DEFAULTS_DOMAIN" answerPromptsOnNotch -bool "$1" >/dev/null 2>&1
}

# Fake Crest hook scripts: record what they got, print a known answer.
make_scripts() { # make_scripts [pre-exit-code]
  mkdir -p "$APPROVALS"
  cat > "$APPROVALS/pretooluse.sh" <<EOF
#!/bin/sh
cat > "\$HOME/got-pre.json"
printf '%s' '$DECISION'
exit ${1:-0}
EOF
  cat > "$APPROVALS/posttooluse.sh" <<'EOF'
#!/bin/sh
cat > "$HOME/got-post.json"
exit 0
EOF
}

beat() { touch "$APPROVALS/heartbeat"; }
stale_beat() { touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$APPROVALS/heartbeat"; }

# Settings.json with Crest's own entries, written the way Crest writes them.
crest_settings() { # crest_settings [file]
  f="${1:-$HOME/.claude/settings.json}"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
{
  "hooks" : {
    "Notification" : [ { "hooks" : [ { "command" : "{ printf '%s ' \"\$(date +%s)\"; cat; echo; } >> \"\$HOME/Library/Application Support/$NOTE_MARK\"", "type" : "command" } ] } ],
    "PostToolUse" : [ { "hooks" : [ { "command" : "sh '$HOME/Library/Application Support/$POST_MARK'", "timeout" : 10, "type" : "command" } ], "matcher" : "AskUserQuestion" } ],
    "PreToolUse" : [ { "hooks" : [ { "command" : "sh '$HOME/Library/Application Support/$PRE_MARK'", "timeout" : 86400, "type" : "command" } ], "matcher" : "Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch|WebSearch|AskUserQuestion" } ]
  },
  "env" : { "CREST_TEST_KEEP" : "1" }
}
EOF
}

ready_env() { fresh_env; make_app "6.0.1"; make_scripts "$@"; beat; set_pref true; }

# run_hook EVENT [payload] -> sets OUT, RC
run_hook() {
  OUT=$(printf '%s' "${2-$PAYLOAD}" | sh "$HOOK" "$1" 2>/dev/null); RC=$?
}
run_status() { OUT=$(sh "$STATUS" "$@" 2>&1); RC=$?; }

# ---------- tests ----------

echo "Crest plugin tests"

t "crest hook already installed: plugin is a no-op for every event"
ready_env; crest_settings
run_hook pre;    assert_eq "$RC" 0 "exit"; assert_eq "$OUT" "" "no output"; assert_no_file "$HOME/got-pre.json" "Crest script not run twice"
run_hook post;   assert_eq "$RC" 0 "exit"; assert_no_file "$HOME/got-post.json" "post not run twice"
run_hook notify '{"message":"x"}'; assert_eq "$RC" 0 "exit"; assert_no_file "$SUPPORT/claude-events.jsonl" "no double mirror"
run_status; assert_contains "$OUT" "All set" "status"; assert_contains "$OUT" "stays out of the way" "status explains"

t "crest hook installed for one event only: the others still forward"
ready_env
cat > "$HOME/.claude/settings.json" <<EOF
{"hooks":{"PostToolUse":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"sh '$HOME/Library/Application Support/$POST_MARK'"}]}]}}
EOF
run_hook pre; assert_eq "$OUT" "$DECISION" "pre forwards"
run_hook post; assert_no_file "$HOME/got-post.json" "post is Crest's"

t "crest present without its hook: plugin forwards to Crest's script"
ready_env
run_hook pre; assert_eq "$RC" 0 "exit"; assert_eq "$OUT" "$DECISION" "relays Crest's decision"
assert_eq "$(cat "$HOME/got-pre.json")" "$PAYLOAD" "payload passed byte for byte"
run_hook post; assert_eq "$(cat "$HOME/got-post.json")" "$PAYLOAD" "post payload"
run_hook notify '{"message":"Claude needs your permission"}'
line=$(cat "$SUPPORT/claude-events.jsonl")
assert_contains "$line" ' {"message":"Claude needs your permission"}' "mirror line"
case "$line" in [0-9]*) ok ;; *) bad "mirror line starts with an epoch: $line" ;; esac
run_status; assert_contains "$OUT" "All set" "status ready"; assert_contains "$OUT" "hands Claude Code's prompts" "status ready text"

t "settings.json with other user hooks and no Crest entry: forwards"
ready_env
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$HOME/.claude/settings.json"
run_hook pre; assert_eq "$OUT" "$DECISION" "forwards"

t "pref never stored (absent): forwards"
ready_env; rm -f "$CREST_DEFAULTS_DOMAIN"
run_hook pre; assert_eq "$OUT" "$DECISION" "forwards"

t "crest missing: pass-through, status says not installed with the link"
fresh_env
run_hook pre; assert_eq "$RC" 0 "exit"; assert_eq "$OUT" "" "no output"
run_hook post; assert_eq "$RC" 0 "exit"
run_hook notify '{}'; assert_eq "$RC" 0 "exit"; assert_no_file "$SUPPORT" "no Crest folder conjured"
run_status; assert_eq "$RC" 0 "status exit"
assert_contains "$OUT" "Crest is not installed." "plain words"
assert_contains "$OUT" "https://crestnotch.app/download?ref=cc-plugin" "download link"
assert_not_contains "$OUT" "—" "no em-dash"

t "crest missing but scripts left behind (Crest deleted): pass-through"
fresh_env; make_scripts; beat; set_pref true
run_hook pre; assert_eq "$OUT" "" "no output"; assert_no_file "$HOME/got-pre.json" "leftover script not run"

t "crest outdated: pass-through, status asks for an update"
fresh_env; make_app "5.1.4"; make_scripts; beat; set_pref true
run_hook pre; assert_eq "$RC" 0 "exit"; assert_eq "$OUT" "" "no output"; assert_no_file "$HOME/got-pre.json" "old Crest not used"
run_status; assert_contains "$OUT" "Crest 5.1.4 is installed" "says version"; assert_contains "$OUT" "needs Crest 5.2.0 or newer" "says minimum"
assert_contains "$OUT" "https://crestnotch.app/download?ref=cc-plugin" "link"

t "crest version unreadable: treated as outdated"
fresh_env; make_app "none"; make_scripts; beat
run_hook pre; assert_eq "$OUT" "" "no output"
run_status; assert_contains "$OUT" "Crest unknown is installed" "status says unknown"

t "version comparison boundaries"
. "$PLUGIN/scripts/crest-lib.sh"
for v in 5.2.0 5.2 5.2.1 5.10.0 6.0.1 6.0.1-beta 6 10.0 "5.2.0 (93)"; do
  if crest_version_ge "$v" 5.2.0; then ok; else bad "$v should be >= 5.2.0"; fi
done
for v in 5.1.99 5.1 4.12.0 0.9 "" abc -1 " 6.0"; do
  if crest_version_ge "$v" 5.2.0; then bad "[$v] should be < 5.2.0"; else ok; fi
done

t "switched off in Crest: plugin respects it"
ready_env; set_pref false
run_hook pre; assert_eq "$OUT" "" "no output"; assert_no_file "$HOME/got-pre.json" "not forwarded"
run_hook notify '{}'; assert_no_file "$SUPPORT/claude-events.jsonl" "no mirror"
run_status; assert_contains "$OUT" "switched off" "status"; assert_contains "$OUT" "Allow or deny commands here" "says where"

t "crest not running (stale heartbeat / none): pass-through"
ready_env; stale_beat
run_hook pre; assert_eq "$OUT" "" "stale: no output"; assert_no_file "$HOME/got-pre.json" "stale: not forwarded"
run_status; assert_contains "$OUT" "not running" "status"
rm -f "$APPROVALS/heartbeat"
run_hook pre; assert_eq "$OUT" "" "no heartbeat: no output"
run_hook post; assert_file "$HOME/got-post.json" "post cleanup still runs (no blocking)"

t "crest installed but never set up (no scripts): pass-through"
fresh_env; make_app "6.0.1"
run_hook pre; assert_eq "$OUT" "" "no output"
run_status; assert_contains "$OUT" "has not set up its Claude Code hook" "status"

t "Crest's script fails: plugin prints nothing and exits 0"
for code in 1 2 3 127; do
  ready_env "$code"
  run_hook pre; assert_eq "$RC" 0 "exit with Crest rc $code"; assert_eq "$OUT" "" "no relay on rc $code"
done

t "malformed input never fails the hook"
ready_env
for p in "" "not json" '{"tool_name":' '{}' "$(printf '\001\002\377')" '[1,2,3]'; do
  run_hook pre "$p"; assert_eq "$RC" 0 "pre exit on [$p]"
  run_hook post "$p"; assert_eq "$RC" 0 "post exit"
  run_hook notify "$p"; assert_eq "$RC" 0 "notify exit"
done
big=$(head -c 300000 /dev/zero | tr '\0' 'a')
run_hook pre "{\"x\":\"$big\"}"; assert_eq "$RC" 0 "300 KB payload"
for arg in "" bogus PRE "pre;"; do
  OUT=$(printf '%s' "$PAYLOAD" | sh "$HOOK" "$arg" 2>/dev/null); RC=$?
  assert_eq "$RC" 0 "arg [$arg]"; assert_eq "$OUT" "" "arg [$arg] no output"
done

t "malformed settings.json: counts as no Crest hook (Claude Code can't run it either)"
ready_env; echo '{ "hooks": { broken' > "$HOME/.claude/settings.json"
run_hook pre; assert_eq "$OUT" "$DECISION" "forwards"
ready_env; echo '' > "$HOME/.claude/settings.json"
run_hook pre; assert_eq "$OUT" "$DECISION" "empty file forwards"
ready_env; echo '{"hooks":"oops"}' > "$HOME/.claude/settings.json"
run_hook pre; assert_eq "$OUT" "$DECISION" "wrong type forwards"

t "CLAUDE_CONFIG_DIR: only the settings Claude Code reads count"
ready_env; crest_settings   # Crest wrote ~/.claude, but Claude Code reads elsewhere
export CLAUDE_CONFIG_DIR="$E/otherconfig"; mkdir -p "$CLAUDE_CONFIG_DIR"
run_hook pre; assert_eq "$OUT" "$DECISION" "forwards when Crest's entry is in an unread file"
crest_settings "$CLAUDE_CONFIG_DIR/settings.json"; rm -f "$HOME/got-pre.json"
run_hook pre; assert_eq "$OUT" "" "no-op when the read file has Crest's entry"; assert_no_file "$HOME/got-pre.json" "not forwarded"
unset CLAUDE_CONFIG_DIR

t "Crest turns its own hook on and off while the plugin is installed"
ready_env
run_hook pre; assert_eq "$OUT" "$DECISION" "before: forwards"
crest_settings; rm -f "$HOME/got-pre.json"
run_hook pre; assert_eq "$OUT" "" "Crest on: no-op"; assert_no_file "$HOME/got-pre.json" "fires once"
echo '{"env":{}}' > "$HOME/.claude/settings.json"
run_hook pre; assert_eq "$OUT" "$DECISION" "Crest's entry removed: forwards again"

t "not macOS: pass-through"
ready_env
mkdir -p "$E/bin"; printf '#!/bin/sh\necho Linux\n' > "$E/bin/uname"; chmod +x "$E/bin/uname"
OUT=$(printf '%s' "$PAYLOAD" | PATH="$E/bin:$PATH" sh "$HOOK" pre 2>/dev/null); RC=$?
assert_eq "$RC" 0 "exit"; assert_eq "$OUT" "" "no output"
OUT=$(PATH="$E/bin:$PATH" sh "$STATUS"); assert_contains "$OUT" "not a Mac" "status"

t "/crest:setup opens the right next step, /crest:status opens nothing"
fresh_env; echo "#!/bin/sh" > "$E/open"; echo 'echo "$1" >> "'"$E"'/opened"' >> "$E/open"; chmod +x "$E/open"
export CREST_OPEN_CMD="$E/open"
run_status; assert_no_file "$E/opened" "status opens nothing"
run_status --open; assert_eq "$(cat "$E/opened")" "https://crestnotch.app/download?ref=cc-plugin" "missing: opens download"
assert_contains "$OUT" "Opened the download page" "says so"
rm -f "$E/opened"; make_app 6.0.1
run_status --open; assert_eq "$(cat "$E/opened")" "$CREST_APP" "not set up: opens Crest"
rm -f "$E/opened"; make_scripts; beat; crest_settings
run_status --open; assert_no_file "$E/opened" "all set: opens nothing"
unset CREST_OPEN_CMD

t "hooks.json commands run as written, never exit non-zero, even from a damaged copy"
cmds=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for ev,entries in d["hooks"].items():
    for e in entries:
        for h in e["hooks"]:
            print(h["command"])' "$PLUGIN/hooks/hooks.json")
assert_eq "$(printf '%s\n' "$cmds" | wc -l | tr -d ' ')" 3 "three hook commands"
ready_env
SPACED="$E/plugin root with spaces"; mkdir -p "$SPACED"; cp -R "$PLUGIN/." "$SPACED/"
printf '%s\n' "$cmds" | while IFS= read -r c; do
  OUT=$(printf '%s' "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$SPACED" sh -c "$c" 2>/dev/null); RC=$?
  [ "$RC" = 0 ] || echo "FAILRC $c" >> "$E/fails"
done
assert_no_file "$E/fails" "commands exit 0 from a path with spaces"
assert_eq "$(cat "$HOME/got-pre.json")" "$PAYLOAD" "pre reached Crest through hooks.json"
rm -f "$SPACED/scripts/crest-lib.sh"
printf '%s\n' "$cmds" | while IFS= read -r c; do
  OUT=$(printf '%s' "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$SPACED" sh -c "$c" 2>/dev/null); RC=$?
  [ "$RC" = 0 ] && [ -z "$OUT" ] || echo "FAIL $c" >> "$E/fails2"
done
assert_no_file "$E/fails2" "damaged copy (lib missing): exit 0, no output"
rm -rf "$SPACED/scripts"
printf '%s\n' "$cmds" | while IFS= read -r c; do
  printf '%s' "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$SPACED" sh -c "$c" >/dev/null 2>&1 || echo "FAIL $c" >> "$E/fails3"
done
assert_no_file "$E/fails3" "scripts folder gone: exit 0"
OUT=$(CLAUDE_PLUGIN_ROOT="$SPACED" sh -c 'sh "${CLAUDE_PLUGIN_ROOT}/scripts/crest-status.sh"' 2>/dev/null)
OUT2=$(cp -R "$PLUGIN/scripts" "$SPACED/" && rm "$SPACED/scripts/crest-lib.sh" && sh "$SPACED/scripts/crest-status.sh"); RC=$?
assert_eq "$RC" 0 "damaged status exit"; assert_contains "$OUT2" "damaged" "damaged status says so"

t "the no-op path is fast (runs before every Bash call)"
ready_env; crest_settings
start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
for i in 1 2 3 4 5; do run_hook pre; done
end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
ms=$(perl -e "printf '%d', ($end-$start)*1000/5")
if [ "$ms" -lt 500 ]; then ok; else bad "no-op took ${ms} ms per call"; fi
echo "  (no-op hook: ~${ms} ms per call)"

t "debug line names the decision"
ready_env; crest_settings
ERR=$(printf '%s' "$PAYLOAD" | CREST_PLUGIN_DEBUG=1 sh "$HOOK" pre 2>&1 >/dev/null)
assert_eq "$ERR" "crest plugin: PreToolUse -> crest_hook" "debug"

t "no telemetry: the scripts never reach the network"
if grep -nE 'curl|wget|nc |https?://[^ ]*\$|/dev/tcp|osascript' "$PLUGIN/scripts/"*.sh | grep -v 'CREST_DOWNLOAD_URL=' >/dev/null; then
  bad "network-ish call in scripts: $(grep -nE 'curl|wget|nc |/dev/tcp|osascript' "$PLUGIN/scripts/"*.sh)"
else ok; fi

t "no em-dashes in anything users read"
if grep -rln "—" "$ROOT/README.md" "$ROOT/.claude-plugin" "$ROOT/commands" "$ROOT/hooks" "$ROOT/scripts" >/dev/null 2>&1; then bad "em-dash found: $(grep -rln "—" "$ROOT/README.md" "$ROOT/.claude-plugin" "$ROOT/commands" "$ROOT/hooks" "$ROOT/scripts")"; else ok; fi

t "end to end with Crest's real hook script (when this Mac has Crest)"
REAL="/Users/$(id -un)/Library/Application Support/Crest/approvals/pretooluse.sh"
if [ -f "$REAL" ]; then
  fresh_env; make_app 6.0.1; set_pref true; mkdir -p "$APPROVALS"
  cp "$REAL" "$APPROVALS/pretooluse.sh"
  [ -f "$(dirname "$REAL")/posttooluse.sh" ] && cp "$(dirname "$REAL")/posttooluse.sh" "$APPROVALS/"
  beat
  # Play Crest: answer the pending prompt the moment it appears.
  ( for i in $(seq 1 100); do
      if [ -f "$APPROVALS/pending-toolu_test1.json" ]; then printf '%s' "$DECISION" > "$APPROVALS/resp-toolu_test1"; exit 0; fi
      touch "$APPROVALS/heartbeat"; sleep 0.05
    done ) &
  run_hook pre; wait
  assert_eq "$RC" 0 "exit"; assert_eq "$OUT" "$DECISION" "notch answer relayed through the plugin"
  assert_no_file "$APPROVALS/pending-toolu_test1.json" "Crest's script cleaned up"
  # Plan mode: Crest's script steps aside, so does the plugin.
  run_hook pre "${PAYLOAD/\"default\"/\"plan\"}"; assert_eq "$RC" 0 "plan exit"; assert_eq "$OUT" "" "plan: no decision"
  # A question: pending card + no decision (the picker shows in the terminal).
  Q='{"session_id":"s1","permission_mode":"acceptEdits","tool_name":"AskUserQuestion","tool_input":{"questions":[]},"tool_use_id":"toolu_q1"}'
  run_hook pre "$Q"; assert_eq "$RC" 0 "question exit"; assert_file "$APPROVALS/pending-toolu_q1.json" "question card dropped"
  run_hook post "$Q"; assert_no_file "$APPROVALS/pending-toolu_q1.json" "post cleared the card"
  # Crest's own entry present: the real script is not run by the plugin.
  crest_settings
  run_hook pre "${PAYLOAD/toolu_test1/toolu_test2}"; assert_no_file "$APPROVALS/pending-toolu_test2.json" "no second card"
else
  skip "Crest's hook script is not on this Mac"
fi

t "install and uninstall the plugin twice with the claude CLI: Crest's hooks survive"
if command -v claude >/dev/null 2>&1; then
  fresh_env
  export CLAUDE_CONFIG_DIR="$E/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  crest_settings "$CLAUDE_CONFIG_DIR/settings.json"
  hooks_of() { python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])).get("hooks"),sort_keys=True))' "$CLAUDE_CONFIG_DIR/settings.json"; }
  before=$(hooks_of)
  log="$E/cli.log"
  claude plugin marketplace add "$ROOT" >>"$log" 2>&1 || bad "marketplace add: $(tail -3 "$log")"
  claude plugin marketplace add "$ROOT" >>"$log" 2>&1   # second add must not break anything
  for round in 1 2; do
    claude plugin install crest@crest-notch >>"$log" 2>&1 || bad "install round $round: $(tail -3 "$log")"
    claude plugin install crest@crest-notch >>"$log" 2>&1   # double install
    en=$(/usr/bin/plutil -extract enabledPlugins json -o - "$CLAUDE_CONFIG_DIR/settings.json" 2>/dev/null)
    assert_contains "$en" "crest@crest-notch" "round $round: enabled"
    assert_eq "$(hooks_of)" "$before" "round $round: Crest's hooks untouched by install"
    claude plugin uninstall crest@crest-notch >>"$log" 2>&1 || bad "uninstall round $round: $(tail -3 "$log")"
    claude plugin uninstall crest@crest-notch >>"$log" 2>&1   # double uninstall
    en=$(/usr/bin/plutil -extract enabledPlugins json -o - "$CLAUDE_CONFIG_DIR/settings.json" 2>/dev/null)
    assert_not_contains "$en" "crest@crest-notch\":true" "round $round: plugin entry gone"
    assert_eq "$(hooks_of)" "$before" "round $round: Crest's hooks untouched by uninstall"
  done
  assert_eq "$(/usr/bin/plutil -extract env.CREST_TEST_KEEP raw -o - "$CLAUDE_CONFIG_DIR/settings.json")" "1" "other settings kept"
  claude plugin marketplace remove crest-notch >>"$log" 2>&1
  unset CLAUDE_CONFIG_DIR
else
  skip "claude CLI not on PATH"
fi

t "manifests validate"
if command -v claude >/dev/null 2>&1; then
  v1=$(claude plugin validate --strict "$ROOT" 2>&1); r1=$?
  v2=$(claude plugin validate --strict "$ROOT/.claude-plugin/plugin.json" 2>&1); r2=$?
  assert_eq "$r1" 0 "marketplace validates: $v1"; assert_eq "$r2" 0 "plugin validates: $v2"
else
  python3 -c 'import json,sys;[json.load(open(f)) for f in sys.argv[1:]]' "$ROOT/.claude-plugin/marketplace.json" "$ROOT/.claude-plugin/plugin.json" "$PLUGIN/hooks/hooks.json" && ok || bad "JSON invalid"
fi

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" -eq 0 ]
