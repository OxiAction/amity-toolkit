![Amity Toolkit](https://raw.githubusercontent.com/OxiAction/amity-toolkit/main/curseforge/banner.png)

# Amity Toolkit – a growing quality-of-life toolkit for WoW Forever

**Amity Toolkit** is a lightweight, modular addon for **World of Warcraft: Forever**. Each module fixes one everyday annoyance, and all of them come in one tidy package with one place to manage them.

Every feature is a **module**. Turn on what you want and leave the rest off. Modules you switch off stay completely inactive: they don't register events or hook anything. You manage everything from one panel that opens from the **minimap button** or with `/amity`.

> **This is just the beginning.** Amity Toolkit keeps growing. New modules will be added over time, so features keep arriving without you having to install, update and manage a pile of separate addons. Ideas and requests are welcome!

---

## ✨ Current modules

### 🩸 Bar Text
Stop hovering over your unit frames to see numbers. Bar Text **always shows health and resource values** on your:

- **Player** frame
- **Target** frame
- **Target-of-target** frame, which normally has no text at all

Pick the format you like: **`100/200 50%`** (current / maximum and percent, the default), **`100/200`** or **`50%`**.

- Adjustable font size for player/target and for the small target-of-target bars

---

### 💰 Auction Item Level
Shopping for gear in the auction house without seeing item levels is painful. This module adds an **iLvl column** to the browse results:

- **Click the header to sort by item level** (highest first); click again to reverse
- Numbers are colored by item quality, like Blizzard's own lists
- On weapons and armor it sits next to Blizzard's required-level column, so you see both

---

### 🛡️ LFG Role Filter
Find the right group or player faster. Adds **Tank / Healer / DPS** toggle buttons to the Looking For Group browse list:

- **Solo players** are matched by the roles they can fill
- **Groups** are matched by the roles they **still need**, or by the roles they **already have**
- Select several roles to see anyone matching any of them
- A small counter shows how many results match out of the total
- Your own listing is always shown

---

### ⚔️ Overpower Alert - Warrior
Never miss an Overpower window again. When your target **dodges**, a large Overpower icon appears with a **5-second countdown**:

- Movable: unlock it in the panel and drag it wherever you like
- A test button shows the alert so you can check how it looks
- Pick an alert sound from a list (or none); each one plays when you pick it
- Disappears automatically when you use Overpower or leave combat
- **Warriors only**: on other classes the module stays completely inactive

---

## 🧭 The Amity panel

One place for everything, no chat commands to remember:

- Open it with the **minimap button**, **`/amity`** or the **addon compartment** menu
- An **overview** of all modules, plus a **tab for each module** with its on/off switch, a description and all of its settings
- **Drag** the panel anywhere; it stays open while you play, so you can watch your changes take effect, and closes with the X
- Switching a module on or off applies after a reload; the panel shows what will change and offers a **Reload UI** button
- **Drag** the minimap button around the minimap edge, or hide it from the overview

---

## 🔒 Built for WoW Forever

WoW Forever runs on the modern engine, which has strict rules for addons: secret unit values, taint protection and a restricted combat log. Amity Toolkit is written with those rules in mind:

- It never writes into Blizzard's frames, so it doesn't cause taint errors
- Health and power text is drawn on the addon's own overlays, using the APIs the game allows for secret values
- No combat log access; Overpower Alert uses spell usability events instead
- Each module is isolated: if one fails, the others keep working

---

## 🚀 What's next?

Amity Toolkit is meant to grow. More quality-of-life modules are planned and will appear in future updates, each one optional and switchable from the same panel. Follow the project to get new features as they land.

Have an idea for a module, or found a bug?
👉 **[github.com/OxiAction/amity-toolkit](https://github.com/OxiAction/amity-toolkit/issues)**
