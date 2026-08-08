# Changelog

All notable changes to PowerStats are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-08-09

### Added

- Initial public release of **PowerStats** (Retail).
- Compact text-only character stats panel (up to 6 stats at once).
- Layout modes: one stat per row, or a single horizontal row.
- Colored stat labels with configurable colors via the in-game config panel.
- Built-in lock control: while locked, the options gear is hidden and the lock button sits on the right edge; unlocking restores gear + lock side by side.
- Combat-aware display: when Blizzard marks combat stats as secret values (Midnight / 12.0+), the panel keeps the last readable numbers instead of inventing zeros.

### Notes

- Compatible with Retail interface `120007` (12.0.7) and `120100` (12.1.0).
- Brand icon: `icon.png` in the addon root.
