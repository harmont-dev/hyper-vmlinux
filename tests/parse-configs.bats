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
  [ "$(echo "$line" | jq -r .fc_origin)" = "" ]
}

@test "parses multi-token variant" {
  run bash "$SCRIPT" "$TMP"
  line="$(echo "$output" | jq -c 'select(.name=="x86_64-5.10-no-acpi")')"
  [ "$(echo "$line" | jq -r .series)" = "5.10" ]
  [ "$(echo "$line" | jq -r .variant)" = "no-acpi" ]
}
