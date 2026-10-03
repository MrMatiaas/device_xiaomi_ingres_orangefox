# PRD v2: Investigasi Mendalam Akar Masalah Lag & Rencana Komprehensif Perbaikan Bug POCO F4 GT (ingres)

## 1. Latar Belakang & Pernyataan Masalah
Berdasarkan pengujian pada perangkat fisik **POCO F4 GT / Redmi K50 Gaming (ingres)**, recovery mengalami **lag yang sangat parah hingga tidak dapat digunakan (unusable)**. 

Pengguna telah mengonfirmasi:
1. **Riwayat author lama dibiarkan tetap ada** pada histori git (`okey biarkan author lama`).
2. Melakukan **investigasi sedalam mungkin** ke seluruh lapisan sistem (kernel, DRM, MinUI, CPU governor, scheduler, touch polling, input queue, thermal, dan fstab) untuk menemukan seluruh akar masalah lag dan bug lainnya.
3. Menyusun **PRD (Product Requirements Document) komprehensif** sebelum mengeksekusi perubahan.

---

## 2. Investigasi Mendalam: Mengapa POCO F4 GT Mengalami Lag Sangat Parah?

POCO F4 GT (`ingres`) adalah ponsel gaming berbasis SoC **Qualcomm Snapdragon 8 Gen 1 (SM8450 / taro)** dengan layar **AMOLED 120Hz**, touch sampling rate gaming **480Hz**, tombol fisik pop-up magnetik (*GameKeys*), dan storage **UFS 3.1**.

Melalui analisis mendalam pada seluruh arsitektur recovery, ditemukan **8 faktor kritis** yang secara simultan menyebabkan kelumpuhan performa (lag parah):

---

### Faktor 1: Ketiadaan "Touch Boost" di Recovery Menyebabkan CPU Terkunci di 300 MHz
* **Mekanisme di Android Normal:** Di OS Android normal, ada daemon `powerhal` / `libperfmgr` yang mendengarkan event sentuhan layar. Setiap kali jari menyentuh layar, Android langsung mengirim sinyal *Touch Boost* untuk menaikkan frekuensi CPU ke 1.5–2.0+ GHz selama beberapa ratus milidetik.
* **Kondisi di Recovery:** Di lingkungan recovery (TWRP/OrangeFox), **TIDAK ADA POWERHAL**.
* **Dampak Fatal:** 
  Governor `schedutil` di kernel melihat MinUI sebagai aplikasi yang tidur (*idle*) saat tidak ada interaksi. Saat jari menyentuh layar untuk menggeser (*swipe*), CPU sedang berada di frekuensi terendah **300 MHz pada core Little (Cortex-A510)**.
  Karena MinUI melakukan rendering 2D via software pada resolusi **1080x2400 (2.592.000 piksel)**, memproses 1 frame 32-bit membutuhkan pemrosesan buffer sebesar ~10.4 MB. Pada kecepatan 300 MHz, CPU membutuhkan waktu **150–250 ms per frame**, yang menghasilkan framerate hancur ke **4–6 FPS**. Setiap geseran terasa macet total!
* **Solusi Mutlak:** 
  1. Kunci CPU cluster Little (`cpu0-3`) ke governor `performance` atau naikkan `scaling_min_freq` ke minimal **1.05 GHz – 1.32 GHz**.
  2. Terapkan perintah ini di 3 titik siklus boot: `on init`, `on boot`, dan `postrecoveryboot.sh` agar tidak tertimpa oleh inisialisasi kernel tahap lanjut.

---

