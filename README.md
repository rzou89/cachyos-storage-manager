# CachyOS Storage Manager

![Version](https://img.shields.io/badge/version-1.1.2-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/shell-fish-4aae47)

Pindahkan data besar (Flatpak, Steam, pacman, paru, cache user, toolchain
development) dari NVMe utama ke drive sekunder — otomatis, idempotent, dan
bisa dikembalikan.

**Baru pakai CSM?** Baca [docs/tutorial.md](docs/tutorial.md) dulu: setup
pertama kali, pemakaian harian, dan cara recovery.

## Fitur utama

- Satu CLI (`csm`) dengan subperintah per modul.
- Strategi **symlink** untuk folder user, **CacheDir ganda** untuk pacman
  (aman kalau drive target tidak ke-mount).
- **Verifikasi sebelum hapus**: sumber tidak pernah dihapus sebelum isinya
  dipastikan sudah ada di target.
- **Idempotent**: aman dijalankan berulang kali.
- Setiap perintah merusak selalu minta konfirmasi, dan setiap perubahan
  file sistem dibackup dulu.

## Requirements

- Linux (CachyOS / Arch-based)
- Fish shell
- `rsync` (disarankan; tanpa itu CSM fallback ke `cp -a`)
- `findmnt` (util-linux) untuk deteksi mount
- `flatpak`, `pacman`, `paru` — hanya untuk modul yang memakainya
- `inotify-tools` (`inotifywait`) untuk Flatpak watcher
- `sudo` — hanya untuk modul `pacman` dan `flatpak core`

## Instalasi

```bash
git clone https://github.com/rzou89/cachyos-storage-manager.git
cd cachyos-storage-manager
./setup.fish
```

Installer akan:

1. Menyalin entry point ke `~/.local/bin/csm`.
2. Menyalin inti CLI ke `~/.local/share/cachyos-storage-manager/csm.fish`.
3. Menyalin modul ke `~/.local/share/cachyos-storage-manager/modules/`.
4. Menyalin contoh config ke `~/.config/cachyos-storage-manager/config.fish`.
5. Memasang dan mengaktifkan systemd user service untuk Flatpak watcher.

Lalu jalankan wizard:

```bash
csm setup
```

## Struktur folder di drive target

```
<target>/CachyOS-Storage-Data-Migration/
├── apps/               launcher game + Wine prefixes (Steam compatdata)
├── cache/              cache user, paru, pacman
├── dev/                toolchain & cache development
├── flatpak/
│   ├── flatpak-data/   data user Flatpak (~/.var/app/<app-id>)
│   └── flatpak-core/   instalasi Flatpak sistem (perlu sudo)
├── shader-cache/       Steam/DXVK/Mesa shader cache
└── system/             tema & aesthetics
```

> Flatpak **core** (binary aplikasi, runtime, repo OSTree) adalah instalasi
> Flatpak terpisah yang terdaftar di `/etc/flatpak/installations.d/`.
> `csm setup` hanya membuatkan foldernya; pemindahannya manual lewat
> `csm flatpak migrate-core` (butuh sudo).

## Perintah

```bash
csm                       Tampilkan help
csm setup                 Wizard setup pertama kali
csm status                Dashboard pemakaian storage per kategori
csm doctor                Cek dependensi & kesehatan servis
csm restore               Kembalikan data yang didukung ke drive lokal
csm scan                  Pindai & tawarkan migrasi interaktif
csm scan --list           Pindai saja, tanpa menawarkan migrasi
csm version               Tampilkan versi
```

### Modul `scan`

`csm scan` memindai folder besar di `$HOME` yang bisa dipindah, menandai tiap
kandidat sebagai **AMAN** (cache yang bisa dibuat ulang) atau **HATI-HATI**
(bisa berisi konfigurasi, save, atau state aplikasi), lalu menawarkan tiga
mode: pindahkan semua, hanya yang AMAN, atau AMAN plus pilihan HATI-HATI.

Inventori dibangun dari `csm_managed_items`, whitelist cache, data per-aplikasi
Flatpak, clone AUR paru, dan cache paket pacman — jadi tidak menduplikasi
daftar di modul lain. Folder kosong dan aplikasi yang sedang berjalan tidak
ditawarkan.

### Konfigurasi

```bash
csm edit                  Tampilkan config
csm edit open             Buka config di $EDITOR
csm edit validate         Validasi config
csm relocate <path>       Pindah seluruh data ke drive lain
```

### Modul `cache`

Folder di bawah `~/.cache` yang masuk `CSM_CACHE_WHITELIST` dipindah ke
`$CSM_CACHE_DIR/<nama>` lalu diganti symlink. Shader cache masuk
`$CSM_SHADERCACHE_DIR`.

```bash
csm cache status          Status folder cache & status migrasinya
csm cache migrate         Pindah folder whitelist ke drive target
csm cache revert          Kembalikan folder ke ~/.cache
```

### Modul `steam`

```bash
csm steam status          Proton compatdata & shader cache
csm steam migrate         Pindah compatdata & shadercache
csm steam revert          Kembalikan ke lokasi asli
csm steam clean-orphans   Hapus prefix game yang sudah di-uninstall
```

### Modul `pacman`

Butuh `sudo`. Memakai dua entri `CacheDir` di `/etc/pacman.conf`: target
lebih dulu (unduhan baru), lalu `/var/cache/pacman/pkg/` sebagai fallback
kalau drive target tidak ke-mount.

```bash
csm pacman status         Tampilkan kedua cache + isi CacheDir aktif
csm pacman migrate        Salin cache ke target & daftarkan CacheDir
csm pacman cleanup-old    Hapus *.pkg.tar.zst* lama di source
csm pacman revert         Hapus CacheDir & opsional kembalikan data
```

> `pacman.conf` tidak mendukung spasi di `CacheDir`. Pastikan `CSM_TARGET`
> / `CSM_PACMAN_DIR` bebas spasi.

### Modul `paru`

```bash
csm paru status           Status symlink ~/.cache/paru/clone
csm paru migrate          Pindah clone AUR ke target & symlink
csm paru revert           Lepas symlink, kembalikan data
```

### Modul `flatpak`

```bash
csm flatpak status            Instalasi, aplikasi, pemakaian disk
csm flatpak migrate           Pindah ~/.var/app ke drive target
csm flatpak migrate-core      Pindah /var/lib/flatpak ke instalasi custom
csm flatpak core-status       Status instalasi core
csm flatpak relocate-core <path>   Pindah core ke path lain
csm flatpak cleanup           Hapus ref yang tidak terpakai
csm flatpak watch             Jalankan watcher di foreground
```

## Flatpak Watcher

Service systemd level user yang memantau `~/.var/app` dan `/var/lib/flatpak`,
lalu memindahkan data Flatpak baru ke drive target otomatis.

```bash
systemctl --user enable --now csm-flatpak-watcher.service
systemctl --user status csm-flatpak-watcher.service
journalctl --user -u csm-flatpak-watcher.service -f
```

`csm setup` mengaktifkannya otomatis kalau `CSM_FLATPAK_WATCH=1`.

## Konfigurasi

File: `~/.config/cachyos-storage-manager/config.fish`

Variabel | Default | Keterangan
---|---|---
`CSM_TARGET` | `/mnt/DataCachyOS` | Drive tempat data CSM hidup. **Tanpa spasi.**
`CSM_ROOT` | `$CSM_TARGET/CachyOS-Storage-Data-Migration` | Folder dasar di drive target.
`CSM_BACKUP_BEFORE_MIGRATE` | `1` | Backup sebelum migrasi.
`CSM_FLATPAK_DIR` | `$CSM_ROOT/flatpak/flatpak-data` | Data user Flatpak.
`CSM_FLATPAK_CORE_DIR` | `$CSM_ROOT/flatpak/flatpak-core/system` | Instalasi Flatpak sistem.
`CSM_FLATPAK_INSTALLATION` | `datacachyos` | Nama instalasi custom. Cek: `flatpak --installations`.
`CSM_FLATPAK_WATCH` | `1` | Aktifkan watcher.
`CSM_PARU_DIR` | `$CSM_ROOT/cache/paru` | Target clone paru.
`CSM_PACMAN_DIR` | `$CSM_ROOT/cache/pacman` | Cache paket pacman.
`CSM_CACHE_DIR` | `$CSM_ROOT/cache` | Target cache user.
`CSM_CACHE_WHITELIST` | `mozilla chrome pip npm ...` | Folder `~/.cache` yang **boleh** dipindah.
`CSM_CACHE_BLACKLIST` | `mesa_shader_cache fontconfig ...` | Folder yang **tidak boleh** dipindah (menang atas whitelist).
`CSM_WINEPREFIX_DIR` | `$CSM_ROOT/apps/wine-prefixes` | Target Proton compatdata.
`CSM_SHADERCACHE_DIR` | `$CSM_ROOT/shader-cache` | Target shader cache.

Config lama yang masih memakai alias `CSM_FLATPAK_DATA_DIR`,
`CSM_PARU_CLONE_DIR`, `CSM_PACMAN_CACHE_DIR`, `CSM_CACHE_TARGET`,
`CSM_CACHE_MIGRATE`, `CSM_CACHE_SKIP` tetap diterima — nilainya
dinormalisasi otomatis saat config dibaca.

## Design Principles

1. **Verifikasi sebelum hapus** — sumber tidak dihapus sampai isinya
   terbukti ada di target.
2. **Idempotent** — aman dijalankan berulang kali.
3. **Konfirmasi sebelum aksi destruktif.**
4. **Deteksi mount** — peringatkan kalau target bukan filesystem terpisah.
5. **Tidak menyentuh** `/usr`, paket terpasang, atau data di luar daftar
   yang dikelola.
6. **Revert selalu tersedia** untuk setiap modul.

## Uninstall

```bash
csm restore          # kembalikan data ke drive lokal (opsional)
csm pacman revert    # kalau pernah migrasi cache pacman
./uninstall.fish
```

Data di drive target **tidak** dihapus oleh uninstaller.

## Dokumentasi

- [docs/tutorial.md](docs/tutorial.md) — tutorial langkah demi langkah
- [CHANGELOG.md](CHANGELOG.md) — riwayat versi

## License

MIT — lihat `LICENSE`.
