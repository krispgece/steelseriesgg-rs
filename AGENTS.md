# steelseriesgg-rs — Agent Handbook

## Project context

Open-source SteelSeries GG replacement for Linux. Controls SteelSeries keyboards and headsets via USB HID: RGB lighting effects, a GameSense-compatible HTTP server (port 27301), device profiles, and optional PulseAudio/PipeWire mixer and Sonar integration.

- **Language**: Rust 2024 edition (MSRV and toolchain: see Source-of-truth files)
- **Primary binary**: `ssgg` (`src/main.rs`, clap CLI)
- **Library crate**: `steelseries_gg` (`src/lib.rs`)
- **Platform**: Linux-first; Windows build supported but not primary
- **Config**: `$XDG_CONFIG_HOME/ssgg/config.toml`
- **Repo**: `https://github.com/Ven0m0/steelseriesgg-rs`

---

## Quick orientation

Use `rg --files src/` for the full tree. Non-obvious entry points:

```
src/main.rs                    main() and the active cmd_* handlers (rgb, profile, headset, mouse, remap, ...)
src/commands/                  moved cmd_* families: onboard.rs, gen3_profile.rs, keymap.rs, apex_2023.rs, performance.rs, diagnostics.rs
src/input/                     key remapper; only linux.rs (evdev/uinput) is behind feature `remap`
src/cli.rs                     clap types (Cli, Commands, *Action) and argument parse helpers
src/daemon.rs                  daemon loop, hot-plug monitoring, GameSense startup
src/error.rs                   crate::error::Error (thiserror) + Result alias
src/devices/hid_reports.rs     HidReportBuilder and typed HID commands - use this, not raw bytes
src/devices/discovery.rs       DeviceManager: enumeration, hot-plug, fingerprinting
src/devices/keyboards/         Keyboard impls (apex.rs, apex_7.rs, apex_pro_tkl_2023.rs = mixed, status in the rules file, apex_m750.rs)
src/devices/headsets/          generic headset + nova7.rs (Arctis Nova 7 family, experimental)
src/devices/mice/              rivalcfg Modern family mice (modern.rs, dpi_tables.rs; experimental)
src/gamesense/server.rs        Axum HTTP server (port 27301)
src/audio/                     feature `audio` (pulse.rs) and `sonar` (sonar.rs)
src/gui.rs                     editor + lighting API server, served by `ssgg-gui` (lib module)
src/bin/                       helper binaries, not part of `ssgg` (discover_actuation probes actuation firmware;
                               ssgg-gui = native window around the editor, feature `desktop`)
tools/profile-gui/             profile editor (plain JS, no build step), embedded by src/gui.rs
examples/                      device_readback.rs (hardware read-back example)
scripts/capture-device.ps1     Windows USBPcap capture helper for new-device reports (see docs/development/adding-hardware.md)
assets/                        udev rules, systemd user unit
tests/                         integration tests
docs/development/              reverse-engineering notes; index and per-file state in docs/development/README.md
```

---

## Architecture

- **Two crates, one package.** The library `steelseries_gg` holds devices, lighting, GameSense, config, state and the
  editor server. `cli.rs`, `commands/` and `daemon.rs` are modules of the `ssgg` binary only; the helper binaries in
  `src/bin/` link the library.
- **Opening a device.** `DeviceManager` enumerates vendor `0x1038` through hidapi and types each device by product ID
  (`product_ids` and the lookups in `src/devices/mod.rs`). `open_keyboard` builds a `Box<dyn Keyboard>` from the PID's
  row in `KEYBOARD_MODELS` (`keyboards/models.rs`): the row's `KeyboardClass` picks the implementation, which wraps
  `GenericKeyboard` (the hidapi handle and the legacy report path); a wireless row with `raw_fallback` gets a
  raw-hidraw keyboard when hidapi cannot open it. `Keyboard` methods have defaults (an unsupported error, or a silent
  `Ok` for some lighting calls), so a class overrides only what its protocol has. The Gen 3 siblings of `0x1628` share
  its implementation; `keyboards/model_caps.rs` and a `0x1628`-only check (`require_wired_2023`: profile write and
  activation, region, meta key) refuse what a row lacks before anything is sent. Not gated that way:
  `actuation set`/`set-value` sends the siblings the unverified `0x2D` guess, and the lighting frame follows the
  `models.rs` row, which for some siblings does not match their spec layout (see the rules file). Headsets
  (`headsets::nova7` table, else `GenericHeadset`) and mice (`mice::modern`) keep their own tables.
