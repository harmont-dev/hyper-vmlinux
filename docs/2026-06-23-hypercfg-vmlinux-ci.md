# hypercfg — vmlinux Build & Publish Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new standalone repo `harmont-dev/hypercfg` containing kernel configs, build scripts, and a manually-triggered GitHub Actions workflow that — for every config in `_hypercfg/` — fetches the matching latest stable Linux source from kernel.org, builds a Firecracker-bootable kernel image, and publishes one GitHub Release per config with the artifact, its `sha256`, and a machine-readable `manifest.json` — plus an aggregate `index.json` so `harmont-dev/hyper` can discover and verify artifacts automatically.

**Architecture:** Because builds pull source tarballs from kernel.org, the workflow needs no Linux source tree — so it lives in its own lightweight repo, not the linux mirror (no multi-GB checkout, no rebasing, no mirror pollution). All logic lives in four small, independently-testable Bash scripts under `scripts/` (config-to-matrix parser, kernel-version resolver, kernel builder, manifest writer). The workflow YAML (`.github/workflows/build-vmlinux.yml`) is a thin orchestrator: a `prepare` job turns `_hypercfg/*.config` into a build matrix, a fan-out `build` job builds + publishes per config on native runners per arch, and an `index` job aggregates manifests into a discovery index. Scripts are TDD'd with `bats-core`; the YAML is linted with `actionlint`.

**Tech Stack:** GitHub Actions (`workflow_dispatch`), Bash, `jq`, `curl`, the Linux kbuild system, `gh` CLI for repo + releases, `bats-core` for tests, `actionlint` for YAML linting.

## Global Constraints

- **This work happens in a NEW repo, not the linux mirror.** Create `harmont-dev/hypercfg` (see Task 1). Do not commit any of this to `harmont-dev/linux`. The existing plan file in the linux mirror's `docs/` is copied into the new repo in Task 1 and must not be committed to the mirror.
- **Repo visibility: public.** Required for free GitHub-hosted `ubuntu-24.04-arm` runners and for `hyper` to download release assets without a token.
- **Default branch is `main`; land the workflow on `main`.** `workflow_dispatch` only appears in the Actions UI for workflows present on the repository's default branch. Per-task commits go to `main` (or a short-lived branch merged to `main` before the first dispatch).
- **Target repo (releases land here):** `harmont-dev/hypercfg`. Consumer: `harmont-dev/hyper`.
- **Configs are version-specific:** configs target 5.10 / 6.1. The matching source is always fetched from kernel.org — there is no local kernel tree to build against.
- **Repo layout (exact):**
  - `_hypercfg/*.config` — the kernel configs.
  - `_hypercfg/sources.json`, `_hypercfg/SOURCES.md` — provenance.
  - `scripts/*.sh` — the four build scripts.
  - `tests/*.bats`, `tests/helpers.bash`, `tests/fixtures/` — tests.
  - `.github/workflows/build-vmlinux.yml` — the workflow.
  - `README.md` — repo readme + consumer contract.
  - `docs/2026-06-23-hypercfg-vmlinux-ci.md` — this plan (copied in Task 1).
- **`_hypercfg/` config filename grammar (exact):** `<arch>-<series>[-<variant>].config` where `arch ∈ {x86_64, aarch64}`, `series` is `MAJOR.MINOR` (e.g. `5.10`), `variant` is an optional dash-joined suffix (e.g. `no-acpi`). Examples: `x86_64-6.1.config`, `x86_64-5.10-no-acpi.config`.
- **Arch mapping (exact, used everywhere):**
  | `arch` | kbuild `ARCH` | runner | build target | artifact filename | artifact build path |
  |---|---|---|---|---|---|
  | `x86_64` | `x86_64` | `ubuntu-24.04` | `vmlinux` | `vmlinux` | `./vmlinux` |
  | `aarch64` | `arm64` | `ubuntu-24.04-arm` | `Image` | `Image` | `./arch/arm64/boot/Image` |
- **kernel.org source dir mapping:** `series` major `5` → `v5.x`, major `6` → `v6.x`. Tarball URL: `https://cdn.kernel.org/pub/linux/kernel/<vdir>/linux-<full_version>.tar.xz`.
- **Release tag scheme (exact):** `vmlinux-<config-name>-<full_version>` — e.g. `vmlinux-x86_64-5.10-no-acpi-5.10.240`. `<config-name>` is the config filename without `.config`. Tags are immutable per resolved kernel point release.
- **Aggregate index release (exact):** tag `hypercfg-index`, single asset `index.json`, clobbered on every run.
- **`schema_version` (manifest.json and index.json):** integer `1`. Do not change without updating `hyper`.
- **Native builds only:** no cross-compilation. Each arch builds on its own native runner; `ARCH` is set explicitly but `CROSS_COMPILE` is never set.
- **Determinism for consumers:** every published artifact MUST have a sibling `<artifact>.sha256` (`sha256sum` format: `<hash>  <filename>`) and appear in `manifest.json` with its sha256, size, and source provenance.
- **Firecracker config upstream (raw URLs), mapped to `_hypercfg/` names:**
  | `_hypercfg/` filename | upstream raw URL |
  |---|---|
  | `aarch64-5.10.config` | `https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-aarch64-5.10.config` |
  | `aarch64-6.1.config` | `https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-aarch64-6.1.config` |
  | `x86_64-5.10-no-acpi.config` | `https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-5.10-no-acpi.config` |
  | `x86_64-5.10.config` | `https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-5.10.config` |
  | `x86_64-6.1.config` | `https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-6.1.config` |

---

## File Structure

- `_hypercfg/*.config` — the five Firecracker kernel configs (Task 2).
- `_hypercfg/sources.json` — machine-readable map `config-name → upstream URL` for provenance (Task 2).
- `_hypercfg/SOURCES.md` — human-readable provenance (Task 2).
- `scripts/parse-configs.sh` — scan `_hypercfg/`, emit one JSON matrix entry per config (Task 3).
- `scripts/resolve-kernel.sh` — given a series, resolve latest point release + source sha256 from kernel.org's signed `sha256sums.asc` (Task 4).
- `scripts/make-manifest.sh` — emit `manifest.json` + `<artifact>.sha256` for a built artifact (Task 5).
- `scripts/build-kernel.sh` — orchestrate download → verify → configure → build → stage artifact (Task 6).
- `tests/helpers.bash` — shared path helpers (Task 1).
- `tests/*.bats` — bats tests for the four scripts (Tasks 3–6).
- `tests/fixtures/` — test fixtures (e.g. trimmed `sha256sums.asc`) (Task 4).
- `README.md` — repo readme + consumer contract for `hyper` (Task 10).
- `.github/workflows/build-vmlinux.yml` — the orchestrating workflow (Tasks 7–9).

---

### Task 1: Create the standalone repo + scaffold + test tooling

**Files:**
- Create: repo `harmont-dev/hypercfg`, cloned locally (e.g. `/home/marko/hypercfg`).
- Create: `scripts/.gitkeep`, `tests/fixtures/.gitkeep`, `tests/helpers.bash`, `docs/2026-06-23-hypercfg-vmlinux-ci.md`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a public GitHub repo `harmont-dev/hypercfg` with default branch `main`, cloned locally; a `bats` runner available via `npx bats` or `bats`; a `helpers.bash` exposing `repo_root` (absolute path to repo root), `scripts_dir`, and `fixtures_dir` for tests. **All subsequent tasks run with CWD = the new repo root.**

