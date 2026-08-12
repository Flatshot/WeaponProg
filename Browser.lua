--[[
    WeaponProg - Browser.lua

    A browsable window (opened from the minimap button or /wp) that lists weapons
    grouped by weapon type -> required-level bracket, showing the same origin info
    as the tooltip. Built with AceGUI-3.0's TreeGroup widget.
]]

local _, ns = ...
local AceGUI = LibStub("AceGUI-3.0")

local BRACKET_SIZE = 10

-- Browser view state, module-level so the async recolor handler can reach it.
local currentView       -- { container, index, path } of the panel on screen
local currentIDs = {}   -- set of itemIDs currently displayed
local refreshPending = false
local qualityEventFrame

-- Rarity/quality colour for an item, as a 6-hex string suitable for ns.Colorize.
-- Returns nil until the item's data is cached; GetItemInfo also requests the load,
-- and GET_ITEM_INFO_RECEIVED then drives a recolor (see setQualityEvents / build).
local function qualityHex(itemID)
    local _, _, quality = GetItemInfo(itemID)
    if not quality then return nil end
    local r, g, b = GetItemQualityColor(quality)
    return string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function bracketIndex(req)
    return math.floor((math.max(req, 1) - 1) / BRACKET_SIZE)
end

local function bracketLabel(idx)
    return (idx * BRACKET_SIZE + 1) .. "-" .. (idx * BRACKET_SIZE + BRACKET_SIZE)
end

-- Build { typeKey = { [bracketIdx] = { {id=, rec=}, ... } } } from ns.WEAPONS.
local function buildIndex()
    local index = {}
    for id, rec in pairs(ns.WEAPONS) do
        local t = rec.type or "UNKNOWN"
        index[t] = index[t] or {}
        local b = bracketIndex(rec.req or 1)
        index[t][b] = index[t][b] or {}
        table.insert(index[t][b], { id = id, rec = rec })
    end
    return index
end

-- Turn the index into the nested table AceGUI TreeGroup expects.
local function buildTree(index)
    local tree = {}
    for _, typeKey in ipairs(ns.WEAPON_TYPE_ORDER) do
        local buckets = index[typeKey]
        if buckets then
            local count = 0
            local children, bIdxs = {}, {}
            for b in pairs(buckets) do table.insert(bIdxs, b) end
            table.sort(bIdxs)
            for _, b in ipairs(bIdxs) do
                count = count + #buckets[b]
                table.insert(children, {
                    value = "b" .. b,
                    text  = "Lvl " .. bracketLabel(b) .. " (" .. #buckets[b] .. ")",
                })
            end
            table.insert(tree, {
                value    = typeKey,
                text     = (ns.WEAPON_TYPE_LABEL[typeKey] or typeKey) .. " (" .. count .. ")",
                children = children,
            })
        end
    end
    return tree
end

-- Collect the {id, rec} entries to display for a selected tree path.
local function collect(index, typeKey, bIdx)
    local out = {}
    local buckets = index[typeKey]
    if not buckets then return out end
    if bIdx then
        for _, e in ipairs(buckets[bIdx] or {}) do table.insert(out, e) end
    else
        for _, list in pairs(buckets) do
            for _, e in ipairs(list) do table.insert(out, e) end
        end
    end
    table.sort(out, function(a, b) return (a.rec.req or 0) < (b.rec.req or 0) end)
    return out
end

