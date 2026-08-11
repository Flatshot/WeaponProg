--[[
    WeaponProg - Sources.lua

    Defines the "origin" taxonomy (AtlasLoot-style: standard categories plus
    crafted broken out per profession), the weapon-type metadata used to group
    the browser, and the single lookup both the tooltip and the browser use.
]]

local _, ns = ...

-- ---------------------------------------------------------------------------
-- Source (origin) types
-- ---------------------------------------------------------------------------
-- key -> { label, color (6-hex, no alpha), icon }
ns.SOURCE = {
    WORLD   = { label = "World Drop",     color = "ffffff", icon = "Interface\\ICONS\\INV_Misc_Map_01" },
    QUEST   = { label = "Quest Reward",   color = "ffff00", icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
    DUNGEON = { label = "Dungeon Drop",   color = "1eff00", icon = "Interface\\ICONS\\INV_Misc_Head_Dragon_01" },
    RAID    = { label = "Raid Drop",      color = "a335ee", icon = "Interface\\ICONS\\INV_Misc_Head_Dragon_Black" },
    VENDOR  = { label = "Vendor",         color = "ffd100", icon = "Interface\\ICONS\\INV_Misc_Coin_01" },
    PVP     = { label = "PvP Reward",     color = "ff4040", icon = "Interface\\ICONS\\INV_BannerPVP_01" },
    BS      = { label = "Blacksmithing",  color = "cc8855", icon = "Interface\\ICONS\\Trade_BlackSmithing" },
    LW      = { label = "Leatherworking", color = "cc8855", icon = "Interface\\ICONS\\Trade_LeatherWorking" },
    ENG     = { label = "Engineering",    color = "cc8855", icon = "Interface\\ICONS\\Trade_Engineering" },
    TAILOR  = { label = "Tailoring",      color = "cc8855", icon = "Interface\\ICONS\\Trade_Tailoring" },
    ENCH    = { label = "Enchanting",     color = "cc8855", icon = "Interface\\ICONS\\Trade_Engraving" },
    UNKNOWN = { label = "Unknown",        color = "999999", icon = "Interface\\ICONS\\INV_Misc_QuestionMark" },
}

-- ---------------------------------------------------------------------------
-- Weapon types (drives the browser's top-level grouping; ordered for display)
-- ---------------------------------------------------------------------------
ns.WEAPON_TYPE_ORDER = {
    "Sword1H", "Sword2H", "Axe1H", "Axe2H", "Mace1H", "Mace2H",
    "Dagger", "Fist", "Polearm", "Staff",
    "Bow", "Crossbow", "Gun", "Thrown", "Wand",
    "FishingPole", "Misc",
}

ns.WEAPON_TYPE_LABEL = {
    Sword1H  = "Swords (1H)",
    Sword2H  = "Swords (2H)",
    Axe1H    = "Axes (1H)",
    Axe2H    = "Axes (2H)",
    Mace1H   = "Maces (1H)",
    Mace2H   = "Maces (2H)",
    Dagger   = "Daggers",
    Fist     = "Fist Weapons",
    Polearm  = "Polearms",
    Staff    = "Staves",
    Bow      = "Bows",
    Crossbow = "Crossbows",
    Gun      = "Guns",
    Thrown   = "Thrown",
    Wand     = "Wands",
    FishingPole = "Fishing Poles",
    Misc     = "Miscellaneous",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
function ns.Colorize(hex, text)
    return "|cff" .. (hex or "ffffff") .. tostring(text) .. "|r"
end

-- Returns the source metadata table for a weapon record (falls back to UNKNOWN).
function ns.GetSourceInfo(srcKey)
    return ns.SOURCE[srcKey] or ns.SOURCE.UNKNOWN
end

-- The single lookup shared by Tooltip.lua and Browser.lua.
-- Returns the record { name, type, req, src, detail } or nil.
function ns.GetWeaponInfo(itemID)
    if not itemID then return nil end
    return ns.WEAPONS[tonumber(itemID)]
end