- [ ] **Step 1: Create and clone the new public repo**

```bash
cd /home/marko
gh repo create harmont-dev/hypercfg --public --clone \
  --description "Firecracker-bootable vmlinux builds published as releases"
cd /home/marko/hypercfg
git status
```
Expected: an empty repo cloned into `/home/marko/hypercfg`, on branch `main`. If `main` doesn't exist yet (empty repo), the first commit in Step 6 establishes it.

- [ ] **Step 2: Copy this plan into the new repo**

```bash
mkdir -p docs scripts tests/fixtures
cp /home/marko/linux/docs/superpowers/plans/2026-06-23-hypercfg-vmlinux-ci.md docs/
touch scripts/.gitkeep tests/fixtures/.gitkeep
```

- [ ] **Step 3: Write `.gitignore`**

Create `.gitignore`:

```gitignore
# Build scratch / staged artifacts
/out/
/work/
*.tar.xz
*.tar.gz
# Local actionlint binary
/actionlint
```

- [ ] **Step 4: Write the test helper**

Create `tests/helpers.bash`:

```bash
# Shared helpers for hypercfg bats tests.
# Resolves paths relative to this file so tests run from any CWD.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
scripts_dir() {
  echo "$(repo_root)/scripts"
}
fixtures_dir() {
  echo "$(repo_root)/tests/fixtures"
}
```

- [ ] **Step 5: Verify bats and jq are available**

Run: `npx --yes bats --version || bats --version; jq --version`
Expected: prints a `Bats 1.x.x` line and a `jq-1.x` line. If missing: `sudo apt-get update && sudo apt-get install -y bats jq`.

- [ ] **Step 6: Commit**

```bash
git add .gitignore scripts/.gitkeep tests/fixtures/.gitkeep tests/helpers.bash docs/2026-06-23-hypercfg-vmlinux-ci.md
git commit -m "chore: scaffold hypercfg repo, test helpers, and plan"
```

---

### Task 2: Vendor the Firecracker configs + provenance

**Files:**
- Create: `_hypercfg/aarch64-5.10.config`, `_hypercfg/aarch64-6.1.config`, `_hypercfg/x86_64-5.10-no-acpi.config`, `_hypercfg/x86_64-5.10.config`, `_hypercfg/x86_64-6.1.config`
- Create: `_hypercfg/sources.json`, `_hypercfg/SOURCES.md`

**Interfaces:**
- Consumes: nothing.
- Produces: five `*.config` files following the filename grammar; `sources.json` — a JSON object mapping `config-name` (no `.config`) → upstream raw URL, consumed by `parse-configs.sh` (Task 3) to populate `fc_origin`.

- [ ] **Step 1: Download and rename the five configs**

```bash
mkdir -p _hypercfg
base="https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs"
curl -fsSL "$base/microvm-kernel-ci-aarch64-5.10.config"        -o _hypercfg/aarch64-5.10.config
curl -fsSL "$base/microvm-kernel-ci-aarch64-6.1.config"         -o _hypercfg/aarch64-6.1.config
curl -fsSL "$base/microvm-kernel-ci-x86_64-5.10-no-acpi.config" -o _hypercfg/x86_64-5.10-no-acpi.config
curl -fsSL "$base/microvm-kernel-ci-x86_64-5.10.config"         -o _hypercfg/x86_64-5.10.config
curl -fsSL "$base/microvm-kernel-ci-x86_64-6.1.config"          -o _hypercfg/x86_64-6.1.config
```

- [ ] **Step 2: Verify all five downloaded and look like kernel configs**

Run:
```bash
for f in _hypercfg/*.config; do
  test -s "$f" && head -1 "$f" | grep -q "Automatically generated" && echo "OK $f" || echo "BAD $f"
done
```
Expected: five `OK` lines (firecracker configs begin with `# Automatically generated file; DO NOT EDIT.`). Re-download any `BAD` file.

- [ ] **Step 3: Write `_hypercfg/sources.json`**

Create `_hypercfg/sources.json`:

```json
{
  "aarch64-5.10": "https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-aarch64-5.10.config",
  "aarch64-6.1": "https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-aarch64-6.1.config",
  "x86_64-5.10-no-acpi": "https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-5.10-no-acpi.config",
  "x86_64-5.10": "https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-5.10.config",
  "x86_64-6.1": "https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-6.1.config"
}
```

- [ ] **Step 4: Validate sources.json keys match the config files**

Run:
```bash
jq -e 'keys == (["aarch64-5.10","aarch64-6.1","x86_64-5.10","x86_64-5.10-no-acpi","x86_64-6.1"])' _hypercfg/sources.json
```
Expected: prints `true`.

- [ ] **Step 5: Write `_hypercfg/SOURCES.md`**

Create `_hypercfg/SOURCES.md`:

```markdown
# _hypercfg config provenance

These kernel configs are vendored from the Firecracker project's
`resources/guest_configs/` directory, renamed to the
`<arch>-<series>[-<variant>].config` grammar used by the publish workflow.

| _hypercfg file | upstream file |
|---|---|
| `aarch64-5.10.config` | `microvm-kernel-ci-aarch64-5.10.config` |
| `aarch64-6.1.config` | `microvm-kernel-ci-aarch64-6.1.config` |
| `x86_64-5.10-no-acpi.config` | `microvm-kernel-ci-x86_64-5.10-no-acpi.config` |
| `x86_64-5.10.config` | `microvm-kernel-ci-x86_64-5.10.config` |
| `x86_64-6.1.config` | `microvm-kernel-ci-x86_64-6.1.config` |

Upstream: https://github.com/firecracker-microvm/firecracker (branch `main`).
Machine-readable source URLs live in `sources.json`.

To add a target: drop a `<arch>-<series>[-<variant>].config` file here, add its
entry to `sources.json`, and the publish workflow picks it up on the next run.
```

- [ ] **Step 6: Commit**

```bash
git add _hypercfg/*.config _hypercfg/sources.json _hypercfg/SOURCES.md
git commit -m "feat: vendor firecracker kernel configs with provenance"
```

---

### Task 3: `parse-configs.sh` — configs → build matrix

**Files:**
- Create: `scripts/parse-configs.sh`
- Test: `tests/parse-configs.bats`

**Interfaces:**
- Consumes: `_hypercfg/*.config` files and `_hypercfg/sources.json` (Task 2).
- Produces: `parse-configs.sh [dir]` (default dir `_hypercfg`) prints, one compact JSON object per line, an entry per config with EXACTLY these keys: `name` (config filename without `.config`), `config` (path to the config file), `arch`, `kbuild_arch`, `series`, `variant` (empty string when none), `vdir`, `runner`, `target`, `artifact`, `fc_origin`. Consumed by the workflow `prepare` job (Task 7), which wraps the lines into `{"include":[...]}`.

- [ ] **Step 1: Write the failing test**

Create `tests/parse-configs.bats`:

