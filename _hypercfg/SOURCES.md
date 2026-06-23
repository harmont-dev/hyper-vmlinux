# _hypercfg config provenance

These kernel configs are vendored from the Firecracker project's
`resources/guest_configs/` directory, renamed to the
`<arch>-<series>[-<variant>].config` grammar used by the publish workflow.

| _hypercfg file | upstream file |
|---|---|
| `aarch64-5.10.config` | `microvm-kernel-ci-aarch64-5.10.config` |
| `aarch64-6.1.config` | `microvm-kernel-ci-aarch64-6.1.config` |
| `x86_64-5.10-no-acpi.config` | `microvm-kernel-ci-x86_64-5.10-no-acpi.config` |
| `x86_64-5.10.config` | `microvm-kernel-ci-x86_64-5.10.config` |
| `x86_64-6.1.config` | `microvm-kernel-ci-x86_64-6.1.config` |

Upstream: https://github.com/firecracker-microvm/firecracker (branch `main`).
Machine-readable source URLs live in `sources.json`.

To add a target: drop a `<arch>-<series>[-<variant>].config` file here, add its
entry to `sources.json`, and the publish workflow picks it up on the next run.
