# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-09-23

### Added

- `csm setup` — interactive first-time setup wizard
  - Validates the target drive (absolute, exists, mounted, writable)
  - Creates the `CachyOS Storage Data Migration/` structure
  - Generates a fresh config
  - Optionally migrates existing flatpak and paru data
  - Enables the Flatpak watcher service
- `csm relocate <path>` — move all CSM data to a new target drive
  - Stops the watcher during the move and restarts it afterwards
  - Backs up the current config
  - Moves every module's data and updates all symlinks
  - Asks before deleting the old data
- `csm edit [show|open|validate]` — inspect, edit, and validate the config
- `docs/tutorial.md` — step-by-step tutorial for non-programmers
- Backward compatibility for older configs (`CSM_FLATPAK_DATA_DIR`,
  `CSM_PARU_CLONE_DIR`, `CSM_PACMAN_CACHE_DIR`, `CSM_CACHE_TARGET`)

### Changed

- New on-disk layout: all module data now lives under
  `<target>/CachyOS Storage Data Migration/<module>/`
- New primary config variables: `CSM_ROOT`, `CSM_FLATPAK_DIR`,
  `CSM_PARU_DIR`, `CSM_PACMAN_DIR`, `CSM_CACHE_DIR`
- README rewritten to reflect the new commands and layout

## [0.3.0] - 2026-09-23

### Added

- Paru module: `csm paru status`, `migrate`, `revert`
- Symlink-based design: `~/.cache/paru/clone` -> `$CSM_PARU_DIR`
- Paru itself is not modified; symlink is transparent

## [0.2.0] - 2026-09-23

### Added

- Flatpak module: `csm flatpak migrate`, `migrate-core`, `cleanup`, `status`, `watch`
- Compatibility aliases for legacy flags (`--data`, `--migrate-core`, `--cleanup-core`, `--status`)
- systemd user service `csm-flatpak-watcher.service`
- `setup.fish` now installs modules to `~/.local/share/cachyos-storage-manager/modules/`
- `setup.fish` enables and starts the watcher service when `CSM_FLATPAK_WATCH=1`
- `uninstall.fish` stops and removes the watcher service
- `csm doctor` checks for `inotifywait` and reports watcher service status
- `csm status` reports Flatpak config values
- Version, license, and shell badges in README

### Fixed

- Install-layout bug: modules directory now resolves correctly when `csm` is
  installed to `~/.local/bin` (v0.1.0 only worked from the repo)
- `csm flatpak status` no longer prompts for a `sudo` password
- `config.fish.example` and README now use `datacachyos` as the default
  Flatpak installation name

## [0.1.0] - 2026-09-22

### Added

- Initial foundation: CLI entry point (`csm`), config loader, setup/uninstall scripts
- `csm version`, `csm help`, `csm status`, `csm doctor` commands
- Example config file