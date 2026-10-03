# Device tree for Redmi K50 Gaming Edition / POCO F4 GT (codename ingres)

OrangeFox Recovery device tree for POCO F4 GT / Redmi K50 Gaming (`ingres`). Built for the `fox_14.1` branch.

## Device specifications

| Device                  | Redmi K50 Gaming Edition / POCO F4 GT                          |
| ----------------------- | :-------------------------------------------------------------- |
| SoC                     | Qualcomm SM8450 Snapdragon 8 Gen 1 (4 nm)                        |
| CPU                     | Octa-core (1x3.00 GHz Cortex-X2 & 3x2.50 GHz Cortex-A710 & 4x1.80 GHz Cortex-A510) |
| GPU                     | Adreno 730                                                       |
| Shipped Android Version | 12 (MIUI 13) — this device tree now builds against OrangeFox's fox_14.1 source branch |
| Partition layout        | A/B, separate vendor_boot, dedicated recovery partition          |
| Kernel                  | Not built from source; recovery reuses whichever kernel is in the active `boot` slot (`BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE`) |
| SELinux                 | Permissive (no custom sepolicy rules)                            |

## Status / known gaps

Validated on a real unlocked ingres unit (bootloader unlocked, `fastboot getvar product` = `ingres`).
Boots to the OrangeFox UI on **both stock HyperOS and PixelOS (AOSP, Android 16 GKI)**, with working
`/data` decryption, touch, and battery. `recovery_a`/`recovery_b` partition sizes matched real
hardware (0x6400000) with no changes needed.

Confirmed working:
- [x] Boots and displays UI, on both a monolithic-kernel ROM (HyperOS) and a GKI/DLKM-kernel ROM
      (PixelOS) — recovery has no kernel of its own and transparently reuses whichever ROM's
      `boot_X` is currently active.
- [x] adbd (note: **native "ADB Sideload" is broken** — hangs at 0% and never transfers. Use
      `adb push <file> /tmp/` then `adb shell twrp install /tmp/<file>` instead.)
- [x] Haptic motor firmware (`aw8697_haptic.bin`, real ingres file bundled in
      `recovery/root/vendor/firmware/` — the ramdisk copy is required because OrangeFox does not
      mount the real `/vendor` partition early enough for the kernel's `request_firmware()` call;
      confirmed via dmesg: `awinic_haptic ...: loaded aw8697_haptic.bin`)
- [x] Notification LED firmware (`aw22xxx_fw.bin`, same mechanism/fix)
- [x] **Touch**. ingres's real touch panel is STMicro FTS over SPI (`fts_touch_spi.ko` + its
      `xiaomi_touch.ko` dependency), loaded via `modprobe` from `/vendor/lib/modules/` at normal
      boot. These aren't part of the base vendor_boot module set recovery boots with, so they never
      load automatically. Fix: real `.ko` files bundled into `recovery/root/vendor/lib/modules/1.1/`,
      loaded via OrangeFox's own userspace vendor-module loader (`TW_LOAD_VENDOR_MODULES` in
      `BoardConfig.mk`, gates compiling in `kernel_module_loader.cpp`). **Do not remove this flag**
      even though it looks redundant with `modules.load.recovery` — it was tried and caused a real
      regression (broke touch AND battery) on a from-scratch test.
