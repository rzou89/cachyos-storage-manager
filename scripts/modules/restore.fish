# Module: Rollback & Restore for CSM

function _csm_restore_app
    set -l app_name $argv[1]
    set -l src_path $argv[2]
    set -l dest_path $argv[3]

    if test -L "$src_path"
        set -l target (readlink -f "$src_path")
        if test "$target" = "$dest_path"; and test -d "$dest_path"
            echo "-> Mengembalikan $app_name ke $src_path ..."
            rm "$src_path"
            mv "$dest_path" "$src_path"
            echo "[OK] Berhasil dipulihkan: $app_name"
        end
    end
end

function csm_restore
    if test -z "$CSM_ROOT"
        echo "[ERROR] CSM_ROOT tidak terkonfigurasi."
        return 1
    end

    echo "========================================"
    echo "   CSM Rollback & Restore Tool (v1.0.0) "
    echo "========================================"
    read -P "Apakah Anda yakin ingin mengembalikan SELURUH data dari NVMe ke lokal ($HOME)? [y/N]: " confirm
    if not string match -ri '^y(es)?$' -- "$confirm"
        echo "[CANCELLED] Proses restore dibatalkan."
        return 0
    end

    echo ""
    echo ">>> Mengembalikan data ke direktori lokal..."
    _csm_restore_app "Heroic Games Launcher" "$HOME/.config/heroic" "$CSM_ROOT/apps/heroic"
    _csm_restore_app "UMU Proton Runtime" "$HOME/.local/share/umu" "$CSM_ROOT/apps/umu"
    _csm_restore_app "Hydra Launcher Config" "$HOME/.config/hydralauncher" "$CSM_ROOT/apps/hydralauncher"
    _csm_restore_app "Goverlay / MangoHud" "$HOME/.local/share/goverlay" "$CSM_ROOT/apps/goverlay"
    _csm_restore_app "Lutris Config & Runners" "$HOME/.local/share/lutris" "$CSM_ROOT/apps/lutris"
    _csm_restore_app "Desktop Icon Themes" "$HOME/.local/share/icons" "$CSM_ROOT/system/icons"
    _csm_restore_app "VS Code - OSS Config" "$HOME/.config/Code - OSS" "$CSM_ROOT/dev/code-oss"
    _csm_restore_app "VS Code Extensions" "$HOME/.vscode" "$CSM_ROOT/dev/vscode-extensions"
    _csm_restore_app "Python UV Cache" "$HOME/.local/share/uv" "$CSM_ROOT/dev/uv"
    _csm_restore_app "Python Pip Cache" "$HOME/.cache/pip" "$CSM_ROOT/cache/pip"
    _csm_restore_app "Rust Cargo" "$HOME/.cargo" "$CSM_ROOT/dev/cargo"
    _csm_restore_app "NPM Cache" "$HOME/.npm" "$CSM_ROOT/cache/npm"
    _csm_restore_app "DXVK Shader Cache" "$HOME/.cache/dxvk" "$CSM_ROOT/shader-cache/dxvk"

    echo ""
    echo "========================================"
    echo " Proses Restore Selesai!"
    echo "========================================"
end
