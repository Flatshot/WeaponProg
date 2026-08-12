-- luacheck configuration for the WeaponProg WoW Classic Era addon.
-- WoW runs Lua 5.1; the API is injected as globals, so we whitelist them.

std = "lua51"
max_line_length = false
codes = true

-- Don't lint bundled third-party libraries.
exclude_files = {
    "Libs/",
    ".luacheckrc",
}

-- Globals this addon defines or mutates (writable).
globals = {
    "WeaponProgData",       -- baked dataset (Data/Weapons.lua), nil'd after import
    "WeaponProgDB",         -- SavedVariable
    "SlashCmdList",
    "SLASH_WEAPONPROG1",
    "SLASH_WEAPONPROG2",
    "StaticPopupDialogs",    -- Blizzard table we register a dialog into
}

-- WoW API surface we read (read-only). Not exhaustive for all of WoW, just what
-- WeaponProg touches plus common companions.
read_globals = {
    -- core frame/UI
    "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip",
    "GameFontNormalLarge", "PlaySound", "SOUNDKIT", "C_Timer",
    -- string/table helpers WoW adds to the global env
    "strjoin", "strsplit", "strtrim", "strlower", "tostringall", "strmatch",
    "wipe", "tContains", "hooksecurefunc",
    -- item / tooltip APIs
    "GetItemIcon", "GetItemInfo", "GetItemQualityColor",
    "C_TooltipInfo", "TooltipDataProcessor", "TooltipUtil", "Enum",
    "C_Item",
    -- popup + chat-link (row click -> Wowhead URL / insert item link)
    "StaticPopup_Show", "IsShiftKeyDown", "ChatEdit_InsertLink", "CLOSE",
    -- libraries (provided by embeds.xml at runtime)
    "LibStub",
}