- [x] **Battery**. The PMIC battery/charger driver is hosted on the ADSP coprocessor and only
      registers once ADSP remoteproc actually boots — normally triggered by a vendor-only init
      script not present in recovery's ramdisk. Fix: `write /sys/class/remoteproc/remoteproc0/state
      start` added to `recovery/root/init.recovery.qcom.rc` right after the `/firmware` mount.
- [x] **`/data` decryption** (FBE metadata unwrap via KeyMint). Two real vendor-blob bugs, both
      required fixing:
      1. `BOARD_USES_QCOM_FBE_DECRYPTION` was never set, so `device/qcom/twrp-common`'s crypto init
         files never got packaged into the ramdisk at all.
      2. The AOSP-compiled `/system/bin/android.hardware.security.keymint-service-qti` fails to
         link — it needs `android.hardware.security.keymint-V1-ndk_platform.so`, which only exists
         inside an APEX module recovery never mounts. Fixed by pulling the real, working
         `/vendor/bin/hw/android.hardware.security.keymint-service-qti` binary and its 3 APEX-only
         `.so` dependencies off a normally-booted, rooted system, and bundling them into
         `recovery/root/vendor/{bin/hw,lib64}/` instead. `device/qcom/twrp-common`'s `keymint-qti`
         service definition was repointed at the real vendor path.
      Confirmed via `adb shell`: `keymint-service-qti` process stays running, `recovery.log` shows
      `"Data successfully decrypted"`, `/sdcard` mounts with real user files.
- [x] **OTA/full-zip installs via `twrp install`** (needed since native ADB Sideload is broken).
      `update_engine_sideload` needs `android.hardware.boot@1.2-service` (bootctl HAL), which is a
      lazy HIDL service that kept exiting immediately (status 0, no crash) — hwservicemanager
      rejected the AOSP-compiled binary's registration because this device tree never declared it
      in a VINTF manifest. Same fix pattern as KeyMint: real `/vendor/bin/hw/android.hardware.
      boot@1.2-service` binary + its VINTF manifest fragment
      (`recovery/root/vendor/etc/vintf/manifest/android.hardware.boot@1.2.xml`) pulled from a
      normally-booted system and bundled in; `bootable/recovery/etc/init/android.hardware.
      boot@1.2-service.rc` repointed at the vendor path.

Still open / unverified:
- [ ] `BoardConfig.mk` kernel load offsets (`BOARD_KERNEL_TAGS_OFFSET`, `BOARD_RAMDISK_OFFSET`)
      (partition *sizes* were confirmed correct).
- [ ] `prebuilt/kernel` is a real kernel Image (pulled from a stock `boot.img`) but is **not**
      actually embedded in the built recovery image (`BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE`) —
      it exists solely to satisfy the build's `check_vintf_all` step, which fails outright
      (`Cannot extract kernel configs`) if this file is empty/missing. Don't revert it to a 0-byte
      placeholder.
- [ ] No custom sepolicy is included on purpose (recovery runs permissive) — confirmed: an AVC
      denial on `/vendor/firmware/aw22xxx_fw.bin` was logged but did not block access
      (`permissive=1`).
- [ ] Native "ADB Sideload" (Apply from ADB) doesn't work — see above, use `twrp install` instead.
- [ ] Magisk's recovery-zip installer (the `.apk` doubles as a flashable zip) gets past
      "Constructing environment" but fails at "Patching ramdisk" (`ERROR: 1`) — not yet diagnosed.

## Compile

This device tree currently targets OrangeFox's **fox_14.1** source branch (not fox_12.1 — an
Android-12-era `fox_12.1` build's bundled `/init` can't handle a GKI/DLKM kernel like PixelOS's,
even though it works fine on HyperOS's monolithic kernel):

```
mkdir ~/OrangeFox_sync && cd ~/OrangeFox_sync
git clone https://github.com/Just-TWRP/OrangeFox_sync.git sync
cd sync
./orangefox_sync.sh --branch 14.1 --path ~/fox_14.1
```

Place this device tree at `device/xiaomi/ingres` inside that manifest directory, then:

```
cd ~/fox_14.1
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"

lunch twrp_ingres-ap2a-eng
mka adbd recoveryimage
```

Note the newer 3-part `<product>-<release>-<variant>` lunch syntax (`ap2a` is the release config,
not a typo) — the old 2-part `twrp_ingres-eng` no longer works on this branch's build system.

**Ninja/Make caching gotcha**: editing a file that gets copied straight into the ramdisk (theme
XML, `init.recovery.*.rc`, prebuilts under `recovery/root/`) does not reliably trigger a
re-package on the next build — it reports success while `recovery.img` still has the old content.
Always verify by unpacking the built `recovery.img` before flashing. If stale, delete
`out/target/product/ingres/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp`,
`.../ramdisk-recovery.img`, and `.../recovery.img`, then rebuild.

## To flash

```
avbtool erase_footer --image recovery.img
avbtool add_hash_footer --partition_name recovery --partition_size 104857600 \
  --key testkey_rsa2048.pem --algorithm SHA256_RSA2048 --rollback_index 1 --image recovery.img
fastboot flash recovery_a recovery.img
fastboot flash recovery_b recovery.img
```

Flash both slots — recovery has no kernel of its own and must be present on whichever slot's
kernel you're testing against.
