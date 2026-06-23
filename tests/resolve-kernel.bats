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
