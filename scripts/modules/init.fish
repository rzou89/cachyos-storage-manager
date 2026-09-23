#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Setup / Relocate / Edit
#
# Wizard-style helpers for first-time setup and for changing
# the target drive without editing config by hand.
#
# Public entry points (called from csm.fish):
#   csm_setup       -> csm setup
#   csm_relocate    -> csm relocate <path>
#   csm_edit        -> csm edit [show|open|validate]
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

function __csm_init_watcher_active
    if not command -sq systemctl
        return 1
    end
    systemctl --user is-active csm-flatpak-watcher.service >/dev/null 2>&1
end

function __csm_init_watcher_stop
    if command -sq systemctl
        systemctl --user stop csm-flatpak-watcher.service 2>/dev/null
    end
end

function __csm_init_watcher_start
    if command -sq systemctl
        systemctl --user start csm-flatpak-watcher.service 2>/dev/null
    end
end

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
        mkdir -p "$path"
        or begin
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

# Write a fresh config file from template, preserving values
# that user may have customised (installation, watch flag).
function __csm_init_write_config
    set -l target "$argv[1]"
    set -l cfg (csm_config_path)

    set -l installation "datacachyos"
    if set -q CSM_FLATPAK_INSTALLATION
        set installation "$CSM_FLATPAK_INSTALLATION"
    end

    set -l watch "1"
    if set -q CSM_FLATPAK_WATCH
        set watch "$CSM_FLATPAK_WATCH"
    end

    set -l backup_before "1"
    if set -q CSM_BACKUP_BEFORE_MIGRATE
        set backup_before "$CSM_BACKUP_BEFORE_MIGRATE"
    end

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
        echo "# Drive target"
        echo "set -g CSM_TARGET \"$target\""
        echo ""
        echo "# Base folder for all CSM data on the target drive."
        echo "set -g CSM_ROOT \"\$CSM_TARGET/CachyOS-Storage-Data-Migration\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Flatpak"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_FLATPAK_DIR \"\$CSM_ROOT/flatpak\""
        echo "set -g CSM_FLATPAK_CORE_DIR \"\$CSM_ROOT/flatpak/system\""
        echo "set -g CSM_FLATPAK_INSTALLATION \"$installation\""
        echo "set -g CSM_FLATPAK_WATCH $watch"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Paru"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_PARU_DIR \"\$CSM_ROOT/paru\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Pacman (reserved, not used yet)"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_PACMAN_DIR \"\$CSM_ROOT/pacman\""
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# User Cache (reserved, not used yet)"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_CACHE_DIR \"\$CSM_ROOT/data cache\""
        echo "set -g CSM_CACHE_MIGRATE paru yay thumbnails mozilla chromium \\"
        echo "    BraveSoftware spotify discord telegram Code JetBrains \\"
        echo "    pip npm yarn go-build"
        echo "set -g CSM_CACHE_SKIP  _db \\"
        echo "    fontconfig dconf ibus fcitx5"
        echo ""
        echo "# ------------------------------------------------------------"
        echo "# Global"
        echo "# ------------------------------------------------------------"
        echo ""
        echo "set -g CSM_BACKUP_BEFORE_MIGRATE $backup_before"
    end > "$cfg"
end

function __csm_init_module_list
    # Modules that participate in relocate.
    # Add to this list as new modules get relocate support.
    echo flatpak
    echo paru
end

# ------------------------------------------------------------
# csm setup
# ------------------------------------------------------------

