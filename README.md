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