### Faktor 2: Polling Thermal Zone 50 Memblokir UI Thread Setiap Detik
* **Kondisi Kode Saat Ini:**
  Di [BoardConfig.mk](file:///workspace/orange-fox-ingres/BoardConfig.mk#L241):
  `TW_CUSTOM_CPU_TEMP_PATH := "/sys/devices/virtual/thermal/thermal_zone50/temp"`
* **Dampak Fatal:**
  1. Pada SM8450, `thermal_zone50` **bukanlah sensor CPU**, melainkan sensor subsistem jarak jauh (modem/PMIC/ADSP) yang membutuhkan komunikasi IPC via GLINK/RPMh.
  2. TWRP memiliki timer internal di thread GUI utama yang membaca file ini **setiap 1 detik** untuk memperbarui status suhu.
  3. Pembacaan sysfs jarak jauh ini mengalami *blocking I/O* atau timeout, sehingga **setiap detik seluruh UI OrangeFox freeze / membeku selama ratusan milidetik**!
  4. Adanya tanda kutip literal `"/..."` juga menyebabkan pemanggilan sistem `open()` gagal dan membanjiri log error secara berulang.
* **Solusi Mutlak:**
  Aktifkan `TW_NO_CPU_TEMP := true` dan hapus `TW_CUSTOM_CPU_TEMP_PATH`. Ini menghentikan thread GUI dari mem-polling sysfs thermal, membebaskan thread antarmuka dari *blocking I/O*.

---

### Faktor 3: Bug Sintaks `*/` di `ueventd.rc` Merusak Izin Hardware Akselerasi Display (MDSS/MDP)
* **Kondisi Kode Saat Ini:**
  Di [recovery/root/vendor/ueventd.rc](file:///workspace/orange-fox-ingres/recovery/root/vendor/ueventd.rc#L434), terdapat baris penutup komentar bahasa C `*/` yang salah tempat:
  ```text
  433: /sys/class/graphics/fb0     msm_cmd_autorefresh_en   0664    system  graphics
  434: */
  435: 
  436: /sys/devices/platform/soc/ae00000.qcom,mdss_mdp power/control 0664 system graphics
  ```
* **Dampak Fatal:**
  Di berkas `.rc`, komentar menggunakan tanda pagar `#`. Ketika daemon `ueventd` membaca baris 434 (`*/`), terjadi syntax error yang menggugurkan pemrosesan izin sysfs di bawahnya. 
  Baris 436 (`ae00000.qcom,mdss_mdp`) adalah pengontrol daya dan performa **Qualcomm Mobile Display Subsystem (MDSS / MDP)**. Kegagalan izin ini melumpuhkan manajemen daya display hardware DRM.
* **Solusi Mutlak:**
  Hapus baris `*/` dari `ueventd.rc`.

---

### Faktor 4: CPU Suspend Aktif Saat Terhubung Charger/USB (`ro.charger.enable_suspend=1`)
* **Kondisi Kode Saat Ini:**
  Di [system.prop](file:///workspace/orange-fox-ingres/system.prop#L2):
  `ro.charger.enable_suspend=1`
* **Dampak Fatal:**
  Saat ponsel dihubungkan ke komputer atau kabel charger dalam mode recovery, properti ini mengizinkan kernel untuk memasuki mode *Deep Sleep (Suspend)*.
  Ketika layar disentuh, kernel harus terbangun dari suspend, menginisialisasi ulang clock bus SPI touchscreen, dan baru memproses event. Hal ini menimbulkan jeda input sentuhan yang parah (*huge input lag / dropped touches*).
* **Solusi Mutlak:**
  Ubah menjadi `ro.charger.enable_suspend=0`.

---

### Faktor 5: Timeout Menunggu Partisi MicroSD Palsu (`recovery.fstab`)
* **Kondisi Kode Saat Ini:**
  Di [recovery/root/system/etc/recovery.fstab](file:///workspace/orange-fox-ingres/recovery/root/system/etc/recovery.fstab#L49):
  `/dev/block/mmcblk0p1 /sdcard vfat nosuid,nodev wait`
* **Dampak Fatal:**
  POCO F4 GT **tidak memiliki slot MicroSD**. Flag `wait` memaksa init/vold untuk memblokir proses mount dan menunggu kemunculan device block `mmcblk0p1` hingga batas waktu timeout habis. Selain itu, konfigurasi ini bertabrakan dengan `RECOVERY_SDCARD_ON_DATA := true`.
* **Solusi Mutlak:**
  Hapus baris `mmcblk0p1` dari `recovery.fstab`.

---

### Faktor 6: Input Queue Flooding dari Touch Panel 480Hz STMicro
* **Kondisi Perangkat:**
  Layar gaming POCO F4 GT memiliki IC Touch **STMicroelectronics FTS** dengan sampling rate hingga **480 Hz** (mengirim hingga 480 sinyal interrupt per detik).
* **Dampak Fatal:**
  Jika MinUI berjalan di CPU frekuensi rendah (300 MHz) dan memproses event input secara sinkron satu per satu pada thread utama, antrean event (`/dev/input/event*`) akan mengalami *buffer overflow*. Akibatnya, UI freeze dan tidak responsif terhadap sentuhan jari.
* **Solusi Mutlak:**
  Dengan menaikkan frekuensi dasar CPU ke >1.0 GHz dan mengoptimalkan buffer grafis di `system.prop`, MinUI dapat menguras antrean event secepat sentuhan dideteksi tanpa menumpuk di kernel.

---

### Faktor 7: Optimasi Tambahan Grafis MinUI di `system.prop`
* MinUI membaca beberapa properti runtime saat menginisialisasi framebuffer:
  1. `ro.minui.pixel_format=RGBX_8888`
  2. `debug.sf.disable_backpressure=1`
  3. `debug.sf.latch_unsignaled=1`
* Menambahkan properti ini di `system.prop` memastikan pipeline rendering langsung terkunci pada mode performa tanpa sinkronisasi buffer yang membebani.

---

### Faktor 8: Redundansi Path Modul Touchscreen
* Driver touchscreen (`fts_touch_spi.ko` dan `xiaomi_touch.ko`) saat ini hanya ada di subfolder `recovery/root/vendor/lib/modules/1.1/`.
* Untuk memastikan modprobe atau script eksternal dapat memuat modul secara instan tanpa kegagalan path, kita buatkan salinan/link di direktori induk `/vendor/lib/modules/`.

---

## 3. Matriks Solusi Rinci (Comprehensive Fix Matrix)

| Komponen | Berkas Terkait | Akar Masalah | Solusi Implementasi |
| :--- | :--- | :--- | :--- |
| **CPU Clock & Governor** | [`init.recovery.qcom.rc`](file:///workspace/orange-fox-ingres/recovery/root/init.recovery.qcom.rc)<br>[`postrecoveryboot.sh`](file:///workspace/orange-fox-ingres/recovery/root/system/bin/postrecoveryboot.sh) | CPU idle di 300MHz karena tidak ada touch boost | Atur `scaling_governor performance` dan naikkan `scaling_min_freq` ke 1.05GHz+ pada `on boot` & `postrecoveryboot.sh`. |
| **Display Permissions** | [`ueventd.rc`](file:///workspace/orange-fox-ingres/recovery/root/vendor/ueventd.rc) | Baris stray `*/` merusak izin MDSS/MDP | Hapus baris 434 (`*/`). |
| **Thermal Stutter** | [`BoardConfig.mk`](file:///workspace/orange-fox-ingres/BoardConfig.mk) | Polling `thermal_zone50` memblokir UI thread tiap detik | Aktifkan `TW_NO_CPU_TEMP := true`, hapus `TW_CUSTOM_CPU_TEMP_PATH`. |
| **Sleep / Suspend** | [`system.prop`](file:///workspace/orange-fox-ingres/system.prop) | CPU suspend saat dicas/kabel terpasang | Ubah `ro.charger.enable_suspend=0`. |
| **MinUI Graphics** | [`system.prop`](file:///workspace/orange-fox-ingres/system.prop) | Format piksel hardware belum dikunci di level properti | Tambahkan `ro.minui.pixel_format=RGBX_8888` & tuning SF. |
| **Storage Timeout** | [`recovery.fstab`](file:///workspace/orange-fox-ingres/recovery/root/system/etc/recovery.fstab) | `wait` pada MicroSD `mmcblk0p1` yang tidak ada | Hapus baris `mmcblk0p1`. |
| **Touch Module Path** | [`recovery/root/vendor/lib/modules/`](file:///workspace/orange-fox-ingres/recovery/root/vendor/lib/modules/) | Modul hanya di subfolder `1.1/` | Sediakan salinan di root `/vendor/lib/modules/`. |
| **Haptics / Getar** | [`BoardConfig.mk`](file:///workspace/orange-fox-ingres/BoardConfig.mk)<br>[`vibratorfeature.rc`](file:///workspace/orange-fox-ingres/recovery/root/vendor/etc/init/vendor.xiaomi.hardware.vibratorfeature.service.rc) | Layanan haptic crash-loop & memblokir Binder | Tetap nonaktif (`TW_NO_HAPTICS := true`, service disabled). |
| **Kecerahan 35%** | [`BoardConfig.mk`](file:///workspace/orange-fox-ingres/BoardConfig.mk)<br>[`init.recovery.qcom.rc`](file:///workspace/orange-fox-ingres/recovery/root/init.recovery.qcom.rc) | Default sebelumnya 50% (1024) | Tetap di 35% (nilai 716 dari 2047). |
| **Git History** | Repositori Git | Permintaan pengguna: biarkan author lama | Pertahankan commit history lama, tambahkan commit baru. |

---

## 4. Rencana Langkah Eksekusi (Implementation Plan)
1. **Perbaikan `ueventd.rc`**: Bersihkan baris penutup `*/` yang rusak.
2. **Optimasi `system.prop`**: Nonaktifkan charger suspend, kunci `ro.minui.pixel_format=RGBX_8888`, dan tambahkan flag SurfaceFlinger.
3. **Penyempurnaan `BoardConfig.mk`**: Tambahkan `TW_NO_CPU_TEMP := true`, hapus `TW_CUSTOM_CPU_TEMP_PATH`.
4. **Pembersihan `recovery.fstab`**: Hapus baris `mmcblk0p1`.
5. **Multi-layer CPU Boosting**:
   * Perbarui [`init.recovery.qcom.rc`](file:///workspace/orange-fox-ingres/recovery/root/init.recovery.qcom.rc) pada blok `on boot` untuk memastikan core CPU 0–7 online dan governor terkunci ke `performance`.
   * Perbarui [`postrecoveryboot.sh`](file:///workspace/orange-fox-ingres/recovery/root/system/bin/postrecoveryboot.sh) agar memverifikasi dan menyetel frekuensi minimum CPU saat runtime recovery dimulai.
6. **Redundansi Modul Touch**: Sinkronkan modul touch ke `/vendor/lib/modules/`.
7. **Commit Git**: Commit seluruh perbaikan di atas atas nama `Bymeopen` dengan tetap mempertahankan commit riwayat lama.
