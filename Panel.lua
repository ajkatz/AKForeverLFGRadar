-- Panel: the radar on the screen. A small movable frame in Blizzard's tooltip look: the picked dungeon (click
-- it for the list), your own distance, everyone heard from over the channel nearest first - their distance
-- to YOUR pick, their own pick as a tag when it differs -, then the group finder's listings for the dungeon
-- sorted by proximity and role, and the Refresh button. A right-click on anybody invites them. Nothing
-- secure is on it: Refresh is an ordinary button whose click is the key press the finder's search needs.
-- It docks beside the finder window while that is open.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH, PAD, ROW, GAP = 290, 8, 14, 2
local WHERE_WIDTH = 130 -- the right column's cap, so a long whereabouts never runs into the name
local MAX_PEERS = 12
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local panel, title, note, pickButton, picker, youText, refreshButton, refreshNote, footer, emptyLine, closeButton, lookupNote
local peerRows, pickerRows, listedRows, listedHeaders = {}, {}, {}, {}
local docked = false
local closedWhileDocked = false -- the X while beside the finder: away until the finder is opened again
Panel.rows = peerRows       -- read by the tests
Panel.pickerRows = pickerRows
Panel.listedRows = listedRows
Panel.listedHeaders = listedHeaders

-- the finder's own role symbols, inline (the micro atlases its browse rows use)
local ROLE_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps" }
local function roleIcon(role)
    local atlas = ROLE_ATLAS[role or ""]
    if not atlas then
        return "|cff555555-|r"
    end
    return "|A:" .. atlas .. ":0:0|a"
end