```bash
#!/usr/bin/env bats

setup() {
  load helpers
  SCRIPT="$(scripts_dir)/parse-configs.sh"
  TMP="$(mktemp -d)"
  : > "$TMP/x86_64-6.1.config"
  : > "$TMP/x86_64-5.10-no-acpi.config"
  : > "$TMP/aarch64-5.10.config"
  cat > "$TMP/sources.json" <<'JSON'
{ "x86_64-6.1": "https://example/x86.config" }
JSON
}

teardown() { rm -rf "$TMP"; }

@test "emits one json line per config" {
  run bash "$SCRIPT" "$TMP"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 3 ]
}

@test "x86_64-6.1 maps arch, runner, target, vdir correctly" {
  run bash "$SCRIPT" "$TMP"
  line="$(echo "$output" | jq -c 'select(.name=="x86_64-6.1")')"
  [ "$(echo "$line" | jq -r .arch)" = "x86_64" ]
  [ "$(echo "$line" | jq -r .kbuild_arch)" = "x86_64" ]
  [ "$(echo "$line" | jq -r .runner)" = "ubuntu-24.04" ]
  [ "$(echo "$line" | jq -r .target)" = "vmlinux" ]
  [ "$(echo "$line" | jq -r .artifact)" = "vmlinux" ]
  [ "$(echo "$line" | jq -r .series)" = "6.1" ]
  [ "$(echo "$line" | jq -r .variant)" = "" ]
  [ "$(echo "$line" | jq -r .vdir)" = "v6.x" ]
  [ "$(echo "$line" | jq -r .fc_origin)" = "https://example/x86.config" ]
}

@test "aarch64 maps to arm64 kbuild arch, arm runner and Image target" {
  run bash "$SCRIPT" "$TMP"
  line="$(echo "$output" | jq -c 'select(.name=="aarch64-5.10")')"
  [ "$(echo "$line" | jq -r .kbuild_arch)" = "arm64" ]
  [ "$(echo "$line" | jq -r .runner)" = "ubuntu-24.04-arm" ]
  [ "$(echo "$line" | jq -r .target)" = "Image" ]
  [ "$(echo "$line" | jq -r .vdir)" = "v5.x" ]
}

@test "parses multi-token variant" {
  run bash "$SCRIPT" "$TMP"
  line="$(echo "$output" | jq -c 'select(.name=="x86_64-5.10-no-acpi")')"
  [ "$(echo "$line" | jq -r .series)" = "5.10" ]
  [ "$(echo "$line" | jq -r .variant)" = "no-acpi" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx --yes bats tests/parse-configs.bats`
Expected: FAIL — `parse-configs.sh` does not exist (`No such file or directory`).

- [ ] **Step 3: Write the implementation**

Create `scripts/parse-configs.sh`:

```bash
#!/usr/bin/env bash
# Scan a directory of <arch>-<series>[-<variant>].config files and emit one
# compact JSON matrix entry per config (one per line) on stdout.
set -euo pipefail

dir="${1:-_hypercfg}"
sources="$dir/sources.json"

shopt -s nullglob
for f in "$dir"/*.config; do
  base="$(basename "$f" .config)"

  arch="${base%%-*}"
  rest="${base#*-}"
  series="${rest%%-*}"
  if [[ "$rest" == *-* ]]; then
    variant="${rest#*-}"
  else
    variant=""
  fi

  case "$arch" in
    x86_64)  kbuild_arch="x86_64"; runner="ubuntu-24.04";     target="vmlinux"; artifact="vmlinux" ;;
    aarch64) kbuild_arch="arm64";  runner="ubuntu-24.04-arm"; target="Image";   artifact="Image"   ;;
    *) echo "parse-configs: unknown arch '$arch' in '$f'" >&2; exit 1 ;;
  esac

  major="${series%%.*}"
  vdir="v${major}.x"

  fc_origin=""
  if [[ -f "$sources" ]]; then
    fc_origin="$(jq -r --arg n "$base" '.[$n] // ""' "$sources")"
  fi

  jq -cn \
    --arg name "$base" \
    --arg config "$f" \
    --arg arch "$arch" \
    --arg kbuild_arch "$kbuild_arch" \
    --arg series "$series" \
    --arg variant "$variant" \
    --arg vdir "$vdir" \
    --arg runner "$runner" \
    --arg target "$target" \
    --arg artifact "$artifact" \
    --arg fc_origin "$fc_origin" \
    '{name:$name, config:$config, arch:$arch, kbuild_arch:$kbuild_arch,
      series:$series, variant:$variant, vdir:$vdir, runner:$runner,
      target:$target, artifact:$artifact, fc_origin:$fc_origin}'
done
```

Then: `chmod +x scripts/parse-configs.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `npx --yes bats tests/parse-configs.bats`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Sanity-check against the real configs**

Run: `bash scripts/parse-configs.sh _hypercfg | jq -s 'length'`
Expected: prints `5`.

- [ ] **Step 6: Commit**

```bash
git add scripts/parse-configs.sh tests/parse-configs.bats
git commit -m "feat: add parse-configs.sh config-to-matrix generator"
```

---

### Task 4: `resolve-kernel.sh` — latest point release + source sha256

**Files:**
- Create: `scripts/resolve-kernel.sh`
- Create: `tests/fixtures/sha256sums-v6.x.asc`
- Test: `tests/resolve-kernel.bats`

**Interfaces:**
- Consumes: a series string like `6.1`; optionally a local checksums file path as `$2` (for tests). Without `$2`, fetches `https://cdn.kernel.org/pub/linux/kernel/<vdir>/sha256sums.asc`.
- Produces: `resolve-kernel.sh <series> [checksums_file]` prints ONE compact JSON object: `{ "series", "version" (full e.g. 6.1.123), "sha256" (source tarball sha256), "tarball" (filename), "url" (full download URL), "vdir" }`. Consumed by `build-kernel.sh` (Task 6).

- [ ] **Step 1: Create the checksums fixture**

Create `tests/fixtures/sha256sums-v6.x.asc`:

```
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

aaaa000000000000000000000000000000000000000000000000000000000001  linux-6.1.9.tar.gz
aaaa000000000000000000000000000000000000000000000000000000000002  linux-6.1.9.tar.xz
bbbb000000000000000000000000000000000000000000000000000000000003  linux-6.1.10.tar.xz
cccc000000000000000000000000000000000000000000000000000000000004  linux-6.1.2.tar.xz
dddd000000000000000000000000000000000000000000000000000000000005  linux-6.6.1.tar.xz
eeee000000000000000000000000000000000000000000000000000000000006  linux-6.1.10.tar.sign
-----BEGIN PGP SIGNATURE-----

iQIzBAEBCgAdFiEE...trimmed...
-----END PGP SIGNATURE-----
```

- [ ] **Step 2: Write the failing test**

Create `tests/resolve-kernel.bats`:

