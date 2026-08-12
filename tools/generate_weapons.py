#!/usr/bin/env python3
"""
generate_weapons.py -- bake WeaponProg's Data/Weapons.lua from local community DBs.

WoW addons have no runtime internet access, so WeaponProg ships a static, baked
weapon dataset (the AtlasLootClassic_Data / GatherMate2_Data pattern). This script
is the *offline* generator for that dataset. It reads the Lua databases that ship
with two community addons already installed in this AddOns folder --

    * Questie          -- item metadata (name, weapon subclass, required level)
                          plus drop / quest / vendor ID references
    * AtlasLootClassic -- authoritative source categorisation (which dungeon/raid,
                          which profession, PvP) via its reverse item->source index

-- filters to weapons, resolves each weapon's origin, and writes a self-contained
Lua table to ../Data/Weapons.lua.

The GENERATED FILE has NO runtime dependency on Questie or AtlasLoot: it is a plain
static table baked into WeaponProg. Those addons only need to be present *here*,
when you run this generator. The data itself is factual game data (item IDs, names,
sources) sourced from those community databases.

Usage:
    py WeaponProg/tools/generate_weapons.py      (from the AddOns folder, or anywhere)

Requires: Python 3.8+ standard library only. No pip, no network.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# Weapons with no drop / quest / vendor / craft signal at all fall back to this.
# In Classic the vast majority of otherwise-unsourced equippable weapons are
# random world drops, so WORLD is the sensible default; set to "UNKNOWN" if you
# would rather leave them explicitly unclassified.
DEFAULT_SOURCE = "WORLD"

# Manual corrections applied AFTER automatic resolution, keyed by itemID:
#   itemID -> (SOURCE_key, detail_string)
# The community DBs miss a few famous "crafted-from-a-drop" or "quest-created"
# legendaries (they carry no drop/quest/vendor/craft reference, so they fall back
# to World drop). Fix those here; add your own as needed. type/req still come from
# Questie -- only the origin is overridden.
OVERRIDES = {
    17182: ("BS", "Blacksmithing — forged from Eye of Sulfuras (Ragnaros) + Sulfuron Hammer"),
    18608: ("QUEST", "Quest reward: The Balance of Light and Shadow (Benediction)"),
    18609: ("QUEST", "Quest reward: The Balance of Light and Shadow (Anathema)"),
}

# Weapon-type keys to drop from the output entirely. Empty == comprehensive
# (every weapon). To trim the two "not really a combat weapon" buckets, use:
#   EXCLUDE_TYPES = {"FishingPole", "Misc"}
EXCLUDE_TYPES: set[str] = set()

# ---------------------------------------------------------------------------
# Paths (resolved relative to this script: tools/ -> WeaponProg/ -> AddOns/)
# ---------------------------------------------------------------------------

TOOLS_DIR = Path(__file__).resolve().parent
WEAPONPROG_DIR = TOOLS_DIR.parent
ADDONS_DIR = WEAPONPROG_DIR.parent

QUESTIE_CLASSIC = ADDONS_DIR / "Questie" / "Database" / "Classic"
ITEM_DB = QUESTIE_CLASSIC / "classicItemDB.lua"
NPC_DB = QUESTIE_CLASSIC / "classicNpcDB.lua"
QUEST_DB = QUESTIE_CLASSIC / "classicQuestDB.lua"

AL_SOURCE = ADDONS_DIR / "AtlasLootClassic_Data" / "source.lua"
AL_DUNGEONS = ADDONS_DIR / "AtlasLootClassic_DungeonsAndRaids" / "data.lua"
AL_PVP = ADDONS_DIR / "AtlasLootClassic_PvP" / "data.lua"

OUT_FILE = WEAPONPROG_DIR / "Data" / "Weapons.lua"

# ---------------------------------------------------------------------------
# Questie weapon subClass (field 13, when class==2) -> our WEAPON_TYPE key.
# Legend from Questie\Database\itemDB.lua. Spear(17) folds into Polearm.
# ---------------------------------------------------------------------------

SUBCLASS_TO_TYPE = {
    0: "Axe1H", 1: "Axe2H", 2: "Bow", 3: "Gun", 4: "Mace1H", 5: "Mace2H",
    6: "Polearm", 7: "Sword1H", 8: "Sword2H", 10: "Staff", 13: "Fist",
    14: "Misc", 15: "Dagger", 16: "Thrown", 17: "Polearm", 18: "Crossbow",
    19: "Wand", 20: "FishingPole",
}

# AtlasLoot source-type code (element [3] of a source.lua ItemData entry) -> our
# SOURCE key. Code 1 (Loot) is resolved to DUNGEON/RAID via the instance's
# ContentType and handled separately. Professions that never craft weapons map to
# UNKNOWN if they ever appear.
AL_SOURCETYPE_TO_SRC = {
    2: "QUEST", 3: "VENDOR",
    5: "BS", 6: "LW", 11: "TAILOR", 12: "ENG", 13: "ENCH",
}

# Pretty display names for AtlasLoot instance IDs (used in the `detail` string).
INSTANCE_NAMES = {
    "Ragefire": "Ragefire Chasm", "WailingCaverns": "Wailing Caverns",
    "TheDeadmines": "The Deadmines", "ShadowfangKeep": "Shadowfang Keep",
    "BlackfathomDeeps": "Blackfathom Deeps", "TheStockade": "The Stockade",
    "Gnomeregan": "Gnomeregan", "RazorfenKraul": "Razorfen Kraul",
    "ScarletMonasteryGraveyard": "Scarlet Monastery: Graveyard",
    "ScarletMonasteryLibrary": "Scarlet Monastery: Library",
    "ScarletMonasteryArmory": "Scarlet Monastery: Armory",
    "ScarletMonasteryCathedral": "Scarlet Monastery: Cathedral",
    "RazorfenDowns": "Razorfen Downs", "Uldaman": "Uldaman",
    "Zul'Farrak": "Zul'Farrak", "Maraudon": "Maraudon",
    "TheTempleOfAtal'Hakkar": "The Temple of Atal'Hakkar",
    "BlackrockDepths": "Blackrock Depths",
    "LowerBlackrockSpire": "Lower Blackrock Spire",
    "UpperBlackrockSpire": "Upper Blackrock Spire",
    "DireMaulEast": "Dire Maul: East", "DireMaulWest": "Dire Maul: West",
    "DireMaulNorth": "Dire Maul: North", "Scholomance": "Scholomance",
    "Stratholme": "Stratholme", "WorldBosses": "World Bosses",
    "MoltenCore": "Molten Core", "Onyxia": "Onyxia's Lair",
    "Zul'Gurub": "Zul'Gurub", "BlackwingLair": "Blackwing Lair",
    "TheRuinsofAhnQiraj": "Ruins of Ahn'Qiraj",
    "TheTempleofAhnQiraj": "Temple of Ahn'Qiraj", "Naxxramas": "Naxxramas",
}

PROFESSION_LABEL = {
    "BS": "Blacksmithing", "LW": "Leatherworking", "TAILOR": "Tailoring",
    "ENG": "Engineering", "ENCH": "Enchanting",
}


# ---------------------------------------------------------------------------
# A tiny parser for the Lua table literals used by these DBs.
# Handles: nested {} tables, positional values, [intkey]=value, nil/true/false,
# ints/floats, and 'single'/"double" quoted strings with backslash escapes.
# Returns a table as a dict: positional entries keyed 1,2,3..., explicit keys as
# given. (No identifier-name keys -- the fully-parsed tables never use them.)
# ---------------------------------------------------------------------------

class LuaParser:
    __slots__ = ("s", "i", "n")

    def __init__(self, s: str):
        self.s = s
        self.i = 0
        self.n = len(s)

    def _err(self, msg: str):
        ctx = self.s[max(0, self.i - 30):self.i + 30]
        raise ValueError(f"{msg} at {self.i}: ...{ctx!r}...")

    def _ws(self):
        while self.i < self.n and self.s[self.i] in " \t\r\n":
            self.i += 1

    def parse_value(self):
        self._ws()
        if self.i >= self.n:
            self._err("unexpected end")
        c = self.s[self.i]
        if c == "{":
            return self._table()
        if c == "'" or c == '"':
            return self._string(c)
        return self._scalar()

    def _string(self, quote: str) -> str:
        self.i += 1
        out = []
        s, n = self.s, self.n
        while self.i < n:
            c = s[self.i]
            if c == "\\" and self.i + 1 < n:
                nxt = s[self.i + 1]
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(nxt, nxt))
                self.i += 2
                continue
            if c == quote:
                self.i += 1
                return "".join(out)
            out.append(c)
            self.i += 1
        self._err("unterminated string")

    def _scalar(self):
        start = self.i
        s = self.s
        while self.i < self.n and s[self.i] not in ",}=]":
            self.i += 1
        tok = s[start:self.i].strip()
        if tok == "nil":
            return None
        if tok == "true":
            return True
        if tok == "false":
            return False
        try:
            return int(tok)
        except ValueError:
            pass
        try:
            return float(tok)
        except ValueError:
            return tok  # bare identifier / constant -- keep raw

    def _table(self) -> dict:
        self.i += 1  # consume '{'
        result: dict = {}
        pos = 0
        while True:
            self._ws()
            if self.i >= self.n:
                self._err("unterminated table")
            c = self.s[self.i]
            if c == "}":
                self.i += 1
                return result
            if c == "[":
                self.i += 1
                key = self.parse_value()
                self._ws()
                if self.s[self.i] != "]":
                    self._err("expected ']'")
                self.i += 1
                self._ws()
                if self.s[self.i] != "=":
                    self._err("expected '=' after [key]")
                self.i += 1
                result[key] = self.parse_value()
            else:
                pos += 1
                result[pos] = self.parse_value()
            self._ws()
            if self.i < self.n and self.s[self.i] == ",":
                self.i += 1


def parse_table_literal(text: str) -> dict:
    """Parse a single '{...}' Lua table literal into a dict."""
    return LuaParser(text).parse_value()


def split_top_fields(inner: str, upto: int) -> list:
    """Return the first `upto` top-level field substrings of a table's *inner*
    text (everything after the opening '{'), stopping early so we never descend
    into large nested tables (e.g. Questie NPC spawn coordinate lists)."""
    fields: list[str] = []
    buf: list[str] = []
    depth = 0
    i, n = 0, len(inner)
    while i < n and len(fields) < upto:
        c = inner[i]
        if c in "'\"":
            buf.append(c)
            i += 1
            while i < n:
                d = inner[i]
                buf.append(d)
                if d == "\\" and i + 1 < n:
                    buf.append(inner[i + 1])
                    i += 2
                    continue
                i += 1
                if d == c:
                    break
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            if depth == 0:  # closing brace of the record itself
                break
            depth -= 1
        elif c == "," and depth == 0:
            fields.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if len(fields) < upto:
        tail = "".join(buf).strip()
        if tail:
            fields.append(tail)
    return fields


def scalar_token(tok: str):
    """Parse one already-split scalar field ('name', 5, nil, ...)."""
    tok = tok.strip()
    if tok == "" or tok == "nil":
        return None
    if tok[0] in "'\"":
        body = tok[1:-1]
        return body.replace("\\'", "'").replace('\\"', '"').replace("\\\\", "\\")
    try:
        return int(tok)
    except ValueError:
        try:
            return float(tok)
        except ValueError:
            return tok


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------

RECORD_RE = re.compile(r"^\[(\d+)\]\s*=\s*(\{.*\}),?\s*$")


def iter_records(path: Path, marker: str):
    """Yield (id:int, inner_after_first_brace:str, full_braces:str) for each
    '[id] = { ... }' line inside the long-string blob that starts with `marker`."""
    started = False
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            if not started:
                if marker in line:
                    started = True
                continue
            stripped = line.rstrip("\n")
            if stripped.startswith("}]]") or stripped == "]]":
                break
            m = RECORD_RE.match(stripped)
            if m:
                yield int(m.group(1)), m.group(2)


def load_items() -> dict:
    """itemID -> parsed dict of the Questie item record (weapons only)."""
    items = {}
    for item_id, braces in iter_records(ITEM_DB, "itemData = [[return"):
        rec = parse_table_literal(braces)
        if rec.get(12) != 2:  # class 2 == Weapon
            continue
        items[item_id] = rec
    return items


def load_names(path: Path, marker: str, upto: int):
    """id -> list of the first `upto` scalar/reference fields (nested tables left
    as raw strings). Used for the NPC and quest DBs, where we only need a couple
    of leading fields and want to skip the huge trailing spawn tables."""
    out = {}
    for rid, braces in iter_records(path, marker):
        inner = braces[1:]  # drop leading '{'
        out[rid] = split_top_fields(inner, upto)
    return out


def load_atlasloot_source():
    """Return (item_source, instances):
       item_source: itemID -> parsed source entry dict ([1]=instIdx,[3]=type,...)
       instances:   ordered list of AtlasLoot instance-id strings (1-based)."""
    if not AL_SOURCE.exists():
        return {}, []
    text = AL_SOURCE.read_text(encoding="utf-8")

    instances = []
    m = re.search(r'\["AtlasLootIDs"\]\s*=\s*\{(.*?)\}', text, re.DOTALL)
    if m:
        instances = re.findall(r'"([^"]*)"', m.group(1))

    item_source = {}
    md = re.search(r'\["ItemData"\]\s*=\s*\{(.*)\}', text, re.DOTALL)
    body = md.group(1) if md else ""
    for line in body.splitlines():
        line = line.strip()
        rec = RECORD_RE.match(line)
        if rec:
            item_source[int(rec.group(1))] = parse_table_literal(rec.group(2))
    return item_source, instances


def load_instance_content():
    """AtlasLoot instance-id -> 'DUNGEON' or 'RAID', from the DungeonsAndRaids
    module's ContentType tags."""
    content = {}
    if not AL_DUNGEONS.exists():
        return content
    current = None
    key_re = re.compile(r'data\["([^"]+)"\]\s*=')
    ct_re = re.compile(r"ContentType\s*=\s*(\w+)")
    with AL_DUNGEONS.open(encoding="utf-8") as fh:
        for line in fh:
            km = key_re.search(line)
            if km:
                current = km.group(1)
                continue
            cm = ct_re.search(line)
            if cm and current:
                ct = cm.group(1)
                content[current] = "DUNGEON" if ct.startswith("DUNGEON") else "RAID"
                current = None
    return content


