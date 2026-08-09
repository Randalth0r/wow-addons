# PowerStats

**Your Stats. Alive.**

By [Randalthor](https://www.curseforge.com/members/randalthor)

Small Retail panel that keeps a few of your character stats on screen while you play. Text only, nothing fancy — just the numbers you care about.

## What it does

- Show up to **6** stats
- Two layouts: **One per Row** or **Single Row**
- Color the labels however you like
- Lock the panel so it does not move (gear icon hides while locked)
- Toggle the background on/off
- Font size from 8 to 20 (fresh install starts at **11**)
- In Single Row, the box grows with the font so everything stays proportional
- **Move** works on ground mounts and while skyriding / dynamic flight
- In combat it holds the last safe values when Blizzard secrets the live ones

## Client

Works on Retail **12.0.7** (`120007`) and **12.1.0** (`120100`).

## Install

Drop the `PowerStats` folder into `World of Warcraft\_retail_\Interface\AddOns\`, restart or `/reload`, and enable it in the AddOns list.

## Commands

| Command | What it does |
|---------|--------------|
| `/ps` or `/powerstats` | Show / hide |
| `/ps config` | Open config |
| `/ps row` / `/ps column` | Switch layout |
| `/ps lock` | Lock / unlock |
| `/ps scale N` | Scale (`0.5`–`2.5`) |
| `/ps <key>` | Toggle a stat (e.g. `/ps haste`) |
| `/ps reset` | Back to defaults |

## In game

- Gear icon opens config (hidden while locked)
- Lock icon locks / unlocks
- Right-click the panel for config
- Config: pick stats, recolor swatches, BG, font size

## Saved variables

`PowerStatsDB`

## Version

**1.0.1** — see [CHANGELOG.md](CHANGELOG.md).

## Links

- CurseForge: https://www.curseforge.com/members/randalthor
- GitHub: https://github.com/Randalth0r/wow-addons