```bash
#!/usr/bin/env bats

setup() {
  load helpers
  SCRIPT="$(scripts_dir)/resolve-kernel.sh"
  FIX="$(fixtures_dir)/sha256sums-v6.x.asc"
}

@test "picks highest 6.1.x point release by numeric patch" {
  run bash "$SCRIPT" 6.1 "$FIX"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .version)" = "6.1.10" ]
}

@test "returns the .tar.xz sha256, not .tar.gz or .tar.sign" {
  run bash "$SCRIPT" 6.1 "$FIX"
  [ "$(echo "$output" | jq -r .sha256)" = "bbbb000000000000000000000000000000000000000000000000000000000003" ]
}

@test "does not match a different series (6.6.x)" {
  run bash "$SCRIPT" 6.1 "$FIX"
  [ "$(echo "$output" | jq -r .version)" != "6.6.1" ]
}

@test "builds correct vdir, tarball and url" {
  run bash "$SCRIPT" 6.1 "$FIX"
  [ "$(echo "$output" | jq -r .vdir)" = "v6.x" ]
  [ "$(echo "$output" | jq -r .tarball)" = "linux-6.1.10.tar.xz" ]
  [ "$(echo "$output" | jq -r .url)" = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.10.tar.xz" ]
}

@test "fails when series has no matching release" {
  run bash "$SCRIPT" 4.4 "$FIX"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `npx --yes bats tests/resolve-kernel.bats`
Expected: FAIL — script does not exist.

- [ ] **Step 4: Write the implementation**

Create `scripts/resolve-kernel.sh`:

```bash
#!/usr/bin/env bash
# Resolve the latest stable point release of a kernel series from kernel.org's
# signed sha256sums.asc, emitting a JSON object with the source tarball sha256.
set -euo pipefail

series="${1:?usage: resolve-kernel.sh <series> [checksums_file]}"
checksums_file="${2:-}"

major="${series%%.*}"
vdir="v${major}.x"

if [[ -n "$checksums_file" ]]; then
  data="$(cat "$checksums_file")"
else
  data="$(curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/${vdir}/sha256sums.asc")"
fi

# Escape the dot in the series for the regex (5.10 -> 5\.10).
escaped="${series//./\\.}"

# Match exactly "linux-<series>.<patch>.tar.xz" lines; emit "version sha".
best="$(
  grep -E "  linux-${escaped}\.[0-9]+\.tar\.xz\$" <<<"$data" \
    | while read -r sha file; do
        ver="${file#linux-}"; ver="${ver%.tar.xz}"
        printf '%s %s\n' "$ver" "$sha"
      done \
    | sort -V \
    | tail -1
)"

if [[ -z "$best" ]]; then
  echo "resolve-kernel: no .tar.xz release found for series '$series' in $vdir" >&2
  exit 1
fi

version="${best%% *}"
sha="${best##* }"
tarball="linux-${version}.tar.xz"
url="https://cdn.kernel.org/pub/linux/kernel/${vdir}/${tarball}"

jq -cn \
  --arg series "$series" \
  --arg version "$version" \
  --arg sha256 "$sha" \
  --arg tarball "$tarball" \
  --arg url "$url" \
  --arg vdir "$vdir" \
  '{series:$series, version:$version, sha256:$sha256, tarball:$tarball, url:$url, vdir:$vdir}'
```

Then: `chmod +x scripts/resolve-kernel.sh`

- [ ] **Step 5: Run test to verify it passes**

Run: `npx --yes bats tests/resolve-kernel.bats`
Expected: PASS — 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/resolve-kernel.sh tests/resolve-kernel.bats tests/fixtures/sha256sums-v6.x.asc
git commit -m "feat: add resolve-kernel.sh kernel.org version resolver"
```

---

### Task 5: `make-manifest.sh` — manifest.json + artifact sha256

**Files:**
- Create: `scripts/make-manifest.sh`
- Test: `tests/make-manifest.bats`

**Interfaces:**
- Consumes: positional args `<outdir> <artifact_filename>`; reads these environment variables: `NAME`, `ARCH`, `KBUILD_ARCH`, `SERIES`, `VARIANT`, `KERNEL_VERSION`, `SOURCE_TARBALL`, `SOURCE_SHA256`, `CONFIG_FILE`, `FC_ORIGIN`, `GIT_REF`, `BUILT_AT`, `RUNNER`, `RELEASE_TAG`. The artifact must already exist at `<outdir>/<artifact_filename>`.
- Produces: writes `<outdir>/manifest.json` (`schema_version: 1`, with `sha256`, `size`, `config_sha256`, and provenance fields) and `<outdir>/<artifact_filename>.sha256` (format `<hash>  <filename>`). Consumed by the `build` job (Task 8) for upload and the `index` job (Task 9) for aggregation.

- [ ] **Step 1: Write the failing test**

Create `tests/make-manifest.bats`:

```bash
#!/usr/bin/env bats

setup() {
  load helpers
  SCRIPT="$(scripts_dir)/make-manifest.sh"
  TMP="$(mktemp -d)"
  printf 'FAKEKERNELBYTES' > "$TMP/vmlinux"
  printf 'CONFIG_X=y\n'    > "$TMP/config.cfg"
}

teardown() { rm -rf "$TMP"; }

run_make() {
  NAME="x86_64-5.10-no-acpi" ARCH="x86_64" KBUILD_ARCH="x86_64" \
  SERIES="5.10" VARIANT="no-acpi" KERNEL_VERSION="5.10.240" \
  SOURCE_TARBALL="linux-5.10.240.tar.xz" SOURCE_SHA256="deadbeef" \
  CONFIG_FILE="$TMP/config.cfg" FC_ORIGIN="https://example/c.config" \
  GIT_REF="abc123" BUILT_AT="2026-06-23T00:00:00Z" RUNNER="ubuntu-24.04" \
  RELEASE_TAG="vmlinux-x86_64-5.10-no-acpi-5.10.240" \
  bash "$SCRIPT" "$TMP" vmlinux
}

@test "writes a sha256 sidecar in sha256sum format" {
  run run_make
  [ "$status" -eq 0 ]
  [ -f "$TMP/vmlinux.sha256" ]
  expected="$(sha256sum "$TMP/vmlinux" | awk '{print $1}')"
  [ "$(awk '{print $1}' "$TMP/vmlinux.sha256")" = "$expected" ]
  [ "$(awk '{print $2}' "$TMP/vmlinux.sha256")" = "vmlinux" ]
}

@test "manifest has schema_version 1 and matching sha256/size" {
  run run_make
  m="$TMP/manifest.json"
  [ -f "$m" ]
  [ "$(jq -r .schema_version "$m")" = "1" ]
  expected="$(sha256sum "$TMP/vmlinux" | awk '{print $1}')"
  [ "$(jq -r .sha256 "$m")" = "$expected" ]
  [ "$(jq -r .size "$m")" = "$(stat -c%s "$TMP/vmlinux")" ]
}

@test "manifest carries provenance and identity fields" {
  run run_make
  m="$TMP/manifest.json"
  [ "$(jq -r .name "$m")" = "x86_64-5.10-no-acpi" ]
  [ "$(jq -r .variant "$m")" = "no-acpi" ]
  [ "$(jq -r .kernel_version "$m")" = "5.10.240" ]
  [ "$(jq -r .source_sha256 "$m")" = "deadbeef" ]
  [ "$(jq -r .artifact "$m")" = "vmlinux" ]
  [ "$(jq -r .release_tag "$m")" = "vmlinux-x86_64-5.10-no-acpi-5.10.240" ]
}

@test "empty VARIANT serializes as json null" {
  run_make_no_variant() {
    NAME="x86_64-6.1" ARCH="x86_64" KBUILD_ARCH="x86_64" SERIES="6.1" \
    VARIANT="" KERNEL_VERSION="6.1.100" SOURCE_TARBALL="t" SOURCE_SHA256="s" \
    CONFIG_FILE="$TMP/config.cfg" FC_ORIGIN="u" GIT_REF="g" \
    BUILT_AT="2026-06-23T00:00:00Z" RUNNER="ubuntu-24.04" \
    RELEASE_TAG="vmlinux-x86_64-6.1-6.1.100" bash "$SCRIPT" "$TMP" vmlinux
  }
  run run_make_no_variant
  [ "$status" -eq 0 ]
  [ "$(jq -r '.variant' "$TMP/manifest.json")" = "null" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx --yes bats tests/make-manifest.bats`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/make-manifest.sh`:

```bash
#!/usr/bin/env bash
# Emit manifest.json + <artifact>.sha256 for a built kernel artifact.
set -euo pipefail

