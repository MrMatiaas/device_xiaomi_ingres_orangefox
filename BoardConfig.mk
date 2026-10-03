#
# Copyright (C) 2022 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/xiaomi/ingres

# Device tree for POCO F4 GT / Redmi K50 Gaming (ingres)
# Partition sizes/offsets below (BOARD_KERNEL_*, BOARD_*_PARTITION_SIZE, BOARD_SUPER_PARTITION_*)
# are verified for ingres hardware.

BOARD_SYSTEMSDK_VERSIONS := 31

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a-branchprot
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := kryo300

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a75

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS ?= product system system_ext vendor vendor_dlkm odm

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

BOARD_AVB_VBMETA_SYSTEM := system
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2

# Bootloader
TARGET_NO_BOOTLOADER := false
TARGET_USES_UEFI := true
TARGET_USES_REMOTEPROC := true
TARGET_NO_KERNEL := false
BOARD_RAMDISK_USE_LZ4 := true

# Build
BUILD_BROKEN_NINJA_USES_ENV_VARS += SDCLANG_AE_CONFIG SDCLANG_CONFIG SDCLANG_SA_ENABLE
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_NINJA_USES_ENV_VARS += RTIC_MPGEN
BUILD_BROKEN_USES_BUILD_HOST_SHARED_LIBRARY := true
BUILD_BROKEN_USES_BUILD_HOST_STATIC_LIBRARY := true
BUILD_BROKEN_USES_BUILD_HOST_EXECUTABLE := true
BUILD_BROKEN_USES_BUILD_COPY_HEADERS := true

# Crypto
# On the old fox_12.1 source, TW_INCLUDE_CRYPTO=true crashed (SIGABRT in
# "Retrieving key from keymaster") because it linked the legacy HIDL Keymaster
# wrapper, and this device's vendor partition only exposes modern KeyMint AIDL.
# This fox_14.1 tree's system/vold/Keystore.cpp already talks to
# android.system.keystore2.IKeystoreService (KeyMint AIDL) instead, and
# bootable/recovery/Android.mk links libkeymint_support /
# lib_android_keymaster_keymint_utils when this is true -- so re-enabling it
# here should let /data actually mount instead of permanently failing with
# "Unable to mount /data" / "Unable to recreate /data/media folder.".
# UPDATE: first test hung forever at the OrangeFox splash logo (adb still
# responsive, so not the old full hang -- just vold blocked). Root cause:
# device/qcom/twrp-common/crypto/init.recovery.qcom_decrypt.rc (which sets
# crypto.ready=1 and starts keymint-qti -- required for vold's read_key() to
# unwrap the hw-wrapped metadata key) was never being packaged into the
# ramdisk at all, because BOARD_USES_QCOM_FBE_DECRYPTION was never set here.
# This device is FBE (not FDE), so per device/qcom/twrp-common/README.md:
TW_INCLUDE_CRYPTO := true
BOARD_USES_QCOM_FBE_DECRYPTION := true
# UPDATE 2 (historical): both available keymint HAL binaries were broken --
# our own bundled /system/bin/android.hardware.security.keymint-service-qti
# failed to link (needs android.hardware.security.keymint-V1-ndk_platform.so,
# which only exists inside an APEX module recovery never mounts), and the
# vendor's own referenced /vendor/bin/hw/android.hardware.security.
# onekeymint-service-qti simply doesn't exist on this vendor image. Real fix:
# pulled the real, working /vendor/bin/hw/android.hardware.security.
# keymint-service-qti binary plus its 3 APEX-only .so dependencies
# (keymint/secureclock/sharedsecret -V1-ndk_platform.so) straight off a
# normally-booted, rooted HyperOS system, and bundled them into this device
# tree's recovery ramdisk (recovery/root/vendor/{bin/hw,lib64}/) instead of
# relying on the AOSP-compiled or vendor-declared-but-missing versions. Also
# had to delete two STALE prebuilt files that were already sitting in this
# device tree since the fox_12.1 era (recovery/root/system/bin/android.
# hardware.security.keymint-service-qti and recovery/root/vendor/etc/init/
# android.hardware.security.keymint-service-qti.rc) -- they defined a SECOND,
# conflicting "keymint-qti" service pointing at the broken binary, silently
# overriding/colliding with twrp-common's correct service definition even
# after that one was fixed. Confirmed via `ps` that the real binary now
# starts and stays running (no crash-loop). OF_SKIP_FBE_DECRYPTION is no
# longer needed -- removed so the real decrypt attempt actually runs.
BOARD_USES_METADATA_PARTITION := true
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# File systems
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USES_VENDOR_DLKMIMAGE := true

# Kernel
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS := --header_version $(BOARD_BOOT_HEADER_VERSION)

TARGET_COMPILE_WITH_MSM_KERNEL := false
BOARD_KERNEL_IMAGE_NAME := Image

