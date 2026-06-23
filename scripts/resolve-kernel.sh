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