outdir="${1:?usage: make-manifest.sh <outdir> <artifact_filename>}"
artifact="${2:?usage: make-manifest.sh <outdir> <artifact_filename>}"
art_path="$outdir/$artifact"

: "${NAME:?}" "${ARCH:?}" "${KBUILD_ARCH:?}" "${SERIES:?}" "${KERNEL_VERSION:?}"
: "${SOURCE_TARBALL:?}" "${SOURCE_SHA256:?}" "${CONFIG_FILE:?}" "${FC_ORIGIN:?}"
: "${GIT_REF:?}" "${BUILT_AT:?}" "${RUNNER:?}" "${RELEASE_TAG:?}"
variant="${VARIANT:-}"

[[ -f "$art_path" ]] || { echo "make-manifest: missing artifact $art_path" >&2; exit 1; }

sha="$(sha256sum "$art_path" | awk '{print $1}')"
size="$(stat -c%s "$art_path")"
cfg_sha="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"

printf '%s  %s\n' "$sha" "$artifact" > "$art_path.sha256"

# Render variant as a JSON string, or null when empty.
if [[ -n "$variant" ]]; then
  variant_json="$(jq -n --arg v "$variant" '$v')"
else
  variant_json="null"
fi

jq -n \
  --arg name "$NAME" \
  --arg arch "$ARCH" \
  --arg kbuild_arch "$KBUILD_ARCH" \
  --arg series "$SERIES" \
  --argjson variant "$variant_json" \
  --arg kernel_version "$KERNEL_VERSION" \
  --arg artifact "$artifact" \
  --arg sha256 "$sha" \
  --argjson size "$size" \
  --arg config_sha256 "$cfg_sha" \
  --arg source_tarball "$SOURCE_TARBALL" \
  --arg source_sha256 "$SOURCE_SHA256" \
  --arg fc_origin "$FC_ORIGIN" \
  --arg git_ref "$GIT_REF" \
  --arg built_at "$BUILT_AT" \
  --arg runner "$RUNNER" \
  --arg release_tag "$RELEASE_TAG" \
  '{ schema_version: 1, name: $name, arch: $arch, kbuild_arch: $kbuild_arch,
     series: $series, variant: $variant, kernel_version: $kernel_version,
     artifact: $artifact, sha256: $sha256, size: $size,
     config_sha256: $config_sha256, source_tarball: $source_tarball,
     source_sha256: $source_sha256, firecracker_config_origin: $fc_origin,
     git_ref: $git_ref, built_at: $built_at, runner: $runner,
     release_tag: $release_tag }' \
  > "$outdir/manifest.json"
```

Then: `chmod +x scripts/make-manifest.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `npx --yes bats tests/make-manifest.bats`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Validate manifest is well-formed JSON**

Run:
```bash
TMP=$(mktemp -d); printf x > "$TMP/vmlinux"; printf x > "$TMP/c"
NAME=n ARCH=x86_64 KBUILD_ARCH=x86_64 SERIES=6.1 VARIANT= KERNEL_VERSION=6.1.1 \
SOURCE_TARBALL=t SOURCE_SHA256=s CONFIG_FILE="$TMP/c" FC_ORIGIN=u GIT_REF=g \
BUILT_AT=now RUNNER=r RELEASE_TAG=tag bash scripts/make-manifest.sh "$TMP" vmlinux
jq -e . "$TMP/manifest.json" >/dev/null && echo VALID; rm -rf "$TMP"
```
Expected: prints `VALID`.

- [ ] **Step 6: Commit**

```bash
git add scripts/make-manifest.sh tests/make-manifest.bats
git commit -m "feat: add make-manifest.sh manifest + sha256 writer"
```

---

### Task 6: `build-kernel.sh` — download, verify, configure, build, stage

**Files:**
- Create: `scripts/build-kernel.sh`
- Test: `tests/build-kernel.bats`

**Interfaces:**
- Consumes: env vars from a matrix entry — `NAME`, `CONFIG` (absolute path), `KBUILD_ARCH`, `SERIES`, `VARIANT`, `VDIR`, `TARGET`, `ARTIFACT`, `FC_ORIGIN`, plus `WORKDIR` (scratch dir), `OUTDIR` (where the staged artifact + manifest go), `GIT_REF`, `RUNNER_NAME`. Calls `resolve-kernel.sh` (Task 4) and `make-manifest.sh` (Task 5). Honors `HYPERCFG_RESOLVE_FILE` (use a local checksums file instead of fetching — for tests) and `HYPERCFG_DRY_RUN=1` (do everything except the actual `make`, staging a placeholder artifact — for smoke tests).
- Produces: `<OUTDIR>/<ARTIFACT>`, `<OUTDIR>/<ARTIFACT>.sha256`, `<OUTDIR>/manifest.json`, and prints `release_tag=<tag>` and `kernel_version=<ver>` as `key=value` lines on stdout (captured by the workflow). Release tag: `vmlinux-<NAME>-<full_version>`.

- [ ] **Step 1: Write the failing test (dry-run path only — no real kernel build in unit tests)**

Create `tests/build-kernel.bats`:

```bash
#!/usr/bin/env bats

setup() {
  load helpers
  SCRIPT="$(scripts_dir)/build-kernel.sh"
  FIX="$(fixtures_dir)/sha256sums-v6.x.asc"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/work" "$TMP/out"
  printf 'CONFIG_X=y\n' > "$TMP/x86_64-6.1.config"
}

teardown() { rm -rf "$TMP"; }

run_dry() {
  HYPERCFG_DRY_RUN=1 HYPERCFG_RESOLVE_FILE="$FIX" \
  NAME="x86_64-6.1" CONFIG="$TMP/x86_64-6.1.config" KBUILD_ARCH="x86_64" \
  SERIES="6.1" VARIANT="" VDIR="v6.x" TARGET="vmlinux" ARTIFACT="vmlinux" \
  FC_ORIGIN="https://example/c" WORKDIR="$TMP/work" OUTDIR="$TMP/out" \
  GIT_REF="abc123" RUNNER_NAME="ubuntu-24.04" \
  bash "$SCRIPT"
}

@test "dry run resolves version and prints release_tag" {
  run run_dry
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "kernel_version=6.1.10"
  echo "$output" | grep -q "release_tag=vmlinux-x86_64-6.1-6.1.10"
}

@test "dry run stages artifact, sha256 and manifest" {
  run run_dry
  [ -f "$TMP/out/vmlinux" ]
  [ -f "$TMP/out/vmlinux.sha256" ]
  [ -f "$TMP/out/manifest.json" ]
  [ "$(jq -r .kernel_version "$TMP/out/manifest.json")" = "6.1.10" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx --yes bats tests/build-kernel.bats`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/build-kernel.sh`:

```bash
#!/usr/bin/env bash
# Download the matching kernel source, verify its sha256, apply the config,
# build the Firecracker boot image, and stage it with a manifest.
set -euo pipefail

