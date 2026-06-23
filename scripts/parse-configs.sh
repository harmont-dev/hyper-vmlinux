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
