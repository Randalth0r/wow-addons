# IncBGS — Changelog

## [v1.0.6](https://www.curseforge.com/wow/addons/incbgs) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Fix
- Removed `RegisterStateDriver`, which was overriding manual show/hide.
  Bar visibility on BG enter/leave now uses a recursive `C_Timer.After`
  that polls `InCombatLockdown()` every second until it is safe to act.

---

## [v1.0.5](https://www.curseforge.com/wow/addons/incbgs) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Fix
- Fixed `ADDON_ACTION_BLOCKED` on `Bar:Show()` triggered by the minimap icon
  click and slash command during combat. All manual show/hide calls now go
  through `SafeToggleBar()`, which checks `InCombatLockdown()` first and prints
  a friendly message if the action cannot be performed during combat.

---

## [v1.0.4](https://www.curseforge.com/wow/addons/incbgs) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Fix
- Replaced manual `Bar:Show()`/`Bar:Hide()` logic with `RegisterStateDriver`
  — the Blizzard-native secure mechanism for frame visibility. The bar now
  shows/hides based on instance type without any Lua-side visibility calls,
  eliminating `ADDON_ACTION_BLOCKED` errors in combat.

---

## [v1.0.2](https://www.curseforge.com/wow/addons/incbgs) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Fix
- Addressed `ADDON_ACTION_BLOCKED` on `IncBGSBar:Show()` more robustly: the
  `C_Timer.After` workaround from v1.0.1 proved insufficient because WoW 12.x
  taints any addon frame shown/hidden from Lua during combat events. Moved to
  `RegisterStateDriver` for secure, taint-free visibility control.

---

## [v1.0.1](https://www.curseforge.com/wow/addons/incbgs) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Fix
- Fixed `ADDON_ACTION_BLOCKED` error on `IncBGSBar:Show()` triggered by
  `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED` events. Bar show/hide is now
  deferred by one tick via `C_Timer.After(0, ...)` to exit the protected
  execution context before calling frame visibility functions.

---

## [v1.0.0](https://www.curseforge.com/wow/addons/incbgs) — June 11, 2026
*By [Randalthor](https://www.curseforge.com/members/randalthor)*

### Initial Release
- Quick Incoming report bar for Battlegrounds, compatible with WoW 12.x (12.0.5)
- 8 one-click buttons: Incoming 1/2/3/4/5/5+, Help, Clear — each automatically
  appends the current sub-zone name to the message
- Fully compatible with WoW 12.x chat restrictions — messages are delivered
  reliably to instance chat without triggering Blizzard's API protection
- Minimap icon via LibDBIcon (uses the instance already loaded by other addons,
  never bundles its own copy)
- Bar draggable by holding the lock button
- H/V layout toggle button integrated in the bar
- Auto show/hide on BG enter/leave
- Optional Raid Warning echo (`/incbgs raidwarn`)
- Saved position and settings across sessions

### Commands
- `/incbgs` — show/hide bar
- `/incbgs horiz` — toggle horizontal/vertical layout
- `/incbgs raidwarn` — toggle raid warning echo
- `/incbgs reset` — move bar to screen center
- `/incbgs minimap` — show/hide minimap icon
