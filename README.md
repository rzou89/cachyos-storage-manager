# CachyOS Storage Manager

![Version](https://img.shields.io/badge/version-0.2.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/shell-fish-4aae47)

Unified storage manager for CachyOS and Arch Linux: move Flatpak data, pacman cache, paru cache, and user cache to another drive — with config-based migration instead of fragile symlinks.

**Status: early development.** Foundation (CLI, config, setup) is complete. The Flatpak module is available as of v0.2.0. Other modules are being added incrementally.

## Planned Modules

Module | Handles | Status
---|---|---
`flatpak` | `~/.var/app`, `/var/lib/flatpak` | ✅ v0.2.0
`pacman` | `/var/cache/pacman/pkg` | 🔜 planned
`paru` | `~/.cache/paru/clone` | 🔜 planned
`cache` | `~/.cache` (whitelist + blacklist) | 🔜 planned

## Requirements

  * Linux (CachyOS or Arch-based)
  * Fish shell
  * Flatpak, pacman, paru (only for the modules that use them)
  * `inotify-tools` (for the Flatpak watcher)

## Installation

    git clone git@github.com:rzou89/cachyos-storage-manager.git
    cd cachyos-storage-manager
    ./setup.fish

The installer will:

  1. Copy the `csm` entry point to `~/.local/bin/csm`.
  2. Copy modules to `~/.local/share/cachyos-storage-manager/modules/`.
  3. Copy the example config to `~/.config/cachyos-storage-manager/config.fish`.
  4. Install and enable the Flatpak watcher user service (if `CSM_FLATPAK_WATCH=1`).

Then edit the config:

    $EDITOR ~/.config/cachyos-storage-manager/config.fish

Set `CSM_TARGET` to the directory on your target drive, for example:

    set -g CSM_TARGET "/mnt/DataCachyOS"

## Uninstall

    ./uninstall.fish

The uninstaller stops and removes the Flatpak watcher service.
Your data on the target drive is **not** deleted.

## Usage

    csm help                     # show help
    csm version                  # show version
    csm status                   # show overall status
    csm doctor                   # check system health

    csm flatpak status           # Flatpak installation status + disk usage
    csm flatpak migrate          # migrate ~/.var/app data to target drive
    csm flatpak migrate-core     # move /var/lib/flatpak apps to custom installation
    csm flatpak cleanup          # remove unused refs from default installation
    csm flatpak watch            # run the watcher in foreground

## Flatpak Watcher

The Flatpak module ships a user-level systemd service that watches
`~/.var/app` and `/var/lib/flatpak` and automatically migrates new
Flatpak data to the target drive.

Enable it:

    systemctl --user enable --now csm-flatpak-watcher.service

Check it:

    systemctl --user status csm-flatpak-watcher.service
    journalctl --user -u csm-flatpak-watcher.service -f

`setup.fish` will enable it automatically when `CSM_FLATPAK_WATCH` is `1`.

## Configuration

Config file: `~/.config/cachyos-storage-manager/config.fish`

Variable | Default | Description
---|---|---
`CSM_TARGET` | `/mnt/DataCachyOS` | Base directory on the target drive.
`CSM_BACKUP_BEFORE_MIGRATE` | `1` | Create a backup before migrating.
`CSM_FLATPAK_DATA_DIR` | `$CSM_TARGET/Flatpak Data` | Flatpak user data location.
`CSM_FLATPAK_INSTALLATION` | `datacachyos` | Name of the custom Flatpak installation.
`CSM_FLATPAK_WATCH` | `1` | Enable the Flatpak data watcher.
`CSM_PACMAN_CACHE_DIR` | `$CSM_TARGET/pacman/pkg` | Pacman cache location.
`CSM_PARU_CLONE_DIR` | `$CSM_TARGET/paru/clone` | Paru clone location.
`CSM_CACHE_TARGET` | `$CSM_TARGET/cache` | User cache target (reserved).

## Design Principles

  1. **Config-based, not symlink-based** where possible.
  2. **Idempotent** — safe to run repeatedly.
  3. **Confirm before destructive actions.**
  4. **Detect mount** — abort if the target drive is not mounted.
  5. **Never touch** `/usr`, `/etc`, or installed packages.

## License

MIT License — see LICENSE.
