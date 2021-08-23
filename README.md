A fixture for Linux eBPF JIT testing
====================================

## Purpose
The primary purpose is to provide a test fixture for running the in-kernel
eBPF test suite test_bpf.ko on any architecture with eBPF JIT support.
The fixture consists of a minimal Linux system with Busybox as userspace,
which is run in QEMU in nographic mode.

## Requirements
Tested on Ubuntu 20.04 LTS on x86_64.

## Getting started
make prerequisities
make arm -j$(nproc)
...
/ # insmod lib/modules/$(uname -r)/kernel/lib/test_bpf.ko

## Directory structure
- config.mk
  Global software version configuration

- defaults/
  Global Linux and Busybox build configuration

- targets/
  Per-target build configuration

- scripts/
  Common scripts and static files

- bin/
  Built toolchains

## Toolchains
Each target may specify a toolchain to use. If none is given, the toolchain
defaults to <arch>-linux-musl, which is built by musl-cross-make. Glibc
toolchains are installed as necessary with apt-get.

## Kernel configuration
Each target specifies a kernel defconfig to be used as a base. Additional
overrides may then be specified in the target/<arch>/kernel file. Global
overrides are set in defaults/kernel.

## Known issues
The powerpc64 target boots but fails to start init.