def load_pvp_items() -> set:
    """Every itemID referenced in the PvP module (any weapon here is a PvP reward)."""
    if not AL_PVP.exists():
        return set()
    text = AL_PVP.read_text(encoding="utf-8")
    return {int(x) for x in re.findall(r"\{\s*\d+,\s*(\d+)\b", text)}


# ---------------------------------------------------------------------------
# Source resolution
# ---------------------------------------------------------------------------

def quest_detail(rec, quest_names):
    ref = rec.get(6) or rec.get(15)  # questRewards / relatedQuests
    qid = _first_from_parsed(ref) if ref else None
    qn = quest_names.get(qid) if qid else None
    return f"Quest reward: {qn}" if qn else "Quest reward"


def vendor_detail(rec, npc_names):
    vid = _first_from_parsed(rec.get(14))
    vn = npc_names.get(vid) if vid else None
    return f"Sold by {vn}" if vn else "Purchased from a vendor"


def effective_req(rec, quest_levels):
    """Required level for a weapon. Questie's requiredLevel (field [10]) is the
    level to *equip*, which is 0 for many quest rewards -- misleading and it
    mis-sorts them by level. When it's 0, fall back to the level of the quest that
    rewards the item (field [6] questRewards -> questDB questLevel), taking the
    minimum across reward quests and ignoring any level-0 quest."""
    req = rec.get(10) or 0
    if req == 0:
        levels = [quest_levels.get(q) for q in _list_from_parsed(rec.get(6))]
        levels = [lvl for lvl in levels if lvl]  # drop None / 0
        if levels:
            return min(levels)
    return req


