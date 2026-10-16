#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Setup / Relocate / Edit
#
# Wizard-style helpers untuk setup pertama kali dan untuk memindah
# target drive tanpa menyunting config secara manual.
#
# Entry point publik (dipanggil dari csm.fish):
#   csm_setup       -> csm setup
#   csm_relocate    -> csm relocate <path>
#   csm_edit        -> csm edit [show|open|validate]
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

function __csm_init_watcher_active
    if not csm_have systemctl
        return 1
    end
    systemctl --user is-active --quiet csm-flatpak-watcher.service 2>/dev/null
end

function __csm_init_watcher_stop
    if csm_have systemctl
        systemctl --user stop csm-flatpak-watcher.service 2>/dev/null
    end
end

function __csm_init_watcher_start
    if csm_have systemctl
        systemctl --user start csm-flatpak-watcher.service 2>/dev/null
    end
end

# Validasi calon drive target: absolut, ada, mounted, bisa ditulis.
function __csm_init_validate_drive
    set -l path "$argv[1]"

    if test -z "$path"
        csm_error "Path kosong."
        return 1
    end

    if not string match -q '/*' "$path"
        csm_error "Path harus absolut: $path"
        return 1
    end
    csm_ok "Path absolut"

    if not test -d "$path"
        csm_warn "Direktori tidak ada: $path"
        if not csm_confirm "Buat sekarang?" "Y"
            return 1
        end
        if not mkdir -p "$path"
            csm_error "Gagal membuat direktori."
            return 1
        end
    end
    csm_ok "Direktori ada"

    if not csm_is_mounted "$path"
        csm_warn "Bukan filesystem terpisah: $path"
        csm_warn "Ini mengurangi manfaat migrasi."
        if not csm_confirm "Lanjut saja?" "N"
            return 1
        end
    else
        csm_ok "Mounted (separate filesystem)"
    end

    if not test -w "$path"
        csm_error "Tidak bisa ditulis: $path"
        return 1
    end
    csm_ok "Bisa ditulis"

    return 0
end

# Tulis config baru dari template, mempertahankan nilai yang mungkin
# sudah dikustomisasi pengguna (installation, watch flag, whitelist).
# Argumen: <drive-target>
function __csm_init_write_config
    set -l target "$argv[1]"
    set -l cfg (csm_config_path)
    set -l root "$target/"(csm_root_name)

    set -l installation (__csm_default_or CSM_FLATPAK_INSTALLATION "datacachyos")
    set -l watch (__csm_default_or CSM_FLATPAK_WATCH 1)
    set -l backup_before (__csm_default_or CSM_BACKUP_BEFORE_MIGRATE 1)

    # 'paru'/'yay' sengaja tidak ada: modul paru menangani
    # ~/.cache/paru/clone sendiri lewat symlink terpisah.
    set -l whitelist (__csm_default_or CSM_CACHE_WHITELIST \
        mozilla google-chrome chromium zen pip yarn npm go-build \
        cargo thumbnails electron node-gyp clangd)

    set -l blacklist (__csm_default_or CSM_CACHE_BLACKLIST \
        fontconfig mesa_shader_cache mesa_shader_cache_db nvidia \
        pipewire wireplumber systemd dconf ibus fcitx5 ksycoca5 \
        plasmashell gnome-shell)

    set -l timestamp (date '+%Y-%m-%d %H:%M:%S')

    mkdir -p (dirname "$cfg")

    begin
        echo "# ============================================================"
        echo "# CachyOS Storage Manager - Configuration"
        echo "#"
        echo "# Generated on $timestamp by 'csm setup' / 'csm relocate'."
        echo "#"
        echo "# Edit manually with: csm edit open"
        echo "# ============================================================"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Global"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "# Drive target (tanpa spasi - dibutuhkan pacman CacheDir)"
        echo "set -g CSM_TARGET \"$target\""
        echo ""
        echo "# Folder dasar seluruh data CSM di drive target."
        echo "set -g CSM_ROOT \"\$CSM_TARGET/"(csm_root_name)"\""
        echo ""
        echo "# Buat backup sebelum migrasi? (1 = ya, 0 = tidak)"
        echo "set -g CSM_BACKUP_BEFORE_MIGRATE $backup_before"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Flatpak"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "# Data aplikasi Flatpak (~/.var/app/<app-id>)"
        echo "set -g CSM_FLATPAK_DIR \"\$CSM_ROOT/flatpak/flatpak-data\""
        echo ""
        echo "# Flatpak core: binary aplikasi, runtime, repo OSTree."
        echo "# Instalasi terdaftar di /etc/flatpak/installations.d/."
        echo "set -g CSM_FLATPAK_CORE_DIR \"\$CSM_ROOT/flatpak/flatpak-core/system\""
        echo ""
        echo "set -g CSM_FLATPAK_INSTALLATION \"$installation\""
        echo "set -g CSM_FLATPAK_WATCH $watch"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# AUR & package caches"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_PARU_DIR \"\$CSM_ROOT/cache/paru\""
        echo "set -g CSM_PACMAN_DIR \"\$CSM_ROOT/cache/pacman\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# User cache"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_CACHE_DIR \"\$CSM_ROOT/cache\""
        echo ""
        echo "# Folder di bawah ~/.cache yang BOLEH dimigrasikan."
        echo "set -g CSM_CACHE_WHITELIST $whitelist"
        echo ""
        echo "# Folder di bawah ~/.cache yang TIDAK boleh dimigrasikan."
        echo "set -g CSM_CACHE_BLACKLIST $blacklist"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Steam & gaming"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_WINEPREFIX_DIR \"\$CSM_ROOT/apps/wine-prefixes\""
        echo "set -g CSM_SHADERCACHE_DIR \"\$CSM_ROOT/shader-cache\""
    end > "$cfg"
