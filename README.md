# hyper-vmlinux

Firecracker-bootable Linux kernel builds, published as GitHub Releases, used as
the default images in [Hyper](https://github.com/harmont-dev/hyper).

Hyper allows you to provide your own `vmlinux` images. It is, however,
convenient, not to have to worry about providing your `vmlinux` images, so by
default, Hyper will fetch images from the [Github Releases of this
repo](https://github.com/harmont-dev/hyper-vmlinux/releases). These are all
checksummed in Hyper's implementation to mitigate the risk of a supply chain
attack.