# Race bitmask -> faction. Alliance group = 77 (Human1+Dwarf4+NightElf8+Gnome64),
# Horde group = 178 (Orc2+Undead16+Tauren32+Troll128). Every value in the Classic
# quest DB sets bits within a single faction (subsets occur but never mix), and 0
# means no race restriction. So a masked test classifies every case.
ALLIANCE_MASK, HORDE_MASK = 77, 178


def _race_faction(r):
    if not r:
        return None  # no restriction -> both
    a, h = (r & ALLIANCE_MASK) != 0, (r & HORDE_MASK) != 0
    return "A" if (a and not h) else "H" if (h and not a) else None


def weapon_faction(rec, quest_races):
    """Faction a quest-reward weapon is obtainable by, as the UNION across its
    questRewards: a mirrored Alliance+Horde quest pair (or any both/unknown quest)
    yields both. Returns 'A', 'H', or None (both/unknown)."""
    a = h = False
    for q in _list_from_parsed(rec.get(6)):
        f = _race_faction(quest_races.get(q))
        if f == "A":
            a = True
        elif f == "H":
            h = True
        else:
            a = h = True  # a both/unknown reward quest => obtainable by both
    return "A" if (a and not h) else "H" if (h and not a) else None


def resolve_source(item_id, rec, ctx):
    """Return (src_key, detail_string)."""
    al_source = ctx["al_source"]
    instances = ctx["instances"]
    content = ctx["content"]
    npc_names = ctx["npc_names"]
    quest_names = ctx["quest_names"]

    # 1) AtlasLoot authoritative categorisation.
    entry = al_source.get(item_id)
    if entry:
        # An entry is either a single source ({a,b,c} or {[3]=t,[4]=x}) or a list
        # of sources ({{...},{...}}) when an item drops in several places. Take
        # the first sub-entry as representative, and note if there are more.
        multi = isinstance(entry.get(1), dict)
        rep = entry.get(1) if multi else entry
        n_more = (len(entry) - 1) if multi else 0
        stype = rep.get(3) if isinstance(rep, dict) else None
        if stype == 1:  # instanced loot
            inst_idx = rep.get(1)
            inst_id = instances[inst_idx - 1] if inst_idx and 1 <= inst_idx <= len(instances) else None
            bucket = content.get(inst_id, "DUNGEON") if inst_id else "DUNGEON"
            pretty = INSTANCE_NAMES.get(inst_id, inst_id or "an instance")
            if n_more:
                pretty += " (and other instances)"
            return bucket, pretty
        src = AL_SOURCETYPE_TO_SRC.get(stype)
        if src == "QUEST":
            return "QUEST", quest_detail(rec, quest_names)
        if src == "VENDOR":
            return "VENDOR", vendor_detail(rec, npc_names)
        if src in PROFESSION_LABEL:
            return src, f"{PROFESSION_LABEL[src]} (crafted)"
        # profession that doesn't make weapons, or Unknown code
        if src:
            return src, ""

    # 2) Questie fallback from the item record's own references.
    if rec.get(6) or rec.get(15):
        return "QUEST", quest_detail(rec, quest_names)

    if rec.get(14):
        return "VENDOR", vendor_detail(rec, npc_names)

    npc_drops = rec.get(2)
    if npc_drops:
        drops = _list_from_parsed(npc_drops)
        if len(drops) == 1:
            nn = npc_names.get(drops[0])
            if nn:
                return "WORLD", f"Drops from {nn}"
        return "WORLD", "World drop"

    return DEFAULT_SOURCE, "World drop" if DEFAULT_SOURCE == "WORLD" else ""


