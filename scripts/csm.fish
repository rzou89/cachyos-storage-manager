#!/usr/bin/env fish

set -g CSM_VERSION "0.7.0"
set -g CSM_SCRIPT_DIR (dirname (status filename))
set -g CSM_MODULES_DIR "$CSM_SCRIPT_DIR/modules"

if not test -d "$CSM_MODULES_DIR"
    set CSM_MODULES_DIR "$HOME/.local/share/cachyos-storage-manager/modules"
end

source $CSM_MODULES_DIR/common.fish
source $CSM_MODULES_DIR/init.fish
source $CSM_MODULES_DIR/flatpak-core.fish
source $CSM_MODULES_DIR/flatpak.fish
source $CSM_MODULES_DIR/pacman.fish
source $CSM_MODULES_DIR/paru.fish
source $CSM_MODULES_DIR/cache.fish

function csm_main
    if test (count $argv) -eq 0
        csm_help
        return 0
    end

    switch $argv[1]
        case version -v --version
            echo "csm $CSM_VERSION"
        case help -h --help
            csm_help
        case status
            csm_status
        case doctor
            csm_doctor
        case init
            csm_init
        case flatpak-core
            switch $argv[2]
                case migrate
                    csm_flatpak_core_migrate
                case revert
                    csm_flatpak_core_revert
                case status
                    csm_flatpak_core_status
                case '*'
                    echo "Usage: csm flatpak-core {migrate|revert|status|watch}"
            end
        case flatpak
            switch $argv[2]
                case migrate
                    csm_flatpak_migrate
                case revert
                    csm_flatpak_revert
                case status
                    csm_flatpak_status
                case watch
                    csm_flatpak_watch
                case '*'
                    echo "Usage: csm flatpak {migrate|revert|status|watch}"
            end
        case pacman
            switch $argv[2]
                case migrate
                    csm_pacman_migrate
                case revert
                    csm_pacman_revert
                case status
                    csm_pacman_status
                case '*'
                    echo "Usage: csm pacman {migrate|revert|status|watch}"
            end
        case cache
            switch $argv[2]
                case status
                    csm_cache_status
                case migrate
                    csm_cache_migrate
                case revert
                    csm_cache_revert
                case '*'
                    echo "Usage: csm cache {status|migrate|revert}"
            end
        case paru
            switch $argv[2]
                case migrate
                    csm_paru_migrate
                case revert
                    csm_paru_revert
                case status
                    csm_paru_status
                case '*'
                    echo "Usage: csm paru {migrate|revert|status|watch}"
            end
        case '*'
            echo "Unknown command: $argv[1]"
            echo "Run 'csm help' for available commands."
            return 1
    end
end

csm_main $argv