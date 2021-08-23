include config.mk

# All target architectures
TARGETS := $(patsubst targets/%/,%,$(dir $(wildcard targets/*/config)))

# Default to native build
ARCH ?= $(shell uname -m)

# Directories
BINDIR    := $(PWD)/bin
SRCDIR    := $(PWD)/src
BUILDDIR  := $(PWD)/build/$(ARCH)
TARGETDIR := $(PWD)/targets/$(ARCH)
SCRIPTDIR := $(PWD)/scripts

# Kernel version
ifneq ($(KERNEL_SRC),)
KERNEL_DIR := $(notdir $(patsubst %/,%,$(KERNEL_SRC)))
else
ifneq ($(KERNEL_VER),)
KERNEL_DIR := linux-$(KERNEL_VER)
KERNEL_PKG := $(KERNEL_DIR).tar.xz
KERNEL_URL := https://cdn.kernel.org/pub/linux/kernel/v5.x/$(KERNEL_PKG)
endif
endif

# Busybox version
BUSYBOX_DIR := busybox-$(BUSYBOX_VER)
BUSYBOX_PKG := $(BUSYBOX_DIR).tar.bz2
BUSYBOX_URL := https://busybox.net/downloads/$(BUSYBOX_PKG)

# Toolchain cross-make version
CROSSMAKE_DIR := musl-cross-make
CROSSMAKE_GIT := https://github.com/richfelker/musl-cross-make.git

# Arch-specific configuration
-include $(TARGETDIR)/config
TOOLCHAIN ?= $(ARCH)-linux-musl
KERNEL_ARCH ?= $(ARCH)
QEMU_ARCH ?= $(ARCH)
QEMU_TTY ?= ttyS0

ifneq ($(QEMU_DTB),)
QEMU_FLAGS += -dtb $(BUILDDIR)/$(KERNEL_DIR)/$(QEMU_DTB)
endif

# Arch-specific kernel config dir
KERNEL_CONFIGDIR := $(SRCDIR)/$(KERNEL_DIR)/arch/$(KERNEL_ARCH)/configs

# Add built toolchains to the search path
PATH := $(PATH):$(BINDIR)/$(TOOLCHAIN)/bin

# ================================================================
#  Top-level targets
# ================================================================

run: $(BUILDDIR)/$(KERNEL_DIR)/vmlinux $(BUILDDIR)/initramfs.cpio.gz
	@echo "Starting system (Ctrl-a x to exit)"
	qemu-system-$(QEMU_ARCH) $(QEMU_FLAGS) \
	    -kernel $(BUILDDIR)/$(KERNEL_DIR)/$(KERNEL_IMAGE) \
	    -initrd $(BUILDDIR)/initramfs.cpio.gz \
	    -nographic -append "console=$(QEMU_TTY) $(QEMU_APPEND)"

clean:
	rm -rf $(BUILDDIR)

distclean: clean
	rm -rf build src dl

prerequisities:
	sudo -k apt-get -y install openbios-sparc openbios-ppc qemu-system

.PHONY: run clean distclean prerequisities

# ================================================================
#  Target architectures
# ================================================================

define Target
$(1):
	$$(MAKE) ARCH=$(1) run
.PHONY: $(1)
endef
$(foreach target,$(TARGETS),$(eval $(call Target,$(target))))

# ================================================================
#  Root file system
# ================================================================

$(BUILDDIR)/initramfs.cpio.gz: $(SCRIPTDIR)/init \
	                       $(BUILDDIR)/$(KERNEL_DIR)/vmlinux \
	                       $(BUILDDIR)/$(BUSYBOX_DIR)/_install
	mkdir -p $(BUILDDIR)/initramfs
	( \
	    set -e ; \
	    cd $(BUILDDIR)/initramfs ; \
	    mkdir -p bin sbin etc proc sys usr/bin usr/sbin ; \
	    cp -a $(BUILDDIR)/$(BUSYBOX_DIR)/_install/* . ; \
	    cp -a $< . ; \
	    chmod +x init ; \
	    find . -print0 | cpio --null -ov --format=newc | gzip > $@ ; \
	)

# ================================================================
#  Kernel build
# ================================================================

# Build the kernel
$(BUILDDIR)/$(KERNEL_DIR)/vmlinux: $(BUILDDIR)/$(KERNEL_DIR)/.config
	rm -rf $(BUILDDIR)/initramfs/lib/modules
	$(MAKE) -C $(BUILDDIR)/$(KERNEL_DIR) ARCH=$(KERNEL_ARCH) \
	        CROSS_COMPILE=$(TOOLCHAIN)- all
	$(MAKE) -C $(BUILDDIR)/$(KERNEL_DIR) ARCH=$(KERNEL_ARCH) \
	        INSTALL_MOD_PATH=$(BUILDDIR)/initramfs modules_install
.PHONY: $(BUILDDIR)/$(KERNEL_DIR)/vmlinux

# Generate kernel config
$(BUILDDIR)/$(KERNEL_DIR)/.config: $(KERNEL_CONFIGDIR)/$(ARCH)_qemu_defconfig
	mkdir -p $(BUILDDIR)/$(KERNEL_DIR)
	$(MAKE) -C $(SRCDIR)/$(KERNEL_DIR) ARCH=$(KERNEL_ARCH) \
	         O=$(BUILDDIR)/$(KERNEL_DIR) $(ARCH)_qemu_defconfig
	(cat defaults/kernel && echo && cat $(TARGETDIR)/kernel && echo) | \
	while read -r LINE; do \
	    CONFIG=$$(echo "$$LINE" | grep -o 'CONFIG_[A-Za-z0-9_-]\+'); \
	    [ -z "$$CONFIG" ] || grep -q "$$CONFIG" $@ || echo "$$LINE" >>$@; \
	done

# Generate kernel defconfig
$(KERNEL_CONFIGDIR)/$(ARCH)_qemu_defconfig: \
                                    $(KERNEL_CONFIGDIR)/$(KERNEL_DEFCONFIG) \
                                    $(TARGETDIR)/kernel $(TARGETDIR)/config \
                                    defaults/kernel Makefile
	echo | cat $< - > $@
	(cat defaults/kernel && echo && cat $(TARGETDIR)/kernel && echo) | \
	while read -r LINE; do \
	    CONFIG=$$(echo "$$LINE" | grep -o 'CONFIG_[A-Za-z0-9_-]\+'); \
	    [ -z "$$CONFIG" ] || sed -i "/$$CONFIG/d" $@; \
	done
	echo | cat defaults/kernel - >> $@
	echo | cat $(TARGETDIR)/kernel - >> $@

# Generate base defconfig
ifeq ($(wildcard $(TARGETDIR)/$(KERNEL_DEFCONFIG)),)
$(KERNEL_CONFIGDIR)/$(KERNEL_DEFCONFIG):
	mkdir -p $(BUILDDIR)/$(KERNEL_DIR)
	$(MAKE) -C $(SRCDIR)/$(KERNEL_DIR) ARCH=$(KERNEL_ARCH) \
	         O=$(BUILDDIR)/$(KERNEL_DIR) $(KERNEL_DEFCONFIG)
	$(MAKE) -C $(BUILDDIR)/$(KERNEL_DIR) ARCH=$(KERNEL_ARCH) savedefconfig
	mv $(BUILDDIR)/$(KERNEL_DIR)/defconfig $@
else
$(KERNEL_CONFIGDIR)/$(KERNEL_DEFCONFIG): $(TARGETDIR)/$(KERNEL_DEFCONFIG)
	cp $< $@
endif
$(KERNEL_CONFIGDIR)/$(KERNEL_DEFCONFIG): $(SRCDIR)/$(KERNEL_DIR)/Makefile

# Prepare kernel source
ifneq ($(KERNEL_SRC),)
$(SRCDIR)/$(KERNEL_DIR)/Makefile:
	mkdir -p $(SRCDIR)
	if echo $(KERNEL_SRC) | grep -q '^/'; then \
	    ln -nfs $(KERNEL_SRC) $(SRCDIR)/$(KERNEL_DIR) || exit 1; \
	else \
	    ln -nfs ../$(KERNEL_SRC) $(SRCDIR)/$(KERNEL_DIR) || exit 1; \
	fi
else
ifneq ($(KERNEL_VER,))
$(SRCDIR)/$(KERNEL_DIR)/Makefile: dl/$(KERNEL_PKG)
	mkdir -p $(SRCDIR)
	tar xf $< -C $(SRCDIR)
	touch $@

dl/$(KERNEL_PKG):
	mkdir -p dl
	wget $(KERNEL_URL) -O $@
else
$(SRCDIR)/$(KERNEL_DIR)/Makefile:
	@echo "Either KERNEL_SRC or KERNEL_VER must be set"
endif
endif

# ================================================================
#  Busybox build
# ================================================================

$(BUILDDIR)/$(BUSYBOX_DIR)/_install: $(BUILDDIR)/$(BUSYBOX_DIR)/.config
	$(MAKE) $(MAKEOPTS) -C $(BUILDDIR)/$(BUSYBOX_DIR) install

$(BUILDDIR)/$(BUSYBOX_DIR)/.config: defaults/busybox defaults/kernel \
                                    $(TARGETDIR)/config \
	                            $(SRCDIR)/$(BUSYBOX_DIR)/Makefile
	mkdir -p $(BUILDDIR)/$(BUSYBOX_DIR)
	cp defaults/busybox $(BUILDDIR)/$(BUSYBOX_DIR)/defconfig
	echo "CONFIG_CROSS_COMPILER_PREFIX=\"$(TOOLCHAIN)-\"" >> \
	     $(BUILDDIR)/$(BUSYBOX_DIR)/defconfig
	$(MAKE) -C $(SRCDIR)/$(BUSYBOX_DIR) \
	         O=$(BUILDDIR)/$(BUSYBOX_DIR) \
	         KBUILD_DEFCONFIG=$(BUILDDIR)/$(BUSYBOX_DIR)/defconfig \
	         defconfig

$(SRCDIR)/$(BUSYBOX_DIR)/Makefile: dl/$(BUSYBOX_PKG)
	mkdir -p $(SRCDIR)
	tar xf $< -C $(SRCDIR)
	touch $@

dl/$(BUSYBOX_PKG):
	mkdir -p dl
	wget $(BUSYBOX_URL) -O $@

# ================================================================
#  Toolchain
# ================================================================

ifeq ($(shell PATH=$(PATH) which $(TOOLCHAIN)-gcc),)
$(BUILDDIR)/$(KERNEL_DIR)/vmlinux $(BUILDDIR)/$(BUSYBOX_DIR)/_install: \
                                                                 $(TOOLCHAIN)
.PHONY: $(TOOLCHAIN)

$(patsubst %,$(ARCH)-linux-%,musl musleabi muslabi64): \
                                  $(BINDIR)/$(TOOLCHAIN)/bin/$(TOOLCHAIN)-gcc

$(patsubst %,$(ARCH)-linux-%,gnu gnueabi gnuabi64):
	@echo "Installing package gcc-$(TOOLCHAIN)"
	sudo -k apt-get -y install gcc-$(TOOLCHAIN)
endif

$(BINDIR)/$(TOOLCHAIN)/bin/$(TOOLCHAIN)-gcc: MAKEOVERRIDES =
$(BINDIR)/$(TOOLCHAIN)/bin/$(TOOLCHAIN)-gcc: $(SRCDIR)/$(CROSSMAKE_DIR)
	cd $< && $(MAKE) TARGET=$(TOOLCHAIN)
	cd $< && $(MAKE) TARGET=$(TOOLCHAIN) \
	                 OUTPUT=$(BINDIR)/$(TOOLCHAIN) install

$(SRCDIR)/$(CROSSMAKE_DIR):
	mkdir -p $(SRCDIR)
	cd $(SRCDIR) && git clone $(CROSSMAKE_GIT) $(CROSSMAKE_DIR)
