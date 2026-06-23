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
