# The two profiles share a DT compatible; identify the installed build separately.
ifeq ($(CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi001c),y)
define Package/base-files/install-target
	$(INSTALL_DIR) $(1)/usr/share/ufi $(1)/lib/upgrade
	echo UFI001C_MB_V01 > $(1)/usr/share/ufi/pcb
	$(INSTALL_DATA) $(PLATFORM_DIR)/ufi/layout-v1 $(1)/usr/share/ufi/layout-v1
	$(INSTALL_DATA) $(PLATFORM_DIR)/ufi/platform.sh $(1)/lib/upgrade/platform.sh
endef
endif

# These targets/feeds are not published by the official snapshot service.
define Package/base-files/filter-apk-sources
	sed -i -e '\|^https://downloads.immortalwrt.org/snapshots/targets/msm89xx/|d' \
		-e '\|^https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic/openstick/|d' \
		-e '\|^https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic/video/|d' \
		$(1)/etc/apk/repositories.d/distfeeds.list
endef
