#!/usr/bin/env bash
# PostToolUse (Edit|Write) checks, run in the checkout of this project that holds the edited file (a worktree under
# .claude/worktrees/ included). Exit 2 sends stderr to Claude; a missing tool skips its check.
#   post-check.sh pin    (sync)  the edited Cargo.toml must keep the exact hidapi = pin (hard constraint 2)
#   post-check.sh build  (async, asyncRewake)  clippy after a src/devices/ edit; the editor selftest after an edit to
#                        tools/profile-gui/ or to a Rust file it reads (sync-products.mjs sources, Apex 7 tables)
in=$(cat)
if command -v jq >/dev/null 2>&1; then
    # -j, not -r: a native Windows jq.exe ends -r output with CRLF, and the CR would break the path.
    f=$(printf '%s' "$in" | jq -j '.tool_input.file_path // empty')
else
    # No jq (common in Git Bash on Windows): read file_path from the raw JSON and undo its \\ escapes.
    f=$(printf '%s' "$in" | grep -o '"file_path" *: *"[^"]*"' | head -n 1 | sed 's/^"file_path" *: *"//; s/"$//; s/\\\\/\\/g')
fi
[ -n "$f" ] && [ -f "$f" ] || exit 0
p=${f//\\//}
. "${0%/*}/checkout.sh"

if [ "$1" = pin ]; then
    case "$p" in */Cargo.toml) ;; *) exit 0 ;; esac
    project_path "$f" || exit 0
    if grep -E '^hidapi *=' "$f" | grep -v '"=' >&2; then
        echo "hidapi is no longer pinned with an exact = version in $p (CLAUDE.md hard constraint 2); that needs explicit task justification." >&2
        exit 2
    fi
    exit 0
fi

project_path "$f" || exit 0
case "$rel" in
    src/devices/mod.rs | src/devices/keyboards/models.rs | src/devices/keyboards/onboard.rs | \
        src/devices/keyboards/apex_7.rs | src/devices/keyboards/apex_7_profile.rs) checks='clippy selftest' ;;
    src/devices/*.rs) checks=clippy ;;
    tools/profile-gui/*) checks=selftest ;;
    *) exit 0 ;;
esac
# A checkout older than the editor has nothing to check.
[ -f "$root/tools/profile-gui/sync-products.mjs" ] || exit 0
cd "$root" || exit 0

clippy() {
    command -v cargo >/dev/null 2>&1 || return 0
    out=$(cargo clippy --all-targets --locked --message-format short -- -D warnings 2>&1) && return 0
    printf '%s\n' "$out" | tail -40
    return 1
}

selftest() {
    command -v node >/dev/null 2>&1 || return 0
    # The selftest reads its files through import.meta.dirname (Node 20.11+); older Node runs the drift check alone.
    if node -e 'const [a, b] = process.versions.node.split(".").map(Number); process.exit(a > 20 || (a === 20 && b >= 11) ? 0 : 1)'; then
        out=$(node tools/profile-gui/selftest.mjs 2>&1) && return 0
    else
        out=$(node tools/profile-gui/sync-products.mjs --check 2>&1) && return 0
    fi
    printf '%s\n' "$out" | grep -v '^  ok ' | tail -40
    return 1
}

# Every edit starts a run, and each run writes its PID to a token file per check. A run that a newer run superseded
# stays silent, so an intermediate state of a multi-step edit does not wake Claude with errors that a later edit
# already fixed. Runs of one check take turns on a flock of its token file (where flock exists; the lock is advisory,
# so a newer run still writes its token), so a run superseded while it waited exits without starting the check. The
# tokens live in the checkout's git dir: creating target/ here would keep cargo from tagging it (CACHEDIR.TAG). A run
# whose token could not be written counts as current, so a stale token cannot silence every run.
g=$(git rev-parse --git-dir 2>/dev/null) || g=
tokens=
for c in $checks; do
    [ -n "$g" ] && { echo $$ >"$g/claude-post-check-$c"; } 2>/dev/null && tokens+=" $c "
done
has_token() { case "$tokens" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
current() { ! has_token "$1" || [ "$(cat "$g/claude-post-check-$1" 2>/dev/null)" = $$ ]; }
command -v flock >/dev/null 2>&1 && have_flock=1 || have_flock=

report=
for c in $checks; do
    if [ -n "$have_flock" ] && has_token "$c" && exec 9>>"$g/claude-post-check-$c"; then flock 9; fi
    # 9>&-: a process the check leaves running (a compiler cache server, say) must not inherit the lock.
    if current "$c" && ! o=$($c 9>&-) && current "$c"; then
        report+="$c failed after the edit to $rel:"$'\n'"$o"$'\n'
    fi
    exec 9>&-
done
[ -n "$report" ] || exit 0
printf '%s' "$report" >&2
exit 2
