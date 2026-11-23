#!/usr/bin/env bash
# PreToolUse (Edit|Write): block hand edits to generated files (cargo, release-please, sync-products.mjs).
in=$(cat)
if command -v jq >/dev/null 2>&1; then
    # -j, not -r: a native Windows jq.exe ends -r output with CRLF, and the CR would break every pattern below.
    f=$(printf '%s' "$in" | jq -j '.tool_input.file_path // empty')
else
    # No jq (common in Git Bash on Windows): read file_path from the raw JSON and undo its \\ escapes.
    f=$(printf '%s' "$in" | grep -o '"file_path" *: *"[^"]*"' | head -n 1 | sed 's/^"file_path" *: *"//; s/"$//; s/\\\\/\\/g')
fi
p=${f//\\//}
case "$p" in
    */Cargo.lock | */CHANGELOG.md | */.release-please-manifest.json)
        echo "BLOCKED: $p is generated (cargo / release-please). Run cargo or let release-please update it." >&2
        exit 2
        ;;
    */tools/profile-gui/products.generated.js)
        echo "BLOCKED: $p is generated from the Rust tables. Run node tools/profile-gui/sync-products.mjs instead." >&2
        exit 2
        ;;
esac
exit 0
