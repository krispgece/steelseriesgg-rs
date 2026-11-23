#!/usr/bin/env bash
# PostToolUse (Edit|Write): rustfmt the edited .rs file, then flag unwrap()/expect() in its production code under src/
# (src/bin/ excepted). Exit 2 feeds stderr back to Claude; exit 0 stays silent.
in=$(cat)
if command -v jq >/dev/null 2>&1; then
    # -j, not -r: a native Windows jq.exe ends -r output with CRLF, and the CR would hide the .rs suffix.
    f=$(printf '%s' "$in" | jq -j '.tool_input.file_path // empty')
else
    # No jq (common in Git Bash on Windows): read file_path from the raw JSON and undo its \\ escapes.
    f=$(printf '%s' "$in" | grep -o '"file_path" *: *"[^"]*"' | head -n 1 | sed 's/^"file_path" *: *"//; s/"$//; s/\\\\/\\/g')
fi
p=${f//\\//}
case "$p" in *.rs) ;; *) exit 0 ;; esac
[ -f "$f" ] || exit 0

# Without rustfmt on PATH the file stays unformatted; CI's `cargo fmt --check` still applies.
if command -v rustfmt >/dev/null 2>&1; then
    if ! out=$(rustfmt --edition 2024 --config-path "${CLAUDE_PROJECT_DIR:-.}/rustfmt.toml" "$f" 2>&1); then
        printf 'rustfmt failed on %s:\n%s\n' "$p" "$out" >&2
        exit 2
    fi
fi

# Hard constraint 4. The path is classified below the checkout that holds the file (a worktree under
# .claude/worktrees/ is its own checkout), so a checkout that sits under some .../src/... directory does not drag
# tests/ or examples/ in.
root=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null) || root=$CLAUDE_PROJECT_DIR
root=${root//\\//}
rel=$p
[ -n "$root" ] && rel=${p#"$root"/}
if [ "$rel" = "$p" ]; then
    case "$p" in */src/bin/*) rel=src/bin/ ;; */src/*) rel=src/ ;; *) rel= ;; esac
fi
case "$rel" in src/bin/*) exit 0 ;; src/*) ;; *) exit 0 ;; esac

# Each item under #[cfg(test)] or #[cfg(all(test, ..))] is skipped by brace depth (an unbalanced brace in a string or
# char literal inside such an item ends the skip early or late). A brace-less #[cfg(test)] element (a match arm, a
# list element, a call argument) keeps the skip going to the next line with a brace or a trailing `;`, so lines after
# it go unchecked. Comment lines are ignored, and a hit within 3 lines below a comment calling it explicitly fatal
# passes (hard constraint 8).
hits=$(awk '
    skip == 2 { depth += gsub(/[{]/, "{") - gsub(/[}]/, "}"); if (depth <= 0) skip = 0; next }
    /^[[:space:]]*#\[cfg\((all\()?test[,)]/ { skip = 1; sub(/^[[:space:]]*#\[cfg\([^]]*\]/, "") }
    skip == 1 {
        o = gsub(/[{]/, "{"); c = gsub(/[}]/, "}")
        if (o > c) { skip = 2; depth = o - c } else if (o > 0 || c > 0 || $0 ~ /;[[:space:]]*$/) skip = 0
        next
    }
    /^[[:space:]]*\/\// { if ($0 ~ /explicitly fatal/) fatal = NR; next }
    /\.unwrap\(\)|\.expect\(/ && !(fatal && NR - fatal <= 3) { print NR ": " $0 }
' "$f")
if [ -n "$hits" ]; then
    printf 'unwrap()/expect() outside #[cfg(test)] in %s (CLAUDE.md hard constraint 4):\n%s\n' "$p" "$hits" >&2
    exit 2
fi
exit 0
