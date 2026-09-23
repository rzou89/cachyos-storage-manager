# Module: Cache Migration for CSM

function csm_cache_migrate
    # Pastikan CSM_ROOT terdefinisi dan tidak kosong
    if test -z "$CSM_ROOT"
        if test -f "$HOME/.config/cachyos-storage-manager/config.fish"
            source "$HOME/.config/cachyos-storage-manager/config.fish" 2>/dev/null
        end
    end

    if test -z "$CSM_ROOT"
        echo "[WARN] CSM_ROOT belum terkonfigurasi, melewati migrasi cache."
        return 0
    end

    echo "========================================"
    echo " Migrating Cache Items (Whitelist-First)"
    echo "========================================"

    set -l cache_target "$CSM_ROOT/cache"
    mkdir -p "$cache_target"

    # Migrasi item cache spesifik jika folder sumber ada
    if test -d "$HOME/.cache/mesa_shader_cache"
        _csm_migrate_app "mesa_shader_cache" "$HOME/.cache/mesa_shader_cache" "$CSM_ROOT/shader-cache/mesa_shader_cache"
    end
end