end

# Ambil nilai variabel bila sudah di-set, kalau belum pakai default.
# Argumen: <nama-variabel> [default...]
function __csm_default_or
    set -l name $argv[1]
    set -l fallback $argv[2..-1]

    if set -q $name
        echo $$name
        return 0
    end

    echo $fallback
end

# Buat struktur folder CSM di drive target.
function __csm_init_create_layout
    set -l root "$argv[1]"

    mkdir -p "$root/apps/wine-prefixes" \
             "$root/cache/paru" \
             "$root/cache/pacman" \
             "$root/dev" \
             "$root/shader-cache" \
             "$root/system" \
             "$root/flatpak/flatpak-data" \
             "$root/flatpak/flatpak-core"
    return $status
end

# ------------------------------------------------------------
# csm setup
# ------------------------------------------------------------

function csm_setup

    csm_section "CachyOS Storage Manager - Setup"

    set -l cfg (csm_config_path)
    echo "Config : $cfg"
    echo ""

    # Rename folder legacy yang memakai spasi.
    if set -q CSM_TARGET; and test -d "$CSM_TARGET/CachyOS Storage Data Migration"
        csm_log "Mendeteksi folder lama dengan spasi. Mengubah nama direktori..."
        if mv "$CSM_TARGET/CachyOS Storage Data Migration" "$CSM_TARGET/"(csm_root_name)
            csm_ok "Folder lama diganti namanya."
        else
            csm_warn "Gagal mengganti nama folder lama. Lanjutkan."
        end
    end

    # --- Tentukan drive target ---
    set -l target ""

    if test -f "$cfg"
        csm_load_config
        if set -q CSM_TARGET; and test -n "$CSM_TARGET"
            echo "[INFO] Drive target yang terkonfigurasi saat ini:"
            echo "       $CSM_TARGET"
            echo ""
            echo "Pilih opsi direktori tujuan:"
            echo "  [1] Gunakan drive yang sudah disetting sebelumnya (Default)"
            echo "  [2] Pindah ke drive tujuan baru"
            echo ""
            read -P "Pilihan Anda [1/2] (1/Enter untuk lanjut, 2 untuk baru, q untuk batal): " opt_choice

            switch "$opt_choice"
                case q Q cancel exit
                    echo "[CANCELLED] Proses wizard dibatalkan oleh pengguna."
                    return 0
                case 2
                    set target ""
                case '*'
                    set target "$CSM_TARGET"
            end
        end
    end

    if test -z "$target"
        echo ""
        echo "Masukkan path drive target secara lengkap, contoh: /mnt/DataCachyOS"
        echo "Jangan gunakan spasi pada path (pacman CacheDir tidak mendukung spasi)."
        read -P "> " input_path

        switch "$input_path"
            case "" q Q cancel exit
                echo "[CANCELLED] Proses wizard dibatalkan oleh pengguna."
                return 0
        end
        set target "$input_path"
    end

    # Path yang diketik (atau yang tersimpan di config lama) bisa saja sudah
    # mengandung folder migrasi. Potong supaya struktur tidak bersarang:
    # /mnt/DataCachyOS/<nama>/<nama> -> /mnt/DataCachyOS/<nama>
    set target (csm_target_normalize "$target")

    # --- Validasi ---
    echo ""
    if not __csm_init_validate_drive "$target"
        return 1
    end

    set -l root "$target/"(csm_root_name)

    echo ""
    echo "Struktur folder yang akan dibuat di bawah:"
    echo "  $root/"
    echo "    ├── apps/           (launcher, Wine prefixes)"
    echo "    ├── cache/          (user, paru, pacman)"
    echo "    ├── dev/            (development tools)"
    echo "    ├── flatpak/"
    echo "    │   ├── flatpak-data/       (data user)"
    echo "    │   └── flatpak-core/       (placeholder, isi manual)"
    echo "    ├── shader-cache/"
    echo "    └── system/"
    echo ""

    if not csm_confirm "Lanjut?" "Y"
        echo "Dibatalkan."
        return 1
    end

    # --- Backup + tulis config ---
    if test -f "$cfg"
        set -l backup (csm_config_backup)
        if test -n "$backup"
            csm_ok "Backup: $backup"
        end
    end

    if not __csm_init_create_layout "$root"
        csm_error "Gagal membuat struktur folder."
        return 1
    end
    csm_ok "Folder dibuat"

    __csm_init_write_config "$target"
    csm_ok "Config ditulis ke $cfg"

    # Reload di proses ini agar migrasi di bawah memakai path baru.
    source "$cfg"
    csm_normalize_config

    # --- Migrasi ---
    echo ""
    if csm_confirm "Migrasikan data yang ada sekarang?" "Y"
        echo ""
        if functions -q csm_cache_migrate; csm_cache_migrate; end
        if functions -q csm_apps_migrate; csm_apps_migrate; end
        if functions -q csm_system_migrate; csm_system_migrate; end
        if functions -q csm_dev_migrate; csm_dev_migrate; end
        if functions -q csm_steam_migrate; csm_steam_migrate; end
        if functions -q csm_flatpak_migrate; csm_flatpak_migrate; end
        if functions -q csm_paru_migrate; csm_paru_migrate; end

        # pacman butuh sudo. Modulnya sudah meminta konfirmasi sendiri.
        if functions -q csm_pacman_migrate
            echo ""
            if csm_confirm "Migrasikan cache pacman sekarang? (butuh sudo)" "N"
                csm_pacman_migrate
            end
        end

        echo ""
        if functions -q csm_sync_symlinks
            csm_sync_symlinks
        end
    end

    # --- Watcher ---
    echo ""
    echo "Flatpak watcher service:"
    set -l enable_watch (__csm_default_or CSM_FLATPAK_WATCH 1)

    if csm_have systemctl
        systemctl --user daemon-reload 2>/dev/null
        if test "$enable_watch" = "1"
            if systemctl --user enable --now csm-flatpak-watcher.service 2>/dev/null
                csm_ok "Watcher diaktifkan"
            else
                csm_warn "Watcher tidak bisa diaktifkan (mungkin belum di-install via setup.fish)"
            end
        else
            systemctl --user disable csm-flatpak-watcher.service 2>/dev/null
            csm_warn "Watcher dinonaktifkan sesuai konfigurasi (CSM_FLATPAK_WATCH=$enable_watch)"
        end
    else
        csm_warn "systemctl tidak ada, watcher dilewati"
    end

    echo ""
    csm_ok "Setup selesai"
    echo ""
    echo "Langkah berikutnya:"
    echo "  csm status"
    echo "  csm doctor"
    echo "  csm flatpak status"
    echo "  csm edit open"
