--[[
    WeaponProg - Core.lua

    Bootstraps the addon: private namespace, saved variables (via AceDB-3.0),
    the baked weapon dataset, and slash commands.

    Built on the !AddonTemplate boilerplate. Every file in this addon receives:
        local addonName, ns = ...
    where `ns` is the shared private table.
]]

local addonName, ns = ...

-- ---------------------------------------------------------------------------
-- Saved variable defaults (AceDB profile)
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    profile = {
        debug   = false,
        minimap = { hide = false }, -- LibDBIcon stores its position here
    },
}

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
local PREFIX = "|cff33ff99" .. addonName .. "|r: " -- colored chat prefix

function ns.Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        print("|cffff9900" .. addonName .. " [debug]|r: " .. strjoin(" ", tostringall(...)))
    end
end

-- ns.WEAPONS is populated from the global written by Data\Weapons.lua (see below).
ns.WEAPONS = {}

-- ---------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame
ns.events = {}

function ns.events.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then return end

    -- AceDB gives us profile-aware SavedVariables + a table LibDBIcon can use.
    ns.aceDB = LibStub("AceDB-3.0"):New("WeaponProgDB", DEFAULTS, true)
    ns.db = ns.aceDB.profile

    -- Move the baked dataset (a global written by Data\Weapons.lua) into our
    -- namespace, then free the global so it can be garbage-collected. This is
    -- the same one-shot-import trick GatherMate2_Data uses.
    if WeaponProgData then
        ns.WEAPONS = WeaponProgData
        WeaponProgData = nil
    end

    local count = 0
    for _ in pairs(ns.WEAPONS) do count = count + 1 end
    ns.Debug("loaded", count, "weapons")

    frame:UnregisterEvent("ADDON_LOADED")
end

function ns.events.PLAYER_LOGIN()
    -- Feature modules register their own hooks; nothing required here beyond a
    -- friendly load message.
    ns.Print("loaded. Click the minimap button or type /wp to browse weapons.")
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = ns.events[event]
    if handler then handler(...) end
end)

for event in pairs(ns.events) do
    frame:RegisterEvent(event)
end

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------
SLASH_WEAPONPROG1 = "/weaponprog"
SLASH_WEAPONPROG2 = "/wp"
SlashCmdList["WEAPONPROG"] = function(msg)
    local cmd = strlower(strtrim(msg or ""))

    if cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("debug " .. (ns.db.debug and "on" or "off") .. ".")
    elseif cmd == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        local icon = LibStub("LibDBIcon-1.0", true)
        if icon then
            if ns.db.minimap.hide then icon:Hide(addonName) else icon:Show(addonName) end
        end
        ns.Print("minimap button " .. (ns.db.minimap.hide and "hidden" or "shown") .. ".")
    else
        -- Default action: open/close the browser.
        if ns.ToggleBrowser then
            ns.ToggleBrowser()
        else
            ns.Print("browser not available.")
        end
    end
end
