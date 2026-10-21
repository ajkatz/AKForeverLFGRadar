-- A small stand-in for the WoW: Forever client, enough to run AKForeverLFGRadar's scenarios: frames,
-- events, timers, a world of zones with yards, instances, a chat channel with peers, the who API behind a
-- key press, and the secret-value rules. Nothing here is the real client; what the real client does with
-- auras, who queries and channels was measured in game and is written in the addon's comments.
local Mock = {}

local realPrint = print
Mock.realPrint = realPrint

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
Mock.SECRET = SECRET

local G = _G

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local widgetMethods = {}

function widgetMethods.SetPoint(self, point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "number" then -- SetPoint(point, x, y)
        point, relativeTo, relativePoint, x, y = point, self.__parent, point, relativeTo, relativePoint
    elseif type(relativeTo) == "string" then
        relativeTo, relativePoint, x, y = self.__parent, relativeTo, relativePoint, x
    end
    self.__points[#self.__points + 1] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end
function widgetMethods.ClearAllPoints(self) self.__points = {} end
function widgetMethods.GetPoint(self, index)
    local p = self.__points[index or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function widgetMethods.GetNumPoints(self) return #self.__points end
function widgetMethods.SetSize(self, w, h) self.__width, self.__height = w, h end
function widgetMethods.SetWidth(self, w) self.__width = w end
function widgetMethods.SetHeight(self, h) self.__height = h end
function widgetMethods.GetWidth(self) return self.__width or 0 end
function widgetMethods.GetHeight(self) return self.__height or 0 end
function widgetMethods.GetSize(self) return self.__width or 0, self.__height or 0 end
function widgetMethods.Show(self) self.__shown = true; local s = self.__scripts.OnShow; if s then s(self) end end
function widgetMethods.Hide(self) self.__shown = false; local s = self.__scripts.OnHide; if s then s(self) end end
function widgetMethods.SetShown(self, shown) if shown then self:Show() else self:Hide() end end
function widgetMethods.IsShown(self) return self.__shown end
function widgetMethods.IsVisible(self)
    local w = self
    while w do
        if not w.__shown then return false end
        w = w.__parent
    end
    return true
end
function widgetMethods.SetScript(self, name, fn) self.__scripts[name] = fn end
function widgetMethods.GetScript(self, name) return self.__scripts[name] end
function widgetMethods.HookScript(self, name, fn)
    local old = self.__scripts[name]
    self.__scripts[name] = function(...) if old then old(...) end fn(...) end
end
function widgetMethods.RegisterEvent(self, event) self.__events[event] = true end
function widgetMethods.UnregisterEvent(self, event) self.__events[event] = nil end
function widgetMethods.RegisterForDrag(self) end
function widgetMethods.RegisterForClicks(self) end
function widgetMethods.SetMovable(self) end
function widgetMethods.SetClampedToScreen(self) end
function widgetMethods.EnableMouse(self) end
function widgetMethods.SetFrameStrata(self, s) self.__strata = s end
function widgetMethods.SetFrameLevel(self, l) self.__level = l end
function widgetMethods.GetFrameLevel(self) return self.__level or 1 end
function widgetMethods.SetAlpha(self, a) self.__alpha = a end
function widgetMethods.GetAlpha(self) return self.__alpha or 1 end
function widgetMethods.SetScale(self, s) self.__scale = s end
function widgetMethods.GetScale(self) return self.__scale or 1 end
function widgetMethods.StartMoving(self) self.__moving = true end
function widgetMethods.StopMovingOrSizing(self) self.__moving = false end
function widgetMethods.SetBackdrop(self, b) self.__backdrop = b end
function widgetMethods.SetBackdropColor(self) end
function widgetMethods.SetBackdropBorderColor(self) end
function widgetMethods.GetParent(self) return self.__parent end
function widgetMethods.GetName(self) return self.__name end
function widgetMethods.GetObjectType(self) return self.__kind end
function widgetMethods.SetText(self, text) self.__text = text end
function widgetMethods.GetText(self) return self.__text end
function widgetMethods.SetFormattedText(self, fmt, ...) self.__text = string.format(fmt, ...) end
function widgetMethods.SetTextColor(self) end
function widgetMethods.SetJustifyH(self) end
function widgetMethods.SetJustifyV(self) end
function widgetMethods.SetWordWrap(self) end
function widgetMethods.SetFont(self) end
function widgetMethods.GetFont(self) return "font", 12, "" end
function widgetMethods.GetStringWidth(self) return #(tostring(self.__text or "")) * 6 end
function widgetMethods.SetNormalFontObject(self) end
function widgetMethods.GetFontString(self) return self.__fontString end
function widgetMethods.SetHighlightTexture(self) end
function widgetMethods.SetNormalTexture(self) end
function widgetMethods.SetTexture(self, t) self.__texture = t end
function widgetMethods.SetColorTexture(self) end
function widgetMethods.SetVertexColor(self) end
function widgetMethods.SetAllPoints(self) end
function widgetMethods.SetTexCoord(self) end
function widgetMethods.SetDesaturated(self) end
function widgetMethods.Enable(self) self.__enabled = true end
function widgetMethods.Disable(self) self.__enabled = false end
function widgetMethods.SetEnabled(self, on) self.__enabled = on and true or false end
function widgetMethods.IsEnabled(self) return self.__enabled ~= false end
function widgetMethods.SetAttribute(self, k, v) self.__attributes[k] = v end
function widgetMethods.EnableKeyboard(self, on) self.__keyboard = on and true or false end
function widgetMethods.SetPropagateKeyboardInput(self, on) self.__propagate = on and true or false end
function widgetMethods.GetPropagateKeyboardInput(self) return self.__propagate or false end
function widgetMethods.GetAttribute(self, k) return self.__attributes[k] end
function widgetMethods.SetOwner(self, owner) self.__owner = owner; self.__lines = {} end
function widgetMethods.AddLine(self, text) self.__lines[#self.__lines + 1] = text end
function widgetMethods.AddDoubleLine(self, a, b) self.__lines[#self.__lines + 1] = tostring(a) .. " " .. tostring(b) end
function widgetMethods.ClearLines(self) self.__lines = {} end
function widgetMethods.SetItemByID(self, id) self.__text = "item " .. tostring(id) end
function widgetMethods.Click(self, button)
    local script = self.__scripts.OnClick
    if script and self.__enabled ~= false then
        script(self, button or "LeftButton")
    end
end

local function newWidget(kind, name, parent)
    local w = { __kind = kind, __name = name, __parent = parent, __points = {}, __scripts = {}, __events = {}, __attributes = {},
        __shown = true, __children = {}, __lines = {} }
    for method, fn in pairs(widgetMethods) do
        w[method] = fn
    end
    function w.CreateFontString(self, fsName, layer, template)
        local fs = newWidget("FontString", fsName, self)
        return fs
    end
    function w.CreateTexture(self, tName)
        return newWidget("Texture", tName, self)
    end
    if parent then
        parent.__children[#parent.__children + 1] = w
    end
    return w
end

------------------------------------------------------------------------
-- The world of the mock: zones with yards, continents, instances
------------------------------------------------------------------------
-- uiMapID -> map; x0/y0/w/h: the zone's place and size in the continent's yards
local MAPS = {
    [947] = { name = "Azeroth", mapType = 1 },
    [1415] = { name = "Eastern Kingdoms", mapType = 2, parent = 947, continent = 0 },
    [1414] = { name = "Kalimdor", mapType = 2, parent = 947, continent = 1 },
    [1436] = { name = "Westfall", mapType = 3, parent = 1415, continent = 0, x0 = 10000, y0 = 2000, w = 3500, h = 2333 },
    [1429] = { name = "Elwynn Forest", mapType = 3, parent = 1415, continent = 0, x0 = 10000, y0 = -500, w = 3470, h = 2314 },
    [1453] = { name = "Stormwind City", mapType = 3, parent = 1415, continent = 0, x0 = 10500, y0 = -1200, w = 1737, h = 1158 },
    [1421] = { name = "Silverpine Forest", mapType = 3, parent = 1415, continent = 0, x0 = 2000, y0 = 1000, w = 4200, h = 2800 },
    [1437] = { name = "Wetlands", mapType = 3, parent = 1415, continent = 0, x0 = 5000, y0 = 3000, w = 4135, h = 2756 },
    [1413] = { name = "The Barrens", mapType = 3, parent = 1414, continent = 1, x0 = 0, y0 = 0, w = 10133, h = 6756 },
    [1454] = { name = "Orgrimmar", mapType = 3, parent = 1414, continent = 1, x0 = 1000, y0 = -3000, w = 1402, h = 935 },
    [1426] = { name = "Dun Morogh", mapType = 3, parent = 1415, continent = 0, x0 = 8000, y0 = 1000, w = 4900, h = 3270 },
}
local INSTANCE_MAPS = {} -- instanceID -> a dungeon map of its own

local function mapByName(name)
    for id, map in pairs(MAPS) do
        if map.name == name then
            return id, map
        end
    end
    error("the mock has no zone called " .. tostring(name))
end
Mock.mapID = function(name) return (mapByName(name)) end

------------------------------------------------------------------------
-- Install: a fresh client with the addon loaded
------------------------------------------------------------------------
local state
Mock.state = nil

function Mock.install(options)
    options = options or {}
    for _, name in ipairs(Mock.globalNames or {}) do
        G[name] = nil
    end
    Mock.globalNames = {}
    Mock.now = 1000
    Mock.clock = 1760000000 -- time() of the login
    Mock.timers = {}
    Mock.frames = {}
    Mock.printed = {}
    Mock.errors = {}
    Mock.forbidden = 0
    Mock.hardware = false
    Mock.sent = {}        -- addon messages sent: { prefix, text, chatType, target }
    Mock.invites = {}
    Mock.whoQueries = {}
    Mock.whoToUi = false
    Mock.chatFilters = {}   -- CHAT_MSG_SYSTEM filters the addon installed
    Mock.chatLines = {}     -- system lines that reached the chat (not swallowed)
    Mock.finderOpenedByWho = 0
    state = {
        playerName = options.playerName or "Purrdee", surname = "Bubson", realm = "TestRealm", class = options.class or "SHAMAN", level = options.level or 22,
        inCombat = false,
        world = { uiMap = 1436, zone = "Westfall", subzone = "", x = 0.5, y = 0.5, inInstance = false, noPosition = false },
        channels = {},
        pins = options.pins or {},
        secretApis = {},
    }
    Mock.state = state

    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
    end
    G.issecretvalue = function(value) return value == SECRET end
    G.geterrorhandler = function()
        return function(err)
            Mock.errors[#Mock.errors + 1] = tostring(err)
        end
    end
    G.GetTime = function() return Mock.now end
    G.time = function() return Mock.clock + (Mock.now - 1000) end
    G.InCombatLockdown = function() return state.inCombat end
    G.UIParent = newWidget("Frame", "UIParent")
    G.GameTooltip = newWidget("GameTooltip", "GameTooltip")
    G.RAID_CLASS_COLORS = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" }, MAGE = { r = 0.41, g = 0.8, b = 0.94, colorStr = "ff69ccf0" },
        SHAMAN = { r = 0, g = 0.44, b = 0.87, colorStr = "ff0070de" }, ROGUE = { r = 1, g = 0.96, b = 0.41, colorStr = "fffff569" },
    }
    G.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
    G.BackdropTemplateMixin = {}
    G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }

    G.CreateFrame = function(kind, name, parent, template)
        local w = newWidget(kind, name, parent or G.UIParent)
        if kind == "Button" then
            w.__fontString = newWidget("FontString", nil, w)
            w.SetText = function(self, text) self.__text = text; self.__fontString.__text = text end
        end
        if name then
            G[name] = w
            Mock.globalNames[#Mock.globalNames + 1] = name
        end
        Mock.frames[#Mock.frames + 1] = w
        return w
    end
    G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

    G.C_Timer = {
        After = function(delay, fn) Mock.timers[#Mock.timers + 1] = { at = Mock.now + delay, fn = fn } end,
        NewTicker = function(interval, fn)
            local ticker = { at = Mock.now + interval, fn = fn, interval = interval }
            ticker.Cancel = function() ticker.cancelled = true end
            Mock.timers[#Mock.timers + 1] = ticker
            return ticker
        end,
    }

    -- who you are
    G.UnitName = function(unit) if unit == "player" then return state.playerName, state.surname end end
    G.GetUnitName = function(unit, full) if unit == "player" then return full and (state.playerName .. " " .. state.surname) or state.playerName end end
    G.GetRealmName = function() return state.realm end
    G.UnitClass = function(unit) if unit == "player" then return "Shaman", state.class end end
    G.UnitLevel = function(unit) if unit == "player" then return state.level end end

    -- where you are
    G.IsInInstance = function()
        if state.world.inInstance then return true, "party" end
        return false, "none"
    end
    G.GetInstanceInfo = function()
        if state.world.inInstance then
            return state.world.instanceName, "party", 1, "Normal", 5, 0, false, state.world.instanceID, 5
        end
        return state.world.zone, "none", 0, "", 0, 0, false, 0, 0
    end
    G.GetRealZoneText = function() return state.world.inInstance and state.world.instanceName or state.world.zone end
    G.GetSubZoneText = function() return state.world.subzone end
    G.C_Map = {
        GetBestMapForUnit = function(unit)
            if unit ~= "player" then return nil end
            return state.world.uiMap
        end,
        GetMapInfo = function(uiMapID)
            local map = MAPS[uiMapID] or INSTANCE_MAPS[uiMapID]
            if not map then return nil end
            return { mapID = uiMapID, name = map.name, mapType = map.mapType, parentMapID = map.parent or 0 }
        end,
        GetMapChildrenInfo = function(uiMapID, mapType, allDescendants)
            local list = {}
            local function collect(parent)
                for id, map in pairs(MAPS) do
                    if map.parent == parent and (mapType == nil or map.mapType == mapType) then
                        list[#list + 1] = { mapID = id, name = map.name, mapType = map.mapType, parentMapID = parent }
                    end
                    if map.parent == parent and allDescendants then
                        collect(id)
                    end
                end
            end
            collect(uiMapID)
            return list
        end,
        GetPlayerMapPosition = function(uiMapID, unit)
            if unit ~= "player" or state.world.inInstance or state.world.noPosition or uiMapID ~= state.world.uiMap then return nil end
            return G.CreateVector2D(state.world.x, state.world.y)
        end,
        GetWorldPosFromMapPos = function(uiMapID, pos)
            local map = MAPS[uiMapID]
            if not map or not map.w then return nil end
            return map.continent, G.CreateVector2D(map.x0 + pos.x * map.w, map.y0 + pos.y * map.h)
        end,
    }
    G.C_EncounterJournal = {
        GetDungeonEntrancesForMap = function(uiMapID)
            local map = MAPS[uiMapID]
            local pins = map and state.pins[map.name] or {}
            local list = {}
            for _, pin in ipairs(pins) do
                list[#list + 1] = { name = pin.name, position = G.CreateVector2D(pin.x, pin.y), areaPoiID = 1, description = "", atlasName = "", journalInstanceID = 0 }
            end
            return list
        end,
    }

    -- the channel and the addon messages
    G.JoinTemporaryChannel = function(name)
        for _, channel in ipairs(state.channels) do
            if channel == name then return 0 end
        end
        state.channels[#state.channels + 1] = name
        C_Timer.After(0.3, function()
            Mock.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", #state.channels + 1 .. ". " .. name, "", "", 0, #state.channels + 1, name)
        end)
        return 0
    end
    G.GetChannelName = function(name)
        for index, channel in ipairs(state.channels) do
            if channel == name then return index + 1, channel, 0, false end
        end
        return 0
    end
    G.LeaveChannelByName = function(name)
        for index, channel in ipairs(state.channels) do
            if channel == name then table.remove(state.channels, index) end
        end
    end
    G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, text, chatType, target)
            Mock.sent[#Mock.sent + 1] = { prefix = prefix, text = text, chatType = chatType, target = target }
            -- the channel echoes your own message back after a moment
            C_Timer.After(1, function()
                Mock.fire("CHAT_MSG_ADDON", prefix, text, chatType, state.playerName .. " " .. state.surname, target, 0, tonumber(target) or 0, "AKLFGRadar", 0)
            end)
            return 0
        end,
    }

    G.C_PartyInfo = { InviteUnit = function(name) Mock.invites[#Mock.invites + 1] = name end }
    G.ChatFrame_AddMessageEventFilter = function(event, fn)
        if event == "CHAT_MSG_SYSTEM" then Mock.chatFilters[#Mock.chatFilters + 1] = fn end
    end
    G.WHO_NUM_RESULTS = "%d |4player:players; total"

    -- /who: a key press or a click, or the client's "blocked" popup; the answer comes with Mock.whoAnswer
    state.whoResults, state.whoTotal = {}, 0
    G.C_FriendList = {
        SendWho = function(filter)
            if not Mock.hardware then
                Mock.forbidden = Mock.forbidden + 1
                return
            end
            Mock.whoQueries[#Mock.whoQueries + 1] = filter
        end,
        SetWhoToUi = function(on) Mock.whoToUi = on and true or false end,
        GetNumWhoResults = function() return #state.whoResults, state.whoTotal end,
        GetWhoInfo = function(index)
            local who = state.whoResults[index]
            if not who then return nil end
            return { fullName = who[1], level = who[2], classStr = who[3], filename = who[3], area = who[4], fullGuildName = "", raceStr = "", gender = 0 }
        end,
    }

    -- the group finder: activities tied to instances, a search (a key press, like /who), its results with the
    -- leader's roles and area, your own listing
    state.lfg = {
        activities = {
            -- minLevel is the REQUIRED level, the suggestion the range the finder shows and filters by
            [1001] = { fullName = "Deadmines", shortName = "DM", categoryID = 2, mapID = 36, minLevel = 10, minLevelSuggestion = 15, maxLevelSuggestion = 22, maxNumPlayers = 5 },
            [1002] = { fullName = "Shadowfang Keep", shortName = "SFK", categoryID = 2, mapID = 33, minLevel = 14, minLevelSuggestion = 20, maxLevelSuggestion = 26, maxNumPlayers = 5 },
            [1003] = { fullName = "Wailing Caverns", shortName = "WC", categoryID = 2, mapID = 43, minLevel = 10, minLevelSuggestion = 17, maxLevelSuggestion = 24, maxNumPlayers = 5 },
            [1101] = { fullName = "Molten Core", shortName = "MC", categoryID = 114, mapID = 409, minLevel = 60, minLevelSuggestion = 60, maxLevelSuggestion = 60, maxNumPlayers = 40 },
            -- wings: one instance map id, several activities
            [1004] = { fullName = "Scarlet Monastery - Graveyard", shortName = "SM GY", categoryID = 2, mapID = 189, minLevel = 20, minLevelSuggestion = 30, maxLevelSuggestion = 38, maxNumPlayers = 5 },
            [1005] = { fullName = "Scarlet Monastery - Library", shortName = "SM Lib", categoryID = 2, mapID = 189, minLevel = 20, minLevelSuggestion = 33, maxLevelSuggestion = 41, maxNumPlayers = 5 },
            [1006] = { fullName = "Scarlet Monastery - Armory", shortName = "SM Arm", categoryID = 2, mapID = 189, minLevel = 20, minLevelSuggestion = 36, maxLevelSuggestion = 44, maxNumPlayers = 5 },
            [1007] = { fullName = "Scarlet Monastery - Cathedral", shortName = "SM Cath", categoryID = 2, mapID = 189, minLevel = 20, minLevelSuggestion = 38, maxLevelSuggestion = 46, maxNumPlayers = 5 },
            [1008] = { fullName = "Lower Blackrock Spire", shortName = "LBRS", categoryID = 2, mapID = 229, minLevel = 44, minLevelSuggestion = 57, maxLevelSuggestion = 60, maxNumPlayers = 5 },
            [1009] = { fullName = "Upper Blackrock Spire", shortName = "UBRS", categoryID = 2, mapID = 229, minLevel = 48, minLevelSuggestion = 60, maxLevelSuggestion = 60, maxNumPlayers = 5 },
            -- Forever's own: no required level at all, only the suggestion; one name the table spells differently
            [1201] = { fullName = "The Hall of Thanes", shortName = "HoT", categoryID = 2, mapID = 3001, minLevel = 0, minLevelSuggestion = 13, maxLevelSuggestion = 18, maxNumPlayers = 5 },
            [1202] = { fullName = "Alcaz Prison", shortName = "AP", categoryID = 2, mapID = 3003, minLevel = 0, minLevelSuggestion = 48, maxLevelSuggestion = 53, maxNumPlayers = 5 },
            [1301] = { fullName = "Karazhan Crypts", shortName = "KC", categoryID = 114, mapID = 3002, minLevel = 0, minLevelSuggestion = 60, maxLevelSuggestion = 60, maxNumPlayers = 10 },
        },
        results = {}, activeEntry = nil,
    }
    Mock.lfgSearches = {}
    -- the playstyle every listing is posted with, worded by the client (Blizzard_LFGUtil's helper)
    G.Enum.LFGEntryGeneralPlaystyle = { None = 0, Learning = 1, FunRelaxed = 2, FunSerious = 3, Expert = 4 }
    G.GetGeneralPlaystyleString = function(value) return ({ "Learning", "Relaxed", "Serious", "Expert" })[value] or "" end
    -- every activity of a category, as the finder's own search takes when nothing is selected
    G.LFGUtil_GetFilteredActivities = function(categoryID)
        local ids = {}
        for id, activity in pairs(state.lfg.activities) do
            if activity.categoryID == categoryID then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        return ids
    end
    G.C_LFGList = {
        GetAvailableCategories = function() return { 2, 114 } end,
        GetLfgCategoryInfo = function(id) return (id == 2 or id == 114) and { name = id == 2 and "Dungeons" or "Raids" } or nil end,
        GetAvailableActivities = function(categoryID)
            local ids = {}
            for id, activity in pairs(state.lfg.activities) do
                if activity.categoryID == categoryID then ids[#ids + 1] = id end
            end
            table.sort(ids)
            return ids
        end,
        GetActivityInfoTable = function(id) return state.lfg.activities[id] end,
        GetSearchResults = function()
            local ids = {}
            for _, result in ipairs(state.lfg.results) do ids[#ids + 1] = result.id end
            return #ids, ids
        end,
        GetSearchResultInfo = function(id)
            for _, result in ipairs(state.lfg.results) do
                if result.id == id then
                    local size = type(result.members) == "table" and (#result.members + 1) or result.members or 1
                    return { searchResultID = id, leaderName = result.leader, activityIDs = { result.activity }, numMembers = size,
                        isDelisted = result.delisted or false, age = 0, hasSelf = false, name = "", comment = "", generalPlaystyle = result.playstyle }
                end
            end
        end,
        GetSearchResultLeaderInfo = function(id)
            for _, result in ipairs(state.lfg.results) do
                if result.id == id then
                    local roles = result.roles or ""
                    return { name = result.leader, level = result.level, areaName = result.area, className = result.class, classFilename = result.class,
                        assignedRole = "NONE", isLeader = true,
                        lfgRoles = { tank = roles:find("T", 1, true) ~= nil, healer = roles:find("H", 1, true) ~= nil, dps = roles:find("D", 1, true) ~= nil } }
                end
            end
        end,
        -- member 1 is the leader; a group's others come from result.members = { { name, level, class, roles, area } ... }
        GetSearchResultPlayerInfo = function(id, index)
            for _, result in ipairs(state.lfg.results) do
                if result.id == id then
                    local person
                    if index == 1 then
                        person = { name = result.leader, level = result.level, class = result.class, roles = result.roles or "", area = result.area, isLeader = true }
                    else
                        person = result.members and result.members[index - 1]
                    end
                    if not person then return nil end
                    local roles = person.roles or ""
                    return { name = person.name, level = person.level, areaName = person.area, className = person.class, classFilename = person.class,
                        assignedRole = "NONE", isLeader = person.isLeader or false,
                        lfgRoles = { tank = roles:find("T", 1, true) ~= nil, healer = roles:find("H", 1, true) ~= nil, dps = roles:find("D", 1, true) ~= nil } }
                end
            end
        end,
        GetSearchResultMemberCounts = function() return {} end,
        HasActiveEntryInfo = function() return state.lfg.activeEntry ~= nil end,
        GetActiveEntryInfo = function() return state.lfg.activeEntry end,
        Search = function(categoryID, filter, preferredFilters, languageFilter, crossFaction, advancedFilter, activityIDs)
            if not Mock.hardware then
                Mock.forbidden = Mock.forbidden + 1
                return
            end
            Mock.lfgSearches[#Mock.lfgSearches + 1] = { categoryID = categoryID, activityIDs = activityIDs }
            C_Timer.After(0.5, function() Mock.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED") end)
        end,
    }

    G.SlashCmdList = {}

    -- load the addon in TOC order
    local ns = {}
    for _, file in ipairs({ "Core.lua", "Dungeons.lua", "Position.lua", "Net.lua", "LFG.lua", "Lookup.lua", "Panel.lua", "Diagnostics.lua" }) do
        local chunk, err = loadfile(file)
        if not chunk then
            error("cannot load " .. file .. ": " .. tostring(err))
        end
        chunk("AKForeverLFGRadar", ns)
    end
    if options.db then
        G.AKForeverLFGRadarDB = options.db
    else
        G.AKForeverLFGRadarDB = nil
    end
    Mock.ns = ns
    return ns, state
end

------------------------------------------------------------------------
-- Events, time, the player
------------------------------------------------------------------------
function Mock.fire(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

function Mock.login()
    Mock.fire("ADDON_LOADED", "AKForeverLFGRadar")
    Mock.fire("PLAYER_LOGIN")
    Mock.fire("PLAYER_ENTERING_WORLD", true, false)
    Mock.advance(0.2)
end

function Mock.advance(seconds)
    local target = Mock.now + seconds
    while true do
        local soonest, index
        for i, timer in ipairs(Mock.timers) do
            if not timer.cancelled and timer.at <= target and (not soonest or timer.at < soonest.at) then
                soonest, index = timer, i
            end
        end
        if not soonest then
            break
        end
        Mock.now = soonest.at
        if soonest.interval then
            soonest.at = soonest.at + soonest.interval
        else
            table.remove(Mock.timers, index)
        end
        soonest.fn()
    end
    Mock.now = target
end

function Mock.slash(text)
    Mock.hardware = true
    G.SlashCmdList.AKFOREVERLFGRADAR(text)
    Mock.hardware = false
end

function Mock.click(button, which)
    Mock.hardware = true
    button:Click(which)
    Mock.hardware = false
end

-- the answer to a who query: { { name, level, class, area } ... }. Asked to the UI, it comes as WHO_LIST_UPDATE
-- - and the finder's Who tab opens its window on that, every time. Otherwise it comes as system lines in the
-- chat, through the addon's filters; a line no filter swallows reaches the chat window.
function Mock.whoAnswer(list, total)
    state.whoResults = list
    state.whoTotal = total or #list
    if Mock.whoToUi then
        Mock.fire("WHO_LIST_UPDATE")
        Mock.finderOpenedByWho = Mock.finderOpenedByWho + 1
        if G.LFGParentFrame then G.LFGParentFrame:Show() end
        return
    end
    local function deliver(text)
        for _, filter in ipairs(Mock.chatFilters) do
            if filter(nil, "CHAT_MSG_SYSTEM", text) then return end
        end
        Mock.chatLines[#Mock.chatLines + 1] = text
    end
    for _, who in ipairs(list) do
        deliver("|Hplayer:" .. who[1] .. "|h[" .. who[1] .. "]|h: Level " .. who[2] .. " Human " .. who[3] .. " - " .. who[4])
    end
    deliver(#list .. " players total")
end

-- a key going down: every frame that hears the keyboard gets it, as a key press the client counts
function Mock.keyPress(key)
    Mock.hardware = true
    for _, frame in ipairs(Mock.frames) do
        if frame.__keyboard and frame.__scripts.OnKeyDown then
            frame.__scripts.OnKeyDown(frame, key)
        end
    end
    Mock.hardware = false
end

function Mock.moveTo(zoneName, x, y)
    local id, map = mapByName(zoneName)
    state.world = { uiMap = id, zone = map.name, subzone = "", x = x, y = y, inInstance = false, noPosition = state.world.noPosition }
    Mock.fire("ZONE_CHANGED_NEW_AREA")
end

function Mock.enterInstance(instanceID, name)
    INSTANCE_MAPS[2000 + instanceID] = { name = name, mapType = 4 }
    state.world = { uiMap = 2000 + instanceID, zone = name, subzone = "", inInstance = true, instanceID = instanceID, instanceName = name }
    Mock.fire("PLAYER_ENTERING_WORLD", false, false)
end

-- an addon message from somebody else on the channel
function Mock.peerMessage(sender, text)
    Mock.fire("CHAT_MSG_ADDON", "AKLR", text, "CHANNEL", sender, "6", 0, 6, "AKLFGRadar", 0)
end

-- a peer's position: { dungeon, uiMap (zone name), x, y, inside (instance id), instanceName, class, level, zone }
function Mock.peerPosition(sender, p)
    local fields
    if p.inside then
        fields = { "P", "1", p.dungeon or "-", "I", 2000 + p.inside, "", "", "", "", "", p.instanceName or "", p.level or "", p.class or "", tostring(p.inside) }
    else
        local id, map = mapByName(p.uiMap)
        local wx, wy = map.x0 + p.x * map.w, map.y0 + p.y * map.h
        fields = { "P", "1", p.dungeon or "-", "O", id, string.format("%.4f", p.x), string.format("%.4f", p.y), map.continent,
            string.format("%.0f", wx), string.format("%.0f", wy), map.name, p.level or "", p.class or "", "" }
    end
    Mock.peerMessage(sender, table.concat(fields, "|"))
end

-- the finder's results: { { id, leader, activity, roles = "THD", class, level, area, members } ... }
function Mock.lfgResults(list)
    state.lfg.results = list
    Mock.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
end

-- the finder window, open on the Browse tab with these activities in its filter
Mock.finderRefreshes = 0
function Mock.openLFG(activityIDs)
    if not G.LFGParentFrame then
        local parent = G.CreateFrame("Frame", "LFGParentFrame", G.UIParent)
        parent:SetSize(458, 535)
        local tab = G.CreateFrame("Frame", nil, parent) -- the side tabs hanging off the right edge: wide on this flavour
        tab:SetSize(60, 60)
        parent.ListingTab = tab
        local browse = G.CreateFrame("Frame", "LFGBrowseFrame", parent)
        browse.ActivityDropdown = { selectedValues = {} }
        browse.CategoryDropdown = { selectedCategoryID = 2 } -- (LFGBrowseCategoryDropdownMixin:GetValue reads this field)
        browse.searching = false
        -- the finder's own way of showing a search for given activities (LFGBrowseMixin:SetSelectedSearchActivities,
        -- forever branch): the dropdown set, then its own search - C_LFGList.Search, hardware-gated
        Mock.browseSelections = {}
        function browse:SetSelectedSearchActivities(activityIDs)
            local values = {}
            for index, id in ipairs(activityIDs or {}) do
                values[index] = id
            end
            self.ActivityDropdown.selectedValues = values
            Mock.browseSelections[#Mock.browseSelections + 1] = values
            if not self.searching then
                G.C_LFGList.Search(2, 0, 0, nil, false, nil, values)
            end
        end
        -- the finder's own refresh button: a click searches again with the filter as it stands
        local refresh = G.CreateFrame("Button", nil, browse)
        refresh:SetScript("OnClick", function()
            Mock.finderRefreshes = Mock.finderRefreshes + 1
            G.C_LFGList.Search(2, 0, 0, nil, false, nil, browse.ActivityDropdown.selectedValues)
        end)
        browse.RefreshButton = refresh
    end
    G.LFGBrowseFrame.ActivityDropdown.selectedValues = activityIDs or {}
    G.LFGParentFrame:Show()
    G.LFGBrowseFrame:Show()
end

function Mock.closeLFG()
    if G.LFGParentFrame then
        G.LFGParentFrame:Hide()
        G.LFGBrowseFrame:Hide()
    end
end

-- you list yourself for an activity (nil: the listing is taken down)
function Mock.listSelf(activityID, playstyle)
    state.lfg.activeEntry = activityID and { activityIDs = { activityID }, requiredItemLevel = 0, requiredHonorLevel = 0, name = "", comment = "", generalPlaystyle = playstyle } or nil
    Mock.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
end


return Mock
