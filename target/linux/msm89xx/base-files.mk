# The two profiles share a DT compatible; identify the installed build separately.
ufi_profiles := $(CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi001c)$(CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi003)
ifeq ($(ufi_profiles),yy)
  $(error Build UFI001C and UFI003C as separate images)
endif
ifeq ($(ufi_profiles),y)
ufi_pcb := $(if $(CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi003),UFI003C_MB_V02,UFI001C_MB_V01)
ufi_layout := $(if $(CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi003),layout-ufi003c-v1,layout-v1)
ufi_upgrade := platform.sh
ifeq ($(CONFIG_TARGET_ROOTFS_SQUASHFS):$(CONFIG_TARGET_ROOTFS_EXT4FS),y:)
ufi_upgrade := platform-fastboot-only.sh
endif
# Reinstall the board files when an incremental build switches image format.
STAMP_CONFIGURED := $(STAMP_CONFIGURED)_$(ufi_pcb)_$(ufi_upgrade)
define Package/base-files/install-target
	$(INSTALL_DIR) $(1)/usr/share/ufi $(1)/lib/upgrade $(1)/etc/board.d $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PLATFORM_DIR)/ufi/99-ufi-network $(1)/etc/board.d/99-ufi-network
	$(INSTALL_DATA) $(PLATFORM_DIR)/ufi/99-ufi-https $(1)/etc/uci-defaults/99-ufi-https
	echo $(ufi_pcb) > $(1)/usr/share/ufi/pcb
	$(INSTALL_DATA) $(PLATFORM_DIR)/ufi/$(ufi_layout) $(1)/usr/share/ufi/layout-v1
	$(INSTALL_DATA) $(PLATFORM_DIR)/ufi/$(ufi_upgrade) $(1)/lib/upgrade/platform.sh
endef
endif

# These targets/feeds are not published by the official snapshot service.
define Package/base-files/filter-apk-sources
	sed -i -e '\|^https://downloads.immortalwrt.org/snapshots/targets/msm89xx/|d' \
		-e '\|^https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic/openstick/|d' \
		-e '\|^https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic/video/|d' \
		$(1)/etc/apk/repositories.d/distfeeds.list
endef