function csm_setup

    # Auto-rename legacy directory with spaces if found
    if test -d "$CSM_TARGET/CachyOS Storage Data Migration"
        echo "Mendeteksi folder lama dengan spasi. Mengubah nama direktori..."
        mv "$CSM_TARGET/CachyOS Storage Data Migration" "$CSM_TARGET/CachyOS-Storage-Data-Migration"
    end


    csm_section "CachyOS Storage Manager - Setup"

    set -l cfg (csm_config_path)
    echo "Config : $cfg"

    if test -f "$cfg"
        echo ""
        csm_warn "Config sudah ada."
        if not csm_confirm "Overwrite? (backup akan dibuat)" "N"
            echo "Dibatalkan."
            return 1
        end
        set -l backup (csm_config_backup)
        if test -n "$backup"
            csm_ok "Backup: $backup"
        end
    end

    echo ""
    echo "Drive target (contoh: /mnt/DataCachyOS)"
    read -P "> " target

    if test -z "$target"
        csm_error "Tidak ada input."
        return 1
    end

    echo ""
    if not __csm_init_validate_drive "$target"
        return 1
    end

    set -l root "$target/CachyOS-Storage-Data-Migration"

    echo ""
    echo "Struktur folder yang akan dibuat:"
    echo "  $root/"
    echo "    ├── Flatpak/"
    echo "    │   ├── Flatpak Core/   (installation, isi manual dengan sudo)"
    echo "    │   └── Flatpak Data/   (data user)"
    echo "    ├── paru/"
    echo "    ├── pacman/             (reserved)"
    echo "    └── data cache/         (reserved)"
    echo ""

    if not csm_confirm "Lanjut?" "Y"
        return 1
    end

    mkdir -p "$root/flatpak/system" \
             "$root/flatpak" \
             "$root/paru" \
             "$root/pacman" \
             "$root/data cache"
    csm_ok "Folder dibuat"

    __csm_init_write_config "$target"
    csm_ok "Config ditulis ke $cfg"

    # Reload in current process so migrate below uses new paths.
    source "$cfg"
    csm_normalize_config

    echo ""
    if csm_confirm "Migrate data yang ada sekarang?" "Y"
        echo ""
        csm_flatpak_migrate
        echo ""
        csm_paru_migrate
    end

    echo ""
    echo "Flatpak watcher service:"
    if command -sq systemctl
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user enable --now csm-flatpak-watcher.service 2>/dev/null
        if test $status -eq 0
            csm_ok "Watcher diaktifkan"
        else
            csm_warn "Watcher tidak bisa diaktifkan (mungkin belum di-install via setup.fish)"
        end
    else
        csm_warn "systemctl tidak ada, watcher dilewati"
    end

    echo ""
    csm_ok "Setup selesai"
    echo ""
    echo "Langkah berikutnya:"
    echo "  csm status"
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

    if not csm_load_config
        return 1
    end

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
    if test -z "$old_root"
        set old_root "$old_drive/CachyOS-Storage-Data-Migration"
    end
    set -l new_root "$new_drive/CachyOS-Storage-Data-Migration"

    set -l old_flatpak "$CSM_FLATPAK_DIR"
    set -l old_paru "$CSM_PARU_DIR"
    set -l new_flatpak "$new_root/flatpak"
    set -l new_flatpak_core "$new_root/flatpak/system"
    set -l new_paru "$new_root/paru"

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

    # Prepare new folders
    mkdir -p "$new_flatpak" "$new_flatpak_core" "$new_paru"

    # Relocate modules
    echo ""
    echo "[ 1/2 ] flatpak"
    csm_flatpak_relocate "$old_flatpak" "$new_flatpak"

    echo ""
    echo "[ 2/2 ] paru"
    csm_paru_relocate "$old_paru" "$new_paru"

    # Update config
    __csm_init_write_config "$new_drive"
    csm_ok "Config di-update"

    # Restart watcher
    if test "$watcher_was_active" = "1"
        __csm_init_watcher_start
        csm_ok "Watcher di-restart"
    end

    # Ask about old data
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

        case "" "show"
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                echo "Jalankan: csm setup"
                return 1
            end
            echo "Config: $cfg"
            echo ""
            cat "$cfg"

        case "open" "edit"
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                echo "Jalankan: csm setup"
                return 1
            end
            set -l editor "$EDITOR"
            if test -z "$editor"
                if command -sq nano
                    set editor nano
                else if command -sq vi
                    set editor vi
                else
                    csm_error "Tidak ada editor. Set \$EDITOR."
                    return 1
                end
            end
            $editor "$cfg"

        case "validate"
            if not test -f "$cfg"
                csm_error "Config tidak ada: $cfg"
                return 1
            end
            source "$cfg"
            csm_normalize_config

            echo "Validasi config:"
            echo ""
            echo "  CSM_TARGET       : $CSM_TARGET"
            echo "  CSM_ROOT         : $CSM_ROOT"
            echo "  CSM_FLATPAK_DIR  : $CSM_FLATPAK_DIR"
            echo "  CSM_PARU_DIR     : $CSM_PARU_DIR"
            echo ""

            set -l fail 0
            for var in CSM_TARGET CSM_ROOT CSM_FLATPAK_DIR CSM_PARU_DIR
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
            end

        case "help" "-h" "--help"
            echo "Usage:"
            echo "  csm edit              Tampilkan config"
            echo "  csm edit open         Buka di \$EDITOR"
            echo "  csm edit validate     Validasi config"

        case "*"
            csm_error "Unknown action: $action"
            return 1
    end
end
