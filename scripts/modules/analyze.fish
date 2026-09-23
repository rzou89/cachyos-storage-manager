# Module: Storage Analysis Dashboard for CSM

function csm_analyze
    if test -z "$CSM_ROOT"; or not test -d "$CSM_ROOT"
        echo "[ERROR] CSM_ROOT belum terkonfigurasi atau direktori tidak ditemukan."
        return 1
    end

    echo "=========================================================="
    echo "       CachyOS Storage Manager - Storage Dashboard        "
    echo "=========================================================="
    echo ""
    echo "Lokasi NVMe Target: $CSM_ROOT"
    echo ""
    printf "%-18s %-15s %s
" "Kategori" "Ukuran NVMe" "Status Migrasi"
    echo "----------------------------------------------------------"

    set -l categories "apps" "cache" "dev" "shader-cache" "steam" "system" "flatpak"
    for cat in $categories
        set -l path "$CSM_ROOT/$cat"
        if test -d "$path"
            set -l size (du -sh "$path" 2>/dev/null | cut -f1)
            printf "%-18s %-15s %s
" "$cat" "$size" "[OK] Terpasang"
        else
            printf "%-18s %-15s %s
" "$cat" "0B" "[-] Belum Ada"
        end
    end

    echo "----------------------------------------------------------"
    echo ""
    echo "Statistik Partisi NVMe Target:"
    df -h "$CSM_ROOT" | tail -n 1 | awk '{print "Total Kapasitas: " $2 " | Terpakai: " $3 " | Tersisa: " $4 " (" $5 " terpakai)"}'
    echo ""
end