- **HID commands.** Each command is a typed struct implementing `HidCommand` (`command_code`, `serialize`,
  `validate`). Most keyboard paths build it through `HidReportBuilder::build_report`; the Nova 7 headsets, Modern
  mice, the Apex M750 and the Apex 7 on-board frames call `serialize` directly.
  `CommandCode` values must be unique, so a command whose wire opcode is already taken gets a free tag
  (`0xF2`-`0xFC` today) and writes its real opcode in `serialize`; a tag never goes on the wire.
- **No read-back.** Most boards cannot report their settings, so ssgg keeps what it last applied: `DeviceStateStore`
  (`device_state.rs`, per device) and `SentFrames` (`apex_pro_tkl_2023.rs`, the last direct or threshold frame, the
  base every per-key change merges onto; see `GLOSSARY.md`).
- **Daemon** (`ssgg daemon`): opens devices, follows hot-plug, applies saved poll rates and the default profile,
  starts the GameSense server (its events become 30-second zone overlays in `DaemonState`) and runs the animation
  loop, which streams one per-key frame per `DIRECT_FRAME_INTERVAL` to direct-frame boards. On exit it sends the
  `0x41` release to `0x1628` boards and saves device state.
- **On-board profiles** are two unrelated protocols. Apex 7 (`0x1612`): `ssgg onboard read|decode|encode|write|load`
  through `Keyboard::onboard_codec` and `OnboardProfileCodec` (`keyboards/onboard.rs`, `apex_7_profile.rs`); the codec
  runs on files with no device. Gen 3 (`0x1628`): the 12,500-byte blob (`apex_pro_tkl_2023_profile*.rs`),
  `ssgg onboard gen3-*`.
- **Profile editor.** `build.rs` copies the `tools/profile-gui/` files into `OUT_DIR` (minified with `desktop`),
  `src/gui.rs` embeds them and serves them plus a token-guarded API on 127.0.0.1 (lighting, headset, and `/api/cli`,
  which runs allowlisted `ssgg` subcommands, on-board writes and loads, actuation and OLED included), and `ssgg-gui`
  wraps that in a native window. `products.generated.js` is generated from the Rust tables: after changing
  `product_ids`, `KEYBOARD_MODELS` or the on-board codec registry, run `node tools/profile-gui/sync-products.mjs`, or
  the selftest fails on drift.

---

## Source-of-truth files

When prose docs and code disagree, always trust these files. Do not quote toolchain, MSRV, or pinned dependency versions from memory or from this document; read them.

| File | What it controls |
|------|-----------------|
| `Cargo.toml` | dependency versions and pins, features, MSRV, edition |
| `rust-toolchain.toml` | toolchain channel and components |
| `.github/workflows/ci.yml` | exact CI commands, pinned CI toolchain, feature matrix |
| `src/devices/hid_reports.rs` | HID command codes and report layouts |

---

## Toolchain and CI

### Local commands

Run the smallest relevant subset for any given change.

| Step | Command |
|------|---------|
| Format check | `cargo fmt --all -- --check` |
| Lint | `cargo clippy --all-targets --locked -- -D warnings` |
| Test | `cargo test --locked` |
| Release build | `cargo build --release --locked` |
| Single test | `cargo test --locked <name-filter>`; `--test cli_smoke` runs one file in `tests/` (unit tests sit in `#[cfg(test)]` modules) |
| Ignored tests | `cargo test --locked -- --ignored` (the Gen 3 profile codec one needs `SSGG_GEN3_PROFILE_DIR` with blobs read from a keyboard) |
| Editor selftest | `node tools/profile-gui/selftest.mjs` (Node 20.11 or newer) |

