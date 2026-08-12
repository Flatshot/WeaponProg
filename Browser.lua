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

-- Persistent scroll state handed to the ScrollFrame each rebuild so an async
-- recolor doesn't snap the view back to the top. Reset only on a real tree
-- navigation (see showContent's `resetScroll`).
local scrollStatus = {}

-- Resolved rarity/quality colours, keyed by itemID. A 6-hex string once known,
-- or `false` for an item the client reports it can't resolve. Caching both means
-- we never re-call GetItemInfo (and so never re-fire its server request) for an
-- item we've already settled — which is what stops the recolor/rebuild loop.
local qualityCache = {}

-- Compute an item's quality colour as a 6-hex string, or nil if not yet cached.
-- GetItemInfo also *requests* the load for uncached items; GET_ITEM_INFO_RECEIVED
-- then resolves it once (see setQualityEvents / build).
local function computeQualityHex(itemID)
    local _, _, quality = GetItemInfo(itemID)
    if not quality then return nil end
    local r, g, b = GetItemQualityColor(quality)
    return string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Cached lookup used when building rows: returns a hex string, or nil while the
-- item is still unresolved. Never re-requests an item already settled in the cache.
local function qualityHex(itemID)
    local cached = qualityCache[itemID]
    if cached ~= nil then
        return cached or nil          -- `false` (unresolvable) -> nil, no re-request
    end
    local hex = computeQualityHex(itemID)
    if hex then qualityCache[itemID] = hex end  -- leave unresolved as nil for the event to settle
    return hex
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

-- resetScroll = true when the user actually navigates the tree (start at the top);
-- the async recolor path passes false so a rebuild keeps the current scroll offset.
local function showContent(container, index, path, resetScroll)
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
    -- Persist scroll offset across rebuilds. On real navigation start fresh at the
    -- top; on an async recolor rebuild keep the offset so the view doesn't jump.
    if resetScroll then wipe(scrollStatus) end
    scroll:SetStatusTable(scrollStatus)
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
    -- Each arrival is recorded in qualityCache *once* (colour on success, `false`
    -- on failure) so we never react to or re-request that item again — otherwise a
    -- single unresolvable itemID would re-fire this event every rebuild forever.
    if not qualityEventFrame then
        qualityEventFrame = CreateFrame("Frame")
        qualityEventFrame:SetScript("OnEvent", function(_, _, itemID, success)
            if not itemID or not currentIDs[itemID] then return end
            if qualityCache[itemID] ~= nil then return end   -- already settled; ignore
            qualityCache[itemID] = (success and computeQualityHex(itemID)) or false
            scheduleRefresh()                                -- one refresh per newly-settled item
        end)
    end
    setQualityEvents(true)

    local tree = AceGUI:Create("TreeGroup")
    tree:SetTree(buildTree(index))
    tree:SetLayout("Fill")
    tree:SetCallback("OnGroupSelected", function(container, _, path)
        showContent(container, index, path, true)  -- navigation: reset scroll to top
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
