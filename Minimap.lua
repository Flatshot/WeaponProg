--[[
    WeaponProg - Minimap.lua

    Creates the minimap button ("dongle") via LibDataBroker + LibDBIcon.
    Left-click opens the weapon browser.
]]

local addonName, ns = ...

local function setup()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not (LDB and LDBIcon) then
        ns.Debug("LibDataBroker/LibDBIcon missing; no minimap button")
        return
    end

    local dataobj = LDB:NewDataObject(addonName, {
        type  = "launcher",
        icon  = "Interface\\ICONS\\INV_Sword_04",
        label = "WeaponProg",
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.db.minimap.hide = true
                LDBIcon:Hide(addonName)
                ns.Print("minimap button hidden. Use /wp minimap to bring it back.")
            else
                ns.ToggleBrowser()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(ns.Colorize("33ff99", "WeaponProg"))
            tooltip:AddLine(ns.Colorize("ffffff", "Left-click: ") .. "browse weapons by type & level")
            tooltip:AddLine(ns.Colorize("ffffff", "Right-click: ") .. "hide this button")
        end,
    })

    LDBIcon:Register(addonName, dataobj, ns.db.minimap)
    ns.Debug("minimap button registered")
end

-- Register after login, once AceDB (ns.db.minimap) exists.
ns.events = ns.events or {}
local prevLogin = ns.events.PLAYER_LOGIN
ns.events.PLAYER_LOGIN = function(...)
    if prevLogin then prevLogin(...) end
    setup()
end
