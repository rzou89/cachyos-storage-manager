#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Developer tools & caches
#
# Memindahkan cache/toolchain development (Cargo, npm, pip, uv, VS Code)
# ke drive target lalu menggantinya dengan symlink.
#
# Dipanggil otomatis oleh 'csm setup'.
# ============================================================

function csm_dev_migrate
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    csm_section "Developer Tools & Caches Migration"
    __csm_group_migrate dev
end

function csm_dev_status
    if not set -q CSM_ROOT; or test -z "$CSM_ROOT"
        csm_error "CSM_ROOT is not configured. Run 'csm setup'."
        return 1
    end

    csm_section "Developer Tools & Caches Status"

    for item in (csm_managed_items)
        set -l parts (string split "|" -- $item)
        set -l group $parts[1]
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        if test "$group" != "dev"
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

function csm_dev_help
    echo "CachyOS Storage Manager - dev module"
    echo ""
    echo "Usage:"
    echo "  csm dev status      Tampilkan status toolchain & cache development"
    echo "  csm dev migrate     Pindah ke drive target"
    echo ""
    echo "Item: VS Code config/extensions, uv, pip, cargo, npm."
    echo "Modul ini juga dijalankan otomatis oleh 'csm setup'."
    echo ""
    echo "Untuk mengembalikan semua item (termasuk modul lain):"
    echo "  csm restore"
end
