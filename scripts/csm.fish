#!/usr/bin/env fish

# ============================================================
# CachyOS Storage Manager - Core CLI
#
# File ini adalah inti CLI: hanya berisi dispatcher dan help.
# Semua helper (config, logging, validasi) ada di modules/common.fish,
# semua modul fitur ada di modules/*.fish.
#
# Di-source pertama kali oleh build/csm, sebelum modules/.
# ============================================================

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------

function csm_usage
    echo "CachyOS Storage Manager v"(csm_version)
    echo ""
    echo "Usage:"
    echo "  csm                       Tampilkan help ini"
    echo "  csm setup                 Wizard setup pertama kali"
    echo "  csm status                Ringkasan pemakaian storage per kategori"
    echo "  csm doctor                Cek dependensi & kesehatan servis"
    echo "  csm restore               Kembalikan data yang didukung ke drive lokal"
    echo "  csm version               Tampilkan versi"
    echo ""
    echo "Modules:"
    echo "  csm flatpak  [status|migrate|migrate-core|core-status|relocate-core|cleanup|watch]"
    echo "  csm steam    [status|migrate|revert|clean-orphans]"
    echo "  csm cache    [status|migrate|revert]"
    echo "  csm pacman   [status|migrate|cleanup-old|revert]"
    echo "  csm paru     [status|migrate|revert]"
    echo "  csm apps     [status|migrate]"
    echo "  csm dev      [status|migrate]"
    echo "  csm system   [status|migrate]"
    echo "  csm scan     [--list]             Pindai & tawarkan migrasi interaktif"
    echo ""
    echo "Config:"
    echo "  csm edit [show|open|validate]   Lihat / sunting / validasi config"
    echo "  csm relocate <path>             Pindah seluruh data ke drive lain"
    echo ""
    echo "Jalankan 'csm <module>' tanpa subperintah untuk melihat status modul."
    echo "Setiap modul juga menerima 'help', mis. 'csm flatpak help'."
end

# ------------------------------------------------------------
# Generic module dispatcher
# ------------------------------------------------------------

# Terjemahkan subperintah CLI menjadi nama fungsi.
#   csm steam clean-orphans -> csm_steam_clean_orphans
#   csm flatpak core-status -> csm_flatpak_core_status
#   csm cache help          -> csm_cache_help
#
# Argumen: <prefix> <default-subcommand> [args...]
function csm_dispatch
    set -l prefix $argv[1]
    set -l default_sub $argv[2]
    set -l args $argv[3..-1]

    if test (count $args) -eq 0
        set args $default_sub
    end

    set -l sub $args[1]
    set -l rest $args[2..-1]

    set -l fn "csm_"$prefix"_"(string replace -a -- '-' '_' $sub)

    switch "$sub"
        case help -h --help
            set fn "csm_"$prefix"_help"
    end

    if functions -q $fn
        $fn $rest
        return $status
    end

    csm_error "Unknown $prefix subcommand: $sub"
    set -l help_fn "csm_"$prefix"_help"
    if functions -q $help_fn
        echo ""
        $help_fn
    end
    return 1
end

# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------

function csm_main
    csm_load_config

    if test (count $argv) -eq 0
        csm_usage
        return 0
    end

    set -l cmd $argv[1]
    set -l rest $argv[2..-1]

    switch "$cmd"

        case -h --help help
            csm_usage

        case version --version -V
            echo "CachyOS Storage Manager v"(csm_version)

        case setup
            csm_setup $rest

        case relocate
            csm_relocate $rest

        case edit config
            csm_edit $rest

        case status analyze info
            csm_analyze $rest

        case doctor
            csm_doctor $rest

        case restore
            csm_restore $rest

        case steam
            csm_dispatch steam status $rest

        case flatpak
            csm_dispatch flatpak status $rest

        case cache
            csm_dispatch cache status $rest

        case pacman
            csm_dispatch pacman status $rest

        case paru
            csm_dispatch paru status $rest

        case apps
            csm_dispatch apps status $rest

        case dev
            csm_dispatch dev status $rest

        case system
            csm_dispatch system status $rest

        case scan
            csm_scan $rest

        case '*'
            csm_error "Unknown command: $cmd"
            echo ""
            csm_usage
            return 1
    end
end