: "${NAME:?}" "${CONFIG:?}" "${KBUILD_ARCH:?}" "${SERIES:?}" "${VDIR:?}"
: "${TARGET:?}" "${ARTIFACT:?}" "${FC_ORIGIN:?}" "${WORKDIR:?}" "${OUTDIR:?}"
: "${GIT_REF:?}" "${RUNNER_NAME:?}"
VARIANT="${VARIANT:-}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_abs="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
mkdir -p "$WORKDIR" "$OUTDIR"

# 1. Resolve the latest point release (+ source sha256) for this series.
if [[ -n "${HYPERCFG_RESOLVE_FILE:-}" ]]; then
  resolved="$("$here/resolve-kernel.sh" "$SERIES" "$HYPERCFG_RESOLVE_FILE")"
else
  resolved="$("$here/resolve-kernel.sh" "$SERIES")"
fi
version="$(jq -r .version <<<"$resolved")"
src_sha="$(jq -r .sha256 <<<"$resolved")"
tarball="$(jq -r .tarball <<<"$resolved")"
url="$(jq -r .url <<<"$resolved")"
release_tag="vmlinux-${NAME}-${version}"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_outputs() {
  echo "kernel_version=$version"
  echo "release_tag=$release_tag"
}

stage_manifest() {
  NAME="$NAME" ARCH="${NAME%%-*}" KBUILD_ARCH="$KBUILD_ARCH" SERIES="$SERIES" \
  VARIANT="$VARIANT" KERNEL_VERSION="$version" SOURCE_TARBALL="$tarball" \
  SOURCE_SHA256="$src_sha" CONFIG_FILE="$config_abs" FC_ORIGIN="$FC_ORIGIN" \
  GIT_REF="$GIT_REF" BUILT_AT="$built_at" RUNNER="$RUNNER_NAME" \
  RELEASE_TAG="$release_tag" \
  "$here/make-manifest.sh" "$OUTDIR" "$ARTIFACT"
}

# Dry-run: skip the heavy download+build, stage a placeholder so the rest of
# the pipeline (manifest, upload, index) is exercisable in smoke tests.
if [[ "${HYPERCFG_DRY_RUN:-}" == "1" ]]; then
  printf 'DRYRUN-%s' "$release_tag" > "$OUTDIR/$ARTIFACT"
  stage_manifest
  emit_outputs
  exit 0
fi

# 2. Download + verify the source tarball.
cd "$WORKDIR"
curl -fSL "$url" -o "$tarball"
echo "${src_sha}  ${tarball}" | sha256sum -c -

# 3. Extract.
tar -xf "$tarball"
srcdir="$WORKDIR/linux-${version}"
cd "$srcdir"

# 4. Apply config and normalize for this exact tree.
cp "$config_abs" .config
make ARCH="$KBUILD_ARCH" olddefconfig

# 5. Build the Firecracker boot image (native; no CROSS_COMPILE).
make ARCH="$KBUILD_ARCH" -j"$(nproc)" "$TARGET"

# 6. Stage the artifact from its arch-specific build path.
case "$KBUILD_ARCH" in
  x86_64) src_artifact="$srcdir/vmlinux" ;;
  arm64)  src_artifact="$srcdir/arch/arm64/boot/Image" ;;
  *) echo "build-kernel: unknown KBUILD_ARCH '$KBUILD_ARCH'" >&2; exit 1 ;;
esac
cp "$src_artifact" "$OUTDIR/$ARTIFACT"

# 7. Manifest + sha256 sidecar.
stage_manifest
emit_outputs
```

Then: `chmod +x scripts/build-kernel.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `npx --yes bats tests/build-kernel.bats`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Run the full script test suite**

Run: `npx --yes bats tests/`
Expected: PASS — all tests across the four scripts pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/build-kernel.sh tests/build-kernel.bats
git commit -m "feat: add build-kernel.sh download/verify/build orchestrator"
```

---

### Task 7: Workflow `prepare` job — configs → matrix

**Files:**
- Create: `.github/workflows/build-vmlinux.yml`

**Interfaces:**
- Consumes: `parse-configs.sh` (Task 3).
- Produces: a `workflow_dispatch` workflow whose `prepare` job outputs `matrix` (a JSON object `{"include":[...]}`) for downstream jobs. Supports an optional `only` input to filter to a subset of config names (comma-separated; empty = all).

- [ ] **Step 1: Install actionlint locally for validation**

Run:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) || true
ls ./actionlint && echo "actionlint ready"
```
Expected: prints `actionlint ready`. (If download fails: `go install github.com/rhysd/actionlint/cmd/actionlint@latest`, or skip local linting — GitHub validates on push.)

- [ ] **Step 2: Write the workflow with the prepare job only**

Create `.github/workflows/build-vmlinux.yml`:

```yaml
name: Build & publish vmlinux

on:
  workflow_dispatch:
    inputs:
      only:
        description: "Comma-separated config names to build (empty = all)"
        required: false
        default: ""

permissions:
  contents: write

concurrency:
  group: build-vmlinux
  cancel-in-progress: false

jobs:
  prepare:
    runs-on: ubuntu-24.04
    outputs:
      matrix: ${{ steps.gen.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      - name: Generate build matrix from _hypercfg
        id: gen
        run: |
          set -euo pipefail
          only="${{ inputs.only }}"
          entries="$(bash scripts/parse-configs.sh _hypercfg)"
          if [[ -n "$only" ]]; then
            filter="$(echo "$only" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -cs .)"
            entries="$(echo "$entries" | jq -c --argjson keep "$filter" 'select(.name as $n | $keep | index($n))')"
          fi
          matrix="$(echo "$entries" | jq -cs '{include: .}')"
          echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
          echo "$matrix" | jq .
```

- [ ] **Step 3: Lint the workflow**

Run: `./actionlint .github/workflows/build-vmlinux.yml || actionlint .github/workflows/build-vmlinux.yml`
Expected: no output (exit 0). Fix any reported issues.

- [ ] **Step 4: Locally simulate the matrix generation**

