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
# Single-release mode: the workflow sets RELEASE_TAG (e.g. "latest") so every
# config's manifest points at the one shared release. Falls back to a
# per-config tag when unset (e.g. local/dry-run use).
release_tag="${RELEASE_TAG:-vmlinux-${NAME}-${version}}"
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
tarball_path="$WORKDIR/$tarball"
curl -fSL "$url" -o "$tarball_path"
echo "${src_sha}  ${tarball_path}" | sha256sum -c -

# 3. Extract.
cd "$WORKDIR"
tar -xf "$tarball_path"
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
