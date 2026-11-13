# Changelog

## [1.0.2] - 2026-11-13

Changes:

- **Overpower Alert** in Berserker Stance now also works in a group when no one else can be attacking your target: group members who are far away, out of range, dead, offline or on another target (and their pets) no longer block the alert.

## [1.0.1] - 2026-11-11

Changes:

- **Overpower Alert** now also works in Berserker Stance while you play solo: when your target dodges, the icon appears so you can switch to Battle Stance in time. It stays hidden while Overpower's cooldown would outlast the window, is tinted blue when the stance swap would leave too little rage (Tactical Mastery), and ends when you change target. In a group the game doesn't tell whose attack was dodged, so there it only works in Battle Stance.

## [1.0.0] - 2026-11-10

New modules:

- **Revenge Alert - Warrior**: movable Revenge icon with a 5 second countdown when you block, dodge or parry. Warriors only; inactive on other classes.
- **Chat Timestamps**: the time, e.g. `14:17`, in front of every chat message. Choose 24 or 12 hour format, with or without seconds, brackets and gray colour.
- **Battle Shout Alert - Warrior**: movable, flashing Battle Shout icon while the buff is not active or about to run out (30 seconds before by default, adjustable), with its own alert sound and an optional "only in combat" setting. Warriors only; inactive on other classes.
- **Auto Replace Enchant**: skips the "replace this enchant?" prompt and enchants right away, handy for levelling Enchanting. Off by default, because it can overwrite a good enchant without warning. Enchanting an item in the trade window still asks.

Changes:

- The Overpower and Revenge icons are moved separately. Each alert has its own tab in the panel with its own on/off switch, alert sound, and unlock, test and reset position buttons.
- The Overpower and Revenge icons also appear when you don't have the rage to use the spell, tinted blue until you do.
- Fixed the Overpower icon disappearing after its 5 seconds while the spell was still usable because the target dodged again. The countdown now starts over.
- The Looking For Group browse list now shows each player's current location next to the game type (the leader's location for groups). Always on, no settings.

## [0.1.0-beta] - 2026-10-23

First beta of **Amity Toolkit** with four modules:

- **Bar Text**: always-on health / resource text as `100/200 50%`, `100/200` or `50%` on the player, target and target-of-target frames.
- **Auction Item Level**: sortable iLvl column in the auction house browse results.
- **LFG Role Filter**: Tank / Healer / DPS filter buttons in the Looking For Group browse list.
- **Overpower Alert - Warrior**: movable Overpower icon with a 5 second countdown when your target dodges. Warriors only; inactive on other classes.

Also included:

- The Amity panel (`/amity`, minimap button or addon compartment): an overview plus one tab per module with its on/off switch, description and settings. The panel can be moved and stays open until closed.
- All settings live in one saved variable (`AmityDB`).
