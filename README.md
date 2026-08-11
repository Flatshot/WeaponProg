# WeaponProg

A **World of Warcraft Classic Era** addon that shows where weapons come from —
world drop, quest, dungeon/raid drop, vendor, crafted, PvP, etc. — both on
**tooltip mouseover** and in a **browsable window** opened from a **minimap button**.

Built on the `!AddonTemplate` boilerplate.

## Features

- **Tooltip origins.** Hover any weapon that's in the dataset (in bags, on the
  auction house, from a chat item link, etc.) and WeaponProg appends its origin:
  a colored source label plus a human-readable detail line.
- **Weapon browser.** Click the minimap button (or `/wp`) to open a window that
  lists weapons grouped by **weapon type → required-level bracket**. Each row
  shows the source label; hovering a row shows the full (augmented) item tooltip.
- **Minimap button.** Left-click opens the browser; right-click hides the button
  (bring it back with `/wp minimap`). Position is saved.

## Slash commands

| Command | Action |
|---|---|
| `/wp` or `/weaponprog` | Toggle the browser window |
| `/wp minimap` | Show/hide the minimap button |
| `/wp debug` | Toggle debug output |

## How the data works (important)

WoW addons have **no runtime internet access**, so WeaponProg cannot pull from
Wowhead live. The weapon data is gathered **offline** and baked into
[`Data/Weapons.lua`](Data/Weapons.lua) — the standard pattern for data addons
(`AtlasLootClassic_Data`, `GatherMate2_Data`).

The shipped data is **comprehensive** — every Classic weapon (~2,100 items across
all types and source categories). It is **generated**, not hand-edited: a Python
tool bakes it offline from the **Questie** and **AtlasLootClassic** community
databases. WeaponProg has no runtime dependency on those addons; it just reads its
own baked table. To regenerate or tune the dataset, see
[`tools/GENERATING_DATA.md`](tools/GENERATING_DATA.md).

## Layout

```
WeaponProg/
  WeaponProg.toc        # manifest (interface 11507)
  embeds.xml            # Ace3 + LibDBIcon load order
  Libs/                 # embedded libraries (copied from Questie)
  Core.lua              # namespace, AceDB, dataset import, slash command
  Sources.lua           # source taxonomy + weapon-type metadata + GetWeaponInfo()
  Data/Weapons.lua      # the baked dataset
  Tooltip.lua           # tooltip origin lines (dual-path hook)
  Browser.lua           # AceGUI TreeGroup browser
  Minimap.lua           # LibDataBroker + LibDBIcon minimap button
  tools/GENERATING_DATA.md
```

## Dependencies

All bundled (no external addons required): LibStub, CallbackHandler-1.0,
AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceConsole-3.0, AceGUI-3.0, AceConfig-3.0,
LibDataBroker-1.1, LibDBIcon-1.0.

## Notes

- `## Interface: 11507` targets Classic Era 1.15.x. If it shows as out of date,
  bump this to match your client (it still loads if "Load out of date AddOns" is
  checked).
- Iterate with `/reload`; enable Lua errors with `/console scriptErrors 1`.
```