`.cargo/config.toml` builds for `x86-64-v3` by default; release CI also builds generic `x86-64` by setting
`RUSTFLAGS=-Ctarget-cpu=x86-64` (env overrides the config; `SSGG_TARGET_CPU` does the same inside the PKGBUILD).
Add `--features <flag>` when touching feature-gated code. The CI feature matrix is in
`.github/workflows/ci.yml`; the `ci-matrix` skill runs every job locally, editor selftests included, except
`test-windows` (`cargo test --locked` on Windows). The `audio` feature needs `libpulse-dev` on Debian/Ubuntu; it
builds on Windows but applies nothing there (the PulseAudio backend is Linux-only).
`cargo clippy-ci` (a `.cargo/config.toml` alias) and the pre-commit clippy hook are not the CI lint: both add
`--all-features --fix`, so they rewrite files and need the `audio` and `desktop` system packages.

---

## Feature flags

| Flag | Enables | Extra dep |
|------|---------|-----------|
| *(none)* | Core RGB, GameSense, profiles | — |
| `audio` | AudioMixer, PulseAudio/PipeWire backend | `libpulse-dev` |
| `sonar` | SonarClient HTTP integration, `sonar_control` binary | `reqwest` (rustls; no system package) |
| `remap` | `ssgg remap run`: evdev key remapper (Linux only) | `evdev` (Linux target), `rustix/event` |
| `desktop` | `ssgg-gui`: native window around the profile editor (`build.rs` minifies its HTML/CSS/JS) | `wry`, `tao`; build-deps `minify-html`, `oxc_*`, `lightningcss`; Linux needs `libwebkit2gtk-4.1-dev`, `libgtk-3-dev` |

`audio`, `sonar`, `remap` and `desktop` are independent; do not couple them. Experimental protocol paths are not feature-gated; they carry
`[EXPERIMENTAL]` labels instead (see `.claude/rules/experimental-protocol.md`).

---

## Hard constraints

1. **HID reports**: always use `HidReportBuilder` and typed helpers in `src/devices/hid_reports.rs`. Never build raw byte arrays by hand.
2. **hidapi pin**: keep the exact `=` pin on `hidapi` in `Cargo.toml`; changing it requires explicit task justification.
3. **GameSense CORS**: enforce localhost-only origin; the policy may only be tightened, never relaxed.
4. **Propagate errors**: use `?` or return an explicit `Err` value — no `unwrap` or `expect` in production paths.
5. **Error types**: `crate::error::Error` (`thiserror`) in the library and in `ssgg` itself (`main.rs`, `commands/` and `daemon.rs` return `steelseries_gg::Result`); `anyhow` with `context()` only in the helper binaries under `src/bin/`.
6. **Protocol accuracy**: the direct-mode frames (`0x40`, `0x61`, `0x3A`), the profile blob and `PerKeyRgb (0x23)` are reverse-engineered; what was replayed on hardware is listed per command in `.claude/rules/experimental-protocol.md`. Label new protocol work clearly; never state it as confirmed unless tested on hardware.
7. **Minimal scope**: fix what the task asks, nothing more. No opportunistic refactors.
8. **No mutable global state**, no panics in non-test code (unless explicitly fatal and documented), no ignored `Result`s.
9. **`unsafe` blocks** must document the safety invariant inline.
10. **Platform-gated deps**: Unix-only crates (`rustix`) live under `[target.'cfg(unix)'.dependencies]`; keep uses behind matching `cfg`.

---

## Rust conventions