-- a group: one symbol per member in the slot they fill, tanks first; a person alone: the roles they offer
local function roleText(entry)
    local parts = {}
    if entry.members > 1 then
        for _, role in ipairs(entry.composition or {}) do
            parts[#parts + 1] = roleIcon(role)
        end
    else
        local roles = entry.roles or {}
        if roles.tank then parts[#parts + 1] = roleIcon("TANK") end
        if roles.healer then parts[#parts + 1] = roleIcon("HEALER") end
        if roles.dps then parts[#parts + 1] = roleIcon("DAMAGER") end
    end
    if #parts == 0 then
        return roleIcon(nil)
    end
    return table.concat(parts)
end

-- the listing's playstyle, dim, after the name - the finder's own word for it
local function styleText(entry)
    return entry.playstyle and ("  |cff999999" .. entry.playstyle .. "|r") or ""
end

local function classColor(class)
    local colors = type(RAID_CLASS_COLORS) == "table" and class and RAID_CLASS_COLORS[class] or nil
    if type(colors) == "table" then
        if type(colors.colorStr) == "string" then
            return "|c" .. colors.colorStr
        elseif type(colors.r) == "number" then
            return string.format("|cff%02x%02x%02x", math.floor(colors.r * 255), math.floor(colors.g * 255), math.floor(colors.b * 255))
        end
    end
    return "|cffffffff"
end

local function invite(name)
    if not name then
        return
    end
    local fn = (type(C_PartyInfo) == "table" and C_PartyInfo.InviteUnit) or InviteUnit
    if type(fn) ~= "function" then
        ns:Print("this client gives no way to invite from here.")
        return
    end
    local ok, err = pcall(fn, name)
    if ok then
        ns:Print("invited " .. name .. ".")
        ns:Log("invite", name)
    else
        ns:Print("could not invite " .. name .. ": " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- Position on the screen, per character
------------------------------------------------------------------------
local function savePosition()
    if not panel or not ns.cdb then
        return
    end
    if docked then
        return -- a place beside the finder is the finder's, not yours
    end
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    if ns.AnySecret(point, relativePoint, x, y) or type(x) ~= "number" then
        return
    end
    ns.cdb.panel = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition()
    panel:ClearAllPoints()
    local saved = ns.cdb and ns.cdb.panel
    if saved and type(saved.x) == "number" and type(saved.y) == "number" then
        panel:SetPoint(saved.point or "TOPLEFT", UIParent, saved.relativePoint or "TOPLEFT", saved.x, saved.y)
    else
        panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -220)
    end
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function showPersonTooltip(row)
    local who = row.peer or row.listed
    if not who then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(who.name)
    if row.listed then
        local entry = row.listed
        GameTooltip:AddLine("Listed in the group finder for " .. (entry.dungeon and entry.dungeon.name or "?") .. (entry.members > 1 and (", a group of " .. entry.members) or "")
            .. (entry.playstyle and (" - " .. entry.playstyle) or ""), 1, 0.82, 0, true)
        local sources = { addon = "runs the addon: measured", listing = "the listing names the area", who = "a /who of ours found them", none = "no area named yet - a /who goes out on your next key press" }
        for _, member in ipairs(entry.people or {}) do
            GameTooltip:AddDoubleLine(roleIcon(member.role) .. " " .. classColor(member.class) .. (member.name or "?") .. "|r" .. (member.level and (" " .. member.level) or ""),
                member.proximity.text .. (member.source == "addon" and "" or " ~"), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        if entry.members > 1 then
            GameTooltip:AddLine("Together: " .. entry.proximity.text, 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine(sources[entry.source] or "", 0.6, 0.6, 0.6, true)
        end
    elseif row.peer then
        local peer = row.peer
        local theirs = peer.dungeon and ns.Dungeons:Get(peer.dungeon)
        GameTooltip:AddLine(((peer.class and (classColor(peer.class) .. peer.class .. "|r ")) or "") .. (peer.level and ("level " .. peer.level) or ""), 1, 1, 1)
        if peer.zone then
            GameTooltip:AddLine("In " .. peer.zone, 1, 1, 1)
        end
        GameTooltip:AddLine("Heading for " .. (theirs and theirs.name or "nothing picked"), 1, 0.82, 0)
        GameTooltip:AddLine("Heard " .. math.floor(GetTime() - peer.at) .. " s ago", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Right-click: invite", 0.5, 1, 0.5)
    GameTooltip:Show()
end

local function createRow(list, index, prefix)
    local row = CreateFrame("Button", "AKForeverLFGRadar" .. prefix .. index, panel)
    row:SetSize(WIDTH - 2 * PAD, ROW)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.where:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.where:SetJustifyH("RIGHT")
    row.where:SetWordWrap(false)
    row.name:SetPoint("RIGHT", row.where, "LEFT", -6, 0)
    row.name:SetPoint("TOP", row, "TOP", 0, 0)
    row.name:SetHeight(ROW)
    row.where:SetHeight(ROW)
    -- a group's second line: its role symbols and where the rest of it is
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -ROW)
    row.detail:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.detail:Hide()
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            invite((self.peer or self.listed or {}).name)
        end
    end)
    row:SetScript("OnEnter", showPersonTooltip)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    list[index] = row
    return row
end

local function dimLine(parent)
    local line = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    line:SetWidth(WIDTH - 2 * PAD)
    return line
end

------------------------------------------------------------------------
-- The picker: the dungeon list under the pick button
------------------------------------------------------------------------
local function pickerRow(index)
    local row = pickerRows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, picker)
    row:SetSize(WIDTH - 2 * PAD - 12, ROW)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.text:SetJustifyH("LEFT")
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnClick", function(self)
        ns.Dungeons:Pick(self.dungeon, "click")
        picker:Hide()
    end)
    pickerRows[index] = row
    return row
end

local function createPicker()
    picker = CreateFrame("Frame", "AKForeverLFGRadarPicker", panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    picker:SetFrameStrata("DIALOG")
    picker:SetWidth(WIDTH - 2 * PAD)
    picker:SetPoint("TOPLEFT", pickButton, "BOTTOMLEFT", 0, -2)
    if type(picker.SetBackdrop) == "function" then
        picker:SetBackdrop(BACKDROP)
        picker:SetBackdropColor(0.05, 0.05, 0.12, 0.97)
    end
    picker:Hide()
    local none = CreateFrame("Button", nil, picker)
    none:SetSize(WIDTH - 2 * PAD - 12, ROW)
    none.text = none:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    none.text:SetPoint("LEFT", none, "LEFT", 2, 0)
    none.text:SetText("none")
    none:SetScript("OnClick", function()
        ns.Dungeons:Pick(nil, "click")
        picker:Hide()
    end)
    pickerRows.none = none
end

-- the list as it stands - lowest level range first, coloured against your level as the finder colours its
-- own - laid out anew each time: the finder's table may have grown since
local function refreshPicker()
    if not picker or not picker:IsShown() then
        return
    end
    local counts = ns.Net:CountsByDungeon()
    local picked = ns.Dungeons:Picked()
    local y = -6
    for index, dungeon in ipairs(ns.Dungeons.list) do
        local row = pickerRow(index)
        row.dungeon = dungeon
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, y)
        row.text:SetText((picked == dungeon and "|cffffd100> |r" or "") .. (dungeon.parentKey and "    " or "") .. ns.Dungeons:LevelColor(dungeon) .. ns.Dungeons:ShortName(dungeon) .. "|r  |cff999999" .. string.lower(dungeon.tag)
            .. (dungeon.levels and (" " .. dungeon.levels) or "") .. "|r")
        local count = counts[dungeon.key] or 0
        for _, wing in ipairs(dungeon.wings or {}) do
            count = count + (counts[wing.key] or 0) -- heading for a wing is heading for the instance
        end
        row.count:SetText(count > 0 and (count .. " heading there") or "")
        row:Show()
        y = y - ROW
    end
    for index = #ns.Dungeons.list + 1, #pickerRows do
        pickerRows[index]:Hide()
    end
    local none = pickerRows.none
    none:ClearAllPoints()
    none:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, y)
    picker:SetHeight(-y + ROW + 6)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function ageText(seconds)
    if seconds < 60 then
        return seconds .. " s ago"
    end
    return math.floor(seconds / 60) .. " min ago"
end

function Panel:Refresh()
    if not panel then
        return
    end
    local dungeon = ns.Dungeons:Picked()
    local peerCount = ns.Net:PeerCount()
    note:SetText(peerCount > 0 and (peerCount .. " with the addon") or "")
    local y = -(PAD - 2) - 16

    pickButton:SetText(dungeon and (ns.Dungeons:LevelColor(dungeon) .. dungeon.name .. "|r" .. (dungeon.levels and ("  |cff999999" .. dungeon.levels .. "|r") or "") .. "  |cff999999v|r")
        or "|cffffd100pick a dungeon|r  |cff999999v|r")
    pickButton:ClearAllPoints()
    pickButton:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    y = y - 20

    local mine = ns.Position:Mine()
    youText:SetText("|cffffd100You:|r " .. mine.text .. (ns.LFG.ownPlaystyle and ("  |cff999999listed " .. ns.LFG.ownPlaystyle .. "|r") or ""))
    youText:ClearAllPoints()
    youText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    y = y - ROW - GAP

    local list = ns.Net:Peers(dungeon)
    for index = 1, MAX_PEERS do
        local row = peerRows[index] or createRow(peerRows, index, "Peer")
        local item = list[index]
        if item then
            local peer = item.peer
            row.peer, row.who = peer, nil
            row.name:SetText(classColor(peer.class) .. peer.name .. "|r" .. (peer.level and (" |cff999999" .. peer.level .. "|r") or ""))
            local tag = ""
            if peer.dungeon and (not dungeon or peer.dungeon ~= dungeon.key) then
                local theirs = ns.Dungeons:Get(peer.dungeon)
                tag = theirs and (" |cff999999> " .. theirs.tag .. "|r") or ""
            end
            local age = item.age >= 30 and (" |cff777777" .. math.floor(item.age) .. "s|r") or ""
            row.where:SetText(item.proximity.text .. tag .. age)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
            row:Show()
            y = y - ROW - GAP
        else
            row.peer = nil
            row:Hide()
        end
    end
    emptyLine:ClearAllPoints()
    emptyLine:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    if #list == 0 then
        emptyLine:SetText(ns.Net.channelID and "nobody else heard from yet" or "joining the channel...")
        emptyLine:Show()
        y = y - ROW - GAP
    elseif #list > MAX_PEERS then
        emptyLine:SetText("+" .. (#list - MAX_PEERS) .. " more")
        emptyLine:Show()
        y = y - ROW - GAP
    else
        emptyLine:Hide()
    end

    -- the group finder's list for this dungeon: the groups, then the players, each sorted by proximity and role
    local listedShown = 0
    local function listedRow()
        listedShown = listedShown + 1
        return listedRows[listedShown] or createRow(listedRows, listedShown, "Listed")
    end
    local function placeRow(row, tall)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        row:SetHeight(tall and 2 * ROW or ROW)
        row.detail:SetShown(tall and true or false)
        -- the right column sizes to its text, up to a cap; past it the text is cut with "..." (the name takes the rest)
        row.where:SetWidth(0)
        if row.where:GetStringWidth() > WHERE_WIDTH then
            row.where:SetWidth(WHERE_WIDTH)
        end
        row:Show()
        y = y - (tall and 2 * ROW or ROW)
    end
    for section = 1, 2 do
        local header = listedHeaders[section]
        if not header then
            header = dimLine(panel)
            listedHeaders[section] = header
        end
        if dungeon then
            local wantGroups = section == 1
            local entries = {}
            for _, entry in ipairs(ns.LFG.listed) do
                if (entry.members > 1) == wantGroups then
                    entries[#entries + 1] = entry
                end
            end
            header:SetText((wantGroups and "Groups" or "Players") .. " listed in the group finder - " .. #entries)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
            header:Show()
            y = y - ROW
            for index = 1, math.min(#entries, MAX_PEERS) do
                local row = listedRow()
                local entry = entries[index]
                row.listed, row.peer = entry, nil
                local guess = entry.source == "addon" and "" or (entry.source == "none" and "" or " |cff777777~|r")
                if wantGroups then
                    -- a group, on two lines: the leader and the size, where most of it is; then its role symbols
                    -- (one per member, tanks first) and where the rest is
                    row.name:SetText("  " .. classColor(entry.class) .. entry.name .. "|r" .. (entry.level and (" |cff999999" .. entry.level .. "|r") or "")
                        .. " |cffffd100+" .. (entry.members - 1) .. "|r" .. styleText(entry))
                    row.where:SetText((entry.proximity.short or entry.proximity.text) .. guess)
                    row.detail:SetText(roleText(entry) .. ((entry.proximity.rest and entry.proximity.rest ~= "") and ("  " .. entry.proximity.rest) or ""))
                else
                    row.name:SetText("  " .. roleText(entry) .. " " .. classColor(entry.class) .. entry.name .. "|r" .. (entry.level and (" |cff999999" .. entry.level .. "|r") or "") .. styleText(entry))
                    row.where:SetText(entry.proximity.text .. guess)
                    row.detail:SetText("")
                end
                placeRow(row, wantGroups)
            end
            if #entries == 0 then
                local row = listedRow()
                row.listed, row.peer = nil, nil
                row.name:SetText(ns.LFG.stats.results > 0 and ("  |cff777777no " .. (wantGroups and "groups" or "players") .. " for this dungeon|r")
                    or "  |cff777777no search yet - open the finder, or click Refresh|r")
                row.where:SetText("")
                row.detail:SetText("")
                placeRow(row, false)
            end
            y = y - GAP
        else
            header:Hide()
        end
    end
    for index = listedShown + 1, #listedRows do
        listedRows[index].listed = nil
        listedRows[index]:Hide()
    end
    -- the members still unplaced: what the lookups are doing
    lookupNote:ClearAllPoints()
    lookupNote:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    local lookups = dungeon and ns.Lookup:Describe() or nil
    if lookups and lookups.pending then
        lookupNote:SetText("asking /who about " .. lookups.pending.name .. "...")
        lookupNote:Show()
        y = y - ROW
    elseif lookups and lookups.waiting > 0 then
        lookupNote:SetText(lookups.waiting .. " unplaced: a /who each rides on your key presses" .. (lookups.stats.armProblem and (" (" .. lookups.stats.armProblem .. ")") or ""))
        lookupNote:Show()
        y = y - ROW
    else
        lookupNote:Hide()
    end

    -- the Refresh button: the finder's list for this dungeon, searched afresh (a click: the search is restricted)
    refreshButton:ClearAllPoints()
    refreshButton:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y - 2)
    refreshNote:ClearAllPoints()
    refreshNote:SetPoint("LEFT", refreshButton, "RIGHT", 6, 0)
    refreshNote:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    local browseOpen = ns.LFG:BrowseOpen()
    refreshButton:SetEnabled(dungeon ~= nil)
    if not dungeon then
        refreshNote:SetText("pick a dungeon first")
    elseif browseOpen then
        refreshNote:SetText("the finder's own refresh")
    elseif ns.LFG.stats.lastSearchAt and GetTime() - ns.LFG.stats.lastSearchAt < 5 then
        refreshNote:SetText("asking the finder...")
    else
        refreshNote:SetText("asks the group finder for its list")
    end
    y = y - 24

    -- the footer
    footer:ClearAllPoints()
    footer:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    if not ns:GetOption("share") then
        footer:SetText("sharing off - the others cannot see you (/dr share on)")
    elseif not ns.Net.channelID then
        footer:SetText("channel not joined yet")
    else
        footer:SetText("")
    end
    if footer:GetText() ~= "" then
        y = y - ROW
    end

    panel:SetHeight(-y + PAD)
    refreshPicker()
end

-- Every second: beside the finder while it is open - and shown with it, gone with it - or on its own where
-- you put it, when asked for ('/dr show').
function Panel:Tick()
    if not panel then
        return
    end
    local dock = ns.LFG:DockTarget()
    if dock and not docked then
        -- clear of the tabs hanging off the finder's right edge (wider on this flavour: measured, not assumed)
        local tab = dock.ListingTab
        local width = type(tab) == "table" and ns.Readable(tab.GetWidth, tab) or nil
        width = (width and type(width[1]) == "number" and width[1] > 0) and width[1] or 48
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", dock, "TOPRIGHT", width + 8, -12)
        docked = true
    elseif not dock and docked then
        docked = false
        closedWhileDocked = false
        restorePosition()
    end
    local wanted
    if docked then
        wanted = not closedWhileDocked
    else
        wanted = ns:GetOption("shown") and true or false
    end
    if panel:IsShown() ~= wanted then
        panel:SetShown(wanted)
        if not wanted and picker then
            picker:Hide()
        end
    end
    if wanted then
        self:Refresh()
    end
end

function Panel:IsDocked()
    return docked
end

-- the X: beside the finder, away until the finder is opened again; on its own, away until '/dr show'
function Panel:Close()
    if docked then
        closedWhileDocked = true
    else
        ns.db.options.shown = false
    end
    if panel then
        panel:Hide()
    end
    if picker then
        picker:Hide()
    end
    ns:Log("panel_closed", docked and "docked" or "free")
end

local refreshQueued = false
function Panel:RequestRefresh()
    if refreshQueued or not panel then
        return
    end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        ns.SafeCall(Panel.Refresh, Panel)
    end)
end

function Panel:SetShown(shown)
    if not panel then
        return
    end
    if shown then
        closedWhileDocked = false
    end
    panel:SetShown(shown)
    if not shown and picker then
        picker:Hide()
    end
    if shown then
        self:Refresh()
    end
end

function Panel:Describe()
    local point, _, relativePoint, x, y
    if panel then
        point, _, relativePoint, x, y = panel:GetPoint(1)
    end
    local shownPeers = 0
    for _, row in ipairs(peerRows) do
        if row:IsShown() then
            shownPeers = shownPeers + 1
        end
    end
    return { shown = panel and panel:IsShown() or false, point = point, relativePoint = relativePoint, x = x, y = y, peersShown = shownPeers, height = panel and panel:GetHeight() }
end

------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------
local function create()
    panel = CreateFrame("Frame", "AKForeverLFGRadarPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetWidth(WIDTH)
    panel:SetHeight(80)
    panel:SetFrameStrata("MEDIUM")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    if type(panel.SetBackdrop) == "function" then
        panel:SetBackdrop(BACKDROP)
        panel:SetBackdropColor(0.09, 0.09, 0.19, 0.92)
        panel:SetBackdropBorderColor(1, 1, 1, 1)
    end
    restorePosition()

    closeButton = CreateFrame("Button", "AKForeverLFGRadarClose", panel, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", function()
        Panel:Close()
    end)

    note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD - 20, -(PAD - 2))
    note:SetJustifyH("RIGHT")
    title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD - 2))
    title:SetJustifyH("LEFT")
    title:SetText("LFG Radar")

    pickButton = CreateFrame("Button", "AKForeverLFGRadarPick", panel)
    pickButton:SetSize(WIDTH - 2 * PAD, 18)
    pickButton:SetNormalFontObject("GameFontHighlight")
    pickButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    pickButton:SetScript("OnClick", function()
        if not picker then
            createPicker()
        end
        picker:SetShown(not picker:IsShown())
        refreshPicker()
    end)
    if pickButton.GetFontString and pickButton:GetFontString() then
        pickButton:GetFontString():SetJustifyH("LEFT")
        pickButton:GetFontString():SetPoint("LEFT", pickButton, "LEFT", 2, 0)
    end

    youText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    youText:SetJustifyH("LEFT")
    youText:SetWordWrap(false)
    youText:SetWidth(WIDTH - 2 * PAD)

    emptyLine = dimLine(panel)

    refreshButton = CreateFrame("Button", "AKForeverLFGRadarRefresh", panel, "UIPanelButtonTemplate")
    refreshButton:SetSize(72, 20)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        local ok, why = ns.LFG:Refresh()
        if not ok then
            ns:Print("no refresh: " .. tostring(why))
        end
        ns.Lookup:Ask("click") -- a click is a key press too: the next unplaced member's /who goes with it
        Panel:RequestRefresh()
    end)
    refreshNote = dimLine(panel)
    lookupNote = dimLine(panel)

    footer = dimLine(panel)

    panel:SetShown(ns:GetOption("shown") and true or false)
    Panel:Tick()
    C_Timer.NewTicker(1, function()
        ns.SafeCall(Panel.Tick, Panel)
    end)
    if ns.cdb and not ns.cdb.hinted then
        ns.cdb.hinted = true
        ns:Print("open the group finder and the radar sits beside it; |cffffd100/dr <dungeon>|r picks one, |cffffd100/dr show|r keeps the panel up on its own.")
    end
end

ns:Listen("LOGIN", create)

for _, message in ipairs({ "PEERS_CHANGED", "PICK_CHANGED", "POSITION_CHANGED", "NET_CHANGED", "ENTRANCES_CHANGED", "LFG_CHANGED", "LOOKUP_CHANGED" }) do
    ns:Listen(message, function()
        Panel:RequestRefresh()
    end)
end

ns:Listen("OPTION_CHANGED", function(key, value)
    if key == "shown" then
        Panel:SetShown(value)
    end
    Panel:RequestRefresh()
end)

ns:RegisterCommand("show", "the panel on its own, finder open or closed", function()
    ns:SetOption("shown", true)
    Panel:SetShown(true)
end)

ns:RegisterCommand("hide", "the panel away until '/dr show' or the next time the finder opens (the channel stays, the others still see you)", function()
    ns:SetOption("shown", false)
    Panel:Close()
end)

ns:RegisterCommand("reset", "the panel back to its first place", function()
    ns.cdb.panel = nil
    if panel then
        restorePosition()
    end
end)
