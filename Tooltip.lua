--[[
    WeaponProg - Tooltip.lua

    Adds origin lines ("WeaponProg: <source>") to weapon tooltips on mouseover.

    Uses the modern TooltipDataProcessor API when present (current Classic Era
    clients) and falls back to the legacy OnTooltipSetItem hook otherwise. This
    dual-path shape follows BagBrother\core\features\itemTooltips.lua.
]]

local _, ns = ...

-- Pull the itemID out of an item link/string, e.g. "...|Hitem:19019:0:..."
local function itemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Append our lines. Guarded so repeated OnTooltipSetItem fires don't stack up.
local function addLines(tooltip, itemID)
    local rec = ns.GetWeaponInfo(itemID)
    if not rec then return end

    -- De-dup: skip if we've already decorated this exact tooltip for this item.
    if tooltip.__weaponProgItem == itemID then return end
    tooltip.__weaponProgItem = itemID

    local src = ns.GetSourceInfo(rec.src)
    -- Quest source takes the faction colour (Alliance blue / Horde red); both-faction
    -- and non-quest sources keep the source's own colour. Mirrors the browser.
    local labelColor = src.color
    if rec.src == "QUEST" and rec.faction then
        labelColor = ns.QUEST_FACTION_COLOR[rec.faction] or src.color
    end
    tooltip:AddLine(" ") -- spacer
    tooltip:AddLine(ns.Colorize("33ff99", "WeaponProg") .. ": " .. ns.Colorize(labelColor, src.label))
    if rec.detail and rec.detail ~= "" then
        tooltip:AddLine(ns.Colorize("cccccc", rec.detail), nil, nil, nil, true) -- wrap = true
    end
    tooltip:Show() -- re-fit the tooltip to the new lines
end

-- Extract the displayed item from a tooltip across API versions.
local function onItem(tooltip)
    if not tooltip or tooltip:IsForbidden() then return end
    local getItem = tooltip.GetItem or (TooltipUtil and TooltipUtil.GetDisplayedItem)
    if not getItem then return end
    local _, link = getItem(tooltip)
    addLines(tooltip, itemIDFromLink(link))
end

local function onClear(tooltip)
    tooltip.__weaponProgItem = nil
end

local function install()
    if C_TooltipInfo and TooltipDataProcessor and Enum and Enum.TooltipDataType then
        -- Modern path: one post-call for every item tooltip.
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
        -- Still clear our guard when the tooltip is wiped.
        if GameTooltip.HookScript then
            GameTooltip:HookScript("OnTooltipCleared", onClear)
        end
    else
        -- Legacy path: hook mouseover (GameTooltip) and links (ItemRefTooltip).
        GameTooltip:HookScript("OnTooltipSetItem", onItem)
        GameTooltip:HookScript("OnTooltipCleared", onClear)
        if ItemRefTooltip then
            ItemRefTooltip:HookScript("OnTooltipSetItem", onItem)
            ItemRefTooltip:HookScript("OnTooltipCleared", onClear)
        end
    end
    ns.Debug("tooltip hook installed")
end

-- Install after login so all tooltip frames exist.
ns.events = ns.events or {}
local prevLogin = ns.events.PLAYER_LOGIN
ns.events.PLAYER_LOGIN = function(...)
    if prevLogin then prevLogin(...) end
    install()
end
