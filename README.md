# CachyOS Storage Manager

![Version](https://img.shields.io/badge/version-1.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/shell-fish-4aae47)

Unified storage manager for CachyOS and Arch Linux: move Flatpak data, pacman cache, paru cache, and user cache to another drive — with config-based migration instead of fragile symlinks.

**New to CSM?** Read [docs/tutorial.md](docs/tutorial.md) first — it walks through first-time setup, daily use, and recovery.

## Planned Modules

Module | Handles | Status
---|---|---
`flatpak` | `~/.var/app`, `/var/lib/flatpak` | ✅ v0.2.0
`paru` | `~/.cache/paru/clone` | ✅ v0.3.0
`pacman` | `/var/cache/pacman/pkg` | ✅ v0.6.1
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
  3. Copy an example config to `~/.config/cachyos-storage-manager/config.fish`.
  4. Install and enable the Flatpak watcher user service.

Then run the interactive wizard:

    csm setup

This will ask for the target drive and generate a proper config with the
following structure on your target drive:

    <target>/CachyOS-Storage-Data-Migration/
      ├── Flatpak/
      │   ├── Flatpak Core/   (installation, see below)
      │   └── Flatpak Data/   (user data)
      ├── paru/
      ├── pacman/             (reserved)
      └── data cache/         (reserved)

The Flatpak **core** (application binaries, runtime, repo) is a separate
Flatpak installation, registered in `/etc/flatpak/installations.d/`.
By default `csm setup` does not move it — it only creates the folder
placeholder. See the tutorial for moving it manually.

## Commands

    csm setup                    First-time setup wizard
    csm relocate <path>          Move all data to a new target drive
    csm edit [show|open|validate] Show, edit, or validate the config
    csm status                   Overall status
    csm doctor                   Check dependencies and service health
    csm version                  Show version
    csm help                     Show help

### Flatpak module

    csm flatpak status           Show installations, apps, disk usage
    csm flatpak migrate          Move ~/.var/app data to target drive
    csm flatpak migrate-core     Move /var/lib/flatpak apps to custom installation
    csm flatpak cleanup          Remove unused refs from default installation
    csm flatpak watch            Run the watcher in foreground

### Paru module

    csm paru status              Show symlink state and disk usage
    csm paru migrate             Move ~/.cache/paru/clone to target and symlink
    csm paru revert              Undo migration (for uninstall)

### Pacman module

    csm pacman status            Show both caches + /etc/pacman.conf state
    csm pacman migrate           Copy cache to target and add CacheDir
    csm pacman cleanup-old       Delete old .pkg.tar.zst* from source
    csm pacman revert            Remove CacheDir and optionally move data back

## Flatpak Watcher

The Flatpak module ships a user-level systemd service that watches
`~/.var/app` and `/var/lib/flatpak` and automatically migrates new
Flatpak data to the target drive.

Enable it:

    systemctl --user enable --now csm-flatpak-watcher.service

Check it:

    systemctl --user status csm-flatpak-watcher.service
    journalctl --user -u csm-flatpak-watcher.service -f

`csm setup` will enable it automatically. When `csm relocate` runs, the
watcher is stopped, the data is moved, the config is updated, and the
watcher is restarted.

## Configuration

Config file: `~/.config/cachyos-storage-manager/config.fish`
Edit with: `csm edit open`

Variable | Default | Description
---|---|---
`CSM_TARGET` | `/mnt/DataCachyOS` | Drive where CSM data lives.
`CSM_ROOT` | `$CSM_TARGET/CachyOS-Storage-Data-Migration` | Base folder on the target drive.
`CSM_FLATPAK_DIR` | `$CSM_ROOT/flatpak` | Flatpak user data location.
`CSM_FLATPAK_CORE_DIR` | `$CSM_ROOT/flatpak/system` | Flatpak installation path (reserved; `csm setup` only creates the folder).
`CSM_FLATPAK_INSTALLATION` | `datacachyos` | Custom Flatpak installation name. Find with `flatpak --installations`.
`CSM_FLATPAK_WATCH` | `1` | Enable the Flatpak watcher service.
`CSM_PARU_DIR` | `$CSM_ROOT/paru` | Paru clone target (symlinked from `~/.cache/paru/clone`).
`CSM_PACMAN_DIR` | `$CSM_ROOT/pacman` | Pacman cache location (reserved).
`CSM_CACHE_DIR` | `$CSM_ROOT/data cache` | User cache target (reserved).
`CSM_BACKUP_BEFORE_MIGRATE` | `1` | Create a backup before migrating.

Older configs that still use compatibility aliases like `CSM_FLATPAK_DATA_DIR`
or `CSM_PARU_CLONE_DIR` are still accepted during normalization.

## Design Principles

  1. **Config-based, not symlink-based** where possible.
  2. **Idempotent** — safe to run repeatedly.
  3. **Confirm before destructive actions.**
  4. **Detect mount** — abort if the target drive is not mounted.
  5. **Never touch** `/usr`, `/etc`, or installed packages.

## Documentation

- [docs/tutorial.md](docs/tutorial.md) — step-by-step tutorial
- [CHANGELOG.md](CHANGELOG.md) — version history

## License

MIT License — see LICENSE.
### Cache Module (`csm cache`)
Safe, granular cache management using Whitelist-First + Pre-flight safety checks.

```bash
csm cache status    # Scan ~/.cache items, size, and classification
csm cache migrate   # Safely migrate whitelisted cache items to target drive
csm cache revert    # Restore migrated cache items back to ~/.cache
```

### Steam & Gaming Module (`csm steam`)
Manages Proton Wine prefixes (`compatdata`), Vulkan shader caches, and orphan prefixes from uninstalled games.

```bash
csm steam status           # Scan Steam compatdata & shadercache sizes and status
csm steam migrate          # Migrate compatdata & shadercache to secondary drive
csm steam revert           # Restore migrated Steam components back to main drive
csm steam clean-orphans    # Scan for leftover Proton prefixes of uninstalled games
```