def _list_from_parsed(field):
    """The item DB is fully parsed, so list fields are dicts {1:id,2:id,...}."""
    if isinstance(field, dict):
        return [v for v in field.values() if isinstance(v, int)]
    if isinstance(field, list):
        return [v for v in field if isinstance(v, int)]
    return []


def _first_from_parsed(field):
    lst = _list_from_parsed(field)
    return lst[0] if lst else None


# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


HEADER = '''--[[
    WeaponProg - Data\\Weapons.lua

    THE BAKED DATASET -- GENERATED FILE, DO NOT EDIT BY HAND.

    WoW addons have no runtime internet access, so this weapon data is baked
    OFFLINE and shipped as a static table (the AtlasLootClassic_Data /
    GatherMate2_Data pattern). It is generated by tools/generate_weapons.py from
    the Questie and AtlasLootClassic community databases; regenerate with:

        py WeaponProg/tools/generate_weapons.py

    This file has NO runtime dependency on Questie or AtlasLoot -- it is a plain
    self-contained table. See tools/GENERATING_DATA.md for the full pipeline.

    Record format:
        [itemID] = { name = <string>, type = <weapon-type key>,
                     req = <number>, src = <source key>, detail = <string>,
                     faction = "A"|"H" }   -- optional; QUEST items only, omitted
                                           -- when obtainable by both factions
    (type keys: Sources.lua ns.WEAPON_TYPE_ORDER; src keys: ns.SOURCE)

    Core.lua copies this global into ns.WEAPONS on ADDON_LOADED, then nils it so
    the table can be garbage-collected.
]]

'''


