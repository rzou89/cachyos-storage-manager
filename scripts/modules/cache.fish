# CachyOS Storage Manager - Cache Module

function _csm_cache_is_safe -a cache_name
    set -l target_dir "$HOME/.cache/$cache_name"

    # 1. Cek Blacklist
    if contains -- "$cache_name" $CSM_CACHE_BLACKLIST
        echo "[BLACKLISTED] $cache_name berada dalam daftar folder sensitif OS."
        return 1
    end

    # 2. Cek apakah ada UNIX domain socket aktif di dalam folder
    if test -d "$target_dir"
        set -l sockets (find "$target_dir" -type s 2>/dev/null)
        if test -n "$sockets"
            echo "[SOCKET DETECTED] $cache_name berisi UNIX domain socket aktif."
            return 1
        end
    end

    # 3. Cek apakah folder sedang dikunci/digunakan oleh proses aktif (fuser)
    if command -v fuser >/dev/null 2>&1
        if fuser -s "$target_dir" 2>/dev/null
            echo "[ACTIVE PROCESS] $cache_name sedang digunakan oleh aplikasi aktif."
            return 1
        end
    end

    return 0
end

function csm_cache_status
    csm_load_config; or return 1

    echo "========================================"
    echo " Cache Module Status"
    echo "========================================"
    echo ""
    echo "Cache Dir : $CSM_CACHE_DIR"
    echo ""

    if not test -d "$HOME/.cache"
        echo "[ERROR] ~/.cache tidak ditemukan!"
        return 1
    end

    printf "%-30s %-12s %-15s\n" "Cache Name" "Size" "Status"
    echo "------------------------------------------------------------"

    # Menggunakan 'ls -1A' untuk mengabaikan alias shell (seperti eza/lsd)
    for item in (/usr/bin/ls -1A "$HOME/.cache")
        set -l item_path "$HOME/.cache/$item"
        set -l size "--"
        if test -d "$item_path"; or test -L "$item_path"
            set size (du -sh "$item_path" 2>/dev/null | cut -f1)
        end

        # Menggunakan nama 'item_status' agar tidak bentrok dengan variabel reserved '$item_status'
        set -l item_status "[UNTRACKED]"
        if test -L "$item_path"
            set item_status "[MIGRATED]"
        else if contains -- "$item" $CSM_CACHE_BLACKLIST
            set item_status "[BLACKLISTED]"
        else if contains -- "$item" $CSM_CACHE_WHITELIST
            set item_status "[WHITELISTED]"
        end

        printf "%-30s %-12s %-15s\n" "$item" "$size" "$item_status"
    end
end

function csm_cache_migrate
    csm_load_config; or return 1

    echo "========================================"
    echo " Migrating Cache Items (Whitelist-First)"
    echo "========================================"
    echo ""

    mkdir -p "$CSM_CACHE_DIR"

    for item in $CSM_CACHE_WHITELIST
        set -l src "$HOME/.cache/$item"
        set -l dest "$CSM_CACHE_DIR/$item"

        if test -d "$src"; and not test -L "$src"
            echo "Processing: $item ..."
            if _csm_cache_is_safe "$item"
                mkdir -p "$dest"
                rsync -aHAX --remove-source-files "$src/" "$dest/" 2>/dev/null
                rm -rf "$src"
                ln -s "$dest" "$src"
                echo "[OK] Successfully migrated: $item -> $dest"
            else
                echo "[SKIP] Skipping $item due to safety checks."
            end
        else if test -L "$src"
            echo "[ALREADY MIGRATED] $item is already symlinked."
        end
    end
end

function csm_cache_revert
    csm_load_config; or return 1

    echo "========================================"
    echo " Reverting Cache Items to ~/.cache"
    echo "========================================"
    echo ""

    for item in $CSM_CACHE_WHITELIST
        set -l src "$HOME/.cache/$item"
        set -l dest "$CSM_CACHE_DIR/$item"

        if test -L "$src"
            echo "Reverting: $item ..."
            unlink "$src"
            mkdir -p "$src"
            if test -d "$dest"
                rsync -aHAX --remove-source-files "$dest/" "$src/" 2>/dev/null
                rm -rf "$dest"
            end
            echo "[OK] Reverted: $item back to ~/.cache"
        end
    end
end