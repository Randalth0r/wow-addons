# PowerStats

**Your Stats. Alive.**

*By [Randalthor](https://www.curseforge.com/members/randalthor)*

PowerStats is a lightweight World of Warcraft **Retail** addon that shows a small, draggable text panel of live character statistics.

## Features

- Up to **6** stats on screen at once
- Two layouts: **one per row** or **single row**
- Colored stat names (customizable)
- Lock / unlock the panel (locked mode hides the options gear and keeps only the lock on the right)
- Right-click the panel (or use `/ps config`) to choose stats
- Combat-friendly: when Blizzard secret-value restrictions apply, the panel holds the last safe readings

## Requirements

| Client | Interface |
|--------|-----------|
| Retail 12.0.7 | `120007` |
| Retail 12.1.0 | `120100` |

## Install

1. Copy the `PowerStats` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. Restart the client or `/reload`.
3. Enable **PowerStats** in the AddOns list.

## Slash commands

| Command | Action |
|---------|--------|
| `/ps` or `/powerstats` | Show / hide the panel |
| `/ps config` | Open the stat selection panel |
| `/ps row` / `/ps column` | Switch layout |
| `/ps lock` | Lock / unlock movement |
| `/ps scale N` | Set scale (`0.5`–`2.5`) |
| `/ps <key>` | Toggle a stat (example: `/ps haste`) |
| `/ps reset` | Restore defaults |

## Configuration

- **Gear icon** — open the config panel (hidden while locked)
- **Lock icon** — lock or unlock the panel
- **Right-click** the panel — toggle config
- In config: pick up to 6 stats and click the color swatches to recolor labels

## Saved variables

`PowerStatsDB`

## Version

Current release: **1.0.0** — see [CHANGELOG.md](CHANGELOG.md).

## Links

- Author: [Randalthor](https://www.curseforge.com/members/randalthor)
- GitHub (wow-addons monorepo): https://github.com/Randalth0r/wow-addons
- CurseForge: https://www.curseforge.com/members/randalthor

## License

Not specified yet. Contact the author if you need redistribution terms.