def build():
    if not ITEM_DB.exists():
        sys.exit(
            f"ERROR: Questie item DB not found at:\n  {ITEM_DB}\n"
            "Questie must be installed in this AddOns folder to generate the data."
        )

    print("Reading Questie item DB ...")
    items = load_items()
    print(f"  {len(items)} weapons (class==2) found")

    print("Reading Questie NPC / quest names ...")
    npc_names = load_names(NPC_DB, "npcData = [[return", 1) if NPC_DB.exists() else {}
    quest_rows = load_names(QUEST_DB, "questData = [[return", 6) if QUEST_DB.exists() else {}
    quest_names = {qid: scalar_token(row[0]) for qid, row in quest_rows.items() if row}
    # questLevel is quest field [5] (row index 4); used to fill in req for
    # quest-reward weapons whose own equip requiredLevel is 0.
    quest_levels = {qid: scalar_token(row[4]) for qid, row in quest_rows.items() if len(row) >= 5}
    # requiredRaces is quest field [6] (row index 5); a race bitmask -> faction.
    quest_races = {qid: scalar_token(row[5]) for qid, row in quest_rows.items() if len(row) >= 6}
    npc_names = {nid: scalar_token(row[0]) for nid, row in npc_names.items() if row}

    print("Reading AtlasLoot source index ...")
    al_source, instances = load_atlasloot_source()
    content = load_instance_content()
    pvp_items = load_pvp_items()
    if al_source:
        print(f"  {len(al_source)} items in source index, "
              f"{len(instances)} instances, {len(pvp_items)} PvP item refs")
    else:
        print("  (AtlasLoot not found -- falling back to Questie references only)")

    ctx = {
        "al_source": al_source, "instances": instances, "content": content,
        "npc_names": npc_names, "quest_names": quest_names,
    }

    rows = []
    per_src: dict[str, int] = {}
    per_type: dict[str, int] = {}
    skipped_type = 0
    skipped_zero = 0

    for item_id, rec in items.items():
        name = rec.get(1)
        if not name:
            continue
        wtype = SUBCLASS_TO_TYPE.get(rec.get(13))
        if not wtype or wtype in EXCLUDE_TYPES:
            skipped_type += 1
            continue
        req = effective_req(rec, quest_levels)
        if req == 0:  # genuinely level-less starter/profession items -- drop them
            skipped_zero += 1
            continue

        src, detail = resolve_source(item_id, rec, ctx)
        if item_id in pvp_items:  # PvP module wins over a plain Vendor tag
            src, detail = "PVP", "PvP reward"
        if item_id in OVERRIDES:  # manual corrections win over everything
            src, detail = OVERRIDES[item_id]

        # Faction of quest rewards, for the browser's quest-label colour.
        faction = weapon_faction(rec, quest_races) if src == "QUEST" else None

        rows.append((item_id, name, wtype, req, src, detail, faction))
        per_src[src] = per_src.get(src, 0) + 1
        per_type[wtype] = per_type.get(wtype, 0) + 1

    rows.sort(key=lambda r: r[0])

    lines = [HEADER, "WeaponProgData = {\n"]
    for item_id, name, wtype, req, src, detail, faction in rows:
        parts = [
            f'name = "{lua_escape(name)}"',
            f'type = "{wtype}"',
            f"req = {req}",
            f'src = "{src}"',
        ]
        if detail:
            parts.append(f'detail = "{lua_escape(detail)}"')
        if faction:  # "A"/"H" only; both/unknown is omitted (browser -> yellow)
            parts.append(f'faction = "{faction}"')
        lines.append(f"    [{item_id}] = {{ {', '.join(parts)} }},\n")
    lines.append("}\n")

    OUT_FILE.write_text("".join(lines), encoding="utf-8")

    # ------- report -------
    print(f"\nWrote {len(rows)} weapons -> {OUT_FILE}")
    if skipped_type:
        print(f"  ({skipped_type} skipped by EXCLUDE_TYPES / unmapped subclass)")
    if skipped_zero:
        print(f"  ({skipped_zero} dropped for req 0)")
    print("\nBy source:")
    for k in sorted(per_src, key=lambda k: -per_src[k]):
        print(f"  {k:8} {per_src[k]}")
    print("\nBy type:")
    for k in sorted(per_type, key=lambda k: -per_type[k]):
        print(f"  {k:12} {per_type[k]}")

    # spot-checks
    print("\nSpot-checks:")
    by_id = {r[0]: r for r in rows}
    for sid in (19019, 2244, 12784, 12940):
        r = by_id.get(sid)
        print(f"  [{sid}] {r}" if r else f"  [{sid}] (not in output)")


if __name__ == "__main__":
    build()
