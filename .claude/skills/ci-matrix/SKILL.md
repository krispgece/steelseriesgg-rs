---
name: ci-matrix
description: Run the full local CI matrix for steelseriesgg-rs, matching .github/workflows/ci.yml (every job but the Windows test, which only CI runs). Use this whenever the user asks to run CI, check all feature variants, run the full test suite, verify before pushing, or run clippy/fmt/tests across features. Invoke proactively before any push or PR review.
---

Run the full CI matrix locally. Stop at the first failure and report it clearly.

## Steps

Run each command in order. If a command fails, report the error output and stop — do not continue to the next step.

**1. Format check**
```
cargo fmt --all -- --check
```

**2. Clippy — default features**
```
cargo clippy --all-targets --locked -- -D warnings
```

**3. Clippy — sonar feature**
```
cargo clippy --all-targets --locked --features sonar -- -D warnings
```

**4. Clippy — audio feature**
```
cargo clippy --all-targets --locked --features audio -- -D warnings
```
Skip and note as skipped if `libpulse-dev` is not installed (the error will mention `libpulse-binding`).

**5. Clippy — remap feature** (Linux only; the evdev layer compiles out elsewhere)
```
cargo clippy --all-targets --locked --features remap -- -D warnings
```

**6. Clippy — desktop feature**
```
cargo clippy --all-targets --locked --features desktop -- -D warnings
```
On Linux, skip and note as skipped if `pkg-config --exists webkit2gtk-4.1 gtk+-3.0` fails (`libwebkit2gtk-4.1-dev` or `libgtk-3-dev` is not installed; CI installs both).

**7. Tests — default features**
```
cargo test --locked
```

**8. Tests — sonar feature**
```
cargo test --locked --features sonar
```

**9. Tests — remap feature**
```
cargo test --locked --features remap
```

**10. Tests — desktop feature**
```
cargo test --locked --features desktop
```
Skip and note as skipped under the same condition as step 6.

**11. Profile GUI selftest — source files**
```
node tools/profile-gui/selftest.mjs
```
Skip and note as skipped if `node` is missing or older than 20.11 (`node --version`): the selftest reads its files through `import.meta.dirname`, and older Node fails at once with `ENOENT ... 'undefined/products.generated.js'`.

**12. Profile GUI selftest — minified files**
```
out_dir=$(cargo check --locked --features desktop --message-format=json \
  | jq -r 'select(.reason == "build-script-executed" and (.package_id | test("steelseries"))) | .out_dir' \
  | tail -1)
test -f "$out_dir/app.js" &&
SSGG_GUI_DIR="$out_dir" node tools/profile-gui/selftest.mjs
```
Skip and note as skipped under the conditions of steps 6 and 11, or if `jq` is missing.

**13. Build — default features**
```
cargo build --release --locked
```

**14. Build — sonar feature**
```
cargo build --release --locked --features sonar
```

**15. Build — audio feature**
```
cargo build --release --locked --features audio
```
Skip and note as skipped if `libpulse-dev` is not installed (same condition as step 4).

**16. Build — remap feature**
```
cargo build --release --locked --features remap
```

**17. Build — desktop feature**
```
cargo build --release --locked --features desktop
```
Skip and note as skipped under the same condition as step 6.

**18. Binary check**
```
test -f "${CARGO_TARGET_DIR:-target}/release/ssgg"
```
On Windows the file is `ssgg.exe`.

CI's `test-windows` job (`cargo test --locked` on `windows-latest`) cannot run on Linux: report it as not run locally, never as passed. On a Windows machine, step 7 is that job.

## Report format

After all steps pass, report:
- Which steps ran and passed
- Any steps skipped and why
- That CI's `test-windows` job was not run (unless this run was on Windows)
- Total time if notable

If a step fails, report:
- Which step failed
- The relevant error lines (trim noise, keep the actionable part)
- What to fix
