#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Storage dashboard
#
# Ringkasan pemakaian drive target per kategori, plus status migrasi
# per item. Read-only, tidak mengubah apa pun.
# ============================================================

function csm_analyze
    csm_require_config; or return 1

    echo ""
    echo "=========================================================="
    echo "       CachyOS Storage Manager - Storage Dashboard        "
    echo "=========================================================="
    echo ""
    echo "Target drive : $CSM_TARGET"
    echo "Target root  : $CSM_ROOT"
    echo ""

    # --- Pemakaian per kategori ---
    printf "%-18s %-12s %s\n" "Kategori" "Ukuran" "Status"
    echo "----------------------------------------------------------"

    set -l categories apps dev system shader-cache cache flatpak
    for cat in $categories
        set -l path "$CSM_ROOT/$cat"
        set -l entries (csm_count_entries "$path")
        if test "$entries" -gt 0
            printf "%-18s %-12s %s\n" "$cat" (csm_dir_size "$path") "[TERPAKAI]"
        else if test -d "$path"
            printf "%-18s %-12s %s\n" "$cat" "0" "[-] kosong"
        else
            printf "%-18s %-12s %s\n" "$cat" "0" "[-] belum dibuat"
        end
    end

    echo "----------------------------------------------------------"
    echo ""

    # --- Status per item ---
    set -l migrated 0
    set -l local 0
    set -l missing 0

    printf "%-30s %-10s %s\n" "Item" "Ukuran" "Status"
    echo "----------------------------------------------------------"

    for item in (csm_managed_items)
        set -l parts (string split "|" -- $item)
        set -l label $parts[2]
        set -l src   $parts[3]
        set -l dest  $parts[4]

        if not test -e "$src"; and not test -L "$src"
            printf "%-30s %-10s %s\n" "$label" "-" "[TIDAK ADA]"
            set missing (math $missing + 1)
        else if test -L "$src"
            printf "%-30s %-10s %s\n" "$label" (csm_dir_size "$src") "[MIGRATED]"
            set migrated (math $migrated + 1)
        else
            printf "%-30s %-10s %s\n" "$label" (csm_dir_size "$src") "[LOKAL]"
            set local (math $local + 1)
        end
    end

    echo "----------------------------------------------------------"
    echo ""
    echo "Ringkasan item: $migrated migrated, $local masih lokal, $missing tidak ada"
    echo ""

    # --- Kapasitas drive ---
    echo "Kapasitas drive target:"
    df -h "$CSM_ROOT" 2>/dev/null | tail -n 1 | awk '{print "  Total: " $2 " | Terpakai: " $3 " | Tersisa: " $4 " (" $5 ")"}'
    echo ""

    echo "Detail per modul:"
    echo "  csm cache status"
    echo "  csm steam status"
    echo "  csm pacman status"
    echo "  csm paru status"
    echo "  csm flatpak status"
    echo ""
end
