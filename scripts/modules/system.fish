#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - System & aesthetics data
#
# Memindahkan data tema/aesthetics (icon themes, ...) ke drive target
# lalu menggantinya dengan symlink.
#
# Dipanggil otomatis oleh 'csm setup'.
# ============================================================

function csm_system_migrate
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    csm_section "System & Aesthetics Data Migration"
    __csm_group_migrate system
end

function csm_system_status
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    csm_section "System & Aesthetics Data Status"

    for item in (csm_managed_items)
        set -l parts (string split "|" -- $item)
        set -l group $parts[1]
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        if test "$group" != "system"
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

function csm_system_help
    echo "CachyOS Storage Manager - system module"
    echo ""
    echo "Usage:"
    echo "  csm system status   Tampilkan status data system & aesthetics"
    echo "  csm system migrate  Pindah ke drive target"
    echo ""
    echo "Item: icon themes (~/.local/share/icons)."
    echo "Modul ini juga dijalankan otomatis oleh 'csm setup'."
    echo ""
    echo "Untuk mengembalikan semua item (termasuk modul lain):"
    echo "  csm restore"
end
