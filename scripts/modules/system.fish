# Module: System & Aesthetics Data Migration for CSM

function csm_system_migrate
    if test -z "$CSM_ROOT"
        return 1
    end

    echo "========================================"
    echo "  Migrating System & Aesthetics Data"
    echo "========================================"

    _csm_migrate_app "Desktop Icon Themes" "$HOME/.local/share/icons" "$CSM_ROOT/system/icons"
end
