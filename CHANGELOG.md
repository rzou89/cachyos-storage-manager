# Changelog

Semua perubahan penting dalam proyek **CachyOS Storage Manager (CSM)** akan dicatat di dokumen ini.

Format ini berdasarkan [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) dan mematuhi [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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