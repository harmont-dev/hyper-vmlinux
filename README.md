# hyper-vmlinux

Firecracker-bootable Linux kernel builds, published as GitHub Releases.

On manual dispatch, the **Build & publish vmlinux** workflow builds a
Firecracker boot image for every config in `_hypercfg/` and publishes them all
into a single rolling `latest` release, alongside an aggregate `index.json`.
Consumed by [`harmont-dev/hyper`](https://github.com/harmont-dev/hyper).

## Adding a target

Drop a config named `<arch>-<series>[-<variant>].config` (e.g.
`x86_64-6.6.config`) into `_hypercfg/`, add its upstream URL to
`_hypercfg/sources.json`, and run the workflow. `arch` is `x86_64` or
`aarch64`; `series` is `MAJOR.MINOR`. Example `sources.json` entry:
`"x86_64-6.6": "https://raw.githubusercontent.com/firecracker-microvm/firecracker/main/resources/guest_configs/microvm-kernel-ci-x86_64-6.6.config"`

## How a build works

For each config the workflow:
1. Resolves the latest stable point release of the series from kernel.org's
   PGP-signed `sha256sums.asc` (e.g. `5.10` -> `5.10.240`).
2. Downloads `linux-<version>.tar.xz` and verifies its sha256 against that
   signed checksum file.
3. Applies the config (`make olddefconfig`) and builds natively
   (`x86_64` on `ubuntu-24.04`, `aarch64` on `ubuntu-24.04-arm`).
4. Produces the boot image (kbuild `vmlinux` for x86_64 / `Image` for aarch64),
   named uniquely per config: `<boot>-<config-name>` — e.g.
   `vmlinux-x86_64-6.1`, `Image-aarch64-6.1`.
5. Stages the artifact, its `<artifact>.sha256`, and `<artifact>.manifest.json`.

## Releases & discovery (for `harmont-dev/hyper`)

Everything lands in **one rolling release**, tag `latest`, clobbered on every
run. Its assets are, for each config:

- `<artifact>` — the boot image (e.g. `vmlinux-x86_64-6.1`, `Image-aarch64-6.1`).
- `<artifact>.sha256` — checksum in `sha256sum -c` format.
- `<artifact>.manifest.json` — per-artifact metadata (provenance + checksums).

plus a single `index.json` listing every config with download URLs and
checksums — fetch it at
`https://github.com/harmont-dev/hyper-vmlinux/releases/download/latest/index.json`
to discover all artifacts without listing assets.

### `index.json` (schema_version 1)

```json
{
  "schema_version": 1,
  "repo": "harmont-dev/hyper-vmlinux",
  "release_tag": "latest",
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
      "artifact": "vmlinux-x86_64-5.10-no-acpi",
      "sha256": "<hex>",
      "size": 12345678,
      "config_sha256": "<hex>",
      "source_tarball": "linux-5.10.240.tar.xz",
      "source_sha256": "<hex>",
      "firecracker_config_origin": "https://raw.githubusercontent.com/.../config",
      "git_ref": "<hyper-vmlinux commit sha>",
      "built_at": "2026-06-23T00:00:00Z",
      "runner": "ubuntu-24.04",
      "release_tag": "latest",
      "artifact_url": ".../releases/download/latest/vmlinux-x86_64-5.10-no-acpi",
      "sha256_url": ".../releases/download/latest/vmlinux-x86_64-5.10-no-acpi.sha256",
      "manifest_url": ".../releases/download/latest/vmlinux-x86_64-5.10-no-acpi.manifest.json"
    }
  }
}
```

**Note:** each entry under `configs` is that config's full `manifest.json` **plus** three index-only fields — `artifact_url`, `sha256_url`, and `manifest_url`. The standalone `<artifact>.manifest.json` asset contains every field shown here *except* those three URLs (the publish job adds them once it knows the download URLs). The `artifact` field is the unique asset filename — use it as the download name; the boot type is `vmlinux` (x86_64) or `Image` (aarch64), inferable from `kbuild_arch`.

### Recommended consumer flow

1. `GET` `https://github.com/harmont-dev/hyper-vmlinux/releases/download/latest/index.json`.
2. Look up `configs["<arch>-<series>[-<variant>]"]`.
3. Download `artifact_url`; verify its sha256 equals `sha256` (or equivalently, run `sha256sum -c <artifact>.sha256` against the downloaded artifact).
4. Use it as the Firecracker `kernel_image_path` (a `vmlinux`-* asset for x86_64,
   an `Image`-* asset for aarch64).
