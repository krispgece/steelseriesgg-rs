# Sourced by the Edit/Write hooks. `project_path <file>` sets `root` to the checkout of this project that holds the
# file (a worktree under .claude/worktrees/ is its own checkout) and `rel` to the file's path below it, and fails for a
# file anywhere else, so the hooks leave other repositories (Tune, a scratch crate, ~/.cargo/registry) alone.
project_path() {
    local p=${1//\\//} d tail out r
    case "$p" in */*) d=${p%/*} ;; *) d=. ;; esac
    tail=${p##*/}
    # A Write can create the directory too: start from the nearest one that exists.
    while [ ! -d "${d:-/}" ]; do
        case "$d" in */*) ;; *) return 1 ;; esac
        tail=${d##*/}/$tail
        d=${d%/*}
    done
    d=${d:-/}
    # git prints the physical toplevel, which a path spelled through a symlink does not start with; --show-prefix
    # gives the directory relative to it either way (an empty prefix leaves only the toplevel line).
    if out=$(git -C "$d" rev-parse --show-toplevel --show-prefix 2>/dev/null); then
        out=${out//$'\r'/}
        root=${out%%$'\n'*}
        case "$out" in *$'\n'*) rel=${out#*$'\n'}$tail ;; *) rel=$tail ;; esac
        is_project "$root" && return 0
        # Another repository: a copy of this project without .git inside its work tree still counts, a repository
        # cloned somewhere inside this project's directory does not.
        [ -n "$CLAUDE_PROJECT_DIR" ] || return 1
        out=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
        [ "${out//$'\r'/}" = "$root" ] || return 1
    fi
    # A copy without .git.
    root=$CLAUDE_PROJECT_DIR
    r=${root//\\//}
    rel=${p#"$r"/}
    [ -n "$r" ] && [ "$rel" != "$p" ] && is_project "$root"
}

# This project, in any version: the editor's product sync script (since v0.1.8) or the package name (since v0.1.0).
is_project() {
    [ -f "$1/tools/profile-gui/sync-products.mjs" ] ||
        grep -Eqs '^[[:space:]]*name[[:space:]]*=[[:space:]]*"steelseries-gg-linux"' "$1/Cargo.toml"
}
