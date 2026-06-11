# One For All — Changelog

## [v1.3.8](https://www.curseforge.com/wow/addons/one-for-all-midnight-updated) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Fix: Excluded LibDBIcon buttons position persistence
- Fixed excluded LibDBIcon buttons (e.g. AlterEgo, BugSack) spawning outside
  the minimap circumference after reload or relog. Root cause: the addon was
  saving raw absolute screen coordinates (`BOTTOMLEFT / UIParent`) for all
  excluded buttons, including LibDBIcon-managed ones. Those coordinates are
  session-dependent and meaningless across reloads.
- LibDBIcon buttons now rely exclusively on `LibDBIcon:Refresh()` and their
  saved `minimapPos` angle to restore position on the minimap circumference.
  Raw pixel coordinates are only saved for non-LibDBIcon (anonymous) buttons.
- Position locking (`OFA_PositionLocked`) is no longer applied to LibDBIcon
  buttons at login — LibDBIcon handles their placement natively.
- `PLAYER_ENTERING_WORLD` now dispatches LibDBIcon buttons via `Refresh()` and
  anonymous buttons via `SetPoint()` independently, preventing cross-contamination
  between the two positioning systems.

## [v1.3.7](https://www.curseforge.com/wow/addons/one-for-all-midnight-updated) — June 7, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### WoW 12.0.5 / 12.0.7 (Midnight) Compatibility
- Updated TOC interface numbers: added `120005` (12.0.5) and `120007` (12.0.7),
  keeping full backward compatibility with 12.0.1, Vanilla, TBC, WotLK,
  Cata Classic, and MoP Classic
- Fixed `RegisterCallback` call syntax (`:` → `.`) that caused a crash on login
- Fixed `IsObjectType` check — WoW 12.x is case-sensitive; `"button"` → `"Button"`
- Fixed `GetPoint()` to use explicit index `GetPoint(1)` with fallback, avoiding
  nil returns on certain frames in 12.x
- Wrapped `GetNormalTexture`, `GetTexture`, and `IsMovable` in `pcall` — direct
  method-value access generates `LUA_WARNING` in Midnight's restricted API and
  caused the addon to fail loading entirely

### Anonymous Button Support (e.g. Mount Route Planner)
- Addon buttons created with no name (`CreateFrame("Button", nil, Minimap)`)
  are now fully supported. A **stable fingerprint** is generated from
  `GetDebugName()` + texture + dimensions — e.g. `OFA_fp_Minimap__28x28` for
  MRP — which remains consistent across sessions and client versions.
  Previously WoW 12.x returned a numeric FileData ID from `GetTexture()` that
  changed every session, making persistence impossible
- Detection now also accepts buttons using `IsMovable()` / `StartMoving()` as
  their drag mechanism, instead of requiring `OnDragStart` script (MRP uses
  `StartMoving()` / `StopMovingOrSizing()`)

### Position Persistence for Excluded Buttons
- Excluded buttons (dragged outside the OneForAll group) now remember their
  position across reloads and full relogs via a new `savedPositions` SavedVariable
- On login, `SetPoint` and `ClearAllPoints` are locked on excluded buttons
  immediately, preventing the addon's own initialization code from overwriting
  the saved position. The correct position is then applied at
  `PLAYER_ENTERING_WORLD`, after all addons have finished their setup

### Multi-row Layout
- Icons now wrap into multiple rows (default: 12 per row, configurable via
  `BUTTONS_PER_ROW`) — prevents icons from going off-screen with large numbers
  of addons

### Other Fixes
- `LibDBIcon:Refresh()` is now used when restoring position for LibDBIcon-managed
  buttons, instead of raw pixel coordinates that break after a reload
- Improved handling of multiple SavedVariables db structures
  (`button.db.minimapPos`, `button.db.minimap.minimapPos`, `button.minimapPos`)
- Added nil guards throughout to prevent silent Lua errors

---

## [v1.2.6](https://github.com/thoreex/OneForAll/tree/v1.2.6) — February 25, 2026
*by Thoreex*

- Version bump
