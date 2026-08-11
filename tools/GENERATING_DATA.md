# Generating / expanding WeaponProg's weapon data

WoW addons **cannot fetch data from the internet at runtime** — there is no HTTP
access in the addon sandbox. So the weapon dataset is baked **offline** and shipped
as a static Lua table in [`Data/Weapons.lua`](../Data/Weapons.lua) — the same
approach `AtlasLootClassic_Data` and `GatherMate2_Data` use.

`Data/Weapons.lua` is **generated**, not hand-edited. It is produced by
[`generate_weapons.py`](generate_weapons.py) from two community databases that ship
with addons already installed in this AddOns folder:

- **Questie** (`Questie/Database/Classic/`) — item metadata: name, weapon subclass
  (weapon `type`), required level, plus drop / quest / vendor ID references.
- **AtlasLootClassic** (`AtlasLootClassic_Data`, `_DungeonsAndRaids`, `_PvP`) —
  authoritative source categorisation: which dungeon/raid, which profession, PvP.

> **No runtime dependency.** Questie and AtlasLoot are read only *when you run the
> generator*. The file it emits is a plain, self-contained table — WeaponProg does
> not read those addons in-game, and works even if they are uninstalled. The data
> itself is factual game data (item IDs, names, sources) credited to those
> community projects.

## Regenerating

From anywhere (paths resolve relative to the script):

```
py WeaponProg/tools/generate_weapons.py
```

Requires **Python 3.8+**, standard library only — no pip, no network. It prints a
per-source and per-type breakdown and a few spot-checks, then overwrites
`Data/Weapons.lua`. Re-run it whenever Questie or AtlasLoot update. After running,
`/reload` in game (or lint with the `wow-addon-lint` skill).

## Record format

Each entry in the global `WeaponProgData` table is keyed by **itemID**:

```lua
[12940] = { name = "Dal'Rend's Sacred Charge", type = "Sword1H", req = 58,
            src = "DUNGEON", detail = "Upper Blackrock Spire" },
```

### Valid `type` keys
Defined in [`Sources.lua`](../Sources.lua) `ns.WEAPON_TYPE_ORDER`:

`Sword1H, Sword2H, Axe1H, Axe2H, Mace1H, Mace2H, Dagger, Fist, Polearm, Staff,
Bow, Crossbow, Gun, Thrown, Wand, FishingPole, Misc`

### Valid `src` keys
Defined in `Sources.lua` `ns.SOURCE`:

`WORLD, QUEST, DUNGEON, RAID, VENDOR, PVP, BS, LW, ENG, TAILOR, ENCH, UNKNOWN`

## How the generator resolves each weapon

1. **Universe & metadata** — every Questie item with `class == 2` (Weapon). Its
   `subClass` maps to a `type` key (Spear folds into Polearm); `name` and
   `requiredLevel` come straight from the record. **Required-level fallback:**
   Questie's `requiredLevel` is the level to *equip*, which is 0 for many quest
   rewards (misleading, and it mis-sorts them by level). When it's 0, the generator
   substitutes the level of the rewarding quest (`questRewards` → questDB
   `questLevel`, min across reward quests, ignoring level-0 quests). Any weapon
   whose effective level is still 0 after this (a handful of level-less
   starter/racial/profession items and fishing poles) is **dropped** from the
   output entirely.
2. **Source** — resolved in priority order:
   - **AtlasLoot `source.lua`** if it has the item: source-type `1` (Loot) becomes
     `DUNGEON` or `RAID` by the instance's `ContentType`; `2`→`QUEST`, `3`→`VENDOR`,
     and profession codes `5/6/11/12/13`→`BS/LW/TAILOR/ENG/ENCH`.
   - **AtlasLoot PvP module** — any weapon listed there is tagged `PVP` (wins over a
     plain vendor tag).
   - **Questie fallback** when AtlasLoot has no entry: the item's own
     `questRewards`/`relatedQuests`→`QUEST`, `vendors`→`VENDOR`, `npcDrops`→`WORLD`.
   - Otherwise `DEFAULT_SOURCE` (`WORLD`).
   - **`OVERRIDES`** — a small manual-correction table (top of the script) wins over
     everything, for famous items the community DBs miss (e.g. Sulfuras is crafted
     from a Ragnaros drop; Benediction/Anathema are quest-created — none carry a
     usable reference, so they'd otherwise fall back to World drop).
3. **`detail`** — a human-readable origin built from Questie's names (dungeon/raid
   instance, quest name, vendor name, dropping NPC, or profession).

## Tuning the output

Constants at the top of `generate_weapons.py`:

- `DEFAULT_SOURCE` — bucket for weapons with no signal at all (default `"WORLD"`;
  set `"UNKNOWN"` to leave them explicitly unclassified).
- `EXCLUDE_TYPES` — weapon-type keys to drop entirely. Empty = comprehensive (every
  weapon, ~2,100). To omit the two non-combat buckets: `{"FishingPole", "Misc"}`.
- `OVERRIDES` — add `itemID: ("SRC", "detail")` rows for any manual corrections.

## Adding a single weapon by hand

The file is regenerated, so hand-edits to `Data/Weapons.lua` are overwritten. To
add or fix one weapon durably, add an `OVERRIDES` entry (for its source) — or, if
it is missing entirely, confirm it exists in Questie's item DB. Then regenerate.

## Data credit

Weapon data is derived from the **Questie** and **AtlasLootClassic** community
databases (factual Classic game data), baked here the same way
`AtlasLootClassic_Data` bakes Wowhead-sourced loot data.
