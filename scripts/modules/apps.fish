#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Game launchers & app data
#
# Memindahkan folder data launcher game (Heroic, Lutris, ...) plus
# shader cache DXVK ke drive target, lalu menggantinya dengan symlink.
#
# Dipanggil otomatis oleh 'csm setup'.
# ============================================================

# ------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------

# Wrapper tipis di atas csm_link_migrate supaya laporan rapi.
# Argumen: <label> <src> <dest>
function _csm_migrate_app
    csm_link_migrate "$argv[1]" "$argv[2]" "$argv[3]"
    return $status
end

# Jalankan migrasi untuk satu grup (= field 1 dari csm_managed_items).
# Argumen: <grup> ...
function __csm_group_migrate
    set -l wanted $argv

    set -l ok 0
    set -l skipped 0
    set -l failed 0

    for item in (csm_managed_items)
        set -l parts (string split "|" -- $item)
        set -l group $parts[1]
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        if not contains -- "$group" $wanted
            continue
        end

        _csm_migrate_app "$label" "$src" "$dest"
        switch $status
            case 0
                set ok (math $ok + 1)
            case 2
                set skipped (math $skipped + 1)
            case '*'
                set failed (math $failed + 1)
        end
    end

    echo ""
    csm_ok "Selesai: $ok dimigrasikan, $skipped tidak ada, $failed gagal"
    echo ""
    return 0
end

# ------------------------------------------------------------
# Migrate
# ------------------------------------------------------------

function csm_apps_migrate
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    csm_section "Game Launchers & App Data Migration"
    __csm_group_migrate apps shader
end

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

function csm_apps_status
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    csm_section "Game Launchers & App Data Status"

    for item in (csm_managed_items)
        set -l parts (string split "|" -- $item)
        set -l group $parts[1]
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        if not contains -- "$group" apps shader
            continue
        end

        if not test -e "$src"; and not test -L "$src"
            printf "%-28s %-10s %s\n" "$label" "-" "[NOT FOUND]"
        else if test -L "$src"
            if test (readlink "$src") = "$dest"
                printf "%-28s %-10s %s\n" "$label" (csm_dir_size "$src") "[MIGRATED]"
            else
                printf "%-28s %-10s %s\n" "$label" (csm_dir_size "$src") "[OTHER LINK]"
            end
        else
            printf "%-28s %-10s %s\n" "$label" (csm_dir_size "$src") "[LOCAL]"
        end
    end

    echo ""
end

function csm_apps_help
    echo "CachyOS Storage Manager - apps module"
    echo ""
    echo "Usage:"
    echo "  csm apps status     Tampilkan status item launcher & shader"
    echo "  csm apps migrate    Pindah item ke drive target"
    echo ""
    echo "Item yang dikelola: Heroic, UMU, Hydra, Goverlay, Lutris, DXVK cache."
    echo "Modul ini juga dijalankan otomatis oleh 'csm setup'."
    echo ""
    echo "Untuk mengembalikan semua item (termasuk modul lain):"
    echo "  csm restore"
end
