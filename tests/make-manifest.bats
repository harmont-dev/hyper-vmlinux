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