local function makeRow(scroll, entry)
    local rec = entry.rec
    local src = ns.GetSourceInfo(rec.src)
    local icon = (GetItemIcon and GetItemIcon(entry.id)) or src.icon

    local row = AceGUI:Create("InteractiveLabel")
    row:SetFullWidth(true)
    row:SetImage(icon)
    row:SetImageSize(20, 20)
    currentIDs[entry.id] = true
    local qhex = qualityHex(entry.id)  -- nil until cached; async handler recolors later

    -- Quest labels take the faction colour (Alliance blue / Horde red); both-faction
    -- and non-quest labels keep the source's own colour.
    local labelColor = src.color
    if rec.src == "QUEST" and rec.faction then
        labelColor = ns.QUEST_FACTION_COLOR[rec.faction] or src.color
    end

    row:SetText(
        ns.Colorize(qhex or "ffffff", rec.name or ("item:" .. entry.id))
        .. "   " .. ns.Colorize("aaaaaa", "Req Lvl " .. (rec.req or "?"))
        .. "   " .. ns.Colorize(labelColor, src.label)
    )
    row:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. entry.id)
        GameTooltip:Show()
    end)
    row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    scroll:AddChild(row)
end

local frame -- singleton AceGUI Frame

local function showContent(container, index, path)
    container:ReleaseChildren()

    -- Remember what's on screen so the async quality-recolor handler can rebuild it.
    currentView = { container = container, index = index, path = path }
    wipe(currentIDs)

    -- path is "typeKey" or "typeKey\001b<idx>"
    local typeKey, bTag = strsplit("\001", path)
    local bIdx = bTag and tonumber((bTag:gsub("^b", "")))

    -- Single child (the scroll) so the container's "Fill" layout gives it the
    -- whole content area; the heading lives as the first row inside the scroll.
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    container:AddChild(scroll)

    local heading = AceGUI:Create("Label")
    heading:SetFullWidth(true)
    heading:SetFontObject(GameFontNormalLarge)
    heading:SetText(ns.WEAPON_TYPE_LABEL[typeKey] or typeKey)
    scroll:AddChild(heading)

    local entries = collect(index, typeKey, bIdx)
    if #entries == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText(ns.Colorize("888888", "No weapons in this category yet."))
        scroll:AddChild(empty)
    else
        for _, e in ipairs(entries) do makeRow(scroll, e) end
    end
end

-- Rebuild the visible panel (debounced) so items whose data just arrived pick up
-- their quality colour. Re-running showContent avoids stashing pooled widget refs.
local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.15, function()
        refreshPending = false
        if frame and frame:IsShown() and currentView then
            showContent(currentView.container, currentView.index, currentView.path)
        end
    end)
end

-- Listen for item-data loads only while the browser is open.
local function setQualityEvents(on)
    if not qualityEventFrame then return end
    if on then
        qualityEventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        qualityEventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function build()
    local index = buildIndex()

    frame = AceGUI:Create("Frame")
    frame:SetTitle("WeaponProg")
    frame:SetStatusText("Weapon origins — grouped by type and required level")
    frame:SetLayout("Fill")
    frame:SetWidth(640)
    frame:SetHeight(460)
    frame:SetCallback("OnClose", function(widget)
        setQualityEvents(false)
        widget:Hide()
    end)

    -- Hidden frame that recolors rows as item data streams in from the server.
    if not qualityEventFrame then
        qualityEventFrame = CreateFrame("Frame")
        qualityEventFrame:SetScript("OnEvent", function(_, _, itemID)
            if itemID and currentIDs[itemID] then scheduleRefresh() end
        end)
    end
    setQualityEvents(true)

    local tree = AceGUI:Create("TreeGroup")
    tree:SetTree(buildTree(index))
    tree:SetLayout("Fill")
    tree:SetCallback("OnGroupSelected", function(container, _, path)
        showContent(container, index, path)
    end)
    frame:AddChild(tree)

    -- Select the first type by default so the panel isn't blank.
    if ns.WEAPON_TYPE_ORDER[1] then
        for _, typeKey in ipairs(ns.WEAPON_TYPE_ORDER) do
            if index[typeKey] then tree:SelectByPath(typeKey); break end
        end
    end

    frame.__tree = tree
end

function ns.ToggleBrowser()
    if not frame then
        build()
        return
    end
    if frame:IsShown() then
        setQualityEvents(false)
        frame:Hide()
    else
        frame:Show()
        setQualityEvents(true)
    end
end
