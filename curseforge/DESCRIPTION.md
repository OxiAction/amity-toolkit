![Amity](https://raw.githubusercontent.com/OxiAction/amity-wow-addon/main/curseforge/banner.png)

**Amity** is a small collection of quality-of-life tweaks for **World of Warcraft: Forever**. Each feature is a module you can switch on or off from the minimap button. Modules you don't use stay completely inactive.

## Modules

### Bar Text
Health and resource text is always visible on your **player**, **target** and **target-of-target** frames, formatted as `100/200 50%`, so you don't have to hover. Font sizes are adjustable, and the original Blizzard "Status Text" format is still available.
`/abt` for options.

### Auction Item Level
Adds an **iLvl** column to the auction house browse results. Click the header to sort by item level, click again to reverse. On weapons and armor it appears next to Blizzard's required-level column.
`/ail all on` also shows item level for non-equipment.

### LFG Role Filter
Adds **Tank / Healer / DPS** toggle buttons to the Looking For Group browse list. Solo players are matched by the roles they can fill. Groups are matched by the roles they still need, or by the roles they already have with `/lfgrf mode has`. Your own listing is always shown.

### Overpower Alert *(warriors)*
Shows a movable Overpower icon with a 5 second countdown when your target dodges, plus an optional sound.
`/opa test` to move the icon, `/opa lock` when done.

## Usage

- **Minimap button:** click it to open the modules panel. Drag it to move it around the minimap.
- `/amity` opens the panel. `/amity help` lists every command.
- Switching a module on or off needs a UI reload. The panel shows a **Reload UI** button when needed.

## Notes

- Built for the WoW Forever client (Interface 16001) and its secret-value and combat-log rules: no taint of Blizzard frames, no combat log access.
- If you used the standalone addons AlwaysBarText, AuctionItemLevel, LFGRoleFilter or OverpowerAlert, remove them. Amity contains all of them and warns you if one is still enabled.

Source and issues: [github.com/OxiAction/amity-wow-addon](https://github.com/OxiAction/amity-wow-addon)