Run:
```bash
bash scripts/parse-configs.sh _hypercfg | jq -cs '{include: .}' | jq '.include | length'
```
Expected: prints `5`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/build-vmlinux.yml
git commit -m "feat: add build-vmlinux workflow prepare job"
```

---

### Task 8: Workflow `build` job — build, manifest, per-config release

**Files:**
- Modify: `.github/workflows/build-vmlinux.yml` (add `build` job after `prepare`)

**Interfaces:**
- Consumes: `prepare.outputs.matrix` (Task 7), `build-kernel.sh` (Task 6).
- Produces: per matrix entry — a GitHub Release tagged `vmlinux-<name>-<version>` containing `<artifact>`, `<artifact>.sha256`, `manifest.json`; and a workflow artifact named `manifest-<name>` containing that `manifest.json` (consumed by the `index` job in Task 9).

- [ ] **Step 1: Add the build job**

Append to `.github/workflows/build-vmlinux.yml` (under `jobs:`, after `prepare`):

```yaml
  build:
    needs: prepare
    runs-on: ${{ matrix.runner }}
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.prepare.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            build-essential bc bison flex libssl-dev libelf-dev \
            xz-utils jq curl

      - name: Build kernel and stage artifact
        id: build
        env:
          NAME: ${{ matrix.name }}
          CONFIG: ${{ github.workspace }}/${{ matrix.config }}
          KBUILD_ARCH: ${{ matrix.kbuild_arch }}
          SERIES: ${{ matrix.series }}
          VARIANT: ${{ matrix.variant }}
          VDIR: ${{ matrix.vdir }}
          TARGET: ${{ matrix.target }}
          ARTIFACT: ${{ matrix.artifact }}
          FC_ORIGIN: ${{ matrix.fc_origin }}
          WORKDIR: ${{ runner.temp }}/work
          OUTDIR: ${{ github.workspace }}/out
          GIT_REF: ${{ github.sha }}
          RUNNER_NAME: ${{ matrix.runner }}
        run: |
          set -euo pipefail
          bash scripts/build-kernel.sh | tee "$RUNNER_TEMP/build-out.env"
          while IFS='=' read -r k v; do
            [[ -n "$k" ]] && echo "$k=$v" >> "$GITHUB_OUTPUT"
          done < "$RUNNER_TEMP/build-out.env"

      - name: Create or update release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ steps.build.outputs.release_tag }}
          NAME: ${{ matrix.name }}
          VERSION: ${{ steps.build.outputs.kernel_version }}
          ARTIFACT: ${{ matrix.artifact }}
        run: |
          set -euo pipefail
          title="vmlinux ${NAME} (linux ${VERSION})"
          if ! gh release view "$TAG" >/dev/null 2>&1; then
            gh release create "$TAG" --title "$title" \
              --notes "Firecracker-bootable \`${ARTIFACT}\` for config \`${NAME}\`, built from Linux ${VERSION}. Verify with the bundled \`${ARTIFACT}.sha256\` / \`manifest.json\`."
          fi
          gh release upload "$TAG" \
            "out/${ARTIFACT}" "out/${ARTIFACT}.sha256" "out/manifest.json" \
            --clobber

      - name: Upload manifest as workflow artifact (for index job)
        uses: actions/upload-artifact@v4
        with:
          name: manifest-${{ matrix.name }}
          path: out/manifest.json
          if-no-files-found: error
```

- [ ] **Step 2: Lint the workflow**

Run: `./actionlint .github/workflows/build-vmlinux.yml || actionlint .github/workflows/build-vmlinux.yml`
Expected: exit 0, no output. Fix any issues.

- [ ] **Step 3: Validate the YAML parses and both jobs exist**

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/build-vmlinux.yml')); print(sorted(d['jobs'].keys()))"
```
Expected: prints `['build', 'prepare']`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-vmlinux.yml
git commit -m "feat: add build job that builds and publishes per-config releases"
```

---

### Task 9: Workflow `index` job — aggregate `index.json`

**Files:**
- Modify: `.github/workflows/build-vmlinux.yml` (add `index` job after `build`)

**Interfaces:**
- Consumes: the `manifest-<name>` workflow artifacts from all `build` jobs (Task 8).
- Produces: a single `index.json` published to the `hypercfg-index` release (clobbered each run). `index.json` shape: `{ schema_version: 1, repo, generated_at, configs: { "<name>": <manifest + artifact_url/sha256_url/manifest_url> } }`. This is the stable discovery endpoint for `hyper`.

- [ ] **Step 1: Add the index job**

Append to `.github/workflows/build-vmlinux.yml` (under `jobs:`, after `build`):

```yaml
  index:
    needs: build
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq

      - name: Download all manifests
        uses: actions/download-artifact@v4
        with:
          pattern: manifest-*
          path: manifests

      - name: Build index.json
        env:
          REPO: ${{ github.repository }}
          SERVER: ${{ github.server_url }}
        run: |
          set -euo pipefail
          generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          configs="$(
            find manifests -name manifest.json -print0 \
              | xargs -0 cat \
              | jq -s \
                  --arg base "$SERVER/$REPO/releases/download" \
                  'map({ (.name): (. + {
                       artifact_url: ($base + "/" + .release_tag + "/" + .artifact),
                       sha256_url:   ($base + "/" + .release_tag + "/" + .artifact + ".sha256"),
                       manifest_url: ($base + "/" + .release_tag + "/manifest.json")
                     }) }) | add'
          )"
          jq -n \
            --argjson configs "$configs" \
            --arg repo "$REPO" \
            --arg generated_at "$generated_at" \
            '{ schema_version: 1, repo: $repo, generated_at: $generated_at, configs: $configs }' \
            > index.json
          jq . index.json

      - name: Publish index release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          if ! gh release view hypercfg-index >/dev/null 2>&1; then
            gh release create hypercfg-index --title "hypercfg artifact index" \
              --notes "Machine-readable index of the latest published vmlinux artifacts. Consumed by harmont-dev/hyper. See index.json."
          fi
          gh release upload hypercfg-index index.json --clobber
```

- [ ] **Step 2: Lint the workflow**

Run: `./actionlint .github/workflows/build-vmlinux.yml || actionlint .github/workflows/build-vmlinux.yml`
Expected: exit 0, no output.

- [ ] **Step 3: Validate the index jq pipeline against a fake manifest**

Run:
```bash
TMP=$(mktemp -d); mkdir -p "$TMP/manifests/manifest-x86_64-6.1"
cat > "$TMP/manifests/manifest-x86_64-6.1/manifest.json" <<'JSON'
{"schema_version":1,"name":"x86_64-6.1","release_tag":"vmlinux-x86_64-6.1-6.1.100","artifact":"vmlinux","sha256":"abc"}
JSON
( cd "$TMP"
  find manifests -name manifest.json -print0 | xargs -0 cat | jq -s \
    --arg base "https://github.com/harmont-dev/hypercfg/releases/download" \
    'map({ (.name): (. + {artifact_url: ($base+"/"+.release_tag+"/"+.artifact)}) }) | add' \
    | jq -e '.["x86_64-6.1"].artifact_url == "https://github.com/harmont-dev/hypercfg/releases/download/vmlinux-x86_64-6.1-6.1.100/vmlinux"' )
rm -rf "$TMP"
```
Expected: prints `true`.

- [ ] **Step 4: Confirm all three jobs are present**

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/build-vmlinux.yml')); print(sorted(d['jobs'].keys()))"
```
Expected: prints `['build', 'index', 'prepare']`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/build-vmlinux.yml
git commit -m "feat: add index job publishing aggregate index.json"
```

---

### Task 10: Repo README + consumer contract

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: documentation of the publish flow and the exact `manifest.json` / `index.json` schemas so `harmont-dev/hyper` can implement discovery + verification against a stable contract.

- [ ] **Step 1: Write the README**

Create `README.md`:

```markdown
# hypercfg

Firecracker-bootable Linux kernel builds, published as GitHub Releases.