# Neither excluding the kernel (reusing boot_a's) nor embedding the real HyperOS stock
# kernel fixed the boot failure, and controlled testing proved the bootloader tolerates
# kernel/DTB mismatches fine (stock HyperOS recovery ramdisk booted to a real UI using
# PixelOS's own boot_a kernel/vendor_boot/dtbo) -- so the remaining variable is our own
# ramdisk. When the kernel is excluded, boot_a's own baked-in cmdline is used instead of
# ours, which meant our console=tty0/earlyprintk=fb debug flags were silently never
# applied on any prior test. Embedding PixelOS's own kernel Image here (byte-identical to
# what's already in boot_a) keeps the kernel/DTB pairing that's proven to work AND makes
# our own BOARD_KERNEL_CMDLINE (with the debug console flags) actually take effect, so we
# can finally see real crash/panic output if the ramdisk itself is what's failing.
#
# Update: embedding a kernel never mattered either way (self-built, stock HyperOS, and
# PixelOS-matching all hung identically) -- the real bugs turned out to be TW_INCLUDE_CRYPTO
# (Keymaster HIDL 4.x abort, now disabled above) and modules.load.recovery (now emptied).
# Re-enabling kernel exclusion so recovery transparently reuses whatever ROM's boot_a
# kernel is currently flashed (the actual goal: works across every ROM on ingres), now
# combined with both fixes for the first time.
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel

BOARD_KERNEL_BASE        := 0x00000000
BOARD_KERNEL_PAGESIZE    := 4096
BOARD_KERNEL_TAGS_OFFSET := 0x01E00000
BOARD_RAMDISK_OFFSET     := 0x02000000

BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200n8 earlycon msm_geni_serial.con_enabled=1 androidboot.selinux=permissive
BOARD_BOOTCONFIG := androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=a600000.dwc3
BOARD_BOOTCONFIG += androidboot.console=ttyMSM0

# Partitions
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_KERNEL-GKI_BOOTIMAGE_PARTITION_SIZE := $(BOARD_BOOTIMAGE_PARTITION_SIZE)
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_USERDATAIMAGE_PARTITION_SIZE := 48318382080
BOARD_PERSISTIMAGE_PARTITION_SIZE := 33554432
BOARD_METADATAIMAGE_PARTITION_SIZE := 16777216
BOARD_DTBOIMG_PARTITION_SIZE := 24117248
BOARD_FLASH_BLOCK_SIZE := 131072 # (BOARD_KERNEL_PAGESIZE * 64)

BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 9122611200
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor vendor_dlkm odm
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600

BOARD_PERSISTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm

BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop

# Recovery
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# TWRP specific build flags
TW_THEME := portrait_hdpi
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 2400
RECOVERY_SDCARD_ON_DATA := true
TARGET_RECOVERY_QCOM_RTC_FIX := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXCLUDE_ENCRYPTED_BACKUPS := false
TW_EXTRA_LANGUAGES := true
TW_INCLUDE_NTFS_3G := true
TW_USE_TOOLBOX := true
TW_INPUT_BLACKLIST := hbtp_vm
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
TW_EXCLUDE_APEX := true
TW_INCLUDE_PYTHON := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true

# TWRP Display flags
TW_BRIGHTNESS_PATH := /sys/class/backlight/panel0-backlight/brightness
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 716
TW_NO_SCREEN_BLANK := true
# Calibration for 1080x2400 panel
TW_Y_OFFSET := 90
TW_H_OFFSET := -90

# OF_STATUS_H: height of status bar / notch-safe area
OF_STATUS_H := 56

# TWRP Haptics - Disabled
TW_NO_HAPTICS := true
TW_EXCLUDE_TWRPAPP := true

# TWRP Version
TW_DEVICE_VERSION := ingres v1

# Load kernel modules for touch & vibrator. Now that the kernel/modules are built from
# source (matching vermagic guaranteed) instead of borrowed from whatever ROM's "boot"
# partition is flashed, load the base waipio module set plus the two touch drivers that
# aren't part of the generic list, straight from the just-built modules, no prebuilt
# copies / userspace loader workaround needed.
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/modules.load.recovery))

# Real ingres touch panel (fts_touch_spi + its xiaomi_touch dependency) isn't part of the
# stock vendor_boot module set, so it never auto-loads via first-stage init. The .ko files
# in recovery/root/{,vendor/}lib/modules/ were rebuilt from the same Ingres-Centre kernel
# source as prebuilt/kernel above, so their vermagic matches. This enables OrangeFox's own
# userspace vendor-module loader (kernel_module_loader.cpp) to load them.
# TESTED: removing this flag entirely (theorizing it was stale/harmless dead weight left
# over from the self-compiled-kernel era) was tried and caused a real regression -- BOTH
# touch AND battery/health HAL broke on a freshly-reinstalled, clean HyperOS (not just the
# already-suspected PixelOS case). Root cause of that cascade not fully diagnosed, but the
# flag is clearly not just inert -- keep it defined.
TW_LOAD_VENDOR_MODULES := "xiaomi_touch.ko fts_touch_spi.ko"

# Disable CPU temp polling in recovery UI loop to prevent blocking I/O and stutter
TW_NO_CPU_TEMP := true

# Namespace definition for librecovery_updater
SOONG_CONFIG_NAMESPACES += ufsbsg
SOONG_CONFIG_ufsbsg += ufsframework
SOONG_CONFIG_ufsbsg_ufsframework := bsg
