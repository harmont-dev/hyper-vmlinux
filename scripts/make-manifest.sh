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
