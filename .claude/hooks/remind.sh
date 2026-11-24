#!/usr/bin/env bash
# PreToolUse reminders. Plain stdout from an exit-0 PreToolUse hook never reaches Claude, so each reminder goes out as
# hookSpecificOutput.additionalContext. `remind.sh git-push` prints the push reminder when the Bash or PowerShell
# command runs git push; without an argument the script reads the Edit/Write tool input and prints the reminder for
# the edited file when it belongs to a checkout of this project.

emit() {
    local t=${1//\\/\\\\}
    t=${t//\"/\\\"}
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$t"
}

in=$(cat)
# jq -j, not -r: a native Windows jq.exe ends -r output with CRLF, and the CR would survive the command substitution.
have_jq() { command -v jq >/dev/null 2>&1; }

if [ "$1" = git-push ]; then
    # The hook's `if` runs this for every command Claude Code cannot split, so look for git push at a command start
    # (after env assignments, time, command or nohup), git's global options (-C dir, -c key=value, --no-pager)
    # allowed. Quoted text that starts with git push (a PR title, say) also triggers the reminder, and without jq the
    # raw JSON is searched, so a description that mentions a push may too. POSIX classes, not [A-Z]: under a Turkish
    # locale [A-Z] does not match I.
    if have_jq; then cmd=$(printf '%s' "$in" | jq -j '.tool_input.command // empty'); else cmd=$in; fi
    if printf '%s\n' "$cmd" |
        grep -Eq '(^|[;&|({"]|\\n)[[:space:]]*(([[:alpha:]_][[:alnum:]_]*=[^[:space:]]*|time|command|nohup)[[:space:]]+)*git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:];&|)"\\]|$)'; then
        emit 'REMINDER: run the ci-matrix skill (fmt, clippy, tests and release builds across features, editor selftests) before pushing.'
    fi
    exit 0
fi

if have_jq; then
    f=$(printf '%s' "$in" | jq -j '.tool_input.file_path // empty')
else
    # No jq (common in Git Bash on Windows): read file_path from the raw JSON and undo its \\ escapes.
    f=$(printf '%s' "$in" | grep -o '"file_path" *: *"[^"]*"' | head -n 1 | sed 's/^"file_path" *: *"//; s/"$//; s/\\\\/\\/g')
fi
p=${f//\\//}
case "$p" in */src/*.rs | */Cargo.toml) ;; *) exit 0 ;; esac
. "${0%/*}/checkout.sh"
project_path "$f" || exit 0

w1628='REMINDER: 0x1628 writes to device state go out only on an explicit request and stay 0x1628-only: keymap set/reset --yes (36; base-layer binding confirmed, power-cycle persistence unknown), device region --yes (75, writes flash, [EXPERIMENTAL]), device meta-key (35, [EXPERIMENTAL]), oled show --onboard (38 83, confirmed; the board keeps the image) and live actuation (38 6x; only 38 61 layer 00 confirmed). model_caps.rs refuses the 36, OLED and 38 6x writes on the siblings, require_wired_2023 the region and meta key; on the other boards built as ApexProTkl2023 (models.rs) actuation set/set-value sends the unverified 0x2D guess, and the other keyboard classes refuse it. Promote a status only after a replay from ssgg on hardware.'

case "$rel" in
    src/devices/hid_reports.rs)
        emit 'REMINDER: build reports only through HidReportBuilder and typed HidCommand structs (command_code, serialize, validate); never construct raw byte arrays by hand outside a command'"'"'s serialize (hard constraint 1). CommandCode values stay unique: a command whose wire opcode is already taken gets a free tag, which never goes on the wire. Label new protocol code [EXPERIMENTAL] or [PLACEHOLDER].'
        ;;
    src/devices/keyboards/apex_pro_tkl_2023_profile.rs | src/devices/keyboards/apex_pro_tkl_2023_profile_codec.rs | src/commands/gen3_profile.rs)
        emit 'REMINDER: Gen 3 on-board profile (0x1628): the 83 01 read-back is confirmed on hardware, but the write chain (02 erase, 03 chunks, B1 commit, B2 load, 34) is [EXPERIMENTAL] and not yet replayed from ssgg. It stays 0x1628-only and goes out only through onboard gen3-write, gen3-restore or gen3-activate with --yes. Keep the write gates: every slot read and saved in that run (gen3-restore tolerates the slots it repairs) and a byte-identical codec round trip (the target slot'"'"'s read blob for gen3-write, each saved file for gen3-restore).'
        ;;
    src/commands/onboard.rs | src/devices/keyboards/onboard.rs | src/devices/keyboards/apex_7.rs | src/devices/keyboards/apex_7_profile.rs)
        emit 'REMINDER: on-board profile writes go out only on an explicit request: Apex 7 (0x1612) through onboard write --yes (88, 03, 05, EB, 89, confirmed on hardware, Linux, 2026-10-20) and Gen 3 (0x1628) through the gated onboard gen3-write or gen3-restore --yes ([EXPERIMENTAL], not yet replayed from ssgg). Any other family stays unwired until its write sequence is confirmed on hardware.'
        ;;
    src/devices/keyboards/apex_pro_tkl_2023.rs)
        emit "$w1628"' This file also sends the Gen 3 profile write chain (02 erase, 03 chunks, B1 commit, B2 load, 34; [EXPERIMENTAL], not yet replayed from ssgg): keep require_wired_2023 and the status-0 echo check of every erase, commit and load answer.'
        ;;
    src/commands/keymap.rs | src/commands/apex_2023.rs | src/devices/keyboards/key_action.rs | src/devices/keyboards/model_caps.rs)
        emit "$w1628"
        ;;
    Cargo.toml | */Cargo.toml)
        emit 'REMINDER: hidapi must keep its exact = version pin in Cargo.toml (hard constraint 2); changing it requires explicit task justification.'
        ;;
esac
exit 0
