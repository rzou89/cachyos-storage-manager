# CachyOS Storage Manager

![Version](https://img.shields.io/badge/version-1.1.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/shell-fish-4aae47)

Unified storage manager for CachyOS and Arch Linux: move Flatpak data, pacman cache, paru cache, and user cache to another drive — with config-based migration instead of fragile symlinks.

**New to CSM?** Read [docs/tutorial.md](docs/tutorial.md) first — it walks through first-time setup, daily use, and recovery.

## Modules

Module | What it manages | Commands
---|---|---
`flatpak` | Flatpak user data, system installation, and watcher | `csm flatpak ...`
`steam` | Proton compatdata, shader caches, orphan prefixes | `csm steam ...`
`cache` | Selected folders under `~/.cache` | `csm cache status`, `csm cache migrate`
Setup migrations | App data, development tools, system data, paru, and pacman | `csm setup`

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

This configures a root folder on the target drive. Active modules create their
data under the following shared layout as needed:

    <target>/CachyOS-Storage-Data-Migration/
    ├── apps/               (launchers and Wine prefixes)
    ├── cache/              (user, paru, and pacman caches)
    ├── dev/                (development tools and data)
    ├── flatpak/            (user data and optional system installation)
    ├── shader-cache/
    └── system/

Steam Wine prefixes use `apps/wine-prefixes` by default. Shader caches use
`shader-cache/`.

The Flatpak **core** (application binaries, runtime, repo) is a separate
Flatpak installation, registered in `/etc/flatpak/installations.d/`.
By default `csm setup` does not move it — it only creates the folder
placeholder. See the tutorial for moving it manually.

## Commands

    csm setup                    First-time setup wizard
    csm status                   Overall status
    csm doctor                   Check dependencies and service health
    csm analyze                  Show storage usage by category
    csm restore                  Restore supported data to the local drive
    csm version                  Show version

### Flatpak module

    csm flatpak status           Show installations, apps, disk usage
    csm flatpak migrate          Move ~/.var/app data to target drive
    csm flatpak migrate-core     Move /var/lib/flatpak apps to custom installation
    csm flatpak cleanup          Remove unused refs from default installation
    csm flatpak watch            Run the watcher in foreground

## Flatpak Watcher

The Flatpak module ships a user-level systemd service that watches
`~/.var/app` and `/var/lib/flatpak` and automatically migrates new
Flatpak data to the target drive.

Enable it:

    systemctl --user enable --now csm-flatpak-watcher.service

Check it:

    systemctl --user status csm-flatpak-watcher.service
    journalctl --user -u csm-flatpak-watcher.service -f

`csm setup` enables it automatically when watching is enabled in the config.

## Configuration

Config file: `~/.config/cachyos-storage-manager/config.fish`
Open it directly with your preferred text editor.

Variable | Default | Description
---|---|---
`CSM_TARGET` | `/mnt/DataCachyOS` | Drive where CSM data lives.
`CSM_ROOT` | `$CSM_TARGET/CachyOS-Storage-Data-Migration` | Base folder on the target drive.
`CSM_FLATPAK_DIR` | `$CSM_ROOT/flatpak/flatpak-data` | Flatpak user data location.
`CSM_FLATPAK_CORE_DIR` | `$CSM_ROOT/flatpak/flatpak-core/system` | Flatpak system installation path.
`CSM_FLATPAK_INSTALLATION` | `datacachyos` | Custom Flatpak installation name. Find with `flatpak --installations`.
`CSM_FLATPAK_WATCH` | `1` | Enable the Flatpak watcher service.
`CSM_PARU_DIR` | `$CSM_ROOT/cache/paru` | Paru clone target (symlinked from `~/.cache/paru/clone`).
`CSM_PACMAN_DIR` | `$CSM_ROOT/cache/pacman` | Pacman cache location.
`CSM_CACHE_DIR` | `$CSM_ROOT/cache` | User cache target.
`CSM_WINEPREFIX_DIR` | `$CSM_ROOT/apps/wine-prefixes` | Steam Proton compatdata target.
`CSM_SHADERCACHE_DIR` | `$CSM_ROOT/shader-cache` | Steam shader cache target.
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
