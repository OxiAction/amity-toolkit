![Amity Toolkit](curseforge/banner.png)

# Amity Toolkit

Quality-of-life modules for **World of Warcraft: Forever** (Interface 16001), bundled in one addon.

| Module              | What it does |
| ------------------- | ------------ |
| Bar Text            | Always shows health / resource text as `100/200 50%`, `100/200` or `50%` on player, target and target-of-target |
| Auction Item Level  | Sortable iLvl column in the auction house browse results |
| LFG Role Filter     | Tank / Healer / DPS filter buttons in the LFG browse list |
| Overpower Alert - Warrior | Warriors only: Overpower icon with a 5s countdown after a dodge |

Everything is managed in one panel, opened with `/amity`, the minimap button or the addon compartment. It has a tab per module with an on/off switch, a description and the module's settings. The panel can be dragged anywhere and stays open until you close it. Switching a module on or off applies after a UI reload; the panel offers a button for it.

## Layout

```
Amity.toc            addon manifest
Core.lua             module registry, saved variables, /amity
Minimap.lua          minimap button
Panel.lua            the Amity panel: overview + one tab per module
Modules/             one file per module
Media/               in-game icons (generated)
curseforge/          logo, banner, description, setup checklist (not packaged)
tools/make_art.py    renders all artwork
tools/build.ps1      builds dist/Amity-<version>.zip
```

## Development

The repo root is the addon folder. Link it into the client as `Amity`:

```
mklink /J "G:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\Amity" "G:\development\repos\amity-toolkit-wow"
```

Adding a module: create `Modules/<Name>.lua`, call `Amity:RegisterModule(key, { title, notes, description, defaults })`, implement `M:Init(db)`, and list the file in `Amity.toc`. Its tab appears in the panel on its own.

Settings are described as data in `M.options`; the panel builds the controls:

```lua
M.options = {
	{ type = "toggle", key = "sound", label = "Play a sound" },
	{ type = "range",  key = "size",  label = "Font size", min = 6, max = 20 },
	{ type = "select", key = "mode",  label = "Mode", values = { { "a", "First" }, { "b", "Second" } } },
	{ type = "button", label = "Test", onClick = function(module) ... end },
}

function M:OnOptionChanged(key) -- apply the new setting
end
```

`M:Unavailable()` can return a reason (e.g. "Warriors only") to grey out the settings. The full format is documented at the top of `Core.lua`. Modules have no slash commands of their own; `/amity` only opens the panel.

Releases: see [curseforge/SETUP.md](curseforge/SETUP.md).
