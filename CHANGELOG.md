# Changelog

Semua perubahan penting dalam proyek **CachyOS Storage Manager (CSM)** akan dicatat di dokumen ini.

Format ini berdasarkan [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) dan mematuhi [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.2] - 2026-10-16

### Fixed
- **Urutan pemuatan modul**: `build/csm` memuat `modules/*.fish` secara
  alfabetis, sehingga `modules/csm.fish` menimpa `csm_load_config` dan
  `csm_doctor` milik `common.fish`. Inti CLI sekarang dipisah ke
  `~/.local/share/cachyos-storage-manager/csm.fish` dan dimuat duluan;
  `common.fish` selalu dimuat sebelum modul fitur.
- **`setup.fish` menyalin modul dua kali** ke path berbeda. Sekarang satu
  kali, dan file inti lama di dalam `modules/` dibersihkan.
- **Modul pacman**: `csm_pacman_status` ternyata berisi seluruh logika
  migrasi (`sudo`, `rsync`, edit `/etc/pacman.conf`). Status sekarang
  read-only; migrasi dipindah ke `csm_pacman_migrate` yang sebelumnya
  dipanggil dispatcher tapi tidak pernah didefinisikan.
- **Modul cache**: `csm cache status`, `csm cache migrate`, dan
  `csm cache revert` diimplementasikan (sebelumnya `csm cache` tanpa argumen
  langsung error "Unknown command: csm_cache_status").
- **Dispatcher**: `csm pacman`, `csm paru`, `csm edit`, `csm relocate`, dan
  `csm help` kini bisa dijangkau (sebelumnya semua jatuh ke `csm_usage`).
- **Nama fungsi help**: `__csm_flatpak_help`, `__csm_flatpak_core_help`, dan
  `__csm_paru_help` tidak pernah ditemukan dispatcher; jadi
  `csm <modul> help` selalu gagal. Semua diganti jadi `csm_<modul>_help`.
- **`csm flatpak relocate-core`** tidak bisa dipanggil: dispatcher mencari
  `csm_flatpak_relocate_core` sementara yang ada `csm_flatpak_core_relocate`.
  Ditambahkan alias.
- **Inisialisasi variabel**: `common.fish` menjalankan
  `set -gx CSM_CACHE_DIR "$CSM_ROOT/cache"` saat di-source, padahal
  `CSM_ROOT` belum terbaca → nilainya jadi `/cache`. Sekarang semua default
  dihitung di `csm_normalize_config` setelah config dibaca.
- **`set -q CSM_CACHE_WHITELIST mesa_shader_cache`** selalu bernilai false:
  argumen kedua `set -q` dianggap index, bukan nilai. Akibatnya whitelist
  pengguna selalu ditimpa default. Diperbaiki jadi
  `set -q CSM_CACHE_WHITELIST` + `contains`.
- **Wizard setup merusak config**: `csm_interactive_setup` menulis ulang
  config hanya 3 baris (menghapus semua variabel lain, tanpa backup) dan
  menetapkan `CSM_ROOT` sama dengan `CSM_TARGET`. Sekarang config ditulis
  lengkap dari template, didahului backup, dan `CSM_ROOT` selalu
  `$CSM_TARGET/CachyOS-Storage-Data-Migration`.
- **`__csm_init_write_config` memakai path v1.0.0** (`$CSM_ROOT/paru`,
  `"$CSM_ROOT/data cache"` dengan spasi). Diperbarui ke struktur v1.1.
- **Keamanan migrasi**: `csm_steam_migrate` menjalankan `rm -rf "$src"`
  meski `rsync` gagal, dan `_csm_migrate_app` menghapus sumber setelah `cp`
  tanpa cek status. Semua pemindahan sekarang lewat `csm_link_migrate` /
  `csm_link_revert`, yang verifikasi jumlah entri dulu sebelum menghapus.
- **Deteksi symlink di `~/.cache`**: glob `*/` membuat `test -L` mengikuti
  symlink sehingga folder yang sudah dimigrasikan tidak pernah terdeteksi.
- **Duplikasi daftar item**: path item yang dikelola terduplikasi di
  `apps.fish`, `dev.fish`, `system.fish`, `restore.fish`, dan `analyze.fish`.
  Sekarang satu sumber: `csm_managed_items` di `common.fish`.
- **Modul flatpak** memanggil `flatpak` tanpa cek ketersediaan → error
  fish mentah saat flatpak tidak terinstall.

### Added
- `csm_link_migrate` / `csm_link_revert` / `csm_count_entries` /
  `csm_dir_size` sebagai primitif migrasi bersama.
