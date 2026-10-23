![Amity Toolkit](https://raw.githubusercontent.com/OxiAction/amity-toolkit/main/curseforge/banner.png)

# Amity Toolkit – a growing quality-of-life toolkit for WoW Forever

**Amity Toolkit** is a lightweight, modular addon for **World of Warcraft: Forever**. It started as a handful of small standalone addons that each fixed one annoyance. Those are now combined into one tidy package with one place to manage them.

Every feature is a **module**. Turn on what you want and leave the rest off. Modules you switch off stay completely inactive: they don't register events or hook anything. You manage everything from a small panel that opens from the **minimap button**.

> **This is just the beginning.** Amity Toolkit keeps growing. New modules will be added over time, so features keep arriving without you having to install, update and manage a pile of separate addons. Ideas and requests are welcome!

---

## ✨ Current modules

### 🩸 Bar Text
Stop hovering over your unit frames to see numbers. Bar Text **always shows health and resource values** on your:

- **Player** frame
- **Target** frame
- **Target-of-target** frame, which normally has no text at all

Values are shown in a compact, readable format: **`100/200 50%`** (current / maximum and percent).

- Adjustable font size for player/target and for the small target-of-target bars
- Optionally hide the maximum value on target-of-target (`cur pct%`)
- Prefer Blizzard's own format? Switch back to the game's *Status Text* setting at any time

Command: `/abt` (`main`, `percent`, `mainsize`, `tot`, `totsize`, `totmax`, `reset`)

---

### 💰 Auction Item Level
Shopping for gear in the auction house without seeing item levels is painful. This module adds an **iLvl column** to the browse results:

- **Click the header to sort by item level** (highest first); click again to reverse
- Numbers are colored by item quality, like Blizzard's own lists
- On weapons and armor it sits next to Blizzard's required-level column, so you see both
- Optionally show item levels for non-equipment too

Command: `/ail all on|off`

---

### 🛡️ LFG Role Filter
Find the right group or player faster. Adds **Tank / Healer / DPS** toggle buttons to the Looking For Group browse list:

- **Solo players** are matched by the roles they can fill
- **Groups** are matched by the roles they **still need**, or by the roles they **already have** with `/lfgrf mode has`
- Select several roles to see anyone matching any of them
- A small counter shows how many results match out of the total
- Your own listing is always shown

Commands: `/lfgrf tank|healer|dps`, `/lfgrf mode needs|has`, `/lfgrf clear`

---

### ⚔️ Overpower Alert *(Warrior)*
Never miss an Overpower window again. When your target **dodges**, a large Overpower icon appears with a **5-second countdown**:

- Movable: place it wherever you like
- Optional raid-warning sound
- Disappears automatically when you use Overpower or leave combat
- Only active for warriors; other classes are unaffected

Commands: `/opa test` (unlock and move), `/opa lock`, `/opa sound on|off`, `/opa reset`

---

## 🧭 The module panel

- **Click the minimap button** to open the module panel
- **Tick or untick** modules; the panel shows what changes after a reload
- Press **Reload UI** to apply your changes
- **Drag** the minimap button around the minimap edge to reposition it
- Hide or show the button with `/amity minimap`
- Also available through the **addon compartment** menu
- `/amity help` lists every module and command

---

## 🔒 Built for WoW Forever

WoW Forever runs on the modern engine, which has strict rules for addons: secret unit values, taint protection and a restricted combat log. Amity Toolkit is written with those rules in mind:

- It never writes into Blizzard's frames, so it doesn't cause taint errors
- Health and power text is drawn on the addon's own overlays, using the APIs the game allows for secret values
- No combat log access; Overpower Alert uses spell usability events instead
- Each module is isolated: if one fails, the others keep working

---

## 🔄 Upgrading from the standalone addons

If you used **AlwaysBarText**, **AuctionItemLevel**, **LFGRoleFilter** or **OverpowerAlert**, please **disable or delete them**. Amity Toolkit contains all of them, and it will warn you in chat if an old one is still enabled. (Settings from the old addons are not carried over.)

---

## 🚀 What's next?

Amity Toolkit is meant to grow. More quality-of-life modules are planned and will appear in future updates, each one optional and switchable from the same panel. Follow the project to get new features as they land.

Have an idea for a module, or found a bug?
👉 **[github.com/OxiAction/amity-toolkit](https://github.com/OxiAction/amity-toolkit/issues)**

Thanks for using Amity Toolkit! 💜
