# Module: Developer Tools & Package Caches for CSM

function csm_dev_migrate
    if test -z "$CSM_ROOT"
        return 1
    end

    echo "========================================"
    echo "  Migrating Developer Tools & Caches"
    echo "========================================"

    _csm_migrate_app "VS Code - OSS Config" "$HOME/.config/Code - OSS" "$CSM_ROOT/dev/code-oss"
    _csm_migrate_app "VS Code Extensions" "$HOME/.vscode" "$CSM_ROOT/dev/vscode-extensions"
    _csm_migrate_app "Python UV Cache" "$HOME/.local/share/uv" "$CSM_ROOT/dev/uv"
    _csm_migrate_app "Python Pip Cache" "$HOME/.cache/pip" "$CSM_ROOT/cache/pip"
    _csm_migrate_app "Rust Cargo" "$HOME/.cargo" "$CSM_ROOT/dev/cargo"
    _csm_migrate_app "NPM Cache" "$HOME/.npm" "$CSM_ROOT/cache/npm"
end