- `csm_managed_items` — daftar kanonik item yang dikelola CSM.
- `csm apps status`, `csm dev status`, `csm system status` (belum
  terdaftar di dispatcher, dipakai internal & untuk debugging).
- Memoization di `csm_validate_target` supaya `csm setup` tidak menanyakan
  hal yang sama berkali-kali dalam satu sesi.
- `csm pacman cleanup-old` dengan konfirmasi bertulis `HAPUS`.

### Changed
- `CSM_CACHE_WHITELIST` default tidak lagi memuat `paru`/`yay`: clone AUR
  ditangani modul paru sendiri lewat symlink terpisah, dan kalau folder
  induknya ikut di-symlink, symlink clone akan rusak.
- `csm status` menampilkan status per item selain per kategori.
- `csm restore` sekarang memakai `csm_link_revert` (verifikasi sebelum
  hapus) dan menampilkan daftar yang akan dikembalikan sebelum eksekusi.
- README, `config/config.fish.example`, dan tutorial diselaraskan dengan
  CLI yang benar-benar aktif.

---

## [1.1.1] - 2026-09-28

### Fixed
- Selaraskan lokasi default prefix Wine Steam ke `$CSM_ROOT/apps/wine-prefixes` di modul Steam dan sinkronisasi symlink.
- Selaraskan lokasi default `paru`, `pacman`, dan cache pada contoh konfigurasi dengan struktur `$CSM_ROOT/cache/`.
- Samakan versi yang ditampilkan CLI dan modul restore dengan versi rilis.

### Documentation
- Perbarui README dan tutorial agar mencerminkan perintah CLI dan struktur folder yang aktif.

---

## [1.1.0] - 2026-09-25

### Added
- Penyempurnaan migrasi dan normalisasi konfigurasi untuk struktur direktori CSM v1.
- Arsip legacy untuk referensi perubahan modul Flatpak.

### Changed
- Perbaikan alur pemuatan konfigurasi dan command utama `csm`.
- Penyederhanaan modul pacman serta penyesuaian pengelolaan cache dan Flatpak.

### Fixed
- Perbaikan path target dan kompatibilitas konfigurasi antar modul.

---

## [1.0.0] - 2026-09-23

### 🚀 Major Release & New Features
- **Storage Analytics Dashboard (`csm analyze` / `csm info`)**: Menampilkan visualisasi penggunaan disk per kategori (`apps`, `cache`, `dev`, `shader-cache`, `steam`, `system`, `flatpak`) serta statistik sisa partisi NVMe.
- **Rollback & Restoration Tool (`csm restore`)**: Memungkinkan pengguna mengembalikan seluruh data dan melepaskan *symlink* dari NVMe kembali ke direktori lokal (`$HOME`) secara aman.
- **Auto-Config Loader**: Menjamin variabel `$CSM_ROOT` dan file konfigurasi selalu ter muat otomatis pada sub-perintah mandiri seperti `csm doctor` dan `csm analyze`.

### 🛠️ Improvements & Fixes
- Standarisasi penuh penamaan variabel lingkungan (`CSM_ROOT`, `CSM_TARGET`, `CSM_PARU_DIR`).
- Penanganan ketat variabel kosong di Fish Shell untuk mencegah error pembuatan direktori (`mkdir /cache`).
- Penyesuaian sintaksis bebas dari *warning/error* linter.

---

## [0.9.0] - 2026-09-23

### ✨ Added
- **Arsitektur NVMe Terpadu**: Pengelompokan folder target yang rapi di bawah `$CSM_ROOT/` (`apps/`, `cache/`, `dev/`, `shader-cache/`, `steam/`, `system/`, `flatpak/`).
- **Interactive Re-configuration Wizard**: Menambahkan opsi untuk menggunakan lokasi NVMe yang sudah ada vs menentukan lokasi baru, lengkap dengan opsi pembatalan bersih (`q` / Enter).
- **Dukungan Modul Baru**: `apps.fish`, `dev.fish`, `system.fish`.

---

## [0.8.0] - 2026-09-15

### 🎉 Initial Baseline Release
- Peluncuran versi dasar modul migrasi Steam, Flatpak watcher, dan pacman/paru cache.

---

## [0.7.0] - 2026-09-10
- Integrasi modul Flatpak core watcher dan otomasi sinkronisasi background service.

---

## [0.6.1] - 2026-09-05
- Perbaikan bug broken symlink pada cache pacman dan paru.

---

## [0.6.0] - 2026-09-01
- Integrasi awal modul pengelolaan cache AUR (paru) dan pacman.

---

## [0.1.0] - [0.5.0] - 2026-08-01
- Versi rilis eksperimental awal dan penentuan struktur direktori migrasi.
