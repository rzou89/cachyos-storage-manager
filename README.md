# CachyOS Storage Manager

Unified storage manager for CachyOS and Arch Linux: move Flatpak data,
pacman cache, paru cache, and user cache to another drive — with config-based
migration instead of fragile symlinks.

**Status: early development.** Only the foundation (CLI, config, setup) is
implemented. Modules are being added incrementally.

## Planned Modules

| Module | Handles | Status |
|--------|---------|--------|
| `flatpak` | `~/.var/app`, `/var/lib/flatpak` | 🔜 planned |
| `pacman` | `/var/cache/pacman/pkg` | 🔜 planned |
| `paru` | `~/.cache/paru/clone` | 🔜 planned |
| `cache` | `~/.cache` (whitelist + blacklist) | 🔜 planned |

## Requirements

- Linux (CachyOS or Arch-based)
- Fish shell
- Flatpak, pacman, paru (only for the modules that use them)

## Installation

```fish
git clone git@github.com:rzou89/cachyos-storage-manager.git
cd cachyos-storage-manager
./setup.fish
```

The installer will:

1. Copy the `csm` entry point to `~/.local/bin/csm`.
2. Copy helper scripts to `~/.local/share/cachyos-storage-manager/`.
3. Copy the example config to `~/.config/cachyos-storage-manager/config.fish`.

Then edit the config:

```fish
$EDITOR ~/.config/cachyos-storage-manager/config.fish
```

Set `CSM_TARGET` to the directory on your target drive, for example:

```fish
set -g CSM_TARGET "/mnt/DataCachyOS"
```

## Uninstall

```fish
./uninstall.fish
```

Your data on the target drive is **not** deleted.

## Usage

```fish
csm help            # show help
csm version         # show version
csm status          # show overall status
csm doctor          # check system health
```

Modules (e.g. `csm flatpak migrate`) are not implemented yet. See the roadmap.

## Configuration

Config file: `~/.config/cachyos-storage-manager/config.fish`

| Variable | Default | Description |
|----------|---------|-------------|
| `CSM_TARGET` | `/mnt/DataCachyOS` | Base directory on the target drive. |
| `CSM_BACKUP_BEFORE_MIGRATE` | `1` | Create a backup before migrating. |
| `CSM_FLATPAK_DATA_DIR` | `$CSM_TARGET/Flatpak Data` | Flatpak user data location. |
| `CSM_FLATPAK_INSTALLATION` | `cachyos` | Name of the custom Flatpak installation. |
| `CSM_FLATPAK_WATCH` | `1` | Enable the Flatpak data watcher. |
| `CSM_PACMAN_CACHE_DIR` | `$CSM_TARGET/pacman/pkg` | Pacman cache location. |
| `CSM_PARU_CLONE_DIR` | `$CSM_TARGET/paru/clone` | Paru clone location. |
| `CSM_CACHE_TARGET` | `$CSM_TARGET/cache` | User cache target (reserved). |

## Design Principles

1. **Config-based, not symlink-based** where possible.
2. **Idempotent** — safe to run repeatedly.
3. **Confirm before destructive actions.**
4. **Detect mount** — abort if the target drive is not mounted.
5. **Never touch** `/usr`, `/etc`, or installed packages.

## License

MIT License — see [LICENSE](LICENSE).