- Naming: `snake_case` for functions and modules, `PascalCase` for types and traits, `SCREAMING_SNAKE_CASE` for constants.
- `rustfmt.toml`: edition 2024 style, max 120 columns, 4-space indentation.
- Prefer `&T` borrows over owned values when ownership is not needed.
- New dependencies require justification; avoid heavy transitive deps.
- No comments that restate what the code does — comment only non-obvious invariants or workarounds.

---

## Working rules

- **Search before reading**: `rg 'TypeName|fn_name' src/`, then read only the relevant lines. Large files:
  `src/devices/hid_reports.rs`, `src/devices/keyboards/apex_7_profile.rs`, `src/devices/keyboards/apex_pro_tkl_2023.rs`,
  `tools/profile-gui/app.js`, `src/main.rs`.
- **Documents**: only create planning or analysis documents when explicitly requested.
- **Hardware steps**: prepare the build and the exact commands, ask the owner to run them, and record only results
  they confirm (`PLAN.md`, "How to work this list").
- **Commits**: Conventional Commits (`feat`, `fix`, `docs`, `deps`, `ci`, ...); release-please builds the version,
  `CHANGELOG.md` and the `PKGBUILD` version from them.

## Project tooling (`.claude/`)

- Skills: `ci-matrix` (full local CI), `gui-selftest` (editor selftest, source and minified), `hid-protocol` (auto-loads for `src/devices/`), `hw-capture`, `promote-protocol`, `dep-audit`, `fuzz-runner`, `benchmark-compare`.
- Commands: `/new-device` (scaffold a device and register it), `/pr-check` (pre-PR go/no-go).
- Review agents: `protocol-reviewer` (device diffs), `security-reviewer` (GameSense server), `gui-reviewer` (editor, `src/gui.rs`, `build.rs`), `dependency-auditor`, `docs-drift-auditor`, `re-verifier`, `release-reviewer`.
- Hooks (`.claude/settings.json`, scripts in `.claude/hooks/`): edits to `Cargo.lock`, `CHANGELOG.md`,
  `.release-please-manifest.json` and `tools/profile-gui/products.generated.js` are blocked; edits to `hid_reports.rs`,
  `Cargo.toml` and the Apex 7 / Gen 3 profile and device-write files get a reminder (`remind.sh`), and so does
  `git push` (run `ci-matrix` first). An edited `.rs` file is rustfmt'ed when rustfmt is on PATH, and one under `src/`
  (not `src/bin/`) is flagged for `unwrap`/`expect` outside `#[cfg(test)]` items; a `Cargo.toml` that loses the exact
  `hidapi` pin is flagged. In the background (`post-check.sh`), `src/devices/` edits run clippy, and editor edits and
  edits to the Rust tables the editor reads run its selftest (without cargo no clippy; below Node 20.11 only the
  `sync-products.mjs --check` drift check); failures come back as a message.
- Permissions: device-writing `ssgg` commands (on-board writes and loads, key mappings, region, meta key, actuation,
  `oled show --onboard`, `fuzz`) and the `discover_actuation` / `verify_key_mapping` probes need approval, in the Bash
  and the PowerShell tool. The rules match anywhere in a command, so one that only quotes such an invocation (an `rg`
  for `ssgg keymap set`, a commit message) prompts too; search for the subcommand without the binary name.

---

## Protocol research notes

