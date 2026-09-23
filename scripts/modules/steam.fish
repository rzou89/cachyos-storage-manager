# CachyOS Storage Manager - Steam & Gaming Module

function csm_steam_status
    csm_load_config; or return 1

    echo "========================================"
    echo " Steam & Gaming Storage Status"
    echo "========================================"
    echo ""

    set -q CSM_WINEPREFIX_DIR; or set -gx CSM_WINEPREFIX_DIR "$CSM_ROOT/wine-prefixes"
    set -q CSM_SHADERCACHE_DIR; or set -gx CSM_SHADERCACHE_DIR "$CSM_ROOT/shader-cache"

    echo "Wine Prefixes Target : $CSM_WINEPREFIX_DIR"
    echo "Shader Cache Target  : $CSM_SHADERCACHE_DIR"
    echo ""

    set -l targets         "$HOME/.local/share/Steam/steamapps/compatdata:Native Steam Compatdata"         "$HOME/.local/share/Steam/steamapps/shadercache:Native Steam Shadercache"         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata:Flatpak Steam Compatdata"         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/shadercache:Flatpak Steam Shadercache"

    printf "%-40s %-12s %-15s
" "Component" "Size" "Status"
    echo "------------------------------------------------------------------"

    for entry in $targets
        set -l parts (string split ":" -- $entry)
        set -l path $parts[1]
        set -l label $parts[2]

        if not test -e "$path"; and not test -L "$path"
            printf "%-40s %-12s %-15s
" "$label" "N/A" "[NOT FOUND]"
            continue
        end

        set -l comp_size "0B"
        if test -d "$path" -o -L "$path"
            set comp_size (du -sh "$path" 2>/dev/null | cut -f1)
        end

        set -l item_status "[UNTRACKED]"
        if test -L "$path"
            set item_status "[MIGRATED]"
        end

        printf "%-40s %-12s %-15s
" "$label" "$comp_size" "$item_status"
    end
end

function csm_steam_migrate
    csm_load_config; or return 1

    set -q CSM_WINEPREFIX_DIR; or set -gx CSM_WINEPREFIX_DIR "$CSM_ROOT/wine-prefixes"
    set -q CSM_SHADERCACHE_DIR; or set -gx CSM_SHADERCACHE_DIR "$CSM_ROOT/shader-cache"

    mkdir -p "$CSM_WINEPREFIX_DIR" "$CSM_SHADERCACHE_DIR"

    echo "========================================"
    echo " Migrating Steam Storage Components"
    echo "========================================"
    echo ""

    set -l targets         "$HOME/.local/share/Steam/steamapps/compatdata:$CSM_WINEPREFIX_DIR/steam-compatdata-native:Native Steam Compatdata"         "$HOME/.local/share/Steam/steamapps/shadercache:$CSM_SHADERCACHE_DIR/steam-shadercache-native:Native Steam Shadercache"         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata:$CSM_WINEPREFIX_DIR/steam-compatdata-flatpak:Flatpak Steam Compatdata"         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/shadercache:$CSM_SHADERCACHE_DIR/steam-shadercache-flatpak:Flatpak Steam Shadercache"

    for entry in $targets
        set -l parts (string split ":" -- $entry)
        set -l src $parts[1]
        set -l dest $parts[2]
        set -l label $parts[3]

        if not test -e "$src"
            continue
        end

        if test -L "$src"
            echo "[SKIP] $label already migrated (symlink)."
            continue
        end

        echo "Migrating: $label ..."
        mkdir -p "$dest"
        rsync -aHAX --remove-source-files "$src/" "$dest/" 2>/dev/null
        rm -rf "$src"
        ln -s "$dest" "$src"
        echo "[OK] Successfully migrated: $label -> $dest"
    end
end

function csm_steam_revert
    csm_load_config; or return 1

    set -q CSM_WINEPREFIX_DIR; or set -gx CSM_WINEPREFIX_DIR "$CSM_ROOT/wine-prefixes"
    set -q CSM_SHADERCACHE_DIR; or set -gx CSM_SHADERCACHE_DIR "$CSM_ROOT/shader-cache"

    echo "========================================"
    echo " Reverting Steam Storage Components"
    echo "========================================"
    echo ""

    set -l targets         "$HOME/.local/share/Steam/steamapps/compatdata:$CSM_WINEPREFIX_DIR/steam-compatdata-native:Native Steam Compatdata"         "$HOME/.local/share/Steam/steamapps/shadercache:$CSM_SHADERCACHE_DIR/steam-shadercache-native:Native Steam Shadercache"         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata:$CSM_WINEPREFIX_DIR/steam-compatdata-flatpak:Flatpak Steam Compatdata"         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/shadercache:$CSM_SHADERCACHE_DIR/steam-shadercache-flatpak:Flatpak Steam Shadercache"

    for entry in $targets
        set -l parts (string split ":" -- $entry)
        set -l src $parts[1]
        set -l dest $parts[2]
        set -l label $parts[3]

        if test -L "$src"
            echo "Reverting: $label ..."
            unlink "$src"
            mkdir -p "$src"
            if test -d "$dest"
                rsync -aHAX --remove-source-files "$dest/" "$src/" 2>/dev/null
                rm -rf "$dest"
            end
            echo "[OK] Reverted: $label back to $src"
        end
    end
end

function csm_steam_clean_orphans
    csm_load_config; or return 1

    echo "========================================"
    echo " Scanning Orphan Steam Compatdata Prefixes"
    echo "========================================"
    echo ""

    set -l compat_dirs "$HOME/.local/share/Steam/steamapps/compatdata" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata"
    set -l steamapps_dirs "$HOME/.local/share/Steam/steamapps" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps"

    set -l orphans_found 0

    for idx in 1 2
        set -l cdir $compat_dirs[$idx]
        set -l sdir $steamapps_dirs[$idx]

        if not test -d "$cdir"
            continue
        end

        set -l real_cdir (realpath "$cdir" 2>/dev/null; or echo "$cdir")

        for item in (/usr/bin/ls -1 "$real_cdir" 2>/dev/null)
            if string match -r "^[0-9]+\$" -- "$item"
                set -l appid "$item"
                set -l acf "$sdir/appmanifest_$appid.acf"

                if not test -f "$acf"; and not contains "$appid" 0 228980 1070560
                    set -l orphan_path "$real_cdir/$appid"
                    set -l orphan_size (du -sh "$orphan_path" 2>/dev/null | cut -f1)
                    echo "[ORPHAN] AppID: $appid | Size: $orphan_size | Path: $orphan_path"
                    set orphans_found (math $orphans_found + 1)
                end
            end
        end
    end

    if test $orphans_found -eq 0
        echo "[OK] No orphan compatdata prefixes found."
    else
        echo ""
        echo "Found $orphans_found orphan prefix(es). Uninstalled games Proton prefixes can be safely cleaned."
    end
end
