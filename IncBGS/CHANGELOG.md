# IncBGS — Changelog

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