On manual dispatch, the **Build & publish vmlinux** workflow builds a
Firecracker boot image for every config in `_hypercfg/` and publishes one
release per config, plus an aggregate discovery index. Consumed by
[`harmont-dev/hyper`](https://github.com/harmont-dev/hyper).

## Adding a target

Drop a config named `<arch>-<series>[-<variant>].config` (e.g.
`x86_64-6.6.config`) into `_hypercfg/`, add its upstream URL to
`_hypercfg/sources.json`, and run the workflow. `arch` is `x86_64` or
`aarch64`; `series` is `MAJOR.MINOR`.

## How a build works

For each config the workflow:
1. Resolves the latest stable point release of the series from kernel.org's
   PGP-signed `sha256sums.asc` (e.g. `5.10` -> `5.10.240`).
2. Downloads `linux-<version>.tar.xz` and verifies its sha256 against that
   signed checksum file.
3. Applies the config (`make olddefconfig`) and builds natively
   (`x86_64` on `ubuntu-24.04`, `aarch64` on `ubuntu-24.04-arm`).
4. Produces the boot image: `vmlinux` (x86_64) or `Image` (aarch64).
5. Publishes a release with the artifact, `<artifact>.sha256`, and
   `manifest.json`.

## Releases & discovery (for `harmont-dev/hyper`)

- **Per-config release** — tag `vmlinux-<config-name>-<full_version>`
  (e.g. `vmlinux-x86_64-5.10-no-acpi-5.10.240`). Assets: the artifact,
  `<artifact>.sha256` (`sha256sum -c` format), and `manifest.json`.
- **Discovery index** — release tag `hypercfg-index`, asset `index.json`,
  refreshed every run. Fetch this to find the latest artifact for each config
  without listing releases.

### `index.json` (schema_version 1)

```json
{
  "schema_version": 1,
  "repo": "harmont-dev/hypercfg",
  "generated_at": "2026-06-23T00:00:00Z",
  "configs": {
    "x86_64-5.10-no-acpi": {
      "schema_version": 1,
      "name": "x86_64-5.10-no-acpi",
      "arch": "x86_64",
      "kbuild_arch": "x86_64",
      "series": "5.10",
      "variant": "no-acpi",
      "kernel_version": "5.10.240",
      "artifact": "vmlinux",
      "sha256": "<hex>",
      "size": 12345678,
      "config_sha256": "<hex>",
      "source_tarball": "linux-5.10.240.tar.xz",
      "source_sha256": "<hex>",
      "firecracker_config_origin": "https://raw.githubusercontent.com/.../config",
      "git_ref": "<hypercfg commit sha>",
      "built_at": "2026-06-23T00:00:00Z",
      "runner": "ubuntu-24.04",
      "release_tag": "vmlinux-x86_64-5.10-no-acpi-5.10.240",
      "artifact_url": ".../releases/download/<tag>/vmlinux",
      "sha256_url": ".../releases/download/<tag>/vmlinux.sha256",
      "manifest_url": ".../releases/download/<tag>/manifest.json"
    }
  }
}
```

### Recommended consumer flow

1. `GET` the `hypercfg-index` release's `index.json`.
2. Look up `configs["<arch>-<series>[-<variant>]"]`.
3. Download `artifact_url`; verify its sha256 equals `sha256`.
4. Use it as the Firecracker `kernel_image_path` (`vmlinux` for x86_64,
   `Image` for aarch64).
```

- [ ] **Step 2: Validate the embedded JSON example parses**

Run:
```bash
awk '/^```json$/{f=1;next} /^```$/{f=0} f' README.md | jq -e . >/dev/null && echo VALID
```
Expected: prints `VALID`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add repo README and hyper consumer contract"
```

---

### Task 11: Full local verification + push + smoke run

**Files:**
- None (verification only).

**Interfaces:**
- Consumes: everything above.
- Produces: the repo pushed to `harmont-dev/hypercfg` with the workflow on `main`, validated by a manual dispatch.

- [ ] **Step 1: Run the entire bats suite**

Run: `npx --yes bats tests/`
Expected: PASS — all tests across all four scripts pass.

- [ ] **Step 2: Lint the workflow one final time**

Run: `./actionlint .github/workflows/build-vmlinux.yml || actionlint .github/workflows/build-vmlinux.yml`
Expected: exit 0, no output.

- [ ] **Step 3: Confirm the working tree is clean and on main**

Run: `git status --short && git rev-parse --abbrev-ref HEAD`
Expected: empty status output (all committed) and `main`.

- [ ] **Step 4: Push to the default branch**

```bash
git push -u origin main
```
Expected: `main` on `origin` updated. The workflow now appears under Actions (it must be on the default branch to be dispatchable).

- [ ] **Step 5: Trigger a smoke run (manual)**

```bash
gh workflow run "Build & publish vmlinux" --ref main -f only=x86_64-6.1
gh run watch "$(gh run list --workflow 'Build & publish vmlinux' --limit 1 --json databaseId -q '.[0].databaseId')"
```
Then verify the published artifact:
```bash
tag="$(gh release list --limit 20 | awk '/^vmlinux-x86_64-6.1-/{print $1; exit}')"
gh release download "$tag" -p 'vmlinux*' -D /tmp/smoke
( cd /tmp/smoke && sha256sum -c vmlinux.sha256 ) && echo "SHA256 OK"
```
Expected: green run; a `vmlinux-x86_64-6.1-<version>` release with `vmlinux`, `vmlinux.sha256`, `manifest.json`; `sha256sum -c` prints `vmlinux: OK`; the `hypercfg-index` release gains an `index.json` listing the config. Then re-run with `only` empty (`gh workflow run "Build & publish vmlinux" --ref main`) to build all five.

---

## Self-Review

**1. Spec coverage:**
- "New GHA workflow, manually triggered" → `workflow_dispatch`, Task 7. ✓
- "Build and publish vmlinux configurations" → Tasks 6 (build), 8 (publish). ✓
- "Individual releases for each version in `_hypercfg/`" → one release per config file, Task 8. ✓
- "Pull in these five configs" → Task 2, with exact URL→filename mapping. ✓
- "Critical: sha256 and so on" → `<artifact>.sha256` (Task 5/8) + `manifest.json` sha256/size + signed source sha256 verification (Task 6). ✓
- "Consumed by `harmont-dev/hyper` to auto-provide usable vmlinux" → `index.json` discovery endpoint (Task 9) + consumer contract (Task 10). ✓
- "Don't need the linux repo since we grab tarballs" → standalone `harmont-dev/hypercfg` repo, Task 1; no kernel tree, source fetched from kernel.org. ✓
- Configs are 5.10/6.1 → matching source always fetched from kernel.org (Task 4/6); never built against any local tree. ✓

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to" — every script and test is written in full; every command has expected output.

**3. Type consistency:** matrix entry keys (`name`, `config`, `arch`, `kbuild_arch`, `series`, `variant`, `vdir`, `runner`, `target`, `artifact`, `fc_origin`) defined in Task 3 are consumed verbatim by the workflow `build` job env (Task 8) and `build-kernel.sh` (Task 6). `resolve-kernel.sh` output keys (`version`, `sha256`, `tarball`, `url`, `vdir`) match `build-kernel.sh`'s `jq -r` reads (Task 6). `make-manifest.sh` env contract (Task 5) matches what `build-kernel.sh`'s `stage_manifest` exports (Task 6). Release tag `vmlinux-<name>-<version>` is identical in Global Constraints, Task 6 (`release_tag`), Task 8 (release create), and Task 9 (URL construction). `schema_version: 1` consistent across manifest, index, and README. Paths are repo-root-relative (`scripts/`, `tests/`, `_hypercfg/`) consistently across helper, tests, and workflow.