end

# ------------------------------------------------------------
# csm relocate
# ------------------------------------------------------------

function csm_relocate

    set -l new_drive "$argv[1]"

    if test -z "$new_drive"
        csm_error "Usage: csm relocate <path>"
        return 1
    end

    csm_require_config; or return 1

    set -l old_drive "$CSM_TARGET"
    if test "$old_drive" = "$new_drive"
        csm_error "Target sama dengan yang sekarang: $new_drive"
        return 1
    end

    csm_section "Pindah Target"

    echo "Dari : $old_drive"
    echo "Ke   : $new_drive"
    echo ""

    if not __csm_init_validate_drive "$new_drive"
        return 1
    end

    set -l old_root "$CSM_ROOT"
    set -l new_root "$new_drive/"(csm_root_name)

    set -l old_flatpak "$CSM_FLATPAK_DIR"
    set -l old_paru "$CSM_PARU_DIR"
    set -l new_flatpak "$new_root/flatpak/flatpak-data"
    set -l new_paru "$new_root/cache/paru"

    echo ""
    echo "Data yang akan dipindah:"
    echo "  flatpak : $old_flatpak"
    if test -d "$old_flatpak"
        du -sh "$old_flatpak" 2>/dev/null
    end
    echo "  paru    : $old_paru"
    if test -d "$old_paru"
        du -sh "$old_paru" 2>/dev/null
    end

    echo ""
    if not csm_confirm "Lanjut?" "N"
        return 1
    end

    # Stop watcher
    set -l watcher_was_active 0
    if __csm_init_watcher_active
        set watcher_was_active 1
        __csm_init_watcher_stop
        csm_ok "Watcher di-stop sementara"
    end

    # Backup config
    set -l backup (csm_config_backup)
    if test -n "$backup"
        csm_ok "Config backup: $backup"
    end

    # Siapkan folder baru
    if not __csm_init_create_layout "$new_root"
        csm_error "Gagal membuat struktur folder di $new_root"
        if test "$watcher_was_active" = "1"
            __csm_init_watcher_start
        end
        return 1
    end

    # Pindahkan modul
    echo ""
    echo "[ 1/2 ] flatpak"
    if functions -q csm_flatpak_relocate
        csm_flatpak_relocate "$old_flatpak" "$new_flatpak"
    end

    echo ""
    echo "[ 2/2 ] paru"
    if functions -q csm_paru_relocate
        csm_paru_relocate "$old_paru" "$new_paru"
    end

    # Update config
    __csm_init_write_config "$new_drive"
    csm_ok "Config di-update"

    # Restart watcher
    if test "$watcher_was_active" = "1"
        __csm_init_watcher_start
        csm_ok "Watcher di-restart"
    end

    # Tanya soal data lama
    echo ""
    if test -d "$old_root"
        if csm_confirm "Hapus data lama di \"$old_root\"?" "N"
            rm -rf "$old_root"
            csm_ok "Data lama dihapus"
        else
            echo "Data lama TIDAK dihapus."
            echo "Hapus manual kalau sudah yakin:"
            echo "  rm -rf \"$old_root\""
        end
    end

    echo ""
    csm_ok "Relocate selesai"
