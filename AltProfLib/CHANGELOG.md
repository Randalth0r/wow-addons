# Changelog

All notable changes to AltProfLib are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-08-09

### Fixed

- Craft Reply / item lookup now indexes all crafting-quality item IDs for a recipe
  (Q1/Q2/Q3), so whispers linking a higher-quality reagent like Arcanoweave Spellthread
  resolve to the same crafter as the base recipe output

## [1.0.0] - 2026-08-09

### Added

- Account-wide profession roster scanning across characters
- Recipe learning scan when profession windows are opened
- Indexed lookups for profession owners, recipe owners, and crafted items
- Tooltip decoration showing which alts know a recipe or can craft an item
- Craft Reply panel for preparing and sending craft offers
- Recent Targets list with class, level, and timestamp enrichment via Who
- Share Crafter button to post the selected crafter name to chat
- English and Italian locale packs for Craft Reply UI strings
- Public API helpers for other addons to query roster data
- Slash command suite under `/apl` and `/altproflib`

### Changed

- Release channel set to stable
- Addon list icon uses a local PNG asset
- Publication metadata and documentation refreshed for CurseForge / GitHub

### Removed

- Internal beta self-test module

## [Unreleased]