- `docs/development/README.md` lists each doc and its state. Source still wins; verify before acting on a doc claim.
- Command-code status (confirmed / experimental / placeholder): `.claude/rules/experimental-protocol.md`.
- Apex Pro TKL 2023 wired (PID `0x1628`, firmware `1.19.7`): transport, lighting frame, profile blob, slot map,
  checksum, 64-byte commands, GG's stored config and the Frida trace are in
  `docs/development/apex-pro-tkl-2023-gg-capture.md`. Status per frame in the rules file. Invariants to keep in mind:
  - **Confirmed on hardware** (Windows, fw 1.19.7): `0x40` solid colours, per-key frames, software brightness and
    25 fps effect streaming; `0x41` release; `1F 81/82` and `38 83` OLED; `38 61` layer 0 actuation; the `83 01`
    profile read-back of all five slots; `36`/`B6`/`B7` key mappings and macro read; `F2`/`F5` device info
    (2026-11-10/11). Linux hidraw is untested.
  - **On-board profile writes are gated, not forbidden** (2026-11-10): the read-back works, so a write is allowed only
    through `ssgg onboard gen3-write --yes` (`gen3-restore` for saved blobs) after every slot was read and saved in
    that run and the read blob of the target slot re-encodes byte-identically (`[EXPERIMENTAL]`, not yet replayed from
    `ssgg` on hardware). GG itself persists bindings, rapid-tap pairs, lock colours and the OLED image by
    rewriting the whole slot (`02 01`, 25 x `03 01`, `B1`, `B2`, `34 00`); it never sends `36`/`B6` on this model.
  - **Lighting read-back**: none (the board keeps no effect; GG streams `0x40` host-rendered frames). The profile
    blob is the only read-back for settings.
  - **GG overwrites ssgg** at about 19 fps while `SteelSeriesEngine.exe` runs. Stop GG before any hardware test.

### Verification tooling (Windows)

Use these to check protocol claims against what official GG really does, before promoting any status. Never modify
the target process or GG's files. Record device, firmware and date for every result.

| Question | Tool | How |
|----------|------|-----|
| What bytes does GG put on the wire? | USBPcap + tshark | `C:\Program Files\USBPcap\USBPcapCMD.exe -d \\.\USBPcap1 -o <file> -A` (no args = interactive, hangs). Read with `C:\Program Files\Wireshark\tshark.exe -e frame.time_epoch -e usb.data_fragment`; filter `usb.setup.bRequest==9 && usb.bmRequestType==0x21 && usb.setup.wValue==0x0300` (`0x0200` = output reports). Re-check the device address after changing ports. |
| Which HID calls does the engine make, and does a UI action trigger a command? | Frida (`frida`, `frida-trace` in `~/.venv`; or `rea` MCP `start_frida_session` / `instrument_with_frida`) | Attach read-only to `SteelSeriesEngine.exe`; hook kernel32 `ReadFile` / `WriteFile` / `DeviceIoControl` for small buffers only (large-buffer hooks coincided with engine restarts). Heap reads (`ReadProcessMemory`) recover the decoded live settings JSON; `*.edevice` files are encrypted and need no decryption. |
| What does a GG binary do (`HIDDLL.dll`, `SSEdevice.dll`)? | Ghidra, else `rea` MCP (Rizin/Cutter tools) | Ghidra is not on PATH on this machine; use `analyzeHeadless` if installed. Prefer Frida first, static analysis only when runtime tracing cannot answer. |
| What config does GG store? | SQLite, read-only | `C:\ProgramData\SteelSeries\GG\apps\engine\db\database.db`, table `configurations`, column `settings`, `device_id` 242. Open with GG stopped. |

A capture or trace proves what GG sends; it does not make an `ssgg` frame Confirmed. Confirmed needs the frame
replayed from `ssgg` on hardware (see `.claude/rules/experimental-protocol.md`).

Gotchas:
- Stop GG: kill every `SteelSeries*` process, or the engine respawns. Restart from `C:\Program Files\SteelSeries\GG`
  with `SteelSeriesGGEZ.exe -dataPath="C:\ProgramData\SteelSeries\GG" -dbEnv=production`
  (`SteelSeriesGG.exe` alone exits with code 2).
- Never launch GUI capture prompters with `-WindowStyle Hidden`; it hides the form.
- `ctx_execute_file` refuses paths outside the project; run analysis scripts with `python -I <script> <args>`.
- Capture artifacts live outside the repo in `%USERPROFILE%\gg-capture-artifacts\`: `blobs.bin` / `blobs3.bin`
  (12,500-byte profile blobs, 8 distinct) and `profile_crc_check.py <blob files>`. The original pcaps are gone.

---

## Backlog

Tracked in `PLAN.md` only. Do not duplicate status here.
