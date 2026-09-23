# Module: Game Launchers & Apps Data Migration for CSM

function _csm_migrate_app
    set -l app_name $argv[1]
    set -l src_path $argv[2]
    set -l dest_path $argv[3]

    if not test -e "$src_path"; and not test -L "$src_path"
        return 0
    end

    if test -L "$src_path"
        set -l current_target (readlink -f "$src_path")
        if test "$current_target" = "$dest_path"
            echo "[ALREADY MIGRATED] $app_name is already symlinked."
            return 0
        end
    end

    set -l parent_dir (dirname "$dest_path")
    mkdir -p "$parent_dir"

    if test -d "$src_path"; and not test -L "$src_path"
        if not test -d "$dest_path"
            echo "-> Moving $src_path to $dest_path ..."
            mv "$src_path" "$dest_path"
        else
            echo "-> Merging $src_path into existing $dest_path ..."
            cp -rP "$src_path/"* "$dest_path/" 2>/dev/null
            rm -rf "$src_path"
        end
        ln -s "$dest_path" "$src_path"
        echo "[OK] Successfully migrated: $app_name"
    end
end

function csm_apps_migrate
    if test -z "$CSM_ROOT"
        return 1
    end

    echo "========================================"
    echo "  Migrating Game Launchers & App Data"
    echo "========================================"

    _csm_migrate_app "Heroic Games Launcher" "$HOME/.config/heroic" "$CSM_ROOT/apps/heroic"
    _csm_migrate_app "UMU Proton Runtime" "$HOME/.local/share/umu" "$CSM_ROOT/apps/umu"
    _csm_migrate_app "Hydra Launcher Config" "$HOME/.config/hydralauncher" "$CSM_ROOT/apps/hydralauncher"
    _csm_migrate_app "Goverlay / MangoHud" "$HOME/.local/share/goverlay" "$CSM_ROOT/apps/goverlay"
    _csm_migrate_app "Lutris Config & Runners" "$HOME/.local/share/lutris" "$CSM_ROOT/apps/lutris"
    _csm_migrate_app "DXVK Shader Cache" "$HOME/.cache/dxvk" "$CSM_ROOT/shader-cache/dxvk"
end