end

# ------------------------------------------------------------
# csm edit
# ------------------------------------------------------------

function csm_edit

    set -l cfg (csm_config_path)
    set -l action ""
    if test (count $argv) -gt 0
        set action "$argv[1]"
    end

    switch "$action"

        case "" show
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                echo "Jalankan: csm setup"
                return 1
            end
            echo "Config: $cfg"
            echo ""
            cat "$cfg"

        case open edit
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                echo "Jalankan: csm setup"
                return 1
            end
            set -l editor "$EDITOR"
            if test -z "$editor"
                if csm_have nano
                    set editor nano
                else if csm_have vi
                    set editor vi
                else
                    csm_error "Tidak ada editor. Set \$EDITOR."
                    return 1
                end
            end
            $editor "$cfg"

        case validate
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                return 1
            end
            csm_load_config

            echo "Validasi config:"
            echo ""
            echo "  CSM_TARGET            : $CSM_TARGET"
            echo "  CSM_ROOT              : $CSM_ROOT"
            echo "  CSM_FLATPAK_DIR       : $CSM_FLATPAK_DIR"
            echo "  CSM_FLATPAK_CORE_DIR  : $CSM_FLATPAK_CORE_DIR"
            echo "  CSM_FLATPAK_INSTALLATION : $CSM_FLATPAK_INSTALLATION"
            echo "  CSM_PARU_DIR          : $CSM_PARU_DIR"
            echo "  CSM_PACMAN_DIR        : $CSM_PACMAN_DIR"
            echo "  CSM_CACHE_DIR         : $CSM_CACHE_DIR"
            echo "  CSM_WINEPREFIX_DIR    : $CSM_WINEPREFIX_DIR"
            echo "  CSM_SHADERCACHE_DIR   : $CSM_SHADERCACHE_DIR"
            echo ""

            set -l fail 0
            for var in CSM_TARGET CSM_ROOT CSM_FLATPAK_DIR CSM_PARU_DIR CSM_PACMAN_DIR CSM_CACHE_DIR
                if not set -q $var
                    csm_warn "$var tidak di-set"
                    set fail 1
                end
            end

            if test "$fail" = "0"
                csm_ok "Semua variabel wajib terisi"
            end

            if set -q CSM_TARGET
                if csm_is_mounted "$CSM_TARGET"
                    csm_ok "Target mounted"
                else
                    csm_warn "Target tidak mounted: $CSM_TARGET"
                end
                if string match -q '* *' "$CSM_TARGET"
                    csm_warn "CSM_TARGET mengandung spasi - modul pacman akan menolaknya."
                end
            end

        case help -h --help
            echo "Usage:"
            echo "  csm edit              Tampilkan config"
            echo "  csm edit open         Buka di \$EDITOR"
            echo "  csm edit validate     Validasi config"

        case '*'
            csm_error "Unknown action: $action"
            return 1
    end
end